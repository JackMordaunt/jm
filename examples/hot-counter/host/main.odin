// The host half of examples/hot-counter: owns the window, spawns the
// child binary named on the command line, and never links the counter's
// own code at all — everything about what it draws lives in the child.
//
//	hot-counter-host build/debug/hot-counter-child.exe
package main

import "core:fmt"
import "core:os"
import "jm:ui/sdl"

main :: proc() {
	if len(os.args) != 2 {
		fmt.eprintln("usage: hot-counter-host <path to hot-counter-child>")
		os.exit(2)
	}
	sdl.run_host(
		{
			title  = "hot-counter (host)",
			width  = 360,
			height = 200,
			child  = {os.args[1]},
			clear  = {246, 246, 248, 255},
		},
	)
}
