// The host half of examples/hot-architecture: owns the window, never
// links the diagram's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	hot-architecture-host build/debug/hot-architecture.watch
//	hot-architecture-host build/debug/hot-architecture-child.exe   (no watch: a fixed child)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "jm:ui/sdl"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: hot-architecture-host <pointer-file | child exe>")
		os.exit(2)
	}
	app := sdl.Host_App {
		title  = "jm:ui's own pipeline (hot)",
		width  = 1360,
		height = 650,
		clear  = {246, 246, 248, 255},
	}
	// A path ending .watch is a pointer file tools/hot-watch republishes;
	// anything else is taken as a fixed child binary to spawn once.
	if strings.has_suffix(os.args[1], ".watch") {
		app.watch = os.args[1]
	} else {
		app.child = {os.args[1]}
	}
	sdl.run_host(app)
}
