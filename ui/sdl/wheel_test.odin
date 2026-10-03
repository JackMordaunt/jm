package sdl

import "core:testing"
import "jm:ui"
import "jm:ui/testutil"

MS :: 1_000_000

@(test)
test_a_notch_scrolls_one_step :: proc(t: ^testing.T) {
	w: Wheel
	testing.expect_value(t, wheel_pixels(&w, {0, 1}, 0, false), [2]f32{0, ui.SCROLL_STEP})
	testing.expect_value(t, wheel_pixels(&w, {0, -2}, 0, true), [2]f32{0, -2 * ui.SCROLL_STEP})
}

@(test)
test_off_macos_a_touchpad_fraction_is_a_fraction_of_a_notch :: proc(t: ^testing.T) {
	w: Wheel
	testing.expect_value(t, wheel_pixels(&w, {0, 0.25}, 0, false), [2]f32{0, 0.25 * ui.SCROLL_STEP})
}

@(test)
test_a_precise_stream_moves_as_far_as_the_fingers :: proc(t: ^testing.T) {
	w: Wheel
	// SDL gives a trackpad's points times 0.1: 3.5 points arrive as 0.35.
	testing.expect(t, testutil.near(wheel_pixels(&w, {0, 0.35}, 10 * MS, true).y, 3.5))
	// A whole number inside the stream is 10 points, not a notch.
	testing.expect(t, testutil.near(wheel_pixels(&w, {0, 1}, 20 * MS, true).y, PRECISE_POINTS))
}

@(test)
test_a_pause_ends_the_precise_stream :: proc(t: ^testing.T) {
	w: Wheel
	wheel_pixels(&w, {0, 0.35}, 10 * MS, true)
	after := u64(10 * MS + WHEEL_STREAM_GAP_NS + 1)
	testing.expect_value(t, wheel_pixels(&w, {0, 1}, after, true), [2]f32{0, ui.SCROLL_STEP})
}
