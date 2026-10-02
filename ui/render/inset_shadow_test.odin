package render

import "core:testing"
import "jm:ui"
import bl "jm:ui/blend2d"
import "jm:ui/ops"
import "jm:ui/design"

@(private = "file")
SIDE :: 48

// design_rendered paints draw into a clear SIDE-square scene and returns the
// rasterised target's alpha per pixel, through the real renderer.
@(private = "file")
design_rendered :: proc(draw: proc(gtx: ^ui.Ctx)) -> (alpha: [SIDE][SIDE]u8) {
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	gtx := ui.Ctx {
		scene     = &sc,
		allocator = context.temp_allocator,
	}
	draw(&gtx)
	f: ui.Frame
	ui.frame_init(&f)
	defer ui.frame_destroy(&f)
	ui.flatten(&sc, &f, {0, 0, SIDE, SIDE})
	r: Renderer
	init(&r)
	defer destroy(&r)
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	bl.image_create(&img, SIDE, SIDE, .PRGB32)
	render(&r, &f, &img, {0, 0, 0, 0})
	for y in 0 ..< SIDE {
		for x in 0 ..< SIDE {
			alpha[y][x] = pixel(&img, x, y)[3]
		}
	}
	return
}

@(test)
test_an_inset_offset_shadow_shades_only_the_edge_it_falls_from :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Primer's --shadow-inset: inset 0 1px 0 0, on a 32x16 box at 8,8.
	a := design_rendered(proc(gtx: ^ui.Ctx) {
		design.paint_inset_shadow(gtx, {{8, 8, 32, 16}, 0}, {0, 1, 0, 0, {0, 0, 0, 255}})
	})
	for x in 8 ..< 40 {
		testing.expectf(t, a[8][x] == 255, "top row x %d: %d, want shaded", x, a[8][x])
		testing.expectf(t, a[9][x] == 0, "second row x %d: %d, want clear", x, a[9][x])
		testing.expectf(t, a[23][x] == 0, "bottom row x %d: %d, want clear", x, a[23][x])
		testing.expectf(t, a[24][x] == 0, "below x %d: %d, want clear (clipped)", x, a[24][x])
	}
	testing.expect_value(t, a[16][8], u8(0)) // the sides cast nothing
	testing.expect_value(t, a[7][20], u8(0)) // nor does anything outside
}

@(test)
test_an_inset_spread_shadow_is_a_ring_inside_the_edge :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// The on-emphasis focus ring (focusOutlineOnEmphasis.css, inset 0 0 0
	// 3px), here on a rounded box.
	a := design_rendered(proc(gtx: ^ui.Ctx) {
		design.paint_inset_shadow(gtx, {{8, 8, 32, 32}, 6}, {0, 0, 0, 3, {0, 0, 0, 255}})
	})
	for d in 0 ..< 3 {
		testing.expectf(t, a[24][8 + d] == 255, "left edge +%d: %d, want shaded", d, a[24][8 + d])
		testing.expectf(t, a[24][39 - d] == 255, "right edge -%d: %d, want shaded", d, a[24][39 - d])
		testing.expectf(t, a[8 + d][24] == 255, "top edge +%d: %d, want shaded", d, a[8 + d][24])
	}
	testing.expect_value(t, a[24][11], u8(0)) // just inside the ring
	testing.expect_value(t, a[24][24], u8(0)) // the middle
	testing.expect_value(t, a[24][7], u8(0)) // outside
	testing.expect_value(t, a[8][8], u8(0)) // the rounded corner's outside
}
