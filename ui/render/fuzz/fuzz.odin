/*
Package fuzz is the jm:ui/render suite for jm:fuzz: the compositor's
promises, checked against generated scenes edited frame by frame.

	report := fuzz.run({seed = 1, iterations = 1000})

A whole-frame render of a Frame is the answer the compositor must reach,
so every generated case checks itself; no expected image is kept anywhere.

	matches_render  each composed frame is what render draws, within SEAM
	                steps of a channel where bands meet
	workers_agree   four workers compose exactly what one does
	still_is_free   composing a frame again changes nothing

What makes the compositor fast is also where it can be wrong without
crashing: conservative draw bounds, scroll detection and its safety checks,
clip interiors, bands. A wrong one leaves a stale pixel, which is what these
look for. The scenes mix clips of every kind, nested, turned and scrolled,
with fills, strokes, paths, gradients and text; one case in eight is big
enough to reach the paths the crew shares.
*/
package render_fuzz

import "base:runtime"
import "core:fmt"

import harness "jm:fuzz"
import "jm:ui"
import "jm:ui/render"
import bl "jm:ui/blend2d"

when ODIN_OS == .Windows {
	FONT :: "C:/Windows/Fonts/arial.ttf"
} else {
	FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}

BG :: ui.Color{240, 240, 244, 255}

// SEAM is how far a composed pixel may differ from a whole render: bands
// meet at tile edges, and a shape crossing one is rasterised against the
// band's edge rather than the target's, which can come out a few steps
// apart; the fuzzer has seen three.
SEAM :: 3

// FRAMES bounds how many edited frames a case composes after its first.
FRAMES :: 8

// CORPUS is where this suite's regressions live, relative to the repository
// root.
CORPUS :: "ui/render/fuzz/corpus"

// Rig is one case's renderer, compositors and targets. ref holds whole
// renders, one and crew what one and four workers composed.
Rig :: struct {
	r:         render.Renderer,
	one, crew: render.Compositor,
	ref:       bl.ImageCore,
	img_one:   bl.ImageCore,
	img_crew:  bl.ImageCore,
	size:      [2]i32,
	ops:       ui.Ops,
	frame:     ui.Frame,
	font:      ui.Font_Id,
}

properties := []harness.Property(^Rig) {
	{"matches_render", matches_render},
	{"workers_agree", workers_agree},
	{"still_is_free", still_is_free},
}

// suite is the compositor and its promises, ready for harness.run.
suite :: proc() -> harness.Suite(^Rig) {
	return harness.Suite(^Rig){name = "ui_render", setup = setup, teardown = teardown, properties = properties}
}

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

setup :: proc() -> (^Rig, bool) {
	g := new(Rig)
	render.init(&g.r)
	render.compositor_init(&g.one, 1)
	// The case's arena is not thread-safe, and the crew's workers allocate
	// on their own threads.
	render.compositor_init(&g.crew, 4, runtime.heap_allocator())
	for img in ([]^bl.ImageCore{&g.ref, &g.img_one, &g.img_crew}) {
		bl.image_init(img)
	}
	ui.ops_init(&g.ops)
	ui.frame_init(&g.frame)
	g.font = ui.add_font(&g.ops, FONT)
	return g, true
}

teardown :: proc(g: ^^Rig) {
	r := g^
	for img in ([]^bl.ImageCore{&r.ref, &r.img_one, &r.img_crew}) {
		bl.image_destroy(img)
	}
	render.compositor_destroy(&r.one)
	render.compositor_destroy(&r.crew)
	render.destroy(&r.r)
	ui.frame_destroy(&r.frame)
	ui.ops_destroy(&r.ops)
	free(r)
}

// advance builds the next frame of the case into g, first the generated scene
// and then that scene edited, and resizes the targets to it.
advance :: proc(g: ^Rig, src: ^harness.Source, m: ^Model, n: int) {
	if n > 0 {
		edits := harness.integer_in(src, 1, 4)
		for _ in 0 ..< edits {
			edit(src, m)
		}
	}
	if m.size != g.size {
		g.size = m.size
		for img in ([]^bl.ImageCore{&g.ref, &g.img_one, &g.img_crew}) {
			bl.image_create(img, m.size.x, m.size.y, .PRGB32)
		}
	}
	build(m, &g.ops, &g.frame, render.shaper(&g.r, g.ops.fonts[:]), g.font)
}

frames :: proc(src: ^harness.Source) -> int {
	return 1 + harness.integer_in(src, 0, FRAMES + 1)
}

matches_render :: proc(g: ^Rig, src: ^harness.Source) -> (string, bool) {
	m := generate(src)
	count := frames(src)
	for n in 0 ..< count {
		advance(g, src, &m, n)
		render.compose(&g.one, &g.frame, &g.img_one, BG)
		render.render(&g.r, &g.frame, &g.ref, BG)
		if d, at := max_delta(&g.img_one, &g.ref); d > SEAM {
			return fmt.aprintf("frame %d (%v, %d draws): composed differs from a whole render by %d at %v", n, m.size, len(g.frame.draws), d, at), false
		}
	}
	return "", true
}

workers_agree :: proc(g: ^Rig, src: ^harness.Source) -> (string, bool) {
	m := generate(src)
	count := frames(src)
	for n in 0 ..< count {
		advance(g, src, &m, n)
		render.compose(&g.one, &g.frame, &g.img_one, BG)
		render.compose(&g.crew, &g.frame, &g.img_crew, BG)
		if d, at := max_delta(&g.img_one, &g.img_crew); d > 0 {
			return fmt.aprintf("frame %d (%v, %d draws): four workers differ from one by %d at %v", n, m.size, len(g.frame.draws), d, at), false
		}
	}
	return "", true
}

still_is_free :: proc(g: ^Rig, src: ^harness.Source) -> (string, bool) {
	m := generate(src)
	count := frames(src)
	for n in 0 ..< count {
		advance(g, src, &m, n)
		render.compose(&g.one, &g.frame, &g.img_one, BG)
		// The same scene built again, not the same Frame: nothing may depend
		// on memory the frame happens to reuse.
		build(&m, &g.ops, &g.frame, render.shaper(&g.r, g.ops.fonts[:]), g.font)
		if again := render.compose(&g.one, &g.frame, &g.img_one, BG); len(again) > 0 {
			return fmt.aprintf("frame %d (%v): composing it again changed %v", n, m.size, again), false
		}
	}
	return "", true
}

// max_delta is the largest channel difference between two same-size
// images, and the first pixel where it occurs.
max_delta :: proc(a, b: ^bl.ImageCore) -> (worst: int, at: [2]int) {
	da, db: bl.ImageData
	bl.image_get_data(a, &da)
	bl.image_get_data(b, &db)
	for y in 0 ..< int(da.size.h) {
		ra := ([^]u32)(uintptr(da.pixel_data) + uintptr(y) * uintptr(da.stride))
		rb := ([^]u32)(uintptr(db.pixel_data) + uintptr(y) * uintptr(db.stride))
		for x in 0 ..< int(da.size.w) {
			if ra[x] == rb[x] {
				continue
			}
			for sh in ([]u32{0, 8, 16, 24}) {
				d := abs(int((ra[x] >> sh) & 0xFF) - int((rb[x] >> sh) & 0xFF))
				if d > worst {
					worst, at = d, {x, y}
				}
			}
		}
	}
	return
}
