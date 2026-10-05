package pq

import "core:strconv"
import "core:strings"
import "core:testing"

// Type OIDs from pg_type.dat. They are fixed for the built-in types, which
// is what lets a generator map them to Odin types without asking.
@(private = "file")
BOOL :: Oid(16)
@(private = "file")
INT8 :: Oid(20)
@(private = "file")
INT4 :: Oid(23)
@(private = "file")
TEXT :: Oid(25)
@(private = "file")
VARCHAR :: Oid(1043)
@(private = "file")
INT4_ARRAY :: Oid(1007)
@(private = "file")
TEXT_ARRAY :: Oid(1009)
@(private = "file")
UUID :: Oid(2950)

// The role permission_errors_surface sets itself to. It is made once, by that
// test alone, so no two sessions race to create it.
@(private = "file")
RESTRICTED :: "jm_pq_describer"

@(private = "file")
run :: proc(t: ^testing.T, conn: ^Conn, sql: string, loc := #caller_location) {
	res, err := exec(conn, sql)
	testing.expect_value(t, err, nil, loc = loc)
	destroy(&res)
}

// oid_of runs a query that returns one oid, such as `SELECT 'rig'::regclass::oid`.
@(private = "file")
oid_of :: proc(t: ^testing.T, conn: ^Conn, sql: string, loc := #caller_location) -> Oid {
	res, err := exec(conn, sql)
	defer destroy(&res)
	if !testing.expect_value(t, err, nil, loc = loc) || len(res.rows) != 1 {
		return 0
	}
	n, _ := strconv.parse_uint(res.rows[0][0].? or_else "")
	return Oid(n)
}

@(private = "file")
must_describe :: proc(
	t: ^testing.T,
	conn: ^Conn,
	sql: string,
	loc := #caller_location,
) -> Description {
	desc, err := describe(conn, sql)
	testing.expect_value(t, err, nil, loc = loc)
	return desc
}

// The fixture every test but the role's works on: two temporary tables, so
// nothing outlives the session or collides with another test's.
@(private = "file")
make_tables :: proc(t: ^testing.T, conn: ^Conn) {
	run(t, conn, `CREATE TEMP TABLE site(id int PRIMARY KEY, name varchar(20) NOT NULL)`)
	run(
		t,
		conn,
		`CREATE TEMP TABLE rig(
			id uuid PRIMARY KEY,
			serial text NOT NULL,
			note text,
			site_id int REFERENCES site(id)
		)`,
	)
}

@(private = "file")
expect_column :: proc(
	t: ^testing.T,
	col: Column,
	want: Column,
	loc := #caller_location,
) {
	testing.expect_value(t, col.name, want.name, loc = loc)
	testing.expect_value(t, col.type_oid, want.type_oid, loc = loc)
	testing.expect_value(t, col.typmod, want.typmod, loc = loc)
	testing.expect_value(t, col.table_oid, want.table_oid, loc = loc)
	testing.expect_value(t, col.table_column, want.table_column, loc = loc)
}

// `id = $1` against a uuid column makes $1 a uuid, with no cast written, and
// each column names the table and attnum it was read from.
@(test)
describe_infers_parameter_types :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	make_tables(t, conn)
	rig := oid_of(t, conn, `SELECT 'rig'::regclass::oid`)

	desc := must_describe(t, conn, `SELECT serial, note FROM rig WHERE id = $1`)
	defer destroy(&desc)
	testing.expect_value(t, len(desc.params), 1)
	testing.expect_value(t, len(desc.columns), 2)
	if len(desc.params) != 1 || len(desc.columns) != 2 {
		return
	}
	testing.expect_value(t, desc.params[0], UUID)
	expect_column(t, desc.columns[0], {"serial", TEXT, -1, rig, 2})
	expect_column(t, desc.columns[1], {"note", TEXT, -1, rig, 3})
}

// A cast decides a parameter's type outright, and the column it feeds is an
// expression with no source table.
@(test)
describe_explicit_cast :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	desc := must_describe(t, conn, `SELECT $1::int, $2::text[] AS tags, 'x'::varchar(5) AS v`)
	defer destroy(&desc)
	testing.expect_value(t, len(desc.params), 2)
	testing.expect_value(t, len(desc.columns), 3)
	if len(desc.params) != 2 || len(desc.columns) != 3 {
		return
	}
	testing.expect_value(t, desc.params[0], INT4)
	testing.expect_value(t, desc.params[1], TEXT_ARRAY)
	expect_column(t, desc.columns[0], {"int4", INT4, -1, 0, 0})
	expect_column(t, desc.columns[1], {"tags", TEXT_ARRAY, -1, 0, 0})
	expect_column(t, desc.columns[2], {"v", VARCHAR, 9, 0, 0})
}

// Columns from two tables each name their own, and varchar(20) carries its
// size as a typmod of 24: the declared length plus the four-byte header.
@(test)
describe_join :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	make_tables(t, conn)
	rig := oid_of(t, conn, `SELECT 'rig'::regclass::oid`)
	site := oid_of(t, conn, `SELECT 'site'::regclass::oid`)

	desc := must_describe(
		t,
		conn,
		`SELECT r.id, s.name AS site FROM rig r JOIN site s ON s.id = r.site_id WHERE s.id = $1`,
	)
	defer destroy(&desc)
	testing.expect_value(t, len(desc.columns), 2)
	if len(desc.columns) != 2 {
		return
	}
	testing.expect_value(t, desc.params[0], INT4)
	expect_column(t, desc.columns[0], {"id", UUID, -1, rig, 1})
	expect_column(t, desc.columns[1], {"site", VARCHAR, 24, site, 2})
}

// Expressions and aggregates have no source column: table_oid and
// table_column are 0 even where the expression reads only one column.
@(test)
describe_expressions_and_aggregates :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	make_tables(t, conn)
	desc := must_describe(
		t,
		conn,
		`SELECT count(*), max(serial), serial || '!' AS loud, note IS NULL AS bare FROM rig
		 GROUP BY serial, note`,
	)
	defer destroy(&desc)
	testing.expect_value(t, len(desc.params), 0)
	testing.expect_value(t, len(desc.columns), 4)
	if len(desc.columns) != 4 {
		return
	}
	expect_column(t, desc.columns[0], {"count", INT8, -1, 0, 0})
	expect_column(t, desc.columns[1], {"max", TEXT, -1, 0, 0})
	expect_column(t, desc.columns[2], {"loud", TEXT, -1, 0, 0})
	expect_column(t, desc.columns[3], {"bare", BOOL, -1, 0, 0})
}

// An enum's OID is the database's own, so a generator reads it from pg_type;
// an array of one has an OID of its own too.
@(test)
describe_enums_and_arrays :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	run(t, conn, `CREATE TYPE pg_temp.mood AS ENUM ('calm', 'busy')`)
	run(t, conn, `CREATE TEMP TABLE shift(mood pg_temp.mood, moods pg_temp.mood[], tags int[])`)
	mood := oid_of(t, conn, `SELECT 'pg_temp.mood'::regtype::oid`)
	moods := oid_of(t, conn, `SELECT typarray FROM pg_type WHERE oid = 'pg_temp.mood'::regtype`)
	shift := oid_of(t, conn, `SELECT 'shift'::regclass::oid`)

	desc := must_describe(
		t,
		conn,
		`SELECT mood, moods, tags FROM shift WHERE mood = $1 AND $2 = ANY(tags)`,
	)
	defer destroy(&desc)
	testing.expect_value(t, len(desc.params), 2)
	testing.expect_value(t, len(desc.columns), 3)
	if len(desc.params) != 2 || len(desc.columns) != 3 {
		return
	}
	testing.expect_value(t, desc.params[0], mood)
	testing.expect_value(t, desc.params[1], INT4)
	expect_column(t, desc.columns[0], {"mood", mood, -1, shift, 1})
	expect_column(t, desc.columns[1], {"moods", moods, -1, shift, 2})
	expect_column(t, desc.columns[2], {"tags", INT4_ARRAY, -1, shift, 3})
}

// A statement the server cannot parse or resolve is a Fault with the
// SQLSTATE and position exec would give, and the session stays usable.
@(test)
describe_rejects_bad_statements :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	make_tables(t, conn)

	_, err := describe(conn, `SELEC 1`)
	defer free_fault(err)
	testing.expect_value(t, fault_of(err).sqlstate, "42601")
	testing.expect_value(t, fault_of(err).position, 1)

	// "SELECT serial, " is fifteen characters, so nope is the sixteenth.
	_, unknown := describe(conn, `SELECT serial, nope FROM rig`)
	defer free_fault(unknown)
	testing.expect_value(t, fault_of(unknown).sqlstate, "42703")
	testing.expect_value(t, fault_of(unknown).position, 16)

	_, several := describe(conn, `SELECT 1; SELECT 2`)
	defer free_fault(several)
	testing.expect_value(t, fault_of(several).sqlstate, "42601")

	_, nul := describe(conn, "SELECT 1\x00; DROP TABLE rig")
	defer free_fault(nul)
	testing.expect_value(t, fault_of(nul).sqlstate, "")
	testing.expect_value(t, fault_of(nul).position, 9)

	testing.expect_value(t, transaction_status(conn), Transaction_Status.Idle)
	desc := must_describe(t, conn, `SELECT 1`)
	destroy(&desc)

	// Inside a transaction block, a rejected statement fails the block.
	run(t, conn, `BEGIN`)
	_, in_block := describe(conn, `SELECT nope FROM rig`)
	defer free_fault(in_block)
	testing.expect_value(t, fault_of(in_block).sqlstate, "42703")
	testing.expect_value(t, transaction_status(conn), Transaction_Status.In_Error)
	run(t, conn, `ROLLBACK`)

	_, closed := describe(nil, `SELECT 1`)
	defer free_fault(closed)
	testing.expect(t, fault_of(closed).message != "", "a nil connection is refused")
}

// A schema the role may not use fails at describe, with 42501. A table it
// may not read does not: PostgreSQL checks table privileges when a statement
// runs, so describe answers and only exec is refused.
@(test)
describe_permission_errors_surface :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	run(
		t,
		conn,
		`DO $$ BEGIN CREATE ROLE ` + RESTRICTED + `;
		 EXCEPTION WHEN duplicate_object THEN NULL; END $$`,
	)
	run(t, conn, `CREATE SCHEMA IF NOT EXISTS describe_private`)
	run(t, conn, `CREATE TABLE IF NOT EXISTS describe_private.vault(x int)`)
	run(t, conn, `CREATE TABLE IF NOT EXISTS public.describe_secret(x int)`)
	run(
		t,
		conn,
		`CREATE OR REPLACE FUNCTION public.describe_fn() RETURNS int
		 LANGUAGE sql AS 'SELECT 1'`,
	)
	run(t, conn, `REVOKE EXECUTE ON FUNCTION public.describe_fn() FROM PUBLIC`)
	run(t, conn, `SET ROLE ` + RESTRICTED)
	defer run(t, conn, `RESET ROLE`)

	_, err := describe(conn, `SELECT x FROM describe_private.vault`)
	defer free_fault(err)
	f := fault_of(err)
	testing.expect_value(t, f.sqlstate, "42501")
	testing.expect(t, strings.contains(f.message, "describe_private"), f.message)

	desc := must_describe(t, conn, `SELECT x FROM public.describe_secret`)
	testing.expect_value(t, len(desc.columns), 1)
	destroy(&desc)
	_, read := exec(conn, `SELECT x FROM public.describe_secret`)
	defer free_fault(read)
	testing.expect_value(t, fault_of(read).sqlstate, "42501")

	// A function's EXECUTE privilege is checked at run time too.
	desc = must_describe(t, conn, `SELECT public.describe_fn() AS one`)
	testing.expect_value(t, len(desc.columns), 1)
	destroy(&desc)
	_, call := exec(conn, `SELECT public.describe_fn()`)
	defer free_fault(call)
	testing.expect_value(t, fault_of(call).sqlstate, "42501")
}

// An UPDATE without RETURNING has parameters and no columns.
@(test)
describe_zero_columns :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	make_tables(t, conn)
	desc := must_describe(t, conn, `UPDATE rig SET note = $1 WHERE id = $2`)
	defer destroy(&desc)
	testing.expect_value(t, len(desc.columns), 0)
	testing.expect_value(t, len(desc.params), 2)
	if len(desc.params) != 2 {
		return
	}
	testing.expect_value(t, desc.params[0], TEXT)
	testing.expect_value(t, desc.params[1], UUID)
}

// describe prepares into the unnamed statement, so the session holds no
// prepared statement afterwards, and the strings outlive the connection.
@(test)
describe_leaves_nothing_behind :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	for _ in 0 ..< 3 {
		desc := must_describe(t, conn, `SELECT $1::int AS n`)
		destroy(&desc)
	}
	res, err := exec(conn, `SELECT count(*) FROM pg_prepared_statements`)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(res.rows), 1)
	if len(res.rows) == 1 {
		testing.expect_value(t, res.rows[0][0].? or_else "", "0")
	}
	destroy(&res)

	desc := must_describe(t, conn, `SELECT 1 AS outlives`)
	defer destroy(&desc)
	close(conn)
	testing.expect_value(t, len(desc.columns), 1)
	if len(desc.columns) == 1 {
		testing.expect_value(t, desc.columns[0].name, "outlives")
	}
}

// not_null reads each source column's NOT NULL constraint; a column with no
// source is false, and an empty description is an empty answer.
@(test)
not_null_follows_the_catalog :: proc(t: ^testing.T) {
	conn, up := connect_to_server(t)
	if !up {
		return
	}
	defer close(conn)
	make_tables(t, conn)
	desc := must_describe(
		t,
		conn,
		`SELECT r.id, r.serial, r.note, s.name, count(*) OVER () AS total
		 FROM rig r LEFT JOIN site s ON s.id = r.site_id`,
	)
	defer destroy(&desc)
	flags, err := not_null(conn, desc)
	defer delete(flags)
	testing.expect_value(t, err, nil)
	// s.name is NOT NULL in site and still NULL wherever the LEFT JOIN finds
	// no site: the flag is the column's constraint, as the doc says.
	want := []bool{true, true, false, true, false}
	testing.expect_value(t, len(flags), len(want))
	if len(flags) == len(want) {
		for w, i in want {
			testing.expectf(t, flags[i] == w, "column %d: got %v, want %v", i, flags[i], w)
		}
	}

	// A view's columns carry no constraint, so a column read through one is
	// false even where the table beneath it says NOT NULL.
	run(t, conn, `CREATE TEMP VIEW rig_serials AS SELECT serial FROM rig`)
	viewed := must_describe(t, conn, `SELECT serial FROM rig_serials`)
	defer destroy(&viewed)
	view := oid_of(t, conn, `SELECT 'rig_serials'::regclass::oid`)
	testing.expect_value(t, len(viewed.columns), 1)
	if len(viewed.columns) == 1 {
		testing.expect_value(t, viewed.columns[0].table_oid, view)
	}
	through, verr := not_null(conn, viewed)
	defer delete(through)
	testing.expect_value(t, verr, nil)
	testing.expect_value(t, len(through), 1)
	if len(through) == 1 {
		testing.expect_value(t, through[0], false)
	}

	none := must_describe(t, conn, `UPDATE rig SET note = NULL`)
	defer destroy(&none)
	empty, eerr := not_null(conn, none)
	defer delete(empty)
	testing.expect_value(t, eerr, nil)
	testing.expect_value(t, len(empty), 0)
}
