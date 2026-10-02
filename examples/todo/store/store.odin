/*
Package store is the todo application's data engine: one SQLite connection
and the thread it belongs to. It is a stage of the stream pipeline, pinned
to that thread (stream.pin), so writes and queries reach it as messages on
one edge and results leave on another, and the connection is touched by
one thread only.

Changes leave another way. SQLite's update hook reports every row a
statement touches, into a buffer; the commit hook hands the buffer on as
one Change_Batch through on_changes, and the rollback hook drops it, so a
change that never committed is never reported. In the application the
batch goes into a port of the pipeline, which re-runs the live queries.
*/
package todo_store

import "base:runtime"
import "core:c"
import "core:encoding/cbor"
import "core:fmt"
import "core:mem"

import "jm:sqlite3"
import "jm:ui"

import "../logic"
import "../shapes"

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

// Query asks for the todos under a filter, to be answered under key.
Query :: struct {
	key:    ui.Need_Key,
	filter: shapes.Filter,
}

// Input is what reaches the store's stage.
Input :: union {
	logic.Write,
	Query,
}

// Result is a shape for the ui: the answer to a Query, as cbor. The
// consumer owns data and frees it with result_free.
Result :: struct {
	key:  ui.Need_Key,
	data: []byte,
}

Store :: struct {
	db:         sqlite3.Db,
	allocator:  mem.Allocator, // results and the pending slice
	batch:      Change_Batch, // what the transaction so far touched
	on_changes: proc(user: rawptr, batch: Change_Batch),
	user:       rawptr,
	results:    [dynamic]Result, // apply's answer, until the stage has emitted it
	problems:   int, // writes that failed, for the log
	ctx:        runtime.Context, // for the hooks, which SQLite calls without one
}

// open opens the database at path, creates the table, and installs the
// hooks. on_changes is called on the store's thread, from inside a commit.
open :: proc(
	st: ^Store,
	path: string,
	on_changes: proc(user: rawptr, batch: Change_Batch),
	user: rawptr,
	allocator := context.allocator,
) -> bool {
	db, err := sqlite3.open(path, {wal = true, busy_timeout = 1000}, allocator)
	if err != nil {
		fmt.eprintln("todo: open:", err)
		return false
	}
	if err = sqlite3.exec(db, `CREATE TABLE IF NOT EXISTS todo(
		id INTEGER PRIMARY KEY,
		title TEXT NOT NULL,
		done INTEGER NOT NULL DEFAULT 0)`); err != nil {
		fmt.eprintln("todo: schema:", err)
		sqlite3.close(&db)
		return false
	}
	st.db = db
	st.allocator = allocator
	st.on_changes = on_changes
	st.user = user
	st.results = make([dynamic]Result, allocator)
	st.ctx = context
	sqlite3.hooks(db, on_update, on_commit, on_rollback, st)
	return true
}

// close closes the connection. Results apply handed out are the caller's,
// freed or not, so nothing pending here is touched.
close :: proc(st: ^Store) {
	sqlite3.hooks(st.db)
	delete(st.results)
	sqlite3.close(&st.db)
	st^ = {}
}

// apply is the stage: a write goes to the database, a query comes back as
// a result. It is the f of a stream.flat_map_with over the store, so the
// slice it returns lives until the next call; the results in it are the
// caller's to free with result_free, which the pipeline's sink does once
// each has been delivered.
apply :: proc(st: ^Store, input: Input) -> []Result {
	clear(&st.results)
	switch v in input {
	case logic.Write:
		if err := write(st, v); err != nil {
			st.problems += 1
			fmt.eprintln("todo: write:", err)
		}
	case Query:
		if data, ok := query(st, v.filter); ok {
			append(&st.results, Result{v.key, data})
		}
	}
	return st.results[:]
}

result_free :: proc(st: ^Store, r: Result) {
	delete(r.data, st.allocator)
}

@(private)
write :: proc(st: ^Store, w: logic.Write) -> sqlite3.Error {
	w := w
	db := st.db
	switch w.op {
	case .Insert:
		return sqlite3.exec_args(db, "INSERT INTO todo(title) VALUES (?)", logic.text_of(&w.title))
	case .Set_Done:
		return sqlite3.exec_args(db, "UPDATE todo SET done = NOT done WHERE id = ?", w.id)
	case .Set_All:
		return sqlite3.exec_args(db, "UPDATE todo SET done = ? WHERE done != ?", w.done, w.done)
	case .Set_Title:
		return sqlite3.exec_args(db, "UPDATE todo SET title = ? WHERE id = ?", logic.text_of(&w.title), w.id)
	case .Remove:
		return sqlite3.exec_args(db, "DELETE FROM todo WHERE id = ?", w.id)
	case .Remove_Done:
		return sqlite3.exec(db, "DELETE FROM todo WHERE done = 1")
	}
	return nil
}

// query runs the filter and marshals the shape into a slice from the
// store's allocator.
@(private)
query :: proc(st: ^Store, filter: shapes.Filter) -> (data: []byte, ok: bool) {
	db := st.db
	counts, err := sqlite3.query(db, "SELECT COUNT(*) FILTER (WHERE done = 0), COUNT(*) FILTER (WHERE done = 1) FROM todo", allocator = context.temp_allocator)
	if err != nil {
		fmt.eprintln("todo: count:", err)
		return nil, false
	}
	res: shapes.Todos_Result
	if sqlite3.next(&counts) {
		res.active = int(sqlite3.integer(counts, 0))
		res.completed = int(sqlite3.integer(counts, 1))
	}
	sqlite3.finish(&counts)
	rows, qerr := sqlite3.query(
		db,
		"SELECT id, title, done FROM todo WHERE ?1 = 0 OR (?1 = 1 AND done = 0) OR (?1 = 2 AND done = 1) ORDER BY id",
		i64(filter),
		allocator = context.temp_allocator,
	)
	if qerr != nil {
		fmt.eprintln("todo: select:", qerr)
		return nil, false
	}
	items := make([dynamic]shapes.Todo, context.temp_allocator)
	for sqlite3.next(&rows) {
		append(&items, shapes.Todo{sqlite3.integer(rows, 0), sqlite3.text(rows, 1), sqlite3.boolean(rows, 2)})
	}
	if ferr := sqlite3.finish(&rows); ferr != nil {
		fmt.eprintln("todo: select:", ferr)
		return nil, false
	}
	res.items = items[:]
	bytes, merr := cbor.marshal_into_bytes(res, allocator = st.allocator, temp_allocator = context.temp_allocator)
	if merr != nil {
		return nil, false
	}
	return bytes, true
}

// The hooks. SQLite calls them on the store's thread with no Odin context,
// so each sets the one open saved. The buffer is the store's; nothing here
// touches the connection.

@(private)
on_update :: proc "c" (user: rawptr, op: sqlite3.Update_Op, db_name, table: cstring, rowid: i64) {
	st := (^Store)(user)
	b := &st.batch
	if b.count < MAX_CHANGES {
		b.rows[b.count] = {op, rowid}
		b.count += 1
	} else {
		b.truncated = true
	}
}

@(private)
on_commit :: proc "c" (user: rawptr) -> c.int {
	st := (^Store)(user)
	context = st.ctx
	if st.batch.count > 0 || st.batch.truncated {
		if st.on_changes != nil {
			st.on_changes(st.user, st.batch)
		}
		st.batch = {}
	}
	return 0
}

@(private)
on_rollback :: proc "c" (user: rawptr) {
	(^Store)(user).batch = {}
}
