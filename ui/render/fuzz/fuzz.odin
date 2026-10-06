/*
Package fuzz is the jm:ui/render suite for jm:fuzz: the compositor's
promises, checked against generated scenes edited frame by frame.

	report := fuzz.run({seed = 1, iterations = 1000})

A whole-frame render of a Frame is the answer the compositor must reach,
so every generated case checks itself; no expected image is kept anywhere.

	matches_render  each composed frame is what render draws, whole or in
	                bands, within SEAM steps of a channel where bands meet
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
import "jm:ui/ops"

import harness "jm:fuzz"
import "jm:ui"
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

BG :: ops.Color{240, 240, 244, 255}

// SEAM is how far a composed pixel may differ from a whole render. A band
// renders its draws moved by its offset and clipped at its own edges, and
// antialiased edges, masks and gradients come out a few steps apart from a
// whole render; seed 1 found five, at case 10281.
//
// Blend2D (at the justfile's blend2d_rev, on macOS arm64) also covers a
// pixel on a 45-degree edge fully where a whole render covers it by half,
// when the image or its clip ends 64 rows down, a band's bottom edge. Both
// corpus cases are that. So a composed pixel may instead match the frame
// rendered band by band, which shares the band's clip and none of the
// compositor's damage, scrolling or caching.
SEAM :: 6

// FRAMES bounds how many edited frames a case composes after its first.
FRAMES :: 8

// CORPUS is where this suite's regressions live, relative to the repository
// root.
CORPUS :: "ui/render/fuzz/corpus"

// Rig is one case's renderer, compositors and targets. ref holds whole
// renders, one and crew what one and four workers composed. The composed
// targets are views into buffers of the biggest size, resized in place as a
// window's are, so a resize keeps what they hold.
Rig :: struct {
	r:         render.Renderer,
	one, crew: render.Compositor,
	ref:       bl.ImageCore,
	banded:    bl.ImageCore, // ref drawn a tile's rows at a time
	sub:       ui.Frame, // one band's draws, for banded
	img_one:   bl.ImageCore,
	img_crew:  bl.ImageCore,
	buf_one:   bl.ImageCore, // what img_one views
	buf_crew:  bl.ImageCore,
	size:      [2]i32,
	scene:     ops.Scene,
	frame:     ui.Frame,
	font:      ops.Font_Id,
}

properties := []harness.Property(^Rig) {
	{"matches_render", matches_render},
	{"workers_agree", workers_agree},
	{"still_is_free", still_is_free},
}

// suite is the compositor and its promises, ready for harness.run.
suite :: proc() -> harness.Suite(^Rig) {
	return harness.Suite(^Rig) {
		name = "ui_render",
		setup = setup,
		teardown = teardown,
		properties = properties,
	}
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
	g.one.damage.resize_in_place = true
	g.crew.damage.resize_in_place = true
	for img in ([]^bl.ImageCore{&g.ref, &g.banded, &g.img_one, &g.img_crew, &g.buf_one, &g.buf_crew}) {
		bl.image_init(img)
	}
	ops.init(&g.scene)
	ui.frame_init(&g.frame)
	ui.frame_init(&g.sub)
	g.font = ops.add_font(&g.scene, FONT)
	return g, true
}

teardown :: proc(g: ^^Rig) {
	r := g^
	for img in ([]^bl.ImageCore{&r.ref, &r.banded, &r.img_one, &r.img_crew, &r.buf_one, &r.buf_crew}) {
		bl.image_destroy(img)
	}
	render.compositor_destroy(&r.one)
	render.compositor_destroy(&r.crew)
	render.destroy(&r.r)
	ui.frame_destroy(&r.frame)
	ui.frame_destroy(&r.sub)
	ops.destroy(&r.scene)
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
		bl.image_create(&g.ref, m.size.x, m.size.y, .PRGB32)
		bl.image_create(&g.banded, m.size.x, m.size.y, .PRGB32)
		views := [2][2]^bl.ImageCore{{&g.img_one, &g.buf_one}, {&g.img_crew, &g.buf_crew}}
		for v in views {
			data: bl.ImageData
			if bl.image_get_data(v[1], &data) != 0 || data.size.w == 0 {
				bl.image_create(v[1], BIG.x, BIG.y, .PRGB32)
				bl.image_get_data(v[1], &data)
			}
			bl.image_create_from_data(
				v[0],
				m.size.x,
				m.size.y,
				.PRGB32,
				data.pixel_data,
				data.stride,
				.RW,
				nil,
				nil,
			)
		}
	}
	build(m, &g.scene, &g.frame, render.shaper(&g.r, g.scene.fonts[:]), g.font)
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
		render_banded(g)
		if d, at := max_delta(&g.img_one, &g.ref, &g.banded); d > SEAM {
			return fmt.aprintf(
					"frame %d (%v, %d draws): composed differs from a whole render by %d at %v",
					n,
					m.size,
					len(g.frame.draws),
					d,
					at,
				),
				false
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
			return fmt.aprintf(
					"frame %d (%v, %d draws): four workers differ from one by %d at %v",
					n,
					m.size,
					len(g.frame.draws),
					d,
					at,
				),
				false
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
		build(&m, &g.scene, &g.frame, render.shaper(&g.r, g.scene.fonts[:]), g.font)
		if again := render.compose(&g.one, &g.frame, &g.img_one, BG); len(again) > 0 {
			return fmt.aprintf("frame %d (%v): composing it again changed %v", n, m.size, again),
				false
		}
	}
	return "", true
}

// max_delta is the largest channel difference between two same-size
// images, and the first pixel where it occurs.
// max_delta is the largest step of a channel between a and b, and where it
// is. Given or_c, a pixel's step is the smaller of its steps to b and to or_c.
max_delta :: proc(a, b: ^bl.ImageCore, or_c: ^bl.ImageCore = nil) -> (worst: int, at: [2]int) {
	da, db, dc: bl.ImageData
	bl.image_get_data(a, &da)
	bl.image_get_data(b, &db)
	dc = db
	if or_c != nil {
		bl.image_get_data(or_c, &dc)
	}
	for y in 0 ..< int(da.size.h) {
		ra := ([^]u32)(uintptr(da.pixel_data) + uintptr(y) * uintptr(da.stride))
		rb := ([^]u32)(uintptr(db.pixel_data) + uintptr(y) * uintptr(db.stride))
		rc := ([^]u32)(uintptr(dc.pixel_data) + uintptr(y) * uintptr(dc.stride))
		for x in 0 ..< int(da.size.w) {
			if ra[x] == rb[x] {
				continue
			}
			d := min(pixel_delta(ra[x], rb[x]), pixel_delta(ra[x], rc[x]))
			if d > worst {
				worst, at = d, {x, y}
			}
		}
	}
	return
}

// pixel_delta is the largest step between two pixels' channels.
pixel_delta :: proc(p, q: u32) -> (worst: int) {
	for sh in ([]u32{0, 8, 16, 24}) {
		worst = max(worst, abs(int((p >> sh) & 0xFF) - int((q >> sh) & 0xFF)))
	}
	return
}

// render_banded draws the frame into banded one tile's rows at a time, each
// band a view of its rows with the frame moved up to meet it, as the
// compositor paints one.
render_banded :: proc(g: ^Rig) {
	data: bl.ImageData
	bl.image_get_data(&g.banded, &data)
	for y := 0; y < int(data.size.h); y += render.TILE {
		rows := min(render.TILE, int(data.size.h) - y)
		shift := ops.translate(0, -f32(y))
		ui.frame_reset(&g.sub)
		g.sub.scene = g.frame.scene
		for cl in g.frame.clips {
			append(&g.sub.clips, ui.Clip{cl.parent, cl.shape, ops.mul(cl.transform, shift)})
		}
		for d in g.frame.draws {
			append(&g.sub.draws, ui.Draw{ops.mul(d.transform, shift), d.clip, d.cmd, d.fade})
		}
		px := rawptr(uintptr(data.pixel_data) + uintptr(y * int(data.stride)))
		view: bl.ImageCore
		bl.image_init(&view)
		bl.image_create_from_data(
			&view,
			data.size.w,
			i32(rows),
			.PRGB32,
			px,
			int(data.stride),
			.RW,
			nil,
			nil,
		)
		render.render(&g.r, &g.sub, &view, BG)
		bl.image_destroy(&view)
	}
}
