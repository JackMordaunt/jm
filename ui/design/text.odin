package design

import "core:fmt"
import "core:strings"
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

// layout_style lays s out at st in font as a paragraph wrapped at width
// (not at all when width <= 0), each line st's line height tall, into the
// frame allocator. max_lines > 0 truncates it to that many lines, the last
// ending in ellipsis: max_lines = 1 truncates rather than wraps at width.
// balance evens the lines out (ui.balanced_width).
layout_style :: proc(gtx: ^ui.Ctx, s: string, st: Type_Style, font: ops.Font_Id, width: f32 = 0, max_lines := 0, ellipsis := ui.ELLIPSIS, balance := false) -> ui.Paragraph {
	return ui.paragraph_layout(gtx.shaper, font, st.size, s, width, gtx.allocator, line_pitch = st.line_height, max_lines = max_lines, ellipsis = ellipsis, balance = balance)
}

// Selection_Paint is a selected byte range of a paragraph and its colours:
// bg under the text, fg for the text over it. A zero value selects nothing.
Selection_Paint :: struct {
	lo, hi: int,
	bg, fg: ops.Color,
}

// draw_paragraph draws p with its first line box's top-left at pos, in
// visual order, right-to-left runs and all. With a selection, its
// highlight goes under the text and the selected stretch is drawn again in
// sel.fg, clipped to the highlight, so the colour changes exactly at the
// selection's edge even inside a ligature.
draw_paragraph :: proc(gtx: ^ui.Ctx, p: ui.Paragraph, pos: ops.Point, color: ops.Color, sel := Selection_Paint{}) {
	rects: []ops.Rect
	if sel.lo < sel.hi {
		rects = ui.paragraph_selection_rects(p, sel.lo, sel.hi, gtx.allocator)
		for r in rects {
			ops.fill(gtx.scene, ops.Rect{pos.x + r.x, pos.y + r.y, r.w, r.h}, sel.bg)
		}
	}
	if color[3] != 0 {
		ui.paragraph_draw(gtx.scene, p, pos, color)
	}
	if sel.fg == color || sel.fg[3] == 0 {
		return
	}
	for r in rects {
		ops.clip_push(gtx.scene, ops.Rect{pos.x + r.x, pos.y + r.y, r.w, r.h})
		ui.paragraph_draw(gtx.scene, p, pos, sel.fg)
		ops.clip_pop(gtx.scene)
	}
}

// thousands writes n with a comma every three digits, in the one locale
// jm:ui has: a count a design system shows (Fluent's rating count,
// Primer's row and value counts).
thousands :: proc(n: int, allocator := context.temp_allocator) -> string {
	digits := fmt.tprintf("%d", abs(n))
	b := strings.builder_make(allocator)
	if n < 0 {
		strings.write_byte(&b, '-')
	}
	for ch, i in digits {
		if i > 0 && (len(digits) - i) % 3 == 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_rune(&b, ch)
	}
	return strings.to_string(b)
}
