// The host half of examples/primer-kitchen: owns the window, never links
// the kitchen's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	primer-kitchen-host build/debug/primer-kitchen.watch
//	primer-kitchen-host build/debug/primer-kitchen-child   (no watch: a fixed child)
package main

import "jm:ui/sdl"

main :: proc() {
	sdl.run_host_from_args(
		{
			title  = "jm:ui primer kitchen",
			width  = 1400,
			height = 900,
			clear  = {255, 255, 255, 255}, // the light theme's --bgColor-default
		},
	)
}
