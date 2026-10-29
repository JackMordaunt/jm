#+build darwin
package shell

import "core:testing"
import NS "core:sys/darwin/Foundation"
import sdl3 "vendor:sdl3"
import "jm:ui/ops"

// SDL's hit-test points are logical, while both local and subprocess
// frames publish drag rectangles in device pixels. Controls and the
// native buttons must remain outside those regions at either density.
@(test)
test_mac_title_drag_scales_points_and_clears_old_regions :: proc(t: ^testing.T) {
	w: Window
	for density in ([]f32{1, 1.5, 2}) {
		w.density = density
		title_set_drags(&w, []ops.Rect{{100 * density, 0, 400 * density, 52 * density}})
		for point in ([]sdl3.Point{{100, 0}, {250, 26}, {499, 51}}) {
			p := point
			testing.expect_value(t, title_mac_drag(&w, &p), sdl3.HitTestResult.DRAGGABLE)
		}
		for point in ([]sdl3.Point{{30, 26}, {99, 26}, {530, 26}, {250, 53}}) {
			p := point
			testing.expect_value(t, title_mac_drag(&w, &p), sdl3.HitTestResult.NORMAL)
		}
		title_set_drags(&w, nil)
		p := sdl3.Point{250, 26}
		testing.expect_value(t, title_mac_drag(&w, &p), sdl3.HitTestResult.NORMAL)
	}
}

// Read the setting by its native values without changing user preferences.
@(test)
test_mac_title_double_click_preferences :: proc(t: ^testing.T) {
	testing.expect_value(t, title_mac_action(nil), Title_Mac_Action.Zoom)
	testing.expect_value(t, title_mac_action(NS.MakeConstantString("Maximize")), Title_Mac_Action.Zoom)
	testing.expect_value(t, title_mac_action(NS.MakeConstantString("Fill")), Title_Mac_Action.Zoom)
	testing.expect_value(t, title_mac_action(NS.MakeConstantString("Minimize")), Title_Mac_Action.Minimize)
	testing.expect_value(t, title_mac_action(NS.MakeConstantString("None")), Title_Mac_Action.None)
}
