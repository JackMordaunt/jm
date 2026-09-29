package ops

import "core:testing"

@(test)
test_mix_fades_from_transparent_without_darkening :: proc(t: ^testing.T) {
	clear_black := Color{0, 0, 0, 0} // a subtle button's rest background
	grey := Color{245, 245, 245, 255} // its hover background
	mid := mix(clear_black, grey, 0.5)
	// Halfway is the grey at half alpha, not a dark grey.
	testing.expect_value(t, mid, Color{245, 245, 245, 128})
	testing.expect_value(t, mix(grey, clear_black, 0.25), Color{245, 245, 245, 191})
	// Exact at the ends, and opaque colours mix channel by channel as before.
	testing.expect_value(t, mix(clear_black, grey, 0), clear_black)
	testing.expect_value(t, mix(clear_black, grey, 1), grey)
	testing.expect_value(t, mix(Color{0, 0, 0, 255}, Color{200, 100, 50, 255}, 0.5), Color{100, 50, 25, 255})
	testing.expect_value(t, mix(clear_black, clear_black, 0.5), clear_black)
}
