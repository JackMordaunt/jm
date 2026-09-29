package design

import "core:testing"
import "jm:ui/ops"

@(private = "file")
Role :: enum u8 {
	Surface,
	On_Surface,
	Primary,
	On_Primary,
}

@(private = "file")
Mode :: enum u8 {
	Light,
	Dark,
}

@(private = "file")
WHITE :: ops.Color{255, 255, 255, 255}
@(private = "file")
BLACK :: ops.Color{0, 0, 0, 255}

@(private = "file")
expect_near :: proc(t: ^testing.T, got, want, tol: f32, loc := #caller_location) {
	testing.expectf(t, abs(got - want) <= tol, "got %v, want %v ± %v", got, want, tol, loc = loc)
}

@(test)
test_apca_matches_the_published_reference_pairs :: proc(t: ^testing.T) {
	// The APCA-W3 readme's example pairs (0.0.98G), text on background.
	hex :: proc(v: u32) -> ops.Color {return {u8(v >> 16), u8(v >> 8), u8(v), 255}}
	expect_near(t, apca(hex(0x888888), hex(0xffffff)), 63.06, 0.05)
	expect_near(t, apca(hex(0xffffff), hex(0x888888)), 68.54, 0.05)
	expect_near(t, apca(hex(0x000000), hex(0xaaaaaa)), 58.15, 0.05)
	expect_near(t, apca(hex(0xaaaaaa), hex(0x000000)), 56.24, 0.05)
	expect_near(t, apca(hex(0x112233), hex(0xddeeff)), 91.67, 0.05)
	expect_near(t, apca(hex(0xddeeff), hex(0x112233)), 93.07, 0.05)
	expect_near(t, apca(hex(0x112233), hex(0x444444)), 8.32, 0.05)
	expect_near(t, apca(hex(0x444444), hex(0x112233)), 7.53, 0.05)
	testing.expect_value(t, apca(WHITE, WHITE), 0)
}

@(test)
test_wcag_ratio_is_symmetric_and_spans_1_to_21 :: proc(t: ^testing.T) {
	expect_near(t, wcag_ratio(BLACK, WHITE), 21, 0.01)
	expect_near(t, wcag_ratio(WHITE, BLACK), 21, 0.01)
	expect_near(t, wcag_ratio(WHITE, WHITE), 1, 0.001)
	testing.expect(t, wcag_ratio(BLACK, WHITE) > wcag_ratio(BLACK, {128, 128, 128, 255}))
}

@(test)
test_oklch_lightness_and_hue :: proc(t: ^testing.T) {
	expect_near(t, oklch(WHITE).l, 1, 0.001)
	expect_near(t, oklch(BLACK).l, 0, 0.001)
	red := oklch({255, 0, 0, 255})
	expect_near(t, red.h, 29.2, 0.5)
	expect_near(t, red.c, 0.2577, 0.002)
	testing.expect_value(t, hue_dist(350, 10), 20)
	testing.expect_value(t, hue_dist(10, 350), 20)
}

@(test)
test_check_reports_only_the_failing_context :: proc(t: ^testing.T) {
	th: Theme(Role, Mode)
	th.bind[.Light] = {.Surface = WHITE, .On_Surface = BLACK, .Primary = {0x65, 0x50, 0xA4, 255}, .On_Primary = {0xEA, 0xDD, 0xFF, 255}}
	th.bind[.Dark] = {.Surface = BLACK, .On_Surface = WHITE, .Primary = {0xD0, 0xBC, 0xFF, 255}, .On_Primary = {0xD0, 0xBC, 0xFF, 255}} // on-primary lost
	axioms := []Axiom(Role){{.Contrast_Min, .On_Surface, .Surface, 60}, {.Ratio_Min, .On_Primary, .Primary, 4.5}, {.Hue_Within, .Primary, .On_Primary, 30}}
	v := check(th, axioms, context.temp_allocator)
	testing.expect_value(t, len(v), 1)
	if len(v) == 1 {
		testing.expect_value(t, v[0].ctx, Mode.Dark)
		testing.expect_value(t, v[0].axiom.rel, Relation.Ratio_Min)
		expect_near(t, v[0].got, 1, 0.001)
	}
}

@(test)
test_measure_lightness_relations :: proc(t: ^testing.T) {
	got, ok := measure(WHITE, BLACK, .Lighter_By, 0.5)
	testing.expect(t, ok)
	expect_near(t, got, 1, 0.001)
	_, ok = measure(WHITE, BLACK, .Darker_By, 0.5)
	testing.expect(t, !ok)
	got, ok = measure(WHITE, WHITE, .Same, 0)
	testing.expect(t, ok)
	testing.expect_value(t, got, 0)
	got, ok = measure(WHITE, BLACK, .Same, 0)
	testing.expect(t, !ok)
	testing.expect_value(t, got, 1)
}

@(test)
test_font_for_picks_the_nearest_weight_heavier_on_ties :: proc(t: ^testing.T) {
	faces := []Font_Face{{400, 1}, {500, 2}, {700, 3}}
	testing.expect_value(t, font_for(nil, 500, 7), ops.Font_Id(7))
	testing.expect_value(t, font_for(faces, 400, 7), ops.Font_Id(1))
	testing.expect_value(t, font_for(faces, 550, 7), ops.Font_Id(2))
	testing.expect_value(t, font_for(faces, 600, 7), ops.Font_Id(3))
	testing.expect_value(t, font_for(faces, 300, 7), ops.Font_Id(1))
	testing.expect_value(t, font_for(faces, 900, 7), ops.Font_Id(3))
}

@(test)
test_bezier_ease_is_identity_for_linear :: proc(t: ^testing.T) {
	lin := Bezier{0, 0, 1, 1}
	for x in ([]f32{0, 0.25, 0.5, 0.75, 1}) {
		expect_near(t, bezier_ease(lin, x), x, 0.001)
	}
	// cubic-bezier(0.42, 0, 0.58, 1), CSS Easing Functions Level 1's
	// ease-in-out: slow at both ends,
	// symmetric about the midpoint. Values from solving the curve at
	// double precision.
	eio := Bezier{0.42, 0, 0.58, 1}
	testing.expect(t, bezier_ease(eio, 0.25) < 0.25)
	expect_near(t, bezier_ease(eio, 0.25), 0.1292, 0.001)
	expect_near(t, bezier_ease(eio, 0.5), 0.5, 0.001)
	expect_near(t, bezier_ease(eio, 0.75), 0.8708, 0.001)
	// Material Design 2's standard curve, cubic-bezier(0.4, 0, 0.2, 1),
	// is past halfway at the midpoint.
	expect_near(t, bezier_ease({0.4, 0, 0.2, 1}, 0.5), 0.7756, 0.001)
}

@(test)
test_effective_state_orders_the_flags :: proc(t: ^testing.T) {
	testing.expect_value(t, effective_state({}), Interaction.Enabled)
	testing.expect_value(t, effective_state({hovered = true}), Interaction.Hovered)
	testing.expect_value(t, effective_state({hovered = true, focused = true}), Interaction.Focused)
	testing.expect_value(t, effective_state({focused = true, pressed = true}), Interaction.Pressed)
	testing.expect_value(t, effective_state({pressed = true, disabled = true}), Interaction.Disabled)
}

@(test)
test_corners_lerp_and_grow :: proc(t: ^testing.T) {
	k := lerp_corners({0, 0, 0, 0}, {8, 8, 8, 8}, 0.5)
	testing.expect_value(t, k, Corners{4, 4, 4, 4})
	testing.expect_value(t, grow_corners({2, 0, 2, 0}, -1), Corners{1, 0, 1, 0})
	testing.expect_value(t, touch_target({10, 10, 20, 48}, 48), ops.Rect{-4, 10, 48, 48})
}
