package ui

import "core:math"
import "core:mem/virtual"
import "core:strings"
import "core:testing"

// golden_scene records a small scene touching every dump form. Shared with
// encode_test.odin.
golden_scene :: proc(ops: ^Ops) {
	font := add_font(ops, "inter.ttf")
	img := add_image(ops, "logo.png")
	run := add_run(ops, shape(stub_shaper(), font, 14, "Save", ops.allocator))
	verbs := make([]Path_Verb, 4, ops.allocator)
	copy(verbs, []Path_Verb{.Move, .Line, .Cubic, .Close})
	points := make([]Point, 5, ops.allocator)
	copy(points, []Point{{0, 0}, {10, 0}, {10, 5}, {5, 10}, {0, 10}})
	path := add_path(ops, {verbs, points})
	stops := make([]Gradient_Stop, 2, ops.allocator)
	copy(stops, []Gradient_Stop{{0, {0, 0, 0, 255}}, {1, {255, 255, 255, 255}}})

	push_transform(ops, translate(16, 16))
	push_clip(ops, Round_Rect{{0, 0, 200, 40}, 6})
	fill(ops, Round_Rect{{0, 0, 200, 40}, 6}, Color{0x33, 0x66, 0xff, 255})
	glyphs(ops, run, {8, 27}, Color{255, 255, 255, 255})
	input_area(ops, 12, Rect{0, 0, 200, 40}, {.Press, .Release})
	tag(ops, 12, "Save")
	pop_clip(ops)
	pop_transform(ops)
	m := macro_begin(ops)
	fill(ops, Ellipse{{0, 0, 10, 10}}, Color{255, 0, 0, 128})
	stroke(ops, Rect{0, 0, 10, 10}, Color{0, 0, 0, 255}, {1.5, .Round, .Bevel})
	macro_end(ops, m)
	push_transform(ops, translate(0, 50.25))
	call(ops, m)
	pop_transform(ops)
	push_clip(ops, Path_Ref{path})
	fill(ops, Rect{0, 0, 1, 2}, Linear_Gradient{{0, 0}, {1, 0}, stops})
	fill(ops, Path_Ref{path}, Radial_Gradient{{5, 5}, 2.5, stops[:1]})
	fill(ops, Rect{0, 0, 32, 32}, Image_Paint{img})
	pop_clip(ops)
	image(ops, img, {0, 0, 32, 32})
}

@(test)
test_dump_golden :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	ops: Ops
	ops_init(&ops)
	golden_scene(&ops)

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
	got := dump(&ops)
	testing.expectf(t, got == want, "dump:\n%s\nwant:\n%s", got, want)
}

@(test)
test_dump_frame_golden :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	ops: Ops
	ops_init(&ops)
	golden_scene(&ops)
	f: Frame
	frame_init(&f)
	flatten(&ops, &f)

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
	ops: Ops
	ops_init(&ops)
	push_transform(&ops, rotate(math.PI / 2))
	push_transform(&ops, rotate(math.PI))
	pop_transform(&ops)
	pop_transform(&ops)
	pop_transform(&ops) // unbalanced: dump clamps rather than failing
	input_area(&ops, 1, Rect{}, {})
	want := "transform 0 1 -1 0 0 0\n  transform -1 0 0 -1 0 0\ninput 1 rect 0 0 0 0 kinds=\n"
	testing.expect_value(t, dump(&ops), want)
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
		write_num(&sb, c.v)
		got := strings.to_string(sb)
		testing.expectf(t, got == c.want, "write_num(%v) = %q, want %q", c.v, got, c.want)
	}
	free_all(context.temp_allocator)
}
