package render

import "core:mem"
import "jm:ui/ops"

import "jm:ui"
import bl "jm:ui/blend2d"

// shaper returns a ui.Shaper over Blend2D's font_shape. It loads fonts from
// fonts (typically sc.fonts[:] after add_font), so it works before any
// frame exists, and shares r's font cache so glyph ids match what render
// draws. fonts must outlive the shaper.
shaper :: proc(r: ^Renderer, fonts: []ops.Font_Ref) -> ui.Shaper {
	r.font_refs = fonts
	return {data = r, shape = shape, metrics = metrics}
}

// shape shapes UTF-8 text at size pixels. Glyph offsets are absolute from
// the run origin in pixels, y down; advance is the pen position after the
// last glyph. An unknown font yields an empty run.
@(private)
shape :: proc(data: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
	r := (^Renderer)(data)
	run := ops.Glyph_Run{font = font, size = size}
	fnt := font_for(r, font, size, r.font_refs)
	if fnt == nil || len(text) == 0 {
		return run
	}

	gb: bl.GlyphBufferCore
	bl.glyph_buffer_init(&gb)
	defer bl.glyph_buffer_destroy(&gb)
	if bl.glyph_buffer_set_text(&gb, raw_data(text), uint(len(text)), .UTF8) != 0 {
		return run
	}
	if bl.font_shape(fnt, &gb) != 0 {
		return run
	}
	n := int(bl.glyph_buffer_get_size(&gb))
	ids := bl.glyph_buffer_get_content(&gb)
	place := bl.glyph_buffer_get_placement_data(&gb)
	if n == 0 || ids == nil {
		return run
	}

	// font_shape leaves ADVANCE_OFFSET placement in design units; the font
	// matrix scales them to pixels and flips y (m11 is negative).
	fm: bl.FontMatrix
	bl.font_get_matrix(fnt, &fm)

	run.glyphs = make([]ops.Glyph, n, allocator)
	pen: [2]f64
	for i in 0 ..< n {
		id := mem.ptr_offset(ids, i)^
		off, adv: [2]f64
		if place != nil {
			p := mem.ptr_offset(place, i)^
			off = {f64(p.placement.x) * fm.m00, f64(p.placement.y) * fm.m11}
			adv = {f64(p.advance.x) * fm.m00, f64(p.advance.y) * fm.m11}
		}
		run.glyphs[i] = {id, f32(pen.x + off.x), f32(pen.y + off.y)}
		pen += adv
	}
	run.advance = f32(pen.x)
	return run
}

// metrics reports ascent, descent and line gap in pixels, all positive.
@(private)
metrics :: proc(data: rawptr, font: ops.Font_Id, size: f32) -> ui.Font_Metrics {
	r := (^Renderer)(data)
	fnt := font_for(r, font, size, r.font_refs)
	if fnt == nil {
		return {}
	}
	fm: bl.FontMetrics
	if bl.font_get_metrics(fnt, &fm) != 0 {
		return {}
	}
	return {ascent = fm.ascent, descent = fm.descent, line_gap = fm.line_gap}
}
