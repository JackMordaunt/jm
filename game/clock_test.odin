package game

import "core:testing"

@(test)
a_frame_at_the_tick_rate_runs_one_tick_every_time :: proc(t: ^testing.T) {
	clock: Clock
	clock_init(&clock)
	for _ in 0 ..< 600 {
		testing.expect_value(t, clock_advance(&clock, f32(1.0 / 60)), 1)
	}
	testing.expect_value(t, clock.tick, u64(600))
}

@(test)
fast_frames_share_ticks_and_say_how_far_between :: proc(t: ^testing.T) {
	clock: Clock
	clock_init(&clock, 0.1)
	testing.expect_value(t, clock_advance(&clock, 0.025), 0)
	testing.expect_value(t, clock_alpha(&clock), f32(0.25))
	testing.expect_value(t, clock_advance(&clock, 0.025), 0)
	testing.expect_value(t, clock_advance(&clock, 0.025), 0)
	testing.expect_value(t, clock_advance(&clock, 0.025), 1)
	testing.expect(t, clock_alpha(&clock) < 0.001)
}

@(test)
a_late_frame_catches_up_then_drops_the_rest :: proc(t: ^testing.T) {
	clock: Clock
	clock_init(&clock, 0.1, max_ticks = 3)
	testing.expect_value(t, clock_advance(&clock, 0.25), 2)
	testing.expect_value(t, clock_advance(&clock, 10), 3) // a stall: three ticks, not a hundred
	testing.expect_value(t, clock.backlog, 0)
	testing.expect_value(t, clock.tick, u64(5))
}
