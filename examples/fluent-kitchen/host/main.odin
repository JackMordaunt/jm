// The host half of examples/fluent-kitchen: owns the window, never links
// the kitchen's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	fluent-kitchen-host build/debug/fluent-kitchen.watch
//	fluent-kitchen-host build/debug/fluent-kitchen-child   (no watch: a fixed child)
package main

import "jm:ui/sdl"

main :: proc() {
	sdl.run_host_from_args(
		{
			title  = "jm:ui fluent kitchen",
			width  = 1400,
			height = 900,
			clear  = {250, 250, 250, 255}, // the web light theme's Neutral_Background2
		},
	)
}
