package plot

import "core:math"
import "core:slice"

// Box_Stats is a box plot's summary of a sample, as box_stats computes it.
Box_Stats :: struct {
	count:          int, // finite samples; NaN and the infinities are left out
	min, max:       f64,
	q1, median, q3: f64,
	whisker_lo:     f64, // the lowest sample at or above q1 - 1.5 IQR
	whisker_hi:     f64, // the highest sample at or below q3 + 1.5 IQR
	mean:           f64,
	outliers:       []f64, // the samples beyond the whiskers, ascending
}

// FENCE_EPS is how near a fence a sample counts as on it: the plugin's
// eps, 10e-3.
FENCE_EPS :: 0.01

// WHISKER_IQR is how many interquartile ranges past the box a whisker may
// reach: Tukey's 1.5.
WHISKER_IQR :: 1.5

// box_stats summarises samples as a Tukey box plot does, the way the
// admin's Chart.js boxplot plugin (@sgratzl/chartjs-chart-boxplot 4.4,
// over @sgratzl/boxplots) does by default, so a chart drawn from the same
// data agrees with it:
//
//   - quartiles are R's type 7 (Hyndman & Fan 1996), the plugin's
//     default: the p-quantile of n sorted samples x is x[h] interpolated
//     linearly to x[h+1] at h = p (n - 1), counting from 0;
//   - each whisker ends at the most extreme sample inside 1.5 IQR of its
//     quartile (the plugin's whiskersMode "nearest"), never at the fence,
//     a sample within FENCE_EPS of a fence counting as inside, as the
//     plugin's eps does;
//   - every sample beyond a whisker is an outlier.
//
// One difference: the plugin drops an outlier within 0.01 of the one
// before it, to draw fewer dots; box_stats keeps them all. outliers is
// allocated on allocator; the samples are copied and sorted there too and
// the copy freed.
box_stats :: proc(samples: []f64, allocator := context.allocator) -> (b: Box_Stats) {
	sorted := make([dynamic]f64, 0, len(samples), allocator)
	defer delete(sorted)
	// A running mean, which a sum of large samples cannot overflow.
	mean: f64
	for v in samples {
		if is_finite(v) {
			append(&sorted, v)
			mean += (v - mean) / f64(len(sorted))
		}
	}
	b.count = len(sorted)
	if b.count == 0 {
		nan := math.nan_f64()
		b.min, b.max, b.q1, b.median, b.q3, b.whisker_lo, b.whisker_hi, b.mean =
			nan, nan, nan, nan, nan, nan, nan, nan
		return
	}
	slice.sort(sorted[:])
	s := sorted[:]
	b.min, b.max = s[0], s[len(s) - 1]
	b.mean = mean
	b.q1, b.median, b.q3 = quantile(s, 0.25), quantile(s, 0.5), quantile(s, 0.75)
	iqr := b.q3 - b.q1
	lo_fence, hi_fence := b.q1 - WHISKER_IQR * iqr, b.q3 + WHISKER_IQR * iqr
	first, last := 0, len(s) - 1
	// The bounds hold where the fences are not numbers: samples whose
	// spread overflows f64 make the IQR infinite.
	// Compared as the plugin compares, a distance from the fence: a fence
	// plus FENCE_EPS rounds back to the fence at the top of f64.
	for first < last && s[first] < lo_fence && lo_fence - s[first] >= FENCE_EPS {
		first += 1
	}
	for last > first && s[last] > hi_fence && s[last] - hi_fence >= FENCE_EPS {
		last -= 1
	}
	b.whisker_lo, b.whisker_hi = s[first], s[last]
	outliers := make([]f64, first + len(s) - 1 - last, allocator)
	copy(outliers, s[:first])
	copy(outliers[first:], s[last + 1:])
	b.outliers = outliers
	return
}

// quantile is R's type 7 p-quantile of sorted, which must not be empty:
// sorted[h] interpolated linearly toward sorted[h+1] at h = p (n - 1).
quantile :: proc(sorted: []f64, p: f64) -> f64 {
	h := p * f64(len(sorted) - 1)
	lo := int(math.floor(h))
	hi := min(lo + 1, len(sorted) - 1)
	f := h - f64(lo)
	if f == 0 {
		return sorted[lo]
	}
	// Weighted rather than lo + f (hi - lo), whose difference overflows
	// for samples near both ends of f64.
	return sorted[lo] * (1 - f) + sorted[hi] * f
}

// stack_bounds stacks one category's values, one per series, as stacked
// bars do: each positive value stacks up from zero on the positives
// before it and each negative down from zero on the negatives, so the two
// never overlap. A value that is not finite, or a series not shown, adds
// nothing and its bounds are both where its stack stands. lo[i] and hi[i]
// are value i's ends; both must be as long as values.
stack_bounds :: proc(values: []f64, shown: Series_Set, lo, hi: []f64) {
	up, down: f64
	for v, i in values {
		if !(i in shown) || !is_finite(v) {
			lo[i], hi[i] = up, up
			continue
		}
		if v >= 0 {
			lo[i], hi[i] = up, up + v
			up += v
		} else {
			lo[i], hi[i] = down + v, down
			down += v
		}
	}
}

// MAX_SERIES is the most series a chart holds.
MAX_SERIES :: 64

// Series_Set is a set of series by index: which are shown, or hidden.
Series_Set :: bit_set[0 ..< MAX_SERIES]
