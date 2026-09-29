package ops

// A shaped run of glyphs, as the Glyphs op draws it. Shaping itself is
// ui's (text.odin): a Shaper produces these from text.

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
