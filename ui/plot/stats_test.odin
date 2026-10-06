package plot

import "core:math"
import "core:testing"

// The expected values below are what @sgratzl/boxplots 4.4 (the admin's
// Chart.js plugin's statistics, at its defaults) returns for the same
// samples, printed by running it under node.

@(test)
test_box_stats_match_the_chartjs_plugin :: proc(t: ^testing.T) {
	Case :: struct {
		samples:                                []f64,
		min, max, q1, median, q3, lo, hi, mean: f64,
		outliers:                               []f64,
	}
	cases := []Case {
		{{1, 2, 3, 4, 5, 6, 7, 8, 9, 100}, 1, 100, 3.25, 5.5, 7.75, 1, 9, 14.5, {100}},
		{
			{97.2, 98.1, 99.5, 95.0, 101.3, 88.4, 99.9, 100.2, 97.7, 62.0, 99.1, 98.8, 103.5},
			62,
			103.5,
			97.2,
			98.8,
			99.9,
			95,
			103.5,
			95.43846153846152,
			{62, 88.4},
		},
		{{5}, 5, 5, 5, 5, 5, 5, 5, 5, {}},
	}
	for c in cases {
		b := box_stats(c.samples, context.temp_allocator)
		got := [?]f64{b.min, b.max, b.q1, b.median, b.q3, b.whisker_lo, b.whisker_hi, b.mean}
		want := [?]f64{c.min, c.max, c.q1, c.median, c.q3, c.lo, c.hi, c.mean}
		for g, i in got {
			testing.expectf(
				t,
				abs(g - want[i]) < 1e-9,
				"%v: field %d is %v, the plugin says %v",
				c.samples,
				i,
				g,
				want[i],
			)
		}
		testing.expectf(
			t,
			len(b.outliers) == len(c.outliers),
			"%v: outliers %v, want %v",
			c.samples,
			b.outliers,
			c.outliers,
		)
		for o, i in c.outliers {
			if i < len(b.outliers) {
				testing.expect_value(t, b.outliers[i], o)
			}
		}
	}
}

@(test)
test_box_stats_leave_out_what_is_not_a_number :: proc(t: ^testing.T) {
	b := box_stats({3, 1, math.nan_f64(), 2, math.inf_f64(1), 4}, context.temp_allocator)
	// The plugin gives the same quartiles for {3, 1, NaN, 2, 4}; it counts
	// the NaN, box_stats counts samples it summarised.
	testing.expect_value(t, b.count, 4)
	testing.expect_value(t, b.q1, 1.75)
	testing.expect_value(t, b.median, 2.5)
	testing.expect_value(t, b.q3, 3.25)
	empty := box_stats({math.nan_f64()}, context.temp_allocator)
	testing.expect_value(t, empty.count, 0)
	testing.expect(t, math.is_nan(empty.median), "an empty sample has no median")
}

@(test)
test_whiskers_stop_at_samples_not_fences :: proc(t: ^testing.T) {
	// q1 2, q3 8, IQR 6: the fences are -7 and 17. The whiskers end on
	// the samples nearest inside them, 0 and 14, not on the fences.
	b := box_stats({0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 14, 30, -20}, context.temp_allocator)
	testing.expect_value(t, b.whisker_lo, 0)
	testing.expect_value(t, b.whisker_hi, 14)
	testing.expect_value(t, len(b.outliers), 2)
}

@(test)
test_quantile_is_type_seven :: proc(t: ^testing.T) {
	s := []f64{10, 20, 30, 40}
	// h = p (n - 1): 0.25 * 3 = 0.75, so 10 + 0.75 * 10.
	testing.expect_value(t, quantile(s, 0.25), 17.5)
	testing.expect_value(t, quantile(s, 0), 10)
	testing.expect_value(t, quantile(s, 1), 40)
}

@(test)
test_stacks_diverge_from_zero :: proc(t: ^testing.T) {
	values := []f64{3, -2, 4, math.nan_f64(), -1, 5}
	lo, hi: [6]f64
	shown := Series_Set{0, 1, 2, 3, 4} // the last is hidden
	stack_bounds(values, shown, lo[:], hi[:])
	testing.expect_value(t, lo, [6]f64{0, -2, 3, 7, -3, 7})
	testing.expect_value(t, hi, [6]f64{3, 0, 7, 7, -2, 7})
}
