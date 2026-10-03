package ui

import "core:math"
import "jm:ui/ops"
import "core:mem/virtual"
import "core:strings"
import "core:testing"

// golden_scene records a small scene touching every dump form. Shared with
// encode_test.odin.
@(private)
golden_scene :: proc(sc: ^ops.Scene) {
	font := ops.add_font(sc, "inter.ttf")
	img := ops.add_image(sc, "logo.png")
	run := ops.add_run(sc, shape(stub_shaper(), font, 14, "Save", sc.allocator))
	verbs := make([]ops.Path_Verb, 4, sc.allocator)
	copy(verbs, []ops.Path_Verb{.Move, .Line, .Cubic, .Close})
	points := make([]ops.Point, 5, sc.allocator)
	copy(points, []ops.Point{{0, 0}, {10, 0}, {10, 5}, {5, 10}, {0, 10}})
	path := ops.add_path(sc, {verbs = verbs, points = points})
	stops := make([]ops.Gradient_Stop, 2, sc.allocator)
	copy(stops, []ops.Gradient_Stop{{0, {0, 0, 0, 255}}, {1, {255, 255, 255, 255}}})

	ops.transform_push(sc, ops.translate(16, 16))
	ops.clip_push(sc, ops.Round_Rect{{0, 0, 200, 40}, 6})
	ops.fill(sc, ops.Round_Rect{{0, 0, 200, 40}, 6}, ops.Color{0x33, 0x66, 0xff, 255})
	ops.glyphs(sc, run, {8, 27}, ops.Color{255, 255, 255, 255})
	ops.input_area(sc, 12, ops.Rect{0, 0, 200, 40}, {.Press, .Release})
	ops.tag(sc, 12, "Save")
	ops.clip_pop(sc)
	ops.transform_pop(sc)
	m := ops.macro_open(sc)
	ops.fill(sc, ops.Ellipse{{0, 0, 10, 10}}, ops.Color{255, 0, 0, 128})
	ops.stroke(sc, ops.Rect{0, 0, 10, 10}, ops.Color{0, 0, 0, 255}, {1.5, .Round, .Bevel})
	ops.macro_close(sc, m)
	ops.transform_push(sc, ops.translate(0, 50.25))
	ops.call(sc, m)
	ops.transform_pop(sc)
	ops.clip_push(sc, ops.Path_Ref{path})
	ops.fill(sc, ops.Rect{0, 0, 1, 2}, ops.Linear_Gradient{{0, 0}, {1, 0}, stops})
	ops.fill(sc, ops.Path_Ref{path}, ops.Radial_Gradient{{5, 5}, 2.5, stops[:1]})
	ops.fill(sc, ops.Rect{0, 0, 32, 32}, ops.Image_Paint{img})
	ops.clip_pop(sc)
	ops.image(sc, img, {0, 0, 32, 32})
}

@(test)
test_dump_golden :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	golden_scene(&sc)

	want := `transform 1 0 0 1 16 16
  clip rrect 0 0 200 40 6
    fill rrect 0 0 200 40 6 #3366ff
    glyphs font=0 size=14 run#0 n=4 adv=33.6 #ffffff @ 8 27
    input 12 rect 0 0 200 40 kinds=press,release
    tag 12 "Save"
macro 0
  fill ellipse 0 0 10 10 #ff000080
  stroke rect 0 0 10 10 #000000 w=1.5 cap=round join=bevel
transform 1 0 0 1 0 50.25
  call 0
clip path#0
  fill rect 0 0 1 2 linear 0 0 1 0 stops=2
  fill path#0 radial 5 5 2.5 stops=1
  fill rect 0 0 32 32 image#0
image#0 dst 0 0 32 32 src 0 0 0 0
`
	got := ops.dump(&sc)
	testing.expectf(t, got == want, "dump:\n%s\nwant:\n%s", got, want)
}

@(test)
test_dump_frame_golden :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	golden_scene(&sc)
	f: Frame
	frame_init(&f)
	flatten(&sc, &f)

	want := `draws
  draw 0 clip=0 [1 0 0 1 16 16] fill rrect 0 0 200 40 6 #3366ff
  draw 1 clip=0 [1 0 0 1 16 16] glyphs font=0 size=14 run#0 n=4 adv=33.6 #ffffff @ 8 27
  draw 2 clip=none [1 0 0 1 0 50.25] fill ellipse 0 0 10 10 #ff000080
  draw 3 clip=none [1 0 0 1 0 50.25] stroke rect 0 0 10 10 #000000 w=1.5 cap=round join=bevel
  draw 4 clip=1 [1 0 0 1 0 0] fill rect 0 0 1 2 linear 0 0 1 0 stops=2
  draw 5 clip=1 [1 0 0 1 0 0] fill path#0 radial 5 5 2.5 stops=1
  draw 6 clip=1 [1 0 0 1 0 0] fill rect 0 0 32 32 image#0
  draw 7 clip=none [1 0 0 1 0 0] image#0 dst 0 0 32 32 src 0 0 0 0
clips
  clip 0 parent=none [1 0 0 1 16 16] rrect 0 0 200 40 6
  clip 1 parent=none [1 0 0 1 0 0] path#0
hits
  hit 0 area=12 order=0 clip=0 [1 0 0 1 16 16] rect 0 0 200 40 kinds=press,release
tags
  tag 12 "Save"
`
	got := dump_frame(&f)
	testing.expectf(t, got == want, "dump_frame:\n%s\nwant:\n%s", got, want)
}

@(test)
test_dump_rotated_matrix_has_no_negative_zero :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	ops.transform_push(&sc, ops.rotate(math.PI / 2))
	ops.transform_push(&sc, ops.rotate(math.PI))
	ops.transform_pop(&sc)
	ops.transform_pop(&sc)
	ops.transform_pop(&sc) // unbalanced: dump clamps rather than failing
	ops.input_area(&sc, 1, ops.Rect{}, {})
	want := "transform 0 1 -1 0 0 0\n  transform -1 0 0 -1 0 0\ninput 1 rect 0 0 0 0 kinds=\n"
	testing.expect_value(t, ops.dump(&sc), want)
}

@(test)
test_fnum :: proc(t: ^testing.T) {
	Case :: struct {
		v:    f64,
		want: string,
	}
	cases := [?]Case {
		{0, "0"},
		{-0.0, "0"},
		{1, "1"},
		{-2, "-2"},
		{200, "200"},
		{0.5, "0.5"},
		{1.25, "1.25"},
		{-1.125, "-1.125"},
		{1.0 / 3.0, "0.333"},
		{2.0 / 3.0, "0.667"},
		{-0.0001, "0"},
		{0.9999, "1"},
		{f64(f32(33.6)), "33.6"},
		{f64(f32(0.1)), "0.1"},
		{1e20, "100000000000000000000"},
		{math.nan_f64(), "nan"},
		{math.inf_f64(1), "inf"},
		{math.inf_f64(-1), "-inf"},
	}
	for c in cases {
		sb := strings.builder_make(context.temp_allocator)
		ops.write_num(&sb, c.v)
		got := strings.to_string(sb)
		testing.expectf(t, got == c.want, "write_num(%v) = %q, want %q", c.v, got, c.want)
	}
	free_all(context.temp_allocator)
}
