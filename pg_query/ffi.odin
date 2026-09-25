/*
The raw C API: the subset of pg_query.h the wrapper needs, under the C names,
exported so a caller that needs an interface the wrapper does not cover can
reach for it. The wrapper in pg_query.odin is what scripts should use. The
declarations track the vendored header, libpg_query commit
6e764b7922a1f4a03764ed3ef3ca216b36e02531 on branch 17-latest, which carries
the PostgreSQL 17.7 parser.

The parser is the source tree under vendor/, compiled into lib/ by the
justfile's `pg_query` recipe, which is also where the compile flags and the
reason for each are written down. The archive path below is relative to this
directory, which is what puts lib/ here rather than in build/; the README's
PostgreSQL section records that and what `just check` does without it.

Every result is returned by value and every free takes its result by value,
which is unusual enough to be worth saying twice: pg_query_free_parse_result
is handed a copy of the struct, not a pointer to it, and declaring it either
way round wrongly would free pointers read out of the wrong registers. The
wrapper's tests parse and free thousands of statements under a sanitizer,
which is what keeps these declarations honest.

Left out, and why: pg_query_scan, pg_query_parse_protobuf,
pg_query_deparse_protobuf, pg_query_summary and pg_query_parse_plpgsql all
hand back a PgQueryProtobuf — a length and a buffer holding an encoded
protobuf message — and nothing in this collection decodes protobuf, so
binding them would hand a caller bytes it has no way to read. The JSON API
carries the same tree. Their objects are still in the archive, because
upstream compiles the protobuf writer into the same translation unit as
pg_query_parse; the justfile's recipe records the experiment.
pg_query_split_with_scanner is left out in favour of the parser-backed
splitter, which the vendored pg_query.h recommends above it.
*/
package pg_query

import "core:c"

when ODIN_OS == .Windows {
	foreign import lib "lib/pg_query.lib"
} else {
	@(extra_linker_flags = "-lpthread -lm")
	foreign import lib "lib/pg_query.a"
}

// PG_MAJORVERSION is the PostgreSQL major release whose grammar is vendored,
// and PG_VERSION_NUM the full one, which is also the "version" field of every
// parse tree this package hands back. A caller talking to a server on another
// release wants to record the skew: both directions fail safe, a stricter
// parser by refusing what the server would take, a looser one by parsing what
// the server would refuse, but neither is the server's own answer.
PG_MAJORVERSION :: "17"
PG_VERSION :: "17.7"
PG_VERSION_NUM :: 170007

// PgQueryError is what the parser says about a statement it would not take.
// message is always set; funcname, filename and lineno point into the
// PostgreSQL sources rather than the query, and the vendored header marks
// context_ optional and able to be NULL. cursorpos is a 1-based byte offset
// into the input, and 0 when the failure has no position.
//
// context_ is the C field `context`, which Odin cannot spell: `context` is
// the implicit argument every procedure carries.
PgQueryError :: struct {
	message:   cstring,
	funcname:  cstring,
	filename:  cstring,
	lineno:    c.int,
	cursorpos: c.int,
	context_:  cstring,
}

// PgQueryParseResult is the parse tree as JSON text. parse_tree is nil when
// error is set, and error is nil when the parse succeeded.
PgQueryParseResult :: struct {
	parse_tree:    cstring,
	stderr_buffer: cstring,
	error:         ^PgQueryError,
}

// PgQuerySplitStmt is one statement's extent in the input: a byte offset and
// a byte length, with the trailing semicolon left out of the length.
PgQuerySplitStmt :: struct {
	stmt_location: c.int,
	stmt_len:      c.int,
}

// PgQuerySplitResult is an array of pointers to extents, not an array of
// extents: stmts[i] is a ^PgQuerySplitStmt.
PgQuerySplitResult :: struct {
	stmts:         [^]^PgQuerySplitStmt,
	n_stmts:       c.int,
	stderr_buffer: cstring,
	error:         ^PgQueryError,
}

// PgQueryIsUtilityResult says, per statement in the input, whether it is a
// utility statement — DDL and everything else that is not a plannable
// SELECT, INSERT, UPDATE, DELETE or MERGE. items is `bool *` in C, one byte
// each.
PgQueryIsUtilityResult :: struct {
	length: c.int,
	items:  [^]b8,
	error:  ^PgQueryError,
}

// PgQueryFingerprintResult is a hash of the statement's shape with its
// literals ignored, as both a number and the same number in hex.
PgQueryFingerprintResult :: struct {
	fingerprint:     u64,
	fingerprint_str: cstring,
	stderr_buffer:   cstring,
	error:           ^PgQueryError,
}

// PgQueryNormalizeResult is the statement with its literals replaced by
// numbered parameters.
PgQueryNormalizeResult :: struct {
	normalized_query: cstring,
	error:            ^PgQueryError,
}

@(default_calling_convention = "c")
foreign lib {
	pg_query_parse             :: proc(input: cstring) -> PgQueryParseResult ---
	pg_query_split_with_parser :: proc(input: cstring) -> PgQuerySplitResult ---
	pg_query_is_utility_stmt   :: proc(query: cstring) -> PgQueryIsUtilityResult ---
	pg_query_fingerprint       :: proc(input: cstring) -> PgQueryFingerprintResult ---
	pg_query_normalize         :: proc(input: cstring) -> PgQueryNormalizeResult ---

	pg_query_free_parse_result       :: proc(result: PgQueryParseResult) ---
	pg_query_free_split_result       :: proc(result: PgQuerySplitResult) ---
	pg_query_free_is_utility_result  :: proc(result: PgQueryIsUtilityResult) ---
	pg_query_free_fingerprint_result :: proc(result: PgQueryFingerprintResult) ---
	pg_query_free_normalize_result   :: proc(result: PgQueryNormalizeResult) ---

	// Releases the calling thread's top memory context. Here for completeness
	// and deliberately not wrapped: pg_query_init already registered a
	// pthread destructor over that same context, so a thread that calls this
	// and then ends frees it twice and glibc aborts. The package doc has the
	// reproduction.
	pg_query_exit :: proc() ---
}
