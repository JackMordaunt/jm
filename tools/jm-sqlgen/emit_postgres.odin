package main

import "core:fmt"
import "core:strings"

// POSTGRES is the driver for code over jm:pq: a query comes back whole, as
// text, and each column is parsed from it into its exact type. A :many
// cursor walks the rows of that result.
POSTGRES :: Driver {
	pkg         = "pq",
	import_path = "jm:pq",
	conn        = "^pq.Conn",
	cursor      = "\tresult: pq.Result,\n\tat:     int,\n\terr:    pq.Error,\n",
	open_into   = pg_open_into,
	one         = pg_one,
	exec        = pg_exec,
	count       = pg_count,
	next        = pg_next,
	close       = PG_CLOSE,
	uses_fmt    = pg_uses_fmt,
}

@(private = "file")
PG_CLOSE :: `	pq.destroy(&rows.result)
	return rows.err
`

@(private = "file")
pg_uses_fmt :: proc(q: Query) -> bool {
	return q.kind == .One
}

@(private = "file")
pg_open_into :: proc(sb: ^strings.Builder, q: Query) {
	pg_query_call(sb, "rows.result =", q)
}

@(private = "file")
pg_one :: proc(sb: ^strings.Builder, q: Query) {
	pg_query_call(sb, "res :=", q)
	strings.write_string(sb, "\tdefer pq.destroy(&res)\n\tif len(res.rows) > 1 {\n")
	fmt.sbprintf(
		sb,
		"\t\tsecond := fmt.aprint(\"%s is :one but returned a second row\", allocator = allocator)\n",
		q.name,
	)
	strings.write_string(sb, "\t\treturn {}, false, pq.Fault{message = second}\n\t}\n")
	strings.write_string(
		sb,
		"\tif len(res.rows) == 0 {\n\t\treturn\n\t}\n\tcells := res.rows[0]\n",
	)
	pg_reads(sb, q, "&err", "allocator")
	fmt.sbprintf(
		sb,
		"\tif err != nil {{\n\t\t%s_free_row(row, allocator)\n\t\treturn {{}}, false, err\n\t}}\n",
		q.name,
	)
	strings.write_string(sb, "\treturn row, true, nil\n}\n")
}

@(private = "file")
pg_exec :: proc(sb: ^strings.Builder, q: Query) {
	pg_query_call(sb, "res :=", q)
	strings.write_string(sb, "\tpq.destroy(&res)\n\treturn nil\n}\n")
}

@(private = "file")
pg_count :: proc(sb: ^strings.Builder, q: Query) {
	pg_query_call(sb, "res :=", q)
	strings.write_string(sb, "\tdefer pq.destroy(&res)\n\treturn i64(res.cmd_tuples), nil\n}\n")
}

@(private = "file")
pg_next :: proc(sb: ^strings.Builder, q: Query) {
	strings.write_string(
		sb,
		"\tif rows.err != nil || rows.at >= len(rows.result.rows) {\n\t\treturn\n\t}\n",
	)
	strings.write_string(sb, "\tcells := rows.result.rows[rows.at]\n\trows.at += 1\n")
	pg_reads(sb, q, "&rows.err", "rows.result.allocator")
	strings.write_string(sb, "\tif rows.err != nil {\n")
	fmt.sbprintf(sb, "\t\t%s_free_row(row, rows.result.allocator)\n", q.name)
	strings.write_string(sb, "\t\treturn {}, false\n\t}\n")
	strings.write_string(sb, "\treturn row, true\n}\n\n")
}

// pg_query_call writes the statement that runs q with its parameters, in the
// order they are numbered, and returns early on failure.
@(private = "file")
pg_query_call :: proc(sb: ^strings.Builder, lhs: string, q: Query) {
	fmt.sbprintf(sb, "\t%s pq.exec_values(\n\t\tdb,\n\t\t%s,\n\t\t{{", lhs, sql_const(q))
	for param, i in q.params {
		if i > 0 {
			strings.write_string(sb, ", ")
		}
		if param.type.nullable {
			fmt.sbprintf(sb, "pq.nullable(%s)", param.name)
		} else {
			strings.write_string(sb, param.name)
		}
	}
	strings.write_string(sb, "},\n\t\tallocator,\n\t) or_return\n")
}

@(private = "file")
pg_reads :: proc(sb: ^strings.Builder, q: Query, err, allocator: string) {
	for f, i in q.fields {
		fmt.sbprintf(
			sb,
			"\trow.%s = pq.%s(cells[%d], %q, %s, %s, %s)\n",
			f.name,
			reader(f),
			i,
			f.name,
			KIND_NAMES[f.type.kind],
			err,
			allocator,
		)
	}
}

// POSTGRES_TEST is what the generated test does to run against PostgreSQL:
// a throwaway server from jm:pq/testdb, skipped with a warning where there
// is none, a transaction for each data set, and a savepoint around each
// query. A failure in SQLSTATE class 22 or 23 is the data set's values
// breaking a constraint or a range; anything else fails the test.
POSTGRES_TEST :: Test_Driver {
	imports = PG_TEST_IMPORTS,
	run     = `
// Each query runs in every data set through its generated proc, which
// checks every value it reads against the type it was generated with. check
// runs too, against the schema as the server holds it.
@(test)
sqlgen_queries_hold_their_types :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	if ok, why := testdb.start(); !ok {
		log.warnf("skipped, no PostgreSQL server to test against: %s", why)
		return
	}
	db, err := pq.connect()
	if !testing.expect_value(t, err, nil) {
		return
	}
	defer pq.close(db)
	for set in SQLGEN_SETS {
		sqlgen_exec(t, db, "BEGIN")
		// A data set's child rows have no parents; see jm-sqlgen's PG_NO_FOREIGN_KEYS.
		sqlgen_exec(t, db, "SET LOCAL session_replication_role = replica")
		sqlgen_exec(t, db, #load("schema.sql", string))
		if set.seed != "" {
			sqlgen_exec(t, db, set.seed)
		}
		testing.expect_value(t, check(db), nil)
		sqlgen_run(t, db, set)
		sqlgen_exec(t, db, "ROLLBACK")
	}
}
`,
	conn    = "^pq.Conn",
	helpers = `
@(private = "file")
sqlgen_exec :: proc(t: ^testing.T, db: ^pq.Conn, sql: string, loc := #caller_location) {
	res, err := pq.exec(db, sql)
	testing.expect_value(t, err, nil, loc = loc)
	pq.destroy(&res)
}

@(private = "file")
sqlgen_begin :: proc(t: ^testing.T, db: ^pq.Conn) {
	sqlgen_exec(t, db, "SAVEPOINT sqlgen")
}

// sqlgen_end undoes what the query changed, and fails the test unless the
// query succeeded or the data set's values broke a constraint or a range,
// SQLSTATE classes 23 and 22. A value read as the wrong type is neither.
@(private = "file")
sqlgen_end :: proc(t: ^testing.T, db: ^pq.Conn, set: Sqlgen_Set, query: string, err: pq.Error) {
	sqlgen_exec(t, db, "ROLLBACK TO SAVEPOINT sqlgen")
	sqlgen_exec(t, db, "RELEASE SAVEPOINT sqlgen")
	f, failed := err.(pq.Fault)
	if !failed {
		return
	}
	data := strings.has_prefix(f.sqlstate, "22") || strings.has_prefix(f.sqlstate, "23")
	testing.expectf(t, data, "data set %s: %s: %s %s", set.name, query, f.sqlstate, f.message)
}
`,
}

@(private = "file")
PG_TEST_IMPORTS :: `import "core:log"
import "core:strings"
import "core:testing"

import "jm:pq"
import "jm:pq/testdb"
`
