package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of button, driven through ui.Probe by its tags.

@(private = "file")
Buttons_Model :: struct {
	saves, sends, adds, offs: int,
}

@(private = "file")
buttons :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Buttons_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if button(gtx, "Save", .Primary) {
		m.saves += 1
	}
	if button(gtx, "Send", .Subtle, .Send, size = .Small) {
		m.sends += 1
	}
	if button(gtx, "", .Secondary, .Add, size = .Large, name = "Add") {
		m.adds += 1
	}
	if button(gtx, "Off", state = .Disabled) {
		m.offs += 1
	}
	button(gtx, "Go", size = .Small)
	button(gtx, "Wide", .Outline, .Settings, icon_position = .After, shape = .Circular)
}

@(test)
test_button_activates_by_click_and_keyboard_and_not_when_disabled :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect_value(t, m.saves, 1)
	// Focused by the click, Enter activates it again; Space too.
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.saves, 2)
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.saves, 3)
	// An icon-only button is tagged by its name.
	testing.expect(t, ui.probe_click(&p, "Add"))
	testing.expect_value(t, m.adds, 1)
	// A disabled button registers no input area, so a click finds nothing.
	testing.expect(t, !ui.probe_click(&p, "Off"))
	testing.expect_value(t, m.offs, 0)
}

@(test)
test_button_sizes_follow_the_styles_file :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	save := ui.probe_bounds(&p, "Save")
	testing.expect_value(t, save.h, 32) // medium: 5px padding, 20px line, 1px borders
	testing.expect_value(t, save.w, 96) // the medium minimum width
	send := ui.probe_bounds(&p, "Send")
	testing.expect_value(t, send.h, 24) // small with an icon: 1px padding, 20px icon, 1px borders
	testing.expect(t, send.w > 64) // its content outgrows the small minimum
	testing.expect_value(t, ui.probe_bounds(&p, "Go").w, 64) // the small minimum width
	testing.expect_value(t, ui.probe_bounds(&p, "Go").h, 24)
	add := ui.probe_bounds(&p, "Add")
	testing.expect_value(t, add, ops.Rect{add.x, add.y, 40, 40}) // large icon-only: square
	wide := ui.probe_bounds(&p, "Wide")
	testing.expect_value(t, wide.h, 32)
	testing.expect(t, wide.w >= 96)
}
