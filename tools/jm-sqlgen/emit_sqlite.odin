package main

import "core:fmt"
import "core:strings"

// SQLITE is the driver for code over jm:sqlite3: a query is a statement
// stepped a row at a time, and a column is read straight off it.
SQLITE :: Driver {
	pkg         = "sqlite3",
	import_path = "jm:sqlite3",
	conn        = "sqlite3.Db",
	cursor      = "\tstmt: sqlite3.Stmt,\n\terr:  sqlite3.Error,\n",
	open_into   = sqlite_open_into,
	one         = sqlite_one,
	exec        = sqlite_exec,
	count       = sqlite_count,
	next        = sqlite_next,
	close       = SQLITE_CLOSE,
	uses_fmt    = sqlite_uses_fmt,
}

@(private = "file")
sqlite_uses_fmt :: proc(q: Query) -> bool {
	return q.kind == .One
}

@(private = "file")
sqlite_open_into :: proc(sb: ^strings.Builder, q: Query) {
	sqlite_query(sb, "rows.stmt =", q)
}

@(private = "file")
sqlite_one :: proc(sb: ^strings.Builder, q: Query) {
	sqlite_query(sb, "stmt :=", q)
	strings.write_string(sb, "\tif sqlite3.next(&stmt) {\n\t\tfound = true\n")
	sqlite_reads(sb, q, "&stmt", "\t\t")
	strings.write_string(sb, "\t\tif stmt.err == nil && sqlite3.next(&stmt) {\n")
	strings.write_string(sb, "\t\t\tstmt.err = sqlite3.Fault {\n\t\t\t\tcode = .Misuse,\n")
	fmt.sbprintf(
		sb,
		"\t\t\t\ttext = fmt.aprint(\"%s is :one but returned a second row\", allocator = allocator),\n" +
		"\t\t\t}}\n\t\t}}\n\t}}\n",
		q.name,
	)
	strings.write_string(sb, "\tif err = sqlite3.finish(&stmt); err != nil {\n")
	fmt.sbprintf(sb, "\t\t%s_free_row(row, allocator)\n", q.name)
	strings.write_string(sb, "\t\treturn {}, false, err\n\t}\n\treturn\n}\n")
}

@(private = "file")
sqlite_exec :: proc(sb: ^strings.Builder, q: Query) {
	sqlite_query(sb, "stmt :=", q)
	strings.write_string(sb, "\tfor sqlite3.next(&stmt) {}\n\treturn sqlite3.finish(&stmt)\n}\n")
}

@(private = "file")
sqlite_count :: proc(sb: ^strings.Builder, q: Query) {
	sqlite_query(sb, "stmt :=", q)
	strings.write_string(sb, "\tfor sqlite3.next(&stmt) {}\n\tsqlite3.finish(&stmt) or_return\n")
	fmt.sbprintf(sb, "\treturn sqlite3.%s(db), nil\n}}\n", q.kind == .Rows ? "changes" : "last_id")
}

@(private = "file")
sqlite_next :: proc(sb: ^strings.Builder, q: Query) {
	strings.write_string(sb, "\tif !sqlite3.next(&rows.stmt) {\n\t\treturn\n\t}\n")
	sqlite_reads(sb, q, "&rows.stmt", "\t")
	strings.write_string(sb, "\tif rows.stmt.err != nil {\n")
	fmt.sbprintf(
		sb,
		"\t\t%s_free_row(row, rows.stmt.allocator)\n\t\treturn {{}}, false\n\t}}\n",
		q.name,
	)
	strings.write_string(sb, "\treturn row, true\n}\n\n")
}

@(private = "file")
sqlite_query :: proc(sb: ^strings.Builder, lhs: string, q: Query) {
	fmt.sbprintf(sb, "\t%s sqlite3.query(\n\t\tdb,\n\t\t%s,\n", lhs, sql_const(q))
	for param in q.params {
		if param.type.nullable {
			fmt.sbprintf(sb, "\t\tsqlite3.nullable(%s),\n", param.name)
		} else {
			fmt.sbprintf(sb, "\t\t%s,\n", param.name)
		}
	}
	strings.write_string(sb, "\t\tallocator = allocator,\n\t) or_return\n")
}

@(private = "file")
sqlite_reads :: proc(sb: ^strings.Builder, q: Query, stmt, indent: string) {
	for f, i in q.fields {
		fmt.sbprintf(
			sb,
			"%srow.%s = sqlite3.%s(%s, %d, %s)\n",
			indent,
			f.name,
			reader(f),
			stmt,
			i,
			KIND_NAMES[f.type.kind],
		)
	}
}

// SQLITE_TEST is what the generated test does to run against SQLite: a
// fresh in-memory database for each data set, and a savepoint around each
// query.
SQLITE_TEST :: Test_Driver {
	imports = "import \"core:testing\"\n\nimport \"jm:sqlite3\"\n",
	run     = `
// Each query runs in every data set through its generated proc, which
// checks every value it reads against the type it was generated with. check
// runs too, against the schema as SQLite holds it.
@(test)
sqlgen_queries_hold_their_types :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for set in SQLGEN_SETS {
		db, err := sqlite3.open(sqlite3.MEMORY)
		if !testing.expectf(t, err == nil, "data set %s: open: %v", set.name, err) {
			return
		}
		defer sqlite3.close(&db)
		testing.expect_value(t, sqlite3.exec(db, #load("schema.sql", string)), nil)
		testing.expect_value(t, sqlite3.exec(db, set.seed), nil)
		testing.expect_value(t, check(db), nil)
		sqlgen_run(t, db, set)
	}
}
`,
	conn    = "sqlite3.Db",
	helpers = `
@(private = "file")
sqlgen_begin :: proc(t: ^testing.T, db: sqlite3.Db) {
	testing.expect_value(t, sqlite3.exec(db, "SAVEPOINT sqlgen"), nil)
}

// sqlgen_end undoes what the query changed, and fails the test unless the
// query succeeded or a constraint the data set happens to break refused it.
// A STRICT column refusing a parameter's type is not such a constraint.
@(private = "file")
sqlgen_end :: proc(
	t: ^testing.T,
	db: sqlite3.Db,
	set: Sqlgen_Set,
	query: string,
	err: sqlite3.Error,
) {
	testing.expect_value(t, sqlite3.exec(db, "ROLLBACK TO sqlgen; RELEASE sqlgen"), nil)
	f, failed := err.(sqlite3.Fault)
	if !failed {
		return
	}
	broke_a_constraint := f.code == .Constraint && f.extended != sqlite3.CONSTRAINT_DATATYPE
	testing.expectf(t, broke_a_constraint, "data set %s: %s: %v: %s", set.name, query, f.code, f.text)
}
`,
}

@(private = "file")
SQLITE_CLOSE :: `	if err := sqlite3.finish(&rows.stmt); rows.err == nil {
		rows.err = err
	}
	return rows.err
`
