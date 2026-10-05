/*
Package store is the file browser's memory: the folders pinned to the
sidebar, the places visited lately, and the journal of changes Undo
reads, in SQLite on one thread. It is a client, not a decider: it reads
what it is asked, writes what it is told, and brackets a command's
writes in a transaction. Which writes a command comes to is
examples/files/logic's to say.

Changes leave another way, as in examples/todo: the connection's hooks
report each committed change through on_changes, which the application
turns into fresh reads of the sidebar.
*/
package files_store

import "core:fmt"
import "core:path/filepath"
import "core:time"

import "jm:sqlite3"

import "../../common"
import "../query"

RECENT_SHOWN :: 12 // places listed
RECENT_KEPT :: 50 // rows kept
JOURNAL_KEPT :: 50 // changes Undo can reach

// Change_Batch is what one transaction changed, as the hooks report it.
Change_Batch :: common.Change_Batch

Store :: struct {
	db:      sqlite3.Db,
	watcher: common.Watcher,
}

// Journal_Row is one change Undo can reverse, as the store keeps it.
Journal_Row :: struct {
	id:      i64,
	change:  u8,
	a, b, c: string,
}

open :: proc(st: ^Store, path: string, on_changes: proc(user: rawptr, batch: Change_Batch), user: rawptr, allocator := context.allocator) -> bool {
	db, err := sqlite3.open(path, {wal = true, busy_timeout = 1000}, allocator)
	if err != nil {
		fmt.eprintln("files: open store:", path, err)
		return false
	}
	if err = sqlite3.exec(db, `
		CREATE TABLE IF NOT EXISTS recent(path TEXT PRIMARY KEY, name TEXT NOT NULL, dir INTEGER NOT NULL, at INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS pin(path TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL);
		CREATE TABLE IF NOT EXISTS journal(id INTEGER PRIMARY KEY, change INTEGER NOT NULL, a TEXT NOT NULL, b TEXT NOT NULL, c TEXT NOT NULL)`); err != nil {
		fmt.eprintln("files: schema:", err)
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

// --- transactions -----------------------------------------------------------

begin :: proc(st: ^Store) -> sqlite3.Error {
	return sqlite3.exec(st.db, "BEGIN IMMEDIATE")
}

commit :: proc(st: ^Store) -> sqlite3.Error {
	return sqlite3.exec(st.db, "COMMIT")
}

// rollback undoes the transaction. Its own failure is logged, not
// returned: the caller is already reporting the failure that made it
// roll back.
rollback :: proc(st: ^Store) {
	if err := sqlite3.exec(st.db, "ROLLBACK"); err != nil {
		fmt.eprintln("files: rollback:", err)
	}
}

// --- places -----------------------------------------------------------------

visit :: proc(st: ^Store, path, name: string, dir: bool) -> sqlite3.Error {
	sqlite3.exec_args(st.db, `INSERT INTO recent(path, name, dir, at) VALUES (?, ?, ?, ?)
		ON CONFLICT(path) DO UPDATE SET name = excluded.name, dir = excluded.dir, at = excluded.at`,
		path, name, dir, time.to_unix_nanoseconds(time.now())) or_return
	return sqlite3.exec_args(st.db, "DELETE FROM recent WHERE path NOT IN (SELECT path FROM recent ORDER BY at DESC LIMIT ?)", i64(RECENT_KEPT))
}

pin :: proc(st: ^Store, path, name: string) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "INSERT OR IGNORE INTO pin(path, name, position) VALUES (?, ?, (SELECT COALESCE(MAX(position), 0) + 1 FROM pin))", path, name)
}

unpin :: proc(st: ^Store, path: string) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "DELETE FROM pin WHERE path = ?", path)
}

// UNDER matches a place at ?1 or anywhere under it, ?2 being the path
// separator: compared by prefix, not LIKE, so a path's own % and _
// match only themselves.
@(private)
UNDER :: "(path = ?1 OR substr(path, 1, length(?1) + length(?2)) = ?1 || ?2)"

// move_places makes the pins and recent places at or under from follow
// their entry to to; a place renamed itself takes its new name.
move_places :: proc(st: ^Store, from, to: string) -> sqlite3.Error {
	sep := filepath.SEPARATOR_STRING
	name := filepath.base(to)
	for table in ([]string{"pin", "recent"}) {
		sql := fmt.tprintf(`UPDATE OR REPLACE %s SET
			name = CASE WHEN path = ?1 THEN ?4 ELSE name END,
			path = ?3 || substr(path, length(?1) + 1)
			WHERE %s`, table, UNDER)
		sqlite3.exec_args(st.db, sql, from, sep, to, name) or_return
	}
	return nil
}

// forget_places drops the pins and recent places at or under path.
forget_places :: proc(st: ^Store, path: string) -> sqlite3.Error {
	sep := filepath.SEPARATOR_STRING
	for table in ([]string{"pin", "recent"}) {
		sqlite3.exec_args(st.db, fmt.tprintf("DELETE FROM %s WHERE %s", table, UNDER), path, sep) or_return
	}
	return nil
}

// places_under says whether any pin or recent place is at or under path.
places_under :: proc(st: ^Store, path: string) -> (yes: bool, err: sqlite3.Error) {
	sql := fmt.tprintf("SELECT EXISTS(SELECT 1 FROM pin WHERE %s) OR EXISTS(SELECT 1 FROM recent WHERE %s)", UNDER, UNDER)
	rows := sqlite3.query(st.db, sql, path, filepath.SEPARATOR_STRING, allocator = context.temp_allocator) or_return
	if sqlite3.next(&rows) {
		yes = sqlite3.boolean(rows, 0)
	}
	err = sqlite3.finish(&rows)
	return
}

// pins is the folders pinned, in the order pinned, in allocator.
pins :: proc(st: ^Store, allocator := context.temp_allocator) -> ([]query.Place, sqlite3.Error) {
	return places(st, "SELECT path, name, 1 FROM pin ORDER BY position LIMIT 100", allocator)
}

// recent is the places visited lately, newest first, in allocator.
recent :: proc(st: ^Store, allocator := context.temp_allocator) -> ([]query.Place, sqlite3.Error) {
	return places(st, fmt.tprintf("SELECT path, name, dir FROM recent ORDER BY at DESC LIMIT %d", RECENT_SHOWN), allocator)
}

@(private)
places :: proc(st: ^Store, sql: string, allocator := context.temp_allocator) -> (out: []query.Place, err: sqlite3.Error) {
	rows := sqlite3.query(st.db, sql, allocator = allocator) or_return
	items := make([dynamic]query.Place, allocator)
	for sqlite3.next(&rows) {
		append(&items, query.Place{path = sqlite3.text(rows, 0), name = sqlite3.text(rows, 1), dir = sqlite3.boolean(rows, 2)})
	}
	return items[:], sqlite3.finish(&rows)
}

// --- the journal --------------------------------------------------------------

// journal remembers a change, keeping the newest JOURNAL_KEPT.
journal :: proc(st: ^Store, change: u8, a, b, c: string) -> sqlite3.Error {
	sqlite3.exec_args(st.db, "INSERT INTO journal(change, a, b, c) VALUES (?, ?, ?, ?)", i64(change), a, b, c) or_return
	return sqlite3.exec_args(st.db, "DELETE FROM journal WHERE id NOT IN (SELECT id FROM journal ORDER BY id DESC LIMIT ?)", i64(JOURNAL_KEPT))
}

// unjournal forgets the change with id.
unjournal :: proc(st: ^Store, id: i64) -> sqlite3.Error {
	return sqlite3.exec_args(st.db, "DELETE FROM journal WHERE id = ?", id)
}

// newest is the newest change in the journal, its text in allocator, and
// whether there is one.
newest :: proc(st: ^Store, allocator := context.temp_allocator) -> (row: Journal_Row, has: bool, err: sqlite3.Error) {
	rows := sqlite3.query(st.db, "SELECT id, change, a, b, c FROM journal ORDER BY id DESC LIMIT 1", allocator = allocator) or_return
	if sqlite3.next(&rows) {
		row = {sqlite3.integer(rows, 0), u8(sqlite3.integer(rows, 1)), sqlite3.text(rows, 2), sqlite3.text(rows, 3), sqlite3.text(rows, 4)}
		has = true
	}
	err = sqlite3.finish(&rows)
	return
}
