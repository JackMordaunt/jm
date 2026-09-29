package material

import "core:testing"
import "jm:ui"

// Behaviour of the selection group — checkbox, radio button, switch,
// chips, text field, autocomplete — driven through ui.Probe by tag.

@(private = "file")
Sel_Model :: struct {
	agree, mixed, wifi:   bool,
	size:                 int,
	sel_changes:          int,
	filter, assist_sel:   bool,
	assist_clicks:        int,
	removed:              bool,
	name, code, amount:   ui.Text_State,
	cleared:              bool,
	fruit:                ui.Text_State,
	open:                 bool,
	picked:               int,
}

@(private = "file")
FRUIT := [?]string{"Apple", "Apricot", "Banana", "Cherry"}

@(private = "file")
sel_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Sel_Model)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	checkbox(gtx, &m.agree, "Agree")
	checkbox(gtx, &m.mixed, "Parent", indeterminate = true)
	if radio_button(gtx, &m.size, 0, "Small") {
		m.sel_changes += 1
	}
	if radio_button(gtx, &m.size, 1, "Large") {
		m.sel_changes += 1
	}
	switch_(gtx, &m.wifi, "Wi-Fi", icons = true)
	chip(gtx, "Lunch", .Filter, &m.filter, shape_morph = true)
	if chip(gtx, "Directions", .Assist, &m.assist_sel, leading = .Directions_Car) {
		m.assist_clicks += 1
	}
	chip(gtx, "Ali", .Input, nil, avatar = .Account_Circle, removed = &m.removed)
	text_field(gtx, &m.name, "Name", prefix = "Dr", max_length = 3)
	text_field(gtx, &m.code, "Code", .Outlined, read_only = true)
	text_field(gtx, &m.amount, "Amount", trailing = .Cancel, trailing_action = &m.cleared)
	if i := autocomplete(gtx, &m.fruit, "Fruit", FRUIT[:], &m.open); i >= 0 {
		m.picked = i
	}
}

@(private = "file")
sel_probe :: proc(p: ^ui.Probe, m: ^Sel_Model) {
	ui.probe_init(p, sel_view, m, {400, 1400}, allocator = context.temp_allocator)
}

@(private = "file")
sel_destroy :: proc(m: ^Sel_Model) {
	ui.text_destroy(&m.name)
	ui.text_destroy(&m.code)
	ui.text_destroy(&m.amount)
	ui.text_destroy(&m.fruit)
}

// settles runs frames until nothing asks for another, at most n of them.
@(private = "file")
settles :: proc(p: ^ui.Probe, n: int) -> bool {
	for _ in 0 ..< n {
		ui.probe_frame(p)
		if !p.wants_frame {
			return true
		}
	}
	return false
}

@(test)
test_checkbox_toggles_by_click_and_space_and_resolves_indeterminate :: proc(t: ^testing.T) {
	m: Sel_Model
	defer sel_destroy(&m)
	p: ui.Probe
	sel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Agree"))
	testing.expect(t, m.agree)
	// Focused by the click, Space unchecks it.
	ui.probe_key(&p, .Space)
	testing.expect(t, !m.agree)
	// The mark's draw-in, colour fade and the 100ms hold on uncheck all end.
	testing.expect(t, settles(&p, 120))
	// A tap on an indeterminate box checks it; it never cycles back into
	// indeterminate by itself (checkbox.json behaviour).
	testing.expect(t, ui.probe_click(&p, "Parent"))
	testing.expect(t, m.mixed)
}

@(test)
test_radio_reports_only_a_change_of_selection :: proc(t: ^testing.T) {
	m: Sel_Model
	defer sel_destroy(&m)
	p: ui.Probe
	sel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Large"))
	testing.expect_value(t, m.size, 1)
	testing.expect(t, ui.probe_click(&p, "Large"))
	testing.expect_value(t, m.sel_changes, 1)
	testing.expect(t, ui.probe_click(&p, "Small"))
	testing.expect_value(t, m.size, 0)
	testing.expect_value(t, m.sel_changes, 2)
	testing.expect(t, settles(&p, 120))
}

@(test)
test_switch_toggles_by_click_and_enter_and_its_handle_settles :: proc(t: ^testing.T) {
	m: Sel_Model
	defer sel_destroy(&m)
	p: ui.Probe
	sel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Wi-Fi"))
	testing.expect(t, m.wifi)
	testing.expect(t, settles(&p, 120))
	ui.probe_key(&p, .Enter)
	testing.expect(t, !m.wifi)
	testing.expect(t, settles(&p, 120))
}

@(test)
test_chips_select_act_and_remove :: proc(t: ^testing.T) {
	m: Sel_Model
	defer sel_destroy(&m)
	p: ui.Probe
	sel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// A filter chip toggles, by click and by Space; its check and corner
	// morph settle.
	testing.expect(t, ui.probe_click(&p, "Lunch"))
	testing.expect(t, m.filter)
	testing.expect(t, settles(&p, 120))
	ui.probe_key(&p, .Space)
	testing.expect(t, !m.filter)
	// An assist chip is a button: selected has no effect on it.
	testing.expect(t, ui.probe_click(&p, "Directions"))
	testing.expect_value(t, m.assist_clicks, 1)
	testing.expect(t, !m.assist_sel)
	// An input chip's close is its own named target.
	testing.expect(t, ui.probe_click(&p, "Ali"))
	testing.expect(t, !m.removed)
	testing.expect(t, ui.probe_click(&p, "remove Ali"))
	testing.expect(t, m.removed)
}

@(test)
test_text_field_keeps_input_past_its_counter_and_read_only_and_trailing_action :: proc(t: ^testing.T) {
	m: Sel_Model
	defer sel_destroy(&m)
	p: ui.Probe
	sel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Name counts to 3: typing past it keeps every character, and its
	// "Dr" prefix is drawn beside the text, never inserted into it.
	testing.expect(t, ui.probe_click(&p, "Name"))
	ui.probe_type(&p, "Grace")
	testing.expect_value(t, ui.text_string(&m.name), "Grace")
	// A read-only field takes focus and moves its caret, but takes no edits.
	ui.text_set(&m.code, "X1")
	testing.expect(t, ui.probe_click(&p, "Code"))
	ui.probe_key(&p, .Home)
	testing.expect_value(t, m.code.cursor, 0)
	ui.probe_key(&p, .End)
	testing.expect_value(t, m.code.cursor, 2)
	ui.probe_type(&p, "Z")
	ui.probe_key(&p, .Backspace)
	testing.expect_value(t, ui.text_string(&m.code), "X1")
	// An actionable trailing icon is its own button.
	testing.expect(t, ui.probe_click(&p, "Amount trailing"))
	testing.expect(t, m.cleared)
	testing.expect(t, settles(&p, 120))
}

@(test)
test_autocomplete_opens_filters_and_picks :: proc(t: ^testing.T) {
	m := Sel_Model{picked = -1}
	defer sel_destroy(&m)
	p: ui.Probe
	sel_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, !has_name(&p, "Apple"))
	testing.expect(t, ui.probe_click(&p, "Fruit"))
	testing.expect(t, m.open)
	ui.probe_frame(&p)
	testing.expect(t, has_name(&p, "Cherry"))
	// Typing filters by substring.
	ui.probe_type(&p, "ap")
	ui.probe_frame(&p)
	testing.expect(t, has_name(&p, "Apple"))
	testing.expect(t, has_name(&p, "Apricot"))
	testing.expect(t, !has_name(&p, "Banana"))
	// Down, Down, Enter takes the second match.
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.picked, 1)
	testing.expect_value(t, ui.text_string(&m.fruit), "Apricot")
	testing.expect(t, !m.open)
	// Reopened on an exact match it lists everything; a click picks, and
	// Escape closes.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	testing.expect(t, has_name(&p, "Banana"))
	testing.expect(t, ui.probe_click(&p, "Banana"))
	testing.expect_value(t, m.picked, 2)
	testing.expect_value(t, ui.text_string(&m.fruit), "Banana")
	ui.probe_key(&p, .Down)
	testing.expect(t, m.open)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
}

@(private = "file")
Low_Field_Model :: struct {
	fruit: ui.Text_State,
	open:  bool,
}

// low_field puts an autocomplete near the bottom of the window.
@(private = "file")
low_field :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Low_Field_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	ui.spacer(gtx, 300)
	OPTIONS := [?]string{"Apple", "Apricot", "Banana", "Cherry"}
	autocomplete(gtx, &m.fruit, "Fruit", OPTIONS[:], &m.open)
}

@(test)
test_autocomplete_near_the_bottom_opens_above_its_field :: proc(t: ^testing.T) {
	m: Low_Field_Model
	defer ui.text_destroy(&m.fruit)
	p: ui.Probe
	ui.probe_init(&p, low_field, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Fruit"))
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	field := ui.probe_bounds(&p, "Fruit")
	for name in ([]string{"Apple", "Apricot", "Banana", "Cherry"}) {
		r := ui.probe_bounds(&p, name)
		testing.expectf(t, r.h > 0, "%s is not laid out", name)
		testing.expectf(t, r.y >= 0 && r.y + r.h <= 400, "%s at %v leaves the 400px window", name, r)
		testing.expectf(t, r.y + r.h <= field.y, "%s at %v is not above the field at %v", name, r, field)
	}
	testing.expect(t, ui.probe_click(&p, "Banana"))
	testing.expect_value(t, ui.text_string(&m.fruit), "Banana")
}
