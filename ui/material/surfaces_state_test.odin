package material

import "core:testing"
import "jm:ui"

// The surfaces group's caller-owned state: a bottom sheet's Sheet_State is
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
