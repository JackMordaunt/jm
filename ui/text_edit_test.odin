package ui

import "core:testing"
import "jm:ui/ops"

@(private = "file")
state :: proc(text: string, cursor: int) -> Text_State {
	s: Text_State
	text_set(&s, text)
	s.cursor, s.anchor = cursor, cursor
	return s
}

// press applies key k with mods to s through a context whose router
// takes the clipboard requests.
@(private = "file")
press :: proc(gtx: ^Ctx, s: ^Text_State, k: Key, mods: Mods = {}, stops: Text_Stops = {}, read_only := false) -> bool {
	return text_edit(gtx, s, 1, Event{kind = .Key, key = k, mods = mods}, stops, read_only)
}

@(private = "file")
Rig :: struct {
	r:   Router,
	gtx: Ctx,
}

@(private = "file")
rig_init :: proc(g: ^Rig) {
	router_init(&g.r)
	g.gtx = Ctx{router = &g.r, shaper = stub_shaper(), allocator = context.temp_allocator}
}

@(private = "file")
rig_destroy :: proc(g: ^Rig) {
	router_destroy(&g.r)
	free_all(context.temp_allocator)
}

@(test)
test_text_edit_moves_by_grapheme :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	// "é" as e + U+0301 (3 bytes, one grapheme), then x.
	s := state("éx", 0)
	defer text_destroy(&s)
	stops := Text_Stops{graphemes = {3, 4}}
	press(&g.gtx, &s, .Right, {}, stops)
	testing.expect_value(t, s.cursor, 3)
	press(&g.gtx, &s, .Right, {}, stops)
	press(&g.gtx, &s, .Right, {}, stops)
	testing.expect_value(t, s.cursor, 4)
	press(&g.gtx, &s, .Left, {}, stops)
	testing.expect_value(t, s.cursor, 3)
	press(&g.gtx, &s, .Left, {}, stops)
	press(&g.gtx, &s, .Left, {}, stops)
	testing.expect_value(t, s.cursor, 0)
}

@(test)
test_text_edit_deletes_by_grapheme :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	stops := Text_Stops{graphemes = {3, 4}}
	s := state("éx", 3)
	defer text_destroy(&s)
	testing.expect(t, press(&g.gtx, &s, .Backspace, {}, stops))
	testing.expect_value(t, text_string(&s), "x")
	testing.expect_value(t, s.cursor, 0)

	d := state("éx", 0)
	defer text_destroy(&d)
	testing.expect(t, press(&g.gtx, &d, .Delete, {}, stops))
	testing.expect_value(t, text_string(&d), "x")
}

@(test)
test_text_edit_without_stops_moves_by_rune :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("éx", 0)
	defer text_destroy(&s)
	press(&g.gtx, &s, .Right)
	testing.expect_value(t, s.cursor, 1)
	press(&g.gtx, &s, .Right)
	testing.expect_value(t, s.cursor, 3)
	testing.expect(t, press(&g.gtx, &s, .Backspace))
	testing.expect_value(t, text_string(&s), "ex")
}

@(test)
test_shift_extends_and_arrows_collapse :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("abcd", 1)
	defer text_destroy(&s)
	press(&g.gtx, &s, .Right, {.Shift})
	press(&g.gtx, &s, .Right, {.Shift})
	testing.expect_value(t, text_selected(&s), "bc")
	testing.expect_value(t, s.anchor, 1)
	press(&g.gtx, &s, .Left) // collapses to the selection's start, not one back
	testing.expect_value(t, [2]int{s.anchor, s.cursor}, [2]int{1, 1})
	press(&g.gtx, &s, .End, {.Shift})
	testing.expect_value(t, text_selected(&s), "bcd")
	press(&g.gtx, &s, .Right)
	testing.expect_value(t, [2]int{s.anchor, s.cursor}, [2]int{4, 4})
}

@(test)
test_typing_and_paste_replace_the_selection :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("hello world", 0)
	defer text_destroy(&s)
	text_select(&s, 6, 11)
	testing.expect(t, text_edit(&g.gtx, &s, 1, Event{kind = .Text, text = "there"}, {}))
	testing.expect_value(t, text_string(&s), "hello there")
	text_select(&s, 0, 5)
	testing.expect(t, text_edit(&g.gtx, &s, 1, Event{kind = .Paste, text = "hi", mime = TEXT_MIME}, {}))
	testing.expect_value(t, text_string(&s), "hi there")
	testing.expect_value(t, s.cursor, 2)
	// Not text: nothing to put in a text buffer.
	testing.expect(t, !text_edit(&g.gtx, &s, 1, Event{kind = .Paste, text = "<b>", mime = "text/html"}, {}))
}

@(test)
test_select_all_copy_and_cut :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("abc", 1)
	defer text_destroy(&s)
	press(&g.gtx, &s, .A, {SHORTCUT})
	testing.expect_value(t, text_selected(&s), "abc")
	testing.expect(t, !press(&g.gtx, &s, .C, {SHORTCUT}))
	testing.expect(t, press(&g.gtx, &s, .X, {SHORTCUT}))
	testing.expect_value(t, text_string(&s), "")
	reqs := router_requests(&g.r)
	testing.expect_value(t, len(reqs), 1) // the cut's write replaced the copy's
	if len(reqs) == 1 {
		testing.expect_value(t, reqs[0].(Clipboard_Write).data, "abc")
	}
	press(&g.gtx, &s, .V, {SHORTCUT})
	testing.expect_value(t, len(g.r.readers), 1)
}

@(test)
test_read_only_text_selects_and_copies_but_never_changes :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("fixed", 5)
	defer text_destroy(&s)
	testing.expect(t, !text_edit(&g.gtx, &s, 1, Event{kind = .Text, text = "x"}, {}, read_only = true))
	testing.expect(t, !press(&g.gtx, &s, .Backspace, read_only = true))
	press(&g.gtx, &s, .A, {SHORTCUT}, read_only = true)
	testing.expect(t, !press(&g.gtx, &s, .X, {SHORTCUT}, read_only = true))
	press(&g.gtx, &s, .C, {SHORTCUT}, read_only = true)
	press(&g.gtx, &s, .V, {SHORTCUT}, read_only = true)
	testing.expect_value(t, text_string(&s), "fixed")
	testing.expect_value(t, len(g.r.readers), 0)
	testing.expect_value(t, router_requests(&g.r)[0].(Clipboard_Write).data, "fixed")
}

@(test)
test_word_moves_and_deletes :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("one two, three", 5) // inside "two"
	defer text_destroy(&s)
	stops := text_stops(&g.gtx, &s, 0, 10)
	press(&g.gtx, &s, .Left, {WORD_MOD}, stops)
	testing.expect_value(t, s.cursor, 4) // start of "two"
	press(&g.gtx, &s, .Left, {WORD_MOD}, stops)
	testing.expect_value(t, s.cursor, 0)
	press(&g.gtx, &s, .Right, {WORD_MOD}, stops)
	when ODIN_OS == .Darwin {
		testing.expect_value(t, s.cursor, 3) // the end of "one"
	} else {
		testing.expect_value(t, s.cursor, 4) // the start of "two"
	}
	e := state("one two, three", 14)
	defer text_destroy(&e)
	estops := text_stops(&g.gtx, &e, 0, 10)
	testing.expect(t, press(&g.gtx, &e, .Backspace, {WORD_MOD}, estops))
	testing.expect_value(t, text_string(&e), "one two, ")
}

@(test)
test_word_at_a_point :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("one two, three", 0)
	defer text_destroy(&s)
	words := text_stops(&g.gtx, &s, 0, 10).words
	lo, hi := text_word_at(words, 5)
	testing.expect_value(t, string(s.buf[lo:hi]), "two")
	lo, hi = text_word_at(words, 3)
	testing.expect_value(t, string(s.buf[lo:hi]), " ") // a space is its own span
	lo, hi = text_word_at(words, 14)
	testing.expect_value(t, string(s.buf[lo:hi]), "three")
}

// send_pointer sends a pointer event at x (6px a rune through the stub) to s.
@(private = "file")
send_pointer :: proc(g: ^Rig, s: ^Text_State, kind: ops.Event_Kind, x: f32, clicks: u8 = 1, mods: Mods = {}, button := Button.Left) {
	text := text_string(s)
	p := paragraph_layout(g.gtx.shaper, 0, 10, text, 0, context.temp_allocator)
	stops := text_stops(&g.gtx, s, 0, 10)
	text_follow_pointer(s, p, Event{kind = kind, clicks = clicks, mods = mods, button = button}, {x, 5}, stops)
}

@(test)
test_press_drag_and_shift_press :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("one two three", 0)
	defer text_destroy(&s)
	send_pointer(&g, &s, .Press, 31) // inside "two", nearest the stop at 5
	testing.expect_value(t, [2]int{s.anchor, s.cursor}, [2]int{5, 5})
	send_pointer(&g, &s, .Move, 61)
	testing.expect_value(t, text_selected(&s), "wo th")
	send_pointer(&g, &s, .Move, 13) // back past the press: the press point stays the anchor
	testing.expect_value(t, [2]int{s.anchor, s.cursor}, [2]int{5, 2})
	send_pointer(&g, &s, .Release, 13)
	send_pointer(&g, &s, .Move, 70) // no longer pressed: moves select nothing
	testing.expect_value(t, [2]int{s.anchor, s.cursor}, [2]int{5, 2})
	send_pointer(&g, &s, .Press, 67, mods = {.Shift}) // extends from the anchor, to 11
	testing.expect_value(t, text_selected(&s), "wo thr")
	send_pointer(&g, &s, .Press, 0, button = .Right)
	testing.expect_value(t, text_selected(&s), "wo thr")
}

@(test)
test_double_and_triple_press :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("one two three", 0)
	defer text_destroy(&s)
	send_pointer(&g, &s, .Press, 31, clicks = 2)
	testing.expect_value(t, text_selected(&s), "two")
	send_pointer(&g, &s, .Move, 70) // dragging after a double click grows by words
	testing.expect_value(t, text_selected(&s), "two three")
	send_pointer(&g, &s, .Move, 2)
	testing.expect_value(t, text_selected(&s), "one two")
	testing.expect_value(t, s.anchor, 7) // the double-clicked word's end holds
	send_pointer(&g, &s, .Release, 2)
	send_pointer(&g, &s, .Press, 31, clicks = 3)
	testing.expect_value(t, text_selected(&s), "one two three")

	para := state("first\nsecond line\nthird", 0)
	defer text_destroy(&para)
	p := paragraph_layout(g.gtx.shaper, 0, 10, text_string(&para), 0, context.temp_allocator)
	text_follow_pointer(&para, p, Event{kind = .Press, clicks = 3}, {10, 15}, text_stops(&g.gtx, &para, 0, 10))
	testing.expect_value(t, text_selected(&para), "second line") // the paragraph, not its newlines
}

@(private = "file")
press_lines :: proc(g: ^Rig, s: ^Text_State, k: Key, mods: Mods = {}) -> bool {
	p := paragraph_layout(g.gtx.shaper, 0, 10, text_string(s), 0, context.temp_allocator)
	return text_edit_lines(&g.gtx, s, 1, Event{kind = .Key, key = k, mods = mods}, text_stops(&g.gtx, s, 0, 10), p)
}

@(test)
test_text_edit_lines_moves_between_and_along_lines :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("abc\nde\nfghij", 2) // after "ab"
	defer text_destroy(&s)
	press_lines(&g, &s, .Down)
	testing.expect_value(t, s.cursor, 6) // after "d", at the x it left
	press_lines(&g, &s, .Down, {.Shift})
	testing.expect_value(t, [2]int{s.anchor, s.cursor}, [2]int{6, 9}) // extends down
	press_lines(&g, &s, .Down)
	testing.expect_value(t, s.cursor, 9) // the last line: stays
	press_lines(&g, &s, .Home)
	testing.expect_value(t, s.cursor, 7) // the line's start, not the text's
	press_lines(&g, &s, .End)
	testing.expect_value(t, s.cursor, 12)
	press_lines(&g, &s, .Up)
	press_lines(&g, &s, .Up)
	press_lines(&g, &s, .Up)
	testing.expect_value(t, s.cursor, 2) // up twice to "ab|"; up again stays
	press_lines(&g, &s, .End)
	testing.expect_value(t, s.cursor, 3) // before the newline, not after it
}

@(test)
test_text_edit_lines_inserts_newlines_unless_read_only :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("ab", 1)
	defer text_destroy(&s)
	testing.expect(t, press_lines(&g, &s, .Enter))
	testing.expect_value(t, text_string(&s), "a\nb")
	testing.expect(t, press_lines(&g, &s, .Backspace)) // the rest is text_edit's
	testing.expect_value(t, text_string(&s), "ab")
	p := paragraph_layout(g.gtx.shaper, 0, 10, text_string(&s), 0, context.temp_allocator)
	testing.expect(t, !text_edit_lines(&g.gtx, &s, 1, Event{kind = .Key, key = .Enter}, {}, p, read_only = true))
	testing.expect_value(t, text_string(&s), "ab")
}

@(test)
test_text_scroll_moves_only_as_far_as_the_caret_needs :: proc(t: ^testing.T) {
	// A 100px view over 300px of text.
	testing.expect_value(t, text_scroll(0, 300, 50, 1, 100), 0) // in view: unchanged
	testing.expect_value(t, text_scroll(0, 300, 150, 1, 100), 51) // past the end: just in
	testing.expect_value(t, text_scroll(120, 300, 80, 1, 100), 80) // before the start: to it
	testing.expect_value(t, text_scroll(250, 300, 290, 1, 100), 200) // never past the content
	testing.expect_value(t, text_scroll(40, 60, 10, 1, 100), 0) // content shorter than the view
}

@(test)
test_a_preedit_shows_at_the_caret_and_commits_as_one_edit :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("ab", 1)
	defer text_destroy(&s)

	testing.expect(t, !text_edit(&g.gtx, &s, 1, Event{kind = .Compose, text = "にほ", span = {6, 6}}, {}))
	testing.expect_value(t, text_string(&s), "ab")
	testing.expect(t, !text_can_undo(&s))
	shown := text_display(&s)
	testing.expect_value(t, shown.text, "aにほb")
	testing.expect_value(t, shown.pre_lo, 1)
	testing.expect_value(t, shown.pre_hi, 7)
	testing.expect_value(t, shown.caret, 7)

	testing.expect(t, text_edit(&g.gtx, &s, 1, Event{kind = .Text, text = "日本"}, {}))
	testing.expect(t, !text_composing(&s))
	testing.expect_value(t, text_string(&s), "a日本b")
	testing.expect_value(t, text_display(&s).text, "a日本b")
	testing.expect(t, text_undo(&s))
	testing.expect_value(t, text_string(&s), "ab")
}

@(test)
test_a_preedit_replaces_the_selection_only_on_show :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("abc", 0)
	defer text_destroy(&s)
	text_select(&s, 0, 2)

	text_edit(&g.gtx, &s, 1, Event{kind = .Compose, text = "zy", span = {0, 1}}, {})
	shown := text_display(&s)
	testing.expect_value(t, shown.text, "zyc")
	testing.expect_value(t, shown.target_lo, 0)
	testing.expect_value(t, shown.target_hi, 1)
	testing.expect_value(t, shown.caret, 0)
	testing.expect_value(t, text_string(&s), "abc")

	// An empty preedit cancels: the selection is back as it was.
	text_edit(&g.gtx, &s, 1, Event{kind = .Compose}, {})
	testing.expect_value(t, text_display(&s).text, "abc")
	testing.expect_value(t, text_selected(&s), "ab")
}

@(test)
test_keys_belong_to_the_input_method_while_it_composes :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("ab", 2)
	defer text_destroy(&s)

	text_edit(&g.gtx, &s, 1, Event{kind = .Compose, text = "k", span = {1, 1}}, {})
	testing.expect(t, !press(&g.gtx, &s, .Backspace))
	testing.expect(t, !press(&g.gtx, &s, .Left))
	testing.expect_value(t, text_string(&s), "ab")
	testing.expect_value(t, s.cursor, 2)

	text_compose_end(&s)
	testing.expect(t, press(&g.gtx, &s, .Backspace))
	testing.expect_value(t, text_string(&s), "a")
}

@(test)
test_a_secret_or_read_only_field_keeps_no_preedit :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s := state("ab", 2)
	defer text_destroy(&s)

	compose := Event{kind = .Compose, text = "k"}
	text_edit(&g.gtx, &s, 1, compose, {})
	testing.expect(t, text_composing(&s))
	text_edit(&g.gtx, &s, 1, compose, {}, secret = true)
	testing.expect(t, !text_composing(&s))
	text_edit(&g.gtx, &s, 1, compose, {})
	testing.expect(t, text_composing(&s))
	text_edit(&g.gtx, &s, 1, compose, {}, read_only = true)
	testing.expect(t, !text_composing(&s))
}
