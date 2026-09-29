package git_fuzz

import "core:testing"
import "core:time"

// A short run on fixed seeds, so `just test` catches a sequence the
// example-based tests never try. Every case makes three repositories on
// disk, so the counts are modest; long runs are `just fuzz git`.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 7, 99}) {
		report := run({seed = seed, iterations = 120, case_timeout = 60 * time.Second})
		testing.expect_value(t, report.iterations, 120)
		for f in report.failures {
			testing.expectf(t, false, "%s failed at case %d (replay: jm-fuzz git -seed=%d): %s", f.property, f.iteration, f.seed, f.detail)
		}
	}
}

// The suite must describe itself completely, or jm:fuzz cannot run it.
// It has no cancel: every operation is on local files and returns.
@(test)
suite_is_complete :: proc(t: ^testing.T) {
	s := suite()
	testing.expect_value(t, s.name, "git")
	testing.expect(t, s.setup != nil, "a case needs a world")
	testing.expect(t, s.teardown != nil, "a case must give it back")
	testing.expect(t, len(s.properties) == 3, "every property must be registered")
	for p in s.properties {
		testing.expect(t, p.name != "", "a property needs a name to be saved under")
		testing.expect(t, p.check != nil, "a property needs a body")
	}
}

// A run is a pure function of its seed, so a failure replays exactly.
@(test)
same_seed_same_run :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	first := run({seed = 42, iterations = 30})
	second := run({seed = 42, iterations = 30})
	testing.expect_value(t, first.iterations, 30)
	testing.expect(t, first.digest != 0, "a run that generated cases has a digest")
	testing.expect_value(t, first.digest, second.digest)
}
