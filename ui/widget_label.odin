package ui

import "core:strings"

// label draws one line of text, baseline at the font's ascent. Its size is
// the text's advance by the line height, clamped to the constraints; v1 does
// not wrap. It records a Tag with the text so a probe can find it.
label :: proc(
	gtx: ^Ctx,
	text: string,
	style := Label_Style{},
	key: u64 = 0,
	loc := #caller_location,
) -> Dims {
	p := widget_open(gtx, key, loc)
	s := resolve_label(gtx.theme, style)
	run, m := shape_line(gtx, text, s.size)
	size := constrain(gtx.constraints, {run.advance, line_height(m)})
	if painted(s.color) {
		glyphs(gtx.ops, add_run(gtx.ops, run), {0, m.ascent}, s.color)
	}
	tag(gtx.ops, p.id, frame_string(gtx, text))
	return widget_close(gtx, &p, {size, m.ascent})
}

// text draws one line of s with its top-left at pos: font, size and colour
// come from style same as label, but there is no widget slot, no sizing
// against constraints and no tag. For a custom widget or canvas that places
// its own text directly, this is the one call in place of shape, metrics,
// line_height, add_run and glyphs.
text :: proc(gtx: ^Ctx, s: string, pos: Point, style := Label_Style{}) {
	st := resolve_label(gtx.theme, style)
	run, m := shape_line(gtx, s, st.size)
	if painted(st.color) {
		glyphs(gtx.ops, add_run(gtx.ops, run), {pos.x, pos.y + m.ascent}, st.color)
	}
}

// shape_line shapes text in the theme font at size, into the frame
// allocator, and returns the run with the font's metrics.
@(private)
shape_line :: proc(gtx: ^Ctx, text: string, size: f32) -> (Glyph_Run, Font_Metrics) {
	run := shape(gtx.shaper, gtx.theme.font, size, text, gtx.allocator)
	return run, metrics(gtx.shaper, gtx.theme.font, size)
}

// frame_string copies s into the frame allocator, since ops outlive the
// caller's strings only for the frame.
frame_string :: proc(gtx: ^Ctx, s: string) -> string {
	out, _ := strings.clone(s, gtx.allocator)
	return out
}
