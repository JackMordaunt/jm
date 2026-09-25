package pq_fuzz

import "core:strings"

import harness "jm:fuzz"

// WELL_FORMED is what damage breaks: statements the server runs, chosen to
// reach the parts of the protocol the binding handles — rows, NULLs, the
// empty string, command tags with a count, notices, errors raised on
// purpose, several statements in one call, and COPY, which the binding
// refuses and libpq has to clean up after.
WELL_FORMED := []string {
	`SELECT 1`,
	`SELECT NULL, '', 'x'`,
	`SELECT 'it''s', E'tab\there', $$dollar$$`,
	`SELECT n, n * 2 FROM generate_series(1, 5) AS n`,
	`VALUES (1, 'a'), (2, NULL)`,
	`SELECT '{"a":[1,2,null]}'::jsonb -> 'a'`,
	`SELECT ARRAY[1, 2, 3], '日本語'::text, '🐘'`,
	`SELECT 1/0`,
	`SELECT 'abc'::int`,
	`SELECT nope FROM nowhere`,
	`CREATE TEMP TABLE t(k int PRIMARY KEY, v text); INSERT INTO t VALUES (1, 'a'), (2, NULL)`,
	`CREATE TEMP TABLE t(k int PRIMARY KEY); INSERT INTO t VALUES (1), (1)`,
	`CREATE TEMP TABLE t(v text); INSERT INTO t SELECT 'r' FROM generate_series(1, 3); UPDATE t SET v = 's'`,
	`DROP TABLE IF EXISTS never_was`,
	`DO $$ BEGIN RAISE NOTICE 'hello %', 1; END $$`,
	`DO $$ BEGIN RAISE EXCEPTION 'boom' USING ERRCODE = 'P0001', HINT = 'a hint'; END $$`,
	`SET LOCAL default_transaction_read_only = on; SHOW default_transaction_read_only`,
	`SAVEPOINT s; SELECT 1; ROLLBACK TO SAVEPOINT s`,
	`COPY (SELECT 1) TO STDOUT`,
	`CREATE TEMP TABLE c(n int); COPY c FROM STDIN`,
	`SELECT 1; SELECT 2`,
	`COMMIT`,
	`-- just a comment`,
	``,
}

// EXPRESSIONS, OPERATORS and CASTS are what generate assembles a SELECT
// list from.
@(private)
EXPRESSIONS := []string {
	`1`,
	`-1`,
	`0.5`,
	`NULL`,
	`''`,
	`'x'`,
	`'it''s'`,
	`E'\\x41'`,
	`'日本'`,
	`true`,
	`now()`,
	`current_user`,
	`length('abc')`,
	`upper('ü')`,
	`repeat('ab', 3)`,
	`'2026-09-25'::date`,
	`'{1,2}'::int[]`,
	`'{"k": null}'::jsonb`,
	`1/0`,
	`'x'::int`,
	`nope`,
	`$1`,
	`(SELECT 1)`,
	`(SELECT 1 UNION SELECT 2)`,
}

@(private)
OPERATORS := []string{" + ", " || ", " = ", " AND ", " < ", ", "}

@(private)
CASTS := []string{"", "", "::text", "::int", "::numeric", "::bool", "::jsonb"}

// PIECES is what a round-tripped value is assembled from: everything that
// breaks quoting, as jm:fuzz's AWKWARD does, plus the backslash and dollar
// forms PostgreSQL adds to string literals and the escapes an identifier
// uses.
@(private)
PIECES := []string {
	"",
	"a",
	" ",
	"'",
	"''",
	`"`,
	`""`,
	"\\",
	"\\'",
	"E'",
	"$$",
	"$tag$",
	"$1",
	";",
	"--",
	"/*",
	"*/",
	"\n",
	"\t",
	"\x00",
	"%",
	"é",
	"日本",
	"\U0001F418",
	"\xff",
	"\xc3\x28",
	"U&'\\0041'",
	"\\x41",
}

// generate assembles a SELECT from EXPRESSIONS. A zero source gives
// `SELECT 1`.
generate :: proc(src: ^harness.Source) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_string(&b, "SELECT ")
	n := 1 + harness.integer_in(src, 0, 4)
	for i in 0 ..< n {
		if i > 0 {
			strings.write_string(&b, harness.choice(src, OPERATORS))
		}
		strings.write_string(&b, harness.choice(src, EXPRESSIONS))
		strings.write_string(&b, harness.choice(src, CASTS))
	}
	if harness.boolean(src) {
		strings.write_string(&b, " FROM generate_series(1, 3) AS g")
	}
	return strings.to_string(b)
}
