package ui

import "core:testing"

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
