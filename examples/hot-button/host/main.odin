// The host half of examples/hot-button: owns the window, never links the
// button pilot's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	hot-button-host build/debug/hot-button.watch
//	hot-button-host build/debug/hot-button-child.exe   (no watch: a fixed child)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "jm:ui/sdl"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: hot-button-host <pointer-file | child exe>")
		os.exit(2)
	}
	app := sdl.Host_App {
		title  = "jm:ui button pilot (hot)",
		width  = 720,
		height = 700,
		clear  = {246, 246, 248, 255},
	}
	if strings.has_suffix(os.args[1], ".watch") {
		app.watch = os.args[1]
	} else {
		app.child = {os.args[1]}
	}
	sdl.run_host(app)
}
