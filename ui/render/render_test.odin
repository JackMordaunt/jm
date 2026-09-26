package render

import "core:math"
import "core:testing"

import "jm:ui"
import bl "jm:ui/blend2d"

@(private = "file")
RED :: ui.Color{255, 0, 0, 255}
@(private = "file")
WHITE :: ui.Color{255, 255, 255, 255}
when ODIN_OS == .Windows {
	@(private = "file")
	FONT :: "C:/Windows/Fonts/arial.ttf"
} else {
	@(private = "file")
	FONT :: "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
}
@(private = "file")
SIZE :: 64

// Fixture is a renderer, an Ops, a Frame over it and a 64×64 target.
@(private = "file")
Fixture :: struct {
	r:     Renderer,
	ops:   ui.Ops,
	frame: ui.Frame,
	img:   bl.ImageCore,
}

@(private = "file")
setup :: proc(fx: ^Fixture) {
	init(&fx.r)
	ui.ops_init(&fx.ops)
	ui.frame_init(&fx.frame)
	fx.frame.ops = &fx.ops
	bl.image_init(&fx.img)
	bl.image_create(&fx.img, SIZE, SIZE, .PRGB32)
}

@(private = "file")
teardown :: proc(fx: ^Fixture) {
	bl.image_destroy(&fx.img)
	ui.frame_destroy(&fx.frame)
	ui.ops_destroy(&fx.ops)
	destroy(&fx.r)
}

@(private = "file")
clip :: proc(fx: ^Fixture, parent: ui.Clip_Id, shape: ui.Shape, m: ui.Affine) -> ui.Clip_Id {
	append(&fx.frame.clips, ui.Clip{parent, shape, m})
	return ui.Clip_Id(len(fx.frame.clips) - 1)
}

@(private = "file")
fill :: proc(fx: ^Fixture, m: ui.Affine, c: ui.Clip_Id, shape: ui.Shape, paint: ui.Paint) {
	append(&fx.frame.draws, ui.Draw{m, c, ui.Fill{shape, paint}})
}

@(private = "file")
at :: proc(fx: ^Fixture, p: ui.Point) -> ui.Color {
	return pixel(&fx.img, int(p.x), int(p.y))
}

@(test)
test_fill_identity :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	fill(&fx, ui.IDENTITY, ui.NO_CLIP, ui.Rect{10, 10, 20, 20}, RED)
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
	m := ui.mul(ui.rotate(math.PI / 2), ui.translate(32, 32))
	fill(&fx, m, ui.NO_CLIP, ui.Rect{0, 0, 20, 4}, RED)
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	p := ui.apply(m, {10, 2})
	testing.expect_value(t, at(&fx, p), RED)
	// Where the rect would be without the rotation stays clear.
	testing.expect_value(t, at(&fx, {42, 34}), WHITE)
}

@(test)
test_rect_clip_fast_path :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	c := clip(&fx, ui.NO_CLIP, ui.Rect{0, 0, 20, 20}, ui.translate(10, 10))
	fill(&fx, ui.IDENTITY, c, ui.Rect{0, 0, SIZE, SIZE}, RED)
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
	c := clip(&fx, ui.NO_CLIP, ui.Round_Rect{{8, 8, 48, 48}, 24}, ui.IDENTITY)
	fill(&fx, ui.IDENTITY, c, ui.Rect{0, 0, SIZE, SIZE}, RED)
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
	m := ui.mul(ui.rotate(math.PI / 4), ui.translate(32, 32))
	c := clip(&fx, ui.NO_CLIP, ui.Rect{-10, -10, 20, 20}, m)
	fill(&fx, ui.IDENTITY, c, ui.Rect{0, 0, SIZE, SIZE}, RED)
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
	left := clip(&fx, ui.NO_CLIP, ui.Rect{0, 0, 32, SIZE}, ui.IDENTITY)
	circle := clip(&fx, left, ui.Ellipse{{8, 8, 48, 48}}, ui.IDENTITY)
	fill(&fx, ui.IDENTITY, circle, ui.Rect{0, 0, SIZE, SIZE}, RED)
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
	font := ui.add_font(&fx.ops, FONT)
	s := shaper(&fx.r, fx.ops.fonts[:])
	run := ui.shape(s, font, 32, "Hi", context.allocator)
	defer delete(run.glyphs)
	testing.expect_value(t, len(run.glyphs), 2)
	testing.expect(t, run.advance > 0)
	fm := ui.metrics(s, font, 32)
	testing.expect(t, fm.ascent > 0 && fm.descent > 0)

	id := ui.add_run(&fx.ops, run)
	origin := ui.Point{4, 44}
	append(&fx.frame.draws, ui.Draw{ui.IDENTITY, ui.NO_CLIP, ui.Glyphs{id, origin, {0, 0, 0, 255}}})
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

@(test)
test_path_gradient_stroke :: proc(t: ^testing.T) {
	fx: Fixture
	setup(&fx)
	defer teardown(&fx)
	verbs := []ui.Path_Verb{.Move, .Line, .Line, .Close}
	points := []ui.Point{{0, 0}, {30, 0}, {0, 30}}
	tri := ui.add_path(&fx.ops, {verbs, points})
	fill(&fx, ui.IDENTITY, ui.NO_CLIP, ui.Path_Ref{tri}, RED)
	stops := []ui.Gradient_Stop{{0, {0, 0, 255, 255}}, {1, {0, 255, 0, 255}}}
	fill(&fx, ui.IDENTITY, ui.NO_CLIP, ui.Rect{0, 40, SIZE, 10}, ui.Linear_Gradient{{0, 0}, {SIZE, 0}, stops})
	append(&fx.frame.draws, ui.Draw{ui.IDENTITY, ui.NO_CLIP, ui.Stroke{ui.Rect{40, 4, 20, 20}, RED, {4, .Butt, .Miter}}})
	render(&fx.r, &fx.frame, &fx.img, WHITE)
	testing.expect_value(t, at(&fx, {5, 5}), RED)
	testing.expect_value(t, at(&fx, {25, 25}), WHITE)
	left, right := at(&fx, {1, 45}), at(&fx, {62, 45})
	testing.expectf(t, left.b > 200 && right.g > 200, "gradient ends %v %v", left, right)
	testing.expect_value(t, at(&fx, {40, 14}), RED)
	testing.expect_value(t, at(&fx, {50, 14}), WHITE)
}
