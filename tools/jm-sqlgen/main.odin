/*
jm-sqlgen turns a package's SQL into typed Odin: a row struct and a proc for
each query, which take the query's parameters by name and type and read each
column as the type it holds. It generates for SQLite, over jm:sqlite3, and
for PostgreSQL, over jm:pq.

	jm-sqlgen examples/todo/store          write the package's generated files
	jm-sqlgen -check examples/todo/store   exit 1 if they are out of date

The package directory holds two files. schema.sql creates the tables;
queries.sql names each query and says what it returns:

	-- engine: sqlite

	-- name: todo_state :one
	-- Whether the todo exists, and whether it is done.
	-- params: id: i64
	SELECT done AS "done: bool" FROM todo WHERE id = @id;

Both open with an `-- engine:` line, sqlite or postgres. A query is tagged
:one (the first row, and an error on a second), :many (a cursor over the
rows), :exec, :rows (how many rows it changed) or :last_id (the rowid an
INSERT assigned, SQLite only). Comment lines under the name line become the
proc's doc comment. Parameters are @name. The `-- params:` line types each
one: i16, i32, i64, f32, f64, bool, string, []byte, or Maybe(T) for one that
may be NULL. The proc takes them in that order.

A :many query `todos` is read three ways. todos_open, todos_next and
todos_close are the cursor. todos is the cursor as a guard, closed at the
end of its block: since a deferred close cannot return, what stopped the
rows is left in rows.err. todos_all reads every row into a slice in the
caller's allocator, which todos_free frees.

	if todos(&rows, db, filter) {
		for row in todos_next(&rows) { ... }
	}
	if rows.err != nil { ... }

The engine types the columns: jm-sqlgen runs the schema and prepares each
query against it, so a misspelt column or table is an error here rather than
at run time. A column that reads a table column directly takes that column's
type, and is Maybe unless the column is NOT NULL and nothing in the statement
can produce a NULL. A column alias annotates a column, `count(*) AS "n: i64"`,
which can type what the engine does not and claim NOT NULL where it cannot
tell. An annotation is a claim, not a fact; the generated test checks it.

SQLite. The schema runs in a scratch in-memory database. Every table must be
STRICT, since only a STRICT table holds to its declared types. SQLite types
no parameter, so each needs the -- params: line, and it stores only 64-bit
integers and floats, so i16, i32 and f32 are refused. NOT NULL is trusted
only when every opcode of the statement's bytecode is an ordinary one; an
outer join makes its far side Maybe, and an aggregate or a subquery makes
every column Maybe. An expression, and a column of a compound SELECT, which
SQLite types from its first arm alone, must be annotated.

PostgreSQL. The schema runs on a throwaway server from jm:pq/testdb, which
needs initdb and pg_ctl on PATH, inside a transaction that is rolled back.
@name is rewritten to $n where PostgreSQL's grammar reads the prefix
operator @ hard against a name, so a @ in a string, a comment or a
dollar-quoted body is left alone; write @ x, with a space, for the absolute
value. The server types every parameter, so the -- params: line is optional:
it fixes the order and can let a parameter be NULL. The server types every
column too, expressions included, with int2, int4, float4 as i16, i32 and
f32, and numeric, uuid, json, the date and time types and enums as their
text. An array or a composite must be cast, as ::text. The server's NOT NULL
is narrowed by the parse tree: the far side of an outer join, a CTE on that
side, and GROUPING SETS, ROLLUP and CUBE make a column Maybe. PostgreSQL has
no last insert id: write RETURNING id and tag the query :one. The generated
test skips, with a warning, where there is no server.

Two files come out, beside the SQL:

	queries_gen.odin       the procs, check, and a compile-time hash of both
	                       SQL files, so editing either without regenerating
	                       fails the build
	queries_gen_test.odin  every query run against every data set: empty
	                       tables, NULL in every nullable column, the extremes
	                       of each type, and each table alone; each value read
	                       is checked against its generated type

check(db) prepares every query against a live database and fails if one has
changed shape, so a database that drifted from schema.sql fails when it is
opened.
*/
package main

import "core:fmt"
import "core:os"
import "core:strings"

import "jm:pq"

USAGE :: `usage: jm-sqlgen [-check] <package dir>...

Reads schema.sql and queries.sql in each directory and writes
queries_gen.odin and queries_gen_test.odin beside them.

  -check   write nothing; exit 1 if a generated file is out of date`

main :: proc() {
	check := false
	dirs: [dynamic]string
	for arg in os.args[1:] {
		switch {
		case arg == "-h" || arg == "--help":
			fmt.println(USAGE)
			return
		case arg == "-check":
			check = true
		case strings.has_prefix(arg, "-"):
			fmt.eprintfln("jm-sqlgen: unknown flag %s\n\n%s", arg, USAGE)
			os.exit(2)
		case:
			append(&dirs, arg)
		}
	}
	if len(dirs) == 0 {
		fmt.eprintln(USAGE)
		os.exit(2)
	}
	failed := false
	for dir in dirs {
		if !run(dir, check) {
			failed = true
		}
	}
	if failed {
		os.exit(1)
	}
}

// run generates one package and writes the files, or compares them.
run :: proc(dir: string, check: bool) -> bool {
	schema, serr := os.read_entire_file(fmt.tprintf("%s/%s", dir, SCHEMA_FILE), context.allocator)
	queries, qerr := os.read_entire_file(
		fmt.tprintf("%s/%s", dir, QUERIES_FILE),
		context.allocator,
	)
	if serr != nil || qerr != nil {
		fmt.eprintfln("%s: needs %s and %s", dir, SCHEMA_FILE, QUERIES_FILE)
		return false
	}
	pkg, pok := package_name(dir)
	if !pok {
		fmt.eprintfln("%s: no package name: add a .odin file that declares one", dir)
		return false
	}
	files, problems := generate(pkg, string(schema), string(queries))
	for msg in problems {
		fmt.eprintfln("%s/%s", dir, msg)
	}
	if len(problems) > 0 {
		return false
	}
	ok := true
	for f in files {
		path := fmt.tprintf("%s/%s", dir, f.name)
		old, rerr := os.read_entire_file(path, context.allocator)
		if rerr == nil && string(old) == f.text {
			continue
		}
		if check {
			fmt.eprintfln("%s is out of date: run jm-sqlgen %s", path, dir)
			ok = false
			continue
		}
		if werr := os.write_entire_file(path, f.text); werr != nil {
			fmt.eprintfln("%s: %v", path, werr)
			ok = false
		}
	}
	return ok
}

// generate is the whole tool without the file system: the schema and
// queries in, the generated files or what is wrong with the input out.
generate :: proc(pkg, schema, queries: string) -> (files: []File, problems: []string) {
	p: Problems
	schema_engine, sok := read_engine(schema, SCHEMA_FILE, &p)
	query_engine, qok := read_engine(queries, QUERIES_FILE, &p)
	if !sok || !qok {
		return nil, p.list[:]
	}
	if schema_engine != query_engine {
		problem(
			&p,
			QUERIES_FILE,
			0,
			"is for %s, but schema.sql is for %s",
			ENGINE_NAMES[query_engine],
			ENGINE_NAMES[schema_engine],
		)
		return nil, p.list[:]
	}
	qs := read_queries(queries, &p)
	switch schema_engine {
	case .Sqlite:
		files = generate_sqlite(pkg, schema, queries, qs, &p)
	case .Postgres:
		files = generate_postgres(pkg, schema, queries, qs, &p)
	}
	if len(p.list) > 0 {
		return nil, p.list[:]
	}
	return files, nil
}

@(private = "file")
generate_sqlite :: proc(pkg, schema, queries_text: string, qs: []Query, p: ^Problems) -> []File {
	cat, ok := describe_all_sqlite(schema, qs, p)
	if !ok {
		return nil
	}
	seeding := Sqlite_Seeding {
		schema = schema,
	}
	sets := build_data_sets(sqlite_seed_tables(cat), sqlite_seeder(&seeding), p)
	if len(p.list) > 0 {
		return nil
	}
	files := make([]File, 2)
	files[0] = File{CODE_FILE, emit_code(SQLITE, pkg, qs, schema, queries_text)}
	files[1] = File{TEST_FILE, emit_test(SQLITE_TEST, pkg, qs, sets)}
	return files
}

// package_name reads the package clause of a hand-written .odin file in dir,
// or of a generated one when there is nothing else, so the generated files
// join the package they sit in.
@(private = "file")
package_name :: proc(dir: string) -> (string, bool) {
	entries, err := os.read_directory_by_path(dir, -1, context.allocator)
	if err != nil {
		return "", false
	}
	fallback := ""
	for e in entries {
		if !strings.has_suffix(e.name, ".odin") {
			continue
		}
		text, rerr := os.read_entire_file(e.fullpath, context.allocator)
		if rerr != nil {
			continue
		}
		name, found := package_clause(string(text))
		if !found {
			continue
		}
		if e.name != CODE_FILE && e.name != TEST_FILE {
			return name, true
		}
		fallback = name
	}
	return fallback, fallback != ""
}

@(private = "file")
package_clause :: proc(text: string) -> (string, bool) {
	rest := text
	for line in strings.split_lines_iterator(&rest) {
		s := strings.trim_space(line)
		if strings.has_prefix(s, "package ") {
			return strings.trim_space(s[len("package "):]), true
		}
	}
	return "", false
}

@(private = "file")
generate_postgres :: proc(pkg, schema, queries_text: string, qs: []Query, p: ^Problems) -> []File {
	pg, ok := describe_all_postgres(schema, qs, p)
	if !ok {
		return nil
	}
	defer pg_close(&pg)
	tables := pg_seed_tables(&pg, p)
	// The data sets each run in a transaction of their own.
	if _, err := pq.exec(pg.conn, "ROLLBACK"); err != nil {
		problem(p, SCHEMA_FILE, 0, "ending the describe: %s", pg_text(err))
		return nil
	}
	seeding := Pg_Seeding {
		pg     = &pg,
		schema = schema,
	}
	sets := build_data_sets(tables, pg_seeder(&seeding), p)
	if len(p.list) > 0 {
		return nil
	}
	files := make([]File, 2)
	files[0] = File{CODE_FILE, emit_code(POSTGRES, pkg, qs, schema, queries_text)}
	files[1] = File{TEST_FILE, emit_test(POSTGRES_TEST, pkg, qs, sets)}
	return files
}
