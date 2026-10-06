package plot

import "core:fmt"
import "core:math"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// Bar_Series is one series of bars: a value per category, NaN for none.
Bar_Series :: struct {
	name:   string,
	values: []f64,
	slot:   Maybe(int), // its colour; nil takes its index
}

// Bar_Chart is a bar chart: series of values over categories, side by
// side or stacked, standing up or lying along.
Bar_Chart :: struct {
	using chart: Chart,
	categories:  []string,
	series:      []Bar_Series,
	value:       Axis,
	horizontal:  bool, // categories down the left, bars running right
	stacked:     bool, // a category's series stack, positives up from zero and negatives down
}

// bar_chart draws c in style: grouped or stacked bars from a zero
// baseline, rounded only at their data ends, a surface gap between bars
// that touch, the category labels turned or thinned when crowded, and a
// tooltip over the category the pointer or keyboard is on listing every
// series in it. The plot takes focus: Left and Right walk the categories,
// Up and Down the series.
bar_chart :: proc(gtx: ^ui.Ctx, c: ^Bar_Chart, style: ^Plot_Style, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	f := frame_open(gtx, &c.chart, style, key, loc)
	entries := make([]Entry, len(c.series), gtx.allocator)
	for s, i in c.series {
		entries[i] = {s.name, bar_slot(s, i), .Rect}
	}
	f.top = legend(&f, entries)
	l := Cat_Layout{horizontal = c.horizontal}
	e := bar_extent(&f, c, &l)
	if !show_status(&f, l.shown > 0 && e.lo <= e.hi && len(c.categories) > 0) {
		return frame_close(&f)
	}
	a := c.value
	a.zero = true
	cat_layout(&f, &l, c.categories, a, e)
	read_plot_events(&f, {len(c.categories), len(c.series)})
	at := cat_active(&f, &l)
	if at >= 0 {
		ops.fill(gtx.scene, band_rect(&f, &l, at), style.hover)
	}
	cat_draw_axes(&f, &l, c.value)
	for i in 0 ..< len(c.categories) {
		draw_bar_category(&f, c, &l, i)
	}
	if at >= 0 {
		bar_readout(&f, c, &l, at)
	}
	summary := cat_summary(&f, "Bar chart", &l, len(c.series), c.value, e)
	plot_listen(&f)
	plot_semantics(&f, summary)
	return frame_close(&f)
}

@(private)
bar_slot :: proc(s: Bar_Series, i: int) -> int {
	return s.slot.? or_else i
}

// bar_value is series s's value in category i, NaN where it has none.
@(private)
bar_value :: proc(c: ^Bar_Chart, s, i: int) -> f64 {
	vs := c.series[s].values
	return vs[i] if i < len(vs) else math.nan_f64()
}

// bar_extent is the extent of the bars the shown series draw: their
// values, or their stacks' ends.
@(private)
bar_extent :: proc(f: ^Frame, c: ^Bar_Chart, l: ^Cat_Layout) -> Extent {
	e := EMPTY_EXTENT
	for s in 0 ..< len(c.series) {
		l.shown += 1 if shown(f, s) else 0
	}
	for i in 0 ..< len(c.categories) {
		lo, hi := bar_stack(f, c, i)
		for s in 0 ..< len(c.series) {
			if shown(f, s) {
				extent_add(&e, lo[s] if c.stacked else bar_value(c, s, i))
				extent_add(&e, hi[s] if c.stacked else bar_value(c, s, i))
			}
		}
	}
	return e
}

// bar_stack is category i's stacked bounds per series, on the frame
// allocator.
@(private)
bar_stack :: proc(f: ^Frame, c: ^Bar_Chart, i: int) -> (lo, hi: []f64) {
	n := min(len(c.series), MAX_SERIES)
	values := make([]f64, n, f.gtx.allocator)
	lo = make([]f64, n, f.gtx.allocator)
	hi = make([]f64, n, f.gtx.allocator)
	for s in 0 ..< n {
		values[s] = bar_value(c, s, i)
	}
	shown_set := ~f.hidden^
	stack_bounds(values, shown_set, lo, hi)
	return
}

// draw_bar_category draws category i's bars.
@(private)
draw_bar_category :: proc(f: ^Frame, c: ^Bar_Chart, l: ^Cat_Layout, i: int) {
	lo, hi := bar_stack(f, c, i)
	k := 0
	for s in 0 ..< len(c.series) {
		v := bar_value(c, s, i)
		if !shown(f, s) || !is_finite(v) {
			k += 1 if shown(f, s) else 0
			continue
		}
		a, b := 0.0, v
		n, slot := l.shown, k
		if c.stacked {
			a, b, n, slot = lo[s], hi[s], 1, 0
		}
		r := bar_rect(f, l, i, slot, n, a, b)
		round := !c.stacked || stack_end(c, f, s, i, v)
		bar_paint(f, l, r, v, round, look(f.style, bar_slot(c.series[s], s)).color)
		k += 1
	}
}

// stack_end reports whether series s's bar in category i ends its stack,
// the only bar there whose data end is rounded.
@(private)
stack_end :: proc(c: ^Bar_Chart, f: ^Frame, s, i: int, v: f64) -> bool {
	for t in s + 1 ..< len(c.series) {
		w := bar_value(c, t, i)
		if shown(f, t) && is_finite(w) && (w >= 0) == (v >= 0) && w != 0 {
			return false
		}
	}
	return true
}

// bar_rect is the bar from value a to b in slot k of n across category
// i's band.
@(private)
bar_rect :: proc(f: ^Frame, l: ^Cat_Layout, i, k, n: int, a, b: f64) -> ops.Rect {
	centre, thick := slot_span(f, l, i, k, n, f.style.bar_max)
	pa, pb := scale_to(l.value.scale, a), scale_to(l.value.scale, b)
	lo, hi := min(pa, pb), max(pa, pb)
	if l.horizontal {
		return {lo, centre - thick / 2, hi - lo, thick}
	}
	return {centre - thick / 2, lo, thick, hi - lo}
}

// bar_paint fills bar r of value v, rounded at its data end when round,
// with a surface gap where a stacked neighbour meets it.
@(private)
bar_paint :: proc(f: ^Frame, l: ^Cat_Layout, r: ops.Rect, v: f64, round: bool, color: ops.Color) {
	g := bar_gap(r, f.style.gap / 2, l.horizontal, v >= 0)
	if g.w <= 0 || g.h <= 0 {
		return
	}
	rad := min(f.style.bar_radius, min(g.w, g.h) / 2) if round else 0
	ops.fill(f.gtx.scene, design.rounded(f.gtx, g, data_end(rad, l.horizontal, v >= 0)), color)
}

// bar_gap takes gap off r's end toward the baseline: a stack's first bar
// sits on the baseline, where the gap reads as the baseline's own line,
// and each bar above it sits gap clear of the one below.
@(private)
bar_gap :: proc(r: ops.Rect, gap: f32, horizontal, up: bool) -> ops.Rect {
	r := r
	switch {
	case horizontal && up:
		r.x, r.w = r.x + gap, r.w - gap
	case horizontal:
		r.w -= gap
	case up:
		r.h -= gap
	case:
		r.y, r.h = r.y + gap, r.h - gap
	}
	return r
}

// data_end is the corners of a bar rounded rad at its data end only: the
// top of a bar up, the bottom of one down, the right of one along.
@(private)
data_end :: proc(rad: f32, horizontal, up: bool) -> design.Corners {
	switch {
	case horizontal && up:
		return {0, rad, rad, 0}
	case horizontal:
		return {rad, 0, 0, rad}
	case up:
		return {rad, rad, 0, 0}
	}
	return {0, 0, rad, rad}
}

// bar_readout draws the tooltip for category i, and rings the bar the
// keyboard is on.
@(private)
bar_readout :: proc(f: ^Frame, c: ^Bar_Chart, l: ^Cat_Layout, i: int) {
	tip: Tip
	put_text(&tip.heading, c.categories[i])
	total: f64
	k := 0
	anchor := band_rect(f, l, i)
	for s in 0 ..< len(c.series) {
		if !shown(f, s) {
			continue
		}
		v := bar_value(c, s, i)
		focus := f.st.keyed && f.st.series == s
		tip_add(&tip, {slot = bar_slot(c.series[s], s), value = format_value(c.value.format, v), name = c.series[s].name, focus = focus})
		total += v if is_finite(v) else 0
		if focus {
			anchor = draw_bar_focus(f, c, l, i, s, k)
		}
		k += 1
	}
	if c.stacked && l.shown > 1 {
		tip_add(&tip, {value = format_value(c.value.format, total), name = "Total", plain = true})
	}
	tooltip(f, &tip, cat_anchor(f, anchor))
}

// draw_bar_focus rings the bar the keyboard is on and names it for a screen
// reader, returning where it is.
@(private)
draw_bar_focus :: proc(f: ^Frame, c: ^Bar_Chart, l: ^Cat_Layout, i, s, k: int) -> ops.Rect {
	v := bar_value(c, s, i)
	r: ops.Rect
	if c.stacked {
		lo, hi := bar_stack(f, c, i)
		r = bar_rect(f, l, i, 0, 1, lo[s], hi[s])
	} else {
		r = bar_rect(f, l, i, k, l.shown, 0, v if is_finite(v) else 0)
	}
	ops.stroke(f.gtx.scene, ops.Round_Rect{grow(r, 2), 3}, f.style.focus, {width = f.style.focus_width})
	val := format_value(c.value.format, v)
	label := fmt.aprintf("%s, %s: %s", c.series[s].name, c.categories[i], label_text(&val), allocator = f.gtx.allocator)
	point_semantics(f, label, r)
	return r
}
