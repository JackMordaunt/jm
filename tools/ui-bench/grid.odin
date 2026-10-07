package main

import "core:fmt"
import "core:strings"
import "core:time"
import "jm:ui"
import bl "jm:ui/blend2d"
import "jm:ui/datagrid"
import "jm:ui/ops"
import "jm:ui/render"

// Grid times jm:ui/datagrid over a hundred thousand rows of twelve
// columns, the size of the admin dashboard's rig table, as it is used:
// standing still, scrolled a wheel notch a frame, flung a few thousand
// rows a frame (every row new, every text shaped), scrolled sideways,
// and standing still sorted and filtered. Layout is the ui proc and
// flatten; render a whole frame on Blend2D; compose the frame through
// render.Compositor, which repaints only what changed and moves what
// scrolled.

GRID_ROWS         :: 100_000
GRID_COLUMN_COUNT :: 12

Grid_Bench :: struct {
	cells: [][GRID_COLUMN_COUNT]string,
	rows:  []datagrid.Page_Row,
	table: datagrid.Memory_Table,
	g:     datagrid.Grid,
	skin:  datagrid.Skin,
	step:  [2]f32, // scrolled each frame
}

GRID_COLUMNS := [GRID_COLUMN_COUNT]datagrid.Column {
	{id = "serial", title = "Serial", row_header = true, pin = .Left},
	{id = "model", title = "Model", filter = .Set},
	{id = "owner", title = "Owner", filter = .Set},
	{id = "site", title = "Facility", filter = .Set},
	{id = "status", title = "Status", filter = .Set},
	{id = "payout", title = "Payout", filter = .Set},
	{id = "hash", title = "Hashrate", kind = .Number, align = .End},
	{id = "standing", title = "Standing", filter = .Set},
	{id = "created", title = "Created", kind = .Date},
	{id = "expected", title = "Expected worker", sizing = .Grow},
	{id = "worker", title = "F. Worker"},
	{id = "tags", title = "Tags"},
}

grid_bench_make :: proc() -> ^Grid_Bench {
	b := new(Grid_Bench)
	b.cells = make([][GRID_COLUMN_COUNT]string, GRID_ROWS)
	sites := []string{"Norway", "Paraguay", "Wisconsin", "Ethiopia", "South Dakota"}
	models := []string {
		"Bitmain S21 XP 270TH",
		"Bitmain S19j Pro 104TH",
		"Whatsminer M60S",
		"Avalon A1466",
	}
	status := []string{"Deployed", "Pre-deployment", "Maintenance", "Unassigned"}
	for i in 0 ..< GRID_ROWS {
		owner := fmt.aprintf("Customer %d", (i * 7919) % 4000)
		b.cells[i] = {
			fmt.aprintf("SN-%07d", i),
			models[i % len(models)],
			owner,
			sites[(i * 7) % len(sites)],
			status[(i * 3) % len(status)],
			"Client" if i % 5 != 0 else "Saz",
			fmt.aprintf("%.1f", f64((i * 37) % 3000) / 10),
			"Paid Up" if i % 9 != 0 else "Overdue",
			fmt.aprintf("2026-%02d-%02d", 1 + i % 12, 1 + i % 28),
			fmt.aprintf("cust%d.rig%d~happyNOsilver", (i * 7919) % 4000, i),
			fmt.aprintf("cust%d.rig%d", (i * 7919) % 4000, i),
			"" if i % 3 != 0 else "batch-7, retrofit",
		}
	}
	b.rows = datagrid.rows_of(b.cells, 0)
	datagrid.memory_table_init(&b.table, GRID_COLUMNS[:], b.rows)
	datagrid.grid_init(&b.g, GRID_COLUMNS[:])
	b.skin.style = datagrid.DEFAULT_STYLE
	return b
}

grid_scene :: proc(gtx: ^ui.Ctx, user: rawptr) {
	b := (^Grid_Bench)(user)
	// Sideways, back and forth between the ends.
	room := b.g.place.mid_w - b.g.geo.mid_w
	if b.g.scroll.x + b.step.x > room || b.g.scroll.x + b.step.x < 0 {
		b.step.x = -b.step.x
	}
	// Down, starting over from the top at the end.
	if f64(b.g.scroll.y + b.step.y) > b.g.geo.content - f64(b.g.geo.body.h) {
		b.g.scroll.y = 0
	}
	b.g.scroll += b.step
	datagrid.grid(gtx, &b.g, GRID_COLUMNS[:], &b.table, &b.skin, "Rigs")
}

grid_bench :: proc(w, h, frames: int) {
	b := grid_bench_make()
	BG :: ops.Color{255, 255, 255, 255}
	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	assert(bl.image_create(&img, i32(w), i32(h), .PRGB32) == 0)
	p: ui.Probe
	ui.probe_init(&p, grid_scene, b, {f32(w), f32(h)})
	ops.add_font(&p.scene, FONT)
	p.shaper = render.shaper(&r, p.scene.fonts[:])
	ui.probe_frame(&p)

	fmt.printfln(
		"datagrid, %d rows x %d columns at %dx%d, %d frames each, ms per frame",
		GRID_ROWS,
		GRID_COLUMN_COUNT,
		w,
		h,
		frames,
	)
	fmt.printfln(
		"%-10s %6s %8s %8s %8s %8s   %s",
		"case",
		"draws",
		"layout",
		"render",
		"compose",
		"shaped",
		"what",
	)
	Case :: struct {
		name, what: string,
		step:       [2]f32,
		prepare:    proc(b: ^Grid_Bench),
	}
	cases := []Case {
		{"steady", "nothing changes", {}, nil},
		{"wheel", "48px down a frame", {0, 48}, nil},
		{"fling", "2,000 rows down a frame", {0, 66_000}, nil},
		{"sideways", "40px across a frame, back and forth", {40, 0}, nil},
		{"filtered", "sorted by two keys, two set filters, steady", {}, proc(b: ^Grid_Bench) {
				datagrid.view_sort_cycle(&b.g.view, 3, false)
				datagrid.view_sort_cycle(&b.g.view, 6, true)
				datagrid.view_set_values(&b.g.view, 1, {"Whatsminer M60S", "Avalon A1466"})
				datagrid.view_set_values(&b.g.view, 7, {"Paid Up"})
			}},
	}
	for c in cases {
		b.step = {}
		b.g.scroll = {}
		if c.prepare != nil {
			c.prepare(b)
		}
		ui.probe_frame(&p)
		ui.probe_frame(&p)
		b.step = c.step
		misses := b.g.text.misses
		t0 := time.tick_now()
		for _ in 0 ..< frames {
			ui.probe_frame(&p)
		}
		layout := time.duration_milliseconds(time.tick_since(t0)) / f64(frames)
		shaped := f64(b.g.text.misses - misses) / f64(frames)
		f := ui.probe_current(&p)
		render.render(&r, f, &img, BG)
		t1 := time.tick_now()
		for _ in 0 ..< frames {
			render.render(&r, f, &img, BG)
		}
		whole := time.duration_milliseconds(time.tick_since(t1)) / f64(frames)
		comp := grid_compose(&p, &img, frames, BG)
		fmt.printfln(
			"%-10s %s %s %s %s %s   %s",
			c.name,
			pad(fmt.tprint(len(f.draws)), 6),
			pad(fmt.tprintf("%.3f", layout), 8),
			pad(fmt.tprintf("%.3f", whole), 8),
			pad(fmt.tprintf("%.3f", comp), 8),
			pad(fmt.tprintf("%.1f", shaped), 8),
			c.what,
		)
		free_all(context.temp_allocator)
	}
	ui.probe_destroy(&p)
}

// pad right-justifies s in width columns: core:fmt pads a number's
// width with zeros.
pad :: proc(s: string, width: int) -> string {
	return strings.right_justify(s, width, " ", context.temp_allocator)
}

// grid_compose is the compositor's ms a frame over frames frames of the
// case, scroll included.
grid_compose :: proc(p: ^ui.Probe, img: ^bl.ImageCore, frames: int, bg: ops.Color) -> f64 {
	c: render.Compositor
	render.compositor_init(&c, 1)
	defer render.compositor_destroy(&c)
	ui.probe_frame(p)
	render.compose(&c, ui.probe_current(p), img, bg)
	spent: time.Duration
	painted, moved: f32
	for _ in 0 ..< frames {
		ui.probe_frame(p)
		t0 := time.tick_now()
		render.compose(&c, ui.probe_current(p), img, bg)
		spent += time.tick_since(t0)
		for q in c.damage.rects {
			painted += q.w * q.h
		}
		for q in c.damage.scrolls {
			moved += q.rect.w * q.rect.h
		}
	}
	area := f32(frames) * p.size.x * p.size.y
	fmt.eprintf("[painted %.0f%% moved %.0f%%] ", 100 * painted / area, 100 * moved / area)
	return time.duration_milliseconds(spent) / f64(frames)
}
