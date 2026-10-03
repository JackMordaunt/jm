package pg_query

import "core:encoding/json"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:sync"
import "core:testing"
import "core:thread"

// The node types in nodes.odin are generated from the schema libpg_query
// ships, and this is what keeps them honest between regenerations: every node
// and every field the Odin side names has to still be in that schema. A
// PostgreSQL major that renames a field therefore fails here, at just test,
// rather than by quietly decoding nothing into it at runtime.
// Loaded at compile time, so the test finds the schema whatever directory it
// is run from, and a vendored tree without it fails to build the tests.
SCHEMA_JSON :: #load("vendor/srcdata/struct_defs.json")

@(test)
schema_conforms :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	value, jerr := json.parse(SCHEMA_JSON, .JSON, true)
	testing.expect_value(t, jerr, json.Error.None)
	schema, is_object := value.(json.Object)
	testing.expect(t, is_object, "struct_defs.json is an object of sections")
	if !is_object {
		return
	}

	for node in SCHEMA {
		section, has_section := schema[node.section].(json.Object)
		testing.expectf(t, has_section, "the schema lost the section %s", node.section)
		if !has_section {
			continue
		}
		entry, has_node := section[node.node].(json.Object)
		testing.expectf(t, has_node, "the schema lost %s/%s", node.section, node.node)
		if !has_node {
			continue
		}
		fields, _ := entry["fields"].(json.Array)
		named := make(map[string]bool, context.temp_allocator)
		for f in fields {
			field, _ := f.(json.Object)
			if key, has := field["name"].(json.String); has {
				named[string(key)] = true
			}
		}
		for field in node.fields {
			testing.expectf(
				t,
				named[field],
				"the schema lost %s.%s; regenerate with just pg_query-gen",
				node.node,
				field,
			)
		}
	}

	// And the count, so a section that lost a whole node is caught even
	// though nothing above names it.
	total := 0
	for name in ([]string{"nodes/parsenodes", "nodes/primnodes", "nodes/value", "nodes/pg_list"}) {
		section, _ := schema[name].(json.Object)
		total += len(section)
	}
	testing.expectf(
		t,
		total == len(SCHEMA),
		"the schema describes %d nodes, nodes.odin has %d; regenerate with just pg_query-gen",
		total,
		len(SCHEMA),
	)
}

// nodes.odin covers the four schema sections a parse tree can draw from, and
// this is what says so against real SQL rather than against a count: a node
// type with no struct for it is a Fault naming the tag, so any of these
// failing names the node that is missing.
@(test)
a_broad_corpus_parses :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	corpus := []string {
		`SELECT 1`,
		`SELECT a, b AS c, count(*) FILTER (WHERE d > 0) FROM t GROUP BY a HAVING count(*) > 1`,
		`SELECT row_number() OVER (PARTITION BY a ORDER BY b DESC NULLS LAST) FROM t`,
		`SELECT CASE WHEN a THEN 1 WHEN b THEN 2 ELSE 3 END FROM t`,
		`SELECT COALESCE(a, b), GREATEST(a, b), NULLIF(a, b) FROM t`,
		`SELECT a IS DISTINCT FROM b, a IS NULL, a IS NOT TRUE FROM t`,
		`SELECT ARRAY[1, 2, 3], (SELECT max(x) FROM u), EXISTS (SELECT 1 FROM u)`,
		`SELECT a::text, CAST(b AS numeric(10, 2)), a COLLATE "C" FROM t`,
		`SELECT * FROM t JOIN u ON t.id = u.id LEFT JOIN v USING (k) WHERE t.a IN (1, 2)`,
		`SELECT * FROM t TABLESAMPLE BERNOULLI (10) REPEATABLE (7)`,
		`SELECT * FROM generate_series(1, 10) AS g(n) WHERE n = ANY (ARRAY[1, 2])`,
		`SELECT * FROM t ORDER BY a LIMIT 10 OFFSET 5 FOR UPDATE OF t NOWAIT`,
		`WITH RECURSIVE r(n) AS (SELECT 1 UNION ALL SELECT n + 1 FROM r WHERE n < 5) SELECT n FROM r`,
		`SELECT a FROM t UNION SELECT b FROM u EXCEPT SELECT c FROM v`,
		`SELECT jsonb_build_object('k', a) -> 'k' ->> 0 FROM t`,
		`SELECT xmlelement(name foo, a) FROM t`,
		`INSERT INTO t (a, b) VALUES (1, 2), (3, 4) ON CONFLICT (a) DO UPDATE SET b = EXCLUDED.b RETURNING *`,
		`UPDATE t SET (a, b) = (SELECT x, y FROM u) WHERE id = 1`,
		`DELETE FROM t USING u WHERE t.id = u.id RETURNING t.a`,
		`MERGE INTO t USING u ON t.id = u.id WHEN MATCHED THEN UPDATE SET a = u.a WHEN NOT MATCHED THEN INSERT (a) VALUES (u.a)`,
		`CREATE TABLE t (id serial PRIMARY KEY, a text NOT NULL DEFAULT 'x', b int REFERENCES u(id) ON DELETE CASCADE, CHECK (b > 0))`,
		`CREATE TABLE p (a int, b date) PARTITION BY RANGE (b)`,
		`CREATE TABLE q PARTITION OF p FOR VALUES FROM ('2020-01-01') TO ('2021-01-01')`,
		`CREATE INDEX CONCURRENTLY i ON t USING gin (a jsonb_path_ops) WHERE b IS NOT NULL`,
		`CREATE VIEW v AS SELECT a FROM t WITH CHECK OPTION`,
		`CREATE MATERIALIZED VIEW m AS SELECT 1 WITH NO DATA`,
		`CREATE FUNCTION f(a int DEFAULT 1) RETURNS int LANGUAGE sql AS 'SELECT a'`,
		`CREATE TRIGGER g AFTER INSERT ON t FOR EACH ROW EXECUTE FUNCTION f()`,
		`CREATE TYPE e AS ENUM ('a', 'b')`,
		`CREATE SEQUENCE s START 1 INCREMENT BY 2 OWNED BY t.id`,
		`CREATE POLICY p ON t FOR SELECT TO reader USING (a > 0)`,
		`ALTER TABLE t ADD COLUMN c int, ALTER COLUMN a SET NOT NULL, DROP CONSTRAINT x`,
		`ALTER TABLE t RENAME COLUMN a TO b`,
		`GRANT SELECT, INSERT ON ALL TABLES IN SCHEMA public TO reader WITH GRANT OPTION`,
		`REVOKE ALL ON t FROM reader CASCADE`,
		`DROP TABLE IF EXISTS t, u CASCADE`,
		`BEGIN ISOLATION LEVEL SERIALIZABLE READ ONLY`,
		`SAVEPOINT a; ROLLBACK TO SAVEPOINT a; RELEASE a; COMMIT`,
		`VACUUM (FULL, ANALYZE) t`,
		`EXPLAIN (ANALYZE, BUFFERS) SELECT 1`,
		`COPY t (a) FROM STDIN WITH (FORMAT csv, HEADER true)`,
		`PREPARE p (int) AS SELECT $1; EXECUTE p (1); DEALLOCATE p`,
		`DECLARE c CURSOR FOR SELECT 1; FETCH FORWARD 10 FROM c; CLOSE c`,
		`SET LOCAL search_path = a, b; RESET ALL; SHOW all`,
		`LOCK TABLE t IN ACCESS EXCLUSIVE MODE NOWAIT`,
		`CREATE ROLE r WITH LOGIN PASSWORD 'x' VALID UNTIL '2030-01-01'`,
		`COMMENT ON TABLE t IS 'note'`,
		`REFRESH MATERIALIZED VIEW CONCURRENTLY m`,
		`CALL p(1, 2)`,
		`LISTEN chan; NOTIFY chan, 'payload'; UNLISTEN chan`,
	}
	for sql in corpus {
		tree, err := parse(sql)
		testing.expectf(t, err == nil, "%s: %v", sql, err)
		if err != nil {
			continue
		}
		testing.expectf(t, len(tree.stmts) > 0, "%s gave no statements", sql)
		for raw, i in tree.stmts {
			testing.expectf(t, raw.stmt != nil, "%s: statement %d decoded to nothing", sql, i)
		}
		destroy(&tree)
	}
}

@(test)
version_is_the_vendored_parser :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	tree, err := parse(`SELECT 1`)
	testing.expect_value(t, err, nil)
	defer destroy(&tree)
	// The tree reports the version the grammar was generated from, so this
	// would notice an archive built from some other checkout.
	testing.expect_value(t, tree.version, PG_VERSION_NUM)
	// The three constants a caller records the skew against a server with
	// have to agree with each other and with the archive.
	testing.expect_value(t, PG_MAJORVERSION, "17")
	testing.expect_value(t, PG_VERSION, "17.7")
	testing.expect(
		t,
		strings.has_prefix(PG_VERSION, PG_MAJORVERSION),
		"the major version must be the full one's prefix",
	)
}

@(test)
parse_gives_both_layers :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	tree, err := parse(
		`update rig set serial_number = 'x' where id = 1 and serial_number = 'u';`,
	)
	testing.expect_value(t, err, nil)
	defer destroy(&tree)

	testing.expect(t, strings.contains(tree.text, `"UpdateStmt"`), "the text layer is the tree")
	testing.expect(t, strings.contains(tree.text, `"relname":"rig"`), "with the relation in it")

	testing.expect_value(t, len(tree.stmts), 1)
	raw := tree.stmts[0]
	testing.expect_value(t, raw.stmt_len, 71)
	update, is_update := raw.stmt.(^UpdateStmt)
	testing.expect(t, is_update, "the node arrives as the type it is")
	if !is_update {
		return
	}
	testing.expect_value(t, update.relation.relname, "rig")
	testing.expect_value(t, len(update.targetList), 1)

	target, is_target := update.targetList[0].(^ResTarget)
	testing.expect(t, is_target, "a target list holds ResTargets")
	testing.expect_value(t, target.name, "serial_number")
	value, is_const := target.val.(^A_Const)
	testing.expect(t, is_const, "assigning a literal gives an A_Const")
	text, is_text := value.val.(^String)
	testing.expect(t, is_text, "and a string literal gives a String")
	testing.expect_value(t, text.sval, "x")

	// The WHERE clause is the shape a safety gate reads.
	clause, is_bool := update.whereClause.(^BoolExpr)
	testing.expect(t, is_bool, "two conditions give a BoolExpr")
	if !is_bool {
		return
	}
	testing.expect_value(t, clause.boolop, BoolExprType.AND_EXPR)
	testing.expect_value(t, len(clause.args), 2)
}

// The whole point of the wrapper: everything it hands back is the caller's,
// so the C result can be freed the moment the call returns. A tree holding
// pointers into libpg_query's memory context would still read correctly here
// until the next parse reused that context — which is what the second parse
// and the churn between them are for.
@(test)
a_tree_outlives_the_library_s_copy :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	first, err := parse(`SELECT a, b FROM first_table WHERE c = 'marker'`)
	testing.expect_value(t, err, nil)
	before := strings.clone(first.text)

	// Parse enough afterwards that the context the first parse used has been
	// released and handed out again several times over.
	for _ in 0 ..< 64 {
		churn, cerr := parse(`SELECT x, y, z FROM another_table WHERE q = 'different'`)
		testing.expect_value(t, cerr, nil)
		destroy(&churn)
	}

	testing.expect_value(t, first.text, before)
	testing.expect(
		t,
		strings.contains(first.text, `"relname":"first_table"`),
		"the tree is still the parser's output and not the input echoed back",
	)
	// The typed nodes are clones too, and they hang off the tree's own arena.
	stmt := first.stmts[0].stmt.(^SelectStmt)
	testing.expect_value(t, stmt.fromClause[0].(^RangeVar).relname, "first_table")
	destroy(&first)
}

// A Fault is copied out of the same context, so it survives the free too, and
// it carries the position a caller needs to point at the offending token.
@(test)
a_fault_names_the_place :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	tree, err := parse(`update rig set x = 1 wher`)
	testing.expect_value(t, tree.text, "")
	fault, is_fault := err.(Fault)
	testing.expect(t, is_fault, "a refused statement is a Fault")
	testing.expect_value(t, fault.message, `syntax error at or near "wher"`)
	testing.expect_value(t, fault.cursorpos, 22)
	testing.expect(t, fault.filename != "", "the parser says where in its own sources it gave up")

	// cursorpos is 1-based, and it points at the token that was not expected.
	sql := `update rig set x = 1 wher`
	testing.expect_value(t, sql[fault.cursorpos - 1:], "wher")
}

// A statement cut short has nothing left to point at, so the parser points one
// past the end. A caller turning cursorpos into a slice index has to expect
// it, which is why it is written down rather than left to be discovered.
@(test)
a_truncated_statement_faults_at_end_of_input :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sql := `SELECT a, `
	_, err := parse(sql)
	fault, is_fault := err.(Fault)
	testing.expect(t, is_fault, "an unfinished statement is a Fault")
	testing.expect_value(t, fault.message, "syntax error at end of input")
	testing.expect_value(t, fault.cursorpos, len(sql) + 1)
}

@(test)
split_measures_each_statement :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sql := `SELECT 1; INSERT INTO t VALUES (2); CREATE TABLE u(a int)`
	spans, err := split(sql)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, len(spans), 3)
	testing.expect_value(t, sql[spans[0].offset:][:spans[0].len], `SELECT 1`)
	testing.expect_value(t, sql[spans[1].offset:][:spans[1].len], ` INSERT INTO t VALUES (2)`)
	testing.expect_value(t, sql[spans[2].offset:][:spans[2].len], ` CREATE TABLE u(a int)`)

	// A span is only useful if it is in bounds and moves forward.
	prev := 0
	for s in spans {
		testing.expect(t, s.offset >= prev, "spans ascend")
		testing.expect(t, s.offset + s.len <= len(sql), "and stay inside the input")
		prev = s.offset + s.len
	}
}

@(test)
is_utility_separates_ddl_from_queries :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	flags, err := is_utility(`SELECT 1; CREATE TABLE t(a int); UPDATE t SET a = 1; VACUUM`)
	testing.expect_value(t, err, nil)
	testing.expect(t, slice.equal(flags, []bool{false, true, false, true}), "DDL is utility")
}

// Every call refuses a statement the grammar will not take, rather than each
// one inventing its own answer for it.
@(test)
every_call_reports_a_syntax_error :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	bad := `SELECT FROM WHERE`

	_, perr := parse(bad)
	testing.expect(t, perr != nil, "parse refuses it")
	_, serr := split(bad)
	testing.expect(t, serr != nil, "split refuses it")
	_, uerr := is_utility(bad)
	testing.expect(t, uerr != nil, "is_utility refuses it")
	_, _, ferr := fingerprint(bad)
	testing.expect(t, ferr != nil, "fingerprint refuses it")
	_, nerr := normalize(bad)
	testing.expect(t, nerr != nil, "normalize refuses it")
}

@(test)
fingerprint_ignores_the_literals :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	one, text_one, err_one := fingerprint(`SELECT * FROM rig WHERE id = 1`)
	testing.expect_value(t, err_one, nil)
	two, text_two, err_two := fingerprint(`SELECT * FROM rig WHERE id = 99999`)
	testing.expect_value(t, err_two, nil)
	testing.expect_value(t, one, two)
	testing.expect_value(t, text_one, text_two)
	testing.expect(t, one != 0, "a fingerprint is not the zero value")
	// The hex string is the same number, so a log can be grouped on either.
	testing.expect_value(t, len(text_one), 16)

	other, _, err_other := fingerprint(`SELECT * FROM crate WHERE id = 1`)
	testing.expect_value(t, err_other, nil)
	testing.expect(t, other != one, "a different table is a different statement")
}

@(test)
normalize_replaces_literals_and_still_parses :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	out, err := normalize(`SELECT 1 FROM t WHERE a = 'secret' AND b = 42`)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, out, `SELECT $1 FROM t WHERE a = $2 AND b = $3`)
	testing.expect(t, !strings.contains(out, "secret"), "the literal is gone")

	tree, perr := parse(out)
	testing.expect_value(t, perr, nil)
	destroy(&tree)
}

// The one shape whose normalized form does not parse, kept as a test so that
// nobody promises more than normalize delivers. A leading minus belongs to
// the constant, so the substitution runs into the keyword before it. Found by
// this package's fuzz suite; what the test shows is what it says.
@(test)
normalize_can_join_a_parameter_onto_the_token_before_it :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	out, err := normalize(`SELECT-1`)
	testing.expect_value(t, err, nil)
	testing.expect_value(t, out, `SELECT$1`)
	_, perr := parse(out)
	testing.expect(t, perr != nil, "which is one identifier, not a statement")

	// A space is all it takes for the same statement to survive it.
	spaced, serr := normalize(`SELECT -1`)
	testing.expect_value(t, serr, nil)
	testing.expect_value(t, spaced, `SELECT $1`)
	tree, sperr := parse(spaced)
	testing.expect_value(t, sperr, nil)
	destroy(&tree)
}

// An Odin string may hold a NUL in the middle; a C string may not. Handing
// one over would submit a prefix and call the result a parse of the whole
// thing, so every call refuses it and says where.
@(test)
an_interior_nul_is_refused_not_truncated :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sql := "SELECT 1\x00; DROP TABLE t"

	_, err := parse(sql)
	fault, is_fault := err.(Fault)
	testing.expect(t, is_fault, "a NUL is a Fault")
	testing.expect_value(t, fault.cursorpos, 9)
	testing.expect(t, strings.contains(fault.message, "NUL"), "and the message says so")

	_, serr := split(sql)
	testing.expect(t, serr != nil, "split refuses it too")
	_, uerr := is_utility(sql)
	testing.expect(t, uerr != nil, "and is_utility")
	_, _, ferr := fingerprint(sql)
	testing.expect(t, ferr != nil, "and fingerprint")
	_, nerr := normalize(sql)
	testing.expect(t, nerr != nil, "and normalize")
}

// libpg_query does not validate its input against the encoding it scans in,
// so a literal holding a stray byte parses and its bytes reach the parse tree
// verbatim. That makes the tree JSON that is not UTF-8, and decoding that
// walked off the end of a buffer in core:encoding/json until this refusal was
// added. The fuzz suite found it; this is the case it found.
@(test)
invalid_utf8_is_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sql := "SELECT '\xff\xfe' FROM t"

	_, err := parse(sql)
	fault, is_fault := err.(Fault)
	testing.expect(t, is_fault, "a statement that is not UTF-8 is a Fault")
	testing.expect(t, strings.contains(fault.message, "UTF-8"), "and the message says so")
	// The literal's first stray byte is at index 8, reported 1-based.
	testing.expect_value(t, fault.cursorpos, 9)

	_, serr := split(sql)
	testing.expect(t, serr != nil, "split refuses it too")
	_, uerr := is_utility(sql)
	testing.expect(t, uerr != nil, "and is_utility")
	_, _, ferr := fingerprint(sql)
	testing.expect(t, ferr != nil, "and fingerprint")
	_, nerr := normalize(sql)
	testing.expect(t, nerr != nil, "and normalize")

	// Multi-byte runes are not the thing being refused.
	fine, ferr2 := parse("SELECT 'héllo \U0001F600' FROM t")
	testing.expect_value(t, ferr2, nil)
	destroy(&fine)
}

@(test)
empty_input_parses_to_no_statements :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for sql in ([]string{"", "   ", "-- just a comment\n", ";"}) {
		tree, err := parse(sql)
		testing.expectf(t, err == nil, "%q should parse: %v", sql, err)
		testing.expectf(t, len(tree.stmts) == 0, "%q holds no statements, got %d", sql, len(tree.stmts))
		destroy(&tree)

		spans, serr := split(sql)
		testing.expect_value(t, serr, nil)
		testing.expect_value(t, len(spans), 0)
	}
}

@(test)
destroy_zeroes_the_tree :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	tree, err := parse(`SELECT 1`)
	testing.expect_value(t, err, nil)
	destroy(&tree)
	testing.expect_value(t, tree.text, "")
	testing.expect_value(t, tree.version, 0)
	testing.expect(t, tree.stmts == nil, "and its typed layer")
	// Twice is not a double free.
	destroy(&tree)
	destroy(nil)
}

// Upstream says libpg_query keeps its memory context per thread. That is the
// claim jm:wasm's docs made about wasm3 and it was wrong, so it is checked
// here rather than taken: eight threads parse the same statements at the same
// time, and every tree must match the one a single thread produces.
//
// No worker calls pg_query_exit. That is the one entry point this package
// does not wrap, and the package doc says why.
@(test)
threads_do_not_collide :: proc(t: ^testing.T) {
	statements := []string {
		`SELECT a, b FROM one WHERE c = 'x'`,
		`UPDATE two SET v = 3 WHERE k = 'y'`,
		`CREATE TABLE three (a int, b text)`,
		`WITH r AS (SELECT 1 AS n) SELECT n FROM r`,
		`DELETE FROM four WHERE id IN (1, 2, 3)`,
		`INSERT INTO five (a) VALUES ('z') RETURNING a`,
	}
	want := make([]string, len(statements))
	defer {
		for w in want {
			delete(w)
		}
		delete(want)
	}
	for sql, i in statements {
		tree, err := parse(sql)
		testing.expect_value(t, err, nil)
		want[i] = strings.clone(tree.text)
		destroy(&tree)
	}

	WORKERS :: 8
	shared := Collision {
		statements = statements,
		want       = want,
	}
	// The pool's own allocator must not be the test thread's temp allocator:
	// the workers reach for it, and that one is not shared.
	pool: thread.Pool
	thread.pool_init(&pool, context.allocator, WORKERS)
	defer thread.pool_destroy(&pool)
	for i in 0 ..< WORKERS {
		thread.pool_add_task(&pool, context.allocator, collide, &shared, i)
	}
	thread.pool_start(&pool)
	thread.pool_finish(&pool)

	testing.expectf(
		t,
		shared.mismatches == 0,
		"%d of %d parses on %d threads disagreed with the single-threaded tree",
		shared.mismatches,
		shared.parses,
		WORKERS,
	)
	testing.expect(t, shared.parses > 0, "the workers must actually have parsed something")
	testing.expectf(t, shared.faults == 0, "%d parses failed that should not have", shared.faults)
}

@(private)
Collision :: struct {
	statements:  []string,
	want:        []string,
	// Written by every worker, so they are counted atomically rather than
	// through a package global the way the jm:fuzz lesson warns against.
	parses:      int,
	mismatches:  int,
	faults:      int,
}

// ROUNDS is how many times each worker walks the statement list. It wants to
// be enough that the workers overlap for a while rather than starting and
// finishing in turn.
@(private)
ROUNDS :: 200

@(private)
collide :: proc(task: thread.Task) {
	shared := (^Collision)(task.data)
	// Each worker owns its allocator, so what overlaps is the parser and
	// nothing else.
	arena: mem.Dynamic_Arena
	mem.dynamic_arena_init(&arena)
	defer mem.dynamic_arena_destroy(&arena)
	context.allocator = mem.dynamic_arena_allocator(&arena)

	for _ in 0 ..< ROUNDS {
		for sql, i in shared.statements {
			tree, err := parse(sql)
			sync.atomic_add(&shared.parses, 1)
			if err != nil {
				sync.atomic_add(&shared.faults, 1)
				continue
			}
			if tree.text != shared.want[i] {
				sync.atomic_add(&shared.mismatches, 1)
			}
			destroy(&tree)
		}
	}
}
