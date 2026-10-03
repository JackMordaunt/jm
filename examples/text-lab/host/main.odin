// The host half of examples/text-lab: owns the window, never links
// the lab's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	text-lab-host build/debug/text-lab.watch
//	text-lab-host build/debug/text-lab-child   (no watch: a fixed child)
package main

import "jm:ui/sdl"

main :: proc() {
	sdl.run_host_from_args(
		{
			title  = "jm:ui text lab",
			width  = 1400,
			height = 900,
			clear  = {250, 250, 250, 255},
		},
	)
}
