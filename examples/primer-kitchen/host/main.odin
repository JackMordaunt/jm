// The host half of examples/primer-kitchen: owns the window, never links
// the kitchen's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	primer-kitchen-host build/debug/primer-kitchen.watch
//	primer-kitchen-host build/debug/primer-kitchen-child   (no watch: a fixed child)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "jm:ui/sdl"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: primer-kitchen-host <pointer-file | child exe>")
		os.exit(2)
	}
	app := sdl.Host_App {
		title  = "jm:ui primer kitchen",
		width  = 1400,
		height = 900,
		clear  = {255, 255, 255, 255}, // the light theme's --bgColor-default
	}
	if strings.has_suffix(os.args[1], ".watch") {
		app.watch = os.args[1]
	} else {
		app.child = {os.args[1]}
	}
	sdl.run_host(app)
}
