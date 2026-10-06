package plot

import "core:math"
import "jm:ui/ops"

// Axis is a value axis: how its numbers are written, its scale, and what
// its domain must reach beyond the data (a percentage chart that should
// start at 80 whatever the data says). title names the axis above it.
Axis :: struct {
	title:  string,
	format: Number_Format,
	scale:  Scale_Kind,
	min:    Maybe(f64), // the domain reaches down at least to this
	max:    Maybe(f64), // and up at least to this
	zero:   bool, // the domain reaches zero, as a bar's or an area's must
}

// Extent is the least and greatest of some values, empty until one is
// added.
Extent :: struct {
	lo, hi: f64,
}

EMPTY_EXTENT :: Extent{math.INF_F64, math.NEG_INF_F64}

// extent_add widens e to v, when v is a number.
extent_add :: proc(e: ^Extent, v: f64) {
	if is_finite(v) {
		e.lo, e.hi = min(e.lo, v), max(e.hi, v)
	}
}

// Value_Axis is a laid-out value axis: its scale, ticks and their labels.
@(private)
Value_Axis :: struct {
	axis:  Axis,
	scale: Scale,
	ticks: Tick_List,
	runs:  [MAX_TICKS]Run,
	width: f32, // the widest label
}

// TICK_PITCH is the least room a value axis gives each tick, in tick label
// heights.
@(private)
TICK_PITCH :: 3.2

// value_axis lays out a over the data in e, along length units: the domain
// widened to nice ends, at most a tick each pitch units (TICK_PITCH tick
// label heights when 0), and their labels.
@(private)
value_axis :: proc(f: ^Frame, a: Axis, e: Extent, length: f32, pitch: f32 = 0) -> (v: Value_Axis) {
	v.axis = a
	lo, hi := e.lo, e.hi
	if m, ok := a.min.?; ok {
		lo = min(lo, m)
	}
	if m, ok := a.max.?; ok {
		hi = max(hi, m)
	}
	if a.zero && a.scale == .Linear {
		lo, hi = min(lo, 0), max(hi, 0)
	}
	if lo > hi {
		lo, hi = 0, 1
	}
	room := pitch if pitch > 0 else f.style.tick_size * TICK_PITCH
	want := clamp(int(length / room), 2, 10)
	if a.scale == .Log {
		lo, hi = decades(lo, hi)
		v.ticks = log_ticks(lo, hi, want)
	} else {
		lo, hi, v.ticks = fit_linear(lo, hi, want)
	}
	v.scale = {
		kind = a.scale,
		d0   = lo,
		d1   = hi,
	}
	value_labels(f, &v)
	return
}

// decades widens [lo, hi] to whole decades for a log axis, at least one;
// a domain that does not reach above zero is the first decade.
@(private)
decades :: proc(lo, hi: f64) -> (f64, f64) {
	bottom := lo if lo > 0 else 1
	top := max(hi, bottom)
	a, b := math.pow(10, math.floor(math.log10(bottom))), math.pow(10, math.ceil(math.log10(top)))
	if a == b {
		b = a * 10
	}
	return a, b
}

// value_labels shapes v's tick labels.
@(private)
value_labels :: proc(f: ^Frame, v: ^Value_Axis) {
	ts := ticks_of(&v.ticks)
	mag: f64
	for t in ts {
		mag = max(mag, abs(t))
	}
	af := axis_format(v.axis.format, v.ticks.step, mag)
	for t, i in ts {
		l := format_tick(v.axis.format, af, t)
		if v.axis.scale == .Log {
			l = format_log_tick(v.axis.format, t)
		}
		v.runs[i] = shape_run(f.gtx, label_text(&l), f.style.tick_size, f.style.font)
		v.width = max(v.width, v.runs[i].width)
	}
}

// Side is which side of the plot a value axis sits on.
@(private)
Axis_Side :: enum u8 {
	Left,
	Right,
	Bottom, // a horizontal bar chart's value axis
}

// draw_value_axis draws v's labels on side of the plot and, for the main
// axis, a gridline at each tick and the zero line.
@(private)
draw_value_axis :: proc(f: ^Frame, v: ^Value_Axis, side: Axis_Side, grid: bool) {
	gtx, s, p := f.gtx, f.style, f.plot
	for t, i in ticks_of(&v.ticks) {
		at := scale_to(v.scale, t)
		r := v.runs[i]
		switch side {
		case .Left:
			draw_run(gtx, r, {p.x - 8 - r.width, at - run_height(r) / 2}, s.muted)
		case .Right:
			draw_run(gtx, r, {p.x + p.w + 8, at - run_height(r) / 2}, s.muted)
		case .Bottom:
			draw_run(
				gtx,
				r,
				{clamp(at - r.width / 2, 0, f.size.x - r.width), p.y + p.h + 6},
				s.muted,
			)
		}
		if !grid {
			continue
		}
		color := s.axis if t == 0 else s.grid
		if side == .Bottom {
			vline(gtx, at, p.y, p.y + p.h, color)
		} else {
			hairline(gtx, p.x, p.x + p.w, at, color)
		}
	}
}

// draw_axis_title draws a value axis's title above it, keyed with slot's
// draw_swatch when the chart has two value axes, so the reader can tell which
// series reads against which. It returns the height it took.
@(private)
draw_axis_title :: proc(f: ^Frame, title: string, x, y: f32, right: bool, slot: int) -> f32 {
	if title == "" {
		return 0
	}
	s := f.style
	r := shape_fit(f.gtx, title, s.tick_size, s.font, f.size.x / 2)
	key: f32 = SWATCH + 4 if slot >= 0 else 0
	at := x - r.width - key if right else x
	if slot >= 0 {
		draw_swatch(
			f.gtx,
			s,
			slot,
			.Line,
			{at, y + run_height(r) / 2 - SWATCH / 2, SWATCH, SWATCH},
		)
	}
	draw_run(f.gtx, r, {at + key, y}, s.muted)
	return run_height(r) + 6
}

// X_Kind is what a line chart's x values are.
X_Kind :: enum u8 {
	Number,
	Time, // seconds since 1970 UTC, ticked on zone's calendar
}

// X_Axis is a line chart's horizontal axis.
X_Axis :: struct {
	title:  string,
	kind:   X_Kind,
	format: Number_Format, // a number axis's labels
	zone:   Zone, // a time axis's calendar
}

// X_Layout is a laid-out horizontal axis of numbers or times.
@(private)
X_Layout :: struct {
	axis:  X_Axis,
	scale: Scale,
	ticks: Time_Ticks, // a number axis uses only its Tick_List
	main:  [MAX_TICKS]Run,
	sub:   [MAX_TICKS]Run, // a time tick's context line, where it has one
	subs:  bool, // some tick has one, so the axis is two lines tall
}

// LABEL_GAP is the least room between neighbouring tick labels.
@(private)
LABEL_GAP :: 12

// x_layout lays out a over [lo, hi] along width: as many ticks as fit
// with their labels LABEL_GAP apart, found by asking for fewer until they
// do. left and right are the chart's room either side of the plot, where
// a label at the plot's end may reach.
@(private)
x_layout :: proc(f: ^Frame, a: X_Axis, lo, hi: f64, width, left, right: f32) -> (x: X_Layout) {
	x.axis = a
	x.scale = {
		kind = .Linear,
		d0   = lo,
		d1   = hi,
		r1   = width,
	}
	want := clamp(int(width / 64), 2, 12)
	for _ in 0 ..< 8 {
		x_ticks(f, &x, lo, hi, want)
		if x_fits(&x, -left, width + right) || want <= 2 {
			return
		}
		want -= 1
	}
	return
}

// x_ticks makes x's ticks and labels for at most want ticks.
@(private)
x_ticks :: proc(f: ^Frame, x: ^X_Layout, lo, hi: f64, want: int) {
	s := f.style
	x.subs = false
	if x.axis.kind == .Time {
		x.ticks = time_ticks(lo, hi, want, x.axis.zone)
		for i in 0 ..< x.ticks.n {
			l := time_label(&x.ticks, i, x.axis.zone)
			x.main[i] = shape_run(f.gtx, label_text(&l.main), s.tick_size, s.font)
			x.sub[i] = shape_run(f.gtx, label_text(&l.sub), s.tick_size, s.font)
			x.subs ||= l.sub.n > 0
		}
		return
	}
	x.ticks = {
		list = linear_ticks(lo, hi, want),
	}
	mag: f64
	for t in ticks_of(&x.ticks) {
		mag = max(mag, abs(t))
	}
	af := axis_format(x.axis.format, x.ticks.step, mag)
	for t, i in ticks_of(&x.ticks) {
		l := format_tick(x.axis.format, af, t)
		x.main[i] = shape_run(f.gtx, label_text(&l), s.tick_size, s.font)
		x.sub[i] = {}
	}
}

// x_fits reports whether x's labels, centred on their ticks and kept
// inside [lo, hi] as draw_x_axis keeps them inside the chart, clear each
// other by LABEL_GAP.
@(private)
x_fits :: proc(x: ^X_Layout, lo, hi: f32) -> bool {
	prev := lo - LABEL_GAP
	for i in 0 ..< x.ticks.n {
		w := max(x.main[i].width, x.sub[i].width)
		at := clamp(scale_to(x.scale, x.ticks.v[i]) - w / 2, lo, hi - w)
		if at < prev + LABEL_GAP {
			return false
		}
		prev = at + w
	}
	return true
}

// x_height is how tall x's labels stand under the plot.
@(private)
x_height :: proc(f: ^Frame, x: ^X_Layout) -> f32 {
	line := f.style.tick_size * 1.3
	return 6 + line * (2 if x.subs else 1)
}

// draw_x_axis draws x's labels under the plot, each centred on its tick
// and kept inside the chart, with a short tick mark, and the baseline.
@(private)
draw_x_axis :: proc(f: ^Frame, x: ^X_Layout) {
	gtx, s, p := f.gtx, f.style, f.plot
	line := s.tick_size * 1.3
	for i in 0 ..< x.ticks.n {
		at := scale_to(x.scale, x.ticks.v[i])
		vline(gtx, at, p.y + p.h, p.y + p.h + 4, s.axis)
		m, sub := x.main[i], x.sub[i]
		draw_run(gtx, m, {clamp(at - m.width / 2, 0, f.size.x - m.width), p.y + p.h + 6}, s.muted)
		if sub.width > 0 {
			draw_run(
				gtx,
				sub,
				{clamp(at - sub.width / 2, 0, f.size.x - sub.width), p.y + p.h + 6 + line},
				s.muted,
			)
		}
	}
	hairline(gtx, p.x, p.x + p.w, p.y + p.h, s.axis)
}

// Band_Layout is a laid-out categorical axis: the bands and each
// category's label, and how the labels were made to fit.
@(private)
Band_Layout :: struct {
	band:   Band,
	runs:   []Run,
	rotate: bool, // the labels are turned 45 degrees to fit
	every:  int, // only every this many labels is drawn, where even turned they collide
	height: f32, // how much room the labels take below (or beside) the plot
}

// ROTATED_MAX is the longest a turned category label is drawn.
@(private)
ROTATED_MAX :: 120

// band_layout lays out categories along length: level labels where they
// fit their band, else turned 45 degrees and cut to ROTATED_MAX, else
// every second, third, ... one. across is how long a label may be for an
// axis whose labels run across the bands (a horizontal bar chart's), 0
// for one along them.
@(private)
band_layout :: proc(f: ^Frame, categories: []string, length, across: f32) -> (b: Band_Layout) {
	s := f.style
	b.band = {
		n     = len(categories),
		r1    = length,
		inner = 0.2,
		outer = 0.1,
	}
	b.runs = make([]Run, len(categories), f.gtx.allocator)
	step := band_step(b.band)
	line := s.tick_size * 1.3
	b.every = 1
	widest: f32
	for c, i in categories {
		limit := across if across > 0 else max(step - 4, 0)
		b.runs[i] = shape_fit(f.gtx, c, s.tick_size, s.font, ROTATED_MAX if across == 0 else limit)
		widest = max(widest, b.runs[i].width)
	}
	if across > 0 {
		b.every = max(int(math.ceil(f64(line / max(step, 1)))), 1)
		b.height = widest + 8
		return
	}
	b.height = 6 + line
	if widest <= step - 4 {
		return
	}
	b.rotate = true
	b.every = max(int(math.ceil(f64(line * 1.2 / max(step, 1)))), 1)
	b.height = 6 + widest * 0.7071 + line * 0.7071
	return
}

// draw_bands_below draws b's labels under the plot, centred on their
// bands or turned to end at them.
@(private)
draw_bands_below :: proc(f: ^Frame, b: ^Band_Layout) {
	gtx, s, p := f.gtx, f.style, f.plot
	for r, i in b.runs {
		if i % b.every != 0 {
			continue
		}
		at := p.x + band_center(b.band, i)
		if !b.rotate {
			draw_run(gtx, r, {at - r.width / 2, p.y + p.h + 6}, s.muted)
			continue
		}
		// Turned about the label's end, which sits under the band.
		ops.transform_push(
			gtx.scene,
			ops.mul(ops.translate(at, p.y + p.h + 6), ops.rotate(-math.PI / 4)),
		)
		draw_run(gtx, r, {-r.width, -run_height(r) / 2}, s.muted)
		ops.transform_pop(gtx.scene)
	}
	hairline(gtx, p.x, p.x + p.w, p.y + p.h, s.axis)
}

// draw_bands_left draws b's labels left of the plot, beside their bands.
@(private)
draw_bands_left :: proc(f: ^Frame, b: ^Band_Layout) {
	gtx, s, p := f.gtx, f.style, f.plot
	for r, i in b.runs {
		if i % b.every != 0 {
			continue
		}
		at := p.y + band_center(b.band, i)
		draw_run(gtx, r, {p.x - 8 - r.width, at - run_height(r) / 2}, s.muted)
	}
	vline(gtx, p.x, p.y, p.y + p.h, s.axis)
}
