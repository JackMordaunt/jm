/*
Package fuzz is the jm:pg_query suite for jm:fuzz: the promises the bindings
make, checked against generated SQL, damaged SQL, and bytes that were never
SQL at all.

	report := fuzz.run({seed = 1, iterations = 10_000})

jm:fuzz owns the machinery — seeding, budgets, shrinking, the corpus, running
a case in a child process. What lives here is what is true of jm:pg_query and
nothing else:

	survives                     any bytes parse or fail, and never both
	error_sane                   a refusal carries a message and a position inside the input
	tree_valid                   a parse gives typed statements, from the vendored version
	split_covers                 spans are in bounds, ascending, and one per statement
	utility_agrees               is_utility answers once per statement
	fingerprint_ignores_literals the same statement with other values hashes the same
	normalize_reparses           what normalize writes, parse reads
	nul_safe                     a NUL inside a statement is refused, never truncated away

nul_safe is the binding-specific one: it exists because an Odin string may
carry a NUL in the middle and a C string may not, so the conversion between
them is a place where a statement can quietly become a shorter statement. The
package doc gives the rule; this checks it against generated input rather than
the three examples in the tests.

The generator in gen.odin is why the success path gets exercised at all: raw
bytes are almost never SQL, so a suite drawing only those would spend its
whole run on the failure path. Three sources are mixed — generated
statements, generated statements with one byte broken, and raw bytes — and
every property says which it drew when it reports.
*/
package pg_query_fuzz

import "core:fmt"
import "core:strings"

import harness "jm:fuzz"
import "jm:pg_query"

// Parser is the subject jm:fuzz hands each property. libpg_query has nothing
// to open: it is a set of procedures over state it keeps per thread —
// vendor/src/postgres/include/utils/memutils.h declares TopMemoryContext
// __thread — with no handle and nothing to release. A Suite is parametric on
// its subject, so there has to be a type; this is it.
Parser :: struct {}

// properties is package level because a Suite holds a slice, which has to
// outlive the call that hands the Suite back.
properties := []harness.Property(Parser) {
	{"survives", survives},
	{"error_sane", error_sane},
	{"tree_valid", tree_valid},
	{"split_covers", split_covers},
	{"utility_agrees", utility_agrees},
	{"fingerprint_ignores_literals", fingerprint_ignores_literals},
	{"normalize_reparses", normalize_reparses},
	{"nul_safe", nul_safe},
}

// suite is jm:pg_query and its promises, ready for harness.run.
//
// cancel is nil, unlike the sqlite3 and wasm suites: vendor/pg_query.h
// declares no entry point that interrupts a parse in flight, so there is no
// honest way to implement it and a deadline enforced from another thread
// would be a lie. A case that will not finish is caught by
// `just fuzz-isolate`, which kills the child.
suite :: proc() -> harness.Suite(Parser) {
	return harness.Suite(Parser){name = "pg_query", setup = open, properties = properties}
}

// CORPUS is where this suite's regressions live, relative to the repository
// root. A case that failed once is kept there and replayed on every run.
CORPUS :: "pg_query/fuzz/corpus"

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

// open makes the subject there is nothing to make.
open :: proc() -> (Parser, bool) {
	return {}, true
}

// Origin is where a case's input came from, so a failure says which of the
// three sources found it.
Origin :: enum {
	// A statement the generator built. A zero source draws this one.
	Generated,
	// A generated statement with jm:fuzz's damage applied to it.
	Damaged,
	// Bytes that were never SQL.
	Raw,
}

// input draws one case's SQL from one of the three sources, weighted so that
// most cases reach the parser's success path.
input :: proc(src: ^harness.Source) -> (sql: string, from: Origin) {
	switch harness.integer_in(src, 0, 8) {
	case 5, 6:
		text, _ := harness.damage_text(src, gen_corpus(), context.temp_allocator)
		return text, .Damaged
	case 7:
		return string(harness.bytes(src, 256, context.temp_allocator)), .Raw
	case:
		g := gen(src)
		return script(&g, context.temp_allocator), .Generated
	}
}

// gen_corpus is WELL_FORMED, which damage reads as bytes.
@(private)
gen_corpus :: proc() -> []string {
	return WELL_FORMED
}

// survives runs every entry point over whatever was drawn. Nothing here
// should crash, and a call must answer exactly once: a tree or a Fault, not
// both and not neither.
survives :: proc(subject: Parser, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := input(src)
	tree, err := pg_query.parse(sql)
	if err != nil && tree.text != "" {
		return fmt.tprintf("%v %s: a refusal came with a tree", from, harness.show(sql)), false
	}
	if err == nil && tree.text == "" {
		return fmt.tprintf("%v %s: a parse came back with no tree", from, harness.show(sql)), false
	}
	// nodes.odin is generated from the schema for exactly one reason: a
	// caller must never be handed a tree with a node missing from it. A
	// refusal naming a type this build has no struct for means the generated
	// set is short, which is this suite's job to find.
	if fault, is_fault := err.(pg_query.Fault); is_fault {
		if strings.contains(fault.message, "no type for") {
			return fmt.tprintf("%v %s: %s", from, harness.show(sql), fault.message), false
		}
	}
	_, _ = pg_query.split(sql)
	_, _ = pg_query.is_utility(sql)
	_, _, _ = pg_query.fingerprint(sql)
	_, _ = pg_query.normalize(sql)
	return "", true
}

// error_sane checks what a refusal says. A gate reporting where a script is
// wrong is only as good as the position it is handed, so the position has to
// be inside the statement it was handed.
error_sane :: proc(subject: Parser, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := input(src)
	_, err := pg_query.parse(sql)
	if err == nil {
		return "", true
	}
	fault := err.(pg_query.Fault)
	if fault.message == "" {
		return fmt.tprintf("%v %s: a refusal with nothing to say", from, harness.show(sql)), false
	}
	// The bound is len + 1 rather than len. This property found out why: a
	// statement cut short faults at one past the end, which is how the parser
	// says "at end of input". pg_query_test.odin keeps that case.
	if fault.cursorpos < 0 || fault.cursorpos > len(sql) + 1 {
		return fmt.tprintf(
				"%v %s: cursorpos %d outside a %d-byte statement",
				from,
				harness.show(sql),
				fault.cursorpos,
				len(sql),
			),
			false
	}
	return "", true
}

// tree_valid checks what a parse gives back: JSON that decodes, a stmts
// array, and the version of the parser that is actually vendored.
tree_valid :: proc(subject: Parser, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := input(src)
	tree, err := pg_query.parse(sql)
	if err != nil {
		return "", true
	}
	if tree.version != pg_query.PG_VERSION_NUM {
		return fmt.tprintf(
				"%v %s: tree says version %d, archive is %d",
				from,
				harness.show(sql),
				tree.version,
				pg_query.PG_VERSION_NUM,
			),
			false
	}
	// Every statement must have arrived as a node. A RawStmt with nothing in
	// it is the hole the generated types exist to prevent.
	for raw, i in tree.stmts {
		if raw.stmt == nil {
			return fmt.tprintf("%v %s: statement %d decoded to nothing", from, harness.show(sql), i),
				false
		}
	}
	if len(tree.stmts) > 0 && !strings.contains(tree.text, `"stmts"`) {
		return fmt.tprintf("%v %s: the text layer disagrees", from, harness.show(sql)), false
	}
	return "", true
}

// split_covers checks that the spans partition the input: one per statement,
// inside it, and moving forward.
split_covers :: proc(subject: Parser, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := input(src)
	tree, perr := pg_query.parse(sql)
	if perr != nil {
		return "", true
	}
	spans, serr := pg_query.split(sql)
	if serr != nil {
		return fmt.tprintf(
				"%v %s: parsed but would not split: %v",
				from,
				harness.show(sql),
				serr,
			),
			false
	}
	want := len(tree.stmts)
	if len(spans) != want {
		return fmt.tprintf(
				"%v %s: %d statements, %d spans",
				from,
				harness.show(sql),
				want,
				len(spans),
			),
			false
	}
	end := 0
	for s, i in spans {
		if s.offset < 0 || s.len < 0 {
			return fmt.tprintf("%v %s: span %d is %v", from, harness.show(sql), i, s), false
		}
		// Written as a subtraction, not a sum: a sum of two large values is
		// a bounds check that wraps. See LEARNINGS, and jm:tar and jm:wasm.
		if s.offset > len(sql) || s.len > len(sql) - s.offset {
			return fmt.tprintf(
					"%v %s: span %d is %v, outside %d bytes",
					from,
					harness.show(sql),
					i,
					s,
					len(sql),
				),
				false
		}
		if s.offset < end {
			return fmt.tprintf(
					"%v %s: span %d starts at %d, inside the one before it",
					from,
					harness.show(sql),
					i,
					s.offset,
				),
				false
		}
		end = s.offset + s.len
	}
	return "", true
}

// utility_agrees checks that is_utility answers once per statement, in order.
// A caller lining the two up is what makes the answer useful at all.
utility_agrees :: proc(subject: Parser, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := input(src)
	tree, perr := pg_query.parse(sql)
	if perr != nil {
		return "", true
	}
	flags, uerr := pg_query.is_utility(sql)
	if uerr != nil {
		return fmt.tprintf(
				"%v %s: parsed but is_utility refused it: %v",
				from,
				harness.show(sql),
				uerr,
			),
			false
	}
	want := len(tree.stmts)
	if len(flags) != want {
		return fmt.tprintf(
				"%v %s: %d statements, %d flags",
				from,
				harness.show(sql),
				want,
				len(flags),
			),
			false
	}
	return "", true
}

// fingerprint_ignores_literals draws one statement twice from the same
// entropy, changing only the literal values, and requires the two to hash the
// same. That is the whole promise of a fingerprint: it names what a statement
// does, not what it says.
fingerprint_ignores_literals :: proc(
	subject: Parser,
	src: ^harness.Source,
) -> (
	detail: string,
	ok: bool,
) {
	// Two generators over one copy of the source each, so both draw the same
	// bytes in the same order; the real source is then advanced past what
	// they consumed, which keeps the case a pure function of its entropy.
	first_src := src^
	second_src := src^
	first_gen := gen(&first_src, 0)
	second_gen := gen(&second_src, 1)
	first := script(&first_gen, context.temp_allocator)
	second := script(&second_gen, context.temp_allocator)
	src^ = first_src

	first_hash, _, first_err := pg_query.fingerprint(first)
	second_hash, _, second_err := pg_query.fingerprint(second)
	if first_err != nil || second_err != nil {
		if (first_err == nil) != (second_err == nil) {
			return fmt.tprintf(
					"%s and %s differ only in their literals but one was refused: %v / %v",
					harness.show(first),
					harness.show(second),
					first_err,
					second_err,
				),
				false
		}
		return "", true
	}
	if first_hash != second_hash {
		return fmt.tprintf(
				"%s hashes %016x, %s hashes %016x",
				harness.show(first),
				first_hash,
				harness.show(second),
				second_hash,
			),
			false
	}
	return "", true
}

// normalize_reparses checks that normalize's output is still a statement. A
// log line that cannot be parsed back is a log line nothing else can read.
normalize_reparses :: proc(subject: Parser, src: ^harness.Source) -> (detail: string, ok: bool) {
	sql, from := input(src)
	if _, perr := pg_query.parse(sql); perr != nil {
		return "", true
	}
	normalized, nerr := pg_query.normalize(sql)
	if nerr != nil {
		return fmt.tprintf(
				"%v %s: parsed but would not normalize: %v",
				from,
				harness.show(sql),
				nerr,
			),
			false
	}
	if joined(normalized) {
		// Upstream's defect, not the binding's, and the package doc records
		// it: normalize substitutes over the literal's recorded extent
		// without checking that a token boundary survives. This suite found
		// it on `SELECT-1`, where the minus belongs to the constant and the
		// output is the single identifier `SELECT$1`.
		return "", true
	}
	if _, rerr := pg_query.parse(normalized); rerr != nil {
		return fmt.tprintf(
				"%v %s normalized to %s, which does not parse: %v",
				from,
				harness.show(sql),
				harness.show(normalized),
				rerr,
			),
			false
	}
	return "", true
}

// nul_safe puts a NUL somewhere inside a statement and requires every call to
// refuse it. The failure this guards against is silent: a cstring conversion
// hands the parser the bytes up to the NUL, the parser is happy with them,
// and a caller is told a statement it never wrote is fine.
nul_safe :: proc(subject: Parser, src: ^harness.Source) -> (detail: string, ok: bool) {
	g := gen(src)
	clean := script(&g, context.temp_allocator)
	at := harness.integer_in(src, 0, len(clean) + 1)
	holed := strings.concatenate(
		{clean[:at], "\x00", clean[at:]},
		context.temp_allocator,
	)

	_, perr := pg_query.parse(holed)
	fault, is_fault := perr.(pg_query.Fault)
	if !is_fault {
		return fmt.tprintf(
				"a NUL at %d of %s was parsed rather than refused",
				at,
				harness.show(clean),
			),
			false
	}
	// cursorpos is 1-based, so it names the NUL itself.
	if fault.cursorpos != at + 1 {
		return fmt.tprintf(
				"a NUL at %d of %s was reported at cursorpos %d",
				at,
				harness.show(clean),
				fault.cursorpos,
			),
			false
	}
	if _, serr := pg_query.split(holed); serr == nil {
		return fmt.tprintf("split took a NUL at %d of %s", at, harness.show(clean)), false
	}
	if _, uerr := pg_query.is_utility(holed); uerr == nil {
		return fmt.tprintf("is_utility took a NUL at %d of %s", at, harness.show(clean)), false
	}
	if _, _, ferr := pg_query.fingerprint(holed); ferr == nil {
		return fmt.tprintf("fingerprint took a NUL at %d of %s", at, harness.show(clean)), false
	}
	if _, nerr := pg_query.normalize(holed); nerr == nil {
		return fmt.tprintf("normalize took a NUL at %d of %s", at, harness.show(clean)), false
	}
	return "", true
}

// joined reports whether normalize put a parameter straight after a character
// that an identifier may contain, which is the one shape its output does not
// parse in.
@(private)
joined :: proc(s: string) -> bool {
	for i in 1 ..< len(s) {
		// A dollar starts a parameter only when a digit follows it.
		if s[i] != '$' || i + 1 >= len(s) || s[i + 1] < '0' || s[i + 1] > '9' {
			continue
		}
		switch c := s[i - 1]; {
		case c == '_', c == '$', c >= '0' && c <= '9':
			return true
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z':
			return true
		case c >= 0x80:
			// A byte outside ASCII is the start or the middle of a rune that
			// an identifier may well contain, so it is treated as one rather
			// than as a separator.
			return true
		}
	}
	return false
}
