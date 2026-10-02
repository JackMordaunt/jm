/*
Package app is the todo application's host: the pipeline that joins the
rules, the store and the ui, and the threads it runs on. It takes a frame
loop's needs and commands through data_host and answers through the inbox;
it never imports the view, so app_test.odin drives it with a ui.Probe and
no window.

The threads, and what crosses between them:

	main      ui/sdl's loop: input in, scene out. After each frame the
	          frame's needs and commands go to the pipeline through ports;
	          shapes come back through an Inbox, and sdl.wake runs a frame.
	logic     one stream worker: logic.process, one request at a time, in
	          order. A refused request becomes a problem; the problem list
	          is kept in the pipeline, in memory, and delivered as a shape.
	db        the store's thread: the pipeline's store stage is pinned to
	          it (stream.pin), so the connection is touched by one thread.
	          The store's update hook buffers each row a statement changes
	          and its commit hook pushes the batch into a port; its
	          rollback hook drops it (examples/todo/store).
	pool      stream.run on two threads: everything else in the graph.

The graph:

	commands ─ async_map(logic) ─┬─ writes ──────────────────┐
	                             └─ problems ─ fold ─ deliver │
	needs ───────────────────────────┐                        ├─ store ─ deliver
	changes ─ debounce ─ route(live) ┴─ queries ──────────────┘

A need for Todos{filter} subscribes a query that route re-runs on every
change batch while the need is live; a dropped need forgets it. Problems
are never stored: the fold's state is the list.
*/
package todo_app

import "core:mem"
import "core:sync"
import "core:thread"
import "core:time"

import "jm:stream"
import "jm:ui"

import "../logic"
import "../shapes"
import "../store"

MAX_PROBLEMS :: 8

// Need_Event is a need appearing or going, as the main thread hands it on.
Need_Event :: struct {
	added:  bool,
	key:    ui.Need_Key,
	todos:  bool, // a Todos need, with filter; else Problems
	filter: shapes.Filter,
}

// Route_In is what the route stage takes: a need or a change batch.
Route_In :: union {
	Need_Event,
	store.Change_Batch,
}

// Route keeps the live Todos needs, so a change re-runs each.
Route :: struct {
	live: map[ui.Need_Key]shapes.Filter,
	out:  [dynamic]store.Input,
}

// Problem_List is the problems in memory, as the fold emits it whole.
Problem_Slot :: struct {
	id:      u64,
	message: logic.Text,
}

Problem_List :: struct {
	items: [MAX_PROBLEMS]Problem_Slot,
	count: int,
}

Host :: struct {
	p:         ^stream.Pipeline,
	cmd_port:  stream.Port(logic.Request),
	need_port: stream.Port(Need_Event),
	chg_port:  stream.Port(store.Change_Batch),
	inbox:     ui.Inbox,
	workers:   ^stream.Workers, // the logic thread
	logic:     logic.Logic,
	route:     Route,
	problems:  Problem_List,
	store:     store.Store,
	missed:    bool, // a change batch the port had no room for; see on_changes
	db_wake:   sync.Sema,
	stopping:  bool, // atomic
	pool:      ^thread.Thread,
	db:        ^thread.Thread,
	wake:      proc(), // runs a frame once a shape is in the inbox; nil for none
}

// init opens the database at path, builds the pipeline and starts the
// threads. wake is called, from a pipeline thread, whenever a shape has
// been put in the inbox: a frame loop runs a frame on it.
init :: proc(h: ^Host, path: string, wake: proc() = nil) -> bool {
	h.wake = wake
	allocator := context.allocator
	ui.inbox_init(&h.inbox, allocator)
	if !store.open(&h.store, path, on_changes, h, allocator) {
		return false
	}
	h.route.live = make(map[ui.Need_Key]shapes.Filter, allocator)
	h.route.out = make([dynamic]store.Input, allocator)
	h.workers = stream.workers_start(1, allocator)

	p := stream.make_pipeline(allocator, cap = 64)
	h.p = p
	p.wake = db_wake
	p.wake_data = h
	commands: stream.Stream(logic.Request)
	needs: stream.Stream(Need_Event)
	changes: stream.Stream(store.Change_Batch)
	commands, h.cmd_port = stream.port(p, logic.Request, name = "commands")
	needs, h.need_port = stream.port(p, Need_Event, name = "needs")
	changes, h.chg_port = stream.port(p, store.Change_Batch, cap = 256, name = "changes")

	// The rules, on their own thread, one request at a time.
	outcomes := stream.async_map(commands, h.workers, &h.logic, logic.process, concurrency = 1, name = "logic")
	problems := stream.transform(stream.filter(outcomes, has_problem, name = "problems"), to_problem)
	stream.for_each_with(stream.transform_with(problems, &h.problems, fold_problem, name = "fold"), h, deliver_problems, name = "deliver problems")
	writes := stream.transform(stream.filter(outcomes, has_write, name = "writes"), to_write)

	// Needs and changes become queries for the store, through what is live.
	settled := stream.debounce(changes, 10 * time.Millisecond)
	routed := stream.merge([]stream.Stream(Route_In){stream.transform(needs, need_in), stream.transform(settled, change_in)}, name = "route in")
	queries := stream.flat_map_with(routed, &h.route, route, name = "route")

	// The store, pinned to the db thread; its results go to the inbox.
	inputs := stream.merge([]stream.Stream(store.Input){writes, queries}, name = "store in")
	results := stream.flat_map_with(inputs, &h.store, store.apply, name = "store")
	stream.pin(p, results.node)
	stream.for_each_with(results, h, deliver_result, name = "deliver")

	h.db = thread.create_and_start_with_poly_data(h, db_main)
	h.pool = thread.create_and_start_with_poly_data(h, pool_main)
	return true
}

// data_host is what the frame loop takes: the callbacks and the inbox.
data_host :: proc(h: ^Host) -> ui.Data_Host {
	return {user = h, on_need = on_need, on_command = on_command, inbox = &h.inbox}
}

// stop ends the threads in the order they depend on each other and frees
// everything.
stop :: proc(h: ^Host) {
	stream.stop(h.p)
	thread.join(h.pool)
	thread.destroy(h.pool)
	sync.atomic_store(&h.stopping, true)
	sync.sema_post(&h.db_wake)
	thread.join(h.db)
	thread.destroy(h.db)
	stream.workers_stop(h.workers)
	stream.destroy(h.p)
	store.close(&h.store)
	delete(h.route.live)
	delete(h.route.out)
	ui.inbox_destroy(&h.inbox)
}

// --- the main thread: what the frame loop hands on ---------------------------

on_need :: proc(user: rawptr, need: ui.Need, added: bool) {
	h := (^Host)(user)
	if q, ok := ui.need_as(need, shapes.Todos); ok {
		stream.port_send(h.need_port, Need_Event{added, need.key, true, q.filter})
	} else if ui.need_is(need, shapes.Problems) {
		stream.port_send(h.need_port, Need_Event{added = added, key = need.key})
	}
}

on_command :: proc(user: rawptr, c: ui.Command) {
	h := (^Host)(user)
	if r, ok := logic.request(c); ok {
		stream.port_send(h.cmd_port, r)
	}
}

// --- the db thread -------------------------------------------------------

db_wake :: proc(data: rawptr) {
	sync.sema_post(&(^Host)(data).db_wake)
}

db_main :: proc(h: ^Host) {
	for {
		sync.sema_wait(&h.db_wake)
		if sync.atomic_load(&h.stopping) {
			return
		}
		stream.drain_pinned(h.p)
		if h.missed && stream.port_push(h.chg_port, store.Change_Batch{truncated = true}) {
			h.missed = false
		}
		free_all(context.temp_allocator)
	}
}

// on_changes runs inside the commit, on the db thread. It must not wait:
// the pipeline's consumer of this port may be parked behind the very
// stage that is committing, so a full port is noted and a catch-up batch
// goes out once the stage has yielded.
on_changes :: proc(user: rawptr, batch: store.Change_Batch) {
	h := (^Host)(user)
	if !stream.port_push(h.chg_port, batch) {
		h.missed = true
	}
}

// --- the pipeline's stages ------------------------------------------------

has_problem :: proc(o: logic.Outcome) -> bool {
	return o.has_problem
}

has_write :: proc(o: logic.Outcome) -> bool {
	return o.has_write
}

to_problem :: proc(o: logic.Outcome) -> logic.Problem_Event {
	return o.problem
}

to_write :: proc(o: logic.Outcome) -> store.Input {
	return o.write
}

need_in :: proc(e: Need_Event) -> Route_In {
	return e
}

change_in :: proc(b: store.Change_Batch) -> Route_In {
	return b
}

// route turns a need into its query and a change into one query per live
// need. A Problems need has nothing to query: the fold delivers.
route :: proc(r: ^Route, v: Route_In) -> []store.Input {
	clear(&r.out)
	switch e in v {
	case Need_Event:
		if !e.todos {
			break
		}
		if e.added {
			r.live[e.key] = e.filter
			append(&r.out, store.Query{e.key, e.filter})
		} else {
			delete_key(&r.live, e.key)
		}
	case store.Change_Batch:
		for key, filter in r.live {
			append(&r.out, store.Query{key, filter})
		}
	}
	return r.out[:]
}

// fold_problem keeps the list: a new problem goes last, the oldest goes
// when the list is full, a dismissed one is removed.
fold_problem :: proc(l: ^Problem_List, e: logic.Problem_Event) -> Problem_List {
	if e.add {
		if l.count == MAX_PROBLEMS {
			copy(l.items[:], l.items[1:])
			l.count -= 1
		}
		l.items[l.count] = {e.id, e.message}
		l.count += 1
	} else {
		for ii in 0 ..< l.count {
			if l.items[ii].id == e.id {
				copy(l.items[ii:], l.items[ii + 1:l.count])
				l.count -= 1
				break
			}
		}
	}
	return l^
}

// deliver_problems marshals the list into the inbox under the Problems
// need. It runs on a pool thread, so it allocates in a stack arena.
deliver_problems :: proc(h: ^Host, l: Problem_List) {
	l := l
	buf: [4096]byte
	arena: mem.Arena
	mem.arena_init(&arena, buf[:])
	context.temp_allocator = mem.arena_allocator(&arena)
	items: [MAX_PROBLEMS]shapes.Problem
	for ii in 0 ..< l.count {
		items[ii] = {l.items[ii].id, logic.text_of(&l.items[ii].message)}
	}
	ui.inbox_put_value(&h.inbox, shapes.Problems{}, shapes.Problems_Result{items = items[:l.count]})
	if h.wake != nil {
		h.wake()
	}
}

deliver_result :: proc(h: ^Host, r: store.Result) {
	ui.inbox_put(&h.inbox, r.key, r.data)
	store.result_free(&h.store, r)
	if h.wake != nil {
		h.wake()
	}
}

pool_main :: proc(h: ^Host) {
	stream.run(h.p, 2)
}

