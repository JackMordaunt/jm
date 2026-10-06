package main

import "core:fmt"
import "core:strings"
import "core:testing"

import "jm:sqlite3"

TEST_SCHEMA :: `-- engine: sqlite
CREATE TABLE todo(
	id INTEGER PRIMARY KEY,
	title TEXT NOT NULL,
	done INTEGER NOT NULL DEFAULT 0,
	note TEXT,
	score REAL NOT NULL DEFAULT 0,
	body BLOB,
	extra ANY
) STRICT;
CREATE TABLE tag(todo_id INTEGER NOT NULL, name TEXT NOT NULL) STRICT;
CREATE TABLE plain(k TEXT PRIMARY KEY) STRICT;
CREATE VIEW open_todo AS SELECT id, title FROM todo WHERE done = 0;
CREATE VIEW both_names AS SELECT title FROM todo UNION SELECT name FROM tag;
CREATE VIEW via_both AS SELECT title FROM both_names;
CREATE VIRTUAL TABLE doc USING fts5(body);
`

// describe_one describes one query block against TEST_SCHEMA.
describe_one :: proc(block: string) -> (q: Query, problems: []string) {
	p: Problems
	qs := read_queries(strings.concatenate({"-- engine: sqlite\n", block}), &p)
	if len(qs) != 1 {
		return {}, p.list[:]
	}
	_, _ = describe_all_sqlite(TEST_SCHEMA, qs, &p)
	return qs[0], p.list[:]
}

field :: proc(q: Query, name: string) -> (f: Field, ok: bool) {
	for x in q.fields {
		if x.name == name {
			return x, true
		}
	}
	return {}, false
}

expect_field :: proc(t: ^testing.T, q: Query, name: string, want: Type, loc := #caller_location) {
	f, ok := field(q, name)
	testing.expectf(t, ok, "%s has no field %s: %v", q.name, name, q.fields, loc = loc)
	testing.expectf(
		t,
		f.type == want,
		"%s.%s is %v, want %v (%s)",
		q.name,
		name,
		f.type,
		want,
		f.why,
		loc = loc,
	)
}

expect_problem :: proc(t: ^testing.T, problems: []string, part: string, loc := #caller_location) {
	for msg in problems {
		if strings.contains(msg, part) {
			return
		}
	}
	testing.expectf(t, false, "no problem mentions %q: %v", part, problems, loc = loc)
}

@(test)
direct_columns_take_the_declared_type_and_nullability :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	q, problems := describe_one(
		`
-- name: all :many
-- params: id: i64
SELECT id, title, done, note, score, body FROM todo WHERE id > @id ORDER BY title`,
	)
	testing.expect_value(t, len(problems), 0)
	expect_field(t, q, "id", {.I64, false})
	expect_field(t, q, "title", {.String, false})
	expect_field(t, q, "done", {.I64, false})
	expect_field(t, q, "note", {.String, true})
	expect_field(t, q, "score", {.F64, false})
	expect_field(t, q, "body", {.Bytes, true})
	testing.expect_value(t, len(q.params), 1)
}

// A view, a CTE and a subquery in FROM are followed to the base table.
@(test)
views_and_subqueries_reach_the_base_table :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?]string {
		"SELECT title FROM open_todo",
		"WITH c AS (SELECT title FROM todo) SELECT title FROM c",
		"SELECT s.title FROM (SELECT title FROM todo) s",
	}
	for sql in cases {
		q, problems := describe_one(fmt.tprintf("-- name: q :many\n%s", sql))
		testing.expectf(t, len(problems) == 0, "%s: %v", sql, problems)
		f, _ := field(q, "title")
		testing.expectf(t, f.type.kind == .String, "%s: %v", sql, f.type)
	}
}

@(test)
rowid_and_strict_primary_keys_are_not_null :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	q, problems := describe_one(`
-- name: keys :many
SELECT todo.rowid AS r, k FROM todo, plain`)
	testing.expect_value(t, len(problems), 0)
	expect_field(t, q, "r", {.I64, false})
	expect_field(t, q, "k", {.String, false})

	// The inference above rests on SQLite refusing NULL in a STRICT table's
	// PRIMARY KEY, which an ordinary table would accept.
	db, err := sqlite3.open(sqlite3.MEMORY)
	testing.expect_value(t, err, nil)
	defer sqlite3.close(&db)
	testing.expect_value(t, sqlite3.exec(db, "CREATE TABLE plain(k TEXT PRIMARY KEY) STRICT"), nil)
	f, refused := sqlite3.exec(db, "INSERT INTO plain VALUES (NULL)").(sqlite3.Fault)
	testing.expect(t, refused)
	testing.expect_value(t, f.extended, sqlite3.CONSTRAINT_NOTNULL)
}

// tag has no index on todo_id, so SQLite builds an automatic index for the
// join, and the NullRow falls on that index's cursor rather than tag's.
@(test)
an_outer_join_makes_only_its_far_side_maybe :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	q, problems := describe_one(
		`
-- name: tagged :many
SELECT t.title, g.name FROM todo t LEFT JOIN tag g ON g.todo_id = t.id`,
	)
	testing.expect_value(t, len(problems), 0)
	expect_field(t, q, "title", {.String, false})
	expect_field(t, q, "name", {.String, true})
	f, _ := field(q, "name")
	testing.expect(t, strings.contains(f.why, "outer side"), f.why)

	// The case above covers the automatic index only while SQLite builds one.
	db, err := sqlite3.open(sqlite3.MEMORY)
	testing.expect_value(t, err, nil)
	defer sqlite3.close(&db)
	testing.expect_value(t, sqlite3.exec(db, TEST_SCHEMA), nil)
	plan, perr := sqlite3.prepare(
		db,
		"EXPLAIN SELECT t.title, g.name FROM todo t LEFT JOIN tag g ON g.todo_id = t.id",
	)
	testing.expect_value(t, perr, nil)
	autoindex := false
	for sqlite3.next(&plan) {
		autoindex = autoindex || sqlite3.text(plan, 1) == "OpenAutoindex"
	}
	sqlite3.finish(&plan)
	testing.expect(t, autoindex, "the join no longer builds an automatic index")
}

// Each of these can yield NULL for a NOT NULL column, so a NOT NULL column
// beside them is Maybe too, with the opcode that made it so.
@(test)
aggregates_and_subqueries_make_not_null_columns_maybe :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?]string {
		"SELECT title, count(*) AS \"n: i64\" FROM todo",
		"SELECT title, (SELECT name FROM tag LIMIT 1) AS \"tag: Maybe(string)\" FROM todo",
		"SELECT title FROM todo WHERE id IN (SELECT todo_id FROM tag)",
	}
	for sql in cases {
		q, problems := describe_one(fmt.tprintf("-- name: q :many\n%s", sql))
		testing.expectf(t, len(problems) == 0, "%s: %v", sql, problems)
		f, _ := field(q, "title")
		testing.expectf(
			t,
			f.type == Type{.String, true} && f.why != "",
			"%s: %v %q",
			sql,
			f.type,
			f.why,
		)
	}
}

@(test)
returning_columns_are_typed :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	q, problems := describe_one(
		`
-- name: add :one
-- params: title: string
INSERT INTO todo(title) VALUES (@title) RETURNING id, title`,
	)
	testing.expect_value(t, len(problems), 0)
	expect_field(t, q, "id", {.I64, false})
	expect_field(t, q, "title", {.String, false})
}

@(test)
annotations_set_and_narrow_types :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	q, problems := describe_one(
		`
-- name: q :many
SELECT done AS "done: bool", count(*) AS "n: i64",
	note AS "note: string", extra AS "extra: f64"
FROM todo GROUP BY id`,
	)
	testing.expect_value(t, len(problems), 0)
	expect_field(t, q, "done", {.Bool, false})
	expect_field(t, q, "n", {.I64, false})
	expect_field(t, q, "note", {.String, false})
	expect_field(t, q, "extra", {.F64, false})
	f, _ := field(q, "n")
	testing.expect(t, f.annotated)
}

@(test)
what_sqlite_does_not_type_must_be_annotated :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?][2]string {
		{"SELECT count(*) AS n FROM todo", "is an expression"},
		{"SELECT title FROM todo UNION SELECT name FROM tag", "compound SELECT"},
		{"SELECT title FROM via_both", "compound SELECT"},
		{"SELECT extra FROM todo", "declares no type"},
		{"SELECT body FROM doc", "declares no type"},
		{"SELECT 1", "cannot name a field"},
	}
	for c in cases {
		_, problems := describe_one(fmt.tprintf("-- name: q :many\n%s", c[0]))
		expect_problem(t, problems, c[1])
	}
}

@(test)
annotations_must_fit_the_column :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	_, problems := describe_one("-- name: q :many\nSELECT title AS \"title: i64\" FROM todo")
	expect_problem(t, problems, "declared TEXT, which cannot hold i64")
	_, problems = describe_one("-- name: q :many\nSELECT title AS \"title: text\" FROM todo")
	expect_problem(t, problems, "is not a type")
}

@(test)
parameters_must_be_named_and_typed :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?][2]string {
		{"-- name: q :exec\nDELETE FROM todo WHERE id = ?", "name every parameter @name"},
		{"-- name: q :exec\nDELETE FROM todo WHERE id = :id", "name every parameter @name"},
		{"-- name: q :exec\nDELETE FROM todo WHERE id = @id", "@id has no type"},
		{
			"-- name: q :exec\n-- params: id: i64, gone: i64\nDELETE FROM todo WHERE id = @id",
			"names gone",
		},
		{"-- name: q :exec\n-- params: id: int\nDELETE FROM todo WHERE id = @id", "is not a type"},
		{
			"-- name: q :exec\n-- params: db: i64\nDELETE FROM todo WHERE id = @db",
			"cannot name a parameter",
		},
	}
	for c in cases {
		_, problems := describe_one(c[0])
		expect_problem(t, problems, c[1])
	}
}

// A parameter used twice is bound once, in the order SQLite numbers it.
@(test)
parameters_bind_in_sqlite_s_order :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	q, problems := describe_one(
		`
-- name: q :exec
-- params: id: i64, done: bool
UPDATE todo SET done = @done WHERE id = @id AND done != @done`,
	)
	testing.expect_value(t, len(problems), 0)
	testing.expect_value(t, len(q.params), 2)
	testing.expect_value(t, q.params[0].name, "done")
	testing.expect_value(t, q.params[1].name, "id")

	// The proc takes them as the -- params: line declares them, so rewriting
	// the SQL cannot reorder a caller's arguments; the bind follows SQLite.
	files, gen_problems := generate(
		"p",
		TEST_SCHEMA,
		"-- engine: sqlite\n-- name: q :exec\n-- params: id: i64, done: bool\n" +
		"UPDATE todo SET done = @done WHERE id = @id",
	)
	testing.expect_value(t, len(gen_problems), 0)
	code := files[0].text
	signature := strings.index(code, "\tid: i64,\n\tdone: bool,\n")
	binding := strings.index(code, "\t\tdone,\n\t\tid,\n")
	testing.expectf(
		t,
		signature > 0 && binding > signature,
		"signature at %d, binding at %d",
		signature,
		binding,
	)
}

@(test)
result_tags_must_match_the_statement :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?][2]string {
		{"-- name: q :exec\nSELECT id FROM todo", "tag it :one or :many"},
		{"-- name: q :one\nDELETE FROM todo", "tag it :exec, :rows or :last_id"},
		{"-- name: q :rows\nSELECT 1 WHERE 0", "tag it :one or :many"},
		{"-- name: q :all\nDELETE FROM todo", "unknown result"},
		{"-- name: q :exec\nDELETE FROM todo; DELETE FROM tag", "more than one statement"},
		{"-- name: q :many\nSELECT nope FROM todo", "no such column"},
		{"-- name: check :exec\nDELETE FROM todo", "cannot name a query"},
		{"-- name: q :many\nSELECT id, id FROM todo", "two columns are named id"},
	}
	for c in cases {
		_, problems := describe_one(c[0])
		expect_problem(t, problems, c[1])
	}
}

@(test)
the_files_must_agree_on_a_known_engine :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?][3]string {
		{"CREATE TABLE a(x INTEGER) STRICT;", "-- engine: sqlite\n", "first line must say"},
		{"-- engine: sqlite\n", "-- engine: mysql\n", "unknown engine"},
		{"-- engine: sqlite\n", "-- engine: postgres\n", "schema.sql is for sqlite"},
		{"-- engine: postgres\n", "-- engine: postgres\n", "does not generate for postgres yet"},
		{
			"-- engine: sqlite\nCREATE TABLE a(x INTEGER);",
			"-- engine: sqlite\n",
			"table a is not STRICT",
		},
		{"-- engine: sqlite\n", "-- engine: sqlite\nSELECT 1;\n", "belongs to no query"},
		{
			"-- engine: sqlite\n",
			"-- engine: sqlite\n-- name: a :exec\nSELECT 1 WHERE 0\n-- name: a :exec\nSELECT 1 WHERE 0\n",
			"already the name",
		},
		{
			"-- engine: sqlite\n",
			"-- engine: sqlite\n-- name: a :many\nSELECT 1 AS \"x: i64\"\n" +
			"-- name: a_all :exec\nSELECT 1 WHERE 0\n",
			"a_all is a name the :many query a generates",
		},
	}
	for c in cases {
		files, problems := generate("p", c[0], c[1])
		testing.expect_value(t, len(files), 0)
		expect_problem(t, problems, c[2])
	}
}

@(test)
scan_skips_literals_and_comments :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	words, more := scan(`SELECT 'union' AS "Union", x'00' -- union
	/* except */ FROM [t];  `)
	testing.expect(t, !more)
	testing.expect(t, !is_compound(words))
	testing.expect(t, mentions(words, "union"), "a quoted name is still a name")
	testing.expect(t, mentions(words, "T"))
	_, more = scan("SELECT 1; SELECT 2")
	testing.expect(t, more)
	words, _ = scan("SELECT a FROM b EXCEPT SELECT a FROM c")
	testing.expect(t, is_compound(words))
}

// A row a CHECK refuses falls back to the base values, and the set says so.
@(test)
a_refused_seed_row_falls_back :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	schema := "-- engine: sqlite\nCREATE TABLE a(s TEXT NOT NULL CHECK (length(s) > 0)) STRICT;"
	p: Problems
	cat, ok := describe_all_sqlite(schema, nil, &p)
	testing.expect(t, ok)
	sets := sqlite_data_sets(schema, cat, &p)
	testing.expect_value(t, len(p.list), 0)
	low: Data_Set
	for s in sets {
		if s.name == "low" {
			low = s
		}
	}
	testing.expect_value(t, low.seed, "INSERT INTO \"a\"(\"s\")\nVALUES ('a');\n")
	testing.expect_value(t, len(low.notes), 1)

	schema = "-- engine: sqlite\nCREATE TABLE a(s TEXT NOT NULL CHECK (s = 'never')) STRICT;"
	clear(&p.list)
	cat, _ = describe_all_sqlite(schema, nil, &p)
	_ = sqlite_data_sets(schema, cat, &p)
	expect_problem(t, p.list[:], "refuses every row")
}

@(test)
literals_escape_what_odin_source_cannot_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	cases := [?][2]string {
		{"SELECT \"x\"\n", "`SELECT \"x\"\n`"},
		{"a`b", "\"a`b\""},
		{"\x00\xff", "\"\\x00\\xff\""},
		{"zß€", "`zß€`"},
	}
	for c in cases {
		sb: strings.Builder
		write_string_literal(&sb, c[0])
		testing.expect_value(t, strings.to_string(sb), c[1])
	}
}

// The checked-in example is what the generator writes now, so a change to
// the generator that changes its output shows up as a failing test until
// the example is regenerated with `just sqlgen tools/jm-sqlgen/testdata/notes`.
@(test)
testdata_is_up_to_date :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	files, problems := generate(
		"notes_queries",
		#load("testdata/notes/schema.sql", string),
		#load("testdata/notes/queries.sql", string),
	)
	testing.expect_value(t, len(problems), 0)
	testing.expect_value(t, len(files), 2)
	testing.expect(
		t,
		files[0].text == #load("testdata/notes/queries_gen.odin", string),
		"queries_gen.odin is stale",
	)
	testing.expect(
		t,
		files[1].text == #load("testdata/notes/queries_gen_test.odin", string),
		"queries_gen_test.odin is stale",
	)
}

// Only :one's second-row error needs core:fmt, and Odin refuses an unused
// import, so a package without a :one must not import it.
@(test)
fmt_is_imported_only_for_one :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	exec_only := "-- engine: sqlite\n-- name: wipe :exec\nDELETE FROM tag\n"
	files, problems := generate("p", TEST_SCHEMA, exec_only)
	testing.expect_value(t, len(problems), 0)
	testing.expect(t, !strings.contains(files[0].text, `import "core:fmt"`))
	one := "-- engine: sqlite\n-- name: first :one\nSELECT name FROM tag LIMIT 1\n"
	files, problems = generate("p", TEST_SCHEMA, one)
	testing.expect_value(t, len(problems), 0)
	testing.expect(t, strings.contains(files[0].text, `import "core:fmt"`))
}

sqlite_data_sets :: proc(schema: string, cat: Catalog, p: ^Problems) -> []Data_Set {
	seeding := Sqlite_Seeding {
		schema = schema,
	}
	return build_data_sets(sqlite_seed_tables(cat), sqlite_seeder(&seeding), p)
}
