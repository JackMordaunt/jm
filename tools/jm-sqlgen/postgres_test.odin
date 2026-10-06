package main

import "core:fmt"
import "core:log"
import "core:strings"
import "core:testing"

import "jm:pq/testdb"

PG_SCHEMA :: `-- engine: postgres
CREATE TYPE mood AS ENUM ('calm', 'busy');
CREATE DOMAIN short_text AS text;
CREATE TABLE todo(
	id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
	title short_text NOT NULL,
	done boolean NOT NULL DEFAULT false,
	small int2 NOT NULL DEFAULT 0,
	rank int4 NOT NULL DEFAULT 0,
	ratio float4 NOT NULL DEFAULT 0,
	price numeric,
	mood mood NOT NULL DEFAULT 'calm',
	tags text[]
);
CREATE TABLE tag(todo_id bigint NOT NULL, name text NOT NULL);
CREATE VIEW open_todo AS SELECT id, title FROM todo WHERE NOT done;
`

// pg_server reports whether the throwaway server is up, logging why not:
// these tests skip without one, as jm:pq's do.
pg_server :: proc() -> bool {
	if ok, why := testdb.start(); !ok {
		log.warnf("skipped, no PostgreSQL server to describe against: %s", why)
		return false
	}
	return true
}

// describe_pg describes one query block against PG_SCHEMA.
describe_pg :: proc(block: string) -> (q: Query, problems: []string) {
	p: Problems
	qs := read_queries(strings.concatenate({"-- engine: postgres\n", block}), &p)
	if len(qs) != 1 {
		return {}, p.list[:]
	}
	pg, ok := describe_all_postgres(PG_SCHEMA, qs, &p)
	if ok {
		pg_close(&pg)
	}
	return qs[0], p.list[:]
}

// A parameter is @name where the grammar reads the prefix operator @ hard
// against a name: not inside a string, a comment or a dollar-quoted body,
// and not the containment operator @>.
@(test)
pg_parameters_are_found_by_the_grammar :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	if !pg_server() {
		return
	}
	q, problems := describe_pg(
		`
-- name: q :many
SELECT title, '@id' AS quoted, $$ @id $$ AS dollar -- @id
FROM todo WHERE id = @id + 1 AND rank = @rank AND id <> @id
AND ARRAY[1] @> ARRAY[1]`,
	)
	testing.expect_value(t, len(problems), 0)
	testing.expect_value(t, len(q.params), 2)
	testing.expect_value(t, q.params[0].name, "id")
	testing.expect_value(t, q.params[1].type.kind, Kind.I32)
	testing.expect(t, strings.contains(q.sql, "id = $1 + 1 AND rank = $2 AND id <> $1"), q.sql)
	testing.expect(
		t,
		strings.contains(q.sql, "'@id'") && strings.contains(q.sql, "$$ @id $$"),
		q.sql,
	)
	testing.expect(t, strings.contains(q.sql, "-- @id"), q.sql)

	_, problems = describe_pg("-- name: q :many\nSELECT title FROM todo WHERE id = $1")
	expect_problem(t, problems, "rather than $n")
}

@(test)
pg_types_are_exact :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	if !pg_server() {
		return
	}
	q, problems := describe_pg(
		`
-- name: q :many
SELECT id, title, done, small, rank, ratio, price, mood FROM todo`,
	)
	testing.expect_value(t, len(problems), 0)
	expect_field(t, q, "id", {.I64, false})
	expect_field(t, q, "title", {.String, false}) // a domain over text
	expect_field(t, q, "done", {.Bool, false})
	expect_field(t, q, "small", {.I16, false})
	expect_field(t, q, "rank", {.I32, false})
	expect_field(t, q, "ratio", {.F32, false})
	expect_field(t, q, "price", {.String, true}) // numeric, as its exact text
	expect_field(t, q, "mood", {.String, false}) // an enum, as its label

	_, problems = describe_pg("-- name: q :many\nSELECT tags FROM todo")
	expect_problem(t, problems, "does not map: cast it")
	q, problems = describe_pg("-- name: q :many\nSELECT tags::text FROM todo")
	testing.expect_value(t, len(problems), 0)
}

// PostgreSQL says a column's source is NOT NULL without regard to how the
// statement reads it, so the joins and groupings that can make it NULL are
// read from the parse tree.
@(test)
pg_nullability_follows_the_statement :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	if !pg_server() {
		return
	}
	cases := [?]struct {
		sql:      string,
		field:    string,
		nullable: bool,
	} {
		{"SELECT t.title, g.name FROM todo t LEFT JOIN tag g ON g.todo_id = t.id", "title", false},
		{"SELECT t.title, g.name FROM todo t LEFT JOIN tag g ON g.todo_id = t.id", "name", true},
		{"SELECT t.title, g.name FROM todo t RIGHT JOIN tag g ON g.todo_id = t.id", "title", true},
		{"SELECT t.title, g.name FROM todo t FULL JOIN tag g ON g.todo_id = t.id", "name", true},
		{
			"WITH c AS (SELECT name, todo_id FROM tag) " +
			"SELECT t.title, c.name FROM todo t LEFT JOIN c ON c.todo_id = t.id",
			"name",
			true,
		},
		{"SELECT title, count(*) AS \"n: i64\" FROM todo GROUP BY ROLLUP (title)", "title", true},
		{"SELECT title FROM todo GROUP BY title", "title", false},
		{"SELECT title FROM open_todo", "title", true},
		{"SELECT upper(title) AS title FROM todo", "title", true},
		{"SELECT title FROM todo UNION SELECT name FROM tag", "title", true},
	}
	for c in cases {
		q, problems := describe_pg(fmt.tprintf("-- name: q :many\n%s", c.sql))
		testing.expectf(t, len(problems) == 0, "%s: %v", c.sql, problems)
		f, _ := field(q, c.field)
		right := f.type.nullable == c.nullable
		testing.expectf(t, right, "%s: %s is %v (%s)", c.sql, c.field, f.type, f.why)
	}
}

@(test)
pg_params_line_must_agree_with_the_server :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	if !pg_server() {
		return
	}
	q, problems := describe_pg(
		`
-- name: q :exec
-- params: rank: i32, price: Maybe(string)
UPDATE todo SET price = @price::numeric WHERE rank = @rank`,
	)
	testing.expect_value(t, len(problems), 0)
	testing.expect_value(t, q.annotations[0].name, "rank")
	testing.expect_value(t, q.params[0].name, "price")
	testing.expect(t, q.params[0].type.nullable)

	cases := [?][2]string {
		{
			"-- params: rank: i64\nUPDATE todo SET done = true WHERE rank = @rank",
			"is i32 on the server, not i64",
		},
		{
			"-- params: rank: i32\nUPDATE todo SET done = @done WHERE rank = @rank",
			"does not name @done",
		},
		{
			"-- params: rank: i32, gone: i32\nUPDATE todo SET done = true WHERE rank = @rank",
			"names gone",
		},
	}
	for c in cases {
		_, problems = describe_pg(fmt.tprintf("-- name: q :exec\n%s", c[0]))
		expect_problem(t, problems, c[1])
	}
	_, problems = describe_pg("-- name: q :last_id\nINSERT INTO tag VALUES (1, 'a')")
	expect_problem(t, problems, "no last insert id")
	_, problems = describe_pg("-- name: q :many\nSELECT nope FROM todo")
	expect_problem(t, problems, "column \"nope\" does not exist")
}

// The checked-in PostgreSQL example is what the generator writes now.
@(test)
pg_testdata_is_up_to_date :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	if !pg_server() {
		return
	}
	files, problems := generate(
		"notes_pg_queries",
		#load("testdata/notes_pg/schema.sql", string),
		#load("testdata/notes_pg/queries.sql", string),
	)
	testing.expect_value(t, len(problems), 0)
	testing.expect_value(t, len(files), 2)
	testing.expect(
		t,
		files[0].text == #load("testdata/notes_pg/queries_gen.odin", string),
		"queries_gen.odin is stale",
	)
	testing.expect(
		t,
		files[1].text == #load("testdata/notes_pg/queries_gen_test.odin", string),
		"queries_gen_test.odin is stale",
	)
}
