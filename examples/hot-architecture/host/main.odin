// The host half of examples/hot-architecture: owns the window, never
// links the diagram's own code, and — given a pointer file kept fresh by
// tools/hot-watch — respawns the child every time a rebuild lands.
//
//	hot-architecture-host build/debug/hot-architecture.watch
//	hot-architecture-host build/debug/hot-architecture-child.exe   (no watch: a fixed child)
package main

import "jm:ui/sdl"

main :: proc() {
	sdl.run_host_from_args(
		{
			title  = "jm:ui's own pipeline (hot)",
			width  = 1360,
			height = 650,
			clear  = {246, 246, 248, 255},
		},
	)
}
