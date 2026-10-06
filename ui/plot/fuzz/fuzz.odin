/*
Package fuzz is the jm:ui/plot suite for jm:fuzz: the promises an axis
makes about its ticks and labels, and the ones decimation, box plots and
stacks make about the data they draw.

	report := fuzz.run({seed = 1, iterations = 10_000})

	linear_ticks  ticks rise, stay in the domain (or cover it, loose), number
	              at most what was asked, and their labels differ
	log_ticks     ticks rise, stay in the domain and number at most asked
	time_ticks    ticks rise, stay in the domain, number at most asked, and
	              each reads uniquely with the context line in force
	decimate      every column's lowest and highest point survive, and at
	              most four points a column are kept
	box_stats     the box is ordered inside the sample's range, the whiskers
	              too, and its outliers lie past the whiskers
	stack         stacked bounds tile from zero without overlapping

Domains are drawn from jm:fuzz's edge values (NaN, the infinities, the ends
of f64) as well as from ordinary magnitudes, so a degenerate axis must still
keep its promises or give no ticks at all.
*/
package plot_fuzz

import "core:fmt"
import "core:math"
import "core:time/datetime"

import harness "jm:fuzz"
import "jm:ui/ops"
import "jm:ui/plot"

// No subject: every case builds its own inputs.
Subject :: struct {}

properties := []harness.Property(Subject) {
	{"linear_ticks", linear_ticks},
	{"log_ticks", log_ticks},
	{"time_ticks", time_ticks},
	{"decimate", decimate},
	{"box_stats", box_stats},
	{"stack", stack},
}

// suite is jm:ui/plot's pure parts and their promises, ready for harness.run.
suite :: proc() -> harness.Suite(Subject) {
	return harness.Suite(Subject) {
		name = "ui_plot",
		setup = proc() -> (Subject, bool) {return {}, true},
		properties = properties,
	}
}

// CORPUS is where this suite's regressions live, relative to the repository
// root.
CORPUS :: "ui/plot/fuzz/corpus"

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

// value draws a number: an edge value, or one of a magnitude drawn from
// 1e-12 to 1e15, either sign, as data on an axis is.
value :: proc(src: ^harness.Source) -> f64 {
	if harness.integer_in(src, 0, 8) == 0 {
		return harness.real(src)
	}
	mag := math.pow(10, f64(harness.integer_in(src, -12, 16)))
	v := f64(harness.integer_in(src, 0, 100_000)) / 1000 * mag
	return -v if harness.boolean(src) else v
}

// domain draws two ends, often close together, as a zoomed axis has.
domain :: proc(src: ^harness.Source) -> (lo, hi: f64) {
	lo = value(src)
	switch harness.integer_in(src, 0, 4) {
	case 0:
		hi = lo
	case 1:
		hi = lo + abs(lo) * math.pow(10, f64(-harness.integer_in(src, 0, 14)))
	case:
		hi = value(src)
	}
	return
}

FORMATS := []plot.Number_Format {
	{},
	{unit = "H/s", short = .Metric, space = true},
	{prefix = "$", short = .Finance},
	{unit = "%"},
}

linear_ticks :: proc(_: Subject, src: ^harness.Source) -> (string, bool) {
	lo, hi := domain(src)
	want := harness.integer_in(src, 0, 40)
	loose := harness.boolean(src)
	l := plot.linear_ticks(lo, hi, want, loose)
	a, b := min(lo, hi), max(lo, hi)
	ts := plot.ticks_of(&l)
	where_ := fmt.tprintf("linear_ticks(%v, %v, %d, loose=%v) = %v", lo, hi, want, loose, ts)
	if plot.is_finite(lo) && plot.is_finite(hi) && len(ts) == 0 {
		return fmt.tprint(where_, ": a finite domain has no ticks"), false
	}
	if len(ts) > max(clamp(want, 1, plot.MAX_TICKS), 1) {
		return fmt.tprint(where_, ": more ticks than asked"), false
	}
	if msg, ok := rising(ts, where_); !ok {
		return msg, false
	}
	if detail, ok := in_domain(ts, a, b, loose && len(ts) > 1 && l.step > 0, where_); !ok {
		return detail, false
	}
	f := harness.choice(src, FORMATS)
	return check_unique_labels(f, &l, where_)
}

// in_domain checks tight ticks lie in [a, b] and loose ones cover it,
// short of where covering it would overflow f64.
in_domain :: proc(ts: []f64, a, b: f64, loose: bool, where_: string) -> (string, bool) {
	for v in ts {
		if !plot.is_finite(v) {
			return fmt.tprint(where_, ": a tick is not finite"), false
		}
		if !loose && (v < a || v > b) && len(ts) > 1 {
			return fmt.tprint(where_, ": a tick outside the domain"), false
		}
	}
	if loose && max(abs(a), abs(b)) < 1e300 && (ts[0] > a || ts[len(ts) - 1] < b) {
		return fmt.tprint(where_, ": loose ticks do not cover the domain"), false
	}
	return "", true
}

rising :: proc(ts: []f64, where_: string) -> (string, bool) {
	for i in 1 ..< len(ts) {
		if !(ts[i] > ts[i - 1]) {
			return fmt.tprint(where_, ": ticks do not rise"), false
		}
	}
	return "", true
}

check_unique_labels :: proc(
	f: plot.Number_Format,
	l: ^plot.Tick_List,
	where_: string,
) -> (
	string,
	bool,
) {
	ts := plot.ticks_of(l)
	mag: f64
	for v in ts {
		mag = max(mag, abs(v))
	}
	a := plot.axis_format(f, l.step, mag)
	seen := make(map[string]int, context.temp_allocator)
	for v, i in ts {
		lab := plot.format_tick(f, a, v)
		s := fmt.tprint(plot.label_text(&lab))
		if j, dup := seen[s]; dup {
			return fmt.tprintf("%s: ticks %v and %v both read %q", where_, ts[j], v, s), false
		}
		seen[s] = i
	}
	return "", true
}

log_ticks :: proc(_: Subject, src: ^harness.Source) -> (string, bool) {
	lo, hi := domain(src)
	want := harness.integer_in(src, 0, 40)
	l := plot.log_ticks(lo, hi, want)
	ts := plot.ticks_of(&l)
	a, b := min(lo, hi), max(lo, hi)
	where_ := fmt.tprintf("log_ticks(%v, %v, %d) = %v", lo, hi, want, ts)
	if len(ts) > clamp(want, 1, plot.MAX_TICKS) {
		return fmt.tprint(where_, ": more ticks than asked"), false
	}
	if msg, ok := rising(ts, where_); !ok {
		return msg, false
	}
	for v in ts {
		if v < a * (1 - 1e-9) || v > b * (1 + 1e-9) || v <= 0 {
			return fmt.tprint(where_, ": a tick outside the domain"), false
		}
	}
	return "", true
}

// new_york is America/New_York's offsets from 2025 to 2028, written out so
// the suite needs no tz database.
@(private)
new_york :: proc() -> plot.Zone {
	@(static) records := [?]datetime.TZ_Record {
		{time = -2717650800, utc_offset = -18000},
		{time = 1741503600, utc_offset = -14400, dst = true},
		{time = 1762063200, utc_offset = -18000},
		{time = 1772953200, utc_offset = -14400, dst = true},
		{time = 1793512800, utc_offset = -18000},
		{time = 1805007600, utc_offset = -14400, dst = true},
		{time = 1825567200, utc_offset = -18000},
		{time = 4102444800, utc_offset = -18000},
	}
	@(static) region: datetime.TZ_Region
	region = {
		name    = "America/New_York",
		records = records[:],
	}
	return {region = &region}
}

time_ticks :: proc(_: Subject, src: ^harness.Source) -> (string, bool) {
	// From 2025 to 2028, where the written-out zone has its transitions,
	// spans from a minute to a century.
	lo := 1735689600 + f64(harness.integer_in(src, 0, 3 * 365 * 86400))
	span := math.pow(10, f64(harness.integer_in(src, 10, 95)) / 10) // 10 s to 3e9 s
	z: plot.Zone
	switch harness.integer_in(src, 0, 3) {
	case 0:
	case 1:
		z.offset = i64(harness.integer_in(src, -56, 57)) * 900 // whole quarter hours, ±14 h
	case 2:
		z = new_york()
	}
	want := harness.integer_in(src, 1, 40)
	tk := plot.time_ticks(lo, lo + span, want, z)
	ts := plot.ticks_of(&tk)
	where_ := fmt.tprintf(
		"time_ticks(%v, +%v s, %d, offset %v ny %v) at %v",
		lo,
		span,
		want,
		z.offset,
		z.region != nil,
		tk.unit,
	)
	if len(ts) > clamp(want, 1, plot.MAX_TICKS) {
		return fmt.tprint(where_, ": more ticks than asked"), false
	}
	if msg, ok := rising(ts, where_); !ok {
		return msg, false
	}
	seen := make(map[string]bool, context.temp_allocator)
	sub := ""
	for v, i in ts {
		if v < lo || v > lo + span {
			return fmt.tprintf("%s: tick %v outside the domain", where_, v), false
		}
		l := plot.time_label(&tk, i, z)
		if l.sub.n > 0 {
			sub = fmt.tprint(plot.label_text(&l.sub))
		}
		key := fmt.tprintf("%s|%s", sub, plot.label_text(&l.main))
		if seen[key] {
			return fmt.tprintf("%s: %q twice", where_, key), false
		}
		seen[key] = true
	}
	return "", true
}

decimate :: proc(_: Subject, src: ^harness.Source) -> (string, bool) {
	n := harness.integer_in(src, 0, 3000)
	cols := harness.integer_in(src, 1, 200)
	line: plot.Polyline
	line.points = make([dynamic]ops.Point, context.temp_allocator)
	line.starts = make([dynamic]int, context.temp_allocator)
	r := plot.Reducer {
		out = &line,
	}
	lo := make([]f32, cols, context.temp_allocator)
	hi := make([]f32, cols, context.temp_allocator)
	for c in 0 ..< cols {
		lo[c], hi[c] = max(f32), min(f32)
	}
	walk := f32(0)
	for i in 0 ..< n {
		x := f32(i) / f32(max(n, 1)) * f32(cols)
		walk += f32(harness.integer_in(src, -100, 101))
		reduce := harness.integer_in(src, 0, 50) != 0
		if !reduce { 	// a gap
			plot.reduce_break(&r)
			continue
		}
		plot.reduce_push(&r, {x, walk}, i)
		c := int(x)
		lo[c], hi[c] = min(lo[c], walk), max(hi[c], walk)
	}
	plot.reduce_flush(&r)
	if len(line.points) > 4 * cols + 4 * len(line.starts) {
		return fmt.tprintf("%d points kept for %d columns", len(line.points), cols), false
	}
	for c in 0 ..< cols {
		if lo[c] > hi[c] {
			continue
		}
		got_lo, got_hi := false, false
		for p in line.points {
			if int(p.x) == c {
				got_lo ||= p.y == lo[c]
				got_hi ||= p.y == hi[c]
			}
		}
		if !got_lo || !got_hi {
			return fmt.tprintf(
					"column %d of %d lost its extreme (%v..%v), n %d",
					c,
					cols,
					lo[c],
					hi[c],
					n,
				),
				false
		}
	}
	return "", true
}

box_stats :: proc(_: Subject, src: ^harness.Source) -> (string, bool) {
	n := harness.integer_in(src, 0, 60)
	samples := make([]f64, n, context.temp_allocator)
	scale := math.pow(10, f64(harness.integer_in(src, -3, 6)))
	for &s in samples {
		s = f64(harness.integer_in(src, -1000, 1000)) * scale
		if harness.integer_in(src, 0, 20) == 0 {
			s = harness.real(src)
		}
	}
	b := plot.box_stats(samples, context.temp_allocator)
	where_ := fmt.tprintf("box_stats(%v) = %v", samples, b)
	if b.count == 0 {
		return "", true
	}
	// A whisker may end inside the box: when the sample a quartile is
	// interpolated from is an outlier, the nearest one inside the fence
	// lies past the quartile. The chart then draws no whisker on that side.
	ordered := b.min <= b.q1 && b.q1 <= b.median && b.median <= b.q3 && b.q3 <= b.max
	ordered &&= b.min <= b.whisker_lo && b.whisker_lo <= b.whisker_hi && b.whisker_hi <= b.max
	if !ordered {
		return fmt.tprint(where_, ": not ordered"), false
	}
	for o in b.outliers {
		if o >= b.whisker_lo && o <= b.whisker_hi {
			return fmt.tprint(where_, ": an outlier inside the whiskers"), false
		}
	}
	return "", true
}

stack :: proc(_: Subject, src: ^harness.Source) -> (string, bool) {
	n := harness.integer_in(src, 0, 12)
	values := make([]f64, n, context.temp_allocator)
	lo := make([]f64, n, context.temp_allocator)
	hi := make([]f64, n, context.temp_allocator)
	shown: plot.Series_Set
	for i in 0 ..< n {
		values[i] = f64(harness.integer_in(src, -50, 51))
		if harness.integer_in(src, 0, 8) == 0 {
			values[i] = math.nan_f64()
		}
		if harness.integer_in(src, 0, 5) != 0 {
			shown += {i}
		}
	}
	plot.stack_bounds(values, shown, lo, hi)
	up, down: f64
	for v, i in values {
		where_ := fmt.tprintf("stack_bounds(%v) = %v..%v at %d", values, lo, hi, i)
		if !(i in shown) || math.is_nan(v) {
			if hi[i] != lo[i] {
				return fmt.tprint(where_, ": a missing value takes room"), false
			}
			continue
		}
		if hi[i] - lo[i] != abs(v) {
			return fmt.tprint(where_, ": the bar is not its value long"), false
		}
		if v >= 0 && lo[i] != up || v < 0 && hi[i] != down {
			return fmt.tprint(where_, ": the bar does not sit on the stack"), false
		}
		if v >= 0 {
			up = hi[i]
		} else {
			down = lo[i]
		}
	}
	return "", true
}
