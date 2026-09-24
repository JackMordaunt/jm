/*
Package fuzz throws randomly generated values and randomly damaged SQL at
jm:sqlite3 and checks the properties that must hold whatever comes back.

	report := fuzz.run({seed = 1, iterations = 10_000})
	for f in report.failures {
		fmt.eprintf("%s failed at iteration %d: %s\n", f.property, f.iteration, f.detail)
	}

Every run is a pure function of its seed, so a failure replays exactly:
`just fuzz seed=<seed>` runs the same cases in the same order. A report names
the seed it used even when it was asked for a random one.

The properties are the promises the package makes that a test with fixed
inputs can only sample:

	round_trip      a bound value reads back as itself, whatever bytes it holds
	injection       a value is never parsed as SQL, however much it looks like it
	damaged_sql     broken SQL faults and leaves the connection usable
	arity           an argument list that does not match the statement is refused
	atomicity       a transaction that fails leaves nothing behind
	reuse           bind, step and reset in any order keep a statement honest

What this cannot see: SQLite reuses memory from its own pool, so reading a
column after the next step returns stale bytes rather than tripping
AddressSanitizer. The clone in text and blob is what prevents it, and only
round_trip's comparison catches a regression there.
*/
package fuzz

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/rand"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:thread"
import "core:time"

import "jm:sqlite3"

// Opts bounds a run. The zero value is one thousand iterations from a seed
// taken off the clock.
Opts :: struct {
	// The seed to replay. 0 takes one from the clock and reports it.
	seed:          u64,
	// How many cases to run. 0 means one thousand, or until duration runs out.
	iterations:    int,
	// Stop after this long, however many iterations are left. 0 is no limit.
	duration:      time.Duration,
	// Stop at the first failure rather than collecting them all.
	stop_on_first: bool,
	// How long one case may run before it is interrupted and reported as a
	// hang. 0 means five seconds. Nothing in SQLite bounds a statement, and
	// a recursive query can return rows without end, so a harness with no
	// watchdog stops being a harness the first time it generates one.
	case_timeout:  time.Duration,
	// Called once per property failure, and once per 1000 iterations when
	// progress is worth showing. nil is silent.
	log:           proc(format: string, args: ..any),
}

// Failure is one property that did not hold, with enough to reproduce it.
Failure :: struct {
	property:  string,
	iteration: int,
	// The seed the whole run used; replaying it reaches this case again.
	seed:      u64,
	// What differed, in full: the value bound and the value read back.
	detail:    string,
}

// Report is what a run found. Its failures are allocated in the allocator
// run was given, and belong to the caller.
Report :: struct {
	seed:       u64,
	iterations: int,
	elapsed:    time.Duration,
	failures:   []Failure,
	// A fingerprint of the randomness each case consumed. Two runs of the
	// same seed agree on it; a run that generated anything differently does
	// not. It is what makes determinism checkable when nothing failed.
	digest:     u64,
}

// watchdog interrupts a case that overruns. The mutex covers both fields, so
// the connection cannot be closed between the deadline check and the
// interrupt that follows it.
@(private)
Watchdog :: struct {
	mutex:    sync.Mutex,
	db:       sqlite3.Db,
	deadline: time.Time,
	fired:    bool,
	stop:     bool,
}

// Property is one promise, checked against a scratch database that is thrown
// away afterwards. It returns the detail of what went wrong, and whether it
// held.
Property :: struct {
	name:  string,
	check: proc(db: sqlite3.Db) -> (detail: string, ok: bool),
}

// properties is every promise a run cycles through, one per iteration.
properties := []Property {
	{"round_trip", round_trip},
	{"injection", injection},
	{"damaged_sql", damaged_sql},
	{"arity", arity},
	{"atomicity", atomicity},
	{"reuse", reuse},
}

// run cycles the properties over generated cases and reports what failed.
run :: proc(opts := Opts{}, allocator := context.allocator) -> Report {
	opts := opts
	if opts.seed == 0 {
		opts.seed = u64(time.now()._nsec) | 1
	}
	if opts.iterations == 0 {
		opts.iterations = 1000
	}

	state := rand.create(opts.seed)
	context.random_generator = runtime.default_random_generator(&state)

	dog := new(Watchdog, context.temp_allocator)
	timeout := opts.case_timeout if opts.case_timeout > 0 else 5 * time.Second
	guard := thread.create_and_start_with_poly_data2(dog, timeout, watch)
	defer {
		sync.lock(&dog.mutex)
		dog.stop = true
		sync.unlock(&dog.mutex)
		thread.join(guard)
		thread.destroy(guard)
	}

	failures := make([dynamic]Failure, allocator)
	started := time.now()
	done := 0
	digest := u64(1469598103934665603)
	for i in 0 ..< opts.iterations {
		if opts.duration > 0 && time.since(started) >= opts.duration {
			break
		}
		done = i + 1
		p := properties[i % len(properties)]

		// Each case gets its own database and its own arena, so a case can
		// neither inherit state from the last nor keep memory after it.
		arena: mem.Dynamic_Arena
		mem.dynamic_arena_init(&arena)
		defer mem.dynamic_arena_destroy(&arena)
		case_context := context
		case_context.allocator = mem.dynamic_arena_allocator(&arena)

		detail, ok := run_case(p, case_context, dog, timeout)
		// Drawn after the case, so it reflects how much randomness the case
		// used, not just which property ran.
		digest = (digest ~ rand.uint64()) * 1099511628211
		if !ok {
			// The detail was built in the case arena, which is about to go.
			f := Failure {
				property  = p.name,
				iteration = i,
				seed      = opts.seed,
				detail    = strings.clone(detail, allocator),
			}
			append(&failures, f)
			if opts.log != nil {
				opts.log("%s failed at iteration %d: %s", p.name, i, f.detail)
			}
			if opts.stop_on_first {
				break
			}
		}
		if opts.log != nil && done % 1000 == 0 {
			opts.log("%d iterations, %d failures", done, len(failures))
		}
	}
	return Report {
		seed = opts.seed,
		iterations = done,
		elapsed = time.since(started),
		failures = failures[:],
		digest = digest,
	}
}

// run_case opens the scratch database, checks one property against it and
// closes it again, under the case's own allocator.
@(private)
run_case :: proc(
	p: Property,
	case_context: runtime.Context,
	dog: ^Watchdog,
	timeout: time.Duration,
) -> (
	detail: string,
	ok: bool,
) {
	context = case_context
	db, err := sqlite3.open(sqlite3.MEMORY)
	if err != nil {
		return fmt.tprintf("open failed: %v", err), false
	}

	sync.lock(&dog.mutex)
	dog.db = db
	dog.deadline = time.time_add(time.now(), timeout)
	dog.fired = false
	sync.unlock(&dog.mutex)

	detail, ok = p.check(db)

	// Retire the connection from the watchdog before closing it, so an
	// interrupt can never land on a closed handle.
	sync.lock(&dog.mutex)
	hung := dog.fired
	dog.db = {}
	sync.unlock(&dog.mutex)
	sqlite3.close(&db)

	if hung {
		// Whatever the property made of the interrupt, the case did not
		// finish on its own, and that is the thing worth reporting.
		if detail == "" {
			return fmt.tprintf("did not finish within %v", timeout), false
		}
		return fmt.tprintf("did not finish within %v, then: %s", timeout, detail), false
	}
	return detail, ok
}

// watch interrupts a case that has run past its deadline, and keeps
// interrupting until the case retires its connection. Interrupting once is
// not enough: a property runs several statements, and the next one would
// simply hang in place of the one that was stopped.
@(private)
watch :: proc(dog: ^Watchdog, timeout: time.Duration) {
	for {
		time.sleep(10 * time.Millisecond)
		sync.lock(&dog.mutex)
		if dog.stop {
			sync.unlock(&dog.mutex)
			return
		}
		if dog.db.handle != nil && time.since(dog.deadline) > 0 {
			sqlite3.interrupt(dog.db)
			dog.fired = true
		}
		sync.unlock(&dog.mutex)
	}
}

// round_trip binds one generated value and reads it back. Whatever bytes go
// in come out, and the storage class is the one the value asked for.
round_trip :: proc(db: sqlite3.Db) -> (detail: string, ok: bool) {
	// An untyped column keeps whatever class it is given, with no affinity
	// to convert it on the way in.
	if err := sqlite3.exec(db, `CREATE TABLE t(v)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	v := value()
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
			return fmt.tprintf("%s read back as %s", show(v), show(got)), false
		}
	case []byte:
		got := sqlite3.blob(rows, 0)
		if len(got) != len(bound) || !slice.equal(got, bound) {
			return fmt.tprintf("%s read back as %s", show(v), show(got)), false
		}
	}
	return "", true
}

// injection writes generated text that is trying to look like SQL, and checks
// that none of it was parsed as any. The canary table is what a successful
// injection would drop.
injection :: proc(db: sqlite3.Db) -> (detail: string, ok: bool) {
	if err := sqlite3.exec(db, `CREATE TABLE t(v TEXT); CREATE TABLE canary(x)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	count := rand.int_range(1, 16)
	written := make([]string, count, context.temp_allocator)
	for i in 0 ..< count {
		written[i] = sql_shaped_text()
		if err := sqlite3.exec_args(db, `INSERT INTO t VALUES (?)`, written[i]); err != nil {
			return fmt.tprintf("insert %s: %v", show(written[i]), err), false
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
			return fmt.tprintf("row %d: %s read back as %s", i, show(want), show(got[i])), false
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
damaged_sql :: proc(db: sqlite3.Db) -> (detail: string, ok: bool) {
	bad := damaged_statement()
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
		return fmt.tprintf("connection lost after %s: %v", show(bad), lerr), false
	}
	defer sqlite3.finish(&live)
	if !sqlite3.next(&live) || sqlite3.integer(live, 0) != 1 {
		return fmt.tprintf("connection unusable after %s", show(bad)), false
	}
	return "", true
}

// arity checks the guard in bind: a list that does not match the statement's
// parameter count is refused, and one that matches is accepted.
arity :: proc(db: sqlite3.Db) -> (detail: string, ok: bool) {
	want := rand.int_range(1, 8)
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

	give := rand.int_range(0, 9)
	args := make([]sqlite3.Value, give, context.temp_allocator)
	for i in 0 ..< give {
		args[i] = value()
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
atomicity :: proc(db: sqlite3.Db) -> (detail: string, ok: bool) {
	if err := sqlite3.exec(db, `CREATE TABLE t(v UNIQUE)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	before := rand.int_range(0, 8)
	for i in 0 ..< before {
		if err := sqlite3.exec_args(db, `INSERT INTO t VALUES (?)`, i64(i)); err != nil {
			return fmt.tprintf("seed row %d: %v", i, err), false
		}
	}

	// The body writes a random number of fresh rows, then collides with one
	// that is already there, which fails the transaction wherever it is.
	doomed := Batch {
		fresh         = rand.int_range(0, 8),
		collide_with  = before > 0 ? i64(rand.int_range(0, before)) : 0,
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
// in one process cannot rewrite each other's expectations: a package global
// here made the tests fail whenever two of them ran at once.
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

// reuse drives one prepared statement through a random sequence of binds,
// steps and resets, and checks the rows that came out are the rows put in.
reuse :: proc(db: sqlite3.Db) -> (detail: string, ok: bool) {
	if err := sqlite3.exec(db, `CREATE TABLE t(v)`); err != nil {
		return fmt.tprintf("create: %v", err), false
	}
	stmt, perr := sqlite3.prepare(db, `INSERT INTO t VALUES (?)`)
	if perr != nil {
		return fmt.tprintf("prepare: %v", perr), false
	}

	rounds := rand.int_range(1, 32)
	sent := make([dynamic]string, context.temp_allocator)
	for _ in 0 ..< rounds {
		v := text()
		if err := sqlite3.bind(&stmt, v); err != nil {
			sqlite3.finish(&stmt)
			return fmt.tprintf("bind %s: %v", show(v), err), false
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
			return fmt.tprintf("row %d: %s read back as %s", i, show(want), show(got[i])), false
		}
	}
	return "", true
}

// collect reads a one-column query into a slice and only then compares
// anything, which is the whole point: a column read that handed back SQLite's
// own memory still looks right while the cursor is on the row, and turns into
// the next row's bytes once it has moved. Comparing inside the loop cannot
// see that, so nothing here does.
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
	// Every value was read before the statement was finalized, so anything
	// still pointing into SQLite's memory is now pointing at whatever took
	// its place.
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

// value generates one bound parameter, weighted towards the edges of each
// type rather than the middle.
value :: proc() -> sqlite3.Value {
	switch rand.int_range(0, 6) {
	case 0:
		return integer()
	case 1:
		return real()
	case 2:
		return rand.int_range(0, 2) == 1
	case 3:
		return text()
	case 4:
		return bytes()
	}
	return nil
}

// integer generates an i64, often one of the values that overflow or sign
// flip if a conversion is wrong somewhere.
integer :: proc() -> i64 {
	edges := []i64 {
		0,
		1,
		-1,
		127,
		128,
		255,
		256,
		-128,
		-129,
		65535,
		65536,
		2147483647,
		2147483648,
		-2147483648,
		-2147483649,
		max(i64),
		min(i64),
		max(i64) - 1,
		min(i64) + 1,
	}
	if rand.int_range(0, 2) == 0 {
		return rand.choice(edges)
	}
	return i64(rand.uint64())
}

// real generates an f64, including the values SQLite has no room for.
real :: proc() -> f64 {
	edges := []f64 {
		0,
		-0,
		1,
		-1,
		0.1,
		math.INF_F64,
		math.NEG_INF_F64,
		math.nan_f64(),
		max(f64),
		min(f64),
		1e308,
		1e-308,
	}
	if rand.int_range(0, 2) == 0 {
		return rand.choice(edges)
	}
	return transmute(f64)rand.uint64()
}

// text generates a string from the bytes that break SQL built by hand, plus
// multi-byte runes and, deliberately, byte sequences that are not UTF-8.
text :: proc() -> string {
	pieces := []string {
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
		"é",
		"\U0001F600",
		"\xff\xfe",
		"a",
		" ",
		"",
	}
	n := rand.int_range(0, 24)
	b := strings.builder_make(context.temp_allocator)
	for _ in 0 ..< n {
		strings.write_string(&b, rand.choice(pieces))
	}
	return strings.to_string(b)
}

// sql_shaped_text generates text that is trying hard to be mistaken for SQL.
sql_shaped_text :: proc() -> string {
	attacks := []string {
		"'; DROP TABLE canary; --",
		"' OR 1=1; --",
		"'||(SELECT name FROM sqlite_schema)||'",
		"\"; DROP TABLE canary; \"",
		"'); DELETE FROM t; --",
		"x'41'",
		"' UNION SELECT * FROM canary --",
		"?; DROP TABLE canary",
		"$1; DROP TABLE canary",
	}
	if rand.int_range(0, 2) == 0 {
		return rand.choice(attacks)
	}
	return strings.concatenate({rand.choice(attacks), text()}, context.temp_allocator)
}

// bytes generates a blob, which unlike text has no encoding to respect.
bytes :: proc() -> []byte {
	n := rand.int_range(0, 64)
	out := make([]byte, n, context.temp_allocator)
	_ = rand.read(out)
	return out
}

// damaged_statement generates SQL the parser should refuse: a valid statement
// with a piece cut out or a byte flipped, or simply a run of random bytes.
damaged_statement :: proc() -> string {
	valid := []string {
		`SELECT 1`,
		`CREATE TABLE z(a, b)`,
		`INSERT INTO z VALUES (1, 2)`,
		`SELECT a FROM z WHERE b = ?`,
		`BEGIN`,
		`PRAGMA journal_mode`,
		// The LIMIT is load-bearing. A recursive CTE is worth feeding to
		// the parser, but a damaged one can recurse without end, and a
		// bound keeps this corpus entry from relying on the watchdog.
		`WITH r(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM r WHERE n < 3) SELECT n FROM r LIMIT 4`,
		`SELECT count(*) FROM sqlite_schema`,
	}
	switch rand.int_range(0, 4) {
	case 0:
		return text()
	case 1:
		// A byte flipped somewhere in the middle.
		src := rand.choice(valid)
		if len(src) == 0 {
			return src
		}
		out := make([]byte, len(src), context.temp_allocator)
		copy(out, src)
		out[rand.int_range(0, len(out))] = byte(rand.int_range(0, 256))
		return string(out)
	case 2:
		// Truncated at a random point, which is where a parser that reads
		// past its input would fall off.
		src := rand.choice(valid)
		return src[:rand.int_range(0, len(src) + 1)]
	}
	return strings.concatenate({rand.choice(valid), text()}, context.temp_allocator)
}

// show renders a value so a failure can be read and retyped, with the bytes
// spelled out rather than printed raw.
show :: proc {
	show_value,
	show_string,
	show_bytes,
}

show_value :: proc(v: sqlite3.Value) -> string {
	switch bound in v {
	case i64:
		return fmt.tprintf("i64(%d)", bound)
	case f64:
		return fmt.tprintf("f64(%v / %08x)", bound, transmute(u64)bound)
	case bool:
		return fmt.tprintf("bool(%v)", bound)
	case string:
		return show_string(bound)
	case []byte:
		return show_bytes(bound)
	}
	return "nil"
}

show_string :: proc(s: string) -> string {
	return fmt.tprintf("string(%d bytes, %02x)", len(s), transmute([]byte)s)
}

show_bytes :: proc(b: []byte) -> string {
	return fmt.tprintf("blob(%d bytes, %02x)", len(b), b)
}
