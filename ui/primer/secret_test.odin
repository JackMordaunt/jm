package primer

import "core:strings"
import "core:testing"

import "jm:ui"

@(private = "file")
Secret_Model :: struct {
	password: ui.Text_State,
}

@(private = "file")
secret_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Secret_Model)(user)
	text_input(gtx, &m.password, name = "Password", secret = true, width = 300)
}

@(test)
test_a_secret_input_shows_bullets_and_keeps_its_text :: proc(t: ^testing.T) {
	m: Secret_Model
	defer delete(m.password.buf)
	p: ui.Probe
	ui.probe_init(&p, secret_ui, &m, {400, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Password"))
	ui.probe_type(&p, "pässwörd")
	testing.expect_value(t, ui.text_string(&m.password), "pässwörd")
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(
		t,
		strings.contains(
			report,
			`password field "Password" value "\u25cf\u25cf\u25cf\u25cf\u25cf\u25cf\u25cf\u25cf"`,
		),
		report,
	)
	testing.expect(t, !strings.contains(report, "pässw"), "the text reached the reader")
	testing.expect(t, !strings.contains(ui.probe_dump(&p), "pässwörd"), "the text was drawn")

	// Select all, then copy and cut: neither reaches the clipboard.
	ui.probe_key(&p, .A, {ui.SHORTCUT})
	lo, hi := ui.text_selection(&m.password)
	testing.expect(t, lo == 0 && hi == len(m.password.buf), "select all selected the text")
	ui.probe_key(&p, .C, {ui.SHORTCUT})
	ui.probe_key(&p, .X, {ui.SHORTCUT})
	testing.expect_value(t, ui.probe_clipboard(&p), "")
	testing.expect_value(t, ui.text_string(&m.password), "pässwörd")

	// Moves go by character: Left twice puts the caret before the "r".
	ui.probe_key(&p, .End)
	ui.probe_key(&p, .Left)
	ui.probe_key(&p, .Left)
	ui.probe_type(&p, "!")
	testing.expect_value(t, ui.text_string(&m.password), "pässwö!rd")
	// A word move cannot find the text's words: it goes to the start.
	ui.probe_key(&p, .Left, {ui.WORD_MOD})
	ui.probe_type(&p, "^")
	testing.expect_value(t, ui.text_string(&m.password), "^pässwö!rd")
}

@(test)
test_a_click_in_a_secret_input_places_the_caret_in_the_text :: proc(t: ^testing.T) {
	m: Secret_Model
	defer delete(m.password.buf)
	ui.text_set(&m.password, "é€x")
	p: ui.Probe
	ui.probe_init(&p, secret_ui, &m, {400, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	box := ui.probe_bounds(&p, "Password")
	// Past the bullets: the caret goes after the last character, whose
	// bytes the bullets do not have.
	ui.probe_click_at(&p, {box.x + box.w - 20, box.y + box.h / 2})
	ui.probe_type(&p, "$")
	testing.expect_value(t, ui.text_string(&m.password), "é€x$")
	// At the field's start: before the first character.
	ui.probe_click_at(&p, {box.x + 2, box.y + box.h / 2})
	ui.probe_type(&p, "^")
	testing.expect_value(t, ui.text_string(&m.password), "^é€x$")
	// Clicks across the bullets land only on the text's rune boundaries,
	// each of them.
	seen: [16]bool
	for x := box.x; x < box.x + box.w; x += 1 {
		ui.probe_click_at(&p, {x, box.y + box.h / 2})
		seen[clamp(m.password.cursor, 0, 15)] = true
	}
	// "^é€x$" has its rune boundaries at bytes 0, 1, 3, 6, 7 and 8.
	want: [16]bool
	for i in ([]int{0, 1, 3, 6, 7, 8}) {
		want[i] = true
	}
	testing.expect_value(t, seen, want)
	// A double click selects every bullet, and so the whole text.
	ui.probe_click_at(&p, {box.x + 20, box.y + box.h / 2}, clicks = 2)
	ui.probe_type(&p, "new")
	testing.expect_value(t, ui.text_string(&m.password), "new")
}
