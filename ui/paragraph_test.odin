package ui

import "core:testing"
import "jm:ui/ops"

// Through the stub every rune advances 6px at size 10.
@(private = "file")
SIZE :: 10

@(private = "file")
lay :: proc(text: string, max_width: f32) -> Paragraph {
	return paragraph_layout(stub_shaper(), 0, SIZE, text, max_width, context.temp_allocator)
}

@(private = "file")
expect_lines :: proc(t: ^testing.T, p: Paragraph, want: [][2]int, loc := #caller_location) {
	if !testing.expect_value(t, len(p.lines), len(want), loc) {
		return
	}
	for w, i in want {
		testing.expect_value(t, [2]int{p.lines[i].start, p.lines[i].end}, w, loc)
	}
}

@(test)
test_paragraph_wraps_at_spaces :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := lay("aaa bbb ccc", 50)
	expect_lines(t, p, {{0, 8}, {8, 11}})
	testing.expect_value(t, p.lines[0].width, 42) // the space after bbb hangs
	testing.expect_value(t, p.lines[1].width, 18)
	// The stub's lines are 10px: ascent 8, descent 2, no gap.
	testing.expect_value(t, p.lines[1].baseline, 18)
	testing.expect_value(t, p.height, 20)

	one := lay("aaa bbb ccc", 0)
	expect_lines(t, one, {{0, 11}})
}

@(test)
test_paragraph_hard_breaks :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	expect_lines(t, lay("ab\ncd", 0), {{0, 3}, {3, 5}})
	// A trailing newline leaves an empty last line for the caret.
	expect_lines(t, lay("ab\n", 0), {{0, 3}, {3, 3}})
	expect_lines(t, lay("", 0), {{0, 0}})
}

@(test)
test_paragraph_breaks_long_words :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Four runes fit in 25px: the word breaks between graphemes.
	expect_lines(t, lay("abcdefghij", 25), {{0, 4}, {4, 8}, {8, 10}})
	// Narrower than one grapheme still makes progress, one per line.
	expect_lines(t, lay("abc", 1), {{0, 1}, {1, 2}, {2, 3}})
}

@(test)
test_paragraph_caret_and_hit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := lay("aaa bbb ccc", 50)
	line, x := paragraph_caret(p, 2)
	testing.expect_value(t, line, 0)
	testing.expect_value(t, x, 12)
	// The hanging space: its caret stops run on past the line's width.
	line, x = paragraph_caret(p, 7)
	testing.expect_value(t, [2]f32{f32(line), x}, [2]f32{0, 42})
	// Where a line wraps is the start of the next one.
	line, x = paragraph_caret(p, 8)
	testing.expect_value(t, [2]f32{f32(line), x}, [2]f32{1, 0})
	line, x = paragraph_caret(p, 11)
	testing.expect_value(t, [2]f32{f32(line), x}, [2]f32{1, 18})

	lh := line_height(p.metrics)
	testing.expect_value(t, paragraph_hit(p, {13, 1}), 2)
	testing.expect_value(t, paragraph_hit(p, {100, 1}), 8)
	testing.expect_value(t, paragraph_hit(p, {7, lh + 1}), 9)
	testing.expect_value(t, paragraph_hit(p, {-5, 5 * lh}), 8)
}

@(test)
test_paragraph_draws_each_run :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	sc: ops.Scene
	ops.init(&sc, context.temp_allocator)
	p := lay("ab cd", 20)
	paragraph_draw(&sc, p, {10, 20}, {0, 0, 0, 255})
	testing.expect_value(t, len(sc.runs), 2)
	second := sc.ops[1].(ops.Glyphs)
	testing.expect_value(t, second.origin, ops.Point{10, 20 + p.lines[1].baseline})
}

// fake_shaped is text as a shaper that knows directions would shape it:
// one 6px glyph per rune, every rune a grapheme, a soft break after each
// space, split into runs of the given directions.
@(private = "file")
fake_shaped :: proc(text: string, rtl: bool, runs: []Shaped_Run) -> Shaped_Text {
	st := shaped_from_run(shape(stub_shaper(), 0, SIZE, text, context.temp_allocator), text, context.temp_allocator)
	st.rtl = rtl
	st.runs = runs
	return st
}

@(test)
test_paragraph_reorders_rtl_runs :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// "ab CD ef" with CD right-to-left, in a left-to-right paragraph.
	text := "ab CD ef"
	st := fake_shaped(text, false, {{0, 3, 0, 3, false}, {3, 5, 3, 5, true}, {5, 8, 5, 8, false}})
	p := paragraph_from_shaped(st, metrics(stub_shaper(), 0, SIZE), text, 0, context.temp_allocator)
	ln := p.lines[0]
	testing.expect_value(t, len(ln.runs), 3)
	testing.expect_value(t, ln.runs[1].x, 18)
	// Drawn right to left: D is the leftmost glyph of the run.
	testing.expect_value(t, ln.runs[1].glyphs.glyphs[0].cluster, 4)
	testing.expect_value(t, ln.runs[1].glyphs.glyphs[1].x, 6)
	// The caret before C stands at the run's right edge, before D between.
	_, x := paragraph_caret(p, 3)
	testing.expect_value(t, x, 30)
	_, x = paragraph_caret(p, 4)
	testing.expect_value(t, x, 24)
	testing.expect_value(t, paragraph_hit(p, {25, 1}), 4)
}

@(test)
test_paragraph_rtl_paragraph :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// "AB cd" in a right-to-left paragraph: AB and its space right to
	// left, cd left to right. The ltr run sits two levels up, so the line
	// reads cd first from the left, and the line aligns right.
	text := "AB cd"
	st := fake_shaped(text, true, {{0, 3, 0, 3, true}, {3, 5, 3, 5, false}})
	p := paragraph_from_shaped(st, metrics(stub_shaper(), 0, SIZE), text, 100, context.temp_allocator)
	ln := p.lines[0]
	testing.expect_value(t, ln.width, 30)
	testing.expect_value(t, ln.x, 70)
	testing.expect_value(t, ln.runs[0].start, 3)
	testing.expect_value(t, ln.runs[1].start, 0)
	// The caret at the very end, after d, stands at cd's right edge.
	_, x := paragraph_caret(p, 5)
	testing.expect_value(t, x, 70 + 12)
	// The caret at the start, before A, stands at the line's right end.
	_, x = paragraph_caret(p, 0)
	testing.expect_value(t, x, 100)
}
