/*
Package pg_query parses PostgreSQL SQL with PostgreSQL's own parser. The C
library is libpg_query — the server's `gram.y` and its dependencies lifted out
of the PostgreSQL source tree — vendored and linked statically, so a built
script needs no libpq, no server and no shared object at runtime. The README's
PostgreSQL section records the version, the compile flags and what `just check`
does without the archive.

	tree, err := pg_query.parse(`UPDATE rig SET serial_number = 'x' WHERE id = 1`)
	if err != nil {
		fault := err.(pg_query.Fault)
		fmt.eprintfln("%s at byte %d", fault.message, fault.cursorpos)
		return
	}
	defer pg_query.destroy(&tree)
	for raw in tree.stmts {
		if update, is_update := raw.stmt.(^pg_query.UpdateStmt); is_update {
			fmt.println(update.relation.relname, len(update.targetList))
		}
	}

A parse tree comes back twice: as the JSON text libpg_query wrote, which is
what to print when something is wrong, and as typed Odin nodes, which is what
to read. The node types are not written by hand. libpg_query ships its own
schema in `vendor/srcdata/`, and `pg_query/gen` turns that into
`pg_query/nodes.odin` — 267 structs, 63 enumerated types and the tag-dispatched
decoder that reads them. `just pg_query-gen` regenerates it.

That is the point of typing them at all. Dropping the schema would not remove
it, only make it implicit: a field PostgreSQL renames in its next major would
then stop decoding silently, and a caller asking "does this statement write?"
would be told no because the field it looked for was absent rather than
because the statement was harmless. Generated from the schema, the same rename
fails to compile the moment the vendored parser is bumped, and
`schema_conforms` in the tests fails before that.

A node type this build has no struct for fails the parse rather than arriving
as a hole, for the same reason.

What the parser knows, this package reports: `is_utility` separates DDL from
plannable statements, `split` gives each statement's extent in the input
without re-parsing it, `fingerprint` hashes a statement's shape with its
literals ignored, and `normalize` replaces those literals with parameters.

Memory: every string in a result is cloned into the allocator the call was
given before the C result is freed. libpg_query allocates out of a per-thread
memory context and `pg_query_free_*` releases the whole of it, so a pointer
held past the free is a read of memory the next parse will reuse. It is the
trap jm:sqlite3's own doc comment describes for text and blob columns, in
another dialect. Nothing this package hands back points into the library.

Encoding: every call refuses a statement that is not valid UTF-8, with a Fault
naming the offset of the first byte that is not. Two things make that the
binding's job rather than the caller's.

A NUL is the first. The C entry points take a NUL-terminated string, so a
statement is only as long as its first NUL; an Odin string may hold one in the
middle, and handing that over would quietly submit a prefix and report success
for a statement nobody wrote.

The rest of the rule is the second, and it is not merely tidiness.
libpg_query runs the scanner with the encoding set to UTF-8 but does not
validate the input against it, so a string literal holding a stray 0xff parses
and its bytes are copied into the parse tree verbatim — which makes the tree
JSON that is not UTF-8, and decoding that overruns a buffer inside
core:encoding/json. Found by this package's own fuzz suite; the gate here is
what closes it, and `invalid_utf8_is_refused` in the tests is the case.
Refusing such input is not this binding inventing a rule either: libpg_query
skips the encoding check a server does on everything it receives, because it
receives nothing.

Threads: libpg_query keeps its memory contexts in thread-local storage, so
separate threads parse independently and no lock is needed here. Verified
rather than believed — `threads_do_not_collide` runs eight threads over the
same statements and compares every tree against the single-threaded one; in C
the same shape survives 144,000 parses across eight threads with nothing
disagreeing.

What is not safe is releasing a context by hand. Read
`vendor/src/pg_query.c`: `pg_query_init` registers `pg_query_thread_exit` as a
pthread destructor over `TopMemoryContext`, and `pg_query_exit` calls
`pg_query_free_top_memory_context` on that same context without clearing the
thread-specific value. A thread that calls it and then ends therefore frees
the context twice and the process aborts in glibc — one worker thread, one
parse, no concurrency needed. So this package wraps every entry point but that
one: let the thread end and the destructor does it.
*/
package pg_query

import "core:encoding/json"
import "core:mem"
import "core:strings"
import "core:unicode/utf8"

// Fault is a statement the parser would not take: the message it gave, the
// position it gave, and where in the PostgreSQL sources it came from. Every
// string is cloned, so a Fault outlives the call that produced it.
Fault :: struct {
	// What went wrong, as PostgreSQL words it: `syntax error at or near "wher"`.
	message:   string,
	// The PostgreSQL function that raised it, its source file and the line.
	// They describe the parser, not the query.
	funcname:  string,
	filename:  string,
	lineno:    int,
	// A 1-based byte offset into the statement, or 0 when the failure has no
	// position. A gate that reports where a script is wrong wants this. It
	// can be one past the last byte, which is how the parser says "at end of
	// input"; `a_truncated_statement_faults_at_end_of_input` in the tests is
	// that case.
	cursorpos: int,
	// Extra detail, often empty.
	context_:  string,
}

// Error is nil when a call succeeded, so `or_return` and prelude.must both
// work on it.
Error :: union {
	Fault,
}

// Tree is a parsed statement list, in both of the forms this package offers.
// Pass it to destroy to release them.
Tree :: struct {
	// The parse tree as libpg_query wrote it, cloned. Keep it for a log or a
	// bug report; read stmts for anything else.
	text:      string,
	// The statements, in order, as typed nodes. Each one's stmt field holds
	// the statement itself: switch on it to find out what it is.
	stmts:     []RawStmt,
	// The server version the grammar came from, as the tree reports it:
	// 170007 for PostgreSQL 17.7. It is PG_VERSION_NUM unless the vendored
	// parser and this package have drifted apart.
	version:   int,
	// Every node hangs off this arena, so releasing them is one call rather
	// than a walk of the tree.
	arena:     ^mem.Dynamic_Arena,
	// Where text and the arena itself came from.
	allocator: mem.Allocator,
}

// Span is one statement's extent in the input, as byte offsets. The trailing
// semicolon is not part of the length, so `sql[s.offset:][:s.len]` is the
// statement on its own.
Span :: struct {
	offset: int,
	len:    int,
}

// parse runs the PostgreSQL grammar over sql, which may hold any number of
// statements separated by semicolons. The tree it hands back holds no
// pointers into the C library.
parse :: proc(sql: string, allocator := context.allocator) -> (tree: Tree, err: Error) {
	text := accept(sql, context.temp_allocator) or_return
	result := pg_query_parse(text)
	defer pg_query_free_parse_result(result)
	if result.error != nil {
		return {}, fault(result.error, allocator)
	}

	// Cloned before the defer above frees the context the C string lives in.
	tree.text = strings.clone(string(result.parse_tree), allocator)
	tree.allocator = allocator
	tree.arena = new(mem.Dynamic_Arena, allocator)
	mem.dynamic_arena_init(tree.arena)
	nodes := mem.dynamic_arena_allocator(tree.arena)
	defer if err != nil {
		mem.dynamic_arena_destroy(tree.arena)
		free(tree.arena, allocator)
		delete(tree.text, allocator)
		tree = {}
	}

	// The json.Value is scaffolding: the typed nodes clone every string they
	// keep, so it is gone by the time parse returns.
	root, jerr := json.parse_string(tree.text, .JSON, true, context.temp_allocator)
	defer json.destroy_value(root, context.temp_allocator)
	// libpg_query wrote this text, so a decode failure means the library and
	// core:encoding/json disagree about JSON rather than anything about the
	// query. It is a Fault all the same: the alternative is a Tree with no
	// statements in it that claims to have parsed.
	if jerr != .None {
		return {}, Fault{message = strings.clone("parse tree is not JSON", allocator)}
	}
	obj, is_object := root.(json.Object)
	if !is_object {
		return {}, Fault{message = strings.clone("parse tree is not an object", allocator)}
	}
	if n, is_int := obj["version"].(json.Integer); is_int {
		tree.version = int(n)
	}
	stmts, tag, decoded := decode_stmts(obj, nodes)
	if !decoded {
		return {}, Fault {
			message = strings.concatenate(
				{"parse tree holds a node this build has no type for: ", tag},
				allocator,
			),
		}
	}
	tree.stmts = stmts
	return tree, nil
}

// destroy releases a Tree and zeroes it. Scripts running on prelude's arena
// need not call it; anything holding a Db-sized allocator for a long time
// should.
destroy :: proc(tree: ^Tree) {
	if tree == nil {
		return
	}
	if tree.allocator.procedure != nil {
		if tree.arena != nil {
			mem.dynamic_arena_destroy(tree.arena)
			free(tree.arena, tree.allocator)
		}
		delete(tree.text, tree.allocator)
	}
	tree^ = {}
}

// split reports where each statement in sql begins and how long it is,
// without handing back a tree. It parses to do it, so a statement the grammar
// refuses is a Fault here as well.
split :: proc(sql: string, allocator := context.allocator) -> (stmts: []Span, err: Error) {
	text := accept(sql, context.temp_allocator) or_return
	result := pg_query_split_with_parser(text)
	defer pg_query_free_split_result(result)
	if result.error != nil {
		return nil, fault(result.error, allocator)
	}
	n := int(result.n_stmts)
	if n <= 0 {
		return nil, nil
	}
	out := make([]Span, n, allocator)
	for i in 0 ..< n {
		// stmts is an array of pointers, so each extent is read through one.
		s := result.stmts[i]
		out[i] = Span {
			offset = int(s.stmt_location),
			len    = int(s.stmt_len),
		}
	}
	return out, nil
}

// is_utility says, for each statement in sql and in order, whether it is a
// utility statement: DDL, GRANT, VACUUM, transaction control, everything that
// does not go through the planner. The slice lines up with split's.
is_utility :: proc(sql: string, allocator := context.allocator) -> (flags: []bool, err: Error) {
	text := accept(sql, context.temp_allocator) or_return
	result := pg_query_is_utility_stmt(text)
	defer pg_query_free_is_utility_result(result)
	if result.error != nil {
		return nil, fault(result.error, allocator)
	}
	n := int(result.length)
	if n <= 0 {
		return nil, nil
	}
	out := make([]bool, n, allocator)
	for i in 0 ..< n {
		out[i] = bool(result.items[i])
	}
	return out, nil
}

// fingerprint hashes what sql does rather than what it says: two statements
// that differ only in their literal values hash the same, which is how a
// query log is grouped. The string is the same number in hex, cloned.
fingerprint :: proc(
	sql: string,
	allocator := context.allocator,
) -> (
	hash: u64,
	text: string,
	err: Error,
) {
	input := accept(sql, context.temp_allocator) or_return
	result := pg_query_fingerprint(input)
	defer pg_query_free_fingerprint_result(result)
	if result.error != nil {
		return 0, "", fault(result.error, allocator)
	}
	if result.fingerprint_str != nil {
		text = strings.clone(string(result.fingerprint_str), allocator)
	}
	return result.fingerprint, text, nil
}

// normalize replaces every literal in sql with a numbered parameter, which
// makes a statement safe to log: `SELECT 1 FROM t WHERE a = 'secret'` becomes
// `SELECT $1 FROM t WHERE a = $2`.
//
// The output usually parses, and there is one shape where it does not.
// libpg_query substitutes over the literal's recorded extent without checking
// that a token boundary survives, and a leading minus belongs to the
// constant, so `SELECT-1` comes back as `SELECT$1` — one identifier, not a
// statement. Upstream's, reproduced in C; this package's fuzz suite found it.
// Treat the output as something to show a human, not as SQL to re-parse.
normalize :: proc(sql: string, allocator := context.allocator) -> (out: string, err: Error) {
	text := accept(sql, context.temp_allocator) or_return
	result := pg_query_normalize(text)
	defer pg_query_free_normalize_result(result)
	if result.error != nil {
		return "", fault(result.error, allocator)
	}
	if result.normalized_query == nil {
		return "", nil
	}
	return strings.clone(string(result.normalized_query), allocator), nil
}

// accept turns sql into the cstring the C API wants, or refuses one the
// parser would misread. See the package doc on encoding.
@(private)
accept :: proc(
	sql: string,
	allocator := context.allocator,
) -> (
	text: cstring,
	err: Error,
) {
	// The NUL is called out on its own because it is the one byte whose
	// damage is silent: everything after it would simply not be parsed.
	if i := strings.index_byte(sql, 0); i >= 0 {
		return nil, refusal(
			"statement holds a NUL byte, which the parser would read as its end",
			i,
			allocator,
		)
	}
	for i := 0; i < len(sql); {
		r, width := utf8.decode_rune_in_string(sql[i:])
		if r == utf8.RUNE_ERROR && width <= 1 {
			return nil, refusal("statement is not valid UTF-8", i, allocator)
		}
		i += width
	}
	return strings.clone_to_cstring(sql, allocator), nil
}

// refusal is a Fault this package raised rather than the parser, positioned
// the way the parser positions its own: 1-based, on the offending byte.
@(private)
refusal :: proc(message: string, at: int, allocator: mem.Allocator) -> Fault {
	return Fault{message = strings.clone(message, allocator), cursorpos = at + 1}
}

// fault copies a PgQueryError out of the library's memory context, before the
// caller's defer frees it.
@(private)
fault :: proc(e: ^PgQueryError, allocator: mem.Allocator) -> Fault {
	if e == nil {
		return {}
	}
	return Fault {
		message = copy_text(e.message, allocator),
		funcname = copy_text(e.funcname, allocator),
		filename = copy_text(e.filename, allocator),
		lineno = int(e.lineno),
		cursorpos = int(e.cursorpos),
		context_ = copy_text(e.context_, allocator),
	}
}

// copy_text clones a C string that may be nil, which several of these fields
// are whenever the parser has nothing to say about them.
@(private)
copy_text :: proc(s: cstring, allocator: mem.Allocator) -> string {
	if s == nil {
		return ""
	}
	return strings.clone(string(s), allocator)
}
