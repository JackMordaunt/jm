// The host half of examples/hot-counter: owns the window, spawns the
// child binary named on the command line, and never links the counter's
// own code at all — everything about what it draws lives in the child.
//
//	hot-counter-host build/debug/hot-counter-child.exe
//	hot-counter-host build/debug/hot-counter.watch   (a child tools/hot-watch republishes)
package main

import "jm:ui/sdl"

main :: proc() {
	sdl.run_host_from_args(
		{
			title  = "hot-counter (host)",
			width  = 360,
			height = 200,
			clear  = {246, 246, 248, 255},
		},
	)
}
