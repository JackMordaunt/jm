package render

import "core:math"
import "core:os"
import "core:strings"
import "jm:ui/ops"
import "core:testing"

import "jm:ui"
import bl "jm:ui/blend2d"

// RED, WHITE and SIZE are package-private, not file-private: diff_test.odin
// shares them as its own test-fixture colors and dimension.
@(private)
RED :: ops.Color{255, 0, 0, 255}
@(private)
WHITE :: ops.Color{255, 255, 255, 255}
when ODIN_OS == .Windows {
	@(private = "file")
	FONT :: "C:/Windows/Fonts/arial.ttf"
} else when ODIN_OS == .Darwin {
	// A plain TrueType file every macOS since Catalina ships; the
	// system face, SFNS.ttf, is not one Blend2D reads.
	@(private = "file")
	FONT :: "/System/Library/Fonts/Supplemental/Arial.ttf"
} else {
	@(private = "file")
	FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}
@(private)
SIZE :: 64

// Fixture is a renderer, a Scene, a Frame over it and a 64×64 target.
@(private = "file")
Fixture :: struct {
	r:     Renderer,
	scene:   ops.Scene,
	frame: ui.Frame,
	img:   bl.ImageCore,
}

@(private = "file")
setup :: proc(fx: ^Fixture) {
	init(&fx.r)
	ops.init(&fx.scene)
	ui.frame_init(&fx.frame)
	fx.frame.scene = &fx.scene
	bl.image_init(&fx.img)
	bl.image_create(&fx.img, SIZE, SIZE, .PRGB32)
}

@(private = "file")
teardown :: proc(fx: ^Fixture) {
	bl.image_destroy(&fx.img)
	ui.frame_destroy(&fx.frame)
	ops.destroy(&fx.scene)
	destroy(&fx.r)
}

@(private = "file")
clip :: proc(fx: ^Fixture, parent: ui.Clip_Id, shape: ops.Shape, m: ops.Affine) -> ui.Clip_Id {
	append(&fx.frame.clips, ui.Clip{parent, shape, m})
	return ui.Clip_Id(len(fx.frame.clips) - 1)
}

@(private = "file")
fill :: proc(fx: ^Fixture, m: ops.Affine, c: ui.Clip_Id, shape: ops.Shape, paint: ops.Paint) {
	append(&fx.frame.draws, ui.Draw{m, c, ops.Fill{shape, paint}})
}

@(private = "file")
at :: proc(fx: ^Fixture, p: ops.Point) -> ops.Color {
	return pixel(&fx.img, int(p.x), int(p.y))
}

@(test)
test_fill_identity :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	fill(&fx, ops.IDENTITY, ui.NO_CLIP, ops.Rect{10, 10, 20, 20}, RED)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {15, 15}), RED)
	testing.expect_value(t, at(&fx, {29, 29}), RED)
	testing.expect_value(t, at(&fx, {5, 5}), WHITE)
	testing.expect_value(t, at(&fx, {31, 20}), WHITE)
}

@(test)
test_fill_rotated :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	m := ops.mul(ops.rotate(math.PI / 2), ops.translate(32, 32))
	fill(&fx, m, ui.NO_CLIP, ops.Rect{0, 0, 20, 4}, RED)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	p := ops.apply(m, {10, 2})
	testing.expect_value(t, at(&fx, p), RED)
	// Where the rect would be without the rotation stays clear.
	testing.expect_value(t, at(&fx, {42, 34}), WHITE)
}

@(test)
test_rect_clip_fast_path :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	c := clip(&fx, ui.NO_CLIP, ops.Rect{0, 0, 20, 20}, ops.translate(10, 10))
	fill(&fx, ops.IDENTITY, c, ops.Rect{0, 0, SIZE, SIZE}, RED)
	_, fast := rect_chain(&fx.frame, c)
	testing.expect(t, fast)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {10, 10}), RED)
	testing.expect_value(t, at(&fx, {29, 29}), RED)
	testing.expect_value(t, at(&fx, {9, 20}), WHITE)
	testing.expect_value(t, at(&fx, {30, 20}), WHITE)
	testing.expect_value(t, at(&fx, {50, 50}), WHITE)
}

@(test)
test_round_rect_clip :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	c := clip(&fx, ui.NO_CLIP, ops.Round_Rect{{8, 8, 48, 48}, 24}, ops.IDENTITY)
	fill(&fx, ops.IDENTITY, c, ops.Rect{0, 0, SIZE, SIZE}, RED)
	_, fast := rect_chain(&fx.frame, c)
	testing.expect(t, !fast)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {32, 32}), RED)
	testing.expect_value(t, at(&fx, {10, 10}), WHITE)
	testing.expect_value(t, at(&fx, {2, 32}), WHITE)
}

@(test)
test_rotated_rect_clip :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	// A 20×20 square rotated 45° about (32, 32): a diamond reaching 14 px out.
	m := ops.mul(ops.rotate(math.PI / 4), ops.translate(32, 32))
	c := clip(&fx, ui.NO_CLIP, ops.Rect{-10, -10, 20, 20}, m)
	fill(&fx, ops.IDENTITY, c, ops.Rect{0, 0, SIZE, SIZE}, RED)
	_, fast := rect_chain(&fx.frame, c)
	testing.expect(t, !fast)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {32, 32}), RED)
	testing.expect_value(t, at(&fx, {41, 32}), RED)
	testing.expect_value(t, at(&fx, {42, 42}), WHITE)
	testing.expect_value(t, at(&fx, {23, 23}), WHITE)
}

@(test)
test_nested_clip_intersects :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	left := clip(&fx, ui.NO_CLIP, ops.Rect{0, 0, 32, SIZE}, ops.IDENTITY)
	circle := clip(&fx, left, ops.Ellipse{{8, 8, 48, 48}}, ops.IDENTITY)
	fill(&fx, ops.IDENTITY, circle, ops.Rect{0, 0, SIZE, SIZE}, RED)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {20, 32}), RED)
	testing.expect_value(t, at(&fx, {40, 32}), WHITE)
	testing.expect_value(t, at(&fx, {10, 10}), WHITE)
}

@(test)
test_text :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	font := ops.add_font(&fx.scene, FONT)
	s := shaper(&fx.r, fx.scene.fonts[:])
	run := ui.shape(s, font, 32, "Hi", context.allocator)
	defer delete(run.glyphs)
	testing.expect_value(t, len(run.glyphs), 2)
	testing.expect(t, run.advance > 0)
	fm := ui.metrics(s, font, 32)
	testing.expect(t, fm.ascent > 0 && fm.descent > 0)

	// Clusters are byte offsets into the UTF-8 text: é is 2 bytes, € 3.
	multi := ui.shape(s, font, 32, "é€a", context.allocator)
	defer delete(multi.glyphs)
	testing.expect_value(t, len(multi.glyphs), 3)
	for want, i in ([]u32{0, 2, 5}) {
		testing.expect_value(t, multi.glyphs[i].cluster, want)
	}

	id := ops.add_run(&fx.scene, run)
	origin := ops.Point{4, 44}
	append(&fx.frame.draws, ui.Draw{ops.IDENTITY, ui.NO_CLIP, ops.Glyphs{id, origin, {0, 0, 0, 255}}})
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	bl.image_write_to_file(&fx.img, "build/test/text.png", nil)

	dark := 0
	for y in int(origin.y - fm.ascent) ..< int(origin.y) {
		for x in int(origin.x) ..< int(origin.x + run.advance) {
			if at(&fx, {f32(x), f32(y)}).r < 64 {
				dark += 1
			}
		}
	}
	testing.expectf(t, dark > 20, "dark pixels in glyph box: %d", dark)
	// Nothing is drawn left of the origin.
	testing.expect_value(t, at(&fx, {1, 30}), WHITE)
}

// second_font_view draws a line of text in font id 1.
@(private = "file")
second_font_view :: proc(gtx: ^ui.Ctx, _: rawptr) {
	gtx.font = 1
	ui.draw_text(gtx, "Hg", {4, 4}, 32, {0, 0, 0, 255})
}

// Two ids naming one file, as when an app falls back to one face for
// several weights, must both draw: id 1 is not folded into id 0.
@(test)
test_fonts_sharing_a_file_keep_their_ids :: proc(t: ^testing.T) {
	os.make_directory("build/test")
	path := "build/test/shared_font.png"
	defer os.remove(path)
	h: Headless
	headless_init(&h, second_font_view, nil, {SIZE, SIZE}, {{id = 0, path = FONT}, {id = 1, path = FONT}})
	defer headless_destroy(&h)
	testing.expect(t, headless_png(&h, path))

	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	testing.expect_value(t, bl.image_read_from_file(&img, cpath, nil), bl.Result(0))
	dark := 0
	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			if pixel(&img, x, y).r < 64 {
				dark += 1
			}
		}
	}
	testing.expectf(t, dark > 20, "dark pixels drawn in font id 1: %d", dark)
}

@(test)
test_text_draws_each_glyph_in_its_font :: proc(t: ^testing.T) {
	// "HH" with the second H put in font 7, which the scene lacks: each
	// glyph draws in its own font, so the second draws nothing.
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	font := ops.add_font(&fx.scene, FONT)
	run := ui.shape(shaper(&fx.r, fx.scene.fonts[:]), font, 24, "HH", context.allocator)
	defer delete(run.glyphs)
	testing.expect_value(t, len(run.glyphs), 2)
	run.glyphs[1].font = 7
	half := run.glyphs[1].x
	id := ops.add_run(&fx.scene, run)
	origin := ops.Point{4, 40}
	append(&fx.frame.draws, ui.Draw{ops.IDENTITY, ui.NO_CLIP, ops.Glyphs{id, origin, {0, 0, 0, 255}}})
	render(&fx.r, &fx.frame, &fx.img, WHITE)

	dark :: proc(fx: ^Fixture, x0, x1, y0, y1: f32) -> int {
		n := 0
		for y in int(y0) ..< int(y1) {
			for x in int(x0) ..< int(x1) {
				if at(fx, {f32(x), f32(y)}).r < 64 {
					n += 1
				}
			}
		}
		return n
	}
	testing.expect(t, dark(&fx, origin.x, origin.x + half, 20, 40) > 10, "the first H drawn")
	testing.expect_value(t, dark(&fx, origin.x + half + 1, min(origin.x + run.advance, SIZE), 20, 40), 0)
}

@(test)
test_path_gradient_stroke :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	verbs := []ops.Path_Verb{.Move, .Line, .Line, .Close}
	points := []ops.Point{{0, 0}, {30, 0}, {0, 30}}
	tri := ops.add_path(&fx.scene, {verbs, points})
	fill(&fx, ops.IDENTITY, ui.NO_CLIP, ops.Path_Ref{tri}, RED)
	stops := []ops.Gradient_Stop{{0, {0, 0, 255, 255}}, {1, {0, 255, 0, 255}}}
	fill(&fx, ops.IDENTITY, ui.NO_CLIP, ops.Rect{0, 40, SIZE, 10}, ops.Linear_Gradient{{0, 0}, {SIZE, 0}, stops})
	append(&fx.frame.draws, ui.Draw{ops.IDENTITY, ui.NO_CLIP, ops.Stroke{ops.Rect{40, 4, 20, 20}, RED, {4, .Butt, .Miter}}})
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {5, 5}), RED)
	testing.expect_value(t, at(&fx, {25, 25}), WHITE)
	left, right := at(&fx, {1, 45}), at(&fx, {62, 45})
	testing.expectf(t, left.b > 200 && right.g > 200, "gradient ends %v %v", left, right)
	testing.expect_value(t, at(&fx, {40, 14}), RED)
	testing.expect_value(t, at(&fx, {50, 14}), WHITE)
}

// Workers must draw what the synchronous path draws, masks included, while
// earlier masked commands still hold the layer.
@(test)
test_threads_match_sync :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	N :: 256
	bl.image_create(&fx.img, N, N, .PRGB32)

	rr := clip(&fx, ui.NO_CLIP, ops.Round_Rect{{8, 8, N - 16, N - 16}, 40}, ops.IDENTITY)
	rot := clip(&fx, ui.NO_CLIP, ops.Rect{0, 0, 120, 60}, ops.mul(ops.rotate(0.4), ops.translate(90, 40)))
	box := clip(&fx, ui.NO_CLIP, ops.Rect{20, 20, 100, 100}, ops.IDENTITY)
	for i in 0 ..< 64 {
		x, y := f32(i % 8) * 32, f32(i / 8) * 32
		c := [4]ui.Clip_Id{ui.NO_CLIP, rr, rot, box}[i % 4]
		col := ops.Color{u8(i * 4), u8(255 - i * 3), u8(i * 9), 200}
		fill(&fx, ops.translate(x, y), c, ops.Round_Rect{{0, 0, 40, 40}, 6}, col)
	}

	render(&fx.r, &fx.frame, &fx.img, WHITE)
	want := make([]u32, N * N)
	defer delete(want)
	copy_pixels(&fx.img, want)

	fx.r.threads = 4
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	got := make([]u32, N * N)
	defer delete(got)
	copy_pixels(&fx.img, got)

	diff := 0
	for v, i in want {
		if got[i] != v {
			diff += 1
		}
	}
	testing.expectf(t, diff == 0, "%d of %d pixels differ from the synchronous render", diff, N * N)
}

@(private = "file")
copy_pixels :: proc(img: ^bl.ImageCore, out: []u32) {
	data: bl.ImageData
	bl.image_get_data(img, &data)
	w := int(data.size.w)
	for y in 0 ..< int(data.size.h) {
		row := ([^]u32)(uintptr(data.pixel_data) + uintptr(y) * uintptr(data.stride))
		copy(out[y * w:][:w], row[:w])
	}
}

// A clip applies to the draws under it as a group: its antialiased edge
// covers the group once, so repeating an opaque draw changes nothing.
@(test)
test_masked_group_edge_applies_once :: proc(t: ^testing.T) {
	once, twice: Fixture
	setup(&once)
	defer teardown(&once)
	setup(&twice)
	defer teardown(&twice)
	rr := ops.Round_Rect{{6.5, 6.5, 50, 40}, 14}
	c1 := clip(&once, ui.NO_CLIP, rr, ops.IDENTITY)
	c2 := clip(&twice, ui.NO_CLIP, rr, ops.IDENTITY)
	fill(&once, ops.IDENTITY, c1, ops.Rect{0, 0, SIZE, SIZE}, RED)
	fill(&twice, ops.IDENTITY, c2, ops.Rect{0, 0, SIZE, SIZE}, RED)
	fill(&twice, ops.IDENTITY, c2, ops.Rect{0, 0, SIZE, SIZE}, RED)
	render(&once.r, &once.frame, &once.img, WHITE)
	render(&twice.r, &twice.frame, &twice.img, WHITE)
	differ := 0
	for y in 0 ..< SIZE {
		for x in 0 ..< SIZE {
			if at(&once, {f32(x), f32(y)}) != at(&twice, {f32(x), f32(y)}) {
				differ += 1
			}
		}
	}
	testing.expectf(t, differ == 0, "%d pixels differ between one and two fills", differ)
}

// A clip reaching past the target draws only the part inside; one wholly
// outside draws nothing.
@(test)
test_masked_clip_off_target :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	part := clip(&fx, ui.NO_CLIP, ops.Round_Rect{{-30, -30, 60, 60}, 20}, ops.IDENTITY)
	gone := clip(&fx, ui.NO_CLIP, ops.Round_Rect{{100, 100, 40, 40}, 10}, ops.IDENTITY)
	fill(&fx, ops.IDENTITY, part, ops.Rect{-40, -40, 200, 200}, RED)
	fill(&fx, ops.IDENTITY, gone, ops.Rect{0, 0, SIZE, SIZE}, RED)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {5, 5}), RED)
	testing.expect_value(t, at(&fx, {40, 40}), WHITE)
	testing.expect_value(t, at(&fx, {60, 60}), WHITE)
}

// A clip's interior is drawn without its mask, so the mask must be opaque
// on every pixel the interior claims: at fractional edges, under scale, in
// nested chains, and with a radius too big for the rect.
@(test)
test_clip_interior_is_opaque :: proc(t: ^testing.T) {
	Case :: struct {
		name:  string,
		outer: ops.Shape,
		inner: ops.Shape, // nil for a single-node chain
		m:     ops.Affine,
		least: f32, // the interior area the case must find
	}
	cases := []Case {
		{"fractional", ops.Round_Rect{{3.3, 4.7, 51.2, 49.9}, 9.6}, nil, ops.IDENTITY, 1500},
		{"scaled", ops.Round_Rect{{2.25, 3.5, 20.5, 18.75}, 5}, nil, ops.mul(ops.scale(2.5, 2.25), ops.translate(0.3, 0.6)), 1500},
		{"nested", ops.Rect{10.4, 0.5, 40.2, 63}, ops.Round_Rect{{1.5, 8.25, 60, 30.5}, 12}, ops.IDENTITY, 600},
		{"big radius", ops.Round_Rect{{8.5, 8.5, 40, 20}, 30}, nil, ops.IDENTITY, 0},
		{"past the target", ops.Round_Rect{{-20.5, 30.5, 120, 60}, 16}, nil, ops.IDENTITY, 1500},
	}
	for tc in cases {
		fx: Fixture
		setup(&fx)
		defer teardown(&fx)
		id := clip(&fx, ui.NO_CLIP, tc.outer, tc.m)
		if tc.inner != nil {
			id = clip(&fx, id, tc.inner, tc.m)
		}
		m := clip_mask(&fx.r, &fx.frame, id, SIZE, SIZE)
		inner := m.inner
		testing.expectf(t, inner.w * inner.h >= tc.least, "%s: interior %v is smaller than %v px", tc.name, inner, tc.least)
		// The mask skips the interior, so rasterize each node's coverage
		// over the whole box and check it there.
		whole := []ops.Rect{{0, 0, m.box.w, m.box.h}}
		partial := 0
		for c := id; c != ui.NO_CLIP; c = fx.frame.clips[c].parent {
			node := fx.frame.clips[c]
			node.transform = ops.mul(node.transform, ops.translate(-m.box.x, -m.box.y))
			cover: bl.ImageCore
			bl.image_init(&cover)
			defer bl.image_destroy(&cover)
			mask_view(&fx.r, &cover, m.box)
			fill_coverage(&fx.r, &fx.frame, &cover, node, whole)
			data: bl.ImageData
			bl.image_get_data(&cover, &data)
			for y in int(inner.y) ..< int(inner.y + inner.h) {
				row := ([^]u8)(uintptr(data.pixel_data) + uintptr((y - int(m.box.y)) * int(data.stride)))
				for x in int(inner.x) ..< int(inner.x + inner.w) {
					if row[x - int(m.box.x)] != 255 {
						partial += 1
					}
				}
			}
		}
		testing.expectf(t, partial == 0, "%s: %d interior pixels are not fully covered", tc.name, partial)
	}
}

// Drawing a clip's interior straight onto the target must look the same as
// drawing it through the layer: translucent draws overlapping across the
// interior's edge show no seam.
@(test)
test_clip_interior_no_seam :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	c := clip(&fx, ui.NO_CLIP, ops.Round_Rect{{2.5, 2.5, 59, 59}, 20}, ops.IDENTITY)
	for i in 0 ..< 4 {
		fill(&fx, ops.IDENTITY, c, ops.Rect{0, f32(i) * 8, SIZE, 30}, ops.Color{0, 80, 200, 90})
	}
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	// Row 40 is under the same fills from x = 4, in the ring, across the
	// interior's left edge near x = 9 and on to the ring at the right; away
	// from the antialiased edge every pixel must match.
	want := at(&fx, {4, 40})
	for x in 4 ..< 60 {
		got := at(&fx, {f32(x), 40})
		if got != want {
			testing.expectf(t, false, "pixel (%d, 40) is %v, the row starts %v", x, got, want)
			break
		}
	}
}
