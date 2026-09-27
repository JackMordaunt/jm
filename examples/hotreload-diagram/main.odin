// A static diagram of the subprocess hot-reload architecture, drawn with
// jm:ui itself: which components live in the host process (owns the OS
// window, never rebuilt) versus the UI subprocess (rebuilt and respawned on
// every source change), and what crosses the pipe between them.
//
//	hotreload-diagram                          open a window
//	hotreload-diagram -dump                    the scene ops as text
//	hotreload-diagram -png build/hotreload.png render it headlessly
package main

import "core:fmt"
import "core:os"
import "jm:ui"
import "jm:ui/render"
import "jm:ui/sdl"

WIDTH :: 1180
HEIGHT :: 820

HOST_COLOR :: ui.Color{51, 102, 255, 255} // blue: the host, owns the window
SUB_COLOR :: ui.Color{155, 89, 182, 255} // purple: the subprocess, gets rebuilt

Chip :: struct {
	title, subtitle: string,
}

HOST_CHIPS :: []Chip {
	{"SDL window & event loop", "owns the OS window; never rebuilt"},
	{"poll -> Raw_Event", "device events, platform-neutral"},
	{"flatten (Ops -> Frame)", "cheap, no rasterization; for compose only"},
	{"render.Compositor", "damage tracking: diff against last frame"},
	{"Blend2D executor", "rasterizes changed rects to the CPU image"},
	{"GPU textures & present", "upload changed rects; scroll copy on GPU"},
	{"wait / pacing", "uses wants_frame + frame_after from the subprocess"},
}

SUB_CHIPS :: []Chip {
	{"Model", "application state - what hot-reload discards"},
	{"ui proc (your widgets)", "the rebuilt binary; this is what gets swapped"},
	{"Router", "hit-tests input into per-widget events"},
	{"Layout", "hover, focus, scroll - reset on respawn"},
	{"flatten (Ops -> Frame)", "only to hit-test its own next frame"},
	{"Shaper (Blend2D font_shape)", "text shaping only, never rasterizes"},
	{"encode(ops) -> stdout", "wire format: draw list + resource paths"},
}

diagram :: proc(gtx: ^ui.Ctx, user: rawptr) {
	th := gtx.theme
	ops := gtx.ops
	ui.fill(ops, ui.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, th.bg)

	ui.text(gtx, "jm:ui hot-reload architecture: the subprocess split", {40, 18}, {size = 22})
	ui.text(gtx, "solid arrows = per-frame wire traffic     dashed arrow = rebuild/respawn, out of band", {40, 46}, {size = 12, color = th.muted})

	host := ui.Rect{40, 86, 500, 610}
	subp := ui.Rect{640, 86, 500, 610}
	watch := ui.Rect{640, 720, 500, 70}

	process_box(gtx, host, "HOST PROCESS", "owns the OS window - stays up across every rebuild", HOST_COLOR, HOST_CHIPS)
	process_box(gtx, subp, "UI SUBPROCESS", "killed and relaunched whenever the source changes", SUB_COLOR, SUB_CHIPS)

	fill_rrect(ops, watch, 8, th.surface, th.outline, th.stroke)
	ui.text(gtx, "file watcher / build supervisor", {watch.x + 20, watch.y + 12}, {size = 14})
	ui.text(gtx, "runs `odin build`; respawns the subprocess on success", {watch.x + 20, watch.y + 34}, {size = 11, color = th.muted})

	// Per-frame wire traffic, in the gap between the two boxes.
	arrow(gtx, {host.x + host.w + 5, 170}, {subp.x - 5, 170}, HOST_COLOR, 2.5)
	ui.text(gtx, "Raw_Event", {host.x + host.w + 8, 132}, {size = 11})
	ui.text(gtx, "(device px, stdin)", {host.x + host.w + 8, 148}, {size = 10, color = th.muted})

	arrow(gtx, {subp.x - 5, 560}, {host.x + host.w + 5, 560}, SUB_COLOR, 2.5)
	ui.text(gtx, "Ops bytes", {host.x + host.w + 8, 570}, {size = 11})
	ui.text(gtx, "(stdout) + wants_frame", {host.x + host.w + 8, 586}, {size = 10, color = th.muted})

	// Out-of-band supervision, as designed (the subprocess split itself is
	// not built yet): the watcher is meant to kill and relaunch the
	// subprocess without the host needing to know it happened mid-frame.
	dashed_arrow(gtx, {watch.x + 70, watch.y}, {watch.x + 70, subp.y + subp.h}, th.muted, 2, 8, 6)
	ui.text(gtx, "kill + respawn", {watch.x + 90, watch.y - 34}, {size = 11})
	ui.text(gtx, "(the model resets; no state crosses a rebuild)", {watch.x + 90, watch.y - 18}, {size = 10, color = th.muted})

	ui.text(gtx, "A crash or a failed build never reaches the host: it keeps the", {host.x, host.y + host.h + 18}, {size = 11, color = th.muted})
	ui.text(gtx, "last good frame on screen until the next respawn lands.", {host.x, host.y + host.h + 34}, {size = 11, color = th.muted})
}

process_box :: proc(gtx: ^ui.Ctx, r: ui.Rect, title, subtitle: string, accent: ui.Color, chips: []Chip) {
	th := gtx.theme
	ops := gtx.ops
	fill_rrect(ops, r, 10, th.surface, accent, 2)
	ui.fill(ops, ui.Rect{r.x, r.y, r.w, 4}, accent)
	ui.text(gtx, title, {r.x + 20, r.y + 16}, {size = 16, color = accent})
	ui.text(gtx, subtitle, {r.x + 20, r.y + 40}, {size = 11, color = th.muted})

	y := r.y + 74
	chip_h: f32 = 62
	gap: f32 = 10
	for c, i in chips {
		cr := ui.Rect{r.x + 20, y, r.w - 40, chip_h}
		fill := i % 2 == 0 ? th.surface_hover : th.surface
		fill_rrect(ops, cr, 8, fill, th.outline, 1)
		ui.fill(ops, ui.Rect{cr.x, cr.y, 4, cr.h}, accent)
		ui.text(gtx, c.title, {cr.x + 14, cr.y + 9}, {size = 13})
		ui.text(gtx, c.subtitle, {cr.x + 14, cr.y + 30}, {size = 10.5, color = th.muted})
		y += chip_h + gap
	}
}

// fill_rrect fills and outlines a round rect in one call; stroke is skipped
// when width <= 0.
fill_rrect :: proc(ops: ^ui.Ops, r: ui.Rect, radius: f32, fill, outline: ui.Color, stroke_w: f32) {
	rr := ui.Round_Rect{r, radius}
	ui.fill(ops, rr, fill)
	if stroke_w > 0 {
		ui.stroke(ops, rr, outline, {width = stroke_w})
	}
}

// arrow draws a straight line from p0 to p1 with a filled triangular
// arrowhead at p1, on ui.line and ui.polygon (both safe to call with a
// literal: they copy through gtx.allocator internally).
arrow :: proc(gtx: ^ui.Ctx, p0, p1: ui.Point, color: ui.Color, width: f32) {
	dir, ok := unit(p1 - p0)
	if !ok {
		return
	}
	shaft_end := ui.Point{p1.x - dir.x * 10, p1.y - dir.y * 10}
	ui.stroke(gtx.ops, ui.line(gtx, p0, shaft_end), color, {width = width, cap = .Round})
	arrow_head(gtx, p1, dir, color)
}

// dashed_arrow is arrow with a dashed shaft, for the out-of-band respawn
// signal: it never fires on the per-frame path, so it reads differently.
dashed_arrow :: proc(gtx: ^ui.Ctx, p0, p1: ui.Point, color: ui.Color, width, dash, gap: f32) {
	d := p1 - p0
	total := length(d)
	dir, ok := unit(d)
	if !ok {
		return
	}
	head_room := f32(12)
	at: f32 = 0
	for at < total - head_room {
		a := ui.Point{p0.x + dir.x * at, p0.y + dir.y * at}
		e := min(at + dash, total - head_room)
		b := ui.Point{p0.x + dir.x * e, p0.y + dir.y * e}
		ui.stroke(gtx.ops, ui.line(gtx, a, b), color, {width = width, cap = .Round})
		at = e + gap
	}
	arrow_head(gtx, p1, dir, color)
}

// arrow_head fills a small triangle whose tip is at tip, pointing along dir.
arrow_head :: proc(gtx: ^ui.Ctx, tip, dir: ui.Point, color: ui.Color, size: f32 = 10) {
	perp := ui.Point{-dir.y, dir.x}
	base := ui.Point{tip.x - dir.x * size, tip.y - dir.y * size}
	left := ui.Point{base.x + perp.x * size * 0.5, base.y + perp.y * size * 0.5}
	right := ui.Point{base.x - perp.x * size * 0.5, base.y - perp.y * size * 0.5}
	ui.fill(gtx.ops, ui.polygon(gtx, []ui.Point{tip, left, right}), color)
}

length :: proc(v: ui.Point) -> f32 {
	s := v.x * v.x + v.y * v.y
	if s == 0 {
		return 0
	}
	x := s
	for _ in 0 ..< 12 {
		x = 0.5 * (x + s / x)
	}
	return x
}

unit :: proc(v: ui.Point) -> (ui.Point, bool) {
	l := length(v)
	if l == 0 {
		return {}, false
	}
	return {v.x / l, v.y / l}, true
}

main :: proc() {
	if len(os.args) == 1 {
		theme := ui.light_theme(0)
		sdl.run(
			{
				title = "jm:ui hot-reload architecture",
				width = WIDTH,
				height = HEIGHT,
				ui = diagram,
				theme = &theme,
				fonts = {{0, sdl.default_font()}},
				clear = theme.bg,
			},
		)
		return
	}

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-dump":
			p: ui.Probe
			ui.probe_init(&p, diagram, nil, {WIDTH, HEIGHT})
			defer ui.probe_destroy(&p)
			fmt.print(ui.probe_dump(&p))
		case "-png":
			if i + 1 >= len(args) {
				fmt.eprintln("-png needs a path")
				os.exit(2)
			}
			i += 1
			path := args[i]
			if !render.snapshot(diagram, nil, {WIDTH, HEIGHT}, {{0, sdl.default_font()}}, path) {
				fmt.eprintfln("could not write %s", path)
				os.exit(1)
			}
		case:
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
	}
}
