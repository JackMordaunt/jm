// jm:ui's own pipeline, drawn with jm:ui: input becomes routed events,
// layout records them into a Scene, which either flattens straight into a
// render call (one process) or gets tunneled through ui/ipc to a second
// process that flattens and renders it there instead — the same seam this
// file's own diagram is being pushed across as you edit it, if you're
// running it under tools/hot-watch and examples/hot-architecture/host.
//
//	hot-architecture-child                          run as the subprocess
//	hot-architecture-child -dump                    the scene sc as text
//	hot-architecture-child -png build/arch.png      render it headlessly
package main

import "core:fmt"
import "jm:ui/ops"
import "core:os"
import "jm:ui"
import "jm:ui/child"
import "jm:ui/diagram"
import "jm:ui/render"

WIDTH :: 1360
HEIGHT :: 650

INPUT_COLOR :: ops.Color{51, 102, 255, 255} // blue
LAYOUT_COLOR :: ops.Color{20, 160, 160, 255} // teal — was amber, edited live for the hot-reload demo
RENDER_COLOR :: ops.Color{32, 150, 80, 255} // green
IPC_COLOR :: ops.Color{155, 89, 182, 255} // purple

INPUT_CHIPS :: []diagram.Chip {
	{"poll()", "SDL events, or a host-forwarded ui/wire Input over ipc"},
	{"translate -> Raw_Event", "platform-neutral: pos, key, button, mods, text"},
	{"Router.router_push", "queues events for the next route"},
	{"router_route(prev frame)", "hit-tests against last frame's hits - one frame late"},
	{"events(gtx, area)", "a widget reads only what was routed to it"},
}

LAYOUT_CHIPS :: []diagram.Chip {
	{"Ctx + widgets", "column/row/box/button/label - widget_open/end"},
	{"records into Ops", "transforms, clips, fills, glyph runs, input areas, tags"},
	{"Layout", "retained state: hover, press, focus, flex measurements"},
	{"flatten(sc, frame)", "Ops -> device-space draws + a hit list"},
	{"Frame", "what next frame's router_route hit-tests against"},
}

RENDER_CHIPS :: []diagram.Chip {
	{"render.compose", "damage tracking: diff against the last paint"},
	{"Blend2D executor", "fill / stroke / glyphs -> pixels, per changed rect"},
	{"render.Compositor", "workers repaint changed regions in parallel"},
	{"GPU texture upload", "only the rects that changed; scroll moves on the GPU"},
	{"present", "shows the texture - the reason any of this ran"},
}

Model :: struct {
	flow: ui.Tween, // the IPC tunnel's dash width, to read as data in motion
}

new_model :: proc() -> Model {
	return {flow = {from = 1.5, to = 4, duration = 1, loop = true}}
}

architecture_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	th := gtx.theme
	sc := gtx.scene
	ops.fill(sc, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, th.bg)

	ui.text(gtx, "jm:ui's own pipeline: input, layout, render (edited live, hot-reloaded)", {40, 18}, {size = 22})
	ui.text(gtx, "the layout/render seam (Ops) either flattens in place or tunnels through ui/ipc to a second process", {40, 46}, {size = 12, color = th.muted})

	stage_h := diagram.group_height(len(INPUT_CHIPS))
	input := ops.Rect{30, 86, 330, stage_h}
	layout := ops.Rect{430, 86, 330, stage_h}
	render_box := ops.Rect{1000, 86, 330, stage_h}

	diagram.group(gtx, input, "INPUT", "device events become routed, per-widget events", INPUT_COLOR, INPUT_CHIPS)
	diagram.group(gtx, layout, "LAYOUT", "widgets describe the frame; flatten makes it device-space", LAYOUT_COLOR, LAYOUT_CHIPS)
	diagram.group(gtx, render_box, "RENDER", "the Frame becomes pixels, only where they changed", RENDER_COLOR, RENDER_CHIPS)

	// Input -> Layout: an ordinary solid arrow, always in-process.
	diagram.arrow(gtx, {input.x + input.w + 5, 170}, {layout.x - 5, 170}, INPUT_COLOR, 2.5)
	ui.text(gtx, "Raw_Event", {input.x + input.w + 10, 145}, {size = 11})

	// The seam: the same Scene, two routes. Solid is the direct call this
	// package's own sdl.run takes; dashed is sdl.run_host's, through the
	// ipc box, tunneling to wherever the render side actually lives.
	seam_y :: 170
	diagram.arrow(gtx, {layout.x + layout.w + 5, seam_y}, {render_box.x - 5, seam_y}, LAYOUT_COLOR, 2.5)
	ui.text(gtx, "Ops", {layout.x + layout.w + 10, seam_y - 25}, {size = 11})
	ui.text(gtx, "(same process)", {layout.x + layout.w + 10, seam_y - 11}, {size = 10, color = th.muted})

	ipc := ops.Rect{830, 300, 100, diagram.group_height(0)}
	diagram.group(gtx, ipc, "ui/ipc", "encode -> pipe -> decode", IPC_COLOR, nil)
	pulse_width := ui.tween_update(&m.flow, gtx)
	diagram.dashed_arrow(gtx, {layout.x + layout.w + 5, ipc.y + ipc.h / 2 - 3}, {ipc.x, ipc.y + ipc.h / 2 - 3}, IPC_COLOR, pulse_width, 8, 6)
	diagram.dashed_arrow(gtx, {ipc.x + ipc.w, ipc.y + ipc.h / 2 + 3}, {render_box.x - 5, ipc.y + ipc.h / 2 + 3}, IPC_COLOR, pulse_width, 8, 6)
	ui.text(gtx, "tunneled: sdl.run_host <-> ui/child", {layout.x + layout.w + 10, ipc.y - 20}, {size = 10, color = th.muted})

	ui.text(gtx, "The same Ops that flatten straight into a render call (ui/sdl.run) can instead cross a process boundary first (ui/sdl.run_host):", {input.x, render_box.y + render_box.h + 20}, {size = 11, color = th.muted})
	ui.text(gtx, "ui/child owns Layout and everything left of the seam; the host owns everything right of it and never links the ui proc at all.", {input.x, render_box.y + render_box.h + 36}, {size = 11, color = th.muted})
}

main :: proc() {
	m := new_model()

	if len(os.args) == 1 {
		child.run({ui = architecture_ui, user = &m, fonts = {{0, ui.default_font()}}})
		return
	}

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-dump":
			p: ui.Probe
			ui.probe_init(&p, architecture_ui, &m, {WIDTH, HEIGHT})
			defer ui.probe_destroy(&p)
			fmt.print(ui.probe_dump(&p))
		case "-png":
			if i + 1 >= len(args) {
				fmt.eprintln("-png needs a path")
				os.exit(2)
			}
			i += 1
			path := args[i]
			if !render.snapshot(architecture_ui, &m, {WIDTH, HEIGHT}, {{0, ui.default_font()}}, path, frames = 15) {
				fmt.eprintfln("could not write %s", path)
				os.exit(1)
			}
		case:
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
	}
}
