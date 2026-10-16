package shell

import "core:os"
import "core:testing"
import "vendor:sdl3"

// MS is a millisecond in ns ticks, as the tests spell times.
@(private = "file")
MS :: u64(NS_PER_MS)

// One period of a 60 Hz cap, in ns: 16.67 ms.
@(private = "file")
PERIOD :: u64(1e9 / 60)

@(test)
test_pace_holds_animation_frames_to_the_cap_on_a_fast_display :: proc(t: ^testing.T) {
	p := Pacer{hz = 60}
	// The frame began at 0 and its work took 5 ms: the next is due a
	// period after it began, a 12 ms wait (16.67 - 5, rounded up).
	testing.expect_value(t, pace(&p, 0, 5 * MS, true, 120), i32(12))
	testing.expect_value(t, p.due, PERIOD)
	// The loop woke 1 ms late and worked 5 ms again. The next due is a
	// period after the last due, not after the late start: an 11 ms wait,
	// so the cadence holds at the period rather than drifting with each
	// late wake.
	start := PERIOD + MS
	testing.expect_value(t, pace(&p, start, start + 5 * MS, true, 120), i32(11))
	testing.expect_value(t, p.due, 2 * PERIOD)
}

@(test)
test_pace_never_holds_a_frame_that_took_input :: proc(t: ^testing.T) {
	p := Pacer{hz = 60}
	testing.expect_value(t, pace(&p, 0, 5 * MS, true, 120), i32(12))
	testing.expect_value(t, pace(&p, PERIOD, PERIOD + 5 * MS, false, 120), i32(0))
	testing.expect_value(t, p.due, 0) // and the timeline restarts with the next quiet frame
	start := 3 * PERIOD
	testing.expect_value(t, pace(&p, start, start + 5 * MS, true, 120), i32(12))
	testing.expect_value(t, p.due, start + PERIOD)
}

@(test)
test_pace_is_a_no_op_on_a_display_no_faster_than_the_cap :: proc(t: ^testing.T) {
	p := Pacer{hz = 60}
	testing.expect_value(t, pace(&p, 0, 5 * MS, true, 60), i32(0))
	testing.expect_value(t, pace(&p, 0, 5 * MS, true, 59.94), i32(0))
	testing.expect_value(t, pace(&p, 0, 5 * MS, true, 0), i32(0)) // rate unknown
	off := Pacer{hz = 0}
	testing.expect_value(t, pace(&off, 0, 5 * MS, true, 120), i32(0))
}

@(test)
test_pace_restarts_the_timeline_after_a_slow_or_late_frame :: proc(t: ^testing.T) {
	p := Pacer{hz = 60}
	testing.expect_value(t, pace(&p, 0, 5 * MS, true, 120), i32(12))
	// The frame took 20 ms, past its successor's due: no wait, and the
	// timeline starts over from now rather than running frames back to
	// back to catch up.
	testing.expect_value(t, pace(&p, PERIOD, PERIOD + 20 * MS, true, 120), i32(0))
	testing.expect_value(t, p.due, PERIOD + 20 * MS)
	// The window idled a second, then an animation began: the due time
	// is a period after that frame, not after the lapsed timeline.
	start := p.due + 1000 * MS
	testing.expect_value(t, pace(&p, start, start + 2 * MS, true, 120), i32(15))
	testing.expect_value(t, p.due, start + PERIOD)
	// A frame that ran 6 ms before its due time (a wake the wait let
	// through) starts the timeline over from itself: the next is a period
	// after it, not the slot after the one it took early, which would
	// leave a 25 ms gap behind a 6 ms one.
	early := p.due - 6 * MS
	testing.expect_value(t, pace(&p, early, early + 5 * MS, true, 120), i32(12))
	testing.expect_value(t, p.due, early + PERIOD)
}

@(test)
test_animation_hz_prefers_the_environment_over_the_app :: proc(t: ^testing.T) {
	_ = os.unset_env(ANIMATION_HZ_ENV) // false when it was not set
	testing.expect_value(t, animation_hz(nil), f32(ANIMATION_HZ))
	testing.expect_value(t, animation_hz(0), f32(0))
	testing.expect_value(t, animation_hz(90), f32(90))
	testing.expect_value(t, os.set_env(ANIMATION_HZ_ENV, "0"), nil)
	defer _ = os.unset_env(ANIMATION_HZ_ENV)
	testing.expect_value(t, animation_hz(90), f32(0)) // the run lifts the app's cap
	testing.expect_value(t, os.set_env(ANIMATION_HZ_ENV, "60"), nil)
	testing.expect_value(t, animation_hz(0), f32(60)) // or sets one the app left off
	testing.expect_value(t, os.set_env(ANIMATION_HZ_ENV, "fast"), nil)
	testing.expect_value(t, animation_hz(90), f32(90)) // a typo leaves the app's
}

@(test)
test_drain_wakes_takes_wakes_alone :: proc(t: ^testing.T) {
	if !sdl3.Init({.EVENTS}) {
		testing.fail_now(t, "SDL's events subsystem would not start")
	}
	defer sdl3.Quit()
	wake_register()
	woke := sdl3.EventType(wake_event)
	count :: proc(kind: sdl3.EventType) -> int {
		return sdl3.PeepEvents(nil, 0, .PEEKEVENT, kind, kind)
	}
	testing.expect(t, !drain_wakes(), "an empty queue leaves nothing to drain")
	wake()
	wake()
	testing.expect(t, drain_wakes(), "wakes alone are drained")
	testing.expect_value(t, count(woke), 0)
	wake()
	key := sdl3.Event{type = .KEY_DOWN}
	_ = sdl3.PushEvent(&key)
	testing.expect(t, !drain_wakes(), "a key among the wakes ends the wait")
	testing.expect_value(t, count(woke), 1) // and every event is left for poll
	testing.expect_value(t, count(.KEY_DOWN), 1)
	sdl3.FlushEvents(.FIRST, .LAST)
}
