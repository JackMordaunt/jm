// ui-bench times jm:ui per frame: layout and flatten on one side, the
// Blend2D executor on the other, for scenes that stress different paths.
//
//	ui-bench            every scene at 900x600
//	ui-bench -n 50      frames per measurement (default 20)
//	ui-bench -w 1800 -h 1200
//	ui-bench -t 0,1,2,4,8   Blend2D worker threads to try (default 0,2,4,8)
//	ui-bench -sweep         grow each kind of content until a frame is over budget
//	ui-bench -sweep -budget 8.3   the same against a 120 Hz frame
//	ui-bench -compose       partial repaint by render.Compositor; -t lists worker counts
//	ui-bench -grid          jm:ui/datagrid over 100,000 rows: still, wheeled, flung, sideways
//
// Layout is timed once per scene. Render is timed per thread count, and a
// checksum of the pixels is compared with the synchronous render so a
// threaded run that draws something else is reported, not hidden.
package main

import "core:fmt"
import "jm:ui/ops"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"
import "jm:ui"
import "jm:ui/base"
import m3 "jm:ui/material"
import bl "jm:ui/blend2d"
import "jm:ui/render"

when ODIN_OS == .Windows {
	FONT :: "C:/Windows/Fonts/arial.ttf"
} else when ODIN_OS == .Darwin {
	// The system face, SFNS.ttf, is not one Blend2D reads.
	FONT :: "/System/Library/Fonts/Supplemental/Arial.ttf"
} else {
	FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}

Scene :: struct {
	name: string,
	what: string,
	ui:   proc(gtx: ^ui.Ctx, user: rawptr),
}

State :: struct {
	list:   ui.List_State,
	rows:   int,
	rrect:  bool,
	count:  int,
	toggle: bool,
}

// widgets: a virtualised list of label+button rows, rect clips only.
widgets :: proc(gtx: ^ui.Ctx, user: rawptr) {
	s := (^State)(user)
	page := ui.inset_open(gtx, ui.pad_all(16))
	defer ui.close(&page)
	if s.rrect {
		// A round-rect clip over the whole page: every draw takes the mask path.
		ops.clip_push(gtx.scene, ops.Round_Rect{{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, 24})
	}
	card := base.panel_open(gtx)
	ui.list(gtx, &s.list, s.rows, row, s)
	ui.close(&card)
	if s.rrect {
		ops.clip_pop(gtx.scene)
	}
}

row :: proc(gtx: ^ui.Ctx, i: int, user: rawptr) {
	s := (^State)(user)
	r := ui.row_open(gtx, gap = 8, align = .Center)
	defer ui.close(&r)
	base.label(gtx, fmt.tprintf("Row %d", i))
	m3.checkbox(gtx, &s.toggle)
	ui.fill_space(gtx)
	if m3.button(gtx, "Pick") {
		s.count += 1
	}
}

// rects: raw fill throughput, 5000 small rects, no widgets.
rects :: proc(gtx: ^ui.Ctx, _: rawptr) {
	w, h := gtx.constraints.max.x, gtx.constraints.max.y
	for i in 0 ..< 5000 {
		x := f32(i % 100) * (w / 100)
		y := f32(i / 100) * (h / 50)
		ops.fill(gtx.scene, ops.Rect{x, y, w / 100 - 1, h / 50 - 1}, ops.Color{u8(i), u8(i * 3), u8(i * 7), 255})
	}
}

// rrects: the same count as round rects, which Blend2D fills as geometry.
rrects :: proc(gtx: ^ui.Ctx, _: rawptr) {
	w, h := gtx.constraints.max.x, gtx.constraints.max.y
	for i in 0 ..< 5000 {
		x := f32(i % 100) * (w / 100)
		y := f32(i / 100) * (h / 50)
		ops.fill(gtx.scene, ops.Round_Rect{{x, y, w / 100 - 1, h / 50 - 1}, 3}, ops.Color{u8(i), u8(i * 3), u8(i * 7), 255})
	}
}

// text: 2000 shaped labels; shaping and glyph rasterisation.
text :: proc(gtx: ^ui.Ctx, _: rawptr) {
	w := gtx.constraints.max.x
	cols := int(w / 90)
	for i in 0 ..< 2000 {
		x := f32(i % cols) * 90
		y := f32(i / cols) * 16
		if y > gtx.constraints.max.y {
			break
		}
		ops.transform_push(gtx.scene, ops.translate(x, y))
		base.label(gtx, fmt.tprintf("label %d", i))
		ops.transform_pop(gtx.scene)
	}
}

// masked: 200 fills each under its own rotated clip, the worst case for
// the mask path: a new mask and a layer composite per draw.
masked :: proc(gtx: ^ui.Ctx, _: rawptr) {
	w, h := gtx.constraints.max.x, gtx.constraints.max.y
	for i in 0 ..< 200 {
		x := f32(i % 20) * (w / 20)
		y := f32(i / 20) * (h / 10)
		ops.transform_push(gtx.scene, ops.mul(ops.rotate(0.3), ops.translate(x, y)))
		ops.clip_push(gtx.scene, ops.Rect{0, 0, w / 20, h / 10})
		ops.fill(gtx.scene, ops.Rect{-10, -10, w / 20 + 20, h / 10 + 20}, ops.Color{u8(i), 120, 200, 255})
		ops.clip_pop(gtx.scene)
		ops.transform_pop(gtx.scene)
	}
}

// checksum folds every pixel of img into one value.
checksum :: proc(img: ^bl.ImageCore) -> u64 {
	data: bl.ImageData
	if bl.image_get_data(img, &data) != 0 {
		return 0
	}
	sum: u64 = 1469598103934665603
	for y in 0 ..< int(data.size.h) {
		row := ([^]u32)(uintptr(data.pixel_data) + uintptr(y) * uintptr(data.stride))
		for x in 0 ..< int(data.size.w) {
			sum = (sum ~ u64(row[x])) * 1099511628211
		}
	}
	return sum
}

main :: proc() {
	n := 20
	w, h := 900, 600
	threads := []u32{0, 2, 4, 8}
	budget := 1000.0 / 60
	do_sweep := false
	do_compose := false
	do_grid := false
	args := make([dynamic]string)
	for a in os.args[1:] {
		if a == "-sweep" {
			do_sweep = true
		} else if a == "-compose" {
			do_compose = true
		} else if a == "-grid" {
			do_grid = true
		} else {
			append(&args, a)
		}
	}
	for i := 0; i < len(args); i += 1 {
		if i + 1 >= len(args) {
			break
		}
		switch args[i] {
		case "-n":
			n, _ = strconv.parse_int(args[i + 1])
		case "-w":
			w, _ = strconv.parse_int(args[i + 1])
		case "-h":
			h, _ = strconv.parse_int(args[i + 1])
		case "-t":
			list := make([dynamic]u32)
			for part in strings.split(args[i + 1], ",", context.temp_allocator) {
				v, _ := strconv.parse_uint(part)
				append(&list, u32(v))
			}
			threads = list[:]
		case "-budget":
			budget, _ = strconv.parse_f64(args[i + 1])
		}
		i += 1
	}

	if do_compose {
		workers := make([]int, len(threads))
		for t, i in threads {
			workers[i] = max(int(t), 1)
		}
		compose_bench(w, h, workers, n)
		return
	}
	if do_sweep {
		sweep(w, h, threads, budget)
		return
	}
	if do_grid {
		grid_bench(w, h, n)
		return
	}

	scenes := []Scene {
		{"widgets", "300-row list, rect clips", widgets},
		{"widgets+rrect", "same under one round-rect clip (mask path)", widgets},
		{"rects", "5000 rect fills", rects},
		{"rrects", "5000 round-rect fills", rrects},
		{"text", "2000 labels", text},
		{"masked", "200 fills, each under a rotated clip", masked},
	}

	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	assert(bl.image_create(&img, i32(w), i32(h), .PRGB32) == 0)

	fmt.printfln("%dx%d, %d frames each, ms per frame; render columns are Blend2D thread counts", w, h, n)
	cell :: proc(v: string, width: int) -> string {
		return strings.right_justify(v, width, " ", context.temp_allocator)
	}
	fmt.printf("%-14s %6s %8s", "scene", "draws", "layout")
	for t in threads {
		fmt.printf(" %s", cell(fmt.tprintf("t=%d", t), 8))
	}
	fmt.println("   what")
	for sc in scenes {
		st := State{rows = 300, rrect = sc.name == "widgets+rrect"}
		p: ui.Probe
		ui.probe_init(&p, sc.ui, &st, {f32(w), f32(h)})
		ops.add_font(&p.scene, FONT)
		p.shaper = render.shaper(&r, p.scene.fonts[:])
		ui.probe_frame(&p)
		ui.probe_frame(&p) // weights settle on the second frame

		t0 := time.tick_now()
		for _ in 0 ..< n {
			ui.probe_frame(&p)
		}
		layout := time.duration_milliseconds(time.tick_since(t0)) / f64(n)

		f := ui.probe_current(&p)
		fmt.printf("%-14s %s %s", sc.name, cell(fmt.tprint(len(f.draws)), 6), cell(fmt.tprintf("%.2f", layout), 8))
		reference: u64
		for t, ti in threads {
			r.threads = t
			render.render(&r, f, &img, {250, 250, 250, 255}) // warm the thread pool and the JIT
			t1 := time.tick_now()
			for _ in 0 ..< n {
				render.render(&r, f, &img, {250, 250, 250, 255})
			}
			rend := time.duration_milliseconds(time.tick_since(t1)) / f64(n)
			sum := checksum(&img)
			if ti == 0 {
				reference = sum
			}
			fmt.printf(" %s%s", cell(fmt.tprintf("%.2f", rend), 7), "!" if sum != reference else " ")
		}
		fmt.printfln("   %s", sc.what)
		ui.probe_destroy(&p)
	}
}
