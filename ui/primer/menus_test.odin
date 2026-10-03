package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import tok "jm:ui/primer/tokens"

// Behaviour of action_menu, driven through ui.Probe by tags.

@(private = "file")
Menu_Model :: struct {
	open, sub:  bool,
	chosen:     string,
	page:       int,
	keep:       bool,
	selection:  Selection_Variant,
	picked:     [3]bool,
}

@(private = "file")
menu_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Menu_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	if button(gtx, "Page") {
		m.page += 1
	}
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	action_menu_button(gtx, "Menu", &m.open)
	mn := action_menu_open(gtx, &m.open, ui.last_widget(gtx), m.selection, name = "Menu")
	for n, i in ([3]string{"Copy", "Quote", "Archive"}) {
		if action_menu_item(&mn, n, selected = m.picked[i], disabled = i == 2, keep_open = m.keep) {
			m.chosen = n
			m.picked[i] = !m.picked[i]
		}
	}
	action_menu_item(&mn, "More", submenu = &m.sub)
	action_menu_divider(&mn)
	if action_menu_item(&mn, "Delete", variant = .Danger) {
		m.chosen = "Delete"
	}
	sub := action_menu_submenu_open(&mn, &m.sub)
	for n in ([2]string{"Alpha", "Beta"}) {
		if action_menu_item(&sub, n) {
			m.chosen = n
		}
	}
	action_menu_close(&sub)
	action_menu_close(&mn)
}

@(private = "file")
menu_probe :: proc(p: ^ui.Probe, m: ^Menu_Model) {
	ui.probe_init(p, menu_view, m, {800, 600}, allocator = context.temp_allocator)
}

@(private = "file")
focus_name :: proc(p: ^ui.Probe) -> string {
	for t in ui.probe_current(p).tags {
		if t.id == p.router.focus {
			return t.name
		}
	}
	return "?"
}

@(test)
test_a_menu_opened_by_click_keeps_focus_on_its_button :: proc(t: ^testing.T) {
	m: Menu_Model
	p: ui.Probe
	menu_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Menu"))
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	testing.expect(t, ui.probe_tagged(&p, "Copy"))
	testing.expect_value(t, focus_name(&p), ("Menu"))
	// ArrowDown on the button moves focus to the first item, ArrowUp the last.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_name(&p), ("Copy"))
	ui.probe_click(&p, "Menu") // closes it
	ui.probe_frame(&p)
	testing.expect(t, !m.open)
	ui.probe_click(&p, "Menu")
	ui.probe_frame(&p)
	ui.probe_key(&p, .Up)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_name(&p), ("Delete"))
}

@(test)
test_a_menu_opened_by_key_focuses_an_item_and_escape_returns_focus :: proc(t: ^testing.T) {
	m: Menu_Model
	p: ui.Probe
	menu_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Page")
	ui.probe_key(&p, .Tab) // to the menu button
	testing.expect_value(t, focus_name(&p), ("Menu"))
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	testing.expect_value(t, focus_name(&p), ("Copy"))
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "button \"Menu\" expandable expanded"), "%s", sem)
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect(t, !m.open)
	testing.expect_value(t, focus_name(&p), ("Menu"))
	// ArrowUp on the closed button opens it at the last item.
	ui.probe_key(&p, .Up)
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	testing.expect_value(t, focus_name(&p), ("Delete"))
	// Arrows wrap; letters jump.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_name(&p), ("Copy"))
	ui.probe_key(&p, .Q)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_name(&p), ("Quote"))
}

@(test)
test_choosing_an_item_or_tab_closes_the_menu :: proc(t: ^testing.T) {
	m: Menu_Model
	p: ui.Probe
	menu_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Menu")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Quote"))
	testing.expect_value(t, m.chosen, "Quote")
	testing.expect(t, !m.open)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_name(&p), ("Menu"))
	// A disabled item does nothing and the menu stays.
	ui.probe_click(&p, "Menu")
	ui.probe_frame(&p)
	ui.probe_click(&p, "Archive")
	testing.expect(t, m.open)
	testing.expect_value(t, m.chosen, "Quote")
	// keep_open: multiple selection that stays open.
	m.keep = true
	testing.expect(t, ui.probe_click(&p, "Copy"))
	testing.expect(t, m.open && m.picked[0])
	// Tab in the menu closes it.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	testing.expect(t, !m.open)
	// A press outside closes it and still lands.
	ui.probe_click(&p, "Menu")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Page"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.page, 1)
}

@(test)
test_a_submenu_opens_on_right_and_closes_on_left :: proc(t: ^testing.T) {
	m: Menu_Model
	p: ui.Probe
	menu_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Page")
	ui.probe_key(&p, .Tab)
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	for _ in 0 ..< 3 {
		ui.probe_key(&p, .Down)
	}
	ui.probe_frame(&p)
	testing.expect_value(t, focus_name(&p), ("More"))
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, m.sub)
	testing.expect_value(t, focus_name(&p), ("Alpha"))
	// It hangs to the right of its item.
	more, alpha := ui.probe_bounds(&p, "More"), ui.probe_bounds(&p, "Alpha")
	testing.expect(t, alpha.x > more.x + more.w)
	ui.probe_key(&p, .Left)
	ui.probe_frame(&p)
	testing.expect(t, !m.sub && m.open)
	testing.expect_value(t, focus_name(&p), ("More"))
	// Choosing in the submenu closes every menu.
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.chosen, "Beta")
	testing.expect(t, !m.sub && !m.open)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_name(&p), ("Menu"))
}

@(test)
test_a_menu_hangs_4px_below_its_button_at_least_192px_wide :: proc(t: ^testing.T) {
	m := Menu_Model{open = true}
	p: ui.Probe
	menu_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 20, 1.0 / 60)
	button := ui.probe_bounds(&p, "Menu")
	copy := ui.probe_bounds(&p, "Copy")
	// The overlay's top is 4px under the button; the list pads 8px.
	testing.expect_value(t, copy.y, button.y + button.h + tok.OVERLAY_OFFSET + tok.BASE_SIZE_8)
	testing.expect_value(t, copy.x, button.x + tok.BASE_SIZE_8)
	testing.expect_value(t, copy.w, OVERLAY_MIN_WIDTH - 2 * tok.BASE_SIZE_8)
	testing.expect_value(t, copy.h, tok.CONTROL_MEDIUM_SIZE)
	// Multiple selection in a menu: a checkmark, and a checkbox role.
	m.selection = .Multiple
	m.picked[1] = true
	ui.probe_frame(&p)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "menu item checkbox \"Quote\" checked"), "%s", sem)
}
