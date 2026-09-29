package ui

import "core:strings"
import "jm:ui/ops"

// draw_text draws one line of s with its top-left at pos in the toolkit's
// font at size, in color. There is no widget slot, no sizing against
// constraints and no tag: for a custom widget or canvas that places its
// own text directly, this is the one call in place of shape, metrics,
// line_height, add_run and glyphs. A themed label or text is base's.
draw_text :: proc(gtx: ^Ctx, s: string, pos: ops.Point, size: f32, color: ops.Color) {
	run, m := shape_line(gtx, s, size)
	if painted(color) {
		ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), {pos.x, pos.y + m.ascent}, color)
	}
}

// shape_line shapes text in the toolkit's font at size, into the frame
// allocator, and returns the run with the font's metrics.
shape_line :: proc(gtx: ^Ctx, text: string, size: f32) -> (ops.Glyph_Run, Font_Metrics) {
	run := shape(gtx.shaper, gtx.font, size, text, gtx.allocator)
	return run, metrics(gtx.shaper, gtx.font, size)
}

// frame_string copies s into the frame allocator, since sc outlive the
// caller's strings only for the frame.
frame_string :: proc(gtx: ^Ctx, s: string) -> string {
	out, _ := strings.clone(s, gtx.allocator)
	return out
}
