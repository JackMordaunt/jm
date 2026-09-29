package base

import "base:runtime"
import "jm:ui"
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
label :: proc(gtx: ^ui.Ctx, text: string, style := Label_Style{}, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	s := resolve_label(style)
	f := font(gtx)
	run := ui.shape(gtx.shaper, f, s.size, text, gtx.allocator)
	m := ui.metrics(gtx.shaper, f, s.size)
	size := ui.constrain(gtx.constraints, {run.advance, ui.line_height(m)})
	if ui.painted(s.color) {
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), {0, m.ascent}, s.color)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	return ui.widget_close(gtx, &p, {size, m.ascent})
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
