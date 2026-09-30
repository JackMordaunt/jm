package ui

import "core:mem"
import "core:unicode/utf8"
import "jm:ui/ops"

// Text is shaped in layout and rasterized in the renderer. The op buffer
// carries glyph runs, never strings, so a renderer needs the font file and
// nothing else. Shaper is the seam: ui/render implements it over Blend2D's
// font_shape; tests use stub_shaper.

Font_Metrics :: struct {
	ascent:   f32, // above the baseline, positive
	descent:  f32, // below the baseline, positive
	line_gap: f32,
}

Shaper :: struct {
	data:    rawptr,
	shape:   proc(data: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run,
	metrics: proc(data: rawptr, font: ops.Font_Id, size: f32) -> Font_Metrics,
}

shape :: proc(s: Shaper, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
	return s.shape(s.data, font, size, text, allocator)
}

metrics :: proc(s: Shaper, font: ops.Font_Id, size: f32) -> Font_Metrics {
	return s.metrics(s.data, font, size)
}

// line_height is ascent + descent + line_gap.
line_height :: proc(m: Font_Metrics) -> f32 {
	return m.ascent + m.descent + m.line_gap
}

// caret_x is the pen x of byte offset i in run, which a shaper made from
// text; i must sit on a rune boundary. A caret between the runes of one
// cluster (inside a ligature) is spread evenly across the cluster's width.
// Glyph x includes the shaper's placement offset, so a cluster whose first
// glyph is nudged moves its caret with it. Left-to-right text only.
caret_x :: proc(run: ops.Glyph_Run, text: string, i: int) -> f32 {
	if i >= len(text) {
		return run.advance
	}
	g := 0
	lo := 0
	for {
		hi, x0, x1, ok := next_cluster(run, len(text), &g)
		if !ok {
			return run.advance
		}
		if i < hi {
			return x0 + (x1 - x0) * cluster_fraction(text[lo:hi], i - lo)
		}
		lo = hi
	}
}

// caret_at is the rune boundary in text nearest x, where run was shaped
// from text: the inverse of caret_x.
caret_at :: proc(run: ops.Glyph_Run, text: string, x: f32) -> int {
	best, best_d := 0, abs(x)
	g := 0
	lo := 0
	for {
		hi, x0, x1, ok := next_cluster(run, len(text), &g)
		if !ok {
			break
		}
		for _, j in text[lo:hi] {
			cx := x0 + (x1 - x0) * cluster_fraction(text[lo:hi], j)
			if d := abs(x - cx); d < best_d {
				best, best_d = lo + j, d
			}
		}
		lo = hi
	}
	if abs(x - run.advance) < best_d {
		best = len(text)
	}
	return best
}

// next_cluster steps g past the glyphs of one cluster and returns where
// the next cluster starts in the text (n at the end) and the pen x span
// the cluster covers. ok is false once the glyphs run out.
@(private = "file")
next_cluster :: proc(run: ops.Glyph_Run, n: int, g: ^int) -> (hi: int, x0, x1: f32, ok: bool) {
	if g^ >= len(run.glyphs) {
		return
	}
	first := run.glyphs[g^]
	g^ += 1
	for g^ < len(run.glyphs) && run.glyphs[g^].cluster <= first.cluster {
		g^ += 1
	}
	if g^ < len(run.glyphs) {
		next := run.glyphs[g^]
		return int(next.cluster), first.x, next.x, true
	}
	return n, first.x, run.advance, true
}

// cluster_fraction is how far through cluster byte offset j lies, counted
// in runes.
@(private = "file")
cluster_fraction :: proc(cluster: string, j: int) -> f32 {
	before := utf8.rune_count(cluster[:j])
	return f32(before) / f32(max(utf8.rune_count(cluster), 1))
}

// stub_shaper is a deterministic monospace shaper for tests and dumps:
// every rune advances 0.6*size and is its own cluster, glyph id is the
// rune, ascent is 0.8*size, descent 0.2*size, no line gap.
stub_shaper :: proc() -> Shaper {
	return {
		shape = proc(_: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
			n := 0
			for _ in text {
				n += 1
			}
			gs := make([]ops.Glyph, n, allocator)
			x: f32
			i := 0
			for r, at in text {
				gs[i] = {u32(r), u32(at), x, 0}
				x += 0.6 * size
				i += 1
			}
			return {font, size, gs, x}
		},
		metrics = proc(_: rawptr, _: ops.Font_Id, size: f32) -> Font_Metrics {
			return {0.8 * size, 0.2 * size, 0}
		},
	}
}
