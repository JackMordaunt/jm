package pq

import "core:fmt"
import "core:log"
import "core:strings"
import "core:testing"
import "core:unicode/utf8"

import "jm:pq/testdb"

// connect_to_server brings up the throwaway server and connects to it through the
// environment, or logs why not. Every test here needs one; without initdb
// they skip rather than fail.
@(private)
connect_to_server :: proc(t: ^testing.T) -> (conn: ^Conn, up: bool) {
	if ok, why := testdb.start(); !ok {
		log.warnf("skipped, no PostgreSQL server to test against: %s", why)
		return nil, false
	}
	err: Error
	conn, err = connect()
	if !testing.expect_value(t, err, nil) {
		return nil, false
	}
	return conn, true
}

@(private = "file")
must_exec :: proc(t: ^testing.T, conn: ^Conn, sql: string, args: []string = {}, loc := #caller_location) -> Result {
	res, err := exec(conn, sql, args)
	testing.expect_value(t, err, nil, loc = loc)
	return res
}

@(private)
fault_of :: proc(err: Error) -> Fault {
	f, _ := err.(Fault)
	return f
}

@(private)
free_fault :: proc(err: Error) {
	if f, is_fault := err.(Fault); is_fault {
		delete(f.message)
		delete(f.detail)
		delete(f.hint)
		delete(f.sqlstate)
	}
}

// connect("") must take everything from the environment, which is how squeal
// connects; testdb has pointed PGHOST at a socket directory and nothing else.
@(test)
connect_from_env :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	res := must_exec(t, conn, `SELECT current_database(), current_user, current_setting('client_encoding')`)
	defer destroy(&res)
	testing.expect_value(t, len(res.rows), 1)
	testing.expect_value(t, res.rows[0][0].? or_else "", testdb.DATABASE)
	testing.expect_value(t, res.rows[0][1].? or_else "", testdb.USER)
	testing.expect_value(t, res.rows[0][2].? or_else "", "UTF8")
}

// A URL overrides the environment, and a server that is not there is a Fault
// with libpq's message rather than a crash or a nil with no reason.
@(test)
connect_fails_cleanly :: proc(t: ^testing.T) {
	if ok, _ := testdb.start(); !ok {
		return
	}
	conn, err := connect("host=/nonexistent/jm-pq connect_timeout=2")
	defer free_fault(err)
	testing.expect(t, conn == nil, "no connection to a socket that does not exist")
	f := fault_of(err)
	testing.expect(t, strings.contains(f.message, "/nonexistent/jm-pq"), f.message)
	testing.expect_value(t, f.sqlstate, "")
}

@(test)
round_trip_with_null :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	ddl := must_exec(t, conn, `CREATE TEMP TABLE note(id int PRIMARY KEY, body text)`)
	testing.expect_value(t, ddl.status, Exec_Status.Command_Ok)
	destroy(&ddl)
	ins := must_exec(t, conn, `INSERT INTO note VALUES (1, 'hello'), (2, NULL), (3, '')`)
	testing.expect_value(t, ins.cmd_tuples, 3)
	destroy(&ins)

	res := must_exec(t, conn, `SELECT id, body FROM note ORDER BY id`)
	defer destroy(&res)
	testing.expect_value(t, res.status, Exec_Status.Tuples_Ok)
	testing.expect_value(t, len(res.columns), 2)
	testing.expect_value(t, res.columns[0], "id")
	testing.expect_value(t, res.columns[1], "body")
	testing.expect_value(t, len(res.rows), 3)
	testing.expect_value(t, res.rows[0][0].? or_else "", "1")
	testing.expect_value(t, res.rows[0][1].? or_else "", "hello")
	_, null_present := res.rows[1][1].?
	testing.expect(t, !null_present, "NULL must read back as nil")
	empty, empty_present := res.rows[2][1].?
	testing.expect(t, empty_present, "the empty string must not read back as NULL")
	testing.expect_value(t, empty, "")
}

// Parameters are sent beside the statement, so what would break SQL built by
// hand arrives untouched: quotes, backslashes, text that looks like SQL or
// like escaped bytes, and multibyte characters.
@(test)
args_round_trip :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	awkward := []string {
		"name-says-what-it-isn't",
		`he said "quoted"`,
		"'; DROP TABLE pg_class; --",
		`back\slash \x00 \\x41 E'\n'`,
		"\\xdeadbeef",
		"line\nbreak\ttab\r",
		"\x01\x02\x7f",
		"日本語 — ümlaut, emoji 🐘",
		"$1 $2 ?",
		"",
	}
	for v in awkward {
		res := must_exec(t, conn, `SELECT $1::text, length($1::text)`, {v})
		testing.expect_value(t, res.rows[0][0].? or_else "<null>", v)
		testing.expect_value(t, res.rows[0][1].? or_else "", fmt.tprint(utf8.rune_count_in_string(v)))
		destroy(&res)
	}
	// Two parameters, in order, and one used twice.
	res := must_exec(t, conn, `SELECT $2 || $1 || $2`, {"a", "b"})
	defer destroy(&res)
	testing.expect_value(t, res.rows[0][0].? or_else "", "bab")
}

@(test)
error_carries_sqlstate_and_position :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	_, err := exec(conn, `SELECT id FROM no_such_table`)
	defer free_fault(err)
	f := fault_of(err)
	testing.expect_value(t, f.sqlstate, "42P01")
	testing.expect(t, strings.contains(f.message, "no_such_table"), f.message)
	// "SELECT id FROM " is fifteen characters, so the table name is the
	// sixteenth.
	testing.expect_value(t, f.position, 16)

	// The position is in characters, not bytes: each ü is two bytes.
	_, err2 := exec(conn, `SELECT 'üüü', nope`)
	defer free_fault(err2)
	f2 := fault_of(err2)
	testing.expect_value(t, f2.sqlstate, "42703")
	testing.expect_value(t, f2.position, 15)

	// A hint and detail come through when the server sends them.
	_, err3 := exec(conn, `SELECT 1/0`)
	defer free_fault(err3)
	testing.expect_value(t, fault_of(err3).sqlstate, "22012")

	// The connection is still usable, outside any transaction.
	testing.expect_value(t, transaction_status(conn), Transaction_Status.Idle)
	ok := must_exec(t, conn, `SELECT 1`)
	destroy(&ok)
}

@(test)
unique_violation_is_23505 :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	r := must_exec(t, conn, `CREATE TEMP TABLE u(k text PRIMARY KEY)`)
	destroy(&r)
	r = must_exec(t, conn, `INSERT INTO u VALUES ($1)`, {"x"})
	destroy(&r)
	_, err := exec(conn, `INSERT INTO u VALUES ($1)`, {"x"})
	defer free_fault(err)
	f := fault_of(err)
	testing.expect_value(t, f.sqlstate, "23505")
	testing.expect(t, strings.contains(f.detail, "(k)=(x)"), f.detail)
}

@(test)
cmd_tuples_on_update :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	r := must_exec(t, conn, `CREATE TEMP TABLE c(n int); INSERT INTO c SELECT generate_series(1, 10)`)
	destroy(&r)
	upd := must_exec(t, conn, `UPDATE c SET n = n + 1 WHERE n > $1`, {"3"})
	testing.expect_value(t, upd.cmd_tuples, 7)
	testing.expect_value(t, len(upd.rows), 0)
	destroy(&upd)
	del := must_exec(t, conn, `DELETE FROM c`)
	testing.expect_value(t, del.cmd_tuples, 10)
	destroy(&del)
	// A command with no count reads as 0.
	set := must_exec(t, conn, `SET search_path = public`)
	testing.expect_value(t, set.cmd_tuples, 0)
	destroy(&set)
}

@(test)
identity_fields_populated :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	id := identity(conn)
	defer {
		delete(id.host)
		delete(id.port)
		delete(id.db)
		delete(id.user)
	}
	testing.expect_value(t, id.host, testdb.dir())
	testing.expect_value(t, id.port, testdb.PORT)
	testing.expect_value(t, id.db, testdb.DATABASE)
	testing.expect_value(t, id.user, testdb.USER)
	testing.expect(t, id.server_version >= 90000, "a server version like 180006")
}

// squeal's read tier: once the session is read-only, a write is refused with
// 25006, read_only_sql_transaction.
@(test)
read_only_refuses_writes :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	// A regular table, because a read-only transaction may still write a
	// temp one: an earlier draft of this test used one and the UPDATE
	// succeeded.
	r := must_exec(t, conn, `CREATE TABLE read_only_probe(n int); INSERT INTO read_only_probe VALUES (1)`)
	destroy(&r)
	r = must_exec(t, conn, `SET default_transaction_read_only = on`)
	destroy(&r)
	_, err := exec(conn, `UPDATE read_only_probe SET n = 2`)
	defer free_fault(err)
	testing.expect_value(t, fault_of(err).sqlstate, "25006")
	sel := must_exec(t, conn, `SELECT n FROM read_only_probe`)
	defer destroy(&sel)
	testing.expect_value(t, sel.rows[0][0].? or_else "", "1")
}

// A literal quoted by escape_literal selects back as exactly the bytes that
// went in, however hard they try to end the literal early.
@(test)
escape_literal_round_trips :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	hostile := []string {
		"it's",
		`'); DROP TABLE x; --`,
		`\'`,
		`\\' OR '1'='1`,
		"E'\\x41'",
		"$$ dollar $$",
		"日本語 🐘 '",
		"",
	}
	for h in hostile {
		lit, err := escape_literal(conn, h)
		testing.expect_value(t, err, nil)
		sql := strings.concatenate({"SELECT ", lit})
		res := must_exec(t, conn, sql)
		testing.expect_value(t, res.rows[0][0].? or_else "<null>", h)
		destroy(&res)
		delete(sql)
		delete(lit)
	}
	id, err := escape_identifier(conn, `we"ird name`)
	defer delete(id)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, id, `"we""ird name"`)
	sql := strings.concatenate({"CREATE TEMP TABLE ", id, "(v int)"})
	defer delete(sql)
	r := must_exec(t, conn, sql)
	destroy(&r)
}

// Everything the binding hands back is cloned before libpq frees it. Read
// after the connection is gone, a value that still pointed into a PGresult
// or the PGconn would be a use after free, and -sanitize:address traps on
// it here. Without the sanitizer the bytes may still look right, which is
// why the read happens after other work has had a chance to reuse them.
@(test)
values_outlive_the_connection :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	res := must_exec(t, conn, `SELECT 'first' AS a, NULL AS b, repeat('x', 1000) AS c`)
	defer destroy(&res)
	_, err := exec(conn, `SELECT nope`)
	defer free_fault(err)
	lit, lerr := escape_literal(conn, "it's")
	defer delete(lit)
	testing.expect_value(t, lerr, nil)
	id := identity(conn)
	defer {
		delete(id.host)
		delete(id.port)
		delete(id.db)
		delete(id.user)
	}
	r := must_exec(t, conn, `DROP TABLE IF EXISTS never_was`)
	destroy(&r)
	testing.expect_value(t, len(conn.notices), 1)
	notice := strings.clone(conn.notices[0])
	defer delete(notice)
	close(conn)

	// Churn the heap so freed blocks get reused.
	for _ in 0 ..< 64 {
		other, cerr := connect()
		if cerr == nil {
			x := must_exec(t, other, `SELECT repeat('y', 1000), 'second'`)
			destroy(&x)
		}
		close(other)
	}

	// Every byte is read here, in instrumented code, before any comparison:
	// string equality runs in base:runtime, which the sanitizer does not
	// instrument, so comparing alone would read freed memory unseen.
	// Measured: with the clone in exec removed, this test passed under
	// -sanitize:address until touch was added, and fails with it.
	touch(res.columns[0], res.columns[2], res.rows[0][0].? or_else "", res.rows[0][2].? or_else "")
	touch(fault_of(err).message, fault_of(err).sqlstate, lit, id.host, id.db, id.user, id.port, notice)

	testing.expect_value(t, res.columns[0], "a")
	testing.expect_value(t, res.columns[2], "c")
	testing.expect_value(t, res.rows[0][0].? or_else "", "first")
	testing.expect_value(t, res.rows[0][2].? or_else "", strings.repeat("x", 1000, context.temp_allocator))
	testing.expect_value(t, fault_of(err).sqlstate, "42703")
	testing.expect(t, strings.contains(fault_of(err).message, "nope"), fault_of(err).message)
	testing.expect_value(t, lit, `'it''s'`)
	testing.expect_value(t, id.db, testdb.DATABASE)
	testing.expect(t, strings.contains(notice, "never_was"), notice)
}

// touch reads every byte of every string, so an instrumented load lands on
// each of them.
@(private = "file")
touch :: proc(strs: ..string) -> (sum: int) {
	for s in strs {
		for i in 0 ..< len(s) {
			sum += int((transmute([]byte)s)[i])
		}
	}
	return sum
}

// A NUL cannot cross into libpq, so every entry point refuses one and says
// where it was, rather than sending the part before it.
@(test)
nul_is_refused :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	_, err := exec(conn, "SELECT 1; DROP\x00 TABLE x")
	f := fault_of(err)
	testing.expect(t, strings.contains(f.message, "offset 14"), f.message)
	testing.expect_value(t, f.position, 15)
	testing.expect_value(t, f.sqlstate, "")
	free_fault(err)

	// The position counts characters, as the server's does.
	_, err = exec(conn, "SELECT 'ü'\x00")
	testing.expect_value(t, fault_of(err).position, 11)
	free_fault(err)

	_, err = exec(conn, `SELECT $1, $2`, {"fine", "cut\x00short"})
	f = fault_of(err)
	testing.expect(t, strings.contains(f.message, "argument 2"), f.message)
	testing.expect(t, strings.contains(f.message, "offset 3"), f.message)
	free_fault(err)

	_, eerr := escape_literal(conn, "ab\x00c")
	testing.expect(t, strings.contains(fault_of(eerr).message, "offset 2"), fault_of(eerr).message)
	free_fault(eerr)
	_, eerr = escape_identifier(conn, "\x00")
	testing.expect(t, strings.contains(fault_of(eerr).message, "offset 0"), fault_of(eerr).message)
	free_fault(eerr)
}

@(test)
notices_are_captured :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	r := must_exec(t, conn, `DO $$ BEGIN RAISE NOTICE 'one'; RAISE WARNING 'two'; END $$`)
	destroy(&r)
	testing.expect_value(t, len(conn.notices), 2)
	if len(conn.notices) == 2 {
		testing.expect_value(t, conn.notices[0], "NOTICE:  one")
		testing.expect_value(t, conn.notices[1], "WARNING:  two")
	}
	clear_notices(conn)
	testing.expect_value(t, len(conn.notices), 0)
}

@(test)
several_statements_return_the_last :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	res := must_exec(t, conn, `SELECT 1; SELECT 2 AS two;`)
	defer destroy(&res)
	testing.expect_value(t, res.columns[0], "two")
	testing.expect_value(t, res.rows[0][0].? or_else "", "2")

	empty := must_exec(t, conn, `  -- nothing but a comment`)
	testing.expect_value(t, empty.status, Exec_Status.Empty_Query)
	destroy(&empty)

	// With args it is one statement, and the server says so.
	_, err := exec(conn, `SELECT $1; SELECT 2`, {"x"})
	defer free_fault(err)
	testing.expect_value(t, fault_of(err).sqlstate, "42601")
}

@(test)
transaction_status_follows_the_session :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	testing.expect_value(t, transaction_status(conn), Transaction_Status.Idle)
	r := must_exec(t, conn, `BEGIN`)
	destroy(&r)
	testing.expect_value(t, transaction_status(conn), Transaction_Status.In_Transaction)
	_, err := exec(conn, `SELECT nope`)
	free_fault(err)
	testing.expect_value(t, transaction_status(conn), Transaction_Status.In_Error)
	_, err = exec(conn, `SELECT 1`)
	testing.expect_value(t, fault_of(err).sqlstate, "25P02")
	free_fault(err)
	r = must_exec(t, conn, `ROLLBACK`)
	destroy(&r)
	testing.expect_value(t, transaction_status(conn), Transaction_Status.Idle)
}

// COPY needs a protocol exchange this binding does not offer. It is refused,
// and libpq ends the COPY on the next command, so the connection lives on.
@(test)
copy_is_refused_and_the_connection_survives :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	r := must_exec(t, conn, `CREATE TEMP TABLE cp(n int); INSERT INTO cp VALUES (1)`)
	destroy(&r)
	for sql in ([]string{`COPY cp FROM STDIN`, `COPY cp TO STDOUT`}) {
		_, err := exec(conn, sql)
		testing.expect(t, strings.contains(fault_of(err).message, "COPY"), fault_of(err).message)
		testing.expect_value(t, fault_of(err).sqlstate, FEATURE_NOT_SUPPORTED)
		free_fault(err)
		after := must_exec(t, conn, `SELECT n FROM cp`)
		testing.expect_value(t, len(after.rows), 1)
		destroy(&after)
		testing.expect_value(t, transaction_status(conn), Transaction_Status.Idle)
	}
	clear_notices(conn)
}

// A closed or nil connection is refused, not dereferenced.
@(test)
nil_connection_is_refused :: proc(t: ^testing.T) {
	_, err := exec(nil, `SELECT 1`)
	testing.expect(t, err != nil, "exec on nil must fail")
	free_fault(err)
	_, eerr := escape_literal(nil, "x")
	testing.expect(t, eerr != nil, "escape on nil must fail")
	free_fault(eerr)
	testing.expect_value(t, identity(nil), Identity{})
	testing.expect_value(t, transaction_status(nil), Transaction_Status.Unknown)
	close(nil)
}
