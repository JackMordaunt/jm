// The host half of examples/material-kitchen: owns the window, never links the
// kitchen's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	material-kitchen-host build/debug/material-kitchen.watch
//	material-kitchen-host build/debug/material-kitchen-child   (no watch: a fixed child)
package main

import "jm:ui/sdl"

main :: proc() {
	sdl.run_host_from_args(
		{
			title  = "jm:ui material kitchen",
			width  = 1400,
			height = 900,
			clear  = {254, 247, 255, 255},
		},
	)
}
