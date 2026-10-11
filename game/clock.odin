package game

// Clock turns the frames' uneven dt into whole ticks of a fixed dt: the
// step a game's logic runs at, whatever the display's rate, so a run is
// the same at 30 Hz as at 144 Hz and a replay repeats it exactly.
//
//	ticks := clock_advance(&clock, gtx.dt)
//	for _ in 0 ..< ticks { step(world, input) }
//
// A frame that comes late runs several ticks to catch up, at most
// max_ticks; past that the backlog is dropped and the game slows down,
// rather than spending each frame catching up on the last.
Clock :: struct {
	dt:        f64, // seconds a tick stands for
	max_ticks: int, // the most ticks one frame runs
	backlog:   f64, // seconds of frame time not yet stepped, under one dt
	tick:      u64, // ticks run so far
}

// DEFAULT_DT is the tick a Game gets when it names none: 60 Hz.
DEFAULT_DT :: 1.0 / 60

// DEFAULT_MAX_TICKS is how many ticks a late frame may run when a Game
// names no limit.
DEFAULT_MAX_TICKS :: 5

// TICK_SLACK is how far short of a whole dt the backlog may be and still
// run a tick: a frame dt that is the tick's dt rounded to f32 must run one
// tick every frame, not zero then two as the rounding error builds up
// (clock_test.odin, a_frame_at_the_tick_rate_runs_one_tick_every_time).
@(private)
TICK_SLACK :: 1e-6

// clock_init makes a clock of dt seconds a tick, catching up at most
// max_ticks a frame; 0 takes the defaults.
clock_init :: proc(clock: ^Clock, dt: f64 = 0, max_ticks := 0) {
	clock^ = {
		dt        = dt if dt > 0 else DEFAULT_DT,
		max_ticks = max_ticks if max_ticks > 0 else DEFAULT_MAX_TICKS,
	}
}

// clock_advance adds a frame's dt and returns how many ticks to run for it.
clock_advance :: proc(clock: ^Clock, frame_dt: f32) -> (ticks: int) {
	clock.backlog += f64(max(frame_dt, 0))
	for clock.backlog >= clock.dt - TICK_SLACK && ticks < clock.max_ticks {
		clock.backlog = max(clock.backlog - clock.dt, 0)
		ticks += 1
	}
	if clock.backlog >= clock.dt {
		clock.backlog = 0
	}
	clock.tick += u64(ticks)
	return
}

// clock_alpha is how far between the last tick and the next the frame
// falls, 0 to 1: what a draw interpolates by to move smoothly when frames
// outpace ticks.
clock_alpha :: proc(clock: ^Clock) -> f32 {
	return f32(min(clock.backlog / clock.dt, 1))
}
