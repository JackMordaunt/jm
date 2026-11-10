package primer

import "core:strings"
import "core:testing"
import "jm:ui"

// An action menu's inline controls: a switch and a segmented control at the
// end of a row, driven through ui.Probe by tags.

@(private = "file")
Inline_Model :: struct {
	open:    bool,
	on:      bool,
	flips:   int,
	chosen:  string,
	theme:   int,
	changes: int,
}

@(private = "file")
inline_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Inline_Model)(user)
	st := ui.stack_open(gtx)
	defer ui.close(&st)

	action_menu_button(gtx, "Menu", &m.open)
	mn := action_menu_open(gtx, &m.open, ui.last_widget(gtx), name = "Menu")
	defer action_menu_close(&mn)

	if action_menu_item(&mn, "Top", leading = .Gear) {
		m.chosen = "Top"
	}

	chosen, flipped := action_menu_item_switch(&mn, "Updates", &m.on, "Automatic checks", leading = .Sync)
	if chosen {
		m.chosen = "Updates"
	}
	if flipped {
		m.flips += 1
	}

	segments := [3]Segment{{label = "Auto", icon = .Device_Desktop}, {label = "Light", icon = .Sun}, {label = "Dark", icon = .Moon}}
	if action_menu_item_segmented(&mn, "Theme", segments[:], &m.theme, "Theme choice", leading = .Sun) {
		m.changes += 1
	}

	if action_menu_item(&mn, "Bottom") {
		m.chosen = "Bottom"
	}
}

@(private = "file")
inline_probe :: proc(p: ^ui.Probe, m: ^Inline_Model) {
	ui.probe_init(p, inline_view, m, {800, 600}, allocator = context.temp_allocator)
	m.open = true
}

@(test)
test_a_press_on_an_item_switch_flips_it_and_leaves_the_item_and_menu :: proc(t: ^testing.T) {
	m: Inline_Model
	p: ui.Probe
	inline_probe(&p, &m)
	defer ui.probe_destroy(&p)

	defer free_all(context.temp_allocator)

	ui.probe_frame(&p)
	ui.probe_frame(&p)

	testing.expect(t, ui.probe_click(&p, "Automatic checks"))
	testing.expect(t, m.on)
	testing.expect_value(t, m.flips, 1)
	testing.expect_value(t, m.chosen, "")
	testing.expect(t, m.open)
	ui.probe_click(&p, "Automatic checks")
	testing.expect(t, !m.on)
	testing.expect_value(t, m.flips, 2)
	testing.expect(t, m.open)
	// The label is the row: it chooses and closes.
	testing.expect(t, ui.probe_click(&p, "Updates"))
	testing.expect_value(t, m.chosen, "Updates")
	testing.expect(t, !m.open)
	testing.expect(t, !m.on)
}

@(test)
test_left_and_right_operate_an_item_switch_and_up_and_down_move_rows :: proc(t: ^testing.T) {
	m: Inline_Model
	p: ui.Probe
	inline_probe(&p, &m)
	defer ui.probe_destroy(&p)

	defer free_all(context.temp_allocator)

	ui.probe_frame(&p)
	ui.probe_frame(&p)

	testing.expect_value(t, ui.probe_focus_name(&p), "Top") // an open menu starts on its first item
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Updates")
	ui.probe_key(&p, .Right)
	testing.expect(t, m.on)
	ui.probe_key(&p, .Right) // already on: no change
	testing.expect_value(t, m.flips, 1)
	ui.probe_key(&p, .Left)
	testing.expect(t, !m.on)
	testing.expect_value(t, m.flips, 2)
	testing.expect_value(t, ui.probe_focus_name(&p), "Updates")
	testing.expect(t, m.open)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Theme")
	ui.probe_key(&p, .Up)
	testing.expect_value(t, ui.probe_focus_name(&p), "Updates")
	// Enter chooses the row, not the switch.
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.chosen, "Updates")
	testing.expect(t, !m.on)
	testing.expect(t, !m.open)
}

@(test)
test_a_press_on_a_segment_selects_it_and_keeps_the_menu_open :: proc(t: ^testing.T) {
	m: Inline_Model
	p: ui.Probe
	inline_probe(&p, &m)
	defer ui.probe_destroy(&p)

	defer free_all(context.temp_allocator)

	ui.probe_frame(&p)
	ui.probe_frame(&p)

	testing.expect(t, ui.probe_click(&p, "Dark"))
	testing.expect_value(t, m.theme, 2)
	testing.expect_value(t, m.changes, 1)
	testing.expect(t, m.open)
	testing.expect_value(t, m.chosen, "")
	ui.probe_click(&p, "Light")
	testing.expect_value(t, m.theme, 1)
	testing.expect(t, m.open)
	ui.probe_click(&p, "Light") // already selected: no change
	testing.expect_value(t, m.changes, 2)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "Dark"), "%s", sem)
}

@(test)
test_arrows_and_enter_operate_a_segmented_item_from_the_keyboard :: proc(t: ^testing.T) {
	m: Inline_Model
	p: ui.Probe
	inline_probe(&p, &m)
	defer ui.probe_destroy(&p)

	defer free_all(context.temp_allocator)

	ui.probe_frame(&p)
	ui.probe_frame(&p)

	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Theme")
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.theme, 1)
	ui.probe_key(&p, .Right)
	ui.probe_key(&p, .Right) // stops at the end
	testing.expect_value(t, m.theme, 2)
	testing.expect_value(t, m.changes, 2)
	ui.probe_key(&p, .Left)
	testing.expect_value(t, m.theme, 1)
	ui.probe_key(&p, .Enter) // the next, wrapping
	testing.expect_value(t, m.theme, 2)
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.theme, 0)
	testing.expect(t, m.open)
	testing.expect_value(t, ui.probe_focus_name(&p), "Theme")
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Bottom")
	testing.expect_value(t, m.chosen, "")
}

@(test)
test_an_item_control_is_not_a_tab_stop_and_names_its_segments :: proc(t: ^testing.T) {
	m: Inline_Model
	p: ui.Probe
	inline_probe(&p, &m)
	defer ui.probe_destroy(&p)

	defer free_all(context.temp_allocator)

	ui.probe_frame(&p)
	ui.probe_frame(&p)

	for name in ([]string{"Automatic checks", "Auto", "Light", "Dark"}) {
		testing.expectf(t, ui.probe_tagged(&p, name), "no %q", name)
	}
	ui.probe_click(&p, "Dark")
	// A press on a segment leaves focus on its row, so the arrows keep moving.
	testing.expect_value(t, ui.probe_focus_name(&p), "Theme")
	ui.probe_key(&p, .Up)
	testing.expect_value(t, ui.probe_focus_name(&p), "Updates")

	// Tab never lands on a control: the rows are the stops.
	for _ in 0 ..< 6 {
		ui.probe_key(&p, .Tab)
		focus := ui.probe_focus_name(&p)
		for name in ([]string{"Automatic checks", "Auto", "Light", "Dark"}) {
			testing.expectf(t, focus != name, "Tab focused the control %q", name)
		}
	}
}

// A button size XSmall is the 24px of a small switch and an inline control, so
// a row of them lines up.
@(test)
test_xsmall_button_is_24px_like_the_inline_controls :: proc(t: ^testing.T) {
	testing.expect_value(t, button_metrics(.XSmall).height, INLINE_HEIGHT)
	testing.expect_value(t, button_metrics(.XSmall).height, f32(24))
}
