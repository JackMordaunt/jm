package ui

import "core:testing"

@(private = "file")
state :: proc(text: string, cursor: int) -> Text_State {
	s: Text_State
	text_set(&s, text)
	s.cursor = cursor
	return s
}

@(test)
test_text_key_moves_by_grapheme :: proc(t: ^testing.T) {
	// "é" as e + U+0301 (3 bytes, one grapheme), then x.
	s := state("éx", 0)
	defer text_destroy(&s)
	stops := []int{3, 4}
	text_key(&s, .Right, stops)
	testing.expect_value(t, s.cursor, 3)
	text_key(&s, .Right, stops)
	testing.expect_value(t, s.cursor, 4)
	text_key(&s, .Right, stops)
	testing.expect_value(t, s.cursor, 4)
	text_key(&s, .Left, stops)
	testing.expect_value(t, s.cursor, 3)
	text_key(&s, .Left, stops)
	testing.expect_value(t, s.cursor, 0)
	text_key(&s, .Left, stops)
	testing.expect_value(t, s.cursor, 0)
}

@(test)
test_text_key_deletes_by_grapheme :: proc(t: ^testing.T) {
	s := state("éx", 3)
	defer text_destroy(&s)
	testing.expect(t, text_key(&s, .Backspace, []int{3, 4}))
	testing.expect_value(t, text_string(&s), "x")
	testing.expect_value(t, s.cursor, 0)

	d := state("éx", 0)
	defer text_destroy(&d)
	testing.expect(t, text_key(&d, .Delete, []int{3, 4}))
	testing.expect_value(t, text_string(&d), "x")
	testing.expect_value(t, d.cursor, 0)
}

@(test)
test_text_key_without_graphemes_moves_by_rune :: proc(t: ^testing.T) {
	s := state("éx", 0)
	defer text_destroy(&s)
	text_key(&s, .Right)
	testing.expect_value(t, s.cursor, 1)
	text_key(&s, .Right)
	testing.expect_value(t, s.cursor, 3)
	testing.expect(t, text_key(&s, .Backspace))
	testing.expect_value(t, text_string(&s), "ex")
	testing.expect_value(t, s.cursor, 1)
}

@(test)
test_text_graphemes_from_the_shaper :: proc(t: ^testing.T) {
	// The stub shaper has no shape_text, so every rune is a stop.
	defer free_all(context.temp_allocator)
	ctx := Ctx{shaper = stub_shaper(), allocator = context.temp_allocator}
	s := state("aé", 0)
	defer text_destroy(&s)
	stops := text_graphemes(&ctx, &s, 0, 10)
	testing.expect_value(t, len(stops), 2)
	testing.expect_value(t, stops[0], 1)
	testing.expect_value(t, stops[1], 3)
}
