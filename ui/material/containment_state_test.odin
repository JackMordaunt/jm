package material

import "core:testing"
import "jm:ui"

// The containment group's caller-owned state: a list row's
// List_Item_State, honoured when passed and kept by the row when not.

@(private = "file")
Owned_Rows :: struct {
	owned:  List_Item_State,
	action: int,
}

@(private = "file")
owned_rows :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Owned_Rows)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	ACTIONS := [?]Icon{.Archive, .Delete}
	list_item(gtx, {headline = "Owned", kind = .Reveal, actions = ACTIONS[:], action = &m.action}, 300, row_state = &m.owned, key = 1)
	list_item(gtx, {headline = "Kept", kind = .Reveal, actions = ACTIONS[:], action = &m.action}, 300, key = 2)
}

@(test)
test_list_item_row_state_is_honoured_and_nil_keeps_its_own :: proc(t: ^testing.T) {
	m := Owned_Rows{action = -1}
	p: ui.Probe
	ui.probe_init(&p, owned_rows, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// The caller opens its row from outside; the other stays closed.
	m.owned.reveal.target = -list_reveal_width(2)
	ui.probe_advance(&p, 60, 1.0 / 60)
	// Kept, with two actions like Owned, would take this click were it
	// reading the caller's state.
	testing.expect(t, !ui.probe_click(&p, "Kept action 1"))
	testing.expect(t, ui.probe_click(&p, "Owned action 1"))
	testing.expect_value(t, m.action, 1)
	// Picking an action closed the row, in the caller's state.
	testing.expect_value(t, m.owned.reveal.target, f32(0))

	// With no state passed, a drag still opens the row, and leaves the
	// caller's state alone.
	c, ok := ui.probe_center(&p, "Kept")
	testing.expect(t, ok)
	ui.router_push(&p.router, {kind = .Move, pos = c})
	ui.router_push(&p.router, {kind = .Press, pos = c, button = .Left})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Move, pos = c + {-120, 0}})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Release, pos = c + {-120, 0}, button = .Left})
	ui.probe_frame(&p)
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "Kept action 0"))
	testing.expect_value(t, m.action, 0)
	testing.expect_value(t, m.owned.reveal.target, f32(0))
	testing.expect_value(t, m.owned.drag, f32(0))
}
