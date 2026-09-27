// The subprocess half of the hot-reload split's own proof: a counter with
// +/- buttons, so a click has to survive the host -> child -> host round
// trip (hit-tested in this process, drawn in the host's window) to move
// the count at all. Rebuild this binary alone and the host (examples/
// hot-counter/host) respawns it, per ui/sdl's run_host.
//
//	hot-counter-child                          run as the subprocess
//	hot-counter-child -dump                    the scene ops as text
//	hot-counter-child -png build/counter.png    render it headlessly
package main

import "core:fmt"
import "core:os"
import "jm:ui"
import "jm:ui/child"
import "jm:ui/render"

WIDTH :: 200
HEIGHT :: 120

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

	if len(os.args) == 1 {
		child.run({ui = counter_ui, user = &m, fonts = {{0, ui.default_font()}}})
		return
	}

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-dump":
			p: ui.Probe
			ui.probe_init(&p, counter_ui, &m, {WIDTH, HEIGHT})
			defer ui.probe_destroy(&p)
			fmt.print(ui.probe_dump(&p))
		case "-png":
			if i + 1 >= len(args) {
				fmt.eprintln("-png needs a path")
				os.exit(2)
			}
			i += 1
			path := args[i]
			if !render.snapshot(counter_ui, &m, {WIDTH, HEIGHT}, {{0, ui.default_font()}}, path) {
				fmt.eprintfln("could not write %s", path)
				os.exit(1)
			}
		case:
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
	}
}
