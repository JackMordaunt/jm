package render

import "core:mem"
import "core:os"
import "jm:ui/ops"

import "jm:ui"
import bl "jm:ui/blend2d"
import "jm:ui/shape"

// SHAPER_ENV names the shaping engine for a whole app: unset or "kb" is
// kb_text_shape (jm:ui/shape), "blend2d" is Blend2D's own font_shape, kept
// to compare the two, as the text lab does.
SHAPER_ENV :: "JM_UI_SHAPER"

// shaper returns a ui.Shaper that shapes with jm:ui/shape (or Blend2D, see
// SHAPER_ENV) and measures with Blend2D's font metrics, so line boxes are
// the same whichever engine shapes. It loads fonts from fonts (typically
// sc.fonts[:] after add_font), so it works before any frame exists; glyph
// ids index the same files render draws from. fonts must outlive the
// shaper. fallbacks are fonts' ids to try in order for a rune the font
// asked for lacks (see shape.set_fallbacks); shape_blend2d does not use
// them.
shaper :: proc(r: ^Renderer, fonts: []ops.Font_Ref, fallbacks: []ops.Font_Id = nil) -> ui.Shaper {
	r.font_refs = fonts
	r.text.refs = fonts
	shape.set_fallbacks(&r.text, fallbacks)
	buf: [64]u8
	if os.get_env(buf[:], SHAPER_ENV) == "blend2d" {
		return {data = r, shape = shape_blend2d, metrics = metrics}
	}
	return {data = r, shape = shape_kb, metrics = metrics, shape_text = shape_text_kb}
}

@(private)
shape_text_kb :: proc(data: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ui.Shaped_Text {
	return shape.shape_text(&(^Renderer)(data).text, font, size, text, allocator)
}

@(private)
shape_kb :: proc(data: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
	return shape.shape(&(^Renderer)(data).text, font, size, text, allocator)
}

// shape_blend2d shapes UTF-8 text at size pixels. Glyph offsets are absolute from
// the run origin in pixels, y down; advance is the pen position after the
// last glyph. An unknown font yields an empty run.
@(private)
shape_blend2d :: proc(data: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
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
	info := bl.glyph_buffer_get_info_data(&gb)
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
		cluster: u32
		if info != nil {
			cluster = mem.ptr_offset(info, i).cluster
		}
		run.glyphs[i] = {id, cluster, f32(pen.x + off.x), f32(pen.y + off.y), font}
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
