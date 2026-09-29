package diagram

import "core:testing"
import "jm:ui/ops"
import "jm:ui"
import "jm:ui/testutil"

@(private = "file")
Harness :: struct {
	scene:   ops.Scene,
	theme: ui.Theme,
	gtx:   ui.Ctx,
}

@(private = "file")
harness_init :: proc(h: ^Harness) {
	ops.init(&h.scene)
	h.theme = ui.light_theme(0)
	h.gtx = {
		scene         = &h.scene,
		constraints = ui.exact({800, 600}),
		theme       = &h.theme,
		shaper      = ui.stub_shaper(),
		allocator   = context.temp_allocator,
	}
}

@(private = "file")
harness_destroy :: proc(h: ^Harness) {
	ops.destroy(&h.scene)
	free_all(context.temp_allocator)
}

@(test)
test_group_draws_the_header_and_every_chip :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)

	chips := []Chip{{"A", "a"}, {"B", "b"}, {"C", "c"}}
	r := ops.Rect{0, 0, 300, group_height(len(chips))}
	group(&h.gtx, r, "Title", "Subtitle", ops.Color{0, 0, 255, 255}, chips)

	// One background fill and one accent stripe for the card itself, plus
	// one background fill and one accent stripe per chip.
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Fill), 2+2*len(chips))
	// Title, subtitle, and title+subtitle per chip.
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Glyphs), 2+2*len(chips))
}

@(test)
test_group_height_matches_groups_own_layout :: proc(t: ^testing.T) {
	testing.expect_value(t, group_height(0), f32(74))
	// group's loop starts each chip at 74 below r.y, steps by chip_h + gap
	// (62 + 10) per chip, and group_height adds 16 below the last one.
	for n in 1 ..= 5 {
		want := f32(74 + n * 62 + (n - 1) * 10 + 16)
		testing.expect_value(t, group_height(n), want)
	}
}

@(test)
test_arrow_draws_a_shaft_and_a_head :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)

	arrow(&h.gtx, {0, 0}, {100, 0}, ops.Color{255, 0, 0, 255}, 2)
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Stroke), 1) // the shaft
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Fill), 1) // the head
}

@(test)
test_arrow_degenerate_points_draw_nothing :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)

	arrow(&h.gtx, {5, 5}, {5, 5}, ops.Color{255, 0, 0, 255}, 2)
	testing.expect_value(t, len(h.scene.ops), 0)
}

@(test)
test_dashed_arrow_draws_several_segments_and_one_head :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)

	dashed_arrow(&h.gtx, {0, 0}, {0, 100}, ops.Color{0, 0, 0, 255}, 2, 8, 6)
	testing.expect(t, testutil.count_ops(h.scene.ops[:], ops.Stroke) > 1)
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Fill), 1) // the head
}
