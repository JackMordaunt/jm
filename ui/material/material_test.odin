package material

import "core:testing"
import "jm:ui"
import tok "jm:ui/material/tokens"

@(test)
test_parse_svg_path_absolute_relative_and_quadratics :: proc(t: ^testing.T) {
	p, ok := parse_svg_path("M10 20h30v-10L0 0q10 0 10 10t10 10Z", context.temp_allocator)
	testing.expect(t, ok)
	defer free_all(context.temp_allocator)
	want := []ui.Path_Verb{.Move, .Line, .Line, .Line, .Cubic, .Cubic, .Close}
	testing.expect_value(t, len(p.verbs), len(want))
	for v, i in want {
		testing.expect_value(t, p.verbs[i], v)
	}
	testing.expect_value(t, p.points[1], ui.Point{40, 20}) // h30, relative
	testing.expect_value(t, p.points[2], ui.Point{40, 10}) // v-10
	testing.expect_value(t, p.points[3], ui.Point{0, 0}) // L, absolute
	// q10 0 10 10 from (0,0): control (10,0) raised to a cubic, end (10,10).
	testing.expect_value(t, p.points[6], ui.Point{10, 10})
	// t10 10 reflects that control through (10,10) and ends at (20,20).
	testing.expect_value(t, p.points[9], ui.Point{20, 20})
}

@(test)
test_parse_svg_path_implicit_lines_after_move :: proc(t: ^testing.T) {
	p, _ := parse_svg_path("m1 1 2 0 0 2z", context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, len(p.verbs), 4)
	testing.expect_value(t, p.verbs[1], ui.Path_Verb.Line)
	testing.expect_value(t, p.points[2], ui.Point{3, 3})
}

@(test)
test_every_icon_parses :: proc(t: ^testing.T) {
	for i in Icon {
		if i == .None {
			continue
		}
		data, _ := icon_svg(i)
		_, ok := parse_svg_path(data, context.temp_allocator)
		testing.expectf(t, ok, "%v has a command parse_svg_path does not handle", i)
		p, box := icon_path(i)
		testing.expectf(t, len(p.points) > 0, "%v parsed to nothing", i)
		for q in p.points {
			if q.x < -1 || q.y < -1 || q.x > box + 1 || q.y > box + 1 {
				testing.expectf(t, false, "%v has a point %v outside its %v box", i, q, box)
				break
			}
		}
	}
}

@(test)
test_parse_svg_path_stops_at_an_arc :: proc(t: ^testing.T) {
	p, ok := parse_svg_path("M3 4a5 5 0 0 1 10 0", context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect(t, !ok)
	// The moveto before the arc was kept; the arc is what stopped it.
	testing.expect_value(t, len(p.verbs), 1)
	testing.expect_value(t, p.points[0], ui.Point{3, 4})
}

@(test)
test_rounded_clamps_radii_to_half_the_short_side :: proc(t: ^testing.T) {
	ops: ui.Ops
	ui.ops_init(&ops, context.temp_allocator)
	defer free_all(context.temp_allocator)
	gtx := ui.Ctx{ops = &ops, allocator = context.temp_allocator}
	ref := rounded(&gtx, {0, 0, 100, 20}, corners_all(50))
	pts := ops.paths[ref.id].points
	// Every corner clamped to 10, half the 20px height.
	testing.expect_value(t, pts[0], ui.Point{10, 0})
	testing.expect_value(t, pts[1], ui.Point{90, 0})
	testing.expect_value(t, pts[5], ui.Point{100, 10})
	testing.expect_value(t, pts[8], ui.Point{90, 20})
	testing.expect_value(t, pts[9], ui.Point{10, 20})
	testing.expect_value(t, pts[12], ui.Point{0, 10})
}

@(test)
test_calendar_arithmetic :: proc(t: ^testing.T) {
	testing.expect_value(t, weekday({2026, 9, 1}), 2) // a Tuesday
	testing.expect_value(t, weekday({2000, 1, 1}), 6) // a Saturday
	testing.expect_value(t, weekday({2024, 2, 29}), 4) // a Thursday
	testing.expect_value(t, days_in_month(2024, 2), 29)
	testing.expect_value(t, days_in_month(1900, 2), 28) // century, not leap
	testing.expect_value(t, days_in_month(2000, 2), 29) // 400th year, leap
	testing.expect_value(t, days_in_month(2026, 9), 30)
}

@(test)
test_corners_resolve_full_to_half_the_short_side :: proc(t: ^testing.T) {
	r := ui.Rect{0, 0, 120, 40}
	testing.expect_value(t, corners(tok.SYS_SHAPE_CORNER_FULL, r), corners_all(20))
	testing.expect_value(t, corners(tok.SYS_SHAPE_CORNER_LARGE_TOP, r), Corners{16, 16, 0, 0})
	m := lerp_corners(corners_all(20), corners_all(8), 0.5)
	testing.expect_value(t, m, corners_all(14))
}

@(test)
test_schemes_and_springs_come_from_the_tokens :: proc(t: ^testing.T) {
	testing.expect_value(t, light_scheme()[.Primary], hex(0x6750a4))
	testing.expect_value(t, dark_scheme()[.Primary], hex(0xd0bcff))
	testing.expect_value(t, PRESSED_OPACITY, f32(0.1))
	defer use_motion(.Expressive)
	testing.expect_value(t, spring_params(.Fast_Spatial), ui.Spring_Params{0.6, 800})
	use_motion(.Standard)
	testing.expect_value(t, spring_params(.Fast_Spatial), ui.Spring_Params{0.9, 1400})
}

@(test)
test_font_for_picks_the_nearest_weight :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	th := ui.light_theme(7)
	gtx.theme = &th
	testing.expect_value(t, font_for(&gtx, 500), ui.Font_Id(7)) // no faces set: the theme font
	use_fonts({1, 2, 3})
	defer fonts = nil
	testing.expect_value(t, font_for(&gtx, 400), ui.Font_Id(1))
	testing.expect_value(t, font_for(&gtx, 500), ui.Font_Id(2))
	testing.expect_value(t, font_for(&gtx, 700), ui.Font_Id(3))
	testing.expect_value(t, font_for(&gtx, 300), ui.Font_Id(1))
	testing.expect_value(t, font_for(&gtx, 550), ui.Font_Id(2))
	testing.expect_value(t, font_for(&gtx, 900), ui.Font_Id(3))
}
