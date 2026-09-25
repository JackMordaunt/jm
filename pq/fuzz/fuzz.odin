/*
Package fuzz is the jm:pq suite for jm:fuzz: the promises the bindings make,
checked against a real server with generated SQL, damaged SQL, and bytes that
were never SQL at all.

	report := fuzz.run({seed = 1, iterations = 10_000})

jm:fuzz owns the machinery — seeding, budgets, shrinking, the corpus, running
a case in a child process. What lives here is what is true of jm:pq:

	survives               any bytes as a statement: refused or run, the connection lives
	literal_round_trip     SELECT <escape_literal(x)> gives back x, byte for byte
	param_round_trip       SELECT $1 with x as the argument gives back x, byte for byte
	identifier_round_trip  a table named escape_identifier(x) can be created and read
	error_sane             a failure has a message and a five-character SQLSTATE
	nul_safe               a NUL is refused with its offset, never cut off at it

It needs a server, and brings up the same throwaway one jm:pq's tests use,
through jm:pq/testdb. Where that cannot be done — no initdb on PATH — run says
why and returns an empty report rather than a failure, so `jm-fuzz` with no
suite named still runs every other suite on a machine without PostgreSQL.

Each case gets its own connection, so no case can inherit a session setting or
a transaction from the one before it, and the tables it makes are temporary
and die with it. The connection is an ordinary role rather than the
superuser, which keeps a generated statement away from COPY TO PROGRAM and
ALTER SYSTEM, and carries a statement_timeout: the suite has no cancel,
because binding PQcancel for it alone would widen the binding for the sake of
its test, and the server can bound a statement by itself.

The round trips hold for valid UTF-8 without a NUL. The connection's client
encoding is UTF-8, so text that is not is the server's to refuse, and a NUL
is the binding's; for either the property only demands that nothing comes
back altered.
*/
package pq_fuzz

import "base:runtime"
import "core:fmt"
import "core:strings"
import "core:sync"
import "core:unicode/utf8"

import harness "jm:fuzz"
import "jm:pq"
import "jm:pq/testdb"

// ROLE is the unprivileged role every case connects as.
ROLE :: "jm_fuzz"

// CONNINFO is what a case connects with; everything else is testdb's
// environment. Two seconds is far longer than any generated statement needs.
CONNINFO :: "user=" + ROLE + " options='-c statement_timeout=2000 -c lock_timeout=2000'"

// properties is package level because a Suite holds a slice, which has to
// outlive the call that hands the Suite back.
properties := []harness.Property(^pq.Conn) {
	{"survives", survives},
	{"literal_round_trip", literal_round_trip},
	{"param_round_trip", param_round_trip},
	{"identifier_round_trip", identifier_round_trip},
	{"error_sane", error_sane},
	{"nul_safe", nul_safe},
}

// suite is jm:pq and its promises, ready for harness.run.
suite :: proc() -> harness.Suite(^pq.Conn) {
	return harness.Suite(^pq.Conn) {
		name = "pq",
		setup = open,
		teardown = shut,
		properties = properties,
	}
}

// CORPUS is where this suite's regressions live, relative to the repository
// root. A case that failed once is kept there and replayed on every run.
CORPUS :: "pq/fuzz/corpus"

// run checks the suite against the throwaway server, or says why it cannot
// and returns an empty report.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	if why, ready := prepare(); !ready {
		fmt.eprintfln("pq: skipped, no server to fuzz against: %s", why)
		return {}
	}
	return harness.run(suite(), opts, allocator)
}

// prepare brings the server up and makes the role cases connect as, once per
// process however many threads ask: two sessions creating the same role at
// once collide in the catalog. A child process finds both already done.
prepare :: proc() -> (why: string, ready: bool) {
	sync.mutex_lock(&preparation.mutex)
	defer sync.mutex_unlock(&preparation.mutex)
	if !preparation.done {
		preparation.done = true
		preparation.why, preparation.ready = make_role()
	}
	return preparation.why, preparation.ready
}

@(private)
preparation: struct {
	mutex: sync.Mutex,
	done:  bool,
	ready: bool,
	why:   string,
}

@(private)
make_role :: proc() -> (why: string, ready: bool) {
	if ok, reason := testdb.start(); !ok {
		return reason, false
	}
	admin, err := pq.connect(allocator = context.temp_allocator)
	if err != nil {
		return fmt.aprintf("%v", err, allocator = runtime.heap_allocator()), false
	}
	defer pq.close(admin)
	_, err = pq.exec(
		admin,
		`DO $$ BEGIN CREATE ROLE ` + ROLE + ` LOGIN; EXCEPTION WHEN duplicate_object THEN NULL; END $$`,
		allocator = context.temp_allocator,
	)
	if err != nil {
		return fmt.aprintf("%v", err, allocator = runtime.heap_allocator()), false
	}
	return "", true
}

// open gives a case its own connection.
open :: proc() -> (^pq.Conn, bool) {
	conn, err := pq.connect(CONNINFO)
	return conn, err == nil
}

shut :: proc(conn: ^^pq.Conn) {
	pq.close(conn^)
	conn^ = nil
}

// Origin is where a case's SQL came from, so a failure says which source
// found it.
Origin :: enum {
	// A SELECT assembled by generate. A zero source draws this one.
	Generated,
	// A statement from WELL_FORMED with jm:fuzz's damage applied.
	Damaged,
	// Bytes that were never SQL.
	Raw,
}

// statement draws one case's SQL, weighted so most cases reach the server's
// success path as well as its parser's failure path.
statement :: proc(src: ^harness.Source) -> (sql: string, from: Origin) {
	switch harness.integer_in(src, 0, 8) {
	case 4, 5, 6:
		text, _ := harness.damage_text(src, WELL_FORMED, context.temp_allocator)
		return text, .Damaged
	case 7:
		return string(harness.bytes(src, 128, context.temp_allocator)), .Raw
	case:
		return generate(src), .Generated
	}
}

// value draws the text a round trip carries: pieces chosen to break SQL
// built by hand, or raw bytes.
value :: proc(src: ^harness.Source) -> string {
	if harness.integer_in(src, 0, 4) == 3 {
		return string(harness.bytes(src, 64, context.temp_allocator))
	}
	return harness.text(src, PIECES, 12, context.temp_allocator)
}

// survives runs whatever was drawn inside a transaction, then rolls it back
// and checks the connection still answers. A call answers exactly once — a
// Result or a Fault — and a Fault always says something.
survives :: proc(conn: ^pq.Conn, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := statement(src)
	if _, err := pq.exec(conn, "BEGIN"); err != nil {
		return fmt.tprintf("BEGIN: %v", err), false
	}
	res, err := pq.exec(conn, sql)
	if err != nil {
		f := err.(pq.Fault)
		if f.message == "" {
			return fmt.tprintf("%v %s: a refusal with nothing to say", from, harness.show(sql)), false
		}
	} else {
		for row, i in res.rows {
			if len(row) != len(res.columns) {
				return fmt.tprintf(
						"%v %s: row %d has %d values for %d columns",
						from,
						harness.show(sql),
						i,
						len(row),
						len(res.columns),
					),
					false
			}
		}
	}
	// The statement may have ended the transaction itself, and ROLLBACK
	// outside one only warns.
	if _, rerr := pq.exec(conn, "ROLLBACK"); rerr != nil {
		return fmt.tprintf("%v %s: ROLLBACK afterwards: %v", from, harness.show(sql), rerr), false
	}
	check, cerr := pq.exec(conn, "SELECT 1")
	if cerr != nil || len(check.rows) != 1 {
		return fmt.tprintf("%v %s: the connection stopped answering: %v", from, harness.show(sql), cerr),
			false
	}
	if s := pq.transaction_status(conn); s != .Idle {
		return fmt.tprintf("%v %s: left the connection %v", from, harness.show(sql), s), false
	}
	return "", true
}

// literal_round_trip quotes x with escape_literal and selects it. Whatever
// comes back must be x, and valid UTF-8 without a NUL must come back.
literal_round_trip :: proc(conn: ^pq.Conn, src: ^harness.Source) -> (detail: string, ok: bool) {
	x := value(src)
	lit, err := pq.escape_literal(conn, x)
	if err != nil {
		if acceptable(x) {
			return fmt.tprintf("%s: escape_literal refused it: %v", harness.show(x), err), false
		}
		return "", true
	}
	res, qerr := pq.exec(conn, strings.concatenate({"SELECT ", lit}, context.temp_allocator))
	return compare(x, lit, res, qerr)
}

// param_round_trip sends x as $1 and selects it back.
param_round_trip :: proc(conn: ^pq.Conn, src: ^harness.Source) -> (detail: string, ok: bool) {
	x := value(src)
	res, err := pq.exec(conn, "SELECT $1", {x})
	return compare(x, "$1", res, err)
}

// identifier_round_trip names a table with escape_identifier(x) and reads it
// back. The server may refuse the name — an empty identifier — but a table it
// created must be readable under the same quoted name, and the catalog must
// hold x itself when x fits in the 63 bytes a name keeps: NAMEDATALEN - 1 in
// a stock build, which is what testdb runs.
identifier_round_trip :: proc(conn: ^pq.Conn, src: ^harness.Source) -> (detail: string, ok: bool) {
	x := value(src)
	id, err := pq.escape_identifier(conn, x)
	if err != nil {
		if acceptable(x) {
			return fmt.tprintf("%s: escape_identifier refused it: %v", harness.show(x), err), false
		}
		return "", true
	}
	create := strings.concatenate({"CREATE TEMP TABLE ", id, " (v int)"}, context.temp_allocator)
	if _, cerr := pq.exec(conn, create); cerr != nil {
		f := cerr.(pq.Fault)
		// The two refusals a quoted name can earn, each checked against its
		// cause: 42601, a syntax error, for the empty identifier `""`, and
		// 22021 for text that is not UTF-8. Any other refusal is the
		// quoting's fault.
		if f.sqlstate == "42601" && x == "" {
			return "", true
		}
		if f.sqlstate == "22021" && !utf8.valid_string(x) {
			return "", true
		}
		return fmt.tprintf("%s quoted as %s: create refused: %v", harness.show(x), id, cerr), false
	}
	sel := strings.concatenate({"SELECT v FROM ", id}, context.temp_allocator)
	if _, serr := pq.exec(conn, sel); serr != nil {
		return fmt.tprintf("%s quoted as %s: created but not readable: %v", harness.show(x), id, serr),
			false
	}
	if len(x) <= 63 {
		names, nerr := pq.exec(conn, `SELECT relname FROM pg_class WHERE relnamespace = pg_my_temp_schema()`)
		if nerr != nil {
			return fmt.tprintf("catalog: %v", nerr), false
		}
		if len(names.rows) != 1 || (names.rows[0][0].? or_else "") != x {
			return fmt.tprintf(
					"%s quoted as %s: the catalog holds %v",
					harness.show(x),
					id,
					names.rows,
				),
				false
		}
	}
	return "", true
}

// error_sane checks what a failure says. squeal branches on the SQLSTATE, so
// every failure the server reports has to carry one of the right shape.
error_sane :: proc(conn: ^pq.Conn, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := statement(src)
	if strings.index_byte(sql, 0) >= 0 {
		// The binding's own refusal, with no SQLSTATE by design; nul_safe
		// covers it.
		return "", true
	}
	_, err := pq.exec(conn, sql)
	if err == nil {
		return "", true
	}
	f := err.(pq.Fault)
	if f.message == "" {
		return fmt.tprintf("%v %s: a failure with no message", from, harness.show(sql)), false
	}
	if !is_sqlstate(f.sqlstate) {
		return fmt.tprintf("%v %s: SQLSTATE %q for %s", from, harness.show(sql), f.sqlstate, f.message),
			false
	}
	// A position is 1-based and counts characters; the server can point one
	// past the end, at end of input.
	if f.position < 0 || f.position > utf8.rune_count_in_string(sql) + 1 {
		return fmt.tprintf(
				"%v %s: position %d outside the statement",
				from,
				harness.show(sql),
				f.position,
			),
			false
	}
	return "", true
}

// nul_safe puts a NUL into a statement that would succeed without its tail,
// into an argument and into text to escape, and checks each is refused by the
// binding, naming the NUL's offset, rather than sent short.
nul_safe :: proc(conn: ^pq.Conn, src: ^harness.Source) -> (detail: string, ok: bool) {
	x := strings.to_valid_utf8(value(src), "", context.temp_allocator)
	x, _ = strings.remove_all(x, "\x00", context.temp_allocator)
	at := harness.integer_in(src, 0, len(x) + 1)
	for at > 0 && at < len(x) && !utf8.rune_start(x[at]) {
		at -= 1
	}
	holed := strings.concatenate({x[:at], "\x00", x[at:]}, context.temp_allocator)
	// The comma ends the number, so offset 1 does not match offset 12.
	want := fmt.tprintf("offset %d,", at)

	// The prefix is a whole statement, so a binding that sent only what came
	// before the NUL would get a Result back.
	lit, lerr := pq.escape_literal(conn, x)
	if lerr != nil {
		return fmt.tprintf("escape %s: %v", harness.show(x), lerr), false
	}
	prefix := strings.concatenate({"SELECT ", lit, " "}, context.temp_allocator)
	sql := strings.concatenate({prefix, "\x00", "garbage"}, context.temp_allocator)
	if d, held := refused(pq.exec(conn, sql), fmt.tprintf("offset %d,", len(prefix))); !held {
		return fmt.tprintf("statement %s: %s", harness.show(sql), d), false
	}
	_, aerr := pq.exec(conn, "SELECT $1", {holed})
	if d, held := refused({}, aerr, want); !held {
		return fmt.tprintf("argument %s: %s", harness.show(holed), d), false
	}
	_, lerr2 := pq.escape_literal(conn, holed)
	if d, held := refused({}, lerr2, want); !held {
		return fmt.tprintf("escape_literal %s: %s", harness.show(holed), d), false
	}
	_, ierr := pq.escape_identifier(conn, holed)
	if d, held := refused({}, ierr, want); !held {
		return fmt.tprintf("escape_identifier %s: %s", harness.show(holed), d), false
	}
	return "", true
}

// refused checks that a call failed in the binding — no SQLSTATE — with a
// message naming the offset.
@(private)
refused :: proc(res: pq.Result, err: pq.Error, offset: string) -> (detail: string, ok: bool) {
	f, is_fault := err.(pq.Fault)
	if !is_fault {
		return fmt.tprintf("was sent rather than refused, and gave %v", res.rows), false
	}
	if f.sqlstate != "" {
		return fmt.tprintf("reached the server: %s %s", f.sqlstate, f.message), false
	}
	if !strings.contains(f.message, offset) {
		return fmt.tprintf("refused without naming %s: %s", offset, f.message), false
	}
	return "", true
}

// compare is the shared end of both round trips.
@(private)
compare :: proc(x, sent: string, res: pq.Result, err: pq.Error) -> (detail: string, ok: bool) {
	if err != nil {
		if acceptable(x) {
			return fmt.tprintf("%s as %s: refused: %v", harness.show(x), harness.show(sent), err), false
		}
		return "", true
	}
	if len(res.rows) != 1 || len(res.rows[0]) != 1 {
		return fmt.tprintf("%s as %s: came back as %v", harness.show(x), harness.show(sent), res.rows),
			false
	}
	got, present := res.rows[0][0].?
	if !present {
		return fmt.tprintf("%s as %s: came back NULL", harness.show(x), harness.show(sent)), false
	}
	if got != x {
		return fmt.tprintf(
				"%s as %s: came back as %s",
				harness.show(x),
				harness.show(sent),
				harness.show(got),
			),
			false
	}
	return "", true
}

// acceptable is text that must round-trip: valid UTF-8 with no NUL in it.
@(private)
acceptable :: proc(x: string) -> bool {
	return utf8.valid_string(x) && strings.index_byte(x, 0) < 0
}

// is_sqlstate is five characters from 0-9 and A-Z, which is every SQLSTATE.
@(private)
is_sqlstate :: proc(s: string) -> bool {
	if len(s) != 5 {
		return false
	}
	for ch in transmute([]byte)s {
		if !(ch >= '0' && ch <= '9') && !(ch >= 'A' && ch <= 'Z') {
			return false
		}
	}
	return true
}
