package ui

import "core:testing"
import "jm:ui/ops"

@(test)
test_scope_gives_a_loop_its_own_ids_and_nests :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	ids: [3]ops.Area_Id
	for i in 0 ..< 3 {
		s := scope_open(gtx, i)
		defer close(&s)
		p := widget_open(gtx) // one call site, three iterations
		ids[i] = p.id
		widget_close(gtx, &p, {})
	}
	testing.expect(t, ids[0] != ids[1] && ids[1] != ids[2] && ids[0] != ids[2])
	testing.expect_value(t, h.layout.scope, ops.Area_Id(0)) // every scope ended

	// Nested: a page, then a row; the same row index under another page
	// is another id.
	row_under :: proc(gtx: ^Ctx, page: string) -> ops.Area_Id {
		ps := scope_open(gtx, page)
		defer close(&ps)
		rs := scope_open(gtx, 7)
		defer close(&rs)
		return claim_id(gtx)
	}
	inbox := row_under(gtx, "inbox")
	testing.expect(t, inbox != row_under(gtx, "sent"))
	harness_frame(&h)
	testing.expect_value(t, row_under(gtx, "inbox"), inbox) // the same row next frame
}

@(test)
test_widget_data_keeps_one_value_per_type_while_asked_for :: proc(t: ^testing.T) {
	Timer :: struct {
		t: f32,
	}
	Anchor :: struct {
		at: ops.Point,
	}
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	tm := widget_data(&h.gtx, 5, Timer)
	testing.expect_value(t, tm.t, 0) // zero at first
	tm.t = 1.5
	an := widget_data(&h.gtx, 5, Anchor) // the same widget, another type: its own slot
	an.at = {3, 4}
	harness_frame(&h)
	testing.expect_value(t, widget_data(&h.gtx, 5, Timer), tm)
	testing.expect_value(t, tm.t, 1.5)
	testing.expect_value(t, len(h.layout.data), 2)
	harness_frame(&h) // asked for last frame: kept
	harness_frame(&h) // not asked for since: dropped
	testing.expect_value(t, len(h.layout.data), 0)
}

@(test)
test_retain_keeps_a_page_state_while_it_is_not_drawn :: proc(t: ^testing.T) {
	Page :: struct {
		n: int,
	}
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	page: Page
	draw :: proc(gtx: ^Ctx, page: ^Page) {
		s := scope_open(gtx, page)
		defer close(&s)
		widget_state(gtx, claim_id(gtx)).springs[0].value = 9
	}
	draw(&h.gtx, &page)
	for _ in 0 ..< 5 {
		harness_frame(&h)
		retain(&h.gtx, &page) // switched away from, but kept
	}
	testing.expect_value(t, len(h.layout.state), 1)
	for _, st in h.layout.state {
		testing.expect_value(t, st.springs[0].value, 9) // kept as it was, not reset
	}
	for _ in 0 ..< 3 {
		harness_frame(&h) // no longer retained
	}
	testing.expect_value(t, len(h.layout.state), 0)
}
