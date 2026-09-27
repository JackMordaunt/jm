// The subprocess half of the hot-reload split's own proof: a counter with
// +/- buttons, so a click has to survive the host -> child -> host round
// trip (hit-tested in this process, drawn in the host's window) to move
// the count at all. Rebuild this binary alone and the host (examples/
// hot-counter/host) respawns it, per ui/sdl's run_host.
package main

import "core:fmt"
import "jm:ui"
import "jm:ui/child"

Model :: struct {
	count: int,
}

counter_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	th := gtx.theme
	ui.fill(gtx.ops, ui.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, th.bg)

	pad := ui.inset(gtx, ui.pad_all(24))
	defer ui.end(&pad)
	row := ui.row(gtx, gap = 12, align = .Center)
	defer ui.end(&row)
	if ui.button(gtx, "-") {
		m.count -= 1
	}
	ui.label(gtx, fmt.tprintf("count %d", m.count), {size = th.heading_size})
	if ui.button(gtx, "+") {
		m.count += 1
	}
}

main :: proc() {
	m: Model
	child.run({ui = counter_ui, user = &m, fonts = {{0, ui.default_font()}}})
}
