package plot

import "core:math"
import "core:slice"
import "core:testing"

@(test)
test_linear_ticks_take_nice_steps :: proc(t: ^testing.T) {
	l := linear_ticks(0, 100, 6)
	testing.expect_value(t, l.step, 20)
	testing.expect_value(t, ticks_of(&l)[0], 0)
	testing.expect_value(t, l.n, 6)
	l = linear_ticks(0.13, 0.91, 5)
	testing.expect_value(t, l.step, 0.2)
	testing.expect(t, abs(l.v[0] - 0.2) < 1e-12, "tight ticks start inside the domain")
	l = linear_ticks(0, 10, 5)
	testing.expect_value(t, l.step, 2.5)
	l = linear_ticks(-3.7, 8.2, 8, loose = true)
	testing.expect_value(t, l.step, 2)
	testing.expect_value(t, l.v[0], -4)
	testing.expect_value(t, l.v[l.n - 1], 10)
}

@(test)
test_ticks_of_a_point_domain :: proc(t: ^testing.T) {
	l := linear_ticks(5, 5, 6)
	testing.expect_value(t, l.n, 1)
	lo, hi := nice_domain(5, 5, 6)
	testing.expect(t, lo < 5 && hi > 5, "a point domain widens around its value")
	lo, hi = nice_domain(0, 0, 6)
	testing.expect_value(t, [2]f64{lo, hi}, [2]f64{0, 1})
	none := linear_ticks(math.nan_f64(), 1, 5)
	testing.expect_value(t, none.n, 0)
}

@(test)
test_ticks_never_write_negative_zero :: proc(t: ^testing.T) {
	// The run starts at ceil(-0.3 / 0.5), which is -0, and -0 times the
	// step is -0 unless it is made 0.
	l := linear_ticks(-0.3, 1, 5)
	zero := -1
	for v, i in ticks_of(&l) {
		if v == 0 {
			zero = i
		}
	}
	testing.expectf(t, zero >= 0, "a domain across zero ticks it: %v", ticks_of(&l))
	if zero >= 0 {
		testing.expect(t, !math.sign_bit(l.v[zero]), "the tick at zero is -0")
	}
}

@(test)
test_log_ticks_step_by_decades :: proc(t: ^testing.T) {
	l := log_ticks(1, 1000, 10)
	testing.expect(t, slice.equal(ticks_of(&l)[:4], []f64{1, 2, 5, 10}), "1, 2 and 5 a decade")
	l = log_ticks(1, 1e12, 6)
	testing.expect_value(t, l.n, 5) // every third decade, an SI prefix apart
	testing.expect_value(t, l.v[1], 1e3)
	l = log_ticks(0, 10, 5)
	testing.expect_value(t, l.n, 0)
}

@(test)
test_scales_map_and_invert :: proc(t: ^testing.T) {
	s := Scale{.Linear, 0, 100, 200, 0}
	testing.expect_value(t, scale_to(s, 25), 150)
	testing.expect_value(t, scale_from(s, 150), 25)
	lg := Scale{.Log, 1, 1000, 0, 300}
	testing.expect(t, abs(scale_to(lg, 10) - 100) < 1e-3, "a decade a third of the way")
	testing.expect(t, math.is_nan(scale_to(lg, 0)), "zero has no place on a log scale")
	testing.expect(t, abs(scale_from(lg, 200) - 100) < 1e-6, "inverse of a decade")
}

@(test)
test_bands_tile_their_range :: proc(t: ^testing.T) {
	b := Band{n = 4, r0 = 0, r1 = 400, inner = 0.2, outer = 0.1}
	step := band_step(b)
	testing.expect(t, abs(band_start(b, 0) - step * 0.1) < 1e-4, "outer room before the first band")
	last_end := band_start(b, 3) + band_width(b)
	testing.expect(t, abs(400 - last_end - step * 0.1) < 1e-3, "and after the last")
	for i in 0 ..< 4 {
		testing.expect_value(t, band_at(b, band_center(b, i)), i)
	}
	testing.expect_value(t, band_at(b, -50), 0)
	testing.expect_value(t, band_at(b, 900), 3)
}

@(test)
test_formats_write_si_and_units :: proc(t: ^testing.T) {
	hash := Number_Format{unit = "H/s", short = .Metric, space = true}
	a := axis_format(hash, 0.5e15, 1.5e15)
	want := [?]string{"0 PH/s", "0.5 PH/s", "1.0 PH/s", "1.5 PH/s"} // zero bare, the rest alike
	for w, i in want {
		l := format_tick(hash, a, f64(i) * 0.5e15)
		testing.expect_value(t, label_text(&l), w)
	}
	money := Number_Format{prefix = "$", short = .Finance}
	l := format_value(money, 1234)
	testing.expect_value(t, label_text(&l), "$1.23k")
	l = format_value(money, -2.5e9)
	testing.expect_value(t, label_text(&l), "−$2.50B")
	exact := Number_Format{prefix = "$", grouped = true, decimals = 2}
	l = format_value(exact, 1234567.891)
	testing.expect_value(t, label_text(&l), "$1,234,567.89")
	pct := Number_Format{unit = "%"}
	a = axis_format(pct, 2.5, 100)
	l = format_tick(pct, a, 97.5)
	testing.expect_value(t, label_text(&l), "97.5%")
	l = format_tick(pct, a, -0.0)
	testing.expect_value(t, label_text(&l), "0%")
}
