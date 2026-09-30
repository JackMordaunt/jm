// The host half of examples/text-lab: owns the window, never links
// the lab's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	text-lab-host build/debug/text-lab.watch
//	text-lab-host build/debug/text-lab-child   (no watch: a fixed child)
package main

import "core:fmt"
import "core:os"
import "core:strings"
import "jm:ui/sdl"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: text-lab-host <pointer-file | child exe>")
		os.exit(2)
	}
	app := sdl.Host_App {
		title  = "jm:ui text lab",
		width  = 1400,
		height = 900,
		clear  = {250, 250, 250, 255},
	}
	if strings.has_suffix(os.args[1], ".watch") {
		app.watch = os.args[1]
	} else {
		app.child = {os.args[1]}
	}
	sdl.run_host(app)
}
