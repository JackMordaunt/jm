package ui

import "core:testing"

@(test)
test_pixel_is_one_device_pixel_at_any_density :: proc(t: ^testing.T) {
	gtx: Ctx
	testing.expect_value(t, pixel(&gtx), f32(1)) // a host that sets none draws at 1
	gtx.density = 2
	testing.expect_value(t, pixel(&gtx), f32(0.5))
	gtx.density = 1.5
	testing.expect(t, abs(pixel(&gtx) * 1.5 - 1) < 1e-6, "a pixel at 1.5x is two thirds of a unit")
}
