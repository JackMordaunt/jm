package plot

import "core:fmt"
import "jm:ui"
import "jm:ui/ops"

// Box_Series is one series of box plots: a summary per category (see
// box_stats), and optionally a name for each outlier, in the order of the
// category's outliers, which its tooltip shows: the rig or client a dot
// stands for.
Box_Series :: struct {
	name:          string,
	boxes:         []Box_Stats,
	outlier_names: [][]string,
	slot:          Maybe(int), // its colour; nil takes its index
}

// Box_Chart is a box plot: series of distributions over categories, side
// by side.
Box_Chart :: struct {
	using chart: Chart,
	categories:  []string,
	series:      []Box_Series,
	value:       Axis,
	mean:        bool, // mark each box's mean too
}

// box_chart draws c in style: per category and series a box from the
// first to the third quartile with the median across it, whiskers to the
// farthest samples inside 1.5 IQR, outliers as dots and, with mean, the
// mean as a hollow diamond. The tooltip reads the category's summaries,
// or the one outlier under the pointer. The plot takes focus: Left and
// Right walk the categories, Up and Down the series.
box_chart :: proc(gtx: ^ui.Ctx, c: ^Box_Chart, style: ^Plot_Style, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	f := frame_open(gtx, &c.chart, style, key, loc)
	entries := make([]Entry, len(c.series), gtx.allocator)
	for s, i in c.series {
		entries[i] = {s.name, box_slot(s, i), .Box}
	}
	f.top = legend(&f, entries)
	l: Cat_Layout
	e := box_extent(&f, c, &l)
	if !show_status(&f, e.lo <= e.hi && len(c.categories) > 0) {
		return frame_close(&f)
	}
	cat_layout(&f, &l, c.categories, c.value, e)
	read_plot_events(&f, {len(c.categories), len(c.series)})
	at := cat_active(&f, &l)
	if at >= 0 {
		ops.fill(gtx.scene, band_rect(&f, &l, at), style.hover)
	}
	cat_draw_axes(&f, &l, c.value)
	for i in 0 ..< len(c.categories) {
		k := 0
		for s in 0 ..< len(c.series) {
			if shown(&f, s) {
				box_draw(&f, c, &l, i, s, k)
				k += 1
			}
		}
	}
	if at >= 0 {
		box_readout(&f, c, &l, at)
	}
	summary := cat_summary(&f, "Box plot", &l, len(c.series), c.value, e)
	plot_listen(&f)
	plot_semantics(&f, summary)
	return frame_close(&f)
}

@(private)
box_slot :: proc(s: Box_Series, i: int) -> int {
	return s.slot.? or_else i
}

// box_of is series s's summary in category i, and whether it has one with
// samples in it.
@(private)
box_of :: proc(c: ^Box_Chart, s, i: int) -> (Box_Stats, bool) {
	bs := c.series[s].boxes
	if i >= len(bs) || bs[i].count == 0 {
		return {}, false
	}
	return bs[i], true
}

// box_extent is the range the shown boxes cover, outliers and all.
@(private)
box_extent :: proc(f: ^Frame, c: ^Box_Chart, l: ^Cat_Layout) -> Extent {
	e := EMPTY_EXTENT
	for s in 0 ..< len(c.series) {
		if !shown(f, s) {
			continue
		}
		l.shown += 1
		for i in 0 ..< len(c.categories) {
			if b, ok := box_of(c, s, i); ok {
				extent_add(&e, b.min)
				extent_add(&e, b.max)
			}
		}
	}
	return e
}

// box_geometry is where series s's box in category i stands: its centre
// across the band and its width.
@(private)
box_geometry :: proc(f: ^Frame, l: ^Cat_Layout, i, k: int) -> (centre, w: f32) {
	return slot_span(f, l, i, k, l.shown, f.style.box_max)
}

// box_draw draws series s's box in category i, the k-th shown.
@(private)
box_draw :: proc(f: ^Frame, c: ^Box_Chart, l: ^Cat_Layout, i, s, k: int) {
	b, ok := box_of(c, s, i)
	if !ok {
		return
	}
	gtx, st := f.gtx, f.style
	lk := look(st, box_slot(c.series[s], s))
	x, w := box_geometry(f, l, i, k)
	y := proc(l: ^Cat_Layout, v: f64) -> f32 {return scale_to(l.value.scale, v)}
	q1, q3, med := y(l, b.q1), y(l, b.q3), y(l, b.median)
	// Whiskers, where they reach past the box; a whisker that ends inside
	// it (its quartile's sample was an outlier) is not drawn.
	if b.whisker_lo < b.q1 {
		draw_whisker(gtx, x, w * 0.4, y(l, b.whisker_lo), q1, lk.color)
	}
	if b.whisker_hi > b.q3 {
		draw_whisker(gtx, x, w * 0.4, y(l, b.whisker_hi), q3, lk.color)
	}
	box := ops.Rect{x - w / 2, min(q1, q3), w, max(abs(q1 - q3), 1)}
	ops.fill(gtx.scene, ops.Round_Rect{box, 2}, ops.with_alpha(lk.color, 0.2))
	ops.stroke(gtx.scene, ops.Round_Rect{box, 2}, lk.color, {width = 1.5})
	ops.stroke(gtx.scene, ui.line(gtx, {box.x, med}, {box.x + w, med}), lk.color, {width = 2.5})
	if c.mean {
		mean := ops.Point{x, y(l, b.mean)}
		draw_marker(gtx, .Diamond, mean, 3.5, st.background, st.background)
		ops.stroke(gtx.scene, marker_shape(gtx, .Diamond, mean, 3.5), lk.color, {width = 1.5})
	}
	for o in b.outliers {
		draw_marker(gtx, lk.marker, {x, y(l, o)}, 3, lk.color, st.background)
	}
}

// draw_whisker draws a whisker at x from its end to the box, capped cap wide.
@(private)
draw_whisker :: proc(gtx: ^ui.Ctx, x, cap, end, box: f32, color: ops.Color) {
	ops.stroke(gtx.scene, ui.line(gtx, {x, end}, {x, box}), color, {width = 1.5})
	ops.stroke(gtx.scene, ui.line(gtx, {x - cap / 2, end}, {x + cap / 2, end}), color, {width = 1.5, cap = .Round})
}

// box_readout draws category i's tooltip: the outlier under the pointer
// if it is near one, else every shown series' summary.
@(private)
box_readout :: proc(f: ^Frame, c: ^Box_Chart, l: ^Cat_Layout, i: int) {
	if active(f) == .Pointer {
		if box_outlier_tip(f, c, l, i) {
			return
		}
	}
	tip: Tip
	put_text(&tip.heading, c.categories[i])
	k := 0
	anchor := band_rect(f, l, i)
	for s in 0 ..< len(c.series) {
		if !shown(f, s) {
			continue
		}
		b, ok := box_of(c, s, i)
		focus := f.st.keyed && f.st.series == s
		if ok {
			box_rows(&tip, c, s, b, focus)
		}
		if focus {
			anchor = draw_box_focus(f, c, l, i, s, k, b)
		}
		k += 1
	}
	tooltip(f, &tip, cat_anchor(f, anchor))
}

// box_rows adds series s's summary to a tooltip: the median first, then
// the box, the whiskers and the mean.
@(private)
box_rows :: proc(t: ^Tip, c: ^Box_Chart, s: int, b: Box_Stats, focus: bool) {
	fm := c.value.format
	name := c.series[s].name
	tip_add(t, {slot = box_slot(c.series[s], s), value = format_value(fm, b.median), name = name, focus = focus})
	tip_add(t, {value = range_label(fm, b.q1, b.q3), name = "middle half", plain = true})
	tip_add(t, {value = range_label(fm, b.whisker_lo, b.whisker_hi), name = "whiskers", plain = true})
	if c.mean {
		tip_add(t, {value = format_value(fm, b.mean), name = "mean", plain = true})
	}
	n: Label
	write_count(&n, "", b.count, "")
	tip_add(t, {value = n, name = "samples" if len(b.outliers) == 0 else outliers_name(len(b.outliers)), plain = true})
}

@(private)
outliers_name :: proc(n: int) -> string {
	return "samples, 1 outlier" if n == 1 else "samples, with outliers"
}

// range_label writes "a – b".
@(private)
range_label :: proc(f: Number_Format, a, b: f64) -> (l: Label) {
	x, y := format_value(f, a), format_value(f, b)
	put_text(&l, label_text(&x))
	put_text(&l, " – ")
	put_text(&l, label_text(&y))
	return
}

// OUTLIER_REACH is how near the pointer must be to an outlier for the
// tooltip to name it.
@(private)
OUTLIER_REACH :: 8

// Near is the outlier nearest the pointer: its series, its index among
// the category's outliers, and where it is drawn.
@(private)
Near :: struct {
	series, outlier: int,
	at:              ops.Point,
	dist:            f32, // squared
}

// box_outlier_tip shows the tooltip of the outlier nearest the pointer in
// category i, if one is within OUTLIER_REACH, and reports whether it did.
@(private)
box_outlier_tip :: proc(f: ^Frame, c: ^Box_Chart, l: ^Cat_Layout, i: int) -> bool {
	near := Near{series = -1, dist = OUTLIER_REACH * OUTLIER_REACH}
	k := 0
	for s in 0 ..< len(c.series) {
		if shown(f, s) {
			nearest_outlier(f, c, l, i, s, k, &near)
			k += 1
		}
	}
	if near.series < 0 {
		return false
	}
	tip: Tip
	put_text(&tip.heading, c.categories[i])
	b, _ := box_of(c, near.series, i)
	ser := c.series[near.series]
	name := fmt.aprintf("%s, outlier", ser.name, allocator = f.gtx.allocator)
	if i < len(ser.outlier_names) && near.outlier < len(ser.outlier_names[i]) {
		name = ser.outlier_names[i][near.outlier]
	}
	tip_add(&tip, {slot = box_slot(ser, near.series), value = format_value(c.value.format, b.outliers[near.outlier]), name = name})
	tooltip(f, &tip, {near.at.x - 4, near.at.y - 4, 8, 8})
	return true
}

// nearest_outlier keeps in near series s's outlier in category i nearest
// the pointer, if nearer than near already is; s is the k-th shown.
@(private)
nearest_outlier :: proc(f: ^Frame, c: ^Box_Chart, l: ^Cat_Layout, i, s, k: int, near: ^Near) {
	b, ok := box_of(c, s, i)
	if !ok {
		return
	}
	x, _ := box_geometry(f, l, i, k)
	p := f.st.pointer
	for o, j in b.outliers {
		q := ops.Point{x, scale_to(l.value.scale, o)}
		if d := (q.x - p.x) * (q.x - p.x) + (q.y - p.y) * (q.y - p.y); d < near.dist {
			near^ = {s, j, q, d}
		}
	}
}

// draw_box_focus rings the box the keyboard is on and names it for a screen
// reader, returning where it is.
@(private)
draw_box_focus :: proc(f: ^Frame, c: ^Box_Chart, l: ^Cat_Layout, i, s, k: int, b: Box_Stats) -> ops.Rect {
	x, w := box_geometry(f, l, i, k)
	r := ops.Rect{x - w / 2, f.plot.y, w, f.plot.h}
	if b.count > 0 {
		lo, hi := scale_to(l.value.scale, b.max), scale_to(l.value.scale, b.min)
		r = {x - w / 2, lo, w, hi - lo}
	}
	ops.stroke(f.gtx.scene, ops.Round_Rect{grow(r, 4), 4}, f.style.focus, {width = f.style.focus_width})
	fm := c.value.format
	med, q1, q3 := format_value(fm, b.median), format_value(fm, b.q1), format_value(fm, b.q3)
	label := fmt.aprintf(
		"%s, %s: median %s, middle half %s to %s, %d samples, %d outliers",
		c.series[s].name, c.categories[i], label_text(&med), label_text(&q1), label_text(&q3), b.count, len(b.outliers),
		allocator = f.gtx.allocator,
	)
	point_semantics(f, label, r)
	return r
}
