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

Fallback: set_fallbacks names fonts to try, in order, for a rune the font
asked for lacks, as a browser's font-family list does. kb picks the font
per grapheme (kb_text_shape.h, CONTEXT:FONT HANDLING, and
test_shape_falls_back); each glyph carries the id of the font it came
from.

Weight: a Font_Ref's weight sets a variable font's wght axis, so its
advances and feature-variation substitutions are those of that weight; a
font without the axis ignores it (test_shape_variable_font_at_its_weight).

Memory: faces are parsed once per Font_Id and live until destroy. Each
font asked for gets a kb context with its fallbacks pushed under it, kept
until the fallbacks change. A shape call allocates only what it returns.

Cache: a paragraph is shaped once and its glyphs, runs and breaks kept,
keyed by the text, the font and the size, which is all kb reads: wrap
width is ui.paragraph_from_shaped's, a later pass over the shaped text,
so one shaping serves every width. The caller's copy is made from its
allocator, so what it gets back lives as long as before. Call tick once
a frame: an entry not used for KEEP_FRAMES whole frames is dropped at the
next tick, and when the cache passes budget it drops its least recently
used half, so a list that scrolls holds a bounded amount. A change of
fallbacks clears it, as does clear_cache. hits and misses count lookups.

Threads: a Shaper is not thread-safe; ui/shell shapes on the main thread
only, its compositor's workers draw glyph ids.
*/
package shape

import "core:hash/xxhash"
import "core:mem"
import "core:os"
import "core:slice"
import "core:strings"
import "jm:ui/ops"
import "jm:ui"
import "jm:ui/kb"

// Shaper holds the faces it has parsed and a kb context per font asked
// for. Zero it and call init before use; set refs before shaping.
Shaper :: struct {
	refs:      []ops.Font_Ref, // what faces are loaded from
	fallbacks: [dynamic]ops.Font_Id, // see set_fallbacks
	faces:     map[ops.Font_Id]^Face, // boxed: a context keeps each font's address
	// contexts holds, per font asked for, a kb context with the fallbacks
	// pushed under it, never popped: kb 2.28d's kbts_ShapePopFont casts
	// &Context->FontBlockSentinel.Prev, the pointer's own address, to the
	// last block (read it in ui/kb/vendor/kb_text_shape.h). nil when the
	// font does not load.
	contexts:  map[ops.Font_Id]^kb.Shape_Context,
	scratch:   [dynamic]ui.Shaped_Glyph, // text under construction, reused
	runs:      [dynamic]ui.Shaped_Run,
	breaks:    [dynamic]ui.Text_Break,
	allocator: ^mem.Allocator, // boxed: kb keeps a pointer to it
	cache:     map[Cache_Key]^Entry, // paragraphs shaped before, see the package doc
	bytes:     int, // what cache's entries hold
	budget:    int, // bytes cache may hold before it drops half; CACHE_BUDGET from init
	frame:     u64, // ticks so far
	seq:       u64, // cache uses so far, so the least recent is known
	hits:      int, // shape_text calls answered from cache
	misses:    int, // and those that shaped
}

// KEEP_FRAMES is how many whole frames a shaped paragraph outlives its
// last use: a label that leaves the view and is back within that many
// ticks is not shaped again; one away longer is dropped at the next tick.
KEEP_FRAMES :: 2

// CACHE_BUDGET is what init sets budget to, 16 MiB: a window of some three
// thousand labels holds 4 MiB (leita's, its debug tray open, 2026-10-16),
// so the budget is the bound for a frame loop that never ticks, not a
// trim a window meets.
CACHE_BUDGET :: 16 << 20

// Cache_Key names a shaping: the text's hash with the font and size that
// shaped it. The entry keeps the text, compared on every hit, so two
// texts of one hash never share glyphs.
@(private)
Cache_Key :: struct {
	font: ops.Font_Id,
	size: u32, // the f32's bits
	hash: u64,
}

// Entry is one shaped paragraph the cache owns, with when it was last
// used: the tick and the order among uses.
@(private)
Entry :: struct {
	text:   string,
	rtl:    bool,
	glyphs: []ui.Shaped_Glyph,
	runs:   []ui.Shaped_Run,
	breaks: []ui.Text_Break,
	frame:  u64,
	seq:    u64,
}

// Face is a parsed font file. ok is false when the file could not be read
// or parsed, so a bad id is tried once; kbts_FontIsValid is no test: its
// body is `return !Font->Error;`, which a zeroed font passes.
@(private)
Face :: struct {
	data:   []byte,
	font:   kb.Font,
	upem:   f32,
	weight: f32, // the ref's, set on the font as it is pushed
	ok:     bool,
}

// init prepares s; everything it holds allocates from allocator.
init :: proc(s: ^Shaper, allocator := context.allocator) {
	s.allocator = new_clone(allocator, allocator)
	s.faces = make(map[ops.Font_Id]^Face, allocator)
	s.contexts = make(map[ops.Font_Id]^kb.Shape_Context, allocator)
	s.fallbacks = make([dynamic]ops.Font_Id, allocator)
	s.scratch = make([dynamic]ui.Shaped_Glyph, allocator)
	s.runs = make([dynamic]ui.Shaped_Run, allocator)
	s.breaks = make([dynamic]ui.Text_Break, allocator)
	s.cache = make(map[Cache_Key]^Entry, allocator)
	s.budget = CACHE_BUDGET
}

// destroy releases every face and kb's context.
destroy :: proc(s: ^Shaper) {
	if s.allocator == nil {
		return
	}
	a := s.allocator^
	clear_cache(s)
	delete(s.cache)
	delete(s.breaks)
	drop_contexts(s)
	for _, f in s.faces {
		if f.ok {
			kb.FreeFont(&f.font)
		}
		delete(f.data, a)
		free(f, a)
	}
	delete(s.faces)
	delete(s.contexts)
	delete(s.fallbacks)
	delete(s.scratch)
	delete(s.runs)
	free(s.allocator, a)
	s^ = {}
}

// set_fallbacks makes fonts the ones tried, first to last, for a rune the
// font asked for lacks; the font asked for is always tried first.
set_fallbacks :: proc(s: ^Shaper, fonts: []ops.Font_Id) {
	same := len(fonts) == len(s.fallbacks)
	for f, i in fonts {
		same = same && s.fallbacks[i] == f
	}
	if same {
		return
	}
	drop_contexts(s)
	clear(&s.fallbacks)
	append(&s.fallbacks, ..fonts)
}

// drop_contexts destroys every context, to be made again on next use, and
// with them what was shaped through them.
@(private)
drop_contexts :: proc(s: ^Shaper) {
	clear_cache(s)
	for _, c in s.contexts {
		if c != nil {
			kb.DestroyShapeContext(c)
		}
	}
	clear(&s.contexts)
}

// context_for is font's kb context, its fallbacks pushed under it, made on
// first use; nil when font does not load.
@(private)
context_for :: proc(s: ^Shaper, font: ops.Font_Id) -> ^kb.Shape_Context {
	if c, ok := s.contexts[font]; ok {
		return c
	}
	primary := face(s, font)
	if primary == nil {
		s.contexts[font] = nil
		return nil
	}
	c := kb.CreateShapeContext(kb.allocator(s.allocator))
	// kb tries the top of its stack first (kb_text_shape.h, CONTEXT:FONT
	// HANDLING): the least preferred go in first, the font asked for last.
	#reverse for id in s.fallbacks {
		if f := face(s, id); f != nil && id != font {
			push_face(c, f)
		}
	}
	push_face(c, primary)
	s.contexts[font] = c
	return c
}

// push_face pushes f onto c at its weight: a variable font's advances and
// substitutions depend on it. kb applies a wght the font has no axis for
// to nothing, so a static font shapes as it always did.
@(private)
push_face :: proc(c: ^kb.Shape_Context, f: ^Face) {
	if f.weight == 0 {
		_ = kb.ShapePushFont(c, &f.font)
		return
	}
	wght := kb.Variation{kb.fourcc("wght"), f.weight}
	_ = kb.ShapePushFont2(c, &f.font, {wght})
}

// face_of is the id and face of the loaded font at address font, as a kb
// run names it.
@(private)
face_of :: proc(s: ^Shaper, font: ^kb.Font) -> (ops.Font_Id, ^Face, bool) {
	for id, f in s.faces {
		if &f.font == font {
			return id, f, true
		}
	}
	return 0, nil, false
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
			run.glyphs[k] = {g.id, g.cluster, pen + g.offset.x, g.offset.y, g.font}
			pen += g.advance
		}
	}
	run.advance = pen
	return run
}

// shape_text shapes UTF-8 text in font at size pixels as a paragraph for
// ui.paragraph_layout: kb's runs with their directions, the paragraph's
// direction, and kb's grapheme and line breaks, each glyph in the font it
// came from. Text is horizontal: a glyph's vertical advance is dropped. An
// unknown or unreadable font yields no glyphs, runs or breaks. A paragraph
// shaped before, in the same font at the same size, comes from the cache.
shape_text :: proc(s: ^Shaper, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ui.Shaped_Text {
	st := ui.Shaped_Text{font = font, size = size}
	if len(text) == 0 {
		return st
	}
	key := Cache_Key{font, transmute(u32)size, xxhash.XXH3_64(transmute([]u8)text)}
	if e := lookup(s, key, text); e != nil {
		s.hits += 1
		return copy_out(e, st, allocator)
	}
	c := context_for(s, font)
	if c == nil {
		return st
	}
	s.misses += 1
	rtl, ok := shape_runs(s, c, font, size, text)
	if !ok {
		return st
	}
	collect_breaks(s, c)
	return copy_out(store(s, key, text, rtl), st, allocator)
}

// shape_runs shapes text through c into s.scratch and s.runs, in logical
// order, and reports the paragraph's direction; ok is false when kb
// could not shape it.
@(private)
shape_runs :: proc(s: ^Shaper, c: ^kb.Shape_Context, font: ops.Font_Id, size: f32, text: string) -> (rtl, ok: bool) {
	kb.ShapeBegin(c, .Dont_Know, .Dont_Know)
	kb.ShapeUtf8(c, text, .Source_Index)
	kb.ShapeEnd(c)
	if kb.ShapeError(c) != .None {
		return false, false
	}

	clear(&s.scratch)
	clear(&s.runs)
	for {
		r: kb.Run
		if !kb.ShapeRun(c, &r) {
			break
		}
		if len(s.runs) == 0 {
			rtl = r.paragraph_direction == .RTL
		}
		id, f, known := face_of(s, r.font)
		if !known {
			id, f = font, face(s, font)
		}
		scale := size / f.upem
		first := len(s.scratch)
		g: ^kb.Glyph
		for kb.GlyphIteratorNext(&r.glyphs, &g) {
			cp: kb.Shape_Codepoint
			_ = kb.ShapeGetShapeCodepoint(c, g.user_id_or_codepoint_index, &cp)
			// Font units are y up, as OpenType's glyph space is.
			append(&s.scratch, ui.Shaped_Glyph{u32(g.id), u32(cp.user_id), f32(g.advance_x) * scale, {f32(g.offset_x) * scale, -f32(g.offset_y) * scale}, id})
		}
		if len(s.scratch) == first {
			continue
		}
		run_rtl := r.direction == .RTL
		if run_rtl {
			reverse(s.scratch[first:]) // kb mirrored it; clusters want logical order
		}
		append(&s.runs, ui.Shaped_Run{first = first, last = len(s.scratch), rtl = run_rtl})
	}
	merge_clusters(s.scratch[:])
	for &r, i in s.runs {
		r.start = int(s.scratch[r.first].cluster)
		r.end = int(s.scratch[s.runs[i + 1].first].cluster) if i + 1 < len(s.runs) else len(text)
	}
	if len(s.runs) > 0 {
		s.runs[0].start = 0
	}
	return rtl, true
}

// collect_breaks gathers the breaks of the text c last shaped into
// s.breaks.
@(private)
collect_breaks :: proc(s: ^Shaper, c: ^kb.Shape_Context) {
	clear(&s.breaks)
	cp: kb.Shape_Codepoint
	for i: i32 = 0; kb.ShapeGetShapeCodepoint(c, i, &cp); i += 1 {
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
		if .Word in cp.breaks {
			kinds += {.Word}
		}
		if kinds != {} {
			append(&s.breaks, ui.Text_Break{int(cp.user_id), kinds})
		}
	}
}

// lookup is the cached shaping of text under key, marked used now; nil
// when there is none. An entry of the same hash but another text goes,
// so its key is free for the text asked for.
@(private)
lookup :: proc(s: ^Shaper, key: Cache_Key, text: string) -> ^Entry {
	e, ok := s.cache[key]
	if !ok {
		return nil
	}
	if e.text != text {
		evict(s, key)
		return nil
	}
	touch(s, e)
	return e
}

// store keeps what shape_runs and collect_breaks left in s as text's
// shaping under key, trimming the cache when it passes its budget.
@(private)
store :: proc(s: ^Shaper, key: Cache_Key, text: string, rtl: bool) -> ^Entry {
	a := s.allocator^
	e := new(Entry, a)
	e.text = strings.clone(text, a)
	e.rtl = rtl
	e.glyphs = slice.clone(s.scratch[:], a)
	e.runs = slice.clone(s.runs[:], a)
	e.breaks = slice.clone(s.breaks[:], a)
	touch(s, e)
	s.cache[key] = e
	s.bytes += entry_bytes(e)
	if s.bytes > s.budget {
		trim(s)
	}
	return e
}

@(private)
touch :: proc(s: ^Shaper, e: ^Entry) {
	s.seq += 1
	e.seq = s.seq
	e.frame = s.frame
}

@(private)
entry_bytes :: proc(e: ^Entry) -> int {
	return size_of(Entry) + len(e.text) + len(e.glyphs) * size_of(ui.Shaped_Glyph) + len(e.runs) * size_of(ui.Shaped_Run) + len(e.breaks) * size_of(ui.Text_Break)
}

// copy_out is e as st for the caller, its slices from allocator.
@(private)
copy_out :: proc(e: ^Entry, st: ui.Shaped_Text, allocator: mem.Allocator) -> ui.Shaped_Text {
	st := st
	st.rtl = e.rtl
	st.glyphs = slice.clone(e.glyphs, allocator)
	st.runs = slice.clone(e.runs, allocator)
	st.breaks = slice.clone(e.breaks, allocator)
	return st
}

// tick ends a frame: an entry not used in the last KEEP_FRAMES whole
// frames is dropped.
tick :: proc(s: ^Shaper) {
	s.frame += 1
	if s.frame <= KEEP_FRAMES {
		return
	}
	stale := make([dynamic]Cache_Key, context.temp_allocator)
	for key, e in s.cache {
		if e.frame < s.frame - KEEP_FRAMES {
			append(&stale, key)
		}
	}
	for key in stale {
		evict(s, key)
	}
}

// trim drops the least recently used half of the cache's entries.
@(private)
trim :: proc(s: ^Shaper) {
	seqs := make([]u64, len(s.cache), context.temp_allocator)
	i := 0
	for _, e in s.cache {
		seqs[i] = e.seq
		i += 1
	}
	slice.sort(seqs)
	cutoff := seqs[len(seqs) / 2]
	stale := make([dynamic]Cache_Key, context.temp_allocator)
	for key, e in s.cache {
		if e.seq < cutoff {
			append(&stale, key)
		}
	}
	for key in stale {
		evict(s, key)
	}
}

// clear_cache drops every shaped paragraph, to be shaped again on next
// use: for when the faces behind the font ids change.
clear_cache :: proc(s: ^Shaper) {
	for _, e in s.cache {
		free_entry(s, e)
	}
	clear(&s.cache)
	s.bytes = 0
}

@(private)
evict :: proc(s: ^Shaper, key: Cache_Key) {
	e, ok := s.cache[key]
	if !ok {
		return
	}
	s.bytes -= entry_bytes(e)
	free_entry(s, e)
	delete_key(&s.cache, key)
}

@(private)
free_entry :: proc(s: ^Shaper, e: ^Entry) {
	a := s.allocator^
	delete(e.text, a)
	delete(e.glyphs, a)
	delete(e.runs, a)
	delete(e.breaks, a)
	free(e, a)
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
		return f if f.ok else nil
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
		f.weight = ref.weight
		f.ok = true
		break
	}
	return f if f.ok else nil
}
