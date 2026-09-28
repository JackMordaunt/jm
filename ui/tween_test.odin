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

@(test)
test_spring_snaps_first_then_settles_on_target :: proc(t: ^testing.T) {
	s: Spring
	gtx: Ctx
	p := Spring_Params{damping = 0.6, stiffness = 800}
	testing.expect_value(t, spring_update(&s, &gtx, 5, p), f32(5))
	testing.expect(t, !gtx.wants_frame)
	gtx.dt = 1.0 / 60
	v := spring_update(&s, &gtx, 10, p)
	testing.expect(t, v > 5 && v < 10)
	testing.expect(t, gtx.wants_frame)
	overshot := false
	for _ in 0 ..< 120 {
		gtx.wants_frame = false
		v = spring_update(&s, &gtx, 10, p)
		overshot ||= v > 10
	}
	testing.expect(t, overshot) // damping < 1 overshoots
	testing.expect_value(t, v, f32(10))
	testing.expect(t, !gtx.wants_frame)
}

@(test)
test_spring_critical_never_overshoots :: proc(t: ^testing.T) {
	s: Spring
	gtx: Ctx
	p := Spring_Params{damping = 1, stiffness = 1600}
	spring_update(&s, &gtx, 0, p)
	gtx.dt = 1.0 / 120
	first := spring_update(&s, &gtx, 1, p)
	testing.expect(t, first > 0 && first < 1) // it moves, not jumps
	for _ in 0 ..< 240 {
		testing.expect(t, spring_update(&s, &gtx, 1, p) <= 1)
	}
	testing.expect_value(t, s.value, f32(1))
}
