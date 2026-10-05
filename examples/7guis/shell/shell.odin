/*
Package shell is what the seven 7GUIs tasks share: a Fluent window, and a
page that paints the theme's background and pads the task inside it. A
task is a model and a ui proc; this is everything around them.
*/
package sevenguis_shell

import "core:fmt"
import "core:os"

import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"
import "jm:ui/render"
import "jm:ui/sdl"

import "../../common"

PAD :: 16

@(private = "file")
scheme: fluent.Scheme

// page_open sets the Fluent light theme for the frame, fills the window
// with its background and opens the inset the task lays itself out in;
// close it with ui.close.
page_open :: proc(gtx: ^ui.Ctx) -> ui.Inset {
	scheme = fluent.theme_scheme(.Web_Light)
	fluent.use(&scheme, fluent.mode_of(.Web_Light))
	fluent.use_fonts({0, 1, 2})
	ops.fill(
		gtx.scene,
		ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y},
		scheme[.Neutral_Background1],
	)
	return ui.inset_open(gtx, ui.pad_all(PAD))
}

// run opens a window of width by height titled title and runs view over
// user in it until the window closes. Given `-png path` it instead renders
// the first frame to path, with no window and no GPU.
run :: proc(title: string, width, height: int, view: ui.UI_Proc, user: rawptr) {
	if len(os.args) == 3 && os.args[1] == "-png" {
		size := ops.Size{f32(width), f32(height)}
		if !render.snapshot(view, user, size, common.fonts(), os.args[2]) {
			fmt.eprintfln("%s: could not write %s", title, os.args[2])
			os.exit(1)
		}
		return
	}
	sdl.run({title = title, width = width, height = height, ui = view, user = user, fonts = common.fonts()})
}
