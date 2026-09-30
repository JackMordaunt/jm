package ui

import "core:mem"
import "core:unicode/utf8"
import "jm:ui/ops"

// Shaped_Text is a paragraph shaped once, before it is broken into lines:
// its glyphs with their advances, the runs of one direction they fall in,
// and where the text may or must break. Everything is in logical order,
// the order of the text; lines and visual order are paragraph.odin's.
Shaped_Text :: struct {
	font:   ops.Font_Id,
	size:   f32,
	rtl:    bool, // the paragraph's direction
	glyphs: []Shaped_Glyph, // clusters never decrease
	runs:   []Shaped_Run, // cover glyphs and text end to end
	breaks: []Text_Break, // ascending; the end of the text is a boundary of every kind
}

// Shaped_Glyph is a glyph and its pen movement, in pixels. offset is where
// it sits from the pen, y down; advance is how far it moves the pen along
// its run's direction.
Shaped_Glyph :: struct {
	id:      u32,
	cluster: u32, // byte offset where its cluster starts
	advance: f32,
	offset:  [2]f32,
}

// Shaped_Run is glyphs[first:last], shaped from text[start:end] in one
// direction. An rtl run's glyphs are still in logical order: it is drawn
// from last to first.
Shaped_Run :: struct {
	first, last: int,
	start, end:  int,
	rtl:         bool,
}

Break_Kind :: enum u8 {
	Grapheme, // a caret may stop here
	Line_Soft, // a line may wrap here
	Line_Hard, // a line must end here
}
Break_Kinds :: bit_set[Break_Kind;u8]

// Text_Break is the boundary before byte offset at.
Text_Break :: struct {
	at:    int,
	kinds: Break_Kinds,
}

// shape_text shapes text as a paragraph through s, or, for a Shaper
// without shape_text, through shape: then the paragraph is one
// left-to-right run, every rune a grapheme, and lines may break after a
// space or tab and must after a newline.
shape_text :: proc(s: Shaper, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> Shaped_Text {
	if s.shape_text != nil {
		return s.shape_text(s.data, font, size, text, allocator)
	}
	return shaped_from_run(shape(s, font, size, text, allocator), text, allocator)
}

// shaped_from_run is shape_text's fallback: run as the one run of text,
// each glyph advancing to where the next one starts.
shaped_from_run :: proc(run: ops.Glyph_Run, text: string, allocator: mem.Allocator) -> Shaped_Text {
	st := Shaped_Text{font = run.font, size = run.size}
	st.glyphs = make([]Shaped_Glyph, len(run.glyphs), allocator)
	for g, i in run.glyphs {
		next := run.advance if i + 1 == len(run.glyphs) else run.glyphs[i + 1].x
		st.glyphs[i] = {g.id, g.cluster, next - g.x, {0, g.y}}
	}
	st.runs = make([]Shaped_Run, 1, allocator)
	st.runs[0] = {0, len(st.glyphs), 0, len(text), false}
	st.breaks = make([]Text_Break, utf8.rune_count(text), allocator)
	prev: rune
	i := 0
	for r, at in text {
		kinds := Break_Kinds{.Grapheme}
		switch prev {
		case '\n':
			kinds += {.Line_Hard}
		case ' ', '\t':
			if r != ' ' && r != '\t' {
				kinds += {.Line_Soft}
			}
		}
		st.breaks[i] = {at, kinds}
		prev = r
		i += 1
	}
	return st
}
