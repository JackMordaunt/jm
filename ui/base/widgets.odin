package base

import "base:runtime"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// Label_Style is a label's colour and size; a zero field takes the theme's.
Label_Style :: struct {
	color: ops.Color, // default Fg
	size:  f32, // default text_size
}

// resolve_label fills s's zero fields from the active theme.
resolve_label :: proc(s: Label_Style) -> Label_Style {
	return {color = ui.or_color(s.color, color(.Fg)), size = s.size == 0 ? theme().text_size : s.size}
}

// label draws one line of text, baseline at the font's ascent. Its size is
// the text's advance by the line height, clamped to the constraints; it
// does not wrap. It records a Tag with the text so a probe can find it.
// The text is selectable (ui.selectable_text) unless selectable is false.
label :: proc(gtx: ^ui.Ctx, text: string, style := Label_Style{}, key: u64 = 0, selectable := true, loc := #caller_location) -> ui.Dims {
	w := ui.widget_open(gtx, key, loc)
	s := resolve_label(style)
	p := ui.paragraph_layout(gtx.shaper, font(gtx), s.size, text, 0, gtx.allocator)
	width := p.width
	for c in p.lines[0].hanging {
		width = max(width, p.width + c.x1) // trailing spaces count, as a run's advance did
	}
	size := ui.constrain(gtx.constraints, {width, p.height})
	if selectable {
		selectable_paragraph(gtx, w.id, p, {}, s.color, {0, 0, size.x, size.y})
	} else if ui.painted(s.color) {
		design.draw_paragraph(gtx, p, {}, s.color)
	}
	ops.tag(gtx.scene, w.id, ui.frame_string(gtx, text), {0, 0, size.x, size.y})
	ui.semantics(gtx, &w, {role = .Text, label = ui.frame_string(gtx, text)})
	return ui.widget_close(gtx, &w, {size, p.metrics.ascent})
}

// selectable_paragraph draws p with its top-left at at in color, selectable
// (ui.selectable_text) through an area over bounds that id names, its
// selection in the theme's selection colours. Content text in any design
// system draws through it; bounds is usually the widget's own box, and id
// its own Area_Id or one mixed from it.
selectable_paragraph :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, p: ui.Paragraph, at: ops.Point, color: ops.Color, bounds: ops.Rect) {
	lo, hi, focused := ui.selectable_text(gtx, id, p, at, bounds)
	design.draw_paragraph(gtx, p, at, color, selection_colors(lo, hi, focused))
}

// text draws one line of s with its top-left at pos, styled like label
// but with no widget slot, no sizing and no tag: ui.draw_text with the
// theme's defaults.
text :: proc(gtx: ^ui.Ctx, s: string, pos: ops.Point, style := Label_Style{}) {
	st := resolve_label(style)
	f := font(gtx)
	run := ui.shape(gtx.shaper, f, st.size, s, gtx.allocator)
	m := ui.metrics(gtx.shaper, f, st.size)
	if ui.painted(st.color) {
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), {pos.x, pos.y + m.ascent}, st.color)
	}
}

// divider is a line of the theme's stroke width (at least 1px) across the
// innermost flex's cross axis: horizontal in a column or outside a flex,
// vertical in a row. It spans the cross max when bounded, else the cross
// min. line defaults to the theme's Outline.
divider :: proc(gtx: ^ui.Ctx, line := ops.Color{}, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	axis, _ := ui.parent_axis(gtx)
	p := ui.widget_open(gtx, key, loc)
	c := ui.or_color(line, color(.Outline))
	t := max(theme().stroke, 1)
	cs := gtx.constraints
	size: ops.Size
	if axis == .Vertical {
		size = {ui.is_finite(cs.max.x) ? cs.max.x : cs.min.x, t}
	} else {
		size = {t, ui.is_finite(cs.max.y) ? cs.max.y : cs.min.y}
	}
	size = ui.constrain(cs, size)
	if ui.painted(c) {
		ops.fill(gtx.scene, ops.Rect{0, 0, size.x, size.y}, c)
	}
	return ui.widget_close(gtx, &p, {size = size})
}

// box_open sizes its body within what it is offered: width or height,
// when non-zero, fixes that axis; min_size and max_size bound the rest
// (a zero max leaves an axis uncapped). The body gets the narrowed
// constraints and the box is at least min_size even around a small body.
// It paints nothing: open a panel inside it for a surface. See
// ui.sized_open for how a conflict with the offered constraints resolves.
box_open :: proc(
	gtx: ^ui.Ctx,
	width: f32 = 0,
	height: f32 = 0,
	min_size := ops.Size{},
	max_size := ops.Size{},
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Inset {
	return ui.sized_open(gtx, box_limits(width, height, min_size, max_size), key, loc)
}

// box is box_open as a guard: `if base.box(gtx, width = 240) { … }`
// closes itself at the end of the if.
@(deferred_in = box_guard_close)
box :: proc(
	gtx: ^ui.Ctx,
	width: f32 = 0,
	height: f32 = 0,
	min_size := ops.Size{},
	max_size := ops.Size{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	box_open(gtx, width, height, min_size, max_size, key, loc)
	return true
}

@(private = "file")
box_guard_close :: proc(gtx: ^ui.Ctx, width, height: f32, min_size, max_size: ops.Size, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Inset)
}

// box_limits folds a fixed width or height into min and max.
@(private = "file")
box_limits :: proc(width, height: f32, min_size, max_size: ops.Size) -> ui.Size_Limits {
	l := ui.Size_Limits{min_size, max_size}
	if width > 0 {
		l.min.x, l.max.x = width, width
	}
	if height > 0 {
		l.min.y, l.max.y = height, height
	}
	return l
}

// panel_open is ui.box_open with the theme's defaults: a Surface fill, an
// Outline border of stroke width, the theme's radius and spacing as
// padding. A zero field takes the default; CLEAR paints nothing.
panel_open :: proc(gtx: ^ui.Ctx, style := ui.Box_Style{}, key: u64 = 0, loc := #caller_location) -> ui.Box {
	th := theme()
	st := style
	st.fill = ui.or_color(st.fill, color(.Surface))
	st.outline = ui.or_color(st.outline, color(.Outline))
	if st.stroke == 0 {
		st.stroke = th.stroke
	}
	if st.radius == 0 {
		st.radius = th.radius
	}
	if st.padding == {} {
		st.padding = ui.pad_all(th.spacing)
	}
	return ui.box_open(gtx, st, key, loc)
}

// panel is panel_open as a guard: `if base.panel(gtx) { … }` closes itself
// at the end of the if (see ui/guards.odin).
@(deferred_in = panel_guard_close)
panel :: proc(gtx: ^ui.Ctx, style := ui.Box_Style{}, key: u64 = 0, loc := #caller_location) -> bool {
	panel_open(gtx, style, key, loc)
	return true
}

@(private = "file")
panel_guard_close :: proc(gtx: ^ui.Ctx, style: ui.Box_Style, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Box)
}
