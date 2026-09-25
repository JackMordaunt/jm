package pg_query_fuzz

import "core:strings"

import harness "jm:fuzz"

/*
A SQL generator, so a case needs no fixtures and no database. It is the
counterpart of wasm/fuzz's Wasm encoder: the properties want statements the
parser will mostly accept, because a suite that only ever feeds a parser
rubbish never leaves the failure path and never checks anything a tree
promises.

Every choice comes off the jm:fuzz Source and a zero byte gives the simplest
one, so shrinking converges on `SELECT 1` rather than wandering.

Gen carries one extra thing the Source does not: a variant. Two generators
over the same entropy with different variants emit statements with the same
shape and different literal values, which is exactly what
fingerprint_ignores_literals needs and is otherwise impossible to arrange from
a byte string.
*/

// Gen is a statement under construction.
Gen :: struct {
	src:     ^harness.Source,
	// Shifts every literal within its own pool, leaving the kind and the
	// shape of the statement alone. 0 is the statement as drawn.
	variant: int,
}

// gen starts a generator over a case's entropy.
gen :: proc(src: ^harness.Source, variant := 0) -> Gen {
	return Gen{src = src, variant = variant}
}

// DEPTH bounds a WHERE clause, so that a case does not spend its entropy on
// nesting and never reach the interesting part of the grammar.
DEPTH :: 4

// script draws between one and four statements, separated by semicolons, in
// the shape a migration or a script arrives as. A zero source gives one
// statement.
script :: proc(g: ^Gen, allocator := context.allocator) -> string {
	n := harness.integer_in(g.src, 1, 5)
	b := strings.builder_make(allocator)
	for i in 0 ..< n {
		if i > 0 {
			strings.write_string(&b, "; ")
		}
		strings.write_string(&b, statement(g, allocator))
	}
	return strings.to_string(b)
}

// statement draws one statement. A zero source gives `SELECT 1`.
statement :: proc(g: ^Gen, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	switch harness.integer_in(g.src, 0, 11) {
	case 1:
		// SELECT over a table, which is where most of the grammar is.
		strings.write_string(&b, "SELECT ")
		columns(g, &b)
		strings.write_string(&b, " FROM ")
		strings.write_string(&b, identifier(g, TABLES))
		where_clause(g, &b)
		if harness.boolean(g.src) {
			strings.write_string(&b, " ORDER BY ")
			strings.write_string(&b, identifier(g, COLUMNS))
		}
		if harness.boolean(g.src) {
			strings.write_string(&b, " LIMIT ")
			strings.write_string(&b, literal(g, NUMBERS))
		}
	case 2:
		strings.write_string(&b, "INSERT INTO ")
		strings.write_string(&b, identifier(g, TABLES))
		strings.write_string(&b, " (")
		strings.write_string(&b, identifier(g, COLUMNS))
		strings.write_string(&b, ") VALUES (")
		strings.write_string(&b, value(g))
		strings.write_string(&b, ")")
	case 3:
		strings.write_string(&b, "UPDATE ")
		strings.write_string(&b, identifier(g, TABLES))
		strings.write_string(&b, " SET ")
		strings.write_string(&b, identifier(g, COLUMNS))
		strings.write_string(&b, " = ")
		strings.write_string(&b, value(g))
		where_clause(g, &b)
	case 4:
		strings.write_string(&b, "DELETE FROM ")
		strings.write_string(&b, identifier(g, TABLES))
		where_clause(g, &b)
	case 5:
		// The utility statements: what is_utility has to separate out.
		strings.write_string(&b, "CREATE TABLE ")
		strings.write_string(&b, identifier(g, TABLES))
		strings.write_string(&b, " (")
		n := harness.integer_in(g.src, 1, 4)
		for i in 0 ..< n {
			if i > 0 {
				strings.write_string(&b, ", ")
			}
			strings.write_string(&b, identifier(g, COLUMNS))
			strings.write_byte(&b, ' ')
			strings.write_string(&b, harness.choice(g.src, TYPES))
		}
		strings.write_string(&b, ")")
	case 6:
		strings.write_string(&b, "DROP TABLE ")
		if harness.boolean(g.src) {
			strings.write_string(&b, "IF EXISTS ")
		}
		strings.write_string(&b, identifier(g, TABLES))
	case 7:
		strings.write_string(&b, "ALTER TABLE ")
		strings.write_string(&b, identifier(g, TABLES))
		strings.write_string(&b, " ADD COLUMN ")
		strings.write_string(&b, identifier(g, COLUMNS))
		strings.write_byte(&b, ' ')
		strings.write_string(&b, harness.choice(g.src, TYPES))
	case 8:
		strings.write_string(&b, harness.choice(g.src, CONTROL))
	case 9:
		strings.write_string(&b, "WITH cte AS (SELECT ")
		strings.write_string(&b, literal(g, NUMBERS))
		strings.write_string(&b, " AS n) SELECT n FROM cte")
		where_clause(g, &b)
	case 10:
		strings.write_string(&b, "GRANT SELECT ON ")
		strings.write_string(&b, identifier(g, TABLES))
		strings.write_string(&b, " TO ")
		strings.write_string(&b, identifier(g, ROLES))
	case:
		// A zero byte lands here: the simplest statement there is.
		strings.write_string(&b, "SELECT ")
		strings.write_string(&b, literal(g, NUMBERS))
	}
	return strings.to_string(b)
}

// columns draws a select list. A zero source gives one column.
@(private)
columns :: proc(g: ^Gen, b: ^strings.Builder) {
	n := harness.integer_in(g.src, 1, 4)
	for i in 0 ..< n {
		if i > 0 {
			strings.write_string(b, ", ")
		}
		strings.write_string(b, identifier(g, COLUMNS))
	}
}

// where_clause draws an optional WHERE. A zero source omits it.
@(private)
where_clause :: proc(g: ^Gen, b: ^strings.Builder) {
	if !harness.boolean(g.src) {
		return
	}
	strings.write_string(b, " WHERE ")
	predicate(g, b, DEPTH)
}

// predicate draws a boolean expression, bounded by depth.
@(private)
predicate :: proc(g: ^Gen, b: ^strings.Builder, depth: int) {
	if depth > 0 && harness.integer_in(g.src, 0, 4) == 3 {
		strings.write_string(b, "(")
		predicate(g, b, depth - 1)
		strings.write_byte(b, ' ')
		strings.write_string(b, harness.choice(g.src, CONNECTIVES))
		strings.write_byte(b, ' ')
		predicate(g, b, depth - 1)
		strings.write_string(b, ")")
		return
	}
	strings.write_string(b, identifier(g, COLUMNS))
	strings.write_byte(b, ' ')
	strings.write_string(b, harness.choice(g.src, COMPARISONS))
	strings.write_byte(b, ' ')
	strings.write_string(b, value(g))
}

// value draws a literal of some kind. The kind comes off the Source, so two
// variants of one statement always agree about it; only the value moves.
@(private)
value :: proc(g: ^Gen) -> string {
	switch harness.integer_in(g.src, 0, 3) {
	case 1:
		return literal(g, STRINGS)
	case 2:
		return literal(g, KEYWORDS)
	case:
		return literal(g, NUMBERS)
	}
}

// literal draws from a pool, shifted by the variant. Two Gens over the same
// entropy with different variants therefore pick different members of the
// same pool at the same place in the same statement.
@(private)
literal :: proc(g: ^Gen, pool: []string) -> string {
	i := harness.integer_in(g.src, 0, len(pool))
	return pool[(i + g.variant) % len(pool)]
}

// identifier draws a name. Names are not literals, so the variant leaves
// them alone: a statement over another table is another statement, and its
// fingerprint should differ.
@(private)
identifier :: proc(g: ^Gen, pool: []string) -> string {
	return harness.choice(g.src, pool)
}

// The vocabulary. Each pool's first entry is what a zero byte draws.
TABLES := []string{"t", "rig", "public.rig", "order_line", `"Quoted Name"`, "site_2"}
COLUMNS := []string{"a", "id", "serial_number", "created_at", `"odd column"`, "b"}
ROLES := []string{"reader", "app_user", "public"}
TYPES := []string{"int", "text", "boolean", "timestamptz", "numeric(10,2)", "jsonb"}
CONTROL := []string{"BEGIN", "COMMIT", "ROLLBACK", "VACUUM", "ANALYZE", "SET search_path = public"}
COMPARISONS := []string{"=", "<>", "<", ">=", "IS DISTINCT FROM"}
CONNECTIVES := []string{"AND", "OR"}

// The literal pools. Members of one pool have to be interchangeable without
// changing the shape of the statement, which is what
// variants_differ_only_in_their_literals checks by normalizing both and
// comparing. Negative numbers are left out because they did not survive that
// check.
NUMBERS := []string{"1", "0", "42", "1000000", "3.5", "2147483648"}
STRINGS := []string{"'a'", "''", "'longer text'", "'it''s quoted'", "'x'"}
KEYWORDS := []string{"NULL", "true", "false"}

// WELL_FORMED is the corpus jm:fuzz's damage works from, for the cases that
// want a statement that was valid until one byte of it was not.
WELL_FORMED := []string {
	`SELECT 1`,
	`SELECT a, b FROM rig WHERE id = 1`,
	`INSERT INTO rig (serial_number) VALUES ('x')`,
	`UPDATE rig SET serial_number = 'y' WHERE id = 2`,
	`DELETE FROM rig WHERE id = 3`,
	`CREATE TABLE site (id int, name text)`,
	`ALTER TABLE site ADD COLUMN note text`,
	`GRANT SELECT ON rig TO reader`,
	`WITH cte AS (SELECT 1 AS n) SELECT n FROM cte`,
	`BEGIN; UPDATE rig SET a = 1; COMMIT`,
	`SELECT $1 FROM t WHERE a = $2`,
	`VACUUM`,
	// The rest reach further into the grammar, so a flipped byte lands on
	// node types the generator above never builds.
	`SELECT row_number() OVER (PARTITION BY a ORDER BY b) FROM t`,
	`SELECT CASE WHEN a THEN 1 ELSE 2 END, a::text, ARRAY[1, 2] FROM t`,
	`SELECT * FROM t JOIN u ON t.id = u.id WHERE t.a IN (SELECT b FROM v)`,
	`INSERT INTO t (a) VALUES (1) ON CONFLICT (a) DO UPDATE SET b = EXCLUDED.b RETURNING *`,
	`MERGE INTO t USING u ON t.id = u.id WHEN MATCHED THEN UPDATE SET a = u.a`,
	`CREATE TABLE t (id serial PRIMARY KEY, a text NOT NULL DEFAULT 'x', CHECK (id > 0))`,
	`CREATE INDEX i ON t USING gin (a) WHERE b IS NOT NULL`,
	`EXPLAIN (ANALYZE) SELECT 1`,
	`SET LOCAL search_path = a, b`,
	`COPY t (a) FROM STDIN WITH (FORMAT csv)`,
}
