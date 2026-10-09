/*
Package store is Atlas's settings: one SQLite table of named values, read
when the window opens and written when a setting changes. The SQL is in
db/, with typed procs generated from it by tools/jm-sqlgen.

A setting is a few bytes written once in a while, so the ui thread writes
it itself, one statement in WAL mode, rather than through a store thread.
*/
package i18n_store

import "core:fmt"

import "jm:sqlite3"

import i18n_db "db"

// LANGUAGE is the setting the display language is saved under, as a
// BCP 47 tag.
LANGUAGE :: "language"

Store :: struct {
	db: sqlite3.Db,
}

// open opens the database at path, creates the table, and checks that
// every query still fits it.
open :: proc(st: ^Store, path: string, allocator := context.allocator) -> bool {
	db, err := sqlite3.open(path, {wal = true, busy_timeout = 1000}, allocator)
	if err != nil {
		fmt.eprintln("atlas: open:", err)
		return false
	}
	if err = sqlite3.exec(db, i18n_db.SCHEMA); err != nil {
		fmt.eprintln("atlas: schema:", err)
		sqlite3.close(&db)
		return false
	}
	if err = i18n_db.check(db, context.temp_allocator); err != nil {
		fmt.eprintln("atlas: the database does not fit the queries:", err)
		sqlite3.close(&db)
		return false
	}
	st.db = db
	return true
}

close :: proc(st: ^Store) {
	sqlite3.close(&st.db)
	st^ = {}
}

// setting is the value saved under name, in allocator; found is false
// when there is none, or it could not be read.
setting :: proc(st: ^Store, name: string, allocator := context.allocator) -> (value: string, found: bool) {
	row, ok, err := i18n_db.setting(st.db, name, allocator)
	if err != nil {
		fmt.eprintln("atlas: read", name, err)
		return "", false
	}
	return row.value, ok
}

// set_setting saves value under name.
set_setting :: proc(st: ^Store, name, value: string) -> bool {
	if err := i18n_db.set_setting(st.db, name, value, context.temp_allocator); err != nil {
		fmt.eprintln("atlas: save", name, err)
		return false
	}
	return true
}
