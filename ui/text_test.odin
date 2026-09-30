package ui

import "core:testing"
import "jm:ui/ops"

@(test)
test_caret_plain :: proc(t: ^testing.T) {
	// "aéb" through the stub: 6px per rune, é is two bytes.
	text := "aéb"
	run := shape(stub_shaper(), 0, 10, text, context.allocator)
	defer delete(run.glyphs)
	testing.expect_value(t, caret_x(run, text, 0), 0)
	testing.expect_value(t, caret_x(run, text, 1), 6)
	testing.expect_value(t, caret_x(run, text, 3), 12)
	testing.expect_value(t, caret_x(run, text, 4), 18)
	testing.expect_value(t, caret_at(run, text, -5), 0)
	testing.expect_value(t, caret_at(run, text, 7), 1)
	testing.expect_value(t, caret_at(run, text, 10), 3)
	testing.expect_value(t, caret_at(run, text, 100), 4)
}

@(test)
test_caret_ligature :: proc(t: ^testing.T) {
	// "ffi" as one 30px ligature glyph then "x": the caret splits the
	// ligature's width in thirds, one per rune.
	text := "ffix"
	gs := []ops.Glyph{{1, 0, 0, 0, 0}, {2, 3, 30, 0, 0}}
	run := ops.Glyph_Run{0, 10, gs, 40}
	testing.expect_value(t, caret_x(run, text, 1), 10)
	testing.expect_value(t, caret_x(run, text, 2), 20)
	testing.expect_value(t, caret_x(run, text, 3), 30)
	testing.expect_value(t, caret_at(run, text, 18), 2)
	testing.expect_value(t, caret_at(run, text, 36), 4)
}

@(test)
test_caret_marks :: proc(t: ^testing.T) {
	// "e" + U+0301 (two bytes) drawn as a base and a nudged mark glyph in
	// one cluster, then "z": the mark's offset does not move the caret.
	text := "éz"
	gs := []ops.Glyph{{1, 0, 0, 0, 0}, {2, 0, 3, -4, 0}, {3, 3, 10, 0, 0}}
	run := ops.Glyph_Run{0, 10, gs, 18}
	testing.expect_value(t, caret_x(run, text, 0), 0)
	testing.expect_value(t, caret_x(run, text, 1), 5) // between e and its mark
	testing.expect_value(t, caret_x(run, text, 3), 10)
	testing.expect_value(t, caret_at(run, text, 9), 3)
}
