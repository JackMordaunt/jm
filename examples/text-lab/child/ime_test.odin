package main

import "core:fmt"
import "core:testing"
import "jm:ui"
import "jm:ui/render"

// open_ime_lab opens the Input method page headlessly, in the lab's fonts.
@(private = "file")
open_ime_lab :: proc(h: ^render.Headless, m: ^Model) {
	m.size = 2
	fonts := lab_fonts(m)
	for p, i in PAGES {
		if p.draw == page_ime {
			m.page = i
		}
	}
	render.headless_init(h, lab_ui, m, {WIDTH, HEIGHT}, fonts, fallbacks = lab_fallbacks(m))
}

// play clicks the step button of composition name n times.
@(private = "file")
play :: proc(t: ^testing.T, h: ^render.Headless, name: string, n: int) {
	for _ in 0 ..< n {
		testing.expectf(t, ui.probe_click(&h.p, fmt.tprintf("step %s", name)), "no step button for %s", name)
		ui.probe_frame(&h.p)
	}
}

@(test)
test_a_scripted_composition_shows_its_preedit_then_commits :: proc(t: ^testing.T) {
	// The lab's fonts and fields live as long as the lab: here, the test.
	context.allocator = context.temp_allocator
	m: Model
	h: render.Headless
	defer free_all(context.temp_allocator)
	open_ime_lab(&h, &m)
	defer render.headless_destroy(&h)
	field := &m.ime.fields[0]

	testing.expect(t, ui.probe_click(&h.p, "CJK field"))
	ime := h.p.text_input
	testing.expect(t, ime.active)
	testing.expect_value(t, ime.area, m.ime.ids[0])

	// Converted, the second clause targeted: shown, not committed, and
	// the input method's caret moved to the target.
	play(t, &h, "Japanese: three clauses", 3)
	testing.expect_value(t, ui.text_string(field), "")
	shown := ui.text_display(field)
	testing.expect_value(t, shown.text, "今日はいい天気")
	testing.expect_value(t, shown.text[shown.target_lo:shown.target_hi], "いい")
	testing.expect(t, h.p.text_input.caret > ime.caret, "the input method's caret did not follow the target clause")

	play(t, &h, "Japanese: three clauses", 2)
	testing.expect_value(t, ui.text_string(field), "今日はいい天気")
	testing.expect(t, !ui.text_composing(field))
	testing.expect(t, ui.text_undo(field))
	testing.expect_value(t, ui.text_string(field), "")
}

@(test)
test_korean_commits_a_syllable_at_a_time_and_a_cancel_commits_nothing :: proc(t: ^testing.T) {
	// The lab's fonts and fields live as long as the lab: here, the test.
	context.allocator = context.temp_allocator
	m: Model
	h: render.Headless
	defer free_all(context.temp_allocator)
	open_ime_lab(&h, &m)
	defer render.headless_destroy(&h)
	field := &m.ime.fields[0]

	testing.expect(t, ui.probe_click(&h.p, "CJK field"))
	play(t, &h, "Korean: syllable by syllable", 5)
	testing.expect_value(t, ui.text_string(field), "한")
	testing.expect_value(t, ui.text_display(field).text, "한ㄱ")
	play(t, &h, "Korean: syllable by syllable", 3)
	testing.expect_value(t, ui.text_string(field), "한글")

	play(t, &h, "Cancelled", 3)
	testing.expect_value(t, ui.text_string(field), "한글")
	testing.expect(t, !ui.text_composing(field))
}

@(test)
test_the_step_buttons_leave_the_field_focused :: proc(t: ^testing.T) {
	// The lab's fonts and fields live as long as the lab: here, the test.
	context.allocator = context.temp_allocator
	m: Model
	h: render.Headless
	defer free_all(context.temp_allocator)
	open_ime_lab(&h, &m)
	defer render.headless_destroy(&h)

	// With no field focused the steps have nowhere to go, and their
	// buttons take no click.
	testing.expect(t, !ui.probe_click(&h.p, "step Cancelled"))
	testing.expect(t, !h.p.text_input.active)

	testing.expect(t, ui.probe_click(&h.p, "Textarea field"))
	play(t, &h, "Japanese: かな → 仮名", 4)
	testing.expect_value(t, m.ime.focus, len(IME_FIELDS))
	testing.expect_value(t, ui.text_display(&m.ime.area).text, "かな")
	testing.expect_value(t, h.p.text_input.area, m.ime.ids[len(IME_FIELDS)])
	line := h.p.text_input.rect.h
	testing.expectf(t, line > 0 && line < 40, "a textarea tells the caret's line, not its box: %.0f px", line)
}
