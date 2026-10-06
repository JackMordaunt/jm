/*
Package sqlite3 is SQLite for scripts. The amalgamation is vendored and linked
statically, so a built script needs no system library and no shared object at
runtime. docs/sqlite.md records the version, the compile-time
options and how to check a build for a stray libsqlite3.

	db := must(sqlite3.open("notes.db"))
	defer sqlite3.close(&db)

	must(sqlite3.exec(db, `CREATE TABLE IF NOT EXISTS note(id INTEGER PRIMARY KEY, body TEXT)`))
	must(sqlite3.exec_args(db, `INSERT INTO note(body) VALUES (?)`, "it isn't quoted by hand"))

	rows := must(sqlite3.query(db, `SELECT id, body FROM note WHERE body LIKE ?`, "%isn't%"))
	defer sqlite3.finish(&rows)
	for sqlite3.next(&rows) {
		fmt.println(sqlite3.integer(rows, 0), sqlite3.text(rows, 1))
	}

Values are always bound, never interpolated into the SQL: a parameter holding
an apostrophe, a newline or a NUL byte round-trips unchanged, and there is no
string-building path for an injection to travel down.

Memory: text and blob columns are cloned into the allocator the query was
given, because SQLite frees its own copy on the next step. Everything else is
a value.

Threads: the justfile's `sqlite` recipe sets SQLITE_THREADSAFE=1, which is
SQLite's serialized mode. One Db is not guarded here, so a Db shared across
jm:flow workers needs the caller's own mutex, or a connection per worker.
*/
package sqlite3

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:time"

// Code is a SQLite primary result code. Ok, Row and Done are not failures.
Code :: enum i32 {
	Ok         = 0,
	Error      = 1,
	Internal   = 2,
	Perm       = 3,
	Abort      = 4,
	Busy       = 5,
	Locked     = 6,
	No_Mem     = 7,
	Read_Only  = 8,
	Interrupt  = 9,
	Io         = 10,
	Corrupt    = 11,
	Not_Found  = 12,
	Full       = 13,
	Cant_Open  = 14,
	Protocol   = 15,
	Empty      = 16,
	Schema     = 17,
	Too_Big    = 18,
	Constraint = 19,
	Mismatch   = 20,
	Misuse     = 21,
	No_Lfs     = 22,
	Auth       = 23,
	Format     = 24,
	Range      = 25,
	Not_A_Db   = 26,
	Notice     = 27,
	Warning    = 28,
	Row        = 100,
	Done       = 101,
}

// Fault is a failed call: the result code and the message the connection gave
// for it, which names the constraint or the file rather than restating the
// code. The text is cloned, so it outlives the next call.
Fault :: struct {
	code:     Code,
	// The extended result code, which tells apart the failures one code
	// covers: CONSTRAINT_DATATYPE from CONSTRAINT_UNIQUE, say. 0 when the
	// failure did not come from the connection.
	extended: i32,
	text:     string,
}

// Extended result codes that callers tell apart. SQLite has many more; these
// are the ones jm reads.
CONSTRAINT_NOTNULL  :: 1299
CONSTRAINT_DATATYPE :: 3091

// Error is nil when a call succeeded, so `or_return` and prelude.must both
// work on it.
Error :: union {
	Fault,
}

// Type is a column's storage class in the row the cursor is on.
Type :: enum {
	Null,
	Integer,
	Real,
	Text,
	Blob,
}

// Value is one bound parameter. A string binds as TEXT, []byte as BLOB, nil
// as NULL, and bool as the integer 0 or 1, which is how SQLite stores it.
Value :: union {
	i64,
	f64,
	bool,
	string,
	[]byte,
}

// Db is an open connection.
Db :: struct {
	handle:    ^Connection,
	allocator: mem.Allocator,
}

// Stmt is one compiled statement, and the row cursor query hands back. The
// column readers below are valid after next has returned true.
Stmt :: struct {
	db:        ^Connection,
	handle:    ^Statement,
	allocator: mem.Allocator,
	// Set when the last step failed, and returned by finish.
	err:       Error,
}

// Opts tunes how open opens the database.
Opts :: struct {
	// Open an existing database for reading only. Nothing is created.
	read_only:    bool,
	// Do not create the database if it is missing; fail with Cant_Open.
	no_create:    bool,
	// Read path as a file: URI, so query parameters like ?mode=ro apply.
	uri:          bool,
	// Switch the database to write-ahead logging after opening. An in-memory
	// database keeps the mode it had; see the tests for both cases.
	wal:          bool,
	// How long a write blocked by another connection waits before Busy.
	busy_timeout: time.Duration,
	// Run these statements right after opening, before anything else. A
	// pragma the whole connection needs belongs here.
	on_open:      string,
}

// MEMORY opens a private in-memory database that is discarded on close.
MEMORY :: ":memory:"

// open opens the database at path, creating it unless Opts says otherwise.
// Pass MEMORY for a scratch database that never touches the disk.
open :: proc(
	path: string,
	opts := Opts{},
	allocator := context.allocator,
) -> (
	db: Db,
	err: Error,
) {
	flags := c.int(OPEN_READWRITE | OPEN_CREATE)
	if opts.read_only {
		flags = OPEN_READONLY
	} else if opts.no_create {
		flags = OPEN_READWRITE
	}
	if opts.uri {
		flags |= OPEN_URI
	}
	handle: ^Connection
	name := strings.clone_to_cstring(path, context.temp_allocator)
	code := Code(sqlite3_open_v2(name, &handle, flags, nil))
	if code != .Ok {
		// open_v2 hands back a handle even on failure, so the message can be
		// read off it; closing it is the caller's job, done here.
		err = fault(handle, code, allocator)
		sqlite3_close_v2(handle)
		return {}, err
	}
	db = Db {
		handle    = handle,
		allocator = allocator,
	}
	if opts.busy_timeout > 0 {
		ms := c.int(time.duration_milliseconds(opts.busy_timeout))
		sqlite3_busy_timeout(handle, ms)
	}
	if opts.wal {
		// SQLite refuses WAL for an in-memory database and keeps the mode it
		// had. Nothing else here depends on the mode, so the result is not
		// worth failing the open over.
		_ = exec(db, "PRAGMA journal_mode = WAL")
	}
	if opts.on_open != "" {
		if err = exec(db, opts.on_open); err != nil {
			sqlite3_close_v2(handle)
			return {}, err
		}
	}
	return db, nil
}

// close closes the connection and zeroes db. An open transaction is rolled
// back. A Stmt that was never finished keeps the connection alive as a
// zombie until it is, so finish every statement before closing: that is what
// sqlite3_close_v2 defers on, and the file stays open until it happens.
close :: proc(db: ^Db) -> Error {
	if db == nil || db.handle == nil {
		return nil
	}
	code := Code(sqlite3_close_v2(db.handle))
	err := code == .Ok ? nil : fault(db.handle, code, db.allocator)
	db^ = {}
	return err
}

// exec runs sql for its effect and discards any rows. The text may hold
// several statements separated by semicolons, which is what a schema is, and
// each runs in turn. It binds nothing: use exec_args to pass values.
exec :: proc(db: Db, sql: string) -> Error {
	rest := sql
	for {
		stmt, tail, err := prepare_one(db, rest)
		if err != nil {
			return err
		}
		if stmt.handle == nil {
			// Only whitespace or a comment was left.
			return nil
		}
		for {
			code := Code(sqlite3_step(stmt.handle))
			if code == .Row {
				continue
			}
			if code != .Done {
				sqlite3_finalize(stmt.handle)
				return fault(db.handle, code, db.allocator)
			}
			break
		}
		sqlite3_finalize(stmt.handle)
		rest = tail
		if strings.trim_space(rest) == "" {
			return nil
		}
	}
}

// exec_args runs one statement with args bound to its ? parameters and
// discards any rows. It is the write half of query.
exec_args :: proc(db: Db, sql: string, args: ..Value) -> Error {
	stmt := query(db, sql, ..args) or_return
	for next(&stmt) {}
	return finish(&stmt)
}

// query compiles sql, binds args to its ? parameters in order, and returns
// the cursor to step with next. Only the first statement in sql is run.
query :: proc(
	db: Db,
	sql: string,
	args: ..Value,
	allocator := context.allocator,
) -> (
	stmt: Stmt,
	err: Error,
) {
	stmt, _, err = prepare_one(db, sql, allocator)
	if err != nil {
		return {}, err
	}
	if stmt.handle == nil {
		return {}, Fault{code = .Error, text = strings.clone("no statement in sql", allocator)}
	}
	if err = bind(&stmt, ..args); err != nil {
		sqlite3_finalize(stmt.handle)
		return {}, err
	}
	return stmt, nil
}

// prepare compiles sql for repeated use: bind, step and reset it, then finish
// it once. Binding one statement many times is how a batch of inserts should
// be written, since the SQL is parsed once.
prepare :: proc(db: Db, sql: string, allocator := context.allocator) -> (stmt: Stmt, err: Error) {
	stmt, _, err = prepare_one(db, sql, allocator)
	if err != nil {
		return {}, err
	}
	if stmt.handle == nil {
		return {}, Fault{code = .Error, text = strings.clone("no statement in sql", allocator)}
	}
	return stmt, nil
}

// bind sets the statement's parameters, numbered from 1 in the order given.
// Passing a different count than the statement declares is a Range fault,
// caught here rather than leaving a parameter silently NULL.
bind :: proc(stmt: ^Stmt, args: ..Value) -> Error {
	want := int(sqlite3_bind_parameter_count(stmt.handle))
	if want != len(args) {
		return Fault {
			code = .Range,
			text = fmt.aprintf(
				"statement takes %d parameters, got %d",
				want,
				len(args),
				allocator = stmt.allocator,
			),
		}
	}
	for arg, i in args {
		idx := c.int(i + 1)
		code: Code
		switch v in arg {
		case i64:
			code = Code(sqlite3_bind_int64(stmt.handle, idx, v))
		case f64:
			code = Code(sqlite3_bind_double(stmt.handle, idx, v))
		case bool:
			code = Code(sqlite3_bind_int64(stmt.handle, idx, v ? 1 : 0))
		case string:
			// raw_data of an empty string is nil, which binds NULL rather
			// than the empty string, so hand SQLite a valid pointer instead.
			p := len(v) > 0 ? raw_data(v) : ([^]u8)(&empty_byte)
			code = Code(sqlite3_bind_text(stmt.handle, idx, p, c.int(len(v)), TRANSIENT))
		case []byte:
			p := len(v) > 0 ? rawptr(raw_data(v)) : rawptr(&empty_byte)
			code = Code(sqlite3_bind_blob(stmt.handle, idx, p, c.int(len(v)), TRANSIENT))
		case:
			code = Code(sqlite3_bind_null(stmt.handle, idx))
		}
		if code != .Ok {
			return fault(stmt.db, code, stmt.allocator)
		}
	}
	return nil
}

// next advances to the next row and reports whether one arrived. A failure
// stops the loop and is kept on the statement for finish to return, so the
// common read loop needs no error check of its own.
next :: proc(stmt: ^Stmt) -> bool {
	if stmt.handle == nil || stmt.err != nil {
		return false
	}
	code := Code(sqlite3_step(stmt.handle))
	switch code {
	case .Row:
		return true
	case .Done:
		return false
	case .Ok,
	     .Error,
	     .Internal,
	     .Perm,
	     .Abort,
	     .Busy,
	     .Locked,
	     .No_Mem,
	     .Read_Only,
	     .Interrupt,
	     .Io,
	     .Corrupt,
	     .Not_Found,
	     .Full,
	     .Cant_Open,
	     .Protocol,
	     .Empty,
	     .Schema,
	     .Too_Big,
	     .Constraint,
	     .Mismatch,
	     .Misuse,
	     .No_Lfs,
	     .Auth,
	     .Format,
	     .Range,
	     .Not_A_Db,
	     .Notice,
	     .Warning:
		stmt.err = fault(stmt.db, code, stmt.allocator)
		return false
	}
	return false
}

// reset rewinds a prepared statement for its next use and clears its
// bindings, so a stale parameter cannot leak into the following row.
reset :: proc(stmt: ^Stmt) -> Error {
	if stmt.handle == nil {
		return nil
	}
	stmt.err = nil
	if code := Code(sqlite3_reset(stmt.handle)); code != .Ok {
		return fault(stmt.db, code, stmt.allocator)
	}
	sqlite3_clear_bindings(stmt.handle)
	return nil
}

// finish releases the statement and returns whatever failure stopped it.
// Calling it twice is safe.
finish :: proc(stmt: ^Stmt) -> Error {
	if stmt.handle == nil {
		return stmt.err
	}
	err := stmt.err
	code := Code(sqlite3_finalize(stmt.handle))
	if err == nil && code != .Ok {
		err = fault(stmt.db, code, stmt.allocator)
	}
	stmt.handle = nil
	return err
}

// transact runs body between BEGIN and COMMIT, rolls back if body fails, and
// returns body's error. user is passed through untouched, since Odin has no
// closures to capture it.
transact :: proc(db: Db, body: proc(db: Db, user: rawptr) -> Error, user: rawptr = nil) -> Error {
	exec(db, "BEGIN") or_return
	if err := body(db, user); err != nil {
		// The rollback's own failure would hide why the work failed, so the
		// body's error is the one returned.
		_ = exec(db, "ROLLBACK")
		return err
	}
	return exec(db, "COMMIT")
}

// column_count reports how many columns the current row has.
column_count :: proc(stmt: Stmt) -> int {
	return int(sqlite3_column_count(stmt.handle))
}

// name is the column's name in the result set, cloned into the statement's
// allocator.
name :: proc(stmt: Stmt, col: int) -> string {
	n := sqlite3_column_name(stmt.handle, c.int(col))
	return n == nil ? "" : strings.clone_from_cstring(n, stmt.allocator)
}

// parameter_count is how many parameters the statement takes. A named
// parameter used twice counts once.
parameter_count :: proc(stmt: Stmt) -> int {
	return int(sqlite3_bind_parameter_count(stmt.handle))
}

// parameter_name is parameter i's name with its prefix, such as "@id", cloned
// into the statement's allocator; "" for a bare ?. Parameters count from 0,
// as columns do, in the order bind takes them.
parameter_name :: proc(stmt: Stmt, i: int) -> string {
	n := sqlite3_bind_parameter_name(stmt.handle, c.int(i + 1))
	return n == nil ? "" : strings.clone_from_cstring(n, stmt.allocator)
}

// read_only reports whether the statement leaves the database unchanged.
read_only :: proc(stmt: Stmt) -> bool {
	return sqlite3_stmt_readonly(stmt.handle) != 0
}

// origin is the table and column a result column reads, cloned into the
// statement's allocator, when it is a plain reference to one: through a view,
// a subquery or a CTE, SQLite follows it to the base table. Both are "" for
// an expression. A compound SELECT reports its leftmost arm only.
origin :: proc(stmt: Stmt, col: int) -> (table, column: string) {
	t := sqlite3_column_table_name(stmt.handle, c.int(col))
	n := sqlite3_column_origin_name(stmt.handle, c.int(col))
	if t == nil || n == nil {
		return "", ""
	}
	return strings.clone_from_cstring(t, stmt.allocator), strings.clone_from_cstring(n, stmt.allocator)
}

// integer reads the column as an integer. A NULL or a non-numeric text reads
// as 0, which is SQLite's own conversion.
integer :: proc(stmt: Stmt, col: int) -> i64 {
	return sqlite3_column_int64(stmt.handle, c.int(col))
}

// real reads the column as a float.
real :: proc(stmt: Stmt, col: int) -> f64 {
	return sqlite3_column_double(stmt.handle, c.int(col))
}

// boolean reads the column as a truth value: non-zero is true.
boolean :: proc(stmt: Stmt, col: int) -> bool {
	return sqlite3_column_int64(stmt.handle, c.int(col)) != 0
}

// text reads the column as a string, cloned into the statement's allocator
// because SQLite frees its copy at the next step.
text :: proc(stmt: Stmt, col: int) -> string {
	n := int(sqlite3_column_bytes(stmt.handle, c.int(col)))
	p := sqlite3_column_text(stmt.handle, c.int(col))
	if p == nil || n == 0 {
		return ""
	}
	return strings.clone(string(p[:n]), stmt.allocator)
}

// blob reads the column's bytes, cloned into the statement's allocator for
// the same reason text is.
blob :: proc(stmt: Stmt, col: int) -> []byte {
	n := int(sqlite3_column_bytes(stmt.handle, c.int(col)))
	p := sqlite3_column_blob(stmt.handle, c.int(col))
	if p == nil || n == 0 {
		return nil
	}
	out := make([]byte, n, stmt.allocator)
	mem.copy(raw_data(out), p, n)
	return out
}

// type_of is how SQLite is storing the column in this row. A column has no
// one type in SQLite, so the same column can read back differently row to row.
type_of :: proc(stmt: Stmt, col: int) -> Type {
	switch int(sqlite3_column_type(stmt.handle, c.int(col))) {
	case TYPE_INTEGER:
		return .Integer
	case TYPE_FLOAT:
		return .Real
	case TYPE_TEXT:
		return .Text
	case TYPE_BLOB:
		return .Blob
	case TYPE_NULL:
		return .Null
	}
	return .Null
}

// is_null reports whether the column holds NULL, which the readers above
// cannot tell apart from 0 or the empty string.
is_null :: proc(stmt: Stmt, col: int) -> bool {
	return type_of(stmt, col) == .Null
}

// read_exact reads the column as T without converting it, where the readers
// above would: T is i64, f64, bool, string or []byte, and the value must be stored
// as INTEGER, REAL, INTEGER 0 or 1, TEXT or BLOB respectively. Anything else,
// NULL included, fails the statement with Mismatch, which next and finish
// then report, and reads as T's zero. Text and blobs are cloned as text and
// blob clone them. Code that tools/jm-sqlgen generates reads every column
// this way, so a value of a type it did not expect stops the read.
read_exact :: proc(
	stmt: ^Stmt,
	col: int,
	$T: typeid,
) -> (
	v: T,
) where T == i64 ||
	T == f64 ||
	T == bool ||
	T == string ||
	T == []byte {
	when T == i64 {
		if expect(stmt, col, .Integer) {
			v = integer(stmt^, col)
		}
	} else when T == f64 {
		if expect(stmt, col, .Real) {
			v = real(stmt^, col)
		}
	} else when T == string {
		if expect(stmt, col, .Text) {
			v = text(stmt^, col)
		}
	} else when T == []byte {
		if expect(stmt, col, .Blob) {
			v = blob(stmt^, col)
		}
	} else {
		if !expect(stmt, col, .Integer) {
			return
		}
		switch n := integer(stmt^, col); n {
		case 0, 1:
			v = n == 1
		case:
			buf: [64]byte
			mismatch(stmt, fmt.bprintf(buf[:], "holds %d, which is not a bool", n), col)
		}
	}
	return
}

// read_exact_maybe reads the column as read_exact does, and as nil when it is
// NULL.
read_exact_maybe :: proc(stmt: ^Stmt, col: int, $T: typeid) -> (v: Maybe(T)) {
	if !is_null(stmt^, col) {
		v = read_exact(stmt, col, T)
	}
	return
}

// nullable is v as a bound value: its value, or NULL when it has none.
nullable :: proc(v: Maybe($T)) -> Value {
	if x, ok := v.?; ok {
		return x
	}
	return nil
}

// check_statement prepares sql and compares it with the shape the calling
// code was written for: params parameters, and columns named columns in
// that order. It is how generated code finds that a database's schema has
// drifted before a query runs. A difference is a Schema fault naming name.
check_statement :: proc(
	db: Db,
	name, sql: string,
	params: int,
	columns: []string,
	allocator := context.allocator,
) -> Error {
	stmt, err := prepare(db, sql, allocator)
	if f, failed := err.(Fault); failed {
		f.text = fmt.aprintf("%s: %s", name, f.text, allocator = allocator)
		return f
	}
	defer finish(&stmt)
	drift := Fault {
		code = .Schema,
	}
	switch {
	case parameter_count(stmt) != params:
		drift.text = fmt.aprintf(
			"%s takes %d parameters, not %d",
			name,
			parameter_count(stmt),
			params,
			allocator = allocator,
		)
		return drift
	case column_count(stmt) != len(columns):
		drift.text = fmt.aprintf(
			"%s returns %d columns, not %d",
			name,
			column_count(stmt),
			len(columns),
			allocator = allocator,
		)
		return drift
	}
	for want, i in columns {
		if got := name_of(stmt, i); got != want {
			drift.text = fmt.aprintf(
				"%s names column %d %q, not %q",
				name,
				i + 1,
				got,
				want,
				allocator = allocator,
			)
			return drift
		}
	}
	return nil
}

// expect reports whether the column holds want, and fails the statement
// with Mismatch when it does not.
@(private = "file")
expect :: proc(stmt: ^Stmt, col: int, want: Type) -> bool {
	got := type_of(stmt^, col)
	if got == want {
		return true
	}
	buf: [64]byte
	mismatch(stmt, fmt.bprintf(buf[:], "holds %v where %v was expected", got, want), col)
	return false
}

// mismatch fails the statement unless it has already failed, so the first
// wrong value is the one reported.
@(private = "file")
mismatch :: proc(stmt: ^Stmt, what: string, col: int) {
	if stmt.err == nil {
		stmt.err = Fault {
			code = .Mismatch,
			text = fmt.aprintf("column %s %s", name_of(stmt^, col), what, allocator = stmt.allocator),
		}
	}
}

// name_of is the column's name without a copy, for a message about to copy
// it anyway.
@(private = "file")
name_of :: proc(stmt: Stmt, col: int) -> string {
	return string(sqlite3_column_name(stmt.handle, c.int(col)))
}

// interrupt is sqlite3_interrupt: it asks the connection to abandon what it
// is running, and is the one call here meant to be made from another thread.
// The interrupted call comes back as a Fault with code Interrupt.
//
// It exists because nothing else here bounds how long a statement runs. A
// query that keeps returning rows keeps exec and next busy until it is
// interrupted; jm:sqlite3/fuzz uses this to put a deadline on a case.
interrupt :: proc(db: Db) {
	if db.handle != nil {
		sqlite3_interrupt(db.handle)
	}
}

// hooks installs the connection's change hooks, replacing any installed
// before; nil removes one. update is called for each row an INSERT,
// UPDATE or DELETE touches, with the table and rowid, bar what SQLite
// leaves out: a DELETE with no WHERE, which it truncates instead, and
// the rows a REPLACE conflict removes; commit once a
// transaction commits, which in autocommit mode is after every such
// statement; rollback when one rolls back. A caller watching for changes
// buffers what update reports and hands the buffer on at commit, since a
// change inside a transaction that rolls back never happened. The procs
// run inside SQLite with no Odin context (see ffi.odin).
hooks :: proc(db: Db, update: Update_Proc = nil, commit: Commit_Proc = nil, rollback: Rollback_Proc = nil, user: rawptr = nil) {
	sqlite3_update_hook(db.handle, update, user)
	sqlite3_commit_hook(db.handle, commit, user)
	sqlite3_rollback_hook(db.handle, rollback, user)
}

// changes is how many rows the last INSERT, UPDATE or DELETE touched.
changes :: proc(db: Db) -> i64 {
	return sqlite3_changes64(db.handle)
}

// last_id is the rowid the last INSERT on this connection assigned.
last_id :: proc(db: Db) -> i64 {
	return sqlite3_last_insert_rowid(db.handle)
}

// version is the SQLite version compiled in, such as "3.53.4".
version :: proc() -> string {
	return string(sqlite3_libversion())
}

// empty_byte backs the pointer handed to bind for an empty string or blob,
// so SQLite sees a valid address with length 0 rather than NULL.
@(private)
empty_byte: u8

// prepare_one compiles the first statement in sql and returns what followed
// it. A handle of nil with no error means sql held no statement.
@(private)
prepare_one :: proc(
	db: Db,
	sql: string,
	allocator := context.allocator,
) -> (
	stmt: Stmt,
	tail: string,
	err: Error,
) {
	stmt = Stmt {
		db        = db.handle,
		allocator = allocator,
	}
	if len(sql) == 0 {
		return stmt, "", nil
	}
	rest: [^]u8
	code := Code(
		sqlite3_prepare_v2(db.handle, raw_data(sql), c.int(len(sql)), &stmt.handle, &rest),
	)
	if code != .Ok {
		return {}, "", fault(db.handle, code, allocator)
	}
	if rest != nil {
		// rest points inside sql, so the remainder is the slice from there to
		// the end rather than a new string.
		used := int(uintptr(rest) - uintptr(raw_data(sql)))
		tail = sql[used:]
	}
	return stmt, tail, nil
}

// fault builds the error for code, preferring the connection's message over
// the generic text for the code.
@(private)
fault :: proc(db: ^Connection, code: Code, allocator: mem.Allocator) -> Error {
	msg: cstring
	extended: i32
	if db != nil {
		msg = sqlite3_errmsg(db)
		extended = i32(sqlite3_extended_errcode(db))
	}
	if msg == nil {
		msg = sqlite3_errstr(c.int(code))
	}
	text := msg == nil ? "" : strings.clone_from_cstring(msg, allocator)
	return Fault{code = code, extended = extended, text = text}
}
