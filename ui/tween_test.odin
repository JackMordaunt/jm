package ui

import "core:testing"

@(test)
test_tween_advances_and_clamps :: proc(t: ^testing.T) {
	tw := Tween{from = 0, to = 10, duration = 2}
	gtx: Ctx
	gtx.dt = 0.5
	testing.expect_value(t, tween_update(&tw, &gtx), f32(2.5))
	testing.expect(t, gtx.wants_frame)
	gtx = {dt = 10}
	testing.expect_value(t, tween_update(&tw, &gtx), f32(10))
	testing.expect(t, !gtx.wants_frame)
}

@(test)
test_tween_loops :: proc(t: ^testing.T) {
	tw := Tween{from = 0, to = 4, duration = 1, loop = true}
	gtx: Ctx
	gtx.dt = 0.75
	testing.expect_value(t, tween_update(&tw, &gtx), f32(3))
	testing.expect(t, gtx.wants_frame)
	gtx = {dt = 0.5}
	testing.expect_value(t, tween_update(&tw, &gtx), f32(1))
}

@(test)
test_tween_zero_duration_jumps :: proc(t: ^testing.T) {
	tw := Tween{from = 0, to = 7}
	gtx: Ctx
	testing.expect_value(t, tween_update(&tw, &gtx), f32(7))
	testing.expect(t, !gtx.wants_frame)
}
