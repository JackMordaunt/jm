package shape

import "core:fmt"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:slice"
import "core:testing"
import harness "jm:fuzz"
import "jm:ui"
import "jm:ui/ops"
import "jm:ui/testutil"

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
	refs := []ops.Font_Ref{{id = 0, path = FONT}}
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
	refs := []ops.Font_Ref{{id = 0, path = FONT}}
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
	refs := []ops.Font_Ref{{id = 0, path = FONT}}
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
	refs := []ops.Font_Ref{{id = 0, path = ASCII}, {id = 1, path = FONT}}
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

// A variable font shapes wider at 700 than at 400: the fixture (see
// testutil.variable_font) everywhere, and macOS's SFNS where it is.
@(test)
test_shape_variable_font_at_its_weight :: proc(t: ^testing.T) {
	os.make_directory("build/test")
	fixture := "build/test/shape-wght.ttf"
	defer os.remove(fixture)
	testing.expect(t, testutil.variable_font(fixture), "write the variable fixture")
	regular, bold := advances_at(fixture, 400, 700)
	// wght 700 is 0.6 of the way to 900, where the fixture is 25% wider.
	want := regular * (1 + 0.6 * testutil.VARIABLE_STRETCH)
	testing.expectf(t, abs(bold - want) < 1, "700 advance %v, want %v", bold, want)
	if os.exists(testutil.SFNS) {
		regular, bold = advances_at(testutil.SFNS, 400, 700)
		testing.expectf(t, bold > regular, "SFNS 700 advance %v, 400 advance %v", bold, regular)
	}
}

// advances_at is how far "Primer weights" advances in the font at path at
// two weights.
@(private = "file")
advances_at :: proc(path: string, light, heavy: f32) -> (f32, f32) {
	s: Shaper
	init(&s)
	defer destroy(&s)
	refs := []ops.Font_Ref{{id = 0, path = path, weight = light}, {id = 1, path = path, weight = heavy}}
	s.refs = refs
	defer free_all(context.temp_allocator)
	a := shape(&s, 0, 32, "Primer weights", context.temp_allocator)
	b := shape(&s, 1, 32, "Primer weights", context.temp_allocator)
	return a.advance, b.advance
}

@(test)
test_shape_static_font_ignores_weight :: proc(t: ^testing.T) {
	s: Shaper
	init(&s)
	defer destroy(&s)
	refs := []ops.Font_Ref{{id = 0, path = ASCII}, {id = 1, path = ASCII, weight = 600}}
	s.refs = refs
	defer free_all(context.temp_allocator)
	plain := shape(&s, 0, 20, "Weight", context.temp_allocator)
	weighted := shape(&s, 1, 20, "Weight", context.temp_allocator)
	testing.expect(t, len(weighted.glyphs) > 0, "a static font at a weight still shapes")
	testing.expect_value(t, weighted.advance, plain.advance)
}

// TWICE is FONT under two ids, so a face can differ while the file does not.
@(private = "file")
TWICE := []ops.Font_Ref{{id = 0, path = FONT}, {id = 1, path = FONT}}

// arial is a Shaper over TWICE, its cache empty.
@(private = "file")
arial :: proc(s: ^Shaper) {
	init(s)
	s.refs = TWICE
}

@(test)
test_shape_text_again_comes_from_the_cache :: proc(t: ^testing.T) {
	s: Shaper
	arial(&s)
	defer destroy(&s)
	defer free_all(context.temp_allocator)
	first := shape_text(&s, 0, 20, "office", context.temp_allocator)
	again := shape_text(&s, 0, 20, "office", context.temp_allocator)
	testing.expect_value(t, s.misses, 1)
	testing.expect_value(t, s.hits, 1)
	testing.expect(t, same_shaping(first, again), "the cached shaping is the first one")
	testing.expect(t, raw_data(first.glyphs) != raw_data(again.glyphs), "each call gets its own copy")
	testing.expect_value(t, len(s.cache), 1)
	testing.expect(t, s.bytes > 0 && s.bytes < 1024, "one word holds under a kilobyte")
}

@(test)
test_shape_text_misses_at_another_size_or_face :: proc(t: ^testing.T) {
	s: Shaper
	arial(&s)
	defer destroy(&s)
	defer free_all(context.temp_allocator)
	_ = shape_text(&s, 0, 20, "office", context.temp_allocator)
	_ = shape_text(&s, 0, 21, "office", context.temp_allocator)
	_ = shape_text(&s, 1, 20, "office", context.temp_allocator)
	_ = shape_text(&s, 0, 20, "officer", context.temp_allocator)
	testing.expect_value(t, s.misses, 4)
	testing.expect_value(t, s.hits, 0)
}

// Wrapping is paragraph_from_shaped's pass over the shaped text, so a
// paragraph laid out at another width is shaped from the cache.
@(test)
test_paragraph_width_is_not_in_the_key :: proc(t: ^testing.T) {
	s: Shaper
	arial(&s)
	defer destroy(&s)
	defer free_all(context.temp_allocator)
	sh := ui.Shaper {
		data = &s,
		shape_text = proc(data: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ui.Shaped_Text {
			return shape_text((^Shaper)(data), font, size, text, allocator)
		},
		metrics = proc(_: rawptr, _: ops.Font_Id, size: f32) -> ui.Font_Metrics {
			return {0.8 * size, 0.2 * size, 0}
		},
	}
	text := "one two three four five six"
	wide := ui.paragraph_layout(sh, 0, 20, text, 1000, context.temp_allocator)
	narrow := ui.paragraph_layout(sh, 0, 20, text, 60, context.temp_allocator)
	testing.expect_value(t, len(wide.lines), 1)
	testing.expect(t, len(narrow.lines) > 1, "the narrow width wraps")
	testing.expect_value(t, s.misses, 1)
	testing.expect_value(t, s.hits, 1)
}

@(test)
test_cache_drops_what_frames_went_by_without :: proc(t: ^testing.T) {
	s: Shaper
	arial(&s)
	defer destroy(&s)
	defer free_all(context.temp_allocator)
	_ = shape_text(&s, 0, 20, "stays", context.temp_allocator)
	_ = shape_text(&s, 0, 20, "goes", context.temp_allocator)
	for _ in 0 ..< KEEP_FRAMES {
		tick(&s)
		_ = shape_text(&s, 0, 20, "stays", context.temp_allocator)
		testing.expect_value(t, len(s.cache), 2) // within its frames, goes is kept
	}
	tick(&s)
	testing.expect_value(t, len(s.cache), 1)
	_ = shape_text(&s, 0, 20, "stays", context.temp_allocator)
	_ = shape_text(&s, 0, 20, "goes", context.temp_allocator)
	testing.expect_value(t, s.hits, KEEP_FRAMES + 1)
	testing.expect_value(t, s.misses, 3)
}

@(test)
test_cache_holds_to_its_budget :: proc(t: ^testing.T) {
	s: Shaper
	arial(&s)
	defer destroy(&s)
	defer free_all(context.temp_allocator)
	s.budget = 4096
	most := 0
	for i in 0 ..< 200 {
		_ = shape_text(&s, 0, 20, fmt.tprintf("row %d of the list", i), context.temp_allocator)
		most = max(most, s.bytes)
	}
	testing.expect_value(t, s.misses, 200)
	testing.expectf(t, most <= s.budget + 512, "held %d bytes against a budget of %d", most, s.budget)
	testing.expect(t, len(s.cache) > 0 && len(s.cache) < 200, "some rows kept, not all")
	_ = shape_text(&s, 0, 20, "row 199 of the list", context.temp_allocator)
	testing.expect_value(t, s.hits, 1) // the most recent survives a trim
}

@(test)
test_cache_clears_when_the_fallbacks_change :: proc(t: ^testing.T) {
	s: Shaper
	arial(&s)
	defer destroy(&s)
	defer free_all(context.temp_allocator)
	_ = shape_text(&s, 0, 20, "office", context.temp_allocator)
	set_fallbacks(&s, {1})
	testing.expect_value(t, len(s.cache), 0)
	testing.expect_value(t, s.bytes, 0)
	_ = shape_text(&s, 0, 20, "office", context.temp_allocator)
	testing.expect_value(t, s.misses, 2)
	clear_cache(&s)
	testing.expect_value(t, len(s.cache), 0)
}

// PIECES are what the property test's strings are built of: letters,
// spaces and breaks, scripts of both directions, a combining mark, a
// Devanagari syllable that reorders, and an emoji the font lacks.
@(private = "file")
PIECES := []string{"a", "office", " ", "\n", "\t", "fi", "שלום", "مرحبا", "e\u0301", "कि", "日本", "\U0001F600", "-", "1"}

// Whatever the text, the shaping that comes back from the cache is the one
// kb made: glyphs, runs, breaks and direction alike, through shape_text
// and through shape.
@(test)
test_cached_shaping_is_the_uncached_shaping :: proc(t: ^testing.T) {
	cached, fresh: Shaper
	arial(&cached)
	arial(&fresh)
	defer destroy(&cached)
	defer destroy(&fresh)
	set_fallbacks(&cached, {1})
	set_fallbacks(&fresh, {1})
	r := rand.create(7)
	context.random_generator = rand.default_random_generator(&r)
	for i in 0 ..< 300 {
		defer free_all(context.temp_allocator)
		bytes := make([]byte, 64, context.temp_allocator)
		_ = rand.read(bytes)
		src := harness.source(bytes)
		text := harness.text(&src, PIECES, 12, context.temp_allocator)
		size := f32(harness.integer_in(&src, 8, 40))
		_ = shape_text(&cached, 0, size, text, context.temp_allocator)
		hit := shape_text(&cached, 0, size, text, context.temp_allocator)
		clear_cache(&fresh)
		want := shape_text(&fresh, 0, size, text, context.temp_allocator)
		if !testing.expectf(t, same_shaping(hit, want), "case %d: %q at %v shaped differently from the cache", i, text, size) {
			return
		}
		run := shape(&cached, 0, size, text, context.temp_allocator)
		clear_cache(&fresh)
		want_run := shape(&fresh, 0, size, text, context.temp_allocator)
		testing.expectf(t, slice.equal(run.glyphs, want_run.glyphs) && run.advance == want_run.advance, "case %d: %q at %v placed differently from the cache", i, text, size)
	}
	testing.expect(t, cached.hits >= 300, "every second call hit")
}

@(private = "file")
same_shaping :: proc(a, b: ui.Shaped_Text) -> bool {
	return a.rtl == b.rtl && a.font == b.font && a.size == b.size && slice.equal(a.glyphs, b.glyphs) && slice.equal(a.runs, b.runs) && slice.equal(a.breaks, b.breaks)
}
