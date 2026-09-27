package render_fuzz

import "core:testing"

// A short run on fixed seeds, so `just test` catches a regression without
// waiting for a long fuzz run.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7}) {
		report := run({seed = seed, iterations = 40})
		testing.expect_value(t, report.iterations, 40)
		for f in report.failures {
			testing.expectf(t, false, "%s failed at case %d (replay: jm-fuzz ui_render -seed=%d): %s", f.property, f.iteration, f.seed, f.detail)
		}
	}
}

@(test)
suite_is_complete :: proc(t: ^testing.T) {
	s := suite()
	testing.expect_value(t, s.name, "ui_render")
	testing.expect(t, s.setup != nil && s.teardown != nil, "a case needs a rig and must give it back")
	testing.expect_value(t, len(s.properties), 3)
}
