package shape

import "core:testing"
import "jm:ui/ops"

when ODIN_OS == .Windows {
	@(private = "file")
	FONT :: "C:/Windows/Fonts/arial.ttf"
} else when ODIN_OS == .Darwin {
	@(private = "file")
	FONT :: "/System/Library/Fonts/Supplemental/Arial.ttf"
} else {
	@(private = "file")
	FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}

@(test)
test_shape_clusters_are_byte_offsets :: proc(t: ^testing.T) {
	s: Shaper
	init(&s)
	defer destroy(&s)
	refs := []ops.Font_Ref{{0, FONT}}
	s.refs = refs
	run := shape(&s, 0, 20, "é€a", context.allocator)
	defer delete(run.glyphs)
	testing.expect_value(t, len(run.glyphs), 3)
	for want, i in ([]u32{0, 2, 5}) {
		testing.expect_value(t, run.glyphs[i].cluster, want)
	}
	testing.expect(t, run.advance > 0)
	for g in run.glyphs {
		testing.expect(t, g.id != 0, "a glyph the font has")
	}
}

@(test)
test_shape_composes_marks :: proc(t: ^testing.T) {
	// kb normalises e + U+0301 to é, which the font has: one glyph for the
	// cluster of both runes.
	s: Shaper
	init(&s)
	defer destroy(&s)
	refs := []ops.Font_Ref{{0, FONT}}
	s.refs = refs
	run := shape(&s, 0, 20, "e\u0301x", context.allocator)
	defer delete(run.glyphs)
	testing.expect_value(t, len(run.glyphs), 2)
	testing.expect_value(t, run.glyphs[1].cluster, 3)
}

@(test)
test_shape_unknown_font :: proc(t: ^testing.T) {
	s: Shaper
	init(&s)
	defer destroy(&s)
	run := shape(&s, 7, 20, "hi", context.allocator)
	testing.expect_value(t, len(run.glyphs), 0)
	testing.expect_value(t, run.advance, 0)
}

@(test)
test_merge_clusters :: proc(t: ^testing.T) {
	// A Devanagari pre-base matra (cluster 3) drawn before its consonant
	// (cluster 0) joins the consonant's cluster.
	gs := []ops.Glyph{{1, 3, 0, 0}, {2, 0, 5, 0}, {3, 6, 9, 0}}
	merge_clusters(gs)
	for want, i in ([]u32{0, 0, 6}) {
		testing.expect_value(t, gs[i].cluster, want)
	}
}

@(test)
test_reverse :: proc(t: ^testing.T) {
	gs := []ops.Glyph{{1, 4, 0, 0}, {2, 2, 5, 0}, {3, 0, 9, 0}}
	reverse(gs)
	for want, i in ([]u32{0, 2, 4}) {
		testing.expect_value(t, gs[i].cluster, want)
	}
}
