package ui

import "core:testing"
import "jm:ui/ops"

// A field's undo history: runs of typing and deleting as one edit each,
// a pause or a caret move splitting them, the selection put back, redo
// dropped by a new edit, the bounds, and the shortcut left to the app
// once the field's history runs out.

@(private = "file")
Rig :: struct {
	r:   Router,
	gtx: Ctx,
}

@(private = "file")
rig_init :: proc(g: ^Rig) {
	router_init(&g.r)
	g.gtx = Ctx {
		router    = &g.r,
		shaper    = stub_shaper(),
		allocator = context.temp_allocator,
	}
}

@(private = "file")
rig_destroy :: proc(g: ^Rig) {
	router_destroy(&g.r)
	free_all(context.temp_allocator)
}

// type_in types ASCII text into s a byte at a time, as keystrokes come.
@(private = "file")
type_in :: proc(g: ^Rig, s: ^Text_State, text: string, secret := false) {
	for ii := 0; ii < len(text); ii += 1 {
		text_edit(&g.gtx, s, 1, Event{kind = .Text, text = text[ii:ii + 1]}, {}, secret = secret)
	}
}

@(private = "file")
key :: proc(g: ^Rig, s: ^Text_State, k: Key, mods: Mods = {}) -> bool {
	return text_edit(&g.gtx, s, 1, Event{kind = .Key, key = k, mods = mods}, {})
}

@(test)
test_a_run_of_typing_undoes_as_one_edit_and_redoes :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s: Text_State
	defer text_destroy(&s)
	type_in(&g, &s, "hello")
	testing.expect(t, key(&g, &s, .Z, {SHORTCUT}))
	testing.expect_value(t, text_string(&s), "")
	testing.expect_value(t, s.cursor, 0)
	testing.expect(t, !key(&g, &s, .Z, {SHORTCUT}), "nothing more to undo")
	testing.expect(t, key(&g, &s, .Z, {SHORTCUT, .Shift}))
	testing.expect_value(t, text_string(&s), "hello")
	testing.expect_value(t, s.cursor, 5)
	testing.expect(t, !text_can_redo(&s))
}

@(test)
test_a_pause_or_a_caret_move_ends_a_run :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s: Text_State
	defer text_destroy(&s)
	type_in(&g, &s, "ab")
	g.gtx.time += TEXT_PAUSE
	type_in(&g, &s, "cd")
	key(&g, &s, .Home)
	type_in(&g, &s, "x")
	testing.expect_value(t, text_string(&s), "xabcd")
	text_undo(&s)
	testing.expect_value(t, text_string(&s), "abcd")
	text_undo(&s)
	testing.expect_value(t, text_string(&s), "ab")
	text_undo(&s)
	testing.expect_value(t, text_string(&s), "")
}

@(test)
test_backspace_and_delete_runs_undo_as_one_with_the_caret_back :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s: Text_State
	defer text_destroy(&s)
	text_set(&s, "abcdef")
	text_move(&s, 4)
	key(&g, &s, .Backspace)
	key(&g, &s, .Backspace)
	testing.expect_value(t, text_string(&s), "abef")
	key(&g, &s, .Delete)
	key(&g, &s, .Delete)
	testing.expect_value(t, text_string(&s), "ab")
	text_undo(&s)
	testing.expect_value(t, text_string(&s), "abef")
	testing.expect_value(t, s.cursor, 2)
	text_undo(&s)
	testing.expect_value(t, text_string(&s), "abcdef")
	testing.expect_value(t, s.cursor, 4)
	testing.expect(t, !text_can_undo(&s), "text_set's text is not an edit")
}

@(test)
test_undo_puts_a_replaced_selection_back_and_a_new_edit_drops_redo :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s: Text_State
	defer text_destroy(&s)
	text_set(&s, "one two")
	text_select(&s, 4, 7)
	type_in(&g, &s, "2")
	testing.expect_value(t, text_string(&s), "one 2")
	text_undo(&s)
	testing.expect_value(t, text_string(&s), "one two")
	lo, hi := text_selection(&s)
	testing.expect_value(t, lo, 4)
	testing.expect_value(t, hi, 7)
	testing.expect(t, text_can_redo(&s))
	type_in(&g, &s, "!")
	testing.expect(t, !text_can_redo(&s), "a new edit drops what was undone")
	testing.expect_value(t, text_string(&s), "one !")
}

@(test)
test_a_buffer_edited_around_the_history_drops_it :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s: Text_State
	defer text_destroy(&s)
	type_in(&g, &s, "abc")
	append(&s.buf, "zz")
	text_clamp(&s)
	testing.expect(t, !text_can_undo(&s))
	testing.expect(t, !text_undo(&s))
	testing.expect_value(t, text_string(&s), "abczz")
}

@(test)
test_a_secret_field_keeps_no_history :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s: Text_State
	defer text_destroy(&s)
	type_in(&g, &s, "hunter2", secret = true)
	testing.expect_value(t, text_string(&s), "hunter2")
	testing.expect(t, !text_can_undo(&s))
	testing.expect_value(t, len(s.history.bytes), 0)
}

@(test)
test_the_history_keeps_its_newest_edits_within_bounds :: proc(t: ^testing.T) {
	g: Rig
	rig_init(&g)
	defer rig_destroy(&g)
	s: Text_State
	defer text_destroy(&s)
	for ii in 0 ..< TEXT_HISTORY_EDITS + 20 {
		text_replace(&s, "ab" if ii % 2 == 0 else "c")
	}
	testing.expect_value(t, len(s.history.edits), TEXT_HISTORY_EDITS)
	undone := 0
	for text_undo(&s) {
		undone += 1
	}
	testing.expect_value(t, undone, TEXT_HISTORY_EDITS)
	// The 20 oldest edits stay: "ab", "c", ... ten of each.
	testing.expect_value(t, len(text_string(&s)), 30)
	big := make([]u8, TEXT_HISTORY_BYTES + 1, context.temp_allocator)
	for &b in big {
		b = 'x'
	}
	text_replace(&s, string(big))
	testing.expect_value(t, len(s.history.edits), 1)
	testing.expect(t, text_undo(&s), "the newest edit stays, however big")
}

@(private = "file")
Undo_Model :: struct {
	s:         Text_State,
	app_undos: int, // what the app's own undo and redo interest heard
}

// undo_view is a field over m.s, with an app-wide undo shortcut that
// takes over once the field has nothing to undo.
@(private = "file")
undo_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Undo_Model)(user)
	app := claim_id(gtx, 90)
	key_interest(gtx, app, .Z, {SHORTCUT}, optional = {.Shift})
	for e in events(gtx, app) {
		if e.kind == .Key && e.key == .Z {
			m.app_undos += 1
		}
	}
	p := widget_open(gtx, 5)
	ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 120, 24}, {.Press, .Key, .Text, .Focus, .Blur})
	ops.tag(gtx.scene, p.id, "Name")
	for e in events(gtx, p.id) {
		text_edit(gtx, &m.s, p.id, e, {})
	}
	text_claim_keys(gtx, &m.s, p.id)
	widget_close(gtx, &p, {size = {120, 24}})
}

@(test)
test_the_undo_shortcut_goes_to_the_app_once_the_field_has_none :: proc(t: ^testing.T) {
	m: Undo_Model
	defer text_destroy(&m.s)
	p: Probe
	probe_init(&p, undo_view, &m, {300, 100})
	defer probe_destroy(&p)
	probe_frame(&p)
	testing.expect(t, probe_click(&p, "Name"))
	probe_type(&p, "hi")
	probe_key(&p, .Z, {SHORTCUT})
	testing.expect_value(t, text_string(&m.s), "")
	testing.expect_value(t, m.app_undos, 0)
	probe_key(&p, .Z, {SHORTCUT})
	testing.expect_value(t, m.app_undos, 1)
	// Redo is the field's while it has one: it claims Shift+Z too.
	probe_key(&p, .Z, {SHORTCUT, .Shift})
	testing.expect_value(t, text_string(&m.s), "hi")
	testing.expect_value(t, m.app_undos, 1)
}
