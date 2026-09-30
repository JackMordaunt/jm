package ui

import "core:mem"
import "core:slice"
import "core:unicode"
import "core:unicode/utf8"
import "jm:ui/ops"

// A Paragraph is text broken into lines and each line put in visual
// order, ready to draw and to place a caret in.
//
// Lines break greedily at the shaper's soft breaks and always at hard ones
// (a newline). Whitespace at a line's end hangs past its edge and is not
// counted in its width. A word wider than the whole line breaks between
// graphemes rather than overflow.
//
// Within a line, runs are reordered by the Unicode bidi algorithm's rule
// L2, with each run's level taken from its direction alone: a right-to-left
// run is one level above a left-to-right paragraph, and a left-to-right run
// two above a right-to-left one. Nested embeddings and isolates beyond that
// are not modelled. A right-to-left paragraph's lines align to the right.
Paragraph :: struct {
	text:      string,
	font:      ops.Font_Id,
	size:      f32,
	metrics:   Font_Metrics,
	rtl:       bool,
	width:     f32, // the widest line, hanging whitespace excluded
	height:    f32,
	pitch:     f32, // from one line's top to the next
	lines:     []Text_Line,
	graphemes: []int, // where a caret may stop, ascending, len(text) included
}

// Text_Line is text[start:end] of its paragraph, end included in the next
// line's start. Positions are from the paragraph's top-left.
Text_Line :: struct {
	start, end: int,
	x:          f32, // where the line's first run starts
	baseline:   f32,
	width:      f32, // hanging whitespace excluded
	runs:       []Line_Run, // left to right
	hang:       int, // text[hang:end] is the whitespace and newline that hang
	// hanging are the clusters of the hanging whitespace before any
	// newline, in logical order, x0..x1 measured out from the line's end
	// edge (its right in a left-to-right paragraph, its left otherwise).
	hanging:    []Cluster_Span,
}

// Line_Run is one direction's glyphs within a line, drawn at the line's x
// plus x. clusters are in logical order, each spanning x0..x1 from the
// line's x.
Line_Run :: struct {
	glyphs:     ops.Glyph_Run,
	x:          f32,
	start, end: int,
	rtl:        bool,
	clusters:   []Cluster_Span,
}

Cluster_Span :: struct {
	start, end: int,
	x0, x1:     f32,
}

// paragraph_layout shapes text through s and breaks it into lines no wider
// than max_width (no limit when max_width <= 0), allocating from allocator.
// Lines are the font's line_height apart, its ascent from the top of each
// line to the baseline; a line_pitch > 0 instead makes each line that
// tall with the font's ascent and descent centred in it, as a type style's
// line box is.
paragraph_layout :: proc(s: Shaper, font: ops.Font_Id, size: f32, text: string, max_width: f32, allocator: mem.Allocator, line_pitch: f32 = 0) -> Paragraph {
	return paragraph_from_shaped(shape_text(s, font, size, text, allocator), metrics(s, font, size), text, max_width, allocator, line_pitch)
}

// paragraph_from_shaped lays out text already shaped as st; see
// paragraph_layout.
paragraph_from_shaped :: proc(st: Shaped_Text, m: Font_Metrics, text: string, max_width: f32, allocator: mem.Allocator, line_pitch: f32 = 0) -> Paragraph {
	p := Paragraph{text = text, font = st.font, size = st.size, metrics = m, rtl = st.rtl}
	l := Layout_State{st = st, text = text, max = max_width, allocator = allocator}
	l.sums = make([]f32, len(st.glyphs) + 1, context.temp_allocator)
	for g, i in st.glyphs {
		l.sums[i + 1] = l.sums[i] + g.advance
	}

	graphemes := make([dynamic]int, 0, len(st.breaks) + 1, allocator)
	for b in st.breaks {
		if .Grapheme in b.kinds {
			append(&graphemes, b.at)
		}
	}
	append(&graphemes, len(text))
	p.graphemes = graphemes[:]
	l.graphemes = p.graphemes

	lines := make([dynamic]Text_Line, allocator)
	start := 0
	for {
		end := next_line_end(&l, start)
		append(&lines, lay_line(&l, start, end))
		if end >= len(text) {
			break
		}
		start = end
	}
	if len(text) > 0 && text[len(text) - 1] == '\n' {
		append(&lines, lay_line(&l, len(text), len(text)))
	}
	p.lines = lines[:]

	p.pitch = line_pitch if line_pitch > 0 else line_height(m)
	above := (p.pitch - m.ascent - m.descent) / 2 + m.ascent if line_pitch > 0 else m.ascent
	for &ln, i in p.lines {
		p.width = max(p.width, ln.width)
		ln.baseline = f32(i) * p.pitch + above
	}
	p.height = f32(len(p.lines)) * p.pitch
	aligned := max_width if max_width > 0 else p.width
	if p.rtl {
		for &ln in p.lines {
			ln.x = aligned - ln.width
		}
	}
	return p
}

// paragraph_draw draws p with its top-left at origin.
paragraph_draw :: proc(sc: ^ops.Scene, p: Paragraph, origin: ops.Point, color: ops.Color) {
	for ln in p.lines {
		for r in ln.runs {
			if len(r.glyphs.glyphs) > 0 {
				ops.glyphs(sc, ops.add_run(sc, r.glyphs), {origin.x + ln.x + r.x, origin.y + ln.baseline}, color)
			}
		}
	}
}

// paragraph_caret is where a caret at byte offset i stands: the line it is
// on and its x from the paragraph's left. An offset where a line wraps is
// the start of the next line.
paragraph_caret :: proc(p: Paragraph, i: int) -> (line: int, x: f32) {
	line = paragraph_line_of(p, i)
	return line, line_caret_x(p, line, i)
}

// paragraph_selection_rects is where to highlight the text between byte
// offsets lo and hi, as rects from the paragraph's top-left, each a whole
// line box tall: per line, one rect per visually contiguous stretch, so a
// selection across a change of direction is split as it reads. A partly
// selected ligature is cut at its runes' share of its width. Selected
// whitespace hanging past a line's edge is included, and a selected
// newline shows as a quarter-em stub at the line's end edge, so selecting
// across a line end is visible. Allocated from allocator.
paragraph_selection_rects :: proc(p: Paragraph, lo, hi: int, allocator := context.temp_allocator) -> []ops.Rect {
	out := make([dynamic]ops.Rect, 0, 4, allocator)
	if hi <= lo {
		return out[:]
	}
	spans := make([dynamic][2]f32, 0, 8, context.temp_allocator)
	for ln, k in p.lines {
		if hi <= ln.start || lo >= max(ln.end, ln.start + 1) {
			continue
		}
		clear(&spans)
		for r in ln.runs {
			for c in r.clusters {
				a, b := max(lo, c.start), min(hi, c.end)
				if a >= b {
					continue
				}
				fa := cluster_fraction(p.text[c.start:c.end], a - c.start)
				fb := cluster_fraction(p.text[c.start:c.end], b - c.start)
				x0, x1 := c.x0 + (c.x1 - c.x0) * fa, c.x0 + (c.x1 - c.x0) * fb
				if r.rtl {
					x0, x1 = c.x1 - (c.x1 - c.x0) * fb, c.x1 - (c.x1 - c.x0) * fa
				}
				append(&spans, [2]f32{ln.x + x0, ln.x + x1})
			}
		}
		// Hanging whitespace, measured out from the end edge.
		for c in ln.hanging {
			a, b := max(lo, c.start), min(hi, c.end)
			if a >= b {
				continue
			}
			d0 := c.x0 + (c.x1 - c.x0) * cluster_fraction(p.text[c.start:c.end], a - c.start)
			d1 := c.x0 + (c.x1 - c.x0) * cluster_fraction(p.text[c.start:c.end], b - c.start)
			if p.rtl {
				append(&spans, [2]f32{ln.x - d1, ln.x - d0})
			} else {
				append(&spans, [2]f32{ln.x + ln.width + d0, ln.x + ln.width + d1})
			}
		}
		// A selected newline: a stub past everything else on the line.
		if e := line_content_end(p.text, ln); e < ln.end && lo < ln.end && hi > e {
			stub := p.size * 0.25
			hang: f32
			for c in ln.hanging {
				hang = max(hang, c.x1)
			}
			if p.rtl {
				append(&spans, [2]f32{ln.x - hang - stub, ln.x - hang})
			} else {
				append(&spans, [2]f32{ln.x + ln.width + hang, ln.x + ln.width + hang + stub})
			}
		}
		slice.sort_by(spans[:], proc(a, b: [2]f32) -> bool {return a[0] < b[0]})
		top := f32(k) * p.pitch
		i := 0
		for i < len(spans) {
			x0, x1 := spans[i][0], spans[i][1]
			i += 1
			for i < len(spans) && spans[i][0] <= x1 + 0.5 {
				x1 = max(x1, spans[i][1])
				i += 1
			}
			append(&out, ops.Rect{x0, top, x1 - x0, p.pitch})
		}
	}
	return out[:]
}

// paragraph_line_of is the line a caret at byte offset i is on.
paragraph_line_of :: proc(p: Paragraph, i: int) -> int {
	for ln, k in p.lines {
		if i < ln.end || k == len(p.lines) - 1 {
			return k
		}
	}
	return 0
}

// paragraph_line_end is the last caret stop on line k, where End puts the
// caret: the text's end on the last line, before the newline on a line a
// newline ends, and before the hanging whitespace on a wrapped line, whose
// end is already the next line's start.
paragraph_line_end :: proc(p: Paragraph, k: int) -> int {
	ln := p.lines[k]
	if k == len(p.lines) - 1 {
		return ln.end
	}
	if e := line_content_end(p.text, ln); e < ln.end {
		return e
	}
	return ln.hang
}

// paragraph_hit is the caret stop nearest pos, a point from the
// paragraph's top-left: on the line pos is level with, clamped to the
// first or last.
paragraph_hit :: proc(p: Paragraph, pos: ops.Point) -> int {
	if len(p.lines) == 0 {
		return 0
	}
	k := clamp(int(pos.y / p.pitch) if p.pitch > 0 else 0, 0, len(p.lines) - 1)
	ln := p.lines[k]
	last := ln.end if k == len(p.lines) - 1 else line_content_end(p.text, ln)
	best, best_d := ln.start, max(f32)
	lo, _ := slice.binary_search(p.graphemes, ln.start)
	for g in p.graphemes[lo:] {
		if g > last {
			break
		}
		if d := abs(line_caret_x(p, k, g) - pos.x); d < best_d {
			best, best_d = g, d
		}
	}
	return best
}

// line_caret_x is the x of a caret at byte offset i on line k, i within
// the line or at its end.
@(private)
line_caret_x :: proc(p: Paragraph, k: int, i: int) -> f32 {
	ln := p.lines[k]
	if i == ln.hang && ln.hang > ln.start {
		// Just after the last visible cluster: its trailing edge, which
		// is its left in a right-to-left run.
		for r in ln.runs {
			for c in r.clusters {
				if c.start < i && i <= c.end {
					return ln.x + (c.x0 if r.rtl else c.x1)
				}
			}
		}
	}
	if i >= ln.hang {
		// Hanging whitespace runs on past the line's end edge.
		d: f32
		for c in ln.hanging {
			if i < c.end {
				d = c.x0 + (c.x1 - c.x0) * cluster_fraction(p.text[c.start:c.end], i - c.start)
				break
			}
			d = c.x1
		}
		return ln.x - d if p.rtl else ln.x + ln.width + d
	}
	for r in ln.runs {
		if i < r.start || i >= r.end {
			continue
		}
		for c in r.clusters {
			if i < c.start || i >= c.end {
				continue
			}
			f := cluster_fraction(p.text[c.start:c.end], i - c.start)
			return ln.x + (c.x1 - (c.x1 - c.x0) * f if r.rtl else c.x0 + (c.x1 - c.x0) * f)
		}
	}
	return ln.x
}

// line_content_end is where line ln's text ends before a hard break.
@(private)
line_content_end :: proc(text: string, ln: Text_Line) -> int {
	e := ln.end
	for e > ln.start && (text[e - 1] == '\n' || text[e - 1] == '\r') {
		e -= 1
	}
	return e
}

@(private)
Layout_State :: struct {
	st:        Shaped_Text,
	text:      string,
	max:       f32,
	sums:      []f32, // sums[k] is the advance of glyphs[:k]
	graphemes: []int,
	allocator: mem.Allocator,
}

// glyph_at is the first glyph whose cluster is at or after byte offset i.
@(private)
glyph_at :: proc(l: ^Layout_State, i: int) -> int {
	k, _ := slice.binary_search_by(l.st.glyphs, i, proc(g: Shaped_Glyph, i: int) -> slice.Ordering {
		return .Less if int(g.cluster) < i else .Greater
	})
	return k
}

// visible_width is the advance of text[start:end] less its trailing
// whitespace.
@(private)
visible_width :: proc(l: ^Layout_State, start, end: int) -> f32 {
	e := trim_hang(l.text, start, end)
	return l.sums[glyph_at(l, e)] - l.sums[glyph_at(l, start)]
}

// trim_hang is end moved back over trailing whitespace and newlines.
@(private)
trim_hang :: proc(text: string, start, end: int) -> int {
	e := end
	for e > start {
		r, n := utf8.decode_last_rune_in_string(text[start:e])
		if !unicode.is_white_space(r) {
			break
		}
		e -= n
	}
	return e
}

@(private)
fits :: proc(l: ^Layout_State, start, end: int) -> bool {
	return l.max <= 0 || visible_width(l, start, end) <= l.max
}

// next_line_end is where the line starting at start ends: at a hard break,
// at the last soft break that fits, or, when not even the first word fits,
// at the last grapheme that does.
@(private)
next_line_end :: proc(l: ^Layout_State, start: int) -> int {
	n := len(l.text)
	fit := -1
	lo, _ := slice.binary_search_by(l.st.breaks, start + 1, proc(b: Text_Break, at: int) -> slice.Ordering {
		return .Less if b.at < at else .Greater
	})
	for k := lo; k <= len(l.st.breaks); k += 1 {
		at, hard, soft := n, true, false
		if k < len(l.st.breaks) {
			b := l.st.breaks[k]
			at, hard, soft = b.at, .Line_Hard in b.kinds, .Line_Soft in b.kinds
		}
		if !hard && !soft {
			continue
		}
		if fits(l, start, at) {
			if hard {
				return at
			}
			fit = at
			continue
		}
		if fit > start {
			return fit
		}
		return grapheme_break(l, start, at)
	}
	return n
}

// grapheme_break is the last grapheme boundary before limit that keeps
// text[start:] within the line, or the first after start when none does.
@(private)
grapheme_break :: proc(l: ^Layout_State, start, limit: int) -> int {
	lo, _ := slice.binary_search(l.graphemes, start + 1)
	best := -1
	for g in l.graphemes[lo:] {
		if g >= limit {
			break
		}
		if !fits(l, start, g) {
			break
		}
		best = g
	}
	if best > start {
		return best
	}
	return l.graphemes[lo] if lo < len(l.graphemes) else limit
}

// lay_line places text[start:end] as one line: its runs cut to the line,
// put in visual order and positioned left to right.
@(private)
lay_line :: proc(l: ^Layout_State, start, end: int) -> Text_Line {
	ln := Text_Line{start = start, end = end, hang = trim_hang(l.text, start, end)}
	Piece :: struct {
		run:   Shaped_Run,
		level: int,
	}
	pieces := make([dynamic]Piece, 0, 4, context.temp_allocator)
	for r in l.st.runs {
		a, b := max(r.start, start), min(r.end, ln.hang)
		if a >= b {
			continue
		}
		cut := Shaped_Run{glyph_at(l, a), glyph_at(l, b), a, b, r.rtl}
		level := (1 if r.rtl else 0) if !l.st.rtl else (1 if r.rtl else 2)
		append(&pieces, Piece{cut, level})
	}
	// L2: from the highest level down to the lowest odd one, reverse every
	// maximal sequence at that level or above.
	top, low_odd := 0, max(int)
	for pc in pieces {
		top = max(top, pc.level)
		if pc.level % 2 == 1 {
			low_odd = min(low_odd, pc.level)
		}
	}
	for level := top; level >= low_odd && level > 0; level -= 1 {
		for i := 0; i < len(pieces); {
			if pieces[i].level < level {
				i += 1
				continue
			}
			j := i
			for j < len(pieces) && pieces[j].level >= level {
				j += 1
			}
			slice.reverse(pieces[i:j])
			i = j
		}
	}

	ln.runs = make([]Line_Run, len(pieces), l.allocator)
	x: f32
	for pc, i in pieces {
		ln.runs[i] = place_run(l, pc.run, x)
		x += run_advance(l, pc.run)
	}
	ln.width = x
	ln.hanging = hanging_clusters(l, ln.hang, line_content_end(l.text, ln))
	return ln
}

// hanging_clusters measures the clusters of text[start:end] as distances
// from where they begin.
@(private)
hanging_clusters :: proc(l: ^Layout_State, start, end: int) -> []Cluster_Span {
	out := make([dynamic]Cluster_Span, 0, 2, l.allocator)
	first, last := glyph_at(l, start), glyph_at(l, end)
	for k := first; k < last; {
		c := int(l.st.glyphs[k].cluster)
		j := k
		for j < last && int(l.st.glyphs[j].cluster) == c {
			j += 1
		}
		cend := int(l.st.glyphs[j].cluster) if j < last else end
		append(&out, Cluster_Span{max(c, start), cend, l.sums[k] - l.sums[first], l.sums[j] - l.sums[first]})
		k = j
	}
	return out[:]
}

@(private)
run_advance :: proc(l: ^Layout_State, r: Shaped_Run) -> f32 {
	return l.sums[r.last] - l.sums[r.first]
}

// place_run lays glyphs[r.first:r.last] out from line x, in visual order,
// and measures each cluster's span.
@(private)
place_run :: proc(l: ^Layout_State, r: Shaped_Run, x: f32) -> Line_Run {
	n := r.last - r.first
	out := Line_Run{x = x, start = r.start, end = r.end, rtl = r.rtl}
	out.glyphs = {font = l.st.font, size = l.st.size, glyphs = make([]ops.Glyph, n, l.allocator)}
	clusters := make([dynamic]Cluster_Span, 0, n, l.allocator)
	pen: f32
	for v in 0 ..< n {
		k := r.first + (n - 1 - v if r.rtl else v) // logical index of the v-th glyph from the left
		g := l.st.glyphs[k]
		out.glyphs.glyphs[v] = {g.id, g.cluster, pen + g.offset.x, g.offset.y, g.font}
		pen += g.advance
	}
	out.glyphs.advance = pen
	// Clusters in logical order; each spans the glyphs that share it.
	for k := r.first; k < r.last; {
		c := int(l.st.glyphs[k].cluster)
		j := k
		for j < r.last && int(l.st.glyphs[j].cluster) == c {
			j += 1
		}
		cend := int(l.st.glyphs[j].cluster) if j < r.last else r.end
		// The glyphs of logical range [k, j) sit at visual positions
		// counted from the left: forward in an ltr run, from the end in an
		// rtl one.
		lo_v, hi_v := k - r.first, j - r.first
		if r.rtl {
			lo_v, hi_v = n - hi_v, n - lo_v
		}
		x0 := l.sums[r.first + lo_v] - l.sums[r.first] if !r.rtl else rtl_pen(l, r, lo_v)
		x1 := l.sums[r.first + hi_v] - l.sums[r.first] if !r.rtl else rtl_pen(l, r, hi_v)
		append(&clusters, Cluster_Span{max(c, r.start), cend, x + x0, x + x1})
		k = j
	}
	out.clusters = clusters[:]
	return out
}

// rtl_pen is the pen x after the first v glyphs from the left of rtl run
// r: the advance of its last v glyphs in logical order.
@(private)
rtl_pen :: proc(l: ^Layout_State, r: Shaped_Run, v: int) -> f32 {
	return l.sums[r.last] - l.sums[r.last - v]
}
