/*
Package shape turns text into glyph runs with kb_text_shape: OpenType GSUB
and GPOS for every script kb supports (Arabic joining, Indic reordering,
Thai, Khmer and the rest), Unicode normalisation, and per-run direction.
It knows fonts only as files and returns ops.Glyph_Run, so a renderer that
draws glyph ids from the same files draws what it shapes.

	s: shape.Shaper
	shape.init(&s)
	defer shape.destroy(&s)
	s.refs = sc.fonts[:]
	run := shape.shape(&s, font, 16, "office", context.allocator)

Direction: kb splits text into runs of one direction and returns them in
logical order, each right-to-left run already mirrored. Runs are placed
left to right in that order: a right-to-left run reads correctly inside a
left-to-right line, but runs are not yet reordered for a right-to-left
paragraph (the Unicode bidi algorithm's line reordering).

Clusters: a glyph's cluster is the byte offset of the first rune kb built
it from. Glyphs come out in logical order, and where a script reorders
glyphs within a syllable (a Devanagari pre-base matra), the syllable's
clusters merge to its smallest, so clusters never decrease along a run.

Memory: faces are parsed once per Font_Id and live until destroy, each
with its own kb context. A shape call allocates only the run it returns.

Threads: a Shaper is not thread-safe.
*/
package shape

import "core:mem"
import "core:os"
import "jm:ui/ops"
import "jm:ui"
import "jm:ui/kb"

// Shaper holds the faces it has parsed. Zero it and call init before use;
// set refs before shaping.
Shaper :: struct {
	refs:      []ops.Font_Ref, // what faces are loaded from
	faces:     map[ops.Font_Id]^Face, // boxed: kb keys its caches by font address
	scratch:   [dynamic]ui.Shaped_Glyph, // text under construction, reused
	runs:      [dynamic]ui.Shaped_Run,
	allocator: ^mem.Allocator, // boxed: kb keeps a pointer to it
}

// Face is a parsed font file and a kb context with only it pushed, so
// shaping never pops a font: kb 2.28d's kbts_ShapePopFont casts
// &Context->FontBlockSentinel.Prev, the pointer's own address, to the last
// block. ctx is nil when the file could not be read or parsed, so a bad id
// is tried once; it is the test because kbts_FontIsValid checks only
// Font->Error, which a zeroed font passes.
@(private)
Face :: struct {
	data: []byte,
	font: kb.Font,
	ctx:  ^kb.Shape_Context,
	upem: f32,
}

// init prepares s; everything it holds allocates from allocator.
init :: proc(s: ^Shaper, allocator := context.allocator) {
	s.allocator = new_clone(allocator, allocator)
	s.faces = make(map[ops.Font_Id]^Face, allocator)
	s.scratch = make([dynamic]ui.Shaped_Glyph, allocator)
	s.runs = make([dynamic]ui.Shaped_Run, allocator)
}

// destroy releases every face and kb's context.
destroy :: proc(s: ^Shaper) {
	if s.allocator == nil {
		return
	}
	a := s.allocator^
	for _, f in s.faces {
		if f.ctx != nil {
			kb.DestroyShapeContext(f.ctx)
			kb.FreeFont(&f.font)
		}
		delete(f.data, a)
		free(f, a)
	}
	delete(s.faces)
	delete(s.scratch)
	delete(s.runs)
	free(s.allocator, a)
	s^ = {}
}

// shape shapes UTF-8 text in font at size pixels as one run: runs of
// either direction laid left to right in logical order (see the package
// doc). Glyph offsets are from the run origin in pixels, y down; advance is
// the pen position after the last glyph. An unknown or unreadable font
// yields an empty run.
shape :: proc(s: ^Shaper, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
	st := shape_text(s, font, size, text, context.temp_allocator)
	run := ops.Glyph_Run{font = font, size = size}
	run.glyphs = make([]ops.Glyph, len(st.glyphs), allocator)
	pen: f32
	for r in st.runs {
		for v in 0 ..< r.last - r.first {
			k := r.last - 1 - v if r.rtl else r.first + v
			g := st.glyphs[k]
			run.glyphs[k] = {g.id, g.cluster, pen + g.offset.x, g.offset.y}
			pen += g.advance
		}
	}
	run.advance = pen
	return run
}

// shape_text shapes UTF-8 text in font at size pixels as a paragraph for
// ui.paragraph_layout: kb's runs with their directions, the paragraph's
// direction, and kb's grapheme and line breaks. Text is horizontal: a
// glyph's vertical advance is dropped. An unknown or unreadable font
// yields no glyphs, runs or breaks.
shape_text :: proc(s: ^Shaper, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ui.Shaped_Text {
	st := ui.Shaped_Text{font = font, size = size}
	f := face(s, font)
	if f == nil || len(text) == 0 {
		return st
	}
	kb.ShapeBegin(f.ctx, .Dont_Know, .Dont_Know)
	kb.ShapeUtf8(f.ctx, text, .Source_Index)
	kb.ShapeEnd(f.ctx)
	if kb.ShapeError(f.ctx) != .None {
		return st
	}

	scale := size / f.upem
	clear(&s.scratch)
	clear(&s.runs)
	for {
		r: kb.Run
		if !kb.ShapeRun(f.ctx, &r) {
			break
		}
		if len(s.runs) == 0 {
			st.rtl = r.paragraph_direction == .RTL
		}
		first := len(s.scratch)
		g: ^kb.Glyph
		for kb.GlyphIteratorNext(&r.glyphs, &g) {
			cp: kb.Shape_Codepoint
			_ = kb.ShapeGetShapeCodepoint(f.ctx, g.user_id_or_codepoint_index, &cp)
			// Font units are y up, as OpenType's glyph space is.
			append(&s.scratch, ui.Shaped_Glyph{u32(g.id), u32(cp.user_id), f32(g.advance_x) * scale, {f32(g.offset_x) * scale, -f32(g.offset_y) * scale}})
		}
		if len(s.scratch) == first {
			continue
		}
		rtl := r.direction == .RTL
		if rtl {
			reverse(s.scratch[first:]) // kb mirrored it; clusters want logical order
		}
		append(&s.runs, ui.Shaped_Run{first = first, last = len(s.scratch), rtl = rtl})
	}
	merge_clusters(s.scratch[:])
	for &r, i in s.runs {
		r.start = int(s.scratch[r.first].cluster)
		r.end = int(s.scratch[s.runs[i + 1].first].cluster) if i + 1 < len(s.runs) else len(text)
	}
	if len(s.runs) > 0 {
		s.runs[0].start = 0
	}

	breaks := make([dynamic]ui.Text_Break, 0, len(text), allocator)
	cp: kb.Shape_Codepoint
	for i: i32 = 0; kb.ShapeGetShapeCodepoint(f.ctx, i, &cp); i += 1 {
		kinds: ui.Break_Kinds
		if .Grapheme in cp.breaks {
			kinds += {.Grapheme}
		}
		if .Line_Soft in cp.breaks {
			kinds += {.Line_Soft}
		}
		if .Line_Hard in cp.breaks {
			kinds += {.Line_Hard}
		}
		if kinds != {} {
			append(&breaks, ui.Text_Break{int(cp.user_id), kinds})
		}
	}
	st.breaks = breaks[:]
	st.glyphs = make([]ui.Shaped_Glyph, len(s.scratch), allocator)
	copy(st.glyphs, s.scratch[:])
	st.runs = make([]ui.Shaped_Run, len(s.runs), allocator)
	copy(st.runs, s.runs[:])
	return st
}

// merge_clusters lowers each glyph's cluster to the smallest that follows
// it, so a glyph a script moved ahead of its base shares the base's
// cluster and clusters never decrease.
@(private)
merge_clusters :: proc(gs: []ui.Shaped_Glyph) {
	for i := len(gs) - 2; i >= 0; i -= 1 {
		gs[i].cluster = min(gs[i].cluster, gs[i + 1].cluster)
	}
}

@(private)
reverse :: proc(gs: []ui.Shaped_Glyph) {
	for i, j := 0, len(gs) - 1; i < j; i, j = i + 1, j - 1 {
		gs[i], gs[j] = gs[j], gs[i]
	}
}

// face is font's parsed face, loading it on first use from s.refs; nil
// when the id is unknown or its file does not parse.
@(private)
face :: proc(s: ^Shaper, font: ops.Font_Id) -> ^Face {
	if f, ok := s.faces[font]; ok {
		return f.ctx != nil ? f : nil
	}
	a := s.allocator^
	f := new(Face, a)
	s.faces[font] = f
	for ref in s.refs {
		if ref.id != font {
			continue
		}
		data, err := os.read_entire_file(ref.path, a)
		if err != nil {
			break
		}
		f.data = data
		fn, fd := kb.allocator(s.allocator)
		f.font = kb.FontFromMemory(data, 0, fn, fd)
		if !kb.FontIsValid(&f.font) {
			kb.FreeFont(&f.font) // whatever a failed parse allocated
			break
		}
		info := kb.Font_Info2_1{size = size_of(kb.Font_Info2_1)}
		kb.GetFontInfo2(&f.font, &info)
		if info.units_per_em == 0 {
			kb.FreeFont(&f.font)
			break
		}
		f.upem = f32(info.units_per_em)
		f.ctx = kb.CreateShapeContext(kb.allocator(s.allocator))
		_ = kb.ShapePushFont(f.ctx, &f.font)
		break
	}
	return f.ctx != nil ? f : nil
}
