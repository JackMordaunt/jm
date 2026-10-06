/*
Package store is the todo application's data engine: one SQLite connection,
touched by one thread. It is a client, not a decider: it reads what it is
asked (the facts a command needs, the rows a query wants), writes what it
is told, and brackets both in a transaction. Which write a command comes to
is examples/todo/logic's to say, and the host's to carry out.

The SQL is in db/: schema.sql and queries.sql, with typed procs generated
from them by tools/jm-sqlgen. This package shapes their rows for the
application.

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
import todo_db "db"

// Change_Batch is what one transaction changed, as the hooks report it.
Change_Batch :: common.Change_Batch

Store :: struct {
	db:      sqlite3.Db,
	watcher: common.Watcher, // the hooks' buffer and where a batch goes
}

// open opens the database at path, creates the table, checks that every
// query still fits it, and installs the hooks. on_changes is called on the
// store's thread, from inside a commit.
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
	if err = sqlite3.exec(db, todo_db.SCHEMA); err != nil {
		fmt.eprintln("todo: schema:", err)
		sqlite3.close(&db)
		return false
	}
	// A database made by an older build may lack a column a query reads.
	if err = todo_db.check(db, context.temp_allocator); err != nil {
		fmt.eprintln("todo: the database does not fit the queries:", err)
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

// --- reads: the generated queries in db, shaped for the application ------

// todo_state says whether todo id exists and whether it is done.
todo_state :: proc(st: ^Store, id: i64) -> (exists, done: bool, err: sqlite3.Error) {
	row, found := todo_db.todo_state(st.db, id, context.temp_allocator) or_return
	return found, row.done, nil
}

// counts is how many todos are active and how many done.
counts :: proc(st: ^Store) -> (active, completed: int, err: sqlite3.Error) {
	row, _ := todo_db.counts(st.db, context.temp_allocator) or_return
	return int(row.active), int(row.completed), nil
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
	items := make([dynamic]query.Todo, allocator)
	rows: todo_db.Todos_Rows
	if todo_db.todos(&rows, st.db, i64(filter), allocator) {
		for row in todo_db.todos_next(&rows) {
			append(&items, query.Todo{row.id, row.title, row.done})
		}
	}
	res.items = items[:]
	return res, rows.err
}

// --- writes ---------------------------------------------------------------

insert :: proc(st: ^Store, title: string) -> sqlite3.Error {
	return todo_db.insert(st.db, title)
}

set_done :: proc(st: ^Store, id: i64, done: bool) -> sqlite3.Error {
	return todo_db.set_done(st.db, id, done)
}

// set_all touches only the rows that differ, so the change batch names
// only those.
set_all :: proc(st: ^Store, done: bool) -> sqlite3.Error {
	return todo_db.set_all(st.db, done)
}

set_title :: proc(st: ^Store, id: i64, title: string) -> sqlite3.Error {
	return todo_db.set_title(st.db, id, title)
}

remove :: proc(st: ^Store, id: i64) -> sqlite3.Error {
	return todo_db.remove(st.db, id)
}

remove_done :: proc(st: ^Store) -> sqlite3.Error {
	return todo_db.remove_done(st.db)
}
