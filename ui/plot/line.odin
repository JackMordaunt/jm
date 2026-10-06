package plot

import "core:fmt"
import "core:math"
import "jm:ui"
import "jm:ui/ops"

// Fill is what a line chart fills under its lines.
Fill :: enum u8 {
	None,
	Area, // each series filled down to zero, a wash of its colour
	Stacked, // each series stacked on those before it, filled between
}

// Line_Series is one line: a value per x (NaN where there is none, which
// breaks the line), the axis it reads against, and its palette slot.
Line_Series :: struct {
	name:  string,
	ys:    []f64,
	right: bool, // reads against the chart's second axis, y2
	slot:  Maybe(int), // its colour; nil takes its index, so a hidden series never repaints another
}

// Line_Chart is a line chart: series over shared, ascending xs. It is an
// area chart with fill, and steps between points with step.
Line_Chart :: struct {
	using chart: Chart,
	x:           X_Axis,
	y:           Axis,
	y2:          Axis, // the axis series with right read against, drawn on the right
	xs:          []f64,
	series:      []Line_Series,
	fill:        Fill,
	step:        Step,
}

// line_chart draws c in style: a legend that toggles series, value and x
// axes with ticks that fit, the lines min/max-decimated to the pixel
// columns they cross, and a crosshair over the nearest x with a tooltip
// listing every series there. The plot takes focus: Left and Right walk
// the points, Up and Down the series, and a screen reader hears each
// point as the keyboard reaches it.
line_chart :: proc(
	gtx: ^ui.Ctx,
	c: ^Line_Chart,
	style: ^Plot_Style,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	f := frame_open(gtx, &c.chart, style, key, loc)
	entries := make([]Entry, len(c.series), gtx.allocator)
	for s, i in c.series {
		entries[i] = {s.name, line_slot(s, i), .Rect if c.fill != .None else .Line}
	}
	f.top = legend(&f, entries)
	l: Line_Layout
	l.chart = c
	if !show_status(&f, line_extents(&f, &l)) {
		return frame_close(&f)
	}
	line_layout(&f, &l)
	read_plot_events(&f, {len(c.xs), len(c.series)})
	line_draw(&f, &l)
	summary := line_summary(&f, &l)
	plot_listen(&f)
	plot_semantics(&f, summary)
	return frame_close(&f)
}

@(private)
line_slot :: proc(s: Line_Series, i: int) -> int {
	return s.slot.? or_else i
}

// Line_Layout is a line chart laid out: its data's extents and axes.
@(private)
Line_Layout :: struct {
	chart:       ^Line_Chart,
	x_lo, x_hi:  f64,
	first, last: int, // the first and last xs that are numbers
	left, right: Extent,
	dual:        bool, // some shown series reads against y2
	x:           X_Layout,
	y, y2:       Value_Axis,
}

// line_extents finds the data's extents over the shown series, and
// whether there is anything to draw.
@(private)
line_extents :: proc(f: ^Frame, l: ^Line_Layout) -> bool {
	c := l.chart
	l.left, l.right = EMPTY_EXTENT, EMPTY_EXTENT
	l.first, l.last = -1, -1
	for x, i in c.xs {
		if is_finite(x) {
			l.first = i if l.first < 0 else l.first
			l.last = i
		}
	}
	if l.first < 0 {
		return false
	}
	l.x_lo, l.x_hi = c.xs[l.first], c.xs[l.last]
	for s, si in c.series {
		if !shown(f, si) {
			continue
		}
		e := &l.right if s.right && c.fill != .Stacked else &l.left
		l.dual ||= s.right && c.fill != .Stacked
		for i in l.first ..= l.last {
			extent_add(e, value_at(f, c, si, i))
		}
	}
	return l.left.lo <= l.left.hi || l.right.lo <= l.right.hi
}

// value_at is series s's value at i as drawn: its own, or the top of its
// stack when stacked, where a missing value below it counts as zero.
@(private)
value_at :: proc(f: ^Frame, c: ^Line_Chart, s, i: int) -> f64 {
	ys := c.series[s].ys
	v := ys[i] if i < len(ys) else math.nan_f64()
	if c.fill != .Stacked || !is_finite(v) {
		return v
	}
	return v + stack_below(f, c, s, i)
}

// stack_below is the sum of the shown series stacked under s at i.
@(private)
stack_below :: proc(f: ^Frame, c: ^Line_Chart, s, i: int) -> (sum: f64) {
	for j in 0 ..< s {
		ys := c.series[j].ys
		if shown(f, j) && i < len(ys) && is_finite(ys[i]) {
			sum += ys[i]
		}
	}
	return
}

// line_layout fits the axes around the plot: titles on top, the value
// axes' labels either side and the x axis's under it.
@(private)
line_layout :: proc(f: ^Frame, l: ^Line_Layout) {
	c := l.chart
	y_axis := c.y
	if c.fill != .None {
		y_axis.zero = true
	}
	titles := max(
		axis_title_height(f, c.y.title),
		axis_title_height(f, c.y2.title) if l.dual else 0,
	)
	top := f.top + titles + f.style.tick_size / 2
	guess := f.style.tick_size * 1.3 * (2 if c.x.kind == .Time else 1) + 6
	height := f.size.y - top - guess
	l.y = value_axis(f, y_axis, l.left, height)
	if l.dual {
		l.y2 = value_axis(f, c.y2, l.right, height)
	}
	left := l.y.width + 10
	right := l.y2.width + 10 if l.dual else 16
	width := max(f.size.x - left - right, 1)
	l.x = x_layout(f, c.x, l.x_lo, l.x_hi, width, left, right)
	height = max(f.size.y - top - x_height(f, &l.x), 1)
	f.plot = {left, top, width, height}
	l.x.scale.r0, l.x.scale.r1 = f.plot.x, f.plot.x + width
	place_value(&l.y, f.plot)
	place_value(&l.y2, f.plot)
}

// place_value maps a vertical value axis onto the plot's height.
@(private)
place_value :: proc(v: ^Value_Axis, p: ops.Rect) {
	v.scale.r0, v.scale.r1 = p.y + p.h, p.y
}

@(private)
axis_title_height :: proc(f: ^Frame, title: string) -> f32 {
	return f.style.tick_size * 1.3 + 6 if title != "" else 0
}

// line_draw draws the axes, the series, and the readout where the pointer
// or keyboard is.
@(private)
line_draw :: proc(f: ^Frame, l: ^Line_Layout) {
	c, p := l.chart, f.plot
	draw_value_axis(f, &l.y, .Left, true)
	if l.dual {
		draw_value_axis(f, &l.y2, .Right, false)
	}
	titles_y := f.top
	draw_axis_title(f, c.y.title, 0, titles_y, false, first_on(f, c, false) if l.dual else -1)
	if l.dual {
		draw_axis_title(f, c.y2.title, f.size.x, titles_y, true, first_on(f, c, true))
	}
	draw_x_axis(f, &l.x)
	ops.clip_push(f.gtx.scene, grow(p, f.style.line_width))
	if c.fill != .None {
		for s in 0 ..< len(c.series) {
			if shown(f, s) {
				series_fill(f, l, s)
			}
		}
	}
	for s in 0 ..< len(c.series) {
		if shown(f, s) {
			series_line(f, l, s)
		}
	}
	ops.clip_pop(f.gtx.scene)
	line_readout(f, l)
}

// first_on is the first shown series on the right axis (or the left),
// whose key labels that axis's title; -1 for none.
@(private)
first_on :: proc(f: ^Frame, c: ^Line_Chart, right: bool) -> int {
	for s, i in c.series {
		if shown(f, i) && s.right == right {
			return line_slot(s, i)
		}
	}
	return -1
}

// y_scale is the scale series s reads against.
@(private)
y_scale :: proc(l: ^Line_Layout, s: int) -> Scale {
	c := l.chart
	return l.y2.scale if c.series[s].right && c.fill != .Stacked && l.dual else l.y.scale
}

// trace decimates a value of every x from first to last into a polyline
// on the frame allocator: below is the stack under s rather than s's own
// top, for the lower edge of a stacked band.
@(private)
trace :: proc(f: ^Frame, l: ^Line_Layout, s: int, lo, hi: int, below := false) -> ^Polyline {
	c := l.chart
	poly := new(Polyline, f.gtx.allocator)
	room := min(hi - lo + 1, 4 * int(f.plot.w) + 8) * (3 if c.step != .None else 1)
	poly.points = make([dynamic]ops.Point, 0, room, f.gtx.allocator)
	poly.starts = make([dynamic]int, 0, 8, f.gtx.allocator)
	poly.step = c.step
	r := Reducer {
		out = poly,
	}
	ys := y_scale(l, s)
	for i in lo ..= hi {
		v := stack_below(f, c, s, i) if below else value_at(f, c, s, i)
		y := scale_to(ys, v)
		if math.is_nan(y) || !is_finite(c.xs[i]) {
			reduce_break(&r)
			continue
		}
		reduce_push(&r, {scale_to(l.x.scale, c.xs[i]), y}, i)
	}
	reduce_flush(&r)
	return poly
}

// series_line strokes series s, dashed where its look asks.
@(private)
series_line :: proc(f: ^Frame, l: ^Line_Layout, s: int) {
	poly := trace(f, l, s, l.first, l.last)
	lk := look(f.style, line_slot(l.chart.series[s], s))
	path := polyline_path(f.gtx, poly, lk.dash)
	style := ops.Stroke_Style {
		width = f.style.line_width,
		cap   = .Round,
		join  = .Round,
	}
	if lk.dash != {} {
		style.cap = .Butt
	}
	ops.stroke(f.gtx.scene, path, lk.color, style)
	if len(poly.points) == 1 || runs_of_one(poly) {
		// A point with no neighbour draws no line, so it gets a marker.
		for k in 0 ..< len(poly.starts) {
			run := polyline_run(poly, k)
			if len(run) == 1 {
				draw_marker(
					f.gtx,
					lk.marker,
					run[0],
					f.style.line_width + 1,
					lk.color,
					f.style.background,
				)
			}
		}
	}
}

@(private)
runs_of_one :: proc(poly: ^Polyline) -> bool {
	for k in 0 ..< len(poly.starts) {
		if len(polyline_run(poly, k)) == 1 {
			return true
		}
	}
	return false
}

// series_fill fills under series s: down to zero, or between it and the
// stack under it, a run at a time so a gap stays open.
@(private)
series_fill :: proc(f: ^Frame, l: ^Line_Layout, s: int) {
	c := l.chart
	lk := look(f.style, line_slot(c.series[s], s))
	color := ops.with_alpha(lk.color, f.style.area_alpha if c.fill == .Area else 0.55)
	base := clamp(scale_to(l.y.scale, 0), f.plot.y, f.plot.y + f.plot.h)
	if math.is_nan(base) {
		base = f.plot.y + f.plot.h
	}
	ys := c.series[s].ys
	for i := l.first; i <= l.last; {
		start, end := next_run(ys, i, l.last)
		if end >= start {
			band_fill(f, l, s, start, end, base, color)
		}
		i = end + 1
	}
}

// next_run is the next run of numbers in ys at or after from, up to last:
// its first and last index, or an empty run (end < start) past last when
// there are none.
@(private)
next_run :: proc(ys: []f64, from, last: int) -> (start, end: int) {
	has :: proc(ys: []f64, i: int) -> bool {return i < len(ys) && is_finite(ys[i])}
	start = from
	for start <= last && !has(ys, start) {
		start += 1
	}
	end = start
	for end + 1 <= last && has(ys, end + 1) {
		end += 1
	}
	if start > last {
		return last + 1, last
	}
	return
}

// band_fill fills series s's band from lo to hi: under its line down to
// base, or down to the stack under it.
@(private)
band_fill :: proc(f: ^Frame, l: ^Line_Layout, s, lo, hi: int, base: f32, color: ops.Color) {
	top := trace(f, l, s, lo, hi)
	pts := make([dynamic]ops.Point, 0, len(top.points) * 2 + 2, f.gtx.allocator)
	append(&pts, ..top.points[:])
	if l.chart.fill == .Stacked {
		under := trace(f, l, s, lo, hi, below = true)
		#reverse for p in under.points {
			append(&pts, p)
		}
	} else if len(top.points) > 0 {
		append(
			&pts,
			ops.Point{top.points[len(top.points) - 1].x, base},
			ops.Point{top.points[0].x, base},
		)
	}
	ops.fill(f.gtx.scene, ui.polygon(f.gtx, pts[:]), color)
}

// polyline_path is poly as a path of one subpath a run, or of one a dash
// where dash is set.
@(private)
polyline_path :: proc(gtx: ^ui.Ctx, poly: ^Polyline, dash: [2]f32) -> ops.Path_Ref {
	if dash != {} {
		return dashed_path(gtx, poly, dash)
	}
	verbs := make([]ops.Path_Verb, len(poly.points), gtx.allocator)
	for i in 0 ..< len(verbs) {
		verbs[i] = .Line
	}
	for k in poly.starts {
		verbs[k] = .Move
	}
	return {ops.add_path(gtx.scene, {verbs = verbs, points = poly.points[:]})}
}

// dashed_path is poly cut into dashes of dash[0] with dash[1] between,
// the pattern running on across a run's corners.
@(private)
dashed_path :: proc(gtx: ^ui.Ctx, poly: ^Polyline, dash: [2]f32) -> ops.Path_Ref {
	verbs := make([dynamic]ops.Path_Verb, 0, len(poly.points) * 2, gtx.allocator)
	pts := make([dynamic]ops.Point, 0, len(poly.points) * 2, gtx.allocator)
	period := max(dash[0] + dash[1], 1)
	for k in 0 ..< len(poly.starts) {
		run := polyline_run(poly, k)
		at: f32 // how far into the pattern the pen is
		for i in 1 ..< len(run) {
			dash_segment(&verbs, &pts, run[i - 1], run[i], dash[0], period, &at)
		}
	}
	return {ops.add_path(gtx.scene, {verbs = verbs[:], points = pts[:]})}
}

// dash_segment adds the dashes of the segment a to b, the pattern at at.
@(private)
dash_segment :: proc(
	verbs: ^[dynamic]ops.Path_Verb,
	pts: ^[dynamic]ops.Point,
	a, b: ops.Point,
	on, period: f32,
	at: ^f32,
) {
	d := b - a
	length := math.sqrt(d.x * d.x + d.y * d.y)
	if length == 0 {
		return
	}
	t: f32
	for t < length {
		phase := math.mod(at^, period)
		run := (on - phase) if phase < on else (period - phase)
		end := min(t + run, length)
		if phase < on {
			append(verbs, ops.Path_Verb.Move, ops.Path_Verb.Line)
			append(pts, a + d * (t / length), a + d * (end / length))
		}
		at^ += end - t
		t = end
	}
}

// nearest is the index of the x in xs[first..last] nearest v.
@(private)
nearest :: proc(xs: []f64, first, last: int, v: f64) -> int {
	lo, hi := first, last
	for lo < hi {
		mid := (lo + hi) / 2
		if xs[mid] < v {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	if lo > first && abs(xs[lo - 1] - v) <= abs(xs[lo] - v) {
		return lo - 1
	}
	return lo
}

// line_readout draws the crosshair, the markers and the tooltip at the
// x the pointer or keyboard is on.
@(private)
line_readout :: proc(f: ^Frame, l: ^Line_Layout) {
	c := l.chart
	i: int
	switch active(f) {
	case .None:
		return
	case .Pointer:
		i = nearest(c.xs, l.first, l.last, scale_from(l.x.scale, f.st.pointer.x))
	case .Keyboard:
		i = clamp(f.st.index, l.first, l.last)
	}
	f.st.index = i
	x := scale_to(l.x.scale, c.xs[i])
	vline(f.gtx, x, f.plot.y, f.plot.y + f.plot.h, f.style.crosshair)
	tip: Tip
	tip.heading = x_value(l, c.xs[i])
	for s in 0 ..< len(c.series) {
		if shown(f, s) {
			line_point(f, l, s, i, &tip)
		}
	}
	keyed := active(f) == .Keyboard
	if keyed {
		line_point_semantics(f, l, i, x)
	}
	anchor := ops.Rect{x - 1, f.plot.y + f.plot.h / 2 - 1, 2, 2}
	tooltip(f, &tip, anchor)
}

// line_point marks series s at i and adds its row to the tooltip.
@(private)
line_point :: proc(f: ^Frame, l: ^Line_Layout, s, i: int, tip: ^Tip) {
	c := l.chart
	ser := c.series[s]
	raw := ser.ys[i] if i < len(ser.ys) else math.nan_f64()
	axis := c.y2 if ser.right && l.dual else c.y
	focus := f.st.keyed && f.st.series == s
	tip_add(
		tip,
		{
			slot = line_slot(ser, s),
			value = format_value(axis.format, raw),
			name = ser.name,
			focus = focus,
		},
	)
	y := scale_to(y_scale(l, s), value_at(f, c, s, i))
	if math.is_nan(y) {
		return
	}
	lk := look(f.style, line_slot(ser, s))
	r := f.style.marker_size + (1.5 if focus else 0)
	draw_marker(
		f.gtx,
		lk.marker,
		{scale_to(l.x.scale, c.xs[i]), y},
		r,
		lk.color,
		f.style.background,
	)
}

// x_value writes x as the tooltip's heading.
@(private)
x_value :: proc(l: ^Line_Layout, x: f64) -> Label {
	c := l.chart
	if c.x.kind == .Time {
		spacing := (l.x_hi - l.x_lo) / f64(max(l.last - l.first, 1))
		return time_value(x, spacing, c.x.zone)
	}
	return format_value(c.x.format, x)
}

// line_point_semantics names the point the keyboard is on for a screen
// reader: its series, x and value.
@(private)
line_point_semantics :: proc(f: ^Frame, l: ^Line_Layout, i: int, x: f32) {
	c := l.chart
	s := clamp(f.st.series, 0, len(c.series) - 1)
	ser := c.series[s]
	h := x_value(l, c.xs[i])
	axis := c.y2 if ser.right && l.dual else c.y
	v := format_value(axis.format, ser.ys[i] if i < len(ser.ys) else math.nan_f64())
	label := fmt.aprintf(
		"%s, %s: %s",
		ser.name,
		label_text(&h),
		label_text(&v),
		allocator = f.gtx.allocator,
	)
	point_semantics(f, label, {x - 4, f.plot.y, 8, f.plot.h})
}

// line_summary is what a screen reader hears of the whole chart: how many
// series, the span of x and the range of values.
@(private)
line_summary :: proc(f: ^Frame, l: ^Line_Layout) -> string {
	c := l.chart
	n := 0
	for _, i in c.series {
		n += 1 if shown(f, i) else 0
	}
	a, b := x_value(l, l.x_lo), x_value(l, l.x_hi)
	lo, hi := format_value(c.y.format, l.left.lo), format_value(c.y.format, l.left.hi)
	return fmt.aprintf(
		"Line chart, %d of %d series shown, %s to %s, values %s to %s",
		n,
		len(c.series),
		label_text(&a),
		label_text(&b),
		label_text(&lo),
		label_text(&hi),
		allocator = f.gtx.allocator,
	)
}
