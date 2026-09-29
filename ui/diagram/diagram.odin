/*
Package diagram is a small kit for the kind of architecture diagram and
node graph that explains a design: titled, accent-bordered groups of
two-line chips, and arrows (solid or dashed) between explicit points. It
draws with plain ui calls — fill_rrect, group, arrow and dashed_arrow are
all just ui.fill/ui.stroke/ui.text/ui.line/ui.polygon underneath — so a
diagram it does not cover is still one ui proc away.

Layout here is by explicit ops.Rect and ops.Point, not ui's flex containers:
a diagram's boxes and arrows are usually placed once, by whoever is
deciding where things go, not measured and wrapped like a form.

	diagram.group(gtx, host_rect, "HOST PROCESS", "owns the window", blue, host_chips)
	diagram.group(gtx, sub_rect, "UI SUBPROCESS", "rebuilt on change", purple, sub_chips)
	diagram.arrow(gtx, {host_rect.x + host_rect.w, 170}, {sub_rect.x, 170}, blue, 2.5)
*/
package diagram

import "jm:ui"
import "jm:ui/ops"

// Chip is one labeled row in a group: a short title and subtitle.
Chip :: struct {
	title, subtitle: string,
}

// fill_rrect fills and outlines a round rect in one call; the outline is
// skipped when stroke_w <= 0.
fill_rrect :: proc(o: ^ops.Scene, r: ops.Rect, radius: f32, fill, outline: ops.Color, stroke_w: f32) {
	rr := ops.Round_Rect{r, radius}
	ops.fill(o, rr, fill)
	if stroke_w > 0 {
		ops.stroke(o, rr, outline, {width = stroke_w})
	}
}

// group draws a titled, accent-bordered card at r — a coloured top
// stripe, a title and subtitle, then chips stacked inside it, alternating
// background — the way examples/hotreload-diagram drew its two process
// boxes. Size r to fit len(chips) chips at 74 logical units each below a
// 74-unit header; group does not clip or scroll what does not fit.
group :: proc(gtx: ^ui.Ctx, r: ops.Rect, title, subtitle: string, accent: ops.Color, chips: []Chip) {
	th := gtx.theme
	o := gtx.scene
	fill_rrect(o, r, 10, th.surface, accent, 2)
	ops.fill(o, ops.Rect{r.x, r.y, r.w, 4}, accent)
	ui.text(gtx, title, {r.x + 20, r.y + 16}, {size = 16, color = accent})
	ui.text(gtx, subtitle, {r.x + 20, r.y + 40}, {size = 11, color = th.muted})

	y := r.y + 74
	chip_h: f32 = 62
	gap: f32 = 10
	for c, i in chips {
		cr := ops.Rect{r.x + 20, y, r.w - 40, chip_h}
		fill := i % 2 == 0 ? th.surface_hover : th.surface
		fill_rrect(o, cr, 8, fill, th.outline, 1)
		ops.fill(o, ops.Rect{cr.x, cr.y, 4, cr.h}, accent)
		ui.text(gtx, c.title, {cr.x + 14, cr.y + 9}, {size = 13})
		ui.text(gtx, c.subtitle, {cr.x + 14, cr.y + 30}, {size = 10.5, color = th.muted})
		y += chip_h + gap
	}
}

// group_height is the r.h a group needs to fit n chips without crowding:
// pass it as r.h when building the caller's own layout.
group_height :: proc(n: int) -> f32 {
	if n <= 0 {
		return 74
	}
	return 74 + f32(n) * 62 + f32(n - 1) * 10 + 16
}

// arrow draws a straight line from p0 to p1 with a filled triangular
// arrowhead at p1. p0 and p1 may come from a literal: arrow builds its
// path through gtx.allocator, never a bare composite literal (see Path).
arrow :: proc(gtx: ^ui.Ctx, p0, p1: ops.Point, color: ops.Color, width: f32) {
	dir, ok := unit(p1 - p0)
	if !ok {
		return
	}
	shaft_end := ops.Point{p1.x - dir.x * 10, p1.y - dir.y * 10}
	ops.stroke(gtx.scene, ui.line(gtx, p0, shaft_end), color, {width = width, cap = .Round})
	arrow_head(gtx, p1, dir, color)
}

// dashed_arrow is arrow with a dashed shaft: the diagram kit's convention
// for a signal that is out of band, not part of the per-frame flow a
// solid arrow depicts.
dashed_arrow :: proc(gtx: ^ui.Ctx, p0, p1: ops.Point, color: ops.Color, width, dash, gap: f32) {
	d := p1 - p0
	total := length(d)
	dir, ok := unit(d)
	if !ok {
		return
	}
	head_room := f32(12)
	at: f32 = 0
	for at < total - head_room {
		a := ops.Point{p0.x + dir.x * at, p0.y + dir.y * at}
		e := min(at + dash, total - head_room)
		b := ops.Point{p0.x + dir.x * e, p0.y + dir.y * e}
		ops.stroke(gtx.scene, ui.line(gtx, a, b), color, {width = width, cap = .Round})
		at = e + gap
	}
	arrow_head(gtx, p1, dir, color)
}

// arrow_head fills a small triangle whose tip is at tip, pointing along
// the unit vector dir.
@(private = "file")
arrow_head :: proc(gtx: ^ui.Ctx, tip, dir: ops.Point, color: ops.Color, size: f32 = 10) {
	perp := ops.Point{-dir.y, dir.x}
	base := ops.Point{tip.x - dir.x * size, tip.y - dir.y * size}
	left := ops.Point{base.x + perp.x * size * 0.5, base.y + perp.y * size * 0.5}
	right := ops.Point{base.x - perp.x * size * 0.5, base.y - perp.y * size * 0.5}
	ops.fill(gtx.scene, ui.polygon(gtx, []ops.Point{tip, left, right}), color)
}

@(private = "file")
length :: proc(v: ops.Point) -> f32 {
	s := v.x * v.x + v.y * v.y
	if s == 0 {
		return 0
	}
	x := s
	for _ in 0 ..< 12 {
		x = 0.5 * (x + s / x)
	}
	return x
}

@(private = "file")
unit :: proc(v: ops.Point) -> (ops.Point, bool) {
	l := length(v)
	if l == 0 {
		return {}, false
	}
	return {v.x / l, v.y / l}, true
}
