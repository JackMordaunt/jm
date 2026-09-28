// The host half of examples/material-kitchen: owns the window, never links the
// kitchen's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	material-kitchen-host build/debug/material-kitchen.watch
//	material-kitchen-host build/debug/material-kitchen-child   (no watch: a fixed child)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "jm:ui/sdl"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: material-kitchen-host <pointer-file | child exe>")
		os.exit(2)
	}
	app := sdl.Host_App {
		title  = "jm:ui material kitchen",
		width  = 1400,
		height = 900,
		clear  = {254, 247, 255, 255},
	}
	if strings.has_suffix(os.args[1], ".watch") {
		app.watch = os.args[1]
	} else {
		app.child = {os.args[1]}
	}
	sdl.run_host(app)
}
