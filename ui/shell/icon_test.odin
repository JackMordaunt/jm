package shell

import "core:testing"

@(test)
test_icon_bounds_crops_to_the_ink :: proc(t: ^testing.T) {
	// 4 by 2, pitch 20: a transparent row, then ink in columns 1 and 2.
	px := make([]byte, 40)
	defer delete(px)
	px[20 + 4 + 3] = 255
	px[20 + 8 + 3] = 1
	x, y, w, h, ok := icon_bounds(px, 4, 2, 20)
	testing.expect(t, ok)
	testing.expect_value(t, x, 1)
	testing.expect_value(t, y, 1)
	testing.expect_value(t, w, 2)
	testing.expect_value(t, h, 1)

	_, _, _, _, none := icon_bounds(px[:20], 4, 1, 20)
	testing.expect(t, !none, "a clear image has no ink")
	_, _, _, _, bad := icon_bounds(px, 4, 2, 8)
	testing.expect(t, !bad, "a short pitch is not a row")
}

@(test)
test_a_repeated_theme_is_kept :: proc(t: ^testing.T) {
	w: Window
	apply_window_theme(&w, true, {1, 2, 3})
	testing.expect(t, w.theme_set && w.theme_dark)
	testing.expect_value(t, w.theme_caption, [3]u8{1, 2, 3})
	apply_window_theme(&w, true, {1, 2, 3})
	apply_window_theme(&w, false, {9, 8, 7})
	testing.expect(t, w.theme_set && !w.theme_dark)
	testing.expect_value(t, w.theme_caption, [3]u8{9, 8, 7})
}
