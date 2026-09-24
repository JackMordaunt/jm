package fuzz

import "core:testing"
import "core:time"

// A short run on fixed seeds, so `just test` catches a regression the
// example-based tests would not: they compare each column while the cursor is
// still on its row, which is exactly when a column read that forgot to clone
// still looks correct. Long runs are `just fuzz`.
@(test)
properties_hold :: proc(t: ^testing.T) {
	for seed in ([]u64{1, 3, 7, 99}) {
		report := run({seed = seed, iterations = 600, case_timeout = 30 * time.Second})
		testing.expect_value(t, report.iterations, 600)
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at iteration %d (replay: sqlite3-fuzz -seed=%d): %s",
				f.property,
				f.iteration,
				f.seed,
				f.detail,
			)
		}
	}
}

// A run must be a pure function of its seed, or a reported failure cannot be
// replayed and the harness is not worth having. The digest is what makes that
// checkable on a run where nothing failed, which is most of them.
@(test)
same_seed_same_run :: proc(t: ^testing.T) {
	first := run({seed = 42, iterations = 120})
	second := run({seed = 42, iterations = 120})
	// Absolute, so two equally empty reports cannot satisfy the pairwise
	// comparisons below.
	testing.expect_value(t, first.iterations, 120)
	testing.expect_value(t, second.iterations, 120)
	testing.expect(t, first.digest != 0, "a run that generated cases has a digest")
	testing.expect_value(t, first.seed, 42)
	testing.expect_value(t, first.digest, second.digest)
	testing.expect_value(t, len(first.failures), len(second.failures))
	for f, i in first.failures {
		testing.expect_value(t, f.property, second.failures[i].property)
		testing.expect_value(t, f.iteration, second.failures[i].iteration)
		testing.expect_value(t, f.detail, second.failures[i].detail)
	}
}

// A different seed must reach different cases, or the digest above would hold
// for any two runs and prove nothing.
@(test)
different_seed_different_run :: proc(t: ^testing.T) {
	a := run({seed = 42, iterations = 120})
	b := run({seed = 43, iterations = 120})
	testing.expect(t, a.digest != b.digest, "two seeds must not generate the same cases")
}

// A run asked for no particular seed must still report the one it used, or a
// random run that fails cannot be turned back into a deterministic one.
@(test)
unset_seed_is_filled_in :: proc(t: ^testing.T) {
	report := run({iterations = 6})
	testing.expect(t, report.seed != 0, "the seed used must come back in the report")
	replay := run({seed = report.seed, iterations = 6})
	testing.expect_value(t, replay.digest, report.digest)
}
