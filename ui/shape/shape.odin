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
import "jm:ui/kb"

// Shaper holds the faces it has parsed. Zero it and call init before use;
// set refs before shaping.
Shaper :: struct {
	refs:      []ops.Font_Ref, // what faces are loaded from
	faces:     map[ops.Font_Id]^Face, // boxed: kb keys its caches by font address
	scratch:   [dynamic]ops.Glyph, // a run under construction, reused
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
	s.scratch = make([dynamic]ops.Glyph, allocator)
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
	free(s.allocator, a)
	s^ = {}
}

// shape shapes UTF-8 text in font at size pixels. Glyph offsets are from
// the run origin in pixels, y down; advance is the pen position after the
// last glyph. An unknown or unreadable font yields an empty run.
shape :: proc(s: ^Shaper, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
	run := ops.Glyph_Run{font = font, size = size}
	f := face(s, font)
	if f == nil || len(text) == 0 {
		return run
	}
	kb.ShapeBegin(f.ctx, .Dont_Know, .Dont_Know)
	kb.ShapeUtf8(f.ctx, text, .Source_Index)
	kb.ShapeEnd(f.ctx)
	if kb.ShapeError(f.ctx) != .None {
		return run
	}

	scale := f64(size) / f64(f.upem)
	clear(&s.scratch)
	pen: [2]i64 // font units
	for {
		r: kb.Run
		if !kb.ShapeRun(f.ctx, &r) {
			break
		}
		start := len(s.scratch)
		g: ^kb.Glyph
		for kb.GlyphIteratorNext(&r.glyphs, &g) {
			cp: kb.Shape_Codepoint
			_ = kb.ShapeGetShapeCodepoint(f.ctx, g.user_id_or_codepoint_index, &cp)
			x := f64(pen.x + i64(g.offset_x)) * scale
			y := -f64(pen.y + i64(g.offset_y)) * scale // font units are y up
			append(&s.scratch, ops.Glyph{u32(g.id), u32(cp.user_id), f32(x), f32(y)})
			pen += {i64(g.advance_x), i64(g.advance_y)}
		}
		if r.direction == .RTL {
			reverse(s.scratch[start:]) // kb mirrored it; clusters want logical order
		}
	}
	merge_clusters(s.scratch[:])
	run.glyphs = make([]ops.Glyph, len(s.scratch), allocator)
	copy(run.glyphs, s.scratch[:])
	run.advance = f32(f64(pen.x) * scale)
	return run
}

// merge_clusters lowers each glyph's cluster to the smallest that follows
// it, so a glyph a script moved ahead of its base shares the base's
// cluster and clusters never decrease.
@(private)
merge_clusters :: proc(gs: []ops.Glyph) {
	for i := len(gs) - 2; i >= 0; i -= 1 {
		gs[i].cluster = min(gs[i].cluster, gs[i + 1].cluster)
	}
}

@(private)
reverse :: proc(gs: []ops.Glyph) {
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
