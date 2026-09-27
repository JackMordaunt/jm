// The jm:ui kitchen sink: every widget, a rotated clipped badge, and the
// probe. With no flags it opens a window. Flags run the same ui headlessly:
//
//	ui-kitchen -dump                     the scene ops as text
//	ui-kitchen -frame                    the flattened draws, clips, hits, tags
//	ui-kitchen -names                    what is on screen, by tag
//	ui-kitchen -png build/kitchen.png    the frame rendered by Blend2D
//	ui-kitchen -click Save -dump         click by name, then dump
//	ui-kitchen -click name -type Ada -png out.png
//
// Flags apply in order, so a script is a command line.
package main

import "core:fmt"
import "core:os"
import "jm:ui"
import "jm:ui/render"
import "jm:ui/sdl"

when ODIN_OS == .Windows {
	FONT :: "C:/Windows/Fonts/arial.ttf"
} else {
	FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}
WIDTH :: 900
HEIGHT :: 600
ROWS :: 200

Model :: struct {
	theme:     ui.Theme,
	dark:      bool,
	name:      ui.Text_State,
	subscribe: bool,
	volume:    f32,
	count:     int,
	saved:     string,
	list:      ui.List_State,
	picked:    int,
	angle:     f32,
	still:     bool, // the badge has stopped turning
}

kitchen :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	th := gtx.theme
	ui.fill(gtx.ops, ui.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, th.bg)

	page := ui.inset(gtx, ui.pad_all(16))
	defer ui.end(&page)
	col := ui.column(gtx, gap = 12)
	defer ui.end(&col)

	{
		hdr := ui.row(gtx, gap = 12, align = .Center)
		defer ui.end(&hdr)
		ui.label(gtx, "jm:ui kitchen", {size = th.heading_size})
		ui.fill_space(gtx)
		ui.label(gtx, fmt.tprintf("frame %d", gtx.frame), {color = th.muted})
		if ui.button(gtx, "Dark" if !m.dark else "Light") {
			m.dark = !m.dark
			m.theme = ui.dark_theme(th.font) if m.dark else ui.light_theme(th.font)
			th^ = m.theme // the window and the probe each hold the theme the ctx points at
		}
	}
	ui.divider(gtx)
	{
		body := ui.row(gtx, gap = 16)
		defer ui.end(&body)
		form(gtx, m)
		ui.flexible(gtx, 1)
		rows(gtx, m)
		{
			side := ui.column(gtx, gap = 12)
			defer ui.end(&side)
			badge(gtx, "affine + clip", m.angle)
			if ui.button(gtx, "Spin" if m.still else "Stop") {
				m.still = !m.still
			}
			ui.label(gtx, fmt.tprintf("picked row %d", m.picked), {color = th.muted})
		}
	}
	// A turning badge wants every frame; a still one lets the window idle.
	if !m.still {
		m.angle += gtx.dt * 0.4
		ui.request_frame(gtx)
	}
}

// form is the left panel: every input widget and a save round-trip.
form :: proc(gtx: ^ui.Ctx, m: ^Model) {
	th := gtx.theme
	card := ui.box(gtx)
	defer ui.end(&card)
	col := ui.column(gtx, gap = 8)
	defer ui.end(&col)

	ui.label(gtx, "Name")
	ui.text_field(gtx, &m.name, name = "name")
	ui.checkbox(gtx, "Subscribe", &m.subscribe)
	{
		r := ui.row(gtx, gap = 8, align = .Center)
		defer ui.end(&r)
		ui.label(gtx, "Volume")
		ui.slider(gtx, &m.volume, 0, 100, name = "volume")
		ui.label(gtx, fmt.tprintf("%.0f", m.volume), {color = th.muted})
	}
	{
		r := ui.row(gtx, gap = 8, align = .Center)
		defer ui.end(&r)
		if ui.button(gtx, "-") {
			m.count -= 1
		}
		ui.label(gtx, fmt.tprintf("count %d", m.count))
		if ui.button(gtx, "+") {
			m.count += 1
		}
	}
	{
		r := ui.row(gtx, gap = 8)
		defer ui.end(&r)
		if ui.button(gtx, "Save") {
			m.saved = fmt.aprintf("Saved %s", ui.text_string(&m.name))
		}
		if ui.button(gtx, "Reset", {fill = th.danger}) {
			ui.text_set(&m.name, "")
			m.subscribe = false
			m.volume = 40
			m.count = 0
			m.saved = ""
		}
	}
	if m.saved != "" {
		ui.label(gtx, m.saved, {color = th.success})
	}
}

// rows is the middle panel: a virtualised list with a button per row.
rows :: proc(gtx: ^ui.Ctx, m: ^Model) {
	card := ui.box(gtx)
	defer ui.end(&card)
	ui.list(gtx, &m.list, ROWS, row_item, m)
}

row_item :: proc(gtx: ^ui.Ctx, i: int, user: rawptr) {
	m := (^Model)(user)
	r := ui.row(gtx, gap = 8, align = .Center)
	defer ui.end(&r)
	ui.label(gtx, fmt.tprintf("Row %d", i))
	ui.fill_space(gtx)
	if ui.button(gtx, "Pick") {
		m.picked = i
	}
}

// badge is a widget written straight against the ops: a gradient under a
// round-rect clip, stripes that the clip cuts, an outline, text, the whole
// thing rotated about its centre. It is what a custom widget costs.
badge :: proc(gtx: ^ui.Ctx, text: string, angle: f32, loc := #caller_location) -> ui.Dims {
	p := ui.widget_begin(gtx, 0, loc)
	th := gtx.theme
	ops := gtx.ops
	w, h: f32 = 200, 64
	rr := ui.Round_Rect{{0, 0, w, h}, 18}

	about_center := ui.mul(ui.mul(ui.translate(-w / 2, -h / 2), ui.rotate(angle)), ui.translate(w / 2, h / 2))
	ui.push_transform(ops, about_center)
	ui.push_clip(ops, rr)
	stops := make([]ui.Gradient_Stop, 2, gtx.allocator)
	stops[0] = {0, th.accent}
	stops[1] = {1, th.danger}
	ui.fill(ops, ui.Rect{0, 0, w, h}, ui.Linear_Gradient{{0, 0}, {w, h}, stops})
	for x: f32 = 8; x < w; x += 28 {
		ui.fill(ops, ui.Ellipse{{x, -12, 14, h + 24}}, ui.Color{255, 255, 255, 48})
	}
	ui.pop_clip(ops)
	ui.stroke(ops, rr, th.fg, {width = 2})
	run := ui.shape(gtx.shaper, th.font, th.text_size, text, gtx.allocator)
	mt := ui.metrics(gtx.shaper, th.font, th.text_size)
	origin := ui.Point{(w - run.advance) / 2, (h - ui.line_height(mt)) / 2 + mt.ascent}
	ui.glyphs(ops, ui.add_run(ops, run), origin, th.on_accent)
	ui.pop_transform(ops)
	ui.tag(ops, p.id, "badge")
	return ui.widget_end(gtx, &p, {{w, h}, 0})
}

main :: proc() {
	m: Model
	m.theme = ui.light_theme(0)
	m.volume = 40
	ui.text_set(&m.name, "Ada")
	defer ui.text_destroy(&m.name)

	if len(os.args) == 1 {
		sdl.run(
			{
				title = "jm:ui kitchen",
				width = WIDTH,
				height = HEIGHT,
				ui = kitchen,
				user = &m,
				theme = &m.theme,
				fonts = {{0, FONT}},
				clear = m.theme.bg,
				threads = 4,
			},
		)
		return
	}

	p: ui.Probe
	ui.probe_init(&p, kitchen, &m, {WIDTH, HEIGHT}, theme = m.theme)
	defer ui.probe_destroy(&p)
	ui.add_font(&p.ops, FONT)
	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	p.shaper = render.shaper(&r, p.ops.fonts[:])
	ui.probe_frame(&p)

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		value :: proc(args: []string, i: ^int, flag: string) -> string {
			if i^ + 1 >= len(args) {
				fmt.eprintfln("%s needs a value", flag)
				os.exit(2)
			}
			i^ += 1
			return args[i^]
		}
		switch args[i] {
		case "-dump":
			fmt.print(ui.probe_dump(&p))
		case "-frame":
			fmt.print(ui.probe_dump_frame(&p))
		case "-names":
			for n in ui.probe_names(&p) {
				fmt.println(n)
			}
		case "-png":
			path := value(args, &i, "-png")
			if !render.render_png(&r, ui.probe_current(&p), WIDTH, HEIGHT, path, m.theme.bg) {
				fmt.eprintfln("could not write %s", path)
				os.exit(1)
			}
		case "-click":
			name := value(args, &i, "-click")
			if !ui.probe_click(&p, name) {
				fmt.eprintfln("nothing named %q on screen", name)
				os.exit(1)
			}
		case "-type":
			ui.probe_type(&p, value(args, &i, "-type"))
		case:
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
	}
}
