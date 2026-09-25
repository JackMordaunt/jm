package ui

import "core:mem"

// Text is shaped in layout and rasterized in the renderer. The op buffer
// carries glyph runs, never strings, so a renderer needs the font file and
// nothing else. Shaper is the seam: ui/render implements it over Blend2D's
// font_shape; tests use stub_shaper.

Glyph :: struct {
	id:   u32,
	x, y: f32, // offset from the run origin, in pixels
}

Glyph_Run :: struct {
	font:    Font_Id,
	size:    f32,
	glyphs:  []Glyph,
	advance: f32, // total advance width in pixels
}

Font_Metrics :: struct {
	ascent:   f32, // above the baseline, positive
	descent:  f32, // below the baseline, positive
	line_gap: f32,
}

Shaper :: struct {
	data:    rawptr,
	shape:   proc(data: rawptr, font: Font_Id, size: f32, text: string, allocator: mem.Allocator) -> Glyph_Run,
	metrics: proc(data: rawptr, font: Font_Id, size: f32) -> Font_Metrics,
}

shape :: proc(s: Shaper, font: Font_Id, size: f32, text: string, allocator: mem.Allocator) -> Glyph_Run {
	return s.shape(s.data, font, size, text, allocator)
}

metrics :: proc(s: Shaper, font: Font_Id, size: f32) -> Font_Metrics {
	return s.metrics(s.data, font, size)
}

// line_height is ascent + descent + line_gap.
line_height :: proc(m: Font_Metrics) -> f32 {
	return m.ascent + m.descent + m.line_gap
}

// stub_shaper is a deterministic monospace shaper for tests and dumps:
// every rune advances 0.6*size, glyph id is the rune, ascent is 0.8*size,
// descent 0.2*size, no line gap.
stub_shaper :: proc() -> Shaper {
	return {
		shape = proc(_: rawptr, font: Font_Id, size: f32, text: string, allocator: mem.Allocator) -> Glyph_Run {
			n := 0
			for _ in text {
				n += 1
			}
			gs := make([]Glyph, n, allocator)
			x: f32
			i := 0
			for r in text {
				gs[i] = {u32(r), x, 0}
				x += 0.6 * size
				i += 1
			}
			return {font, size, gs, x}
		},
		metrics = proc(_: rawptr, _: Font_Id, size: f32) -> Font_Metrics {
			return {0.8 * size, 0.2 * size, 0}
		},
	}
}
