/*
Package store is the todo application's data engine: one SQLite connection,
touched by one thread. It is a client, not a decider: it reads what it is
asked (the facts a command needs, the rows a query wants), writes what it
is told, and brackets both in a transaction. Which write a command comes to
is examples/todo/logic's to say, and the host's to carry out.

Changes leave another way. SQLite's update hook reports every row a
statement touches, into a buffer; the commit hook hands the buffer on as
one Change_Batch through on_changes, and the rollback hook drops it, so a
change that never committed is never reported. In the application the
batch goes into a port of the pipeline, which re-runs the live queries.
*/
package todo_store

import "core:fmt"

import "jm:sqlite3"

import "../../common"
import "../query"

// Change_Batch is what one transaction changed, as the hooks report it.
Change_Batch :: common.Change_Batch

Store :: struct {
	db:      sqlite3.Db,
	watcher: common.Watcher, // the hooks' buffer and where a batch goes
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
	if err = sqlite3.exec(
		db,
		`CREATE TABLE IF NOT EXISTS todo(
		id INTEGER PRIMARY KEY,
		title TEXT NOT NULL,
		done INTEGER NOT NULL DEFAULT 0)`,
	); err != nil {
		fmt.eprintln("todo: schema:", err)
		sqlite3.close(&db)
		return false
	}
	st.db = db
	common.watch(db, &st.watcher, on_changes, user)
	return true
}

close :: proc(st: ^Store) {
	common.unwatch(st.db)
	sqlite3.close(&st.db)
	st^ = {}
}

// --- transactions: a command's reads and writes commit together ----------

begin :: proc(st: ^Store) -> sqlite3.Error {
	return sqlite3.exec(st.db, "BEGIN IMMEDIATE")
}

commit :: proc(st: ^Store) -> sqlite3.Error {
	return sqlite3.exec(st.db, "COMMIT")
}

// rollback undoes the transaction. Its own failure is not returned: the
// caller is already reporting the failure that made it roll back.
rollback :: proc(st: ^Store) {
	if err := sqlite3.exec(st.db, "ROLLBACK"); err != nil {
		fmt.eprintln("todo: rollback:", err)
	}
}

// --- reads ----------------------------------------------------------------

// todo_state says whether todo id exists and whether it is done.
todo_state :: proc(st: ^Store, id: i64) -> (exists, done: bool, err: sqlite3.Error) {
	rows := sqlite3.query(
		st.db,
		"SELECT done FROM todo WHERE id = ?",
		id,
		allocator = context.temp_allocator,
	) or_return
	if sqlite3.next(&rows) {
		exists, done = true, sqlite3.boolean(rows, 0)
	}
	err = sqlite3.finish(&rows)
	return
}

// counts is how many todos are active and how many done.
counts :: proc(st: ^Store) -> (active, completed: int, err: sqlite3.Error) {
	rows := sqlite3.query(
		st.db,
		"SELECT COUNT(*) FILTER (WHERE done = 0), COUNT(*) FILTER (WHERE done = 1) FROM todo",
		allocator = context.temp_allocator,
	) or_return
	if sqlite3.next(&rows) {
		active = int(sqlite3.integer(rows, 0))
		completed = int(sqlite3.integer(rows, 1))
	}
	err = sqlite3.finish(&rows)
	return
}

// todos answers query.Todos, in allocator.
todos :: proc(
	st: ^Store,
	filter: query.Filter,
	allocator := context.temp_allocator,
) -> (
	res: query.Todos_Result,
	err: sqlite3.Error,
) {
	res.active, res.completed = counts(st) or_return
	rows := sqlite3.query(
		st.db,
		"SELECT id, title, done FROM todo WHERE ?1 = 0 OR (?1 = 1 AND done = 0) OR (?1 = 2 AND done = 1) ORDER BY id",
		i64(filter),
		allocator = allocator,
	) or_return
	items := make([dynamic]query.Todo, allocator)
	for sqlite3.next(&rows) {
		todo := query.Todo{sqlite3.integer(rows, 0), sqlite3.text(rows, 1), sqlite3.boolean(rows, 2)}
		append(&items, todo)
	}
	res.items = items[:]
	err = sqlite3.finish(&rows)
	return
}

// --- writes ---------------------------------------------------------------

insert :: proc(st: ^Store, title: string) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "INSERT INTO todo(title) VALUES (?)", title)
}

set_done :: proc(st: ^Store, id: i64, done: bool) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "UPDATE todo SET done = ? WHERE id = ?", done, id)
}

// set_all touches only the rows that differ, so the change batch names
// only those.
set_all :: proc(st: ^Store, done: bool) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "UPDATE todo SET done = ? WHERE done != ?", done, done)
}

set_title :: proc(st: ^Store, id: i64, title: string) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "UPDATE todo SET title = ? WHERE id = ?", title, id)
}

remove :: proc(st: ^Store, id: i64) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "DELETE FROM todo WHERE id = ?", id)
}

remove_done :: proc(st: ^Store) -> sqlite3.Error {
	return sqlite3.exec(st.db, "DELETE FROM todo WHERE done = 1")
}
