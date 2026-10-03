package fluent

import "core:testing"
import "jm:ui"

// Behaviour of the form controls, driven through ui.Probe by their tags.

@(private = "file")
Form_Model :: struct {
	agree, off: bool,
	on:         bool,
	choice:     int,
	volume:     f32,
	locked:     f32,
}

@(private = "file")
RADIOS := [?]string{"First", "Second", "Third"}

@(private = "file")
form :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Form_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	checkbox(gtx, &m.agree, "Agree")
	checkbox(gtx, &m.off, "Off", state = .Disabled)
	radio_group(gtx, RADIOS[:], &m.choice)
	toggle_switch(gtx, &m.on, "Dark")
	slider(gtx, &m.volume, 0, 100, 1, 220, name = "Volume")
	slider(gtx, &m.locked, 0, 100, 1, 220, name = "Locked", state = .Disabled)
}

@(test)
test_checkbox_and_switch_toggle_by_click_and_space :: proc(t: ^testing.T) {
	m := Form_Model{choice = -1}
	p: ui.Probe
	ui.probe_init(&p, form, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Agree"))
	testing.expect(t, m.agree)
	ui.probe_key(&p, .Space) // focused by the click
	testing.expect(t, !m.agree)
	testing.expect(t, !ui.probe_click(&p, "Off")) // disabled: no input area
	testing.expect(t, !m.off)
	testing.expect(t, ui.probe_click(&p, "Dark"))
	testing.expect(t, m.on)
	ui.probe_key(&p, .Space)
	testing.expect(t, !m.on)
}

@(test)
test_radio_group_selects_by_click_and_arrows :: proc(t: ^testing.T) {
	m := Form_Model{choice = -1}
	p: ui.Probe
	ui.probe_init(&p, form, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Second"))
	testing.expect_value(t, m.choice, 1)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, m.choice, 2)
	ui.probe_key(&p, .Down) // wraps
	testing.expect_value(t, m.choice, 0)
	ui.probe_key(&p, .Up)
	testing.expect_value(t, m.choice, 2)
	ui.probe_key(&p, .Left)
	testing.expect_value(t, m.choice, 1)
	testing.expect_value(t, focused_tag(&p), "Second") // focus moves with the selection
	// One Tab stop, entered at the selected radio, which Tab does not change.
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, focused_tag(&p), "Dark") // out of the group to the switch
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, focused_tag(&p), "Second")
	testing.expect_value(t, m.choice, 1)
	testing.expect(t, ui.probe_click(&p, "First"))
	testing.expect_value(t, m.choice, 0)
}

@(test)
test_slider_jumps_on_press_and_steps_by_key :: proc(t: ^testing.T) {
	m := Form_Model{choice = -1}
	p: ui.Probe
	ui.probe_init(&p, form, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Volume")) // the centre: half way
	testing.expect_value(t, m.volume, 50)
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.volume, 51)
	ui.probe_key(&p, .Page_Down)
	testing.expect_value(t, m.volume, 41)
	ui.probe_key(&p, .Home)
	testing.expect_value(t, m.volume, 0)
	ui.probe_key(&p, .End)
	testing.expect_value(t, m.volume, 100)
	ui.probe_key(&p, .Left)
	testing.expect_value(t, m.volume, 99)
	// A drag from the centre to the right end.
	c := ui.probe_bounds(&p, "Volume")
	ui.probe_move(&p, c.x + c.w / 2, c.y + c.h / 2)
	ui.router_push(&p.router, {kind = .Press, pos = {c.x + c.w / 2, c.y + c.h / 2}, button = .Left})
	ui.probe_frame(&p)
	ui.probe_move(&p, c.x + c.w, c.y + c.h / 2)
	testing.expect_value(t, m.volume, 100)
	ui.router_push(&p.router, {kind = .Release, pos = {c.x + c.w, c.y + c.h / 2}, button = .Left})
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_click(&p, "Locked"))
	testing.expect_value(t, m.locked, 0)
}

@(test)
test_form_control_sizes_follow_the_styles_files :: proc(t: ^testing.T) {
	m := Form_Model{choice = -1}
	p: ui.Probe
	ui.probe_init(&p, form, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	agree := ui.probe_bounds(&p, "Agree")
	testing.expect_value(t, agree.h, 32) // a 16px box in 8px margins
	first := ui.probe_bounds(&p, "First")
	second := ui.probe_bounds(&p, "Second")
	testing.expect_value(t, first.h, 32)
	testing.expect_value(t, second.y - first.y, 32) // rows touch: no gap
	dark := ui.probe_bounds(&p, "Dark")
	testing.expect_value(t, dark.h, 36) // a 20px track in 8px margins
	vol := ui.probe_bounds(&p, "Volume")
	testing.expect_value(t, vol.w, 220)
	testing.expect_value(t, vol.h, 32)
}
