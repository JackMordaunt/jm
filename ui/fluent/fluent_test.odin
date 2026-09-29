package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

@(test)
test_schemes_come_from_the_tokens :: proc(t: ^testing.T) {
	testing.expect_value(t, theme_scheme(.Web_Light)[.Brand_Background], hex(0x0f6cbdff))
	testing.expect_value(t, theme_scheme(.Web_Dark)[.Brand_Background], hex(0x115ea3ff))
	testing.expect_value(t, theme_scheme(.Teams_Light)[.Brand_Background], hex(0x5b5fc7ff))
	testing.expect_value(t, theme_scheme(.High_Contrast)[.Stroke_Focus2], hex(0x1aebffff))
	// An alpha colour keeps its alpha: the subtle background is nothing at rest.
	testing.expect_value(t, theme_scheme(.Web_Light)[.Subtle_Background], ops.Color{0, 0, 0, 0})
	testing.expect_value(t, scheme()[.Neutral_Background1], hex(0xffffffff)) // web light until use
}

@(test)
test_every_theme_satisfies_the_colour_axioms :: proc(t: ^testing.T) {
	v := design.check(bindings(), AXIOMS, context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, len(v), 0)
	for x in v {
		testing.expectf(t, false, "%v: %v %v vs %v: got %.2f, want %v", x.ctx, x.axiom.rel, x.axiom.a, x.axiom.b, x.got, x.axiom.k)
	}
}

@(test)
test_every_theme_maps_to_a_valid_base_theme :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for th in Theme {
		s := theme_scheme(th)
		bt := base_theme(&s, mode_of(th))
		// Only the theme's own mode is bound; the other keeps base's palette.
		v := design.check(bt.colors, base.AXIOMS, context.temp_allocator)
		testing.expect_value(t, len(v), 0)
		for x in v {
			testing.expectf(t, false, "%v as %v: %v %v vs %v: got %.2f, want %v", th, x.ctx, x.axiom.rel, x.axiom.a, x.axiom.b, x.got, x.axiom.k)
		}
		testing.expect_value(t, bt.colors.bind[mode_of(th)][.Surface], s[.Neutral_Background1])
		testing.expect_value(t, bt.radius, tok.BORDER_RADIUS_MEDIUM)
	}
}

@(test)
test_check_catches_a_theme_that_loses_a_pair :: proc(t: ^testing.T) {
	th := bindings()
	th.bind[.Teams_Dark][.Neutral_Foreground_On_Brand] = th.bind[.Teams_Dark][.Brand_Background]
	v := design.check(th, AXIOMS, context.temp_allocator)
	defer free_all(context.temp_allocator)
	// On-brand text pairs with the brand background at rest, hovered and
	// pressed: three axioms, all in the one theme.
	testing.expect_value(t, len(v), 3)
	for x in v {
		testing.expect_value(t, x.ctx, Theme.Teams_Dark)
		testing.expect_value(t, x.axiom.a, tok.Role.Neutral_Foreground_On_Brand)
	}
}

@(test)
test_role_for_picks_the_state_token_by_priority :: proc(t: ^testing.T) {
	s := State_Roles{.Neutral_Background1, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background_Disabled}
	c: Control
	testing.expect_value(t, role_for(s, c), tok.Role.Neutral_Background1)
	c.hovered = true
	c.state = design.effective_state(c)
	testing.expect_value(t, role_for(s, c), tok.Role.Neutral_Background1_Hover)
	c.pressed = true // pressed wins over hover
	c.state = design.effective_state(c)
	testing.expect_value(t, role_for(s, c), tok.Role.Neutral_Background1_Pressed)
	c.focused = true // focus has no token of its own: pressed still
	c.state = design.effective_state(c)
	testing.expect_value(t, role_for(s, c), tok.Role.Neutral_Background1_Pressed)
	c.pressed, c.hovered = false, false // focused alone reads rest
	c.state = design.effective_state(c)
	testing.expect_value(t, role_for(s, c), tok.Role.Neutral_Background1)
	c.disabled = true
	c.state = design.effective_state(c)
	testing.expect_value(t, role_for(s, c), tok.Role.Neutral_Background_Disabled)
	testing.expect_value(t, color_for(s, c), scheme()[.Neutral_Background_Disabled])
}

@(test)
test_blend_eases_a_live_colour_and_snaps_a_forced_one :: proc(t: ^testing.T) {
	red, blue := ops.Color{255, 0, 0, 255}, ops.Color{0, 0, 255, 255}
	gtx: ui.Ctx
	gtx.dt = 0.05
	forced: Control
	testing.expect_value(t, blend(&gtx, forced, 0, red), red)
	testing.expect_value(t, blend(&gtx, forced, 0, blue), blue)

	f: Fades
	live: Control
	live.fades = &f
	testing.expect_value(t, blend(&gtx, live, 0, red), red) // the first frame has nothing to ease from
	mid := blend(&gtx, live, 0, blue) // 50ms into DURATION_FASTER's 100
	testing.expect(t, mid != red && mid != blue)
	testing.expect_value(t, mid, ops.mix(red, blue, design.bezier_ease(tok.CURVE_EASY_EASE, 0.5)))
	testing.expect(t, gtx.wants_frame)
	testing.expect_value(t, blend(&gtx, live, 0, blue), blue)
	// Slot 1 is its own transition, untouched by slot 0's.
	testing.expect_value(t, blend(&gtx, live, 1, blue), blue)
}

@(test)
test_font_for_picks_the_nearest_weight :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	gtx.font = 7
	testing.expect_value(t, font_for(&gtx, 600), ops.Font_Id(7)) // no faces set: the frame font
	use_fonts({1, 2, 3})
	defer loaded = false
	testing.expect_value(t, font_for(&gtx, tok.FONT_WEIGHT_REGULAR), ops.Font_Id(1))
	testing.expect_value(t, font_for(&gtx, tok.FONT_WEIGHT_SEMIBOLD), ops.Font_Id(2))
	testing.expect_value(t, font_for(&gtx, tok.FONT_WEIGHT_BOLD), ops.Font_Id(3))
	testing.expect_value(t, font_for(&gtx, tok.FONT_WEIGHT_MEDIUM), ops.Font_Id(2)) // a tie goes to the heavier
	testing.expect_value(t, control_style(.Medium, tok.FONT_WEIGHT_SEMIBOLD), tok.Type_Style{600, 14, 20, 0})
}

@(test)
test_radius_makes_circular_a_pill :: proc(t: ^testing.T) {
	testing.expect_value(t, radius(tok.BORDER_RADIUS_CIRCULAR, {0, 0, 96, 32}), f32(16))
	testing.expect_value(t, radius(tok.BORDER_RADIUS_MEDIUM, {0, 0, 96, 32}), f32(4))
}
