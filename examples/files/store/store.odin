/*
Package store is the file browser's memory: the folders pinned to the
sidebar and the places visited lately, in SQLite on one thread. As in
examples/todo it is a stage of the stream pipeline, pinned to its
thread; writes and queries reach it as messages, results leave as
messages, and the connection's hooks report each committed change
through on_changes, which the application turns into fresh queries for
the shapes that are live.
*/
package files_store

import "core:encoding/cbor"
import "core:fmt"
import "core:mem"
import "core:time"

import "jm:sqlite3"
import "jm:ui"

import "../../common"
import "../shapes"

RECENT_SHOWN :: 12 // places listed
RECENT_KEPT :: 50 // rows kept

Text :: struct {
	buf: [common.MAX_PATH]u8,
	len: int,
}

text_make :: proc(s: string) -> (t: Text) {
	t.len = copy(t.buf[:], s)
	return
}

text_of :: proc(t: ^Text) -> string {
	return string(t.buf[:t.len])
}

Op :: enum u8 {
	Visited,
	Pin,
	Unpin,
}

Write :: struct {
	op:   Op,
	path: Text,
	name: Text,
	dir:  bool,
}

Kind :: enum u8 {
	Recent,
	Pins,
}

Query :: struct {
	key:  ui.Need_Key,
	kind: Kind,
}

Input :: union {
	Write,
	Query,
}

// Result is a shape for the ui, the caller's to free with result_free;
// Change_Batch is what one transaction changed, as the hooks report it.
Result :: common.Result
Change_Batch :: common.Change_Batch

Store :: struct {
	db:        sqlite3.Db,
	allocator: mem.Allocator,
	watcher:   common.Watcher,
	results:   [dynamic]Result,
}

open :: proc(st: ^Store, path: string, on_changes: proc(user: rawptr, batch: Change_Batch), user: rawptr, allocator := context.allocator) -> bool {
	db, err := sqlite3.open(path, {wal = true, busy_timeout = 1000}, allocator)
	if err != nil {
		fmt.eprintln("files: open store:", path, err)
		return false
	}
	if err = sqlite3.exec(db, `
		CREATE TABLE IF NOT EXISTS recent(path TEXT PRIMARY KEY, name TEXT NOT NULL, dir INTEGER NOT NULL, at INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS pin(path TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL)`); err != nil {
		fmt.eprintln("files: schema:", err)
		sqlite3.close(&db)
		return false
	}
	st.db = db
	st.allocator = allocator
	st.results = make([dynamic]Result, allocator)
	common.watch(db, &st.watcher, on_changes, user)
	return true
}

close :: proc(st: ^Store) {
	common.unwatch(st.db)
	delete(st.results)
	sqlite3.close(&st.db)
	st^ = {}
}

// apply is the stage: a write goes to the database, a query comes back
// as a result. The slice lives until the next call; the results in it
// are the caller's to free with result_free.
apply :: proc(st: ^Store, input: Input) -> []Result {
	clear(&st.results)
	switch v in input {
	case Write:
		if err := write(st, v); err != nil {
			fmt.eprintln("files: write:", err)
		}
	case Query:
		if data, ok := query(st, v.kind); ok {
			append(&st.results, Result{v.key, data})
		}
	}
	return st.results[:]
}

result_free :: proc(st: ^Store, r: Result) {
	delete(r.data, st.allocator)
}

@(private)
write :: proc(st: ^Store, w: Write) -> sqlite3.Error {
	w := w
	db := st.db
	switch w.op {
	case .Visited:
		sqlite3.exec_args(db, `INSERT INTO recent(path, name, dir, at) VALUES (?, ?, ?, ?)
			ON CONFLICT(path) DO UPDATE SET name = excluded.name, dir = excluded.dir, at = excluded.at`,
			text_of(&w.path), text_of(&w.name), w.dir, time.time_to_unix(time.now())) or_return
		return sqlite3.exec_args(db, "DELETE FROM recent WHERE path NOT IN (SELECT path FROM recent ORDER BY at DESC LIMIT ?)", i64(RECENT_KEPT))
	case .Pin:
		return sqlite3.exec_args(db, "INSERT OR IGNORE INTO pin(path, name, position) VALUES (?, ?, (SELECT COALESCE(MAX(position), 0) + 1 FROM pin))", text_of(&w.path), text_of(&w.name))
	case .Unpin:
		return sqlite3.exec_args(db, "DELETE FROM pin WHERE path = ?", text_of(&w.path))
	}
	return nil
}

@(private)
query :: proc(st: ^Store, kind: Kind) -> (data: []byte, ok: bool) {
	sql: string
	switch kind {
	case .Recent:
		sql = "SELECT path, name, dir FROM recent ORDER BY at DESC LIMIT ?"
	case .Pins:
		sql = "SELECT path, name, 1 FROM pin ORDER BY position LIMIT ?"
	}
	rows, err := sqlite3.query(st.db, sql, i64(RECENT_SHOWN if kind == .Recent else 100), allocator = context.temp_allocator)
	if err != nil {
		fmt.eprintln("files: query:", err)
		return nil, false
	}
	items := make([dynamic]shapes.Place, context.temp_allocator)
	for sqlite3.next(&rows) {
		append(&items, shapes.Place{path = sqlite3.text(rows, 0), name = sqlite3.text(rows, 1), dir = sqlite3.boolean(rows, 2)})
	}
	if ferr := sqlite3.finish(&rows); ferr != nil {
		return nil, false
	}
	merr: cbor.Marshal_Error
	switch kind {
	case .Recent:
		data, merr = cbor.marshal_into_bytes(shapes.Recent_Result{items = items[:]}, allocator = st.allocator, temp_allocator = context.temp_allocator)
	case .Pins:
		data, merr = cbor.marshal_into_bytes(shapes.Pins_Result{items = items[:]}, allocator = st.allocator, temp_allocator = context.temp_allocator)
	}
	return data, merr == nil
}
