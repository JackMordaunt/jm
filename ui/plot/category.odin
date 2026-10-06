package plot

import "core:fmt"
import "jm:ui/ops"

// Cat_Layout is a chart over categories laid out: its bands, value axis,
// and which way they run.
@(private)
Cat_Layout :: struct {
	horizontal: bool, // categories down the left, values along the bottom
	bands:      Band_Layout,
	value:      Value_Axis,
	shown:      int, // how many series are shown
}

// cat_layout fits a category chart's axes around its plot. Vertically the
// categories run along the bottom under their bars, turned or thinned to
// fit; horizontally down the left, cut to a third of the width, with the
// values along the bottom.
@(private)
cat_layout :: proc(f: ^Frame, l: ^Cat_Layout, categories: []string, a: Axis, e: Extent) {
	s := f.style
	title := axis_title_height(f, a.title)
	top := f.top + title + s.tick_size / 2
	line := s.tick_size * 1.3 + 6
	if l.horizontal {
		l.bands = band_layout(f, categories, 1, f.size.x / 3)
		left := l.bands.height + 2
		width := max(f.size.x - left - 16, 1)
		height := max(f.size.y - top - line, 1)
		l.value = value_axis(f, a, e, width, pitch = 72)
		f.plot = {left, top, width, height}
		l.bands = band_layout(f, categories, height, f.size.x / 3)
		l.value.scale.r0, l.value.scale.r1 = f.plot.x, f.plot.x + width
		return
	}
	l.value = value_axis(f, a, e, f.size.y - top - line)
	left := l.value.width + 10
	width := max(f.size.x - left - 8, 1)
	l.bands = band_layout(f, categories, width, 0)
	height := max(f.size.y - top - l.bands.height, 1)
	f.plot = {left, top, width, height}
	place_value(&l.value, f.plot)
}

// cat_draw_axes draws a category chart's axes and the value axis's title.
@(private)
cat_draw_axes :: proc(f: ^Frame, l: ^Cat_Layout, a: Axis) {
	if l.horizontal {
		draw_value_axis(f, &l.value, .Bottom, true)
		draw_bands_left(f, &l.bands)
	} else {
		draw_value_axis(f, &l.value, .Left, true)
		draw_bands_below(f, &l.bands)
	}
	draw_axis_title(f, a.title, 0, f.top, false, -1)
}

// band_rect is category i's band across the whole plot.
@(private)
band_rect :: proc(f: ^Frame, l: ^Cat_Layout, i: int) -> ops.Rect {
	b, p := l.bands.band, f.plot
	start, width := band_start(b, i), band_width(b)
	pad := (band_step(b) - width) / 2
	if l.horizontal {
		return {p.x, p.y + start - pad, p.w, width + 2 * pad}
	}
	return {p.x + start - pad, p.y, width + 2 * pad, p.h}
}

// slot_span is where the k-th of n shown series sits across category i's
// band: its centre and the thickness it may take, at most most.
@(private)
slot_span :: proc(f: ^Frame, l: ^Cat_Layout, i, k, n: int, most: f32) -> (centre, thick: f32) {
	b := l.bands.band
	each := band_width(b) / f32(max(n, 1))
	thick = min(max(each - f.style.gap, 1), most)
	centre = band_start(b, i) + each * (f32(k) + 0.5)
	centre += f.plot.y if l.horizontal else f.plot.x
	return
}

// cat_pointer is the category under the pointer, or the keyboard's, or -1
// when the readout is not showing.
@(private)
cat_active :: proc(f: ^Frame, l: ^Cat_Layout) -> int {
	switch active(f) {
	case .None:
		return -1
	case .Pointer:
		p := f.st.pointer
		at := p.y - f.plot.y if l.horizontal else p.x - f.plot.x
		f.st.index = band_at(l.bands.band, at)
	case .Keyboard:
	}
	return clamp(f.st.index, 0, max(l.bands.band.n - 1, 0))
}

// cat_anchor is where a category chart's tooltip stands: beside the
// pointer, or beside rect, the mark the keyboard is on.
@(private)
cat_anchor :: proc(f: ^Frame, rect: ops.Rect) -> ops.Rect {
	if active(f) == .Pointer {
		p := f.st.pointer
		return {p.x - 4, p.y - 4, 8, 8}
	}
	return rect
}

// cat_summary is what a screen reader hears of a category chart.
@(private)
cat_summary :: proc(f: ^Frame, kind: string, l: ^Cat_Layout, series: int, a: Axis, e: Extent) -> string {
	lo, hi := format_value(a.format, e.lo), format_value(a.format, e.hi)
	n := l.bands.band.n
	return fmt.aprintf(
		"%s, %d %s, %d of %d series shown, values %s to %s",
		kind, n, "category" if n == 1 else "categories", l.shown, series, label_text(&lo), label_text(&hi),
		allocator = f.gtx.allocator,
	)
}
