// The host half of examples/fluent-kitchen: owns the window, never links
// the kitchen's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	fluent-kitchen-host build/debug/fluent-kitchen.watch
//	fluent-kitchen-host build/debug/fluent-kitchen-child   (no watch: a fixed child)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "jm:ui/sdl"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: fluent-kitchen-host <pointer-file | child exe>")
		os.exit(2)
	}
	app := sdl.Host_App {
		title  = "jm:ui fluent kitchen",
		width  = 1400,
		height = 900,
		clear  = {250, 250, 250, 255}, // the web light theme's Neutral_Background2
	}
	if strings.has_suffix(os.args[1], ".watch") {
		app.watch = os.args[1]
	} else {
		app.child = {os.args[1]}
	}
	sdl.run_host(app)
}
