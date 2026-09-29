package fluent

import "core:testing"
import "jm:ui"

// Behaviour of the rest of the button family, driven through ui.Probe.

@(private = "file")
Family_Model :: struct {
	bold, menu, split_menu: bool,
	saves, opens, clicks:   int,
}

@(private = "file")
family :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Family_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	toggle_button(gtx, "Bold", &m.bold, .Subtle, .Text_Bold)
	if menu_button(gtx, "Options", &m.menu) {
		m.opens += 1
	}
	if split_button(gtx, "Save", &m.split_menu, .Primary) {
		m.saves += 1
	}
	if compound_button(gtx, "Create", "Start from a blank file", ic = .Add) {
		m.clicks += 1
	}
	compound_button(gtx, "", "", ic = .Settings, name = "Settings", size = .Large)
	toggle_button(gtx, "Off", &m.bold, state = .Disabled, key = 1)
}

@(test)
test_toggle_button_flips_checked_and_disabled_does_not :: proc(t: ^testing.T) {
	m: Family_Model
	p: ui.Probe
	ui.probe_init(&p, family, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Bold"))
	testing.expect(t, m.bold)
	ui.probe_key(&p, .Space)
	testing.expect(t, !m.bold)
	testing.expect(t, !ui.probe_click(&p, "Off"))
	testing.expect(t, !m.bold)
	testing.expect_value(t, ui.probe_bounds(&p, "Bold").h, 32)
}

@(test)
test_menu_button_toggles_open_by_click_and_arrow :: proc(t: ^testing.T) {
	m: Family_Model
	p: ui.Probe
	ui.probe_init(&p, family, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Options"))
	testing.expect(t, m.menu)
	testing.expect_value(t, m.opens, 1)
	testing.expect(t, ui.probe_click(&p, "Options"))
	testing.expect(t, !m.menu)
	ui.probe_key(&p, .Down) // focused from the click: ArrowDown opens
	testing.expect(t, m.menu)
	ui.probe_key(&p, .Down) // open already: nothing
	testing.expect(t, m.menu)
	// Wider than a plain button of the same label: the chevron and its gap.
	testing.expect(t, ui.probe_bounds(&p, "Options").w >= 96)
}

@(test)
test_split_button_halves_act_apart :: proc(t: ^testing.T) {
	m: Family_Model
	p: ui.Probe
	ui.probe_init(&p, family, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect_value(t, m.saves, 1)
	testing.expect(t, !m.split_menu)
	testing.expect(t, ui.probe_click(&p, "Menu"))
	testing.expect(t, m.split_menu)
	testing.expect_value(t, m.saves, 1)
	save, menu := ui.probe_bounds(&p, "Save"), ui.probe_bounds(&p, "Menu")
	testing.expect_value(t, save.h, 32)
	testing.expect_value(t, menu.h, 32)
	testing.expect(t, menu.w >= 24)
	testing.expect_value(t, menu.x, save.x + save.w) // joined
}

@(test)
test_compound_button_grows_with_its_two_lines :: proc(t: ^testing.T) {
	m: Family_Model
	p: ui.Probe
	ui.probe_init(&p, family, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Create"))
	testing.expect_value(t, m.clicks, 1)
	c := ui.probe_bounds(&p, "Create")
	// 14px top, the 40px icon, 16px bottom and two 1px borders.
	testing.expect_value(t, c.h, 14 + 40 + 16 + 2)
	testing.expect(t, c.w >= 96)
	// Icon-only: a fixed square, tagged by its name.
	sq := ui.probe_bounds(&p, "Settings")
	testing.expect_value(t, sq.w, 56)
	testing.expect_value(t, sq.h, 56)
}
