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

@(test)
test_selection_rects_on_one_line :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := lay("aaa bbb", 0)
	rs := paragraph_selection_rects(p, 1, 5)
	testing.expect_value(t, len(rs), 1)
	testing.expect_value(t, rs[0], ops.Rect{6, 0, 24, 10})
	testing.expect_value(t, len(paragraph_selection_rects(p, 3, 3)), 0)
}

@(test)
test_selection_rects_across_a_wrap :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Lines "aaa bbb " (its space hanging past 42) and "ccc".
	p := lay("aaa bbb ccc", 50)
	rs := paragraph_selection_rects(p, 2, 9)
	testing.expect_value(t, len(rs), 2)
	testing.expect_value(t, rs[0], ops.Rect{12, 0, 36, 10}) // to the hanging space's end
	testing.expect_value(t, rs[1], ops.Rect{0, 10, 6, 10})
}

@(test)
test_selection_rects_split_at_a_change_of_direction :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// "ab CD ef" with CD right to left: selecting "b C" lights b and the
	// space, then C, which sits right of D.
	text := "ab CD ef"
	st := fake_shaped(text, false, {{0, 3, 0, 3, false}, {3, 5, 3, 5, true}, {5, 8, 5, 8, false}})
	p := paragraph_from_shaped(st, metrics(stub_shaper(), 0, SIZE), text, 0, context.temp_allocator)
	rs := paragraph_selection_rects(p, 1, 4)
	testing.expect_value(t, len(rs), 2)
	testing.expect_value(t, rs[0], ops.Rect{6, 0, 12, 10})
	testing.expect_value(t, rs[1], ops.Rect{24, 0, 6, 10})
}

@(test)
test_selection_rects_show_a_selected_newline :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := lay("ab\ncd", 0)
	rs := paragraph_selection_rects(p, 1, 4)
	testing.expect_value(t, len(rs), 2)
	testing.expect_value(t, rs[0], ops.Rect{6, 0, 6 + SIZE * 0.25, 10})
	testing.expect_value(t, rs[1], ops.Rect{0, 10, 6, 10})
}

@(private = "file")
lay_max :: proc(text: string, max_width: f32, max_lines: int, ellipsis := ELLIPSIS) -> Paragraph {
	return paragraph_layout(stub_shaper(), 0, SIZE, text, max_width, context.temp_allocator, max_lines = max_lines, ellipsis = ellipsis)
}

@(test)
test_paragraph_truncates_one_line_instead_of_wrapping :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// 50px holds eight runes; seven and the ellipsis's one fit.
	p := lay_max("aaaa bbbb cccc", 50, 1)
	testing.expect(t, p.truncated)
	expect_lines(t, p, {{0, 14}})
	ln := p.lines[0]
	testing.expect_value(t, ln.width, 48) // "aaaa bb" and the ellipsis
	last := ln.runs[len(ln.runs) - 1]
	testing.expect_value(t, last.clusters[0], Cluster_Span{7, 14, 42, 48})
	// Caret stops end at the cut, then jump the ellipsis to the text's end.
	n := len(p.graphemes)
	testing.expect_value(t, [2]int{p.graphemes[n - 2], p.graphemes[n - 1]}, [2]int{7, 14})
	testing.expect_value(t, paragraph_hit(p, {47, 5}), 14)
	_, x := paragraph_caret(p, 7)
	testing.expect_value(t, x, 42)
	// What fits is not truncated; a space before the cut is trimmed.
	testing.expect(t, !lay_max("aaaa", 50, 1).truncated)
	testing.expect_value(t, lay_max("aaaaaa bbb", 50, 1).lines[0].width, 42) // "aaaaaa" "…"
}

@(test)
test_paragraph_wraps_to_max_lines_then_truncates :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := lay_max("aaa bbb ccc ddd eee", 50, 2)
	testing.expect(t, p.truncated)
	expect_lines(t, p, {{0, 8}, {8, 19}})
	testing.expect_value(t, p.lines[1].width, 48) // "ccc ddd…"
	testing.expect(t, !lay_max("aaa bbb ccc ddd", 50, 2).truncated) // two lines exactly
	// A hard break ends the last line's text even with room to spare.
	q := lay_max("one\ntwo\nthree", 0, 2)
	expect_lines(t, q, {{0, 4}, {4, 13}})
	testing.expect_value(t, q.lines[1].width, 24) // "two…"
	// Within the limit, nothing changes.
	expect_lines(t, lay_max("ab\ncd\n", 0, 2), {{0, 3}, {3, 6}})
}

@(test)
test_paragraph_without_ellipsis_runs_on_to_clip :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := lay_max("aaaa bbbb cccc\nhidden", 50, 1, ellipsis = "")
	testing.expect(t, p.truncated)
	expect_lines(t, p, {{0, 21}})
	testing.expect_value(t, p.lines[0].width, 84) // the whole first line, wider than 50
}

@(test)
test_selecting_through_an_ellipsis_selects_the_hidden_text :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := lay_max("aaaa bbbb cccc", 50, 1)
	rects := paragraph_selection_rects(p, 5, 14)
	testing.expect_value(t, len(rects), 1)
	testing.expect_value(t, rects[0], ops.Rect{30, 0, 18, p.pitch}) // "bb" and the ellipsis
	s: Text_State
	text_set(&s, p.text)
	defer text_destroy(&s)
	text_select(&s, 5, paragraph_hit(p, {60, 5}))
	testing.expect_value(t, text_selected(&s), "bbbb cccc")
}

@(test)
test_a_balanced_paragraph_evens_its_lines_out :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Six four-rune words, 24px each with 6px spaces: greedy at 120px
	// takes four then two; balanced keeps two lines, three and three.
	six := "aaaa bbbb cccc dddd eeee ffff"
	expect_lines(t, lay(six, 120), {{0, 20}, {20, 29}})
	b := paragraph_layout(stub_shaper(), 0, SIZE, six, 120, context.temp_allocator, balance = true)
	expect_lines(t, b, {{0, 15}, {15, 29}})
	testing.expect_value(t, b.width, 84)
	// Five words at 90px are three then two either way: no split is more even.
	five := paragraph_layout(stub_shaper(), 0, SIZE, "aaaa bbbb cccc dddd eeee", 90, context.temp_allocator, balance = true)
	expect_lines(t, five, {{0, 15}, {15, 24}})
	// One line, or no width to wrap at, stays as it is.
	testing.expect_value(t, paragraph_layout(stub_shaper(), 0, SIZE, "aaaa", 120, context.temp_allocator, balance = true).width, 24)
	testing.expect_value(t, len(paragraph_layout(stub_shaper(), 0, SIZE, six, 0, context.temp_allocator, balance = true).lines), 1)
}

@(test)
test_white_space_collapses_as_css_does :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	s := "  one   two\n\tthree  \n four  "
	testing.expect_value(t, white_space_text(s, .Normal), "one two three four")
	testing.expect_value(t, white_space_text(s, .Nowrap), "one two three four")
	testing.expect_value(t, white_space_text(s, .Pre_Line), "one two\nthree\nfour")
	testing.expect_value(t, white_space_text("a\r\nb", .Pre_Line), "a\nb")
	// The preserving modes keep everything but expand a tab to its stop.
	testing.expect_value(t, white_space_text(s, .Pre), "  one   two\n        three  \n four  ")
	testing.expect_value(t, white_space_text("ab\tc\td\n\te", .Pre_Wrap), "ab      c       d\n        e")
	no_tabs := "  kept  as is \n"
	testing.expect(t, raw_data(white_space_text(no_tabs, .Pre)) == raw_data(no_tabs))
	testing.expect_value(t, white_space_text("", .Normal), "")
	testing.expect_value(t, white_space_text("   ", .Normal), "")
	plain := "already plain"
	testing.expect(t, raw_data(white_space_text(plain, .Normal)) == raw_data(plain)) // nothing to change: no copy
	testing.expect(t, white_space_wraps(.Normal) && white_space_wraps(.Pre_Wrap) && white_space_wraps(.Pre_Line))
	testing.expect(t, !white_space_wraps(.Nowrap) && !white_space_wraps(.Pre))
}
