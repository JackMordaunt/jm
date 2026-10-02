package example_common

import "base:runtime"
import "core:c"
import "core:mem"
import "core:sync"
import "core:thread"

import "jm:sqlite3"
import "jm:stream"
import "jm:ui"

// What a SQLite data engine on its own thread shares between examples:
// the change batches its hooks report, the thread that drains the
// pipeline's pinned store stage, and the sink that hands a stage's
// results to the ui.

// MAX_CHANGES is how many rows one batch names; past that it says only
// that there were more, which is as good: a reader re-queries either way.
MAX_CHANGES :: 64

Change :: struct {
	op:    sqlite3.Update_Op,
	rowid: i64,
}

// Change_Batch is what one transaction changed.
Change_Batch :: struct {
	rows:      [MAX_CHANGES]Change,
	count:     int,
	truncated: bool,
}

// Watcher is a connection's change hooks: the update hook buffers each
// row a statement touches, the commit hook hands the buffer to
// on_changes, the rollback hook drops it, so a change that never
// committed is never reported. The hooks run on the connection's thread
// inside SQLite with no Odin context; ctx is the one they take.
Watcher :: struct {
	batch:      Change_Batch,
	on_changes: proc(user: rawptr, batch: Change_Batch),
	user:       rawptr,
	ctx:        runtime.Context,
}

// watch installs w's hooks on db; unwatch removes them.
watch :: proc(db: sqlite3.Db, w: ^Watcher, on_changes: proc(user: rawptr, batch: Change_Batch), user: rawptr) {
	w.on_changes = on_changes
	w.user = user
	w.ctx = context
	sqlite3.hooks(db, on_update, on_commit, on_rollback, w)
}

unwatch :: proc(db: sqlite3.Db) {
	sqlite3.hooks(db)
}

@(private)
on_update :: proc "c" (user: rawptr, op: sqlite3.Update_Op, db_name, table: cstring, rowid: i64) {
	w := (^Watcher)(user)
	b := &w.batch
	if b.count < MAX_CHANGES {
		b.rows[b.count] = {op, rowid}
		b.count += 1
	} else {
		b.truncated = true
	}
}

@(private)
on_commit :: proc "c" (user: rawptr) -> c.int {
	w := (^Watcher)(user)
	context = w.ctx
	if w.batch.count > 0 || w.batch.truncated {
		if w.on_changes != nil {
			w.on_changes(w.user, w.batch)
		}
		w.batch = {}
	}
	return 0
}

@(private)
on_rollback :: proc "c" (user: rawptr) {
	(^Watcher)(user).batch = {}
}

// Result is a shape a store stage answered: cbor under the need's key,
// in the allocator the stage was given, the consumer's to free.
Result :: struct {
	key:  ui.Need_Key,
	data: []byte,
}

// Db_Thread is the thread a pinned store stage runs on: it waits to be
// woken by the pipeline (p.wake), drains the pinned nodes, and sends on
// any change batch the port had no room for while the stage ran.
Db_Thread :: struct {
	p:        ^stream.Pipeline,
	changes:  stream.Port(Change_Batch),
	wake:     sync.Sema,
	stopping: bool, // atomic
	missed:   bool,
	thread:   ^thread.Thread,
}

// db_thread_open makes the changes port on p and points p's wake at d;
// the stream it returns is what the hooks' batches arrive on.
db_thread_open :: proc(d: ^Db_Thread, p: ^stream.Pipeline) -> stream.Stream(Change_Batch) {
	d.p = p
	p.wake = db_wake
	p.wake_data = d
	changes: stream.Stream(Change_Batch)
	changes, d.changes = stream.port(p, Change_Batch, cap = 256, name = "changes")
	return changes
}

db_thread_start :: proc(d: ^Db_Thread) {
	d.thread = thread.create_and_start_with_poly_data(d, db_main)
}

db_thread_stop :: proc(d: ^Db_Thread) {
	sync.atomic_store(&d.stopping, true)
	sync.sema_post(&d.wake)
	thread.join(d.thread)
	thread.destroy(d.thread)
}

// db_on_changes is the Watcher's on_changes for a store on a Db_Thread:
// it runs inside the commit and must not wait, since the port's consumer
// may be parked behind the very stage that is committing, so a full
// port is noted and a catch-up batch goes out once the stage has yielded.
db_on_changes :: proc(user: rawptr, batch: Change_Batch) {
	d := (^Db_Thread)(user)
	if !stream.port_push(d.changes, batch) {
		d.missed = true
	}
}

@(private)
db_wake :: proc(data: rawptr) {
	sync.sema_post(&(^Db_Thread)(data).wake)
}

@(private)
db_main :: proc(d: ^Db_Thread) {
	for {
		sync.sema_wait(&d.wake)
		if sync.atomic_load(&d.stopping) {
			return
		}
		stream.drain_pinned(d.p)
		if d.missed && stream.port_push(d.changes, Change_Batch{truncated = true}) {
			d.missed = false
		}
		free_all(context.temp_allocator)
	}
}

// Sink is where a stage's results go: the ui's inbox, and the frame loop
// to wake. deliver is the for_each over a results stream.
Sink :: struct {
	inbox:     ^ui.Inbox,
	wake:      proc(),
	allocator: mem.Allocator, // the results' bytes
}

deliver :: proc(s: ^Sink, r: Result) {
	ui.inbox_put(s.inbox, r.key, r.data)
	delete(r.data, s.allocator)
	if s.wake != nil {
		s.wake()
	}
}
