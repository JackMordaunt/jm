package plot_fuzz

import "core:testing"

// A short run on fixed seeds, so `just test` catches a regression without
// waiting for a long fuzz run.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7}) {
		report := run({seed = seed, iterations = 400, corpus_dir = CORPUS})
		testing.expect(t, report.iterations >= 400, "every case must run")
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at case %d (replay: jm-fuzz ui_plot -seed=%d): %s",
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
	testing.expect_value(t, s.name, "ui_plot")
	want := []string {
		"linear_ticks",
		"fit_linear",
		"log_ticks",
		"time_ticks",
		"decimate",
		"box_stats",
		"stack",
	}
	testing.expect_value(t, len(s.properties), len(want))
	for p, i in s.properties {
		if i < len(want) {
			testing.expect_value(t, p.name, want[i])
		}
		testing.expectf(t, p.check != nil, "%s has no check", p.name)
	}
}
