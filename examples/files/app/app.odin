/*
Package app is the file browser's host: the pipeline that reads folders,
makes thumbnails and opens files for the ui on four worker threads, and
keeps the sidebar's pins and recent places in SQLite on a thread of its
own, as examples/todo keeps its todos.

	needs (listing, places) ─┐
	needs (thumb) ─ debounce_by(key, 60 ms) ─┤─ async_map(fs, 4 workers) ─ deliver
	commands (open) ─┘

	commands (visited, pin, unpin) ─ writes ─────────────┐
	needs (recent, pins) ─────┐                           ├─ store (pinned) ─ deliver
	changes ─ debounce ─ route(live) ─ queries ───────────┘

A folder is read as soon as it is needed. A thumbnail waits a short
quiet first, so a row that scrolls past never starts one, and one whose
need goes while its job runs is cancelled where the work next checks.
Thumbnails go under the temp directory, a folder per run. The store's
commit hook pushes each change into a port, and the route stage re-runs
the queries for the shapes that are live, so a pin or a visit shows in
the sidebar the moment it is committed.
*/
package files_app

import "core:encoding/cbor"
import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:thread"
import "core:time"

import "jm:stream"
import "jm:ui"

import "../../common"
import "../fs"
import "../shapes"
import "../store"

QUIET :: 60 * time.Millisecond
SETTLE :: 10 * time.Millisecond // commits coalesced before the sidebar re-queries
WORKERS :: 4

Kind :: enum u8 {
	Listing,
	Thumb,
	Open,
	Places,
}

// Need_Event is a sidebar need appearing or going.
Need_Event :: struct {
	added: bool,
	key:   ui.Need_Key,
	kind:  store.Kind,
}

Route_In :: union {
	Need_Event,
	store.Change_Batch,
}

// Route keeps the sidebar needs that are live, so a change re-runs each.
Route :: struct {
	live: map[ui.Need_Key]store.Kind,
	out:  [dynamic]store.Input,
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
// allocator; a thumbnail written or not; an open attempted.
Done :: struct {
	job:       ^Job,
	cancelled: bool,
	ok:        bool,
	data:      []byte,
}

Host :: struct {
	p:         ^stream.Pipeline,
	direct:    stream.Port(Request), // listings, places and opens, at once
	thumbs:    stream.Port(Request), // thumbnails, after a quiet
	need_db:   stream.Port(Need_Event), // sidebar needs
	db_in:     stream.Port(store.Input), // writes
	inbox:     ui.Inbox,
	workers:   ^stream.Workers,
	jobs:      map[ui.Need_Key]^Job, // under mutex
	mutex:     sync.Mutex,
	dir:       string,
	home:      string,
	stats:     shapes.Stats_Result,
	pool:      ^thread.Thread,
	wake:      proc(),
	allocator: mem.Allocator,
	// The store and its thread: the pinned stage, woken by the pipeline.
	store:     store.Store,
	route:     Route,
	db:        common.DB_Thread,
	sink:      common.Sink,
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
	if !store.open(&h.store, db, common.db_on_changes, &h.db, h.allocator) {
		return false
	}
	h.sink = {&h.inbox, wake, h.allocator}
	h.route.live = make(map[ui.Need_Key]store.Kind, h.allocator)
	h.route.out = make([dynamic]store.Input, h.allocator)
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
	h.workers = stream.workers_start(WORKERS, h.allocator)

	p := stream.make_pipeline(h.allocator, cap = 64)
	h.p = p
	direct, thumbs: stream.Stream(Request)
	direct, h.direct = stream.port(p, Request, cap = 256, name = "direct")
	thumbs, h.thumbs = stream.port(p, Request, cap = 256, name = "thumbs")
	settled := stream.debounce_by(thumbs, QUIET, request_key, name = "quiet")
	work := stream.merge([]stream.Stream(Request){direct, settled}, name = "work")
	done := stream.async_map(work, h.workers, h, run_job, concurrency = WORKERS, ordered = false, name = "fs")
	stream.for_each_with(done, h, deliver, name = "deliver")

	// The store's half: writes and routed queries into the pinned stage.
	changes := common.db_thread_open(&h.db, p)
	need_db: stream.Stream(Need_Event)
	db_in: stream.Stream(store.Input)
	need_db, h.need_db = stream.port(p, Need_Event, name = "sidebar needs")
	db_in, h.db_in = stream.port(p, store.Input, name = "writes")
	committed := stream.debounce(changes, SETTLE)
	routed := stream.merge([]stream.Stream(Route_In){stream.transform(need_db, need_in), stream.transform(committed, change_in)}, name = "route in")
	queries := stream.flat_map_with(routed, &h.route, route, name = "route")
	inputs := stream.merge([]stream.Stream(store.Input){db_in, queries}, name = "store in")
	results := stream.flat_map_with(inputs, &h.store, store.apply, name = "store")
	stream.pin(p, results.node)
	stream.for_each_with(results, &h.sink, common.deliver, name = "deliver db")

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
	stream.workers_stop(h.workers)
	stream.destroy(h.p)
	store.close(&h.store)
	for _, job in h.jobs {
		free(job, h.allocator)
	}
	delete(h.jobs)
	delete(h.route.live)
	delete(h.route.out)
	ui.inbox_destroy(&h.inbox)
	delete(h.dir, h.allocator)
	delete(h.home, h.allocator)
}

// --- the main thread -------------------------------------------------------

on_need :: proc(user: rawptr, need: ui.Need, added: bool) {
	h := (^Host)(user)
	// The sidebar's needs go to the store's route, not to a worker.
	if ui.need_is(need, shapes.Recent) || ui.need_is(need, shapes.Pins) {
		sync.mutex_lock(&h.mutex)
		h.stats.open += 1 if added else -1
		sync.mutex_unlock(&h.mutex)
		stream.port_send(h.need_db, Need_Event{added, need.key, .Recent if ui.need_is(need, shapes.Recent) else .Pins})
		return
	}
	job := new(Job, h.allocator)
	job.key = need.key
	if q, ok := ui.need_as(need, shapes.Listing); ok {
		job.kind = .Listing
		job.path_len = copy(job.path[:], q.path)
	} else if ui.need_is(need, shapes.Places) {
		job.kind = .Places
	} else if tq, is := ui.need_as(need, shapes.Thumb); is {
		job.kind = .Thumb
		job.px = tq.px
		job.path_len = copy(job.path[:], tq.path)
		job.dst_len = len(fmt.bprintf(job.dst[:], "%s%cthumb-%x-%d.bmp", h.dir, filepath.SEPARATOR, u64(need.key), tq.px))
	} else {
		free(job, h.allocator)
		return
	}
	sync.mutex_lock(&h.mutex)
	if !added {
		free(job, h.allocator)
		h.stats.open -= 1
		if running, is_running := h.jobs[need.key]; is_running {
			sync.atomic_store(&running.cancel, true)
		}
		sync.mutex_unlock(&h.mutex)
		return
	}
	h.stats.open += 1
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

on_command :: proc(user: rawptr, c: ui.Command) {
	h := (^Host)(user)
	if o, opens := ui.command_as(c, shapes.Open); opens {
		job := new(Job, h.allocator)
		job.kind = .Open
		job.path_len = copy(job.path[:], o.path)
		stream.port_send(h.direct, Request{0, job})
	} else if v, visited := ui.command_as(c, shapes.Visited); visited {
		stream.port_send(h.db_in, store.Write{op = .Visited, path = store.text_make(v.path), name = store.text_make(v.name), dir = v.dir})
	} else if pin, pins := ui.command_as(c, shapes.Pin); pins {
		stream.port_send(h.db_in, store.Write{op = .Pin, path = store.text_make(pin.path), name = store.text_make(pin.name)})
	} else if un, unpins := ui.command_as(c, shapes.Unpin); unpins {
		stream.port_send(h.db_in, store.Write{op = .Unpin, path = store.text_make(un.path)})
	}
}

// --- the store's route ------------------------------------------------------

need_in :: proc(e: Need_Event) -> Route_In {
	return e
}

change_in :: proc(b: store.Change_Batch) -> Route_In {
	return b
}

// route turns a sidebar need into its query and a change into a fresh
// query for each live Pins need. Recent is answered once, when its need
// appears: a snapshot, so the sidebar holds still while the folders
// visited are still being written down for the next time.
route :: proc(r: ^Route, v: Route_In) -> []store.Input {
	clear(&r.out)
	switch e in v {
	case Need_Event:
		if e.added {
			r.live[e.key] = e.kind
			append(&r.out, store.Query{e.key, e.kind})
		} else {
			delete_key(&r.live, e.key)
		}
	case store.Change_Batch:
		for key, kind in r.live {
			if kind == .Pins {
				append(&r.out, store.Query{key, kind})
			}
		}
	}
	return r.out[:]
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
		entries, error := fs.list(path, context.temp_allocator)
		data, err := cbor.marshal_into_bytes(shapes.Listing_Result{entries = entries, error = error}, allocator = h.allocator, temp_allocator = context.temp_allocator)
		return {job = job, ok = err == nil, data = data}
	case .Thumb:
		dst := string(job.dst[:job.dst_len])
		ok := fs.thumbnail(path, dst, job.px, &job.cancel)
		return {job = job, ok = ok, cancelled = !ok && sync.atomic_load(&job.cancel)}
	case .Open:
		return {job = job, ok = fs.open_default(path)}
	case .Places:
		data, err := cbor.marshal_into_bytes(shapes.Places_Result{items = places(h.home, context.temp_allocator)}, allocator = h.allocator, temp_allocator = context.temp_allocator)
		return {job = job, ok = err == nil, data = data}
	}
	return {job = job}
}

// places is the standard folders under home that exist, the home folder first.
places :: proc(home: string, allocator := context.allocator) -> []shapes.Place {
	out := make([dynamic]shapes.Place, allocator)
	append(&out, shapes.Place{name = "Home", path = home, dir = true})
	for name in ([]string{"Desktop", "Documents", "Downloads", "Music", "Pictures", "Videos"}) {
		path, _ := filepath.join({home, name}, allocator)
		if os.exists(path) {
			append(&out, shapes.Place{name = name, path = path, dir = true})
		}
	}
	return out[:]
}

// deliver, on a pool thread, retires the job and hands its answer to the
// ui, with the statistics.
deliver :: proc(h: ^Host, d: Done) {
	job := d.job
	sync.mutex_lock(&h.mutex)
	current := job.kind == .Open || h.jobs[job.key] == job
	if current && job.kind != .Open {
		delete_key(&h.jobs, job.key)
		h.stats.pending -= 1
	}
	switch job.kind {
	case .Listing:
		if current && d.ok {
			h.stats.listings += 1
		}
	case .Thumb:
		if d.cancelled || !current {
			h.stats.cancelled += 1
		} else if d.ok {
			h.stats.thumbs += 1
		}
	case .Open, .Places:
	}
	stats := h.stats
	sync.mutex_unlock(&h.mutex)

	buf: [2048]byte
	stack: mem.Arena
	mem.arena_init(&stack, buf[:])
	context.temp_allocator = mem.arena_allocator(&stack)
	if current && d.ok {
		switch job.kind {
		case .Listing, .Places:
			ui.inbox_put(&h.inbox, job.key, d.data)
		case .Thumb:
			ui.inbox_put_value(&h.inbox, shapes.Thumb{path = string(job.path[:job.path_len]), px = job.px}, shapes.Thumb_Result{image = string(job.dst[:job.dst_len])})
		case .Open:
		}
	}
	if d.data != nil {
		delete(d.data, h.allocator)
	}
	ui.inbox_put_value(&h.inbox, shapes.Stats{}, stats)
	free(job, h.allocator)
	if h.wake != nil {
		h.wake()
	}
}

pool_main :: proc(h: ^Host) {
	stream.run(h.p, 2)
}

stats :: proc(h: ^Host) -> shapes.Stats_Result {
	sync.mutex_lock(&h.mutex)
	defer sync.mutex_unlock(&h.mutex)
	return h.stats
}
