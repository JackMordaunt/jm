package sqlite3

import "base:runtime"
import "core:c"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:testing"

@(test)
version_is_vendored :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	testing.expect_value(t, version(), "3.53.4")

	// The version alone would match a system library that happens to agree,
	// so check the options the justfile's recipe sets.
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)
	rows, qerr := query(db, `PRAGMA compile_options`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	opts: map[string]bool
	for next(&rows) {
		opts[text(rows, 0)] = true
	}
	testing.expect(t, opts["DQS=0"], "the archive must be the one just sqlite built")
	testing.expect(
		t,
		opts["THREADSAFE=1"],
		"threadsafe is why the recipe departs from the recommended set",
	)
	testing.expect(t, opts["ENABLE_FTS5"], "FTS5 is compiled in for a full-text index")
	testing.expect(
		t,
		opts["OMIT_LOAD_EXTENSION"],
		"load_extension is omitted so the link needs no libdl",
	)
	testing.expect(
		t,
		!opts["OMIT_AUTOINIT"],
		"autoinit stays on, so no call can precede initialize",
	)
}

// TRANSIENT is what every bind call passes, and it is the reason a caller may
// free or overwrite its buffer the moment bind returns.
@(test)
bind_copies_the_caller_s_bytes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)
	testing.expect_value(t, exec(db, `CREATE TABLE t(v TEXT)`), nil)

	buf := make([]byte, 5, context.temp_allocator)
	copy(buf, "alpha")
	stmt, perr := prepare(db, `INSERT INTO t VALUES (?)`)
	testing.expect_value(t, perr, nil)
	testing.expect_value(t, bind(&stmt, string(buf)), nil)
	// Overwrite the buffer after binding but before stepping.
	copy(buf, "OMEGA")
	testing.expect(t, !next(&stmt), "an insert returns no row")
	testing.expect_value(t, finish(&stmt), nil)

	rows, qerr := query(db, `SELECT v FROM t`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	testing.expect(t, next(&rows))
	testing.expect_value(t, text(rows, 0), "alpha")
}

@(test)
memory_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)

	testing.expect_value(t, exec(db, `CREATE TABLE note(id INTEGER PRIMARY KEY, body TEXT)`), nil)
	testing.expect_value(t, exec_args(db, `INSERT INTO note(body) VALUES (?)`, "hello"), nil)
	testing.expect_value(t, changes(db), 1)
	testing.expect_value(t, last_id(db), 1)

	rows, qerr := query(db, `SELECT id, body FROM note`)
	testing.expect_value(t, qerr, nil)
	testing.expect(t, next(&rows), "one row expected")
	testing.expect_value(t, integer(rows, 0), 1)
	testing.expect_value(t, text(rows, 1), "hello")
	testing.expect(t, !next(&rows), "only one row expected")
	testing.expect_value(t, finish(&rows), nil)
}

// A bound value survives unchanged through the characters that break SQL
// built by hand: an apostrophe, a quote, a semicolon, a backslash, a tab and
// a newline.
@(test)
quotes_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)
	testing.expect_value(t, exec(db, `CREATE TABLE t(v TEXT)`), nil)

	awkward := []string {
		"name-says-what-it-isn't",
		`he said "quoted"`,
		"; DROP TABLE t; --",
		"back\\slash and \ttab",
		"line\nbreak",
		"",
	}
	for v in awkward {
		testing.expect_value(t, exec_args(db, `INSERT INTO t(v) VALUES (?)`, v), nil)
	}
	rows, qerr := query(db, `SELECT v FROM t ORDER BY rowid`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	i := 0
	for next(&rows) {
		testing.expect_value(t, text(rows, 0), awkward[i])
		// An empty string must stay text, not become NULL.
		testing.expect(t, !is_null(rows, 0), "empty string must not be NULL")
		i += 1
	}
	testing.expect_value(t, i, len(awkward))

	// The table survived the statement that tried to drop it.
	count, cerr := query(db, `SELECT count(*) FROM t`)
	testing.expect_value(t, cerr, nil)
	defer finish(&count)
	testing.expect(t, next(&count))
	testing.expect_value(t, integer(count, 0), i64(len(awkward)))
}

@(test)
value_types_round_trip :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)
	testing.expect_value(t, exec(db, `CREATE TABLE v(i INT, r REAL, b BLOB, f INT, n TEXT)`), nil)

	raw := []byte{0, 1, 2, 0xff, 0}
	testing.expect_value(
		t,
		exec_args(db, `INSERT INTO v VALUES (?, ?, ?, ?, ?)`, i64(-7), 2.5, raw, true, nil),
		nil,
	)
	rows, qerr := query(db, `SELECT i, r, b, f, n FROM v`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	testing.expect(t, next(&rows))
	testing.expect_value(t, integer(rows, 0), -7)
	testing.expect_value(t, real(rows, 1), 2.5)
	testing.expect(t, slice.equal(blob(rows, 2), raw), "blob must survive its NUL bytes")
	testing.expect_value(t, boolean(rows, 3), true)
	testing.expect(t, is_null(rows, 4), "nil must bind as NULL")
	testing.expect_value(t, column_count(rows), 5)
	testing.expect_value(t, name(rows, 1), "r")
}

@(test)
errors_carry_the_message :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)

	_, serr := query(db, `SELECT nope FROM missing_table`)
	fault, ok := serr.(Fault)
	testing.expect(t, ok, "a bad query must fault")
	testing.expect_value(t, fault.code, Code.Error)
	// The point of the error type: the text names the table, not just a code.
	testing.expect_value(t, fault.text, "no such table: missing_table")

	testing.expect_value(t, exec(db, `CREATE TABLE u(v TEXT UNIQUE)`), nil)
	testing.expect_value(t, exec_args(db, `INSERT INTO u VALUES (?)`, "x"), nil)
	cerr := exec_args(db, `INSERT INTO u VALUES (?)`, "x")
	cfault, cok := cerr.(Fault)
	testing.expect(t, cok, "a duplicate must fault")
	testing.expect_value(t, cfault.code, Code.Constraint)
	testing.expect_value(t, cfault.text, "UNIQUE constraint failed: u.v")
}

@(test)
bind_count_is_checked :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)
	testing.expect_value(t, exec(db, `CREATE TABLE t(a, b)`), nil)

	short := exec_args(db, `INSERT INTO t VALUES (?, ?)`, i64(1))
	fault, ok := short.(Fault)
	testing.expect(t, ok, "a short argument list must fault")
	testing.expect_value(t, fault.code, Code.Range)
	testing.expect_value(t, fault.text, "statement takes 2 parameters, got 1")

	// What that guard is worth: bind the same statement through the raw API,
	// leaving the second parameter unset, and SQLite stores NULL without
	// complaint. bind refuses the call instead of writing that row.
	stmt, perr := prepare(db, `INSERT INTO t VALUES (?, ?)`)
	testing.expect_value(t, perr, nil)
	testing.expect_value(t, Code(sqlite3_bind_int64(stmt.handle, 1, 1)), Code.Ok)
	testing.expect(t, !next(&stmt), "an insert returns no row")
	testing.expect_value(t, finish(&stmt), nil)

	rows, qerr := query(db, `SELECT a, b FROM t`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	testing.expect(t, next(&rows), "the unguarded insert wrote a row")
	testing.expect_value(t, type_of(rows, 0), Type.Integer)
	testing.expect_value(t, type_of(rows, 1), Type.Null)
}

@(test)
exec_runs_every_statement :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)

	schema := `
		CREATE TABLE a(x INT);
		CREATE TABLE b(y INT);
		INSERT INTO a VALUES (1);
		INSERT INTO b VALUES (2);
	`
	testing.expect_value(t, exec(db, schema), nil)
	rows, qerr := query(db, `SELECT a.x + b.y FROM a, b`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	testing.expect(t, next(&rows))
	testing.expect_value(t, integer(rows, 0), 3)
}

@(test)
prepared_statement_is_reused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)
	testing.expect_value(t, exec(db, `CREATE TABLE n(v INT)`), nil)

	stmt, perr := prepare(db, `INSERT INTO n VALUES (?)`)
	testing.expect_value(t, perr, nil)
	for i in 0 ..< 100 {
		testing.expect_value(t, bind(&stmt, i64(i)), nil)
		testing.expect(t, !next(&stmt), "an insert returns no row")
		testing.expect_value(t, reset(&stmt), nil)
	}
	testing.expect_value(t, finish(&stmt), nil)

	sum, qerr := query(db, `SELECT count(*), sum(v) FROM n`)
	testing.expect_value(t, qerr, nil)
	defer finish(&sum)
	testing.expect(t, next(&sum))
	testing.expect_value(t, integer(sum, 0), 100)
	testing.expect_value(t, integer(sum, 1), 4950)
}

@(test)
file_survives_reopen :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	temp := os.temp_directory(context.temp_allocator) or_else ""
	dir, derr := os.make_directory_temp(temp, "jm-sqlite3-*", context.temp_allocator)
	testing.expect(t, derr == nil)
	defer os.remove_all(dir)
	path, _ := filepath.join({dir, "notes.db"}, context.temp_allocator)

	{
		db, err := open(path, Opts{wal = true})
		testing.expect_value(t, err, nil)
		defer close(&db)
		testing.expect_value(t, exec(db, `CREATE TABLE note(body TEXT)`), nil)
		testing.expect_value(t, transact(db, write_three), nil)
	}
	testing.expect(t, os.is_file(path), "the database file must exist")

	db, err := open(path, Opts{no_create = true})
	testing.expect_value(t, err, nil)
	defer close(&db)
	rows, qerr := query(db, `SELECT body FROM note ORDER BY rowid`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	got: [dynamic]string
	for next(&rows) {
		append(&got, text(rows, 0))
	}
	testing.expect_value(t, len(got), 3)
	testing.expect_value(t, got[0], "one")
	testing.expect_value(t, got[2], "three's")
}

@(private = "file")
write_three :: proc(db: Db, user: rawptr) -> Error {
	for body in ([]string{"one", "two", "three's"}) {
		exec_args(db, `INSERT INTO note(body) VALUES (?)`, body) or_return
	}
	return nil
}

@(test)
transaction_rolls_back :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY)
	testing.expect_value(t, err, nil)
	defer close(&db)
	testing.expect_value(t, exec(db, `CREATE TABLE t(v TEXT UNIQUE)`), nil)

	ferr := transact(db, write_then_fail)
	fault, ok := ferr.(Fault)
	testing.expect(t, ok, "the body's failure must be returned")
	testing.expect_value(t, fault.code, Code.Constraint)

	// Nothing the body wrote before it failed may survive.
	rows, qerr := query(db, `SELECT count(*) FROM t`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	testing.expect(t, next(&rows))
	testing.expect_value(t, integer(rows, 0), 0)
}

@(private = "file")
write_then_fail :: proc(db: Db, user: rawptr) -> Error {
	exec_args(db, `INSERT INTO t VALUES (?)`, "dup") or_return
	exec_args(db, `INSERT INTO t VALUES (?)`, "dup") or_return
	return nil
}

@(test)
read_only_refuses_writes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	temp := os.temp_directory(context.temp_allocator) or_else ""
	dir, derr := os.make_directory_temp(temp, "jm-sqlite3-ro-*", context.temp_allocator)
	testing.expect(t, derr == nil)
	defer os.remove_all(dir)
	path, _ := filepath.join({dir, "ro.db"}, context.temp_allocator)

	{
		db, err := open(path)
		testing.expect_value(t, err, nil)
		defer close(&db)
		testing.expect_value(t, exec(db, `CREATE TABLE t(v INT)`), nil)
	}

	db, err := open(path, Opts{read_only = true})
	testing.expect_value(t, err, nil)
	defer close(&db)
	werr := exec_args(db, `INSERT INTO t VALUES (?)`, i64(1))
	fault, ok := werr.(Fault)
	testing.expect(t, ok, "a write to a read-only database must fault")
	testing.expect_value(t, fault.code, Code.Read_Only)
}

@(test)
missing_file_faults :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	temp := os.temp_directory(context.temp_allocator) or_else ""
	path, _ := filepath.join({temp, "jm-sqlite3-does-not-exist.db"}, context.temp_allocator)
	_, err := open(path, Opts{no_create = true})
	fault, ok := err.(Fault)
	testing.expect(t, ok, "opening a missing database without create must fault")
	testing.expect_value(t, fault.code, Code.Cant_Open)
	testing.expect_value(t, fault.text, "unable to open database file")
	testing.expect(t, !os.exists(path), "no_create must not create the file")
}

// Opts.wal on an in-memory database leaves the mode alone: SQLite will not
// put :memory: into WAL.
@(test)
memory_ignores_wal :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	db, err := open(MEMORY, Opts{wal = true})
	testing.expect_value(t, err, nil)
	defer close(&db)

	rows, qerr := query(db, `PRAGMA journal_mode`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	testing.expect(t, next(&rows))
	testing.expect_value(t, text(rows, 0), "memory")
}

// And a file-backed database does take WAL, which is the other half of the
// option's doc.
@(test)
file_takes_wal :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	temp := os.temp_directory(context.temp_allocator) or_else ""
	dir, derr := os.make_directory_temp(temp, "jm-sqlite3-wal-*", context.temp_allocator)
	testing.expect(t, derr == nil)
	defer os.remove_all(dir)
	path, _ := filepath.join({dir, "wal.db"}, context.temp_allocator)

	db, err := open(path, Opts{wal = true})
	testing.expect_value(t, err, nil)
	defer close(&db)
	rows, qerr := query(db, `PRAGMA journal_mode`)
	testing.expect_value(t, qerr, nil)
	defer finish(&rows)
	testing.expect(t, next(&rows))
	testing.expect_value(t, text(rows, 0), "wal")
}

@(private = "file")
Hook_Log :: struct {
	rows:      [dynamic]i64,
	commits:   int,
	rollbacks: int,
}

@(private = "file")
log_update :: proc "c" (user: rawptr, op: Update_Op, db_name, table: cstring, rowid: i64) {
	context = runtime.default_context()
	l := (^Hook_Log)(user)
	append(&l.rows, rowid if op != .Delete else -rowid)
}

@(private = "file")
log_commit :: proc "c" (user: rawptr) -> c.int {
	(^Hook_Log)(user).commits += 1
	return 0
}

@(private = "file")
log_rollback :: proc "c" (user: rawptr) {
	(^Hook_Log)(user).rollbacks += 1
}

@(test)
hooks_report_rows_commits_and_rollbacks :: proc(t: ^testing.T) {
	db, err := open(MEMORY)
	testing.expect(t, err == nil)
	defer close(&db)
	testing.expect(t, exec(db, "CREATE TABLE todo(id INTEGER PRIMARY KEY, title TEXT)") == nil)
	l: Hook_Log
	defer delete(l.rows)
	hooks(db, log_update, log_commit, log_rollback, &l)

	// Autocommit: one statement, one row, one commit.
	testing.expect(t, exec_args(db, "INSERT INTO todo(title) VALUES (?)", "a") == nil)
	testing.expect_value(t, len(l.rows), 1)
	testing.expect_value(t, l.commits, 1)

	// A transaction: rows report as they happen, the commit once at the end.
	testing.expect(t, exec(db, "BEGIN") == nil)
	testing.expect(t, exec_args(db, "INSERT INTO todo(title) VALUES (?)", "b") == nil)
	testing.expect(t, exec(db, "DELETE FROM todo WHERE id = 1") == nil)
	testing.expect_value(t, l.commits, 1)
	testing.expect(t, exec(db, "COMMIT") == nil)
	testing.expect_value(t, l.commits, 2)
	testing.expect_value(t, len(l.rows), 3)
	testing.expect_value(t, l.rows[2], i64(-1))

	// A rollback reports as one, and the rows it undid were reported before it.
	testing.expect(t, exec(db, "BEGIN") == nil)
	testing.expect(t, exec_args(db, "INSERT INTO todo(title) VALUES (?)", "c") == nil)
	testing.expect(t, exec(db, "ROLLBACK") == nil)
	testing.expect_value(t, l.rollbacks, 1)
	testing.expect_value(t, l.commits, 2)

	// Removed hooks say nothing.
	hooks(db)
	testing.expect(t, exec_args(db, "INSERT INTO todo(title) VALUES (?)", "d") == nil)
	testing.expect_value(t, l.commits, 2)
}
