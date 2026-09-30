package ops

// A shaped run of glyphs, as the Glyphs op draws it. Shaping itself is
// ui's (text.odin): a Shaper produces these from text.
//
// A cluster is the smallest span of text the shaper maps to glyphs as a
// unit, such as several runes to one ligature glyph or one rune to a base
// and mark glyphs. A Shaper must emit glyphs in logical order, so clusters
// never decrease along a run: ui.caret_x relies on it, and test_text
// (ui/render) and test_caret_plain (ui) pin it for both shapers.

Glyph :: struct {
	id:      u32,
	cluster: u32, // byte offset in the shaped text where this glyph's cluster starts
	x, y:    f32, // offset from the run origin, in pixels
}

Glyph_Run :: struct {
	font:    Font_Id,
	size:    f32,
	glyphs:  []Glyph,
	advance: f32, // total advance width in pixels
}
