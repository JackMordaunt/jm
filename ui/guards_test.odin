package ui

import "core:testing"

// Two nested guards each get back the handle they held, innermost first,
// and the next frame starts with nothing held.
@(test)
test_guard_handles_nest :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	outer := guard_hold(&h.gtx, int)
	outer^ = 1
	inner := guard_hold(&h.gtx, f32)
	inner^ = 2
	testing.expect_value(t, guard_take(&h.gtx, f32)^, f32(2))
	testing.expect_value(t, guard_take(&h.gtx, int)^, 1)
	harness_frame(&h)
	testing.expect_value(t, len(h.layout.held), 0)
}
