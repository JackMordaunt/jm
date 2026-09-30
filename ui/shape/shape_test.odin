package shape

import "core:testing"
import "jm:ui"
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
	gs := []ui.Shaped_Glyph{{1, 3, 6, {}, 0}, {2, 0, 6, {}, 0}, {3, 6, 6, {}, 0}}
	merge_clusters(gs)
	for want, i in ([]u32{0, 0, 6}) {
		testing.expect_value(t, gs[i].cluster, want)
	}
}

@(test)
test_reverse :: proc(t: ^testing.T) {
	gs := []ui.Shaped_Glyph{{1, 4, 6, {}, 0}, {2, 2, 6, {}, 0}, {3, 0, 6, {}, 0}}
	reverse(gs)
	for want, i in ([]u32{0, 2, 4}) {
		testing.expect_value(t, gs[i].cluster, want)
	}
}

@(test)
test_shape_text_directions_and_breaks :: proc(t: ^testing.T) {
	s: Shaper
	init(&s)
	defer destroy(&s)
	refs := []ops.Font_Ref{{0, FONT}}
	s.refs = refs
	text := "ab שלום cd" // ab שלום cd: Hebrew is 2 bytes a letter
	st := shape_text(&s, 0, 20, text, context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect(t, !st.rtl, "the paragraph starts left to right")

	rtl_run := -1
	for r, i in st.runs {
		if r.rtl {
			rtl_run = i
		}
	}
	if testing.expect(t, rtl_run >= 0, "a right-to-left run") {
		r := st.runs[rtl_run]
		testing.expect_value(t, r.start, 3)
		// Its glyphs are back in logical order: clusters rise.
		for k in r.first + 1 ..< r.last {
			testing.expect(t, st.glyphs[k].cluster >= st.glyphs[k - 1].cluster)
		}
	}

	soft: [dynamic]int
	soft.allocator = context.temp_allocator
	for b in st.breaks {
		if .Line_Soft in b.kinds {
			append(&soft, b.at)
		}
	}
	testing.expect_value(t, len(soft), 2)
	if len(soft) == 2 {
		testing.expect_value(t, soft[0], 3) // before ש
		testing.expect_value(t, soft[1], 12) // before c
	}
}

// ASCII is Liberation Sans cut down to printable ASCII (OFL, renamed as
// the licence asks of a modified font; see testdata/LICENSE): a font that
// certainly lacks é, with FONT behind it certainly having it.
@(private = "file")
ASCII :: #directory + "/testdata/ascii.ttf"

@(test)
test_shape_falls_back :: proc(t: ^testing.T) {
	s: Shaper
	init(&s)
	defer destroy(&s)
	refs := []ops.Font_Ref{{0, ASCII}, {1, FONT}}
	s.refs = refs
	defer free_all(context.temp_allocator)

	alone := shape(&s, 0, 20, "a\u00e9", context.temp_allocator)
	testing.expect_value(t, len(alone.glyphs), 2)
	testing.expect_value(t, alone.glyphs[1].id, 0) // no é without a fallback

	set_fallbacks(&s, {1})
	run := shape(&s, 0, 20, "a\u00e9", context.temp_allocator)
	testing.expect_value(t, len(run.glyphs), 2)
	testing.expect_value(t, run.glyphs[0].font, 0)
	testing.expect_value(t, run.glyphs[1].font, 1)
	testing.expect(t, run.glyphs[1].id != 0, "the fallback's glyph for é")
}
