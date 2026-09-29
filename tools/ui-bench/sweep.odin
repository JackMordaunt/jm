package main

import "core:fmt"
import "core:math"
import "core:strings"
import "core:time"
import "jm:ui"
import m3 "jm:ui/material"
import bl "jm:ui/blend2d"
import "jm:ui/render"

// Sweep grows one kind of content until a frame blows the budget, to show
// how complex a scene can get before it stops fitting in a frame.
Family :: struct {
	name: string,
	what: string,
	ui:   proc(gtx: ^ui.Ctx, user: rawptr),
}

Sweep_State :: struct {
	n:      int,
	toggle: bool,
}

SWEEP_MAX :: 1 << 17

// grid_cell places item i of n in a grid that covers the window with cells
// of roughly the window's aspect, and constrains gtx to that cell.
grid_cell :: proc(gtx: ^ui.Ctx, i, n: int, size: ui.Size) -> ui.Size {
	cols := max(1, int(math.ceil(math.sqrt(f32(n) * size.x / size.y))))
	rows := max(1, (n + cols - 1) / cols)
	cw, ch := size.x / f32(cols), size.y / f32(rows)
	ui.transform_push(gtx.ops, ui.translate(f32(i % cols) * cw, f32(i / cols) * ch))
	return {cw, ch}
}

sweep_rect :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		ui.fill(gtx.ops, ui.Rect{0, 0, c.x - 1, c.y - 1}, ui.Color{u8(i), u8(i * 3), u8(i * 7), 255})
		ui.transform_pop(gtx.ops)
	}
}

sweep_rrect :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		ui.fill(gtx.ops, ui.Round_Rect{{0, 0, c.x - 1, c.y - 1}, 4}, ui.Color{u8(i), u8(i * 3), u8(i * 7), 255})
		ui.transform_pop(gtx.ops)
	}
}

sweep_stroke :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		ui.stroke(gtx.ops, ui.Round_Rect{{0.5, 0.5, c.x - 2, c.y - 2}, 4}, ui.Color{60, 60, 70, 255}, {width = 1})
		ui.transform_pop(gtx.ops)
	}
}

sweep_label :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	outer := gtx.constraints
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		gtx.constraints = ui.loose(c)
		ui.label(gtx, fmt.tprintf("label %d", i))
		ui.transform_pop(gtx.ops)
	}
	gtx.constraints = outer
}

sweep_button :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	outer := gtx.constraints
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		gtx.constraints = ui.loose(c)
		m3.button(gtx, "Pick", key = u64(i))
		ui.transform_pop(gtx.ops)
	}
	gtx.constraints = outer
}

// sweep_panel is one kitchen-style card per item: a box holding a label, a
// checkbox and a button.
sweep_panel :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	outer := gtx.constraints
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		gtx.constraints = ui.loose(c)
		card := ui.box_open(gtx, key = u64(i))
		r := ui.row_open(gtx, gap = 8, align = .Center, key = u64(i))
		ui.label(gtx, fmt.tprintf("Item %d", i))
		m3.checkbox(gtx, &s.toggle, key = u64(i))
		m3.button(gtx, "Pick", key = u64(i))
		ui.close(&r)
		ui.close(&card)
		ui.transform_pop(gtx.ops)
	}
	gtx.constraints = outer
}

// sweep_clip_shared puts every round-rect fill under one round-rect clip:
// one mask, but each draw still takes the layer path.
sweep_clip_shared :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	ui.clip_push(gtx.ops, ui.Round_Rect{{0, 0, size.x, size.y}, 24})
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		ui.fill(gtx.ops, ui.Round_Rect{{0, 0, c.x - 1, c.y - 1}, 4}, ui.Color{u8(i), u8(i * 3), u8(i * 7), 255})
		ui.transform_pop(gtx.ops)
	}
	ui.clip_pop(gtx.ops)
}

// sweep_clip_each gives every fill its own rotated clip: a mask per draw.
sweep_clip_each :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^Sweep_State)(user)
	size := gtx.constraints.max
	for i in 0 ..< s.n {
		c := grid_cell(gtx, i, s.n, size)
		ui.transform_push(gtx.ops, ui.rotate(0.1))
		ui.clip_push(gtx.ops, ui.Rect{0, 0, c.x - 1, c.y - 1})
		ui.fill(gtx.ops, ui.Rect{-4, -4, c.x + 8, c.y + 8}, ui.Color{u8(i), 120, 200, 255})
		ui.clip_pop(gtx.ops)
		ui.transform_pop(gtx.ops)
		ui.transform_pop(gtx.ops)
	}
}

// Sweep_Point is one measurement: n items, in ms per frame.
Sweep_Point :: struct {
	n:      int,
	draws:  int,
	layout: f64,
	render: [dynamic]f64, // one per thread count
}

// sweep runs every family at w x h, doubling n from 16 until the fastest
// thread count exceeds twice budget or n reaches SWEEP_MAX.
sweep :: proc(w, h: int, threads: []u32, budget: f64) {
	families := []Family {
		{"rect", "rect fills", sweep_rect},
		{"rrect", "round-rect fills", sweep_rrect},
		{"stroke", "1px round-rect strokes", sweep_stroke},
		{"label", "shaped labels", sweep_label},
		{"button", "buttons (fill + text + hit)", sweep_button},
		{"panel", "cards: box, label, checkbox, button", sweep_panel},
		{"clip-shared", "round-rect fills under one round-rect clip", sweep_clip_shared},
		{"clip-each", "fills each under its own rotated clip", sweep_clip_each},
	}

	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	assert(bl.image_create(&img, i32(w), i32(h), .PRGB32) == 0)

	cell :: proc(v: string, width: int) -> string {
		return strings.right_justify(v, width, " ", context.temp_allocator)
	}
	fmt.printfln("%dx%d, budget %.1f ms per frame (layout + render); ms per frame, render columns are Blend2D thread counts", w, h, budget)

	Summary :: struct {
		name: string,
		what: string,
		best: [dynamic]int, // largest n within budget, per thread count
	}
	summaries := make([dynamic]Summary)

	for fam in families {
		fmt.printfln("\n%s: %s", fam.name, fam.what)
		fmt.printf("%8s %7s %8s", "n", "draws", "layout")
		for t in threads {
			fmt.printf(" %s", cell(fmt.tprintf("t=%d", t), 8))
		}
		fmt.println()

		sm := Summary{fam.name, fam.what, make([dynamic]int)}
		resize(&sm.best, len(threads))

		for n := 16; n <= SWEEP_MAX; n *= 2 {
			st := Sweep_State{n = n}
			p: ui.Probe
			ui.probe_init(&p, fam.ui, &st, {f32(w), f32(h)})
			ui.add_font(&p.ops, FONT)
			p.shaper = render.shaper(&r, p.ops.fonts[:])
			ui.probe_frame(&p)
			ui.probe_frame(&p)

			// Enough frames for a quarter second of work, at least three.
			t0 := time.tick_now()
			ui.probe_frame(&p)
			one := time.duration_milliseconds(time.tick_since(t0))
			frames := clamp(int(250 / max(one, 0.01)), 3, 50)
			t0 = time.tick_now()
			for _ in 0 ..< frames {
				ui.probe_frame(&p)
			}
			layout := time.duration_milliseconds(time.tick_since(t0)) / f64(frames)

			f := ui.probe_current(&p)
			fmt.printf("%s %s %s", cell(fmt.tprint(n), 8), cell(fmt.tprint(len(f.draws)), 7), cell(fmt.tprintf("%.2f", layout), 8))
			fastest := max(f64)
			reference: u64
			for t, ti in threads {
				r.threads = t
				t1 := time.tick_now()
				render.render(&r, f, &img, {250, 250, 250, 255}) // warm the pool and the JIT
				warm := time.duration_milliseconds(time.tick_since(t1))
				frames = clamp(int(250 / max(warm, 0.01)), 3, 50)
				t1 = time.tick_now()
				for _ in 0 ..< frames {
					render.render(&r, f, &img, {250, 250, 250, 255})
				}
				rend := time.duration_milliseconds(time.tick_since(t1)) / f64(frames)
				sum := checksum(&img)
				if ti == 0 {
					reference = sum
				}
				total := layout + rend
				fastest = min(fastest, total)
				if total <= budget {
					sm.best[ti] = n
				}
				mark := "!" if sum != reference else (" " if total <= budget else "*")
				fmt.printf(" %s%s", cell(fmt.tprintf("%.2f", rend), 7), mark)
			}
			fmt.println()
			ui.probe_destroy(&p)
			free_all(context.temp_allocator)
			if fastest > 2 * budget {
				break
			}
		}
		append(&summaries, sm)
	}

	fmt.printfln("\nlargest n within %.1f ms (* above: over budget, !: pixels differ from t=%d)", budget, threads[0])
	fmt.printf("%-12s", "family")
	for t in threads {
		fmt.printf(" %s", cell(fmt.tprintf("t=%d", t), 8))
	}
	fmt.println("   what")
	for sm in summaries {
		fmt.printf("%-12s", sm.name)
		for b in sm.best {
			fmt.printf(" %s", cell("<16" if b == 0 else fmt.tprint(b), 8))
		}
		fmt.printfln("   %s", sm.what)
	}
}
