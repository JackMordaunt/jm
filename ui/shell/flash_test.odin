package shell

import "core:testing"
import "jm:ui/ops"


@(test)
test_flash_leaves_the_debug_panels_alone :: proc(t: ^testing.T) {
	w: Window
	defer delete(w.flashes)
	repaint := ops.Rect{0, 0, 100, 100}
	tray := ops.Rect{60, 60, 60, 60} // overlaps the repaint's corner
	panel := ops.Rect{10, 10, 20, 20} // inside it
	flash_outside(&w, repaint, {tray, panel}, 0)
	area: f32
	for fl in w.flashes {
		r := ops.Rect{fl.r.x, fl.r.y, fl.r.w, fl.r.h}
		for k in ([]ops.Rect{tray, panel}) {
			c := ops.rect_intersect(r, k)
			testing.expect(t, c.w <= 0 || c.h <= 0) // no piece touches a panel
		}
		area += r.w * r.h
	}
	// All of the repaint but the 40x40 under the tray and the panel's 20x20.
	testing.expect_value(t, area, f32(100 * 100 - 40 * 40 - 20 * 20))
}
