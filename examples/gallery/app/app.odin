/*
Package app is the gallery's host: the pipeline that makes pictures for
the tiles the ui needs, and gives them up when it stops needing them.

	needs ─ (added) ─ debounce_by(key, 80 ms) ─ async_map(cache or gen, 4 workers) ─ deliver
	      └ (dropped) ─ the tile's cancel flag, set at once

A need that appears starts a job after a short quiet, so a tile that
scrolls past in a flick never starts; one that is dropped while its job
runs has its cancel flag set on the main thread, the generator sees it
at its next row and gives up, and the result is discarded at the door.
A job asks the cache first and makes the picture only on a miss, then
puts it in the cache, which holds CACHE_BUDGET bytes of pictures (10 MB), least
recently used out first, never one a frame still needs. The sink keeps
the statistics, the cache's among them, and delivers them as a shape.
*/
package gallery_app

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:sync"
import "core:thread"
import "core:time"

import "jm:stream"
import "jm:ui"

import "../cache"
import "../gen"
import "../shapes"

QUIET :: 80 * time.Millisecond
WORKERS :: 4
CACHE_BUDGET :: 10 * 1024 * 1024

// Request is a need appearing, as the main thread hands it on.
Request :: struct {
	key: ui.Need_Key,
	job: ^Job,
}

// Job is one picture being made, a tile or a patch of one: its cancel
// flag, which the main thread sets, and the path it writes.
Job :: struct {
	cancel: bool, // atomic
	key:    ui.Need_Key,
	index:  int,
	px:     int,
	patch:  bool,
	level:  int,
	x, y:   int,
	path:   [256]u8,
	len:    int,
}

// Done is a job's end: cancelled, answered from the cache, or made.
Done :: struct {
	job:       ^Job,
	cancelled: bool,
	hit:       bool,
}

Host :: struct {
	p:         ^stream.Pipeline,
	need_port: stream.Port(Request),
	inbox:     ui.Inbox,
	workers:   ^stream.Workers,
	jobs:      map[ui.Need_Key]^Job, // under mutex: live jobs by need
	live:      map[ui.Need_Key]bool, // under mutex: the needs open now, which the cache keeps
	mutex:     sync.Mutex,
	cache:     cache.Cache,
	dir:       string, // this run's tile files
	stats:     shapes.Stats_Result,
	pool:      ^thread.Thread,
	wake:      proc(),
	allocator: mem.Allocator,
}

// init makes a directory for this run's pictures, builds the pipeline and
// starts the threads. wake is called from a pipeline thread whenever a
// shape has been put in the inbox. cache_budget is the cache's size, the
// default for the application and a small one for a test of eviction.
init :: proc(h: ^Host, wake: proc() = nil, cache_budget := CACHE_BUDGET) -> bool {
	h.wake = wake
	h.allocator = context.allocator
	tmp, err := os.temp_directory(context.temp_allocator)
	if err != nil {
		fmt.eprintln("gallery: no temp directory:", err)
		return false
	}
	run := fmt.tprintf("jm-gallery-%d", time.now()._nsec / 1_000_000)
	dir, _ := filepath.join({tmp, run}, h.allocator)
	if merr := os.make_directory(dir); merr != nil && !os.exists(dir) {
		fmt.eprintln("gallery: make directory:", dir, merr)
		return false
	}
	h.dir = dir
	ui.inbox_init(&h.inbox, h.allocator)
	h.jobs = make(map[ui.Need_Key]^Job, h.allocator)
	h.live = make(map[ui.Need_Key]bool, h.allocator)
	cache.init(&h.cache, cache_budget, h.allocator)
	h.workers = stream.workers_start(WORKERS, h.allocator)

	p := stream.make_pipeline(h.allocator, cap = 64)
	h.p = p
	requests: stream.Stream(Request)
	requests, h.need_port = stream.port(p, Request, cap = 256, name = "needs")
	settled := stream.debounce_by(requests, QUIET, request_key, name = "quiet")
	done := stream.async_map(settled, h.workers, h, make_tile, concurrency = WORKERS, ordered = false, name = "gen")
	stream.for_each_with(done, h, deliver, name = "deliver")
	h.pool = thread.create_and_start_with_poly_data(h, pool_main)
	return true
}

data_host :: proc(h: ^Host) -> ui.Data_Host {
	return {user = h, on_need = on_need, inbox = &h.inbox}
}

stop :: proc(h: ^Host) {
	// Cancel what is running so the workers finish quickly.
	sync.mutex_lock(&h.mutex)
	for _, job in h.jobs {
		sync.atomic_store(&job.cancel, true)
	}
	sync.mutex_unlock(&h.mutex)
	stream.stop(h.p)
	thread.join(h.pool)
	thread.destroy(h.pool)
	stream.workers_stop(h.workers)
	stream.destroy(h.p)
	for _, job in h.jobs {
		free(job, h.allocator)
	}
	delete(h.jobs)
	delete(h.live)
	cache.destroy(&h.cache)
	ui.inbox_destroy(&h.inbox)
	delete(h.dir, h.allocator)
}

// --- the main thread -------------------------------------------------------

// on_need starts a job for a tile that is needed and cancels one that is
// not. A tile needed again while its cancelled job still runs gets a new
// job; the old one's result is told apart by its pointer.
on_need :: proc(user: rawptr, need: ui.Need, added: bool) {
	h := (^Host)(user)
	job := new(Job, h.allocator)
	job.key = need.key
	if q, ok := ui.need_as(need, shapes.Tile); ok {
		job.index, job.px = q.index, q.px
		job.len = len(fmt.bprintf(job.path[:], "%s%ctile-%d-%d.bmp", h.dir, filepath.SEPARATOR, q.index, q.px))
	} else if pq, is := ui.need_as(need, shapes.Patch); is {
		job.index, job.px, job.patch, job.level, job.x, job.y = pq.index, pq.px, true, pq.level, pq.x, pq.y
		job.len = len(fmt.bprintf(job.path[:], "%s%cpatch-%d-%d-%d-%d-%d.bmp", h.dir, filepath.SEPARATOR, pq.index, pq.level, pq.x, pq.y, pq.px))
	} else {
		free(job, h.allocator)
		return
	}
	sync.mutex_lock(&h.mutex)
	if !added {
		free(job, h.allocator)
		delete_key(&h.live, need.key)
		h.stats.open -= 1
		if running, is_running := h.jobs[need.key]; is_running {
			sync.atomic_store(&running.cancel, true)
		}
		sync.mutex_unlock(&h.mutex)
		return
	}
	h.live[need.key] = true
	h.stats.open += 1
	if running, is_running := h.jobs[need.key]; is_running && !sync.atomic_load(&running.cancel) {
		free(job, h.allocator)
		sync.mutex_unlock(&h.mutex)
		return
	}
	h.jobs[need.key] = job
	h.stats.pending += 1
	sync.mutex_unlock(&h.mutex)
	// Sent with the lock released: a full port waits on the pool, and a
	// pool thread delivering waits on the lock.
	stream.port_send(h.need_port, Request{need.key, job})
}

// --- the pipeline -----------------------------------------------------------

request_key :: proc(r: Request) -> ui.Need_Key {
	return r.key
}

// make_tile runs on a worker. The cache is asked first: a picture it
// holds is the quick path that must not flash. On a miss the picture is
// made, then put, which may let the least recent go.
make_tile :: proc(h: ^Host, r: Request) -> Done {
	job := r.job
	path := string(job.path[:job.len])
	if sync.atomic_load(&job.cancel) {
		return {job = job, cancelled = true}
	}
	if _, hit := cache.get(&h.cache, job.key); hit {
		return {job = job, hit = true}
	}
	ok: bool
	if job.patch {
		ok = gen.patch(job.index, job.level, job.x, job.y, job.px, path, &job.cancel, patch_iterations(job.level))
	} else {
		ok = gen.tile(job.index, job.px, path, &job.cancel, iterations_for(job.px))
	}
	if ok {
		cache.put(&h.cache, job.key, path, 54 + job.px * job.px * 4, keep_live, h)
	}
	return {job = job, cancelled = !ok}
}

// keep_live is the cache's keep: a picture a frame needs now stays.
keep_live :: proc(user: rawptr, key: ui.Need_Key) -> bool {
	h := (^Host)(user)
	sync.mutex_guard(&h.mutex)
	return key in h.live
}

// iterations_for keeps a large picture's cost near three tiles' worth:
// the steps a pixel may take fall with the pixel count, within bounds.
iterations_for :: proc(px: int) -> int {
	base := 160 * 160 * 3
	return clamp(gen.ITERATIONS * base / max(px * px, 1), 400, gen.ITERATIONS)
}

// patch_iterations grows with the zoom: a deep square needs more steps
// to tell its points apart, and a shallow one is wanted fast.
patch_iterations :: proc(level: int) -> int {
	return min(1000 + 250 * level, gen.ITERATIONS)
}

// deliver, on a pool thread, retires the job and hands the picture and
// the statistics to the ui. A result for a job the table has replaced
// is dropped, whatever it says.
deliver :: proc(h: ^Host, d: Done) {
	job := d.job
	// The cache's counts first: its lock is taken before this one, in put.
	cs := cache.stats(&h.cache)
	sync.mutex_lock(&h.mutex)
	current := h.jobs[job.key] == job
	if current {
		delete_key(&h.jobs, job.key)
	}
	h.stats.pending -= 1
	if d.cancelled || !current {
		h.stats.cancelled += 1
	} else if !d.hit {
		h.stats.generated += 1
	}
	h.stats.cached, h.stats.cache_bytes = cs.entries, cs.bytes
	h.stats.hits, h.stats.misses, h.stats.evictions = cs.hits, cs.misses, cs.evictions
	stats := h.stats
	sync.mutex_unlock(&h.mutex)

	buf: [512]byte
	arena: mem.Arena
	mem.arena_init(&arena, buf[:])
	context.temp_allocator = mem.arena_allocator(&arena)
	if current && !d.cancelled {
		path := string(job.path[:job.len])
		if job.patch {
			ui.inbox_put_value(&h.inbox, shapes.Patch{job.index, job.level, job.x, job.y, job.px}, shapes.Tile_Result{path = path})
		} else {
			ui.inbox_put_value(&h.inbox, shapes.Tile{index = job.index, px = job.px}, shapes.Tile_Result{path = path})
		}
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

// stats is a copy of the statistics now, for a test.
stats :: proc(h: ^Host) -> shapes.Stats_Result {
	sync.mutex_guard(&h.mutex)
	return h.stats
}

