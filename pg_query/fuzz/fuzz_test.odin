package pg_query_fuzz

import "base:runtime"
import "core:math/rand"
import "core:strings"
import "core:testing"

import harness "jm:fuzz"
import "jm:pg_query"

// A short run on fixed seeds, so `just test` catches a regression without
// waiting for a long fuzz run. Long runs are `just fuzz pg_query`.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7, 99}) {
		report := run({seed = seed, iterations = 200})
		testing.expect_value(t, report.iterations, 200)
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at case %d (replay: jm-fuzz pg_query -seed=%d): %s",
				f.property,
				f.iteration,
				f.seed,
				f.detail,
			)
		}
	}
}

@(test)
suite_is_complete :: proc(t: ^testing.T) {
	s := suite()
	testing.expect_value(t, s.name, "pg_query")
	testing.expect(t, s.setup != nil, "a case needs a subject, even an empty one")
	testing.expect(
		t,
		s.cancel == nil,
		"libpg_query gives nothing to interrupt a parse with; -isolate is the answer",
	)
	testing.expect(t, len(s.properties) == 8, "every property must be registered")
	for p in s.properties {
		testing.expect(t, p.name != "", "a property needs a name to be saved under")
		testing.expect(t, p.check != nil, "a property needs a body")
	}
}

// A run is a pure function of its seed, so a failure replays exactly. The
// fingerprint property draws from copies of the Source and then advances the
// real one, which is the sort of thing that breaks this if it is done wrong.
@(test)
same_seed_same_run :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	first := run({seed = 42, iterations = 120})
	second := run({seed = 42, iterations = 120})
	testing.expect_value(t, first.iterations, 120)
	testing.expect(t, first.digest != 0, "a run that generated cases has a digest")
	testing.expect_value(t, first.digest, second.digest)
}

// The generator has to produce SQL the parser takes, or every property that
// checks a tree is quietly skipping. It also has to reach all three sources.
@(test)
generated_sql_mostly_parses :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	src := entropy(1)
	parsed, total := 0, 0
	for _ in 0 ..< 500 {
		g := gen(&src)
		sql := script(&g, context.temp_allocator)
		total += 1
		if _, err := pg_query.parse(sql); err == nil {
			parsed += 1
		}
	}
	testing.expectf(
		t,
		parsed == total,
		"the generator emitted %d statements the parser refused",
		total - parsed,
	)
}

@(test)
input_reaches_every_source :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	src := entropy(7)
	seen: [Origin]bool
	for _ in 0 ..< 2000 {
		_, from := input(&src)
		seen[from] = true
	}
	for origin in Origin {
		testing.expectf(t, seen[origin], "input never drew %v", origin)
	}
}

// The two variants of a statement must differ, or
// fingerprint_ignores_literals is comparing a statement with itself and would
// hold however broken the fingerprint was.
@(test)
variants_differ_only_in_their_literals :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	src := entropy(11)
	differed, same_shape := 0, 0
	for _ in 0 ..< 500 {
		first_src := src
		second_src := src
		first_gen := gen(&first_src, 0)
		second_gen := gen(&second_src, 1)
		first := script(&first_gen, context.temp_allocator)
		second := script(&second_gen, context.temp_allocator)
		src = first_src
		if first != second {
			differed += 1
		}
		// The shapes agree when both normalize to the same thing, which is
		// the parser's own opinion about which parts were literals.
		first_norm, first_err := pg_query.normalize(first)
		second_norm, second_err := pg_query.normalize(second)
		if first_err == nil && second_err == nil && first_norm == second_norm {
			same_shape += 1
		}
	}
	testing.expectf(t, differed > 100, "only %d of 500 pairs differed at all", differed)
	testing.expectf(
		t,
		same_shape > 400,
		"only %d of 500 pairs normalized to the same statement",
		same_shape,
	)
}

// The NUL property's own premise: the generator's statements are clean, so a
// NUL found in one was put there by the property and not drawn by accident.
@(test)
generated_sql_holds_no_nul :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	src := entropy(13)
	for _ in 0 ..< 500 {
		g := gen(&src)
		sql := script(&g, context.temp_allocator)
		// A generator that stopped emitting anything would hold the NUL
		// check vacuously, so the length is asserted first.
		testing.expect(t, len(sql) > 0, "the generator must emit a statement")
		testing.expectf(
			t,
			strings.index_byte(sql, 0) < 0,
			"the generator emitted a NUL in %s",
			harness.show(sql),
		)
	}
}

// entropy is a Source over pseudo-random bytes, which is what a run draws
// from. The seed is fixed so a failure here replays.
@(private)
entropy :: proc(seed: u64) -> harness.Source {
	state := rand.create(seed)
	context.random_generator = runtime.default_random_generator(&state)
	bytes := make([]byte, 1 << 16, context.temp_allocator)
	for i in 0 ..< len(bytes) {
		bytes[i] = byte(rand.uint32())
	}
	return harness.source(bytes)
}
