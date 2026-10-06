/*
The raw C API: the subset of sqlite3.h the wrapper needs, under the C names,
exported so a caller that needs an interface the wrapper does not cover can
reach for it. The wrapper in sqlite3.odin is what scripts should use. The
declarations track the vendored header, sqlite3.h 3.53.4.

The library is the amalgamation under vendor/, compiled into lib/ by the
justfile's `sqlite` recipe, which is also where the compile-time options and
the reason for each are written down. The archive path below is relative to
this directory, which is what puts lib/ here rather than in build/;
docs/sqlite.md records that and what `just check` does without it.
*/
package sqlite3

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "lib/sqlite3.lib"
} else when ODIN_OS == .Darwin {
	// libm and libpthread are libSystem, which Odin links already.
	foreign import lib "lib/sqlite3.a"
} else {
	@(extra_linker_flags = "-lpthread -lm")
	foreign import lib "lib/sqlite3.a"
}

// Connection is sqlite3, the open database handle. SQLite owns the memory.
Connection :: struct {}

// Statement is sqlite3_stmt, one compiled statement. SQLite owns the memory.
Statement :: struct {}

// TRANSIENT tells a bind call to copy the bytes it was handed, because Odin
// owns them and may free or move them before the statement runs.
TRANSIENT :: rawptr(~uintptr(0))

// Flags for sqlite3_open_v2.
OPEN_READONLY  :: 0x00000001
OPEN_READWRITE :: 0x00000002
OPEN_CREATE    :: 0x00000004
OPEN_URI       :: 0x00000040

// Update_Op is what sqlite3_update_hook reports a row change as: the
// SQLITE_INSERT, SQLITE_DELETE and SQLITE_UPDATE authorizer codes.
Update_Op :: enum c.int {
	Delete = 9,
	Insert = 18,
	Update = 23,
}

// The hook procs. They run on the thread that executed the statement,
// inside SQLite, with no Odin context: set one up before calling into
// anything that needs it, and never touch the connection from inside.
// A commit hook returning non-zero turns the commit into a rollback.
Update_Proc :: proc "c" (user: rawptr, op: Update_Op, db_name, table: cstring, rowid: i64)
Commit_Proc :: proc "c" (user: rawptr) -> c.int
Rollback_Proc :: proc "c" (user: rawptr)

// Column storage classes, as sqlite3_column_type reports them.
TYPE_INTEGER :: 1
TYPE_FLOAT   :: 2
TYPE_TEXT    :: 3
TYPE_BLOB    :: 4
TYPE_NULL    :: 5

@(default_calling_convention = "c")
foreign lib {
	sqlite3_libversion :: proc() -> cstring ---
	sqlite3_errstr     :: proc(code: c.int) -> cstring ---

	sqlite3_open_v2           :: proc(filename: cstring, db: ^^Connection, flags: c.int, vfs: cstring) -> c.int ---
	sqlite3_close_v2          :: proc(db: ^Connection) -> c.int ---
	sqlite3_errmsg            :: proc(db: ^Connection) -> cstring ---
	sqlite3_extended_errcode  :: proc(db: ^Connection) -> c.int ---
	sqlite3_busy_timeout      :: proc(db: ^Connection, ms: c.int) -> c.int ---
	sqlite3_interrupt         :: proc(db: ^Connection) ---
	sqlite3_changes64         :: proc(db: ^Connection) -> i64 ---
	sqlite3_last_insert_rowid :: proc(db: ^Connection) -> i64 ---
	sqlite3_update_hook       :: proc(db: ^Connection, cb: Update_Proc, user: rawptr) -> rawptr ---
	sqlite3_commit_hook       :: proc(db: ^Connection, cb: Commit_Proc, user: rawptr) -> rawptr ---
	sqlite3_rollback_hook     :: proc(db: ^Connection, cb: Rollback_Proc, user: rawptr) -> rawptr ---

	sqlite3_prepare_v2           :: proc(db: ^Connection, sql: [^]u8, n: c.int, stmt: ^^Statement, tail: ^[^]u8) -> c.int ---
	sqlite3_finalize             :: proc(stmt: ^Statement) -> c.int ---
	sqlite3_step                 :: proc(stmt: ^Statement) -> c.int ---
	sqlite3_reset                :: proc(stmt: ^Statement) -> c.int ---
	sqlite3_clear_bindings       :: proc(stmt: ^Statement) -> c.int ---
	sqlite3_bind_parameter_count :: proc(stmt: ^Statement) -> c.int ---
	sqlite3_bind_parameter_name  :: proc(stmt: ^Statement, i: c.int) -> cstring ---
	sqlite3_stmt_readonly        :: proc(stmt: ^Statement) -> c.int ---

	sqlite3_bind_null   :: proc(stmt: ^Statement, i: c.int) -> c.int ---
	sqlite3_bind_int64  :: proc(stmt: ^Statement, i: c.int, v: i64) -> c.int ---
	sqlite3_bind_double :: proc(stmt: ^Statement, i: c.int, v: f64) -> c.int ---
	sqlite3_bind_text   :: proc(stmt: ^Statement, i: c.int, v: [^]u8, n: c.int, free: rawptr) -> c.int ---
	sqlite3_bind_blob   :: proc(stmt: ^Statement, i: c.int, v: rawptr, n: c.int, free: rawptr) -> c.int ---

	sqlite3_column_count  :: proc(stmt: ^Statement) -> c.int ---
	sqlite3_column_name   :: proc(stmt: ^Statement, col: c.int) -> cstring ---
	sqlite3_column_type   :: proc(stmt: ^Statement, col: c.int) -> c.int ---
	sqlite3_column_bytes  :: proc(stmt: ^Statement, col: c.int) -> c.int ---
	sqlite3_column_int64  :: proc(stmt: ^Statement, col: c.int) -> i64 ---
	sqlite3_column_double :: proc(stmt: ^Statement, col: c.int) -> f64 ---
	sqlite3_column_text   :: proc(stmt: ^Statement, col: c.int) -> [^]u8 ---
	sqlite3_column_blob   :: proc(stmt: ^Statement, col: c.int) -> rawptr ---

	// SQLITE_ENABLE_COLUMN_METADATA, which the justfile's `sqlite` recipe sets:
	// the table and column a result column reads, when it reads one directly.
	sqlite3_column_table_name  :: proc(stmt: ^Statement, col: c.int) -> cstring ---
	sqlite3_column_origin_name :: proc(stmt: ^Statement, col: c.int) -> cstring ---
}
