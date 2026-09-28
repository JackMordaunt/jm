package material

import "core:testing"
import "jm:ui"

// The surfaces group's caller-owned state: a bottom sheet's Sheet_State, a
// date picker's Date_Picker_State and a carousel's Carousel_State are
// honoured when passed, and kept internally when not.

// click_at presses and releases at device point pt, a frame each.
@(private = "file")
click_at :: proc(p: ^ui.Probe, pt: ui.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = pt})
	ui.router_push(&p.router, {kind = .Press, pos = pt})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Release, pos = pt})
	ui.probe_frame(p)
}

@(private = "file")
Sheet_State_Model :: struct {
	open, owned: bool,
	state:       Sheet_State,
}

@(private = "file")
sheet_state_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Sheet_State_Model)(user)
	sh := bottom_sheet(gtx, &m.open, {400, 600}, state = m.owned ? &m.state : nil)
	if sh.visible {
		button(gtx, "Inside")
	}
	end_sheet(&sh)
}

@(test)
test_bottom_sheet_keeps_its_state_where_told :: proc(t: ^testing.T) {
	// Passed: the anchor, the measured height and the drag land in it.
	m := Sheet_State_Model{open = true, owned = true}
	p: ui.Probe
	ui.probe_init(&p, sheet_state_ui, &m, {400, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, has_name(&p, "Inside"))
	testing.expect_value(t, m.state.anchor, Sheet_Value.Partially_Expanded)
	// The sheet sits on the window's bottom edge, so its height is twice
	// the distance from its centre to that edge.
	body, found := ui.probe_center(&p, "sheet")
	testing.expect(t, found)
	testing.expect_value(t, m.state.height, 2 * (600 - body.y))
	c, ok := ui.probe_center(&p, "drag handle")
	testing.expect(t, ok)
	ui.router_push(&p.router, {kind = .Move, pos = c})
	ui.router_push(&p.router, {kind = .Press, pos = c})
	ui.probe_frame(&p)
	testing.expect(t, m.state.drag.dragging)
	ui.router_push(&p.router, {kind = .Release, pos = c})
	ui.probe_frame(&p)
	testing.expect(t, !m.state.drag.dragging)
	// The handle's click expanded it; the caller's anchor says so.
	testing.expect_value(t, m.state.anchor, Sheet_Value.Expanded)

	// Not passed: the sheet still works, from its own store.
	n := Sheet_State_Model{open = true}
	q: ui.Probe
	ui.probe_init(&q, sheet_state_ui, &n, {400, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&q)
	ui.probe_advance(&q, 60, 1.0 / 60)
	testing.expect(t, has_name(&q, "Inside"))
	testing.expect(t, ui.probe_click(&q, "drag handle")) // Partially_Expanded expands
	testing.expect(t, ui.probe_click(&q, "drag handle")) // Expanded hides
	testing.expect(t, !n.open)
	testing.expect_value(t, n.state, Sheet_State{})
}

@(private = "file")
Date_State_Model :: struct {
	sel, view: Date,
	input:     ui.Text_State,
	owned:     bool,
	state:     Date_Picker_State,
}

@(private = "file")
date_state_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Date_State_Model)(user)
	date_picker(gtx, &m.sel, &m.view, {2026, 9, 28}, input = &m.input, state = m.owned ? &m.state : nil)
}

@(test)
test_date_picker_keeps_its_state_where_told :: proc(t: ^testing.T) {
	// Passed: the caller opens the year menu and reads the mode back.
	m := Date_State_Model{view = {2026, 9, 1}, owned = true}
	m.state.year_open = true
	defer ui.text_destroy(&m.input)
	p: ui.Probe
	ui.probe_init(&p, date_state_ui, &m, {400, 700}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p)
	testing.expect(t, has_name(&p, "year 1900")) // opened by the caller, at the top
	testing.expect(t, !has_name(&p, "2026-09-01"))
	testing.expect(t, ui.probe_click(&p, "year menu"))
	testing.expect(t, !m.state.year_open)
	testing.expect(t, ui.probe_click(&p, "year menu"))
	testing.expect(t, m.state.year_open)
	testing.expect(t, m.state.year_scroll > 0) // opened a few years before 2026
	testing.expect(t, ui.probe_click(&p, "date mode"))
	testing.expect_value(t, m.state.mode, Date_Mode.Input)

	// Not passed: the same clicks work from the picker's own store.
	n := Date_State_Model{view = {2026, 9, 1}}
	defer ui.text_destroy(&n.input)
	q: ui.Probe
	ui.probe_init(&q, date_state_ui, &n, {400, 700}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&q)
	testing.expect(t, ui.probe_click(&q, "year menu"))
	testing.expect(t, has_name(&q, "year 2026"))
	testing.expect(t, ui.probe_click(&q, "year menu"))
	testing.expect(t, has_name(&q, "2026-09-01"))
	testing.expect(t, ui.probe_click(&q, "date mode"))
	ui.probe_advance(&q, 30, 1.0 / 60)
	testing.expect(t, has_name(&q, "date input"))
	testing.expect_value(t, n.state, Date_Picker_State{})
}

@(private = "file")
Carousel_State_Model :: struct {
	hit:   int,
	owned: bool,
	state: Carousel_State,
}

@(private = "file")
carousel_state_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Carousel_State_Model)(user)
	items := [?]Carousel_Item{{"A", {}, {}}, {"B", {}, {}}, {"C", {}, {}}, {"D", {}, {}}, {"E", {}, {}}, {"F", {}, {}}, {"G", {}, {}}, {"H", {}, {}}}
	if i := carousel(gtx, items[:], 400, 200, item_spacing = 8, state = m.owned ? &m.state : nil); i >= 0 {
		m.hit = i
	}
}

@(test)
test_carousel_keeps_its_state_where_told :: proc(t: ^testing.T) {
	// Passed: the caller's position places it, and moves it later.
	m := Carousel_State_Model{hit = -1, owned = true}
	m.state.position = 2
	p: ui.Probe
	ui.probe_init(&p, carousel_state_ui, &m, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 60, 1.0 / 60)
	c, ok := ui.probe_center(&p, "carousel")
	testing.expect(t, ok)
	left := ui.Point{c.x - 190, c.y}
	click_at(&p, left)
	testing.expect_value(t, m.hit, 2)
	testing.expect_value(t, m.state.position, 2)
	ui.probe_key(&p, .Right)
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect_value(t, m.state.position, 3)
	m.state.position = 0.8 // set from outside: it snaps from there
	ui.probe_advance(&p, 120, 1.0 / 60)
	testing.expect_value(t, m.state.position, 1)
	click_at(&p, left)
	testing.expect_value(t, m.hit, 1)

	// Not passed: a scroll still moves it, from its own store.
	n := Carousel_State_Model{hit = -1}
	q: ui.Probe
	ui.probe_init(&q, carousel_state_ui, &n, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&q)
	ui.probe_frame(&q)
	click_at(&q, left)
	testing.expect_value(t, n.hit, 0)
	ui.probe_key(&q, .Right)
	ui.probe_advance(&q, 60, 1.0 / 60)
	click_at(&q, left)
	testing.expect_value(t, n.hit, 1)
	testing.expect_value(t, n.state, Carousel_State{})
}
