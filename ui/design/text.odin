package design

import "jm:ui"
import "jm:ui/ops"

// Type_Style is a composite typography token: weight on the CSS scale (400 regular, 700 bold), size
// and line height in sp, and tracking in em. jm:ui has no tracking, so
// shaping drops it.
Type_Style :: struct {
	weight:      f32,
	size:        f32,
	line_height: f32,
	tracking:    f32,
}

// Font_Face is one loaded face and the weight it carries. jm:ui picks a
// face per run, not a weight, so a system loads one face per weight it
// uses and font_for maps a style's weight onto them.
Font_Face :: struct {
	weight: f32,
	id:     ops.Font_Id,
}

// font_for is the face in faces nearest weight w, the heavier on a tie,
// or fallback when faces is empty.
font_for :: proc(faces: []Font_Face, w: f32, fallback: ops.Font_Id) -> ops.Font_Id {
	if len(faces) == 0 {
		return fallback
	}
	best := faces[0]
	for f in faces[1:] {
		d, bd := abs(f.weight - w), abs(best.weight - w)
		if d < bd || (d == bd && f.weight > best.weight) {
			best = f
		}
	}
	return best.id
}

// Text is a shaped run with the metrics needed to place it.
Text :: struct {
	run:     ops.Glyph_Run,
	metrics: ui.Font_Metrics,
	width:   f32,
	height:  f32, // the style's line height, not the font's
}

// shape_style shapes s at st in font, into the frame allocator.
shape_style :: proc(gtx: ^ui.Ctx, s: string, st: Type_Style, font: ops.Font_Id) -> Text {
	run := ui.shape(gtx.shaper, font, st.size, s, gtx.allocator)
	m := ui.metrics(gtx.shaper, font, st.size)
	return {run, m, run.advance, st.line_height}
}

// draw_text draws t with its line box's top-left at pos, vertically
// centring the font's ascent+descent in the style's line height.
draw_text :: proc(gtx: ^ui.Ctx, t: Text, pos: ops.Point, color: ops.Color) {
	if color[3] == 0 || len(t.run.glyphs) == 0 {
		return
	}
	glyph_h := t.metrics.ascent + t.metrics.descent
	y := pos.y + (t.height - glyph_h) / 2 + t.metrics.ascent
	ops.glyphs(gtx.scene, ops.add_run(gtx.scene, t.run), {pos.x, y}, color)
}

// baseline_of is where draw_text puts t's baseline, relative to its top.
baseline_of :: proc(t: Text) -> f32 {
	return (t.height - t.metrics.ascent - t.metrics.descent) / 2 + t.metrics.ascent
}
