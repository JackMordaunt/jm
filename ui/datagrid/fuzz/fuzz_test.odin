package datagrid_fuzz

import "core:testing"

import harness "jm:fuzz"

// A short run of each suite on fixed seeds, replaying its corpus, so `just
// test` catches a regression without a long fuzz run.
@(test)
model_holds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 2, 3}) {
		report := run_model({seed = seed, iterations = 300, corpus_dir = MODEL_CORPUS})
		testing.expect(t, report.iterations >= 300, "every case must run")
		expect_clean(t, report)
	}
}

@(test)
paged_holds_on_fixed_seeds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 2, 3}) {
		report := run_paged({seed = seed, iterations = 40, corpus_dir = PAGED_CORPUS})
		testing.expect(t, report.iterations >= 40, "every case must run")
		expect_clean(t, report)
	}
}

expect_clean :: proc(t: ^testing.T, report: harness.Report) {
	for f in report.failures {
		testing.expectf(
			t,
			false,
			"%s failed at case %d (replay: jm-fuzz with -seed=%d): %s",
			f.property,
			f.iteration,
			f.seed,
			f.detail,
		)
	}
}

@(test)
suites_are_complete :: proc(t: ^testing.T) {
	testing.expect_value(t, len(model_suite().properties), 7)
	testing.expect_value(t, len(paged_suite().properties), 1)
}
