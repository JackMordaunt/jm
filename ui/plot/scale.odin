package plot

import "core:math"

// MAX_TICKS is the most ticks an axis carries. Ticks live in a fixed
// array, so laying an axis out allocates nothing.
MAX_TICKS :: 32

// Tick_List is an axis's tick values in increasing order. step is the
// distance between neighbours on a linear axis, which sets how many
// decimals their labels need; 0 on a log or time axis.
Tick_List :: struct {
	v:    [MAX_TICKS]f64,
	n:    int,
	step: f64,
}

// ticks_of is l's values as a slice.
ticks_of :: proc(l: ^Tick_List) -> []f64 {
	return l.v[:l.n]
}

// NICE are the mantissas a step may take, as Heckbert's "nice numbers"
// (Graphics Gems, 1990) with 2.5 added: 1, 2, 2.5 and 5 times a power of
// ten. The first that fits the count wins, so steps stay as fine as the
// axis has room for.
@(private)
NICE := [?]f64{1, 2, 2.5, 5, 10}

// linear_ticks is at most max_count ticks over [lo, hi] on a linear axis,
// at a nice step. Loose ticks start at or below lo and end at or above hi,
// for an axis whose domain is then widened to them (nice_domain); tight
// ticks all lie inside [lo, hi]. A domain that is not finite gives none;
// one with no width gives the one value, as a domain widened around it
// would show it.
linear_ticks :: proc(lo, hi: f64, max_count: int, loose := false) -> (l: Tick_List) {
	lo, hi := lo, hi
	if !is_finite(lo) || !is_finite(hi) {
		return
	}
	if lo > hi {
		lo, hi = hi, lo
	}
	want := clamp(max_count, 1, MAX_TICKS)
	step := 0 if degenerate(lo, hi) else nice_step(lo, hi, want, loose)
	if step != 0 {
		l.step = step
		add_multiples(&l, lo, hi, loose)
	}
	if l.n == 0 {
		// A domain with no width, or narrower than the step that fits one
		// tick, holds no multiple of it: its start stands in.
		l.v[0], l.n = lo, 1
	}
	return
}

// add_multiples adds l.step's multiples of a tight (or loose) run over
// [lo, hi] to l.
@(private)
add_multiples :: proc(l: ^Tick_List, lo, hi: f64, loose: bool) {
	first, last := run_ends(lo, hi, l.step, loose)
	for k := first; k <= last && l.n < MAX_TICKS; k += 1 {
		v := k * l.step + 0 // + 0 turns -0 into 0, which formats as "0"
		// A tight run's ends can round a hair outside it, and a multiple
		// near the top of f64 can overflow.
		if !is_finite(v) || (!loose && (v < lo || v > hi)) {
			continue
		}
		l.v[l.n] = v
		l.n += 1
	}
}

// nice_step is the finest nice step that puts at most want ticks on
// [lo, hi], or 0 when the domain is too narrow for its magnitude to step
// across at all in f64.
@(private)
nice_step :: proc(lo, hi: f64, want: int, loose: bool) -> f64 {
	span := hi - lo
	raw := span / f64(max(want - 1, 1))
	mag := math.pow(10, math.floor(math.log10(raw)))
	for _ in 0 ..< 4 {
		for m in NICE {
			step := m * mag
			if !is_finite(step) || step <= 0 {
				return 0
			}
			if tick_count(lo, hi, step, loose) <= f64(want) {
				return step
			}
		}
		mag *= 10
	}
	return 0
}

// run_ends is the first and last multiple of step, as multiples, of a
// tight (or loose) run over [lo, hi]. lo / step rounds, so a loose end's
// multiple can land a hair inside the domain; one more step out keeps it
// outside.
@(private)
run_ends :: proc(lo, hi, step: f64, loose: bool) -> (first, last: f64) {
	if !loose {
		return math.ceil(lo / step), math.floor(hi / step)
	}
	first, last = math.floor(lo / step), math.ceil(hi / step)
	if first * step > lo {
		first -= 1
	}
	if last * step < hi {
		last += 1
	}
	return
}

// tick_count is how many multiples of step a tight (or loose) run over
// [lo, hi] holds.
@(private)
tick_count :: proc(lo, hi, step: f64, loose: bool) -> f64 {
	first, last := run_ends(lo, hi, step, loose)
	return last - first + 1
}

// degenerate reports whether [lo, hi] is too narrow to tick: no width, or
// a width under a billionth of its magnitude. The cutoff is a margin, well
// short of f64's 2e-16, that keeps a step thousands of ulps wide and the
// multiples counting up to it small whole numbers.
@(private)
degenerate :: proc(lo, hi: f64) -> bool {
	mag := max(abs(lo), abs(hi))
	return hi - lo <= mag * 1e-9 || hi - lo < 1e-300
}

// nice_domain widens [lo, hi] to the loose ticks' ends, as an axis does
// before it maps values, so its first and last gridlines sit on the
// plot's edges. A domain with no width is widened around its value first:
// by a tenth of it either way, or to [0, 1] at zero.
nice_domain :: proc(lo, hi: f64, max_count: int) -> (f64, f64) {
	lo, hi := lo, hi
	if !is_finite(lo) || !is_finite(hi) {
		return 0, 1
	}
	if lo > hi {
		lo, hi = hi, lo
	}
	if degenerate(lo, hi) {
		pad := abs(lo) * 0.1
		if pad == 0 {
			return 0, 1
		}
		lo, hi = lo - pad, hi + pad
	}
	l := linear_ticks(lo, hi, max_count, loose = true)
	if l.n < 2 {
		return lo, hi
	}
	return l.v[0], l.v[l.n - 1]
}

// log_ticks is at most max_count ticks over [lo, hi] on a log axis: every
// power of ten when they fit, every second, third (an SI prefix apart),
// fifth or tenth one when they do not, and 2 and 5 times each power as
// well when there is room for three a decade. A domain that does not lie
// above zero gives none.
log_ticks :: proc(lo, hi: f64, max_count: int) -> (l: Tick_List) {
	lo, hi := lo, hi
	if lo > hi {
		lo, hi = hi, lo
	}
	if !(is_finite(hi) && lo > 0) {
		return // NaN fails lo > 0, and lo > 0 below a finite hi is finite
	}
	want := clamp(max_count, 1, MAX_TICKS)
	e0, e1 := math.floor(math.log10(lo)), math.ceil(math.log10(hi))
	decades := e1 - e0
	if decades * 3 + 1 <= f64(want) && decades <= 3 {
		log_tick_add_125(&l, e0, e1, lo, hi)
		return
	}
	every := log_every(decades, want)
	for e := math.ceil(e0 / every) * every; e <= e1 && l.n < want; e += every {
		log_tick_add(&l, math.pow(10, e), lo, hi)
	}
	return
}

// log_tick_add_125 adds 1, 2 and 5 times each power of ten from 10^e0 to
// 10^e1 that lies in [lo, hi].
@(private)
log_tick_add_125 :: proc(l: ^Tick_List, e0, e1, lo, hi: f64) {
	for e := e0; e <= e1; e += 1 {
		for m in ([3]f64{1, 2, 5}) {
			log_tick_add(l, m * math.pow(10, e), lo, hi)
		}
	}
}

// log_every is how many decades apart log ticks over decades stand to
// number at most want: the first nice count that fits, else as many as
// it takes.
@(private)
log_every :: proc(decades: f64, want: int) -> f64 {
	for e in ([?]f64{1, 2, 3, 5, 10, 20, 50}) {
		if math.floor(decades / e) + 1 <= f64(want) {
			return e
		}
	}
	return math.ceil(decades / f64(want - 1)) if want > 1 else decades + 1
}

@(private)
log_tick_add :: proc(l: ^Tick_List, v, lo, hi: f64) {
	if v >= lo * (1 - 1e-12) && v <= hi * (1 + 1e-12) && l.n < MAX_TICKS && is_finite(v) {
		l.v[l.n] = v
		l.n += 1
	}
}

// Scale_Kind is how a value axis maps values to positions.
Scale_Kind :: enum u8 {
	Linear,
	Log, // base 10; values at or below zero have no position and draw as gaps
}

// Scale maps a domain of values onto a range of positions: d0 lands on
// r0 and d1 on r1, so a y axis passes its bottom as r0.
Scale :: struct {
	kind:   Scale_Kind,
	d0, d1: f64,
	r0, r1: f32,
}

// scale_to is v's position on s; NaN when v has none (not finite, or not
// above zero on a log scale).
scale_to :: proc(s: Scale, v: f64) -> f32 {
	a, b, x := s.d0, s.d1, v
	if s.kind == .Log {
		if v <= 0 || s.d0 <= 0 || s.d1 <= 0 {
			return math.nan_f32()
		}
		a, b, x = math.log10(s.d0), math.log10(s.d1), math.log10(v)
	}
	if !is_finite(x) {
		return math.nan_f32()
	}
	if b == a {
		return (s.r0 + s.r1) / 2
	}
	t := (x - a) / (b - a)
	return f32(f64(s.r0) + t * f64(s.r1 - s.r0))
}

// scale_from is the value at position p on s: scale_to's inverse.
scale_from :: proc(s: Scale, p: f32) -> f64 {
	if s.r1 == s.r0 {
		return s.d0
	}
	t := f64(p - s.r0) / f64(s.r1 - s.r0)
	if s.kind == .Log {
		a, b := math.log10(s.d0), math.log10(s.d1)
		return math.pow(10, a + t * (b - a))
	}
	return s.d0 + t * (s.d1 - s.d0)
}

// Band is a categorical axis: n bands laid side by side over [r0, r1],
// each with a share inner of its step left empty between it and the
// next, and outer steps' worth of room at either end.
Band :: struct {
	n:      int,
	r0, r1: f32,
	inner:  f32, // 0-1: the share of each step between bands
	outer:  f32, // steps of room before the first band and after the last
}

// band_step is the distance from one band's start to the next's.
band_step :: proc(b: Band) -> f32 {
	if b.n <= 0 {
		return 0
	}
	return (b.r1 - b.r0) / (f32(b.n) - b.inner + 2 * b.outer)
}

// band_width is how wide each band is.
band_width :: proc(b: Band) -> f32 {
	return band_step(b) * (1 - b.inner)
}

// band_start is where band i starts: past the outer room and i steps.
band_start :: proc(b: Band, i: int) -> f32 {
	return b.r0 + band_step(b) * (b.outer + f32(i))
}

// band_center is the middle of band i.
band_center :: proc(b: Band, i: int) -> f32 {
	return band_start(b, i) + band_width(b) / 2
}

// band_at is the band nearest position p, or -1 when there are none.
band_at :: proc(b: Band, p: f32) -> int {
	step := band_step(b)
	if b.n <= 0 || step == 0 {
		return -1
	}
	i := int(math.floor((p - b.r0) / step - b.outer + b.inner / 2))
	return clamp(i, 0, b.n - 1)
}

// is_finite reports whether v is a number other than an infinity.
is_finite :: proc(v: f64) -> bool {
	return !math.is_nan(v) && !math.is_inf(v)
}
