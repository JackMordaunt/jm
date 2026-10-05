/*
Package app is the todo application's host: the pipeline that joins the
ui to the logic and the store, and the threads it runs on. It takes a
frame loop's needs and commands through data_host and answers through the
inbox; it never imports the view, so app_test.odin drives it with a
ui.Probe and no window. It is where ui.Command, the ui's encoding of a
command, becomes a todo.Command.

The threads, and what crosses between them:

	main      ui/sdl's loop: input in, scene out. After each frame the
	          frame's needs and commands go to the pipeline through ports;
	          results come back through an Inbox, and sdl.wake runs a frame.
	db        the store's thread: the pipeline's db stage is pinned to it
	          (stream.pin), so the connection is touched by one thread.
	          Each command is enriched, decided by logic, and executed
	          there, in one transaction (command.odin); reads are answered
	          there too. The problem list lives with the stage, in memory.
	          The store's update hook buffers each row a statement changes
	          and its commit hook pushes the batch into a port; its
	          rollback hook drops it (examples/todo/store).
	pool      stream.run on two threads: everything else in the graph.

The graph:

	commands ───────────────────────────────┐
	needs ─────────────────────┐            ├─ db ─ deliver
	changes ─ debounce ─ route(live) ─ reads ┘

A need for Todos{filter} subscribes a read that route re-runs on every
change batch while the need is live; a dropped need forgets it. A need
for Problems is answered once from the list in memory, and again by the
db stage whenever the list changes.
*/
package todo_app

import "core:thread"
import "core:time"

import "jm:stream"
import "jm:ui"

import "../../common"
import "../query"
import "../store"
import "../todo"

// Need_Event is a need appearing or going, as the main thread hands it on.
Need_Event :: struct {
	added: bool,
	key:   ui.Need_Key,
	q:     Read_Query,
}

// Route_In is what the route stage takes: a need or a change batch.
Route_In :: union {
	Need_Event,
	store.Change_Batch,
}

// Route keeps the live Todos needs, so a change re-runs each.
Route :: struct {
	live: map[ui.Need_Key]query.Filter,
	out:  [dynamic]Read,
}

Host :: struct {
	p:         ^stream.Pipeline,
	cmd_port:  stream.Port(todo.Command),
	need_port: stream.Port(Need_Event),
	inbox:     ui.Inbox,
	route:     Route,
	stage:     Db_Stage,
	db:        common.DB_Thread, // the store's thread, and the changes port
	sink:      common.Sink, // results to the inbox
	pool:      ^thread.Thread,
}

// init opens the database at path, builds the pipeline and starts the
// threads. wake is called, from a pipeline thread, whenever a result has
// been put in the inbox: a frame loop runs a frame on it.
init :: proc(h: ^Host, path: string, wake: proc() = nil) -> bool {
	allocator := context.allocator
	ui.inbox_init(&h.inbox, allocator)
	h.sink = {&h.inbox, wake, allocator}
	if !store.open(&h.stage.store, path, common.db_on_changes, &h.db, allocator) {
		return false
	}
	h.stage.allocator = allocator
	h.stage.out = make([dynamic]common.Result, allocator)
	h.route.live = make(map[ui.Need_Key]query.Filter, allocator)
	h.route.out = make([dynamic]Read, allocator)

	p := stream.make_pipeline(allocator, cap = 64)
	h.p = p

	db_changes := common.db_thread_open(&h.db, p)

	commands: stream.Stream(todo.Command)
	commands, h.cmd_port = stream.port(p, todo.Command, name = "commands")

	needs: stream.Stream(Need_Event)
	needs, h.need_port = stream.port(p, Need_Event, name = "needs")

	// Needs and changes become reads, through what is live.
	db_changes_settled := stream.debounce(db_changes, 10 * time.Millisecond)

	routed := stream.merge(
		[]stream.Stream(Route_In) {
			stream.transform(needs, need_in),
			stream.transform(db_changes_settled, change_in),
		},
		name = "route in",
	)

	reads := stream.flat_map_with(routed, &h.route, route, name = "route")

	// The db stage, pinned to the db thread; its results go to the inbox.
	db_in := stream.merge(
		[]stream.Stream(Db_In){stream.transform(commands, command_in), stream.transform(reads, read_in)},
		name = "db in",
	)

	results := stream.flat_map_with(db_in, &h.stage, db_apply, name = "db")

	stream.pin(p, results.node)
	stream.for_each_with(results, &h.sink, common.deliver, name = "deliver")

	common.db_thread_start(&h.db)
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
	common.db_thread_stop(&h.db)
	stream.destroy(h.p)
	store.close(&h.stage.store)
	delete(h.stage.out)
	delete(h.route.live)
	delete(h.route.out)
	ui.inbox_destroy(&h.inbox)
}

// --- the main thread: what the frame loop hands on ---------------------------

// on_need sends on the needs the application answers.
on_need :: proc(user: rawptr, need: ui.Need, added: bool) {
	h := (^Host)(user)
	if q, ok := ui.need_as(need, query.Todos); ok {
		stream.port_send(h.need_port, Need_Event{added, need.key, q})
	} else if ui.need_is(need, query.Problems) {
		stream.port_send(h.need_port, Need_Event{added, need.key, query.Problems{}})
	}
}

// on_command decodes the ui's command. A todo.Command holds no pointers,
// so the decoded value is whole and crosses the port by copy.
on_command :: proc(user: rawptr, c: ui.Command) {
	h := (^Host)(user)
	if cmd, ok := ui.command_as(c, todo.Command); ok {
		stream.port_send(h.cmd_port, cmd)
	}
}

// --- the pipeline's stages ------------------------------------------------

need_in :: proc(e: Need_Event) -> Route_In {
	return e
}

change_in :: proc(b: store.Change_Batch) -> Route_In {
	return b
}

command_in :: proc(c: todo.Command) -> Db_In {
	return c
}

read_in :: proc(r: Read) -> Db_In {
	return r
}

// route turns a new need into its read and a change into one read per
// live Todos need. A Problems need is read once, when it appears: the db
// stage sends the list again whenever it changes, so it is never live.
route :: proc(r: ^Route, v: Route_In) -> []Read {
	clear(&r.out)
	switch e in v {
	case Need_Event:
		if e.added {
			append(&r.out, Read{e.key, e.q})
		}
		if todos, ok := e.q.(query.Todos); ok {
			if e.added {
				r.live[e.key] = todos.filter
			} else {
				delete_key(&r.live, e.key)
			}
		}
	case store.Change_Batch:
		for key, filter in r.live {
			append(&r.out, Read{key, query.Todos{filter}})
		}
	}
	return r.out[:]
}

pool_main :: proc(h: ^Host) {
	stream.run(h.p, 2)
}
