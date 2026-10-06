/*
Package app is the file browser's host. It decodes the ui's commands into
files.Commands, gathers the facts each needs, has examples/files/logic
plan it, and carries the plan out (desk.odin). It reads folders and makes
thumbnails for the ui's needs on four worker threads, copies on a thread
of its own, and keeps pins, recent places and the undo journal in SQLite
on another, as examples/todo keeps its todos.

	needs (listing, places) ─┐
	needs (thumb) ─ debounce_by(key, 60 ms) ─┤─ async_map(fs, 4 workers) ─ deliver
	relists (watcher, desk) ─┘

	commands ───────────────────────────────┐
	copy events (copier thread) ────────────┤
	needs (recent, pins, activity) ─┐       ├─ desk (pinned) ─ deliver
	changes ─ debounce ─ route(live) ─ reads ┘

	interval(500 ms) ─ poll: folders shown whose time changed are read again

A folder is read as soon as it is needed, and again whenever it changes:
the desk relists the folders its own changes touched at once, and the
watcher polls the time of each folder shown, so a change another
application makes shows within half a second. A thumbnail waits a short
quiet first, so a row that scrolls past never starts one, and one whose
need goes while its job runs is cancelled where the work next checks.
Thumbnails go under the temp directory, a folder per run.
*/
package files_app

import "core:encoding/cbor"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "jm:stream"
import "jm:ui"

import "../../common"
import "../files"
import "../fs"
import "../query"
import "../store"

QUIET   :: 60 * time.Millisecond
SETTLE  :: 10 * time.Millisecond // commits coalesced before the sidebar re-queries
POLL    :: 500 * time.Millisecond // how often the folders shown are checked for change
WORKERS :: 4

Kind :: enum u8 {
	Listing,
	Thumb,
	Open,
	Places,
}

// Need_Event is a need the desk answers appearing or going.
Need_Event :: struct {
	added: bool,
	key:   ui.Need_Key,
	kind:  Read_Kind,
}

Route_In :: union {
	Need_Event,
	store.Change_Batch,
}

// Route keeps the desk's needs that are live, so a change re-reads each.
Route :: struct {
	live: map[ui.Need_Key]Read_Kind,
	out:  [dynamic]Desk_In,
}

// Shown_Folder is a folder shown, and the time it had when it was last read.
Shown_Folder :: struct {
	path:     [common.MAX_PATH]u8,
	path_len: int,
	modified: i64, // 0 until a read has finished
}

// Job is one piece of work: what, on which path, and a cancel flag the
// main thread sets.
Job :: struct {
	cancel:   bool, // atomic
	kind:     Kind,
	key:      ui.Need_Key,
	path:     [common.MAX_PATH]u8,
	path_len: int,
	px:       int,
	dst:      [common.MAX_PATH]u8, // a thumbnail's file
	dst_len:  int,
}

Request :: struct {
	key: ui.Need_Key,
	job: ^Job,
}

// Done is a job's end: its result bytes for a listing, in the host's
// allocator, with the folder's time when it was read; a thumbnail written
// or not; an open attempted.
Done :: struct {
	job:       ^Job,
	cancelled: bool,
	ok:        bool,
	data:      []byte,
	modified:  i64,
}

Host :: struct {
	p:           ^stream.Pipeline,
	direct:      stream.Port(Request), // listings, places and opens, at once
	thumbs:      stream.Port(Request), // thumbnails, after a quiet
	need_db:     stream.Port(Need_Event), // needs the desk answers
	commands:    stream.Port(files.Command),
	copy_events: stream.Port(Copy_Event),
	inbox:       ui.Inbox,
	workers:     ^stream.Workers,
	copiers:     ^stream.Workers, // one thread: copies run one at a time
	jobs:        map[ui.Need_Key]^Job, // under mutex
	listings:    map[ui.Need_Key]Shown_Folder, // the folders shown, under mutex
	mutex:       sync.Mutex,
	dir:         string,
	home:        string,
	place_paths: []string, // the standard folders, which protection guards
	stats:       query.Stats_Result,
	pool:        ^thread.Thread,
	wake:        proc(),
	allocator:   mem.Allocator,
	// The desk and its thread: the pinned stage, woken by the pipeline.
	desk:        Desk,
	route:       Route,
	db:          common.DB_Thread,
	sink:        common.Sink,
}

// init opens the store at db_path (the default under the state folder,
// or sqlite3.MEMORY for a test), makes a folder for this run's
// thumbnails, builds the pipeline and starts the threads.
init :: proc(h: ^Host, wake: proc() = nil, db_path := "") -> bool {
	h.wake = wake
	h.allocator = context.allocator
	home, herr := os.user_home_dir(h.allocator)
	if herr != nil {
		fmt.eprintln("files: no home folder:", herr)
		return false
	}
	h.home = home
	db := db_path
	if db == "" {
		state, _ := filepath.join({home, ".local", "state", "jm-files"}, context.temp_allocator)
		_ = os.make_directory_all(state)
		db, _ = filepath.join({state, "files.db"}, context.temp_allocator)
	}
	if !store.open(&h.desk.store, db, common.db_on_changes, &h.db, h.allocator) {
		return false
	}
	h.desk.h = h
	h.desk.allocator = h.allocator
	h.desk.out = make([dynamic]common.Result, h.allocator)
	standard := places(home, context.temp_allocator)
	h.place_paths = make([]string, len(standard) - 1, h.allocator)
	for pl, ii in standard[1:] {
		h.place_paths[ii] = strings.clone(pl.path, h.allocator)
	}
	h.sink = {&h.inbox, wake, h.allocator}
	h.route.live = make(map[ui.Need_Key]Read_Kind, h.allocator)
	h.route.out = make([dynamic]Desk_In, h.allocator)
	tmp, err := os.temp_directory(context.temp_allocator)
	if err != nil {
		fmt.eprintln("files: no temp directory:", err)
		return false
	}
	run := fmt.tprintf("jm-files-%d", time.now()._nsec / 1_000_000)
	dir, _ := filepath.join({tmp, run}, h.allocator)
	if merr := os.make_directory(dir); merr != nil && !os.exists(dir) {
		fmt.eprintln("files: make directory:", dir, merr)
		return false
	}
	h.dir = dir
	ui.inbox_init(&h.inbox, h.allocator)
	h.jobs = make(map[ui.Need_Key]^Job, h.allocator)
	h.listings = make(map[ui.Need_Key]Shown_Folder, h.allocator)
	h.workers = stream.workers_start(WORKERS, h.allocator)
	h.copiers = stream.workers_start(1, h.allocator)

	p := stream.make_pipeline(h.allocator, cap = 64)
	h.p = p
	direct, thumbs: stream.Stream(Request)
	direct, h.direct = stream.port(p, Request, cap = 256, name = "direct")
	thumbs, h.thumbs = stream.port(p, Request, cap = 256, name = "thumbs")
	settled := stream.debounce_by(thumbs, QUIET, request_key, name = "quiet")
	work := stream.merge([]stream.Stream(Request){direct, settled}, name = "work")
	done := stream.async_map(
		work,
		h.workers,
		h,
		run_job,
		concurrency = WORKERS,
		ordered = false,
		name = "fs",
	)
	stream.for_each_with(done, h, deliver, name = "deliver")
	stream.for_each_with(stream.interval(p, POLL, name = "watch"), h, poll, name = "poll")

	// The desk's half: commands, copies' events and routed reads into the
	// pinned stage.
	changes := common.db_thread_open(&h.db, p)
	need_db: stream.Stream(Need_Event)
	commands: stream.Stream(files.Command)
	copy_events: stream.Stream(Copy_Event)
	need_db, h.need_db = stream.port(p, Need_Event, name = "desk needs")
	commands, h.commands = stream.port(p, files.Command, name = "commands")
	copy_events, h.copy_events = stream.port(p, Copy_Event, cap = 256, name = "copy events")
	committed := stream.debounce(changes, SETTLE)
	routed := stream.merge(
		[]stream.Stream(Route_In) {
			stream.transform(need_db, need_in),
			stream.transform(committed, change_in),
		},
		name = "route in",
	)
	reads := stream.flat_map_with(routed, &h.route, route, name = "route")
	inputs := stream.merge(
		[]stream.Stream(Desk_In) {
			stream.transform(commands, command_in),
			stream.transform(copy_events, copy_event_in),
			reads,
		},
		name = "desk in",
	)
	results := stream.flat_map_with(inputs, &h.desk, desk_apply, name = "desk")
	stream.pin(p, results.node)
	stream.for_each_with(results, &h.sink, common.deliver, name = "deliver desk")

	common.db_thread_start(&h.db)
	h.pool = thread.create_and_start_with_poly_data(h, pool_main)
	return true
}

data_host :: proc(h: ^Host) -> ui.Data_Host {
	return {user = h, on_need = on_need, on_command = on_command, inbox = &h.inbox}
}

stop :: proc(h: ^Host) {
	sync.mutex_lock(&h.mutex)
	for _, job in h.jobs {
		sync.atomic_store(&job.cancel, true)
	}
	sync.mutex_unlock(&h.mutex)
	stream.stop(h.p)
	thread.join(h.pool)
	thread.destroy(h.pool)
	common.db_thread_stop(&h.db)
	// The desk's thread is gone, so its copies are the main thread's to
	// stop: each sees its cancel where it next checks.
	for &op in h.desk.ops[:h.desk.op_n] {
		if op.copy != nil {
			sync.atomic_store(&op.copy.cancel, true)
		}
	}
	stream.workers_stop(h.copiers)
	stream.workers_stop(h.workers)
	stream.destroy(h.p)
	store.close(&h.desk.store)
	for &op in h.desk.ops[:h.desk.op_n] {
		if op.copy != nil {
			free(op.copy, h.allocator)
		}
	}
	delete(h.desk.out)
	for _, job in h.jobs {
		free(job, h.allocator)
	}
	delete(h.jobs)
	delete(h.listings)
	for p in h.place_paths {
		delete(p, h.allocator)
	}
	delete(h.place_paths, h.allocator)
	delete(h.route.live)
	delete(h.route.out)
	ui.inbox_destroy(&h.inbox)
	delete(h.dir, h.allocator)
	delete(h.home, h.allocator)
}

// --- the main thread -------------------------------------------------------

on_need :: proc(user: rawptr, need: ui.Need, added: bool) {
	h := (^Host)(user)
	// The sidebar's lists and the activity are the desk's to answer.
	kind: Maybe(Read_Kind)
	switch {
	case ui.need_is(need, query.Recent_Places):
		kind = .Recent
	case ui.need_is(need, query.Pins):
		kind = .Pins
	case ui.need_is(need, query.Activity):
		kind = .Activity
	}
	if k, desk := kind.?; desk {
		sync.mutex_lock(&h.mutex)
		h.stats.open += 1 if added else -1
		sync.mutex_unlock(&h.mutex)
		stream.port_send(h.need_db, Need_Event{added, need.key, k})
		return
	}
	job := new(Job, h.allocator)
	job.key = need.key
	if q, ok := ui.need_as(need, query.Listing); ok {
		job.kind = .Listing
		job.path_len = copy(job.path[:], q.path)
	} else if ui.need_is(need, query.Places) {
		job.kind = .Places
	} else if tq, is := ui.need_as(need, query.Thumb); is {
		job.kind = .Thumb
		job.px = tq.px
		job.path_len = copy(job.path[:], tq.path)
		job.dst_len = len(
			fmt.bprintf(
				job.dst[:],
				"%s%cthumb-%x-%d.bmp",
				h.dir,
				filepath.SEPARATOR,
				u64(need.key),
				tq.px,
			),
		)
	} else {
		free(job, h.allocator)
		return
	}
	sync.mutex_lock(&h.mutex)
	if !added {
		free(job, h.allocator)
		h.stats.open -= 1
		delete_key(&h.listings, need.key)
		if running, is_running := h.jobs[need.key]; is_running {
			sync.atomic_store(&running.cancel, true)
		}
		sync.mutex_unlock(&h.mutex)
		return
	}
	h.stats.open += 1
	if job.kind == .Listing {
		w := Shown_Folder {
			path_len = job.path_len,
		}
		w.path = job.path
		h.listings[need.key] = w
	}
	if running, is_running := h.jobs[need.key]; is_running && !sync.atomic_load(&running.cancel) {
		free(job, h.allocator)
		sync.mutex_unlock(&h.mutex)
		return
	}
	h.jobs[need.key] = job
	h.stats.pending += 1
	sync.mutex_unlock(&h.mutex)
	// Sent with the lock released: a full port waits on the pool.
	if job.kind == .Thumb {
		stream.port_send(h.thumbs, Request{need.key, job})
	} else {
		stream.port_send(h.direct, Request{need.key, job})
	}
}

// on_command decodes the ui's command; every one goes to the desk. A
// files.Command holds no pointers, so the decoded value is whole and
// crosses the port by copy.
on_command :: proc(user: rawptr, c: ui.Command) {
	h := (^Host)(user)
	if cmd, ok := ui.command_as(c, files.Command); ok {
		stream.port_send(h.commands, cmd)
	}
}

// --- the desk's route ---------------------------------------------------------

need_in :: proc(e: Need_Event) -> Route_In {
	return e
}

change_in :: proc(b: store.Change_Batch) -> Route_In {
	return b
}

command_in :: proc(c: files.Command) -> Desk_In {
	return c
}

copy_event_in :: proc(e: Copy_Event) -> Desk_In {
	return e
}

// route turns a need into its read and a change into a fresh read for
// each live Pins need. Recent is answered once, when its need appears: a
// snapshot, so the sidebar holds still while the folders visited are
// still being written down for the next time. The activity is answered
// when its need appears and sent again by the desk whenever it changes.
route :: proc(r: ^Route, v: Route_In) -> []Desk_In {
	clear(&r.out)
	switch e in v {
	case Need_Event:
		if e.added {
			r.live[e.key] = e.kind
			append(&r.out, Read{e.key, e.kind})
		} else {
			delete_key(&r.live, e.key)
		}
	case store.Change_Batch:
		for key, kind in r.live {
			if kind == .Pins {
				append(&r.out, Read{key, kind})
			}
		}
	}
	return r.out[:]
}

// --- folders that change ---------------------------------------------------------

// relist reads again every folder shown at path. Any thread may call
// it; it never waits, so a full queue drops the read and the next poll
// makes it.
relist :: proc(h: ^Host, path: string) {
	sync.mutex_guard(&h.mutex)
	for key, &w in h.listings {
		if string(w.path[:w.path_len]) == path {
			relist_locked(h, key, &w)
		}
	}
}

@(private)
relist_locked :: proc(h: ^Host, key: ui.Need_Key, w: ^Shown_Folder) {
	if running, is_running := h.jobs[key]; is_running && !sync.atomic_load(&running.cancel) {
		return // a read is on its way; the poll catches a change it missed
	}
	job := new(Job, h.allocator)
	job^ = {
		kind     = .Listing,
		key      = key,
		path     = w.path,
		path_len = w.path_len,
	}
	if !stream.port_push(h.direct, Request{key, job}) {
		free(job, h.allocator)
		return
	}
	h.jobs[key] = job
	h.stats.pending += 1
}

// poll checks the time of every folder shown against the time it had when
// last read, and reads again the ones that changed: a change another
// application made. It runs on a pool thread every POLL.
poll :: proc(h: ^Host, _: time.Duration) {
	Seen :: struct {
		key:      ui.Need_Key,
		path:     string,
		modified: i64,
	}
	// An arena of its own: the pool thread's temp allocator is shared by
	// whatever else runs there.
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, h.allocator, h.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&arena)
	seen := make([dynamic]Seen, context.temp_allocator)
	sync.mutex_lock(&h.mutex)
	for key, &w in h.listings {
		if w.modified != 0 {
			append(
				&seen,
				Seen {
					key,
					strings.clone(string(w.path[:w.path_len]), context.temp_allocator),
					w.modified,
				},
			)
		}
	}
	sync.mutex_unlock(&h.mutex)
	for s in seen {
		now := fs.modified(s.path)
		if now == s.modified {
			continue
		}
		sync.mutex_guard(&h.mutex)
		if w, live := &h.listings[s.key]; live && w.modified == s.modified {
			relist_locked(h, s.key, w)
		}
	}
}

// open_file asks the system to open path, on a worker: the opener takes
// a moment, which the desk's thread must not wait for.
open_file :: proc(h: ^Host, path: string) {
	job := new(Job, h.allocator)
	job.kind = .Open
	job.path_len = copy(job.path[:], path)
	if !stream.port_push(h.direct, Request{0, job}) {
		free(job, h.allocator)
	}
}

// --- the pipeline -----------------------------------------------------------

request_key :: proc(r: Request) -> ui.Need_Key {
	return r.key
}

// run_job runs on a worker, with its own arena for what the work
// allocates, so nothing a worker touches outlives the job.
run_job :: proc(h: ^Host, r: Request) -> Done {
	job := r.job
	if sync.atomic_load(&job.cancel) {
		return {job = job, cancelled = true}
	}
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena, h.allocator, h.allocator)
	defer mem.dynamic_arena_destroy(&arena)
	context.temp_allocator = mem.dynamic_arena_allocator(&arena)
	path := string(job.path[:job.path_len])
	switch job.kind {
	case .Listing:
		// The time first: a change made while the folder is read shows
		// as a later time at the next poll.
		modified := fs.modified(path)
		entries, error := fs.list(path, context.temp_allocator)
		data, err := cbor.marshal_into_bytes(
			query.Listing_Result{entries = entries, error = error},
			allocator = h.allocator,
			temp_allocator = context.temp_allocator,
		)
		return {job = job, ok = err == nil, data = data, modified = modified}
	case .Thumb:
		dst := string(job.dst[:job.dst_len])
		ok := fs.thumbnail(path, dst, job.px, &job.cancel)
		return {job = job, ok = ok, cancelled = !ok && sync.atomic_load(&job.cancel)}
	case .Open:
		return {job = job, ok = fs.open_default(path)}
	case .Places:
		data, err := cbor.marshal_into_bytes(
			query.Places_Result{items = places(h.home, context.temp_allocator)},
			allocator = h.allocator,
			temp_allocator = context.temp_allocator,
		)
		return {job = job, ok = err == nil, data = data}
	}
	return {job = job}
}

// places is the standard folders under home that exist, the home folder first.
places :: proc(home: string, allocator := context.allocator) -> []query.Place {
	out := make([dynamic]query.Place, allocator)
	append(&out, query.Place{name = "Home", path = home, dir = true})
	for name in ([]string{"Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos"}) {
		path, _ := filepath.join({home, name}, allocator)
		if os.exists(path) {
			append(&out, query.Place{name = name, path = path, dir = true})
		}
	}
	return out[:]
}

// deliver, on a pool thread, hands the job's answer to the ui, then retires
// it with the statistics. A job stays pending until its answer is in the
// inbox: one retired first let a reader find nothing pending and the inbox
// empty while an answer was still on its way, and stop waiting for it.
deliver :: proc(h: ^Host, d: Done) {
	job := d.job
	current := count_done(h, d)

	buf: [2048]byte
	stack: mem.Arena
	mem.arena_init(&stack, buf[:])
	context.temp_allocator = mem.arena_allocator(&stack)
	if current && d.ok {
		switch job.kind {
		case .Listing, .Places:
			ui.inbox_put(&h.inbox, job.key, d.data)
		case .Thumb:
			ui.inbox_put_value(
				&h.inbox,
				query.Thumb{path = string(job.path[:job.path_len]), px = job.px},
				query.Thumb_Result{image = string(job.dst[:job.dst_len])},
			)
		case .Open:
		}
	}
	if d.data != nil {
		delete(d.data, h.allocator)
	}
	sync.mutex_lock(&h.mutex)
	if current && job.kind != .Open {
		h.stats.pending -= 1
	}
	stats := h.stats
	sync.mutex_unlock(&h.mutex)
	ui.inbox_put_value(&h.inbox, query.Stats{}, stats)
	free(job, h.allocator)
	if h.wake != nil {
		h.wake()
	}
}

// count_done forgets d's job and counts how it ended, and says whether it was
// still the job for its need.
count_done :: proc(h: ^Host, d: Done) -> (current: bool) {
	job := d.job
	sync.mutex_guard(&h.mutex)
	current = job.kind == .Open || h.jobs[job.key] == job
	if current && job.kind != .Open {
		delete_key(&h.jobs, job.key)
	}
	switch job.kind {
	case .Listing:
		if current && d.ok {
			h.stats.listings += 1
			if w, live := &h.listings[job.key]; live {
				w.modified = d.modified
			}
		}
	case .Thumb:
		if d.cancelled || !current {
			h.stats.cancelled += 1
		} else if d.ok {
			h.stats.thumbs += 1
		}
	case .Open, .Places:
	}
	return
}

pool_main :: proc(h: ^Host) {
	stream.run(h.p, 2)
}

stats :: proc(h: ^Host) -> query.Stats_Result {
	sync.mutex_guard(&h.mutex)
	return h.stats
}
