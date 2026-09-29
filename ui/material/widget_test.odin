package material

import "core:testing"
import "jm:ui"

// Behaviour of the live components, driven through ui.Probe by their tags.

@(private = "file")
Model :: struct {
	agree:    bool,
	radio:    int,
	on:       bool,
	tab:      int,
	filter:   bool,
	removed:  bool,
	name:     ui.Text_State,
	clicks:   int,
	selected: int,
}

@(private = "file")
controls :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	checkbox(gtx, &m.agree, "Agree")
	radio_button(gtx, &m.radio, 0, "Small")
	radio_button(gtx, &m.radio, 1, "Large")
	switch_(gtx, &m.on, "Wi-Fi")
	LABELS := [?]string{"Video", "Photos"}
	tabs(gtx, LABELS[:], &m.tab, width = 300)
	chip(gtx, "Lunch", .Filter, &m.filter)
	off := false
	chip(gtx, "Ali", .Input, &off, removed = &m.removed)
	text_field(gtx, &m.name, "Name")
	if button(gtx, "Save") {
		m.clicks += 1
	}
	if button(gtx, "Off", state = .Disabled) {
		m.clicks += 100
	}
	ITEMS := [?]Nav_Item{{label = "Inbox", icon = .Inbox}, {label = "Sent", icon = .Send}}
	navigation_bar(gtx, ITEMS[:], &m.selected, 300)
}

@(test)
test_live_controls_respond_to_clicks :: proc(t: ^testing.T) {
	m: Model
	defer ui.text_destroy(&m.name)
	p: ui.Probe
	ui.probe_init(&p, controls, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Agree"))
	testing.expect(t, m.agree)
	testing.expect(t, ui.probe_click(&p, "Large"))
	testing.expect_value(t, m.radio, 1)
	testing.expect(t, ui.probe_click(&p, "Wi-Fi"))
	testing.expect(t, m.on)
	testing.expect(t, ui.probe_click(&p, "Photos"))
	testing.expect_value(t, m.tab, 1)
	testing.expect(t, ui.probe_click(&p, "Lunch"))
	testing.expect(t, m.filter)
	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect_value(t, m.clicks, 1)
	testing.expect(t, ui.probe_click(&p, "Sent"))
	testing.expect_value(t, m.selected, 1)
	// A disabled button is laid out but registers no input area to click.
	testing.expect(t, has_name(&p, "Off"))
	testing.expect(t, !ui.probe_click(&p, "Off"))
	testing.expect_value(t, m.clicks, 1)
	// The input chip's body is not its close icon; the close icon removes.
	testing.expect(t, ui.probe_click(&p, "Ali"))
	testing.expect(t, !m.removed)
	testing.expect(t, ui.probe_click(&p, "remove Ali"))
	testing.expect(t, m.removed)
}

@(test)
test_text_field_takes_focus_and_text :: proc(t: ^testing.T) {
	m: Model
	defer ui.text_destroy(&m.name)
	p: ui.Probe
	ui.probe_init(&p, controls, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Name"))
	ui.probe_type(&p, "Ada")
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, ui.text_string(&m.name), "Ad")
}

@(test)
test_forced_states_take_no_input :: proc(t: ^testing.T) {
	forced :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Model)(user)
		col := ui.column_open(gtx)
		defer ui.close(&col)
		checkbox(gtx, &m.agree, "Agree", state = .Hovered)
		checkbox(gtx, &m.on, "Live")
	}
	m: Model
	p: ui.Probe
	ui.probe_init(&p, forced, &m, {200, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// The forced one is laid out, yet offers nothing to click; its live
	// twin in the same frame does.
	testing.expect(t, has_name(&p, "Agree"))
	testing.expect(t, !ui.probe_click(&p, "Agree"))
	testing.expect(t, !m.agree)
	testing.expect(t, ui.probe_click(&p, "Live"))
	testing.expect(t, m.on)
}

// has_name reports whether the probe's current frame tags name. Shared by
// the package's tests.
@(private)
has_name :: proc(p: ^ui.Probe, name: string) -> bool {
	for n in ui.probe_names(p) {
		if n == name {
			return true
		}
	}
	return false
}

@(private = "file")
Overlay_Model :: struct {
	menu_open, dialog_open: bool,
	picked, chose:          int,
	under:                  int,
}

@(private = "file")
overlays :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Overlay_Model)(user)
	// A row, so "Under" is beside the menu, not beneath one of its items.
	r := ui.row_open(gtx, gap = 8)
	defer ui.close(&r)
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		if button(gtx, "Edit") {
			m.menu_open = true
		}
		ITEMS := [?]Menu_Item{{label = "Cut"}, {label = "Copy"}}
		if i := menu(gtx, &m.menu_open, ITEMS[:]); i >= 0 {
			m.picked = i
		}
	}
	if button(gtx, "Under") {
		m.under += 1
	}
	ACTIONS := [?]string{"Cancel", "OK"}
	if i := dialog(gtx, &m.dialog_open, {400, 400}, "Title", "Body", ACTIONS[:]); i >= 0 {
		m.chose = i
	}
}

@(test)
test_menu_picks_and_closes_and_its_scrim_blocks_the_page :: proc(t: ^testing.T) {
	m := Overlay_Model{picked = -1, chose = -1}
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Edit"))
	testing.expect(t, m.menu_open)
	// The open menu's scrim takes a click meant for the page and closes it.
	testing.expect(t, ui.probe_click(&p, "Under"))
	testing.expect_value(t, m.under, 0)
	testing.expect(t, !m.menu_open)

	ui.probe_click(&p, "Edit")
	testing.expect(t, ui.probe_click(&p, "Copy"))
	testing.expect_value(t, m.picked, 1)
	testing.expect(t, !m.menu_open)
	testing.expect(t, ui.probe_click(&p, "Under"))
	testing.expect_value(t, m.under, 1)
}

@(test)
test_dialog_returns_the_action_and_closes :: proc(t: ^testing.T) {
	m := Overlay_Model{picked = -1, chose = -1, dialog_open = true}
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p) // hits from the first frame
	testing.expect(t, ui.probe_click(&p, "OK"))
	testing.expect_value(t, m.chose, 1)
	testing.expect(t, !m.dialog_open)
}

@(test)
test_slider_steps_by_key_and_button_group_selects_one :: proc(t: ^testing.T) {
	M :: struct {
		v:   f32,
		sel: [3]bool,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		col := ui.column_open(gtx, gap = 8)
		defer ui.close(&col)
		slider(gtx, &m.v, 0, 100, 10)
		LABELS := [?]string{"A", "B", "C"}
		button_group(gtx, LABELS[:], m.sel[:])
	}
	m := M{v = 20} // off the midpoint, so the click must move it
	p: ui.Probe
	ui.probe_init(&p, view, &m, {300, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// A click at the slider's centre sets the midpoint and focuses it.
	testing.expect(t, ui.probe_click(&p, "slider"))
	testing.expect_value(t, m.v, 50)
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.v, 60)
	ui.probe_key(&p, .End)
	testing.expect_value(t, m.v, 100)

	testing.expect(t, ui.probe_click(&p, "B"))
	testing.expect(t, ui.probe_click(&p, "C"))
	testing.expect_value(t, m.sel, [3]bool{false, false, true})
}

@(test)
test_search_view_filters_and_picks :: proc(t: ^testing.T) {
	M :: struct {
		q:      ui.Text_State,
		picked: int,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		SUGGESTIONS := [?]string{"Material", "Motion", "Shape"}
		if i := search_bar(gtx, &m.q, "Find", suggestions = SUGGESTIONS[:]); i >= 0 {
			m.picked = i
		}
	}
	m := M{picked = -1}
	defer ui.text_destroy(&m.q)
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Find"))
	ui.probe_frame(&p)
	testing.expect(t, has_name(&p, "Shape")) // focused and empty: everything matches
	ui.probe_type(&p, "M")
	ui.probe_frame(&p)
	testing.expect(t, has_name(&p, "Motion"))
	testing.expect(t, !has_name(&p, "Shape"))
	testing.expect(t, ui.probe_click(&p, "Motion"))
	testing.expect_value(t, m.picked, 1)
	testing.expect_value(t, ui.text_string(&m.q), "Motion")
	ui.probe_frame(&p)
	testing.expect(t, !has_name(&p, "Material")) // dismissed until the text changes
}

@(test)
test_date_picker_selects_a_clicked_day :: proc(t: ^testing.T) {
	M :: struct {
		sel, view: Date,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		date_picker(gtx, &m.sel, &m.view, {2026, 9, 28})
	}
	m := M{sel = {2026, 9, 28}}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, m.view, Date{2026, 9, 1})
	// Day cells are tagged with their date.
	testing.expect(t, ui.probe_click(&p, "2026-09-01"))
	testing.expect_value(t, m.sel, Date{2026, 9, 1})
}

@(private = "file")
Low_Menu_Model :: struct {
	open: bool,
}

// low_menu puts a menu's anchor button near the bottom of the window.
@(private = "file")
low_menu :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Low_Menu_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	ui.spacer(gtx, 250)
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	if button(gtx, "Edit") {
		m.open = true
	}
	ITEMS := [?]Menu_Item{{label = "Cut"}, {label = "Copy"}, {label = "Paste"}}
	menu(gtx, &m.open, ITEMS[:])
}

@(test)
test_menu_near_the_bottom_opens_above_its_anchor :: proc(t: ^testing.T) {
	m: Low_Menu_Model
	p: ui.Probe
	ui.probe_init(&p, low_menu, &m, {400, 320}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Edit"))
	ui.probe_advance(&p, 60, 0.016) // the open springs settle
	edit := ui.probe_bounds(&p, "Edit")
	for name in ([]string{"Cut", "Copy", "Paste"}) {
		r := ui.probe_bounds(&p, name)
		testing.expectf(t, r.h > 0, "%s is not laid out", name)
		testing.expectf(t, r.y >= 0 && r.y + r.h <= 320, "%s at %v leaves the 320px window", name, r)
		testing.expectf(t, r.y + r.h <= edit.y, "%s at %v is not above Edit at %v", name, r, edit)
	}
	// The items still pick.
	testing.expect(t, ui.probe_click(&p, "Copy"))
	testing.expect(t, !m.open)
}
