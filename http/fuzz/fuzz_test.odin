package http_fuzz

import "core:testing"

import harness "jm:fuzz"

// A short run of each suite on fixed seeds, replaying its corpus, so `just
// test` catches a regression without a long fuzz run.
@(test)
wire_holds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 2, 3}) {
		report := run_wire({seed = seed, iterations = 60, corpus_dir = WIRE_CORPUS})
		testing.expect(t, report.iterations >= 60, "every case must run")
		expect_clean(t, report)
	}
}

@(test)
model_holds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 2, 3}) {
		report := run_model({seed = seed, iterations = 30, corpus_dir = MODEL_CORPUS})
		testing.expect(t, report.iterations >= 30, "every case must run")
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
	for s in ([]harness.Suite(Subject){wire_suite(), model_suite()}) {
		testing.expect(t, s.setup != nil && s.teardown != nil, "a case needs a server")
		testing.expect_value(t, len(s.properties), 1)
	}
}
