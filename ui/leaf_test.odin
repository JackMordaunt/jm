package ui

import "jm:ui/ops"

// label is the tests' leaf widget: one line of text at 14px in black,
// tagged with its text so a probe can find it. The themed label lives in
// ui/base, which package ui cannot import; this is the same widget
// without the theme.
label :: proc(gtx: ^Ctx, text: string, color := ops.Color{0, 0, 0, 255}, key: u64 = 0, loc := #caller_location) -> Dims {
	p := widget_open(gtx, key, loc)
	run, m := shape_line(gtx, text, 14)
	size := constrain(gtx.constraints, {run.advance, line_height(m)})
	if painted(color) {
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), {0, m.ascent}, color)
	}
	ops.tag(gtx.scene, p.id, frame_string(gtx, text), {0, 0, size.x, size.y})
	return widget_close(gtx, &p, {size, m.ascent})
}

// divider is the tests' cross-axis line: base.divider without the theme.
divider :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Dims {
	axis, _ := parent_axis(gtx)
	p := widget_open(gtx, key, loc)
	cs := gtx.constraints
	size: ops.Size
	if axis == .Vertical {
		size = {is_finite(cs.max.x) ? cs.max.x : cs.min.x, 1}
	} else {
		size = {1, is_finite(cs.max.y) ? cs.max.y : cs.min.y}
	}
	size = constrain(cs, size)
	ops.fill(gtx.scene, ops.Rect{0, 0, size.x, size.y}, ops.Color{0, 0, 0, 255})
	return widget_close(gtx, &p, {size = size})
}
