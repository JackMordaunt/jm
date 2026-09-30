package ops

// A shaped run of glyphs, as the Glyphs op draws it. Shaping itself is
// ui's (text.odin): a Shaper produces these from text.
//
// A cluster is the smallest span of text the shaper maps to glyphs as a
// unit, such as several runes to one ligature glyph or one rune to a base
// and mark glyphs. A Shaper must emit glyphs in logical order, so clusters
// never decrease along a run: ui.caret_x relies on it, and test_text
// (ui/render) and test_caret_plain (ui) pin it for both shapers.
//
// Each glyph names its own font: a shaper that falls back to another font
// for a rune the run's font lacks keeps one run, and a renderer draws each
// stretch of one font with that font.

Glyph :: struct {
	id:      u32,
	cluster: u32, // byte offset in the shaped text where this glyph's cluster starts
	x, y:    f32, // offset from the run origin, in pixels
	font:    Font_Id, // the face id indexes; the run's font unless a fallback's
}

Glyph_Run :: struct {
	font:    Font_Id, // the font asked for, whose metrics the line uses
	size:    f32,
	glyphs:  []Glyph,
	advance: f32, // total advance width in pixels
}
