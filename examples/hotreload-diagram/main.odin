// A diagram of the subprocess hot-reload architecture, drawn with jm:ui's
// own ui/diagram kit: which components live in the host process (owns the
// OS window, never rebuilt) versus the UI subprocess (rebuilt and
// respawned on every source change), and what crosses the pipe between
// them. The top arrow's width pulses on a ui.Tween, meant to stand in for
// the per-frame Raw_Event traffic the design has that arrow carrying —
// the subprocess split itself is not built yet, so nothing here sends any.
//
//	hotreload-diagram                          open a window
//	hotreload-diagram -dump                    the scene sc as text
//	hotreload-diagram -png build/hotreload.png render it headlessly
package main

import "core:fmt"
import "jm:ui/ops"
import "core:os"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/diagram"
import "jm:ui/render"
import "jm:ui/sdl"

WIDTH :: 1180
HEIGHT :: 820

HOST_COLOR :: ops.Color{51, 102, 255, 255} // blue: the host, owns the window
SUB_COLOR :: ops.Color{155, 89, 182, 255} // purple: the subprocess, gets rebuilt

HOST_CHIPS :: []diagram.Chip {
	{"SDL window & event loop", "owns the OS window; never rebuilt"},
	{"poll -> Raw_Event", "device events, platform-neutral"},
	{"flatten (Ops -> Frame)", "cheap, no rasterization; for compose only"},
	{"render.Compositor", "damage tracking: diff against last frame"},
	{"Blend2D executor", "rasterizes changed rects to the CPU image"},
	{"GPU textures & present", "upload changed rects; scroll copy on GPU"},
	{"wait / pacing", "uses wants_frame + frame_after from the subprocess"},
}

SUB_CHIPS :: []diagram.Chip {
	{"Model", "application state - what hot-reload discards"},
	{"ui proc (your widgets)", "the rebuilt binary; this is what gets swapped"},
	{"Router", "hit-tests input into per-widget events"},
	{"Layout", "hover, focus, scroll - reset on respawn"},
	{"flatten (Ops -> Frame)", "only to hit-test its own next frame"},
	{"Shaper (Blend2D font_shape)", "text shaping only, never rasterizes"},
	{"encode(sc) -> stdout", "wire format: draw list + resource paths"},
}

Model :: struct {
	pulse: ui.Tween, // the top arrow's width, standing in for live traffic
}

new_model :: proc() -> Model {
	return {pulse = {from = 2, to = 4.5, duration = 1.2, loop = true}}
}

diagram_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	th := base.theme()
	sc := gtx.scene
	ops.fill(sc, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, base.color(.Bg))

	base.text(gtx, "jm:ui hot-reload architecture: the subprocess split", {40, 18}, {size = 22})
	base.text(gtx, "solid arrows = per-frame wire traffic     dashed arrow = rebuild/respawn, out of band", {40, 46}, {size = 12, color = base.color(.Muted)})

	host := ops.Rect{40, 86, 500, diagram.group_height(len(HOST_CHIPS))}
	subp := ops.Rect{640, 86, 500, diagram.group_height(len(SUB_CHIPS))}
	watch := ops.Rect{640, subp.y + subp.h + 34, 500, 70}

	diagram.group(gtx, host, "HOST PROCESS", "owns the OS window - stays up across every rebuild", HOST_COLOR, HOST_CHIPS)
	diagram.group(gtx, subp, "UI SUBPROCESS", "killed and relaunched whenever the source changes", SUB_COLOR, SUB_CHIPS)

	diagram.fill_rrect(sc, watch, 8, base.color(.Surface), base.color(.Outline), th.stroke)
	base.text(gtx, "file watcher / build supervisor", {watch.x + 20, watch.y + 12}, {size = 14})
	base.text(gtx, "runs `odin build`; respawns the subprocess on success", {watch.x + 20, watch.y + 34}, {size = 11, color = base.color(.Muted)})

	// Per-frame wire traffic, in the gap between the two boxes. The top
	// arrow's width pulses to stand in for events actually flowing.
	width := ui.tween_update(&m.pulse, gtx)
	diagram.arrow(gtx, {host.x + host.w + 5, 170}, {subp.x - 5, 170}, HOST_COLOR, width)
	base.text(gtx, "Raw_Event", {host.x + host.w + 8, 132}, {size = 11})
	base.text(gtx, "(device px, stdin)", {host.x + host.w + 8, 148}, {size = 10, color = base.color(.Muted)})

	diagram.arrow(gtx, {subp.x - 5, 560}, {host.x + host.w + 5, 560}, SUB_COLOR, 2.5)
	base.text(gtx, "Ops bytes", {host.x + host.w + 8, 570}, {size = 11})
	base.text(gtx, "(stdout) + wants_frame", {host.x + host.w + 8, 586}, {size = 10, color = base.color(.Muted)})

	// Out-of-band supervision, as designed (the subprocess split itself is
	// not built yet): the watcher is meant to kill and relaunch the
	// subprocess without the host needing to know it happened mid-frame.
	diagram.dashed_arrow(gtx, {watch.x + 70, watch.y}, {watch.x + 70, subp.y + subp.h}, base.color(.Muted), 2, 8, 6)
	base.text(gtx, "kill + respawn", {watch.x + 90, watch.y - 34}, {size = 11})
	base.text(gtx, "(the model resets; no state crosses a rebuild)", {watch.x + 90, watch.y - 18}, {size = 10, color = base.color(.Muted)})

	base.text(gtx, "A crash or a failed build never reaches the host: it keeps the", {host.x, host.y + host.h + 18}, {size = 11, color = base.color(.Muted)})
	base.text(gtx, "last good frame on screen until the next respawn lands.", {host.x, host.y + host.h + 34}, {size = 11, color = base.color(.Muted)})
}

main :: proc() {
	m := new_model()

	if len(os.args) == 1 {
		th := base.light(0)
		base.use(&th)
		sdl.run(
			{
				title = "jm:ui hot-reload architecture",
				width = WIDTH,
				height = HEIGHT,
				ui = diagram_ui,
				user = &m,
				fonts = {{id = 0, path = sdl.default_font()}},
				clear = base.color(.Bg),
			},
		)
		return
	}

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-dump":
			p: ui.Probe
			ui.probe_init(&p, diagram_ui, &m, {WIDTH, HEIGHT})
			defer ui.probe_destroy(&p)
			fmt.print(ui.probe_dump(&p))
		case "-png":
			if i + 1 >= len(args) {
				fmt.eprintln("-png needs a path")
				os.exit(2)
			}
			i += 1
			path := args[i]
			// frames = 15: catch the pulse partway through its loop, not at
			// its resting start value.
			if !render.snapshot(diagram_ui, &m, {WIDTH, HEIGHT}, {{id = 0, path = sdl.default_font()}}, path, frames = 15) {
				fmt.eprintfln("could not write %s", path)
				os.exit(1)
			}
		case:
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
	}
}
