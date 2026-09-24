package sqlite3_fuzz

import "base:runtime"
import "core:math/rand"
import "core:testing"
import "core:time"

import harness "jm:fuzz"

// A short run on fixed seeds, so `just test` catches a regression the
// example-based tests would not: those compare each column while the cursor
// is still on its row, which is exactly when a column read that forgot to
// clone still looks correct. Long runs are `just fuzz`.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7, 99}) {
		report := run({seed = seed, iterations = 600, case_timeout = 30 * time.Second})
		testing.expect_value(t, report.iterations, 600)
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at case %d (replay: sqlite3-fuzz -seed=%d): %s",
				f.property,
				f.iteration,
				f.seed,
				f.detail,
			)
		}
	}
}

// The suite must describe itself completely, or jm:fuzz cannot run it: no
// setup means no subject, and no cancel means a query with no end hangs the
// run instead of being reported.
@(test)
suite_is_complete :: proc(t: ^testing.T) {
	s := suite()
	testing.expect_value(t, s.name, "sqlite3")
	testing.expect(t, s.setup != nil, "a case needs a database")
	testing.expect(t, s.teardown != nil, "a case must give it back")
	testing.expect(t, s.cancel != nil, "a case that will not finish must be stoppable")
	testing.expect(t, len(s.properties) == 6, "every property must be registered")
	for p in s.properties {
		testing.expect(t, p.name != "", "a property needs a name to be saved under")
		testing.expect(t, p.check != nil, "a property needs a body")
	}
}

// A run is a pure function of its seed, so a failure replays exactly.
@(test)
same_seed_same_run :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	first := run({seed = 42, iterations = 120})
	second := run({seed = 42, iterations = 120})
	testing.expect_value(t, first.iterations, 120)
	testing.expect(t, first.digest != 0, "a run that generated cases has a digest")
	testing.expect_value(t, first.digest, second.digest)
}

// The generators must reach every kind of value, or round_trip is only ever
// testing one of them.
@(test)
values_cover_every_type :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	// Filled from a seeded generator, because that is what a run draws from.
	state := rand.create(1)
	context.random_generator = runtime.default_random_generator(&state)
	bytes := make([]byte, 1 << 16)
	for i in 0 ..< len(bytes) {
		bytes[i] = byte(rand.uint32())
	}
	src := harness.source(bytes)
	seen: [harness.Damage]bool
	saw_null, saw_int, saw_real, saw_bool, saw_text, saw_blob :=
		false, false, false, false, false, false
	for _ in 0 ..< 4000 {
		switch v in value(&src) {
		case i64:
			saw_int = true
		case f64:
			saw_real = true
		case bool:
			saw_bool = true
		case string:
			saw_text = true
		case []byte:
			saw_blob = true
		case:
			saw_null = true
		}
		_, how := harness.damage_text(&src, STATEMENTS, context.temp_allocator)
		seen[how] = true
	}
	testing.expect(t, saw_null, "NULL must be generated")
	testing.expect(t, saw_int, "integers must be generated")
	testing.expect(t, saw_real, "reals must be generated")
	testing.expect(t, saw_bool, "booleans must be generated")
	testing.expect(t, saw_text, "text must be generated")
	testing.expect(t, saw_blob, "blobs must be generated")
	for k in harness.Damage {
		testing.expectf(t, seen[k], "damage never produced %v", k)
	}
}
