package stream_fuzz

import "core:testing"

// A short run on fixed seeds, so `just test` catches a regression without
// waiting for a long fuzz run.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7, 99}) {
		report := run({seed = seed, iterations = 150})
		testing.expect_value(t, report.iterations, 150)
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at case %d (replay: jm-fuzz stream -seed=%d): %s",
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
	testing.expect_value(t, s.name, "stream")
	testing.expect(t, s.setup != nil, "a case needs a subject")
	testing.expect(t, len(s.properties) == 14, "every property must be registered")
	testing.expect(t, s.cancel != nil, "a pool that deadlocks has to be stoppable")
	for p in s.properties {
		testing.expect(t, p.name != "", "a property needs a name to be saved under")
		testing.expect(t, p.check != nil, "a property needs a body")
	}
}
