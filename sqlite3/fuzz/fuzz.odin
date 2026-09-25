/*
Package fuzz is the jm:sqlite3 suite for jm:fuzz: the promises the bindings
make, checked against generated values and damaged SQL.

	report := fuzz.run({seed = 1, iterations = 10_000})

jm:fuzz owns the machinery — seeding, budgets, shrinking, the corpus, the
deadline on a case. What lives here is what is true of SQLite and nothing
else:

	round_trip   a bound value reads back as itself, whatever bytes it holds
	injection    a value is never parsed as SQL, however much it looks like it
	damaged_sql  broken SQL faults and leaves the connection usable
	arity        an argument list that does not match the statement is refused
	atomicity    a transaction that fails leaves nothing behind
	reuse        bind, step and reset in any order keep a statement honest

The properties read every row before comparing any of them, for the reason
jm:sqlite3's own doc comment gives for cloning in text and blob: a column's
bytes belong to SQLite until the next step. Comparing inside the loop is the
shape that cannot notice when they stop being copied; see collect.
*/
package sqlite3_fuzz

import "core:fmt"
import "core:math"
import "core:slice"
import "core:strings"

import harness "jm:fuzz"
import "jm:sqlite3"

// properties is package level because a Suite holds a slice, which has to
// outlive the call that hands the Suite back.
properties := []harness.Property(sqlite3.Db) {
	{"round_trip", round_trip},
	{"injection", injection},
	{"damaged_sql", damaged_sql},
	{"arity", arity},
	{"atomicity", atomicity},
	{"reuse", reuse},
}

// suite is jm:sqlite3 and its promises, ready for harness.run.
suite :: proc() -> harness.Suite(sqlite3.Db) {
	return harness.Suite(sqlite3.Db) {
		name = "sqlite3",
		setup = open,
		teardown = shut,
		cancel = stop,
		properties = properties,
	}
}

// CORPUS is where this suite's regressions live, relative to the repository
// root. A case that failed once is kept there and replayed on every run.
CORPUS :: "sqlite3/fuzz/corpus"

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

// open gives each case a private in-memory database, discarded on close.
open :: proc() -> (sqlite3.Db, bool) {
	db, err := sqlite3.open(sqlite3.MEMORY)
	return db, err == nil
}

shut :: proc(db: ^sqlite3.Db) {
	sqlite3.close(db)
}

// stop is what the deadline calls: a query with no end runs until something
// interrupts it.
stop :: proc(db: sqlite3.Db) {
	sqlite3.interrupt(db)
}

// round_trip binds one generated value and reads it back. Whatever bytes go
// in come out, and the storage class is the one the value asked for.
round_trip :: proc(db: sqlite3.Db, src: ^harness.Source) -> (detail: string, ok: bool) {
	// An untyped column keeps whatever class it is given, with no affinity
	// to convert it on the way in.
	if err := sqlite3.exec(db, `CREATE TABLE t(v)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	v := value(src)
	if err := sqlite3.exec_args(db, `INSERT INTO t VALUES (?)`, v); err != nil {
		return fmt.tprintf("insert %s: %v", show(v), err), false
	}
	rows, qerr := sqlite3.query(db, `SELECT v FROM t`)
	if qerr != nil {
		return fmt.tprintf("select: %v", qerr), false
	}
	defer sqlite3.finish(&rows)
	if !sqlite3.next(&rows) {
		return fmt.tprintf("%s vanished", show(v)), false
	}

	want := expected_type(v)
	if got := sqlite3.type_of(rows, 0); got != want {
		return fmt.tprintf("%s stored as %v, wanted %v", show(v), got, want), false
	}
	switch bound in v {
	case i64:
		if got := sqlite3.integer(rows, 0); got != bound {
			return fmt.tprintf("%d read back as %d", bound, got), false
		}
	case f64:
		// SQLite has no NaN: binding one stores NULL, which expected_type
		// already accounts for.
		if !math.is_nan(bound) {
			if got := sqlite3.real(rows, 0); got != bound {
				return fmt.tprintf("%v read back as %v", bound, got), false
			}
		}
	case bool:
		if got := sqlite3.boolean(rows, 0); got != bound {
			return fmt.tprintf("%v read back as %v", bound, got), false
		}
	case string:
		if got := sqlite3.text(rows, 0); got != bound {
			return fmt.tprintf("%s read back as %s", show(v), harness.show(got)), false
		}
	case []byte:
		got := sqlite3.blob(rows, 0)
		if len(got) != len(bound) || !slice.equal(got, bound) {
			return fmt.tprintf("%s read back as %s", show(v), harness.show(got)), false
		}
	}
	return "", true
}

// injection writes generated text that is trying to look like SQL, and checks
// that none of it was parsed as any. The canary table is what a successful
// injection would drop.
injection :: proc(db: sqlite3.Db, src: ^harness.Source) -> (detail: string, ok: bool) {
	if err := sqlite3.exec(db, `CREATE TABLE t(v TEXT); CREATE TABLE canary(x)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	count := harness.integer_in(src, 1, 16)
	written := make([]string, count, context.temp_allocator)
	for i in 0 ..< count {
		written[i] = sql_shaped_text(src)
		if err := sqlite3.exec_args(db, `INSERT INTO t VALUES (?)`, written[i]); err != nil {
			return fmt.tprintf("insert %s: %v", harness.show(written[i]), err), false
		}
	}

	got, gerr := collect(db, `SELECT v FROM t ORDER BY rowid`)
	if gerr != "" {
		return gerr, false
	}
	if len(got) != count {
		return fmt.tprintf("wrote %d rows, read %d", count, len(got)), false
	}
	for want, i in written {
		if got[i] != want {
			return fmt.tprintf(
					"row %d: %s read back as %s",
					i,
					harness.show(want),
					harness.show(got[i]),
				),
				false
		}
	}

	// Nothing bound may have reached the parser, so the canary is untouched.
	check, cerr := sqlite3.query(db, `SELECT count(*) FROM canary`)
	if cerr != nil {
		return fmt.tprintf("canary gone: %v", cerr), false
	}
	defer sqlite3.finish(&check)
	if !sqlite3.next(&check) {
		return "canary unreadable", false
	}
	return "", true
}

// damaged_sql feeds the parser text it should refuse. A refusal is a Fault,
// never a crash, and the connection still works afterwards.
damaged_sql :: proc(db: sqlite3.Db, src: ^harness.Source) -> (detail: string, ok: bool) {
	bad, how := harness.damage_text(src, STATEMENTS, context.temp_allocator)
	// Either outcome is allowed: damage can land on something valid. What is
	// not allowed is a crash, or a connection that stops answering.
	_ = sqlite3.exec(db, bad)
	if rows, err := sqlite3.query(db, bad); err == nil {
		for sqlite3.next(&rows) {
			// Reading every column of every row is where a wrong column
			// count or a stale pointer would show.
			for col in 0 ..< sqlite3.column_count(rows) {
				_ = sqlite3.type_of(rows, col)
				_ = sqlite3.text(rows, col)
				_ = sqlite3.blob(rows, col)
			}
		}
		_ = sqlite3.finish(&rows)
	}

	live, lerr := sqlite3.query(db, `SELECT 1`)
	if lerr != nil {
		return fmt.tprintf("connection lost after %v %s: %v", how, harness.show(bad), lerr), false
	}
	defer sqlite3.finish(&live)
	if !sqlite3.next(&live) || sqlite3.integer(live, 0) != 1 {
		return fmt.tprintf("connection unusable after %v %s", how, harness.show(bad)), false
	}
	return "", true
}

// arity checks the guard in bind: a list that does not match the statement's
// parameter count is refused, and one that matches is accepted.
arity :: proc(db: sqlite3.Db, src: ^harness.Source) -> (detail: string, ok: bool) {
	want := harness.integer_in(src, 1, 8)
	marks := make([dynamic]string, context.temp_allocator)
	for _ in 0 ..< want {
		append(&marks, "?")
	}
	sql := fmt.tprintf("SELECT %s", strings.join(marks[:], ", ", context.temp_allocator))
	stmt, perr := sqlite3.prepare(db, sql)
	if perr != nil {
		return fmt.tprintf("prepare %s: %v", sql, perr), false
	}
	defer sqlite3.finish(&stmt)

	give := harness.integer_in(src, 0, 9)
	args := make([]sqlite3.Value, give, context.temp_allocator)
	for i in 0 ..< give {
		args[i] = value(src)
	}
	err := sqlite3.bind(&stmt, ..args)
	if give == want && err != nil {
		return fmt.tprintf("%d parameters, %d args, refused: %v", want, give, err), false
	}
	if give != want {
		fault, is_fault := err.(sqlite3.Fault)
		if !is_fault {
			return fmt.tprintf("%d parameters, %d args, accepted", want, give), false
		}
		if fault.code != .Range {
			return fmt.tprintf("%d parameters, %d args, gave %v", want, give, fault.code), false
		}
	}
	return "", true
}

// atomicity rolls a transaction back from a random point and checks that the
// table holds exactly what it held before.
atomicity :: proc(db: sqlite3.Db, src: ^harness.Source) -> (detail: string, ok: bool) {
	if err := sqlite3.exec(db, `CREATE TABLE t(v UNIQUE)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	before := harness.integer_in(src, 0, 8)
	for i in 0 ..< before {
		if err := sqlite3.exec_args(db, `INSERT INTO t VALUES (?)`, i64(i)); err != nil {
			return fmt.tprintf("seed row %d: %v", i, err), false
		}
	}

	// The body writes a random number of fresh rows, then collides with one
	// that is already there, which fails the transaction wherever it is.
	doomed := Batch {
		fresh         = harness.integer_in(src, 0, 8),
		collide_with  = before > 0 ? i64(harness.integer_in(src, 0, before)) : 0,
		has_collision = before > 0,
	}
	err := sqlite3.transact(db, batch_body, &doomed)
	if doomed.has_collision && err == nil {
		return "the colliding transaction was not refused", false
	}

	rows, qerr := sqlite3.query(db, `SELECT count(*) FROM t`)
	if qerr != nil {
		return fmt.tprintf("count: %v", qerr), false
	}
	defer sqlite3.finish(&rows)
	if !sqlite3.next(&rows) {
		return "count returned no row", false
	}
	got := sqlite3.integer(rows, 0)
	want := i64(before)
	if !doomed.has_collision {
		// With nothing to collide with the body commits, so its rows stay.
		want += i64(doomed.fresh)
	}
	if got != want {
		return fmt.tprintf("%d rows after rollback, wanted %d", got, want), false
	}
	return "", true
}

// Batch is what batch_body should write inside a transaction. It travels
// through transact's user pointer rather than a package global, so two runs
// in one process cannot rewrite each other's expectations.
@(private)
Batch :: struct {
	fresh:         int,
	collide_with:  i64,
	has_collision: bool,
}

@(private)
batch_body :: proc(db: sqlite3.Db, user: rawptr) -> sqlite3.Error {
	doomed := (^Batch)(user)
	for i in 0 ..< doomed.fresh {
		sqlite3.exec_args(db, `INSERT INTO t VALUES (?)`, i64(1000 + i)) or_return
	}
	if doomed.has_collision {
		sqlite3.exec_args(db, `INSERT INTO t VALUES (?)`, doomed.collide_with) or_return
	}
	return nil
}

// reuse drives one prepared statement through a run of binds, steps and
// resets, and checks the rows that came out are the rows put in.
reuse :: proc(db: sqlite3.Db, src: ^harness.Source) -> (detail: string, ok: bool) {
	if err := sqlite3.exec(db, `CREATE TABLE t(v)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	stmt, perr := sqlite3.prepare(db, `INSERT INTO t VALUES (?)`)
	if perr != nil {
		return fmt.tprintf("prepare: %v", perr), false
	}

	rounds := harness.integer_in(src, 1, 32)
	sent := make([dynamic]string, context.temp_allocator)
	for _ in 0 ..< rounds {
		v := sql_shaped_text(src)
		if err := sqlite3.bind(&stmt, v); err != nil {
			sqlite3.finish(&stmt)
			return fmt.tprintf("bind %s: %v", harness.show(v), err), false
		}
		if sqlite3.next(&stmt) {
			sqlite3.finish(&stmt)
			return "an insert returned a row", false
		}
		if err := sqlite3.reset(&stmt); err != nil {
			sqlite3.finish(&stmt)
			return fmt.tprintf("reset: %v", err), false
		}
		append(&sent, v)
	}
	if err := sqlite3.finish(&stmt); err != nil {
		return fmt.tprintf("finish: %v", err), false
	}

	got, gerr := collect(db, `SELECT v FROM t ORDER BY rowid`)
	if gerr != "" {
		return gerr, false
	}
	if len(got) != len(sent) {
		return fmt.tprintf("sent %d rows, read %d", len(sent), len(got)), false
	}
	for want, i in sent {
		if got[i] != want {
			return fmt.tprintf(
					"row %d: %s read back as %s",
					i,
					harness.show(want),
					harness.show(got[i]),
				),
				false
		}
	}
	return "", true
}

// collect reads a one-column query into a slice and only then compares
// anything, which is the whole point: a column read that handed back SQLite's
// own memory still looks right while the cursor is on the row, and turns into
// the next row's bytes once it has moved.
@(private)
collect :: proc(db: sqlite3.Db, sql: string) -> (out: []string, detail: string) {
	rows, err := sqlite3.query(db, sql)
	if err != nil {
		return nil, fmt.tprintf("select: %v", err)
	}
	read := make([dynamic]string, context.temp_allocator)
	for sqlite3.next(&rows) {
		append(&read, sqlite3.text(rows, 0))
	}
	if ferr := sqlite3.finish(&rows); ferr != nil {
		return nil, fmt.tprintf("finish: %v", ferr)
	}
	return read[:], ""
}

// expected_type is the storage class SQLite should give a bound value.
@(private)
expected_type :: proc(v: sqlite3.Value) -> sqlite3.Type {
	switch bound in v {
	case i64:
		return .Integer
	case bool:
		return .Integer
	case f64:
		// A NaN has no SQLite representation, so it lands as NULL.
		return math.is_nan(bound) ? .Null : .Real
	case string:
		return .Text
	case []byte:
		return .Blob
	}
	return .Null
}

// value draws one bound parameter. A zero source gives NULL, the simplest
// thing a column can hold.
value :: proc(src: ^harness.Source) -> sqlite3.Value {
	switch harness.integer_in(src, 0, 6) {
	case 1:
		return harness.integer(src)
	case 2:
		return harness.real(src)
	case 3:
		return harness.boolean(src)
	case 4:
		return sql_shaped_text(src)
	case 5:
		return harness.bytes(src, 64, context.temp_allocator)
	}
	return nil
}

// PIECES is what a value holds when it is trying to escape the parameter it
// was bound to.
PIECES := []string {
	"",
	"a",
	" ",
	"'",
	`"`,
	"`",
	";",
	"--",
	"/*",
	"*/",
	"\\",
	"\n",
	"\r",
	"\t",
	"\x00",
	"%",
	"_",
	"?",
	"$1",
	":name",
	"DROP TABLE t",
	"' OR '1'='1",
	"'; DROP TABLE canary; --",
	"'||(SELECT name FROM sqlite_schema)||'",
	"' UNION SELECT * FROM canary --",
	"x'41'",
	"é",
	"\U0001F600",
	"\xff\xfe",
}

// sql_shaped_text draws text that is trying hard to be mistaken for SQL.
sql_shaped_text :: proc(src: ^harness.Source) -> string {
	return harness.text(src, PIECES, 24, context.temp_allocator)
}

// STATEMENTS is the well-formed corpus damage works from.
STATEMENTS := []string {
	`SELECT 1`,
	`CREATE TABLE z(a, b)`,
	`INSERT INTO z VALUES (1, 2)`,
	`SELECT a FROM z WHERE b = ?`,
	`BEGIN`,
	`PRAGMA journal_mode`,
	// The LIMIT is load-bearing. A recursive CTE is worth feeding to the
	// parser, but a damaged one can recurse without end, and a bound keeps
	// this corpus entry from relying on the deadline.
	`WITH r(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM r WHERE n < 3) SELECT n FROM r LIMIT 4`,
	`SELECT count(*) FROM sqlite_schema`,
}

// show renders a bound value for a failure report.
show :: proc(v: sqlite3.Value) -> string {
	switch bound in v {
	case i64:
		return fmt.tprintf("i64(%d)", bound)
	case f64:
		return fmt.tprintf("f64(%v / %016x)", bound, transmute(u64)bound)
	case bool:
		return fmt.tprintf("bool(%v)", bound)
	case string:
		return fmt.tprintf("text(%s)", harness.show(bound))
	case []byte:
		return fmt.tprintf("blob(%s)", harness.show(bound))
	}
	return "NULL"
}
