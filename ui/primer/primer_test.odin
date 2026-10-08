package primer

import "core:testing"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

@(test)
test_schemes_come_from_the_tokens :: proc(t: ^testing.T) {
	testing.expect_value(t, theme_scheme(.Light)[.Fg_Color_Default], ops.rgba(0x1f2328ff))
	testing.expect_value(t, theme_scheme(.Light)[.Button_Primary_Bg_Color_Rest], ops.rgba(0x1f883dff))
	// Colorblind themes draw the primary button blue (foundations themes.rules).
	testing.expect_value(t, theme_scheme(.Light_Colorblind)[.Button_Primary_Bg_Color_Rest], ops.rgba(0x0969daff))
	testing.expect_value(t, theme_scheme(.Dark_Dimmed)[.Button_Primary_Bg_Color_Rest], ops.rgba(0x347d39ff))
	// An alpha colour keeps its alpha.
	testing.expect_value(t, theme_scheme(.Light)[.Selection_Bg_Color], ops.rgba(0x0969da33))
	testing.expect_value(t, scheme()[.Fg_Color_Default], ops.rgba(0x1f2328ff)) // light until use
}

// DIMMED_BELOW_AA are the pairings Primer's dark dimmed theme, its
// softer dark, binds under the AA ratios AXIOMS ask: accent and link text
// on the page at 4.33:1, the focus outline at 2.96:1, the semantic tints
// at 3.3 to 4.4:1. Every other theme meets every axiom.
@(private = "file")
DIMMED_BELOW_AA := [][2]tok.Role {
	{.Fg_Color_Accent, .Bg_Color_Default},
	{.Fg_Color_Link, .Bg_Color_Default},
	{.Fg_Color_Accent, .Bg_Color_Accent_Muted},
	{.Fg_Color_Success, .Bg_Color_Success_Muted},
	{.Fg_Color_Danger, .Bg_Color_Danger_Muted},
	{.Fg_Color_Attention, .Bg_Color_Attention_Muted},
	{.Fg_Color_Done, .Bg_Color_Done_Muted},
	{.Focus_Outline_Color, .Bg_Color_Default},
	{.Button_Danger_Fg_Color_Rest, .Button_Danger_Bg_Color_Rest},
}

@(test)
test_every_theme_satisfies_the_colour_axioms :: proc(t: ^testing.T) {
	v := design.check(bindings(), AXIOMS, context.temp_allocator)
	defer free_all(context.temp_allocator)
	dimmed := 0
	for x in v {
		known := false
		for p in DIMMED_BELOW_AA {
			known ||= x.ctx == .Dark_Dimmed && x.axiom.a == p[0] && x.axiom.b == p[1]
		}
		if known {
			dimmed += 1
			continue
		}
		testing.expectf(t, false, "%v: %v %v vs %v: got %.2f, want %v", x.ctx, x.axiom.rel, x.axiom.a, x.axiom.b, x.got, x.axiom.k)
	}
	testing.expect_value(t, dimmed, len(DIMMED_BELOW_AA)) // each one still fails: a fix upstream shows here
}

@(test)
test_every_theme_maps_to_a_valid_base_theme :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for th in Theme {
		s := theme_scheme(th)
		bt := base_theme(&s, mode_of(th))
		v := design.check(bt.colors, base.AXIOMS, context.temp_allocator)
		testing.expect_value(t, len(v), 0)
		for x in v {
			testing.expectf(t, false, "%v as %v: %v %v vs %v: got %.2f, want %v", th, x.ctx, x.axiom.rel, x.axiom.a, x.axiom.b, x.got, x.axiom.k)
		}
		testing.expect_value(t, bt.colors.bind[mode_of(th)][.Bg], s[.Bg_Color_Default])
	}
}

@(test)
test_check_catches_a_theme_that_loses_a_pair :: proc(t: ^testing.T) {
	th := bindings()
	th.bind[.Dark_Tritanopia][.Fg_Color_On_Emphasis] = th.bind[.Dark_Tritanopia][.Bg_Color_Accent_Emphasis]
	v := design.check(th, AXIOMS, context.temp_allocator)
	defer free_all(context.temp_allocator)
	// onEmphasis text pairs with five emphasis fills, all in the one theme;
	// dark dimmed's known shortfalls are the only others.
	broken := 0
	for x in v {
		if x.ctx == .Dark_Dimmed {
			continue
		}
		testing.expect_value(t, x.ctx, Theme.Dark_Tritanopia)
		testing.expect_value(t, x.axiom.a, tok.Role.Fg_Color_On_Emphasis)
		broken += 1
	}
	testing.expect(t, broken >= 1)
}

@(test)
test_mode_of_reads_every_dark_family_as_dark :: proc(t: ^testing.T) {
	for th in Theme {
		dark := theme_scheme(th)[.Bg_Color_Default][0] < 128
		testing.expectf(t, (mode_of(th) == .Dark) == dark, "%v", th)
	}
}

@(test)
test_every_icon_parses_whole_at_every_height_it_has :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	for i in Icon {
		for paths, h in ([3]design.Icon_Paths{ICON_12[i], ICON_16[i], ICON_24[i]}) {
			for d, n in paths.d {
				if d == "" {
					continue
				}
				p, ok := design.parse_svg_path(d, context.temp_allocator)
				testing.expectf(t, ok && len(p.points) > 0, "%v at height %d, path %d, stopped after %d points", i, h, n, len(p.points))
			}
		}
	}
}

// A path that starts with a relative moveto starts from the origin (SVG
// 1.1 paths, 8.3.2), so every point of every icon lies in its own box; a
// path read on from the end of the one before it would land outside
// (agent's prompt did, when an icon's paths were joined into one).
@(test)
test_every_icon_stays_inside_its_box :: proc(t: ^testing.T) {
	for i in Icon {
		for size in ([]f32{12, 16, 24}) {
			paths, h := icon_paths(i, size)
			w := icon_width(i, h)
			for p in paths {
				if q, out := point_outside(p, w, h); out {
					testing.expectf(t, false, "%v at %v: point %v outside %vx%v", i, h, q, w, h)
				}
			}
		}
	}
}

// point_outside is a point on p, its curves sampled rather than their
// control points (which may stand off an arc), more than a quarter unit
// outside the w by h box.
@(private = "file")
point_outside :: proc(p: ops.Path, w, h: f32) -> (ops.Point, bool) {
	outside :: proc(q: ops.Point, w, h: f32) -> bool {
		return q.x < -0.25 || q.y < -0.25 || q.x > w + 0.25 || q.y > h + 0.25
	}
	at, cur, start := 0, ops.Point{}, ops.Point{}
	for v in p.verbs {
		switch v {
		case .Move, .Line:
			cur = p.points[at]
			at += 1
			if v == .Move {
				start = cur
			}
			if outside(cur, w, h) {
				return cur, true
			}
		case .Cubic:
			c1, c2, end := p.points[at], p.points[at + 1], p.points[at + 2]
			at += 3
			for n in 1 ..= 8 {
				s := f32(n) / 8
				r := 1 - s
				q := r * r * r * cur + 3 * r * r * s * c1 + 3 * r * s * s * c2 + s * s * s * end
				if outside(q, w, h) {
					return q, true
				}
			}
			cur = end
		case .Close:
			cur = start
		}
	}
	return {}, false
}

@(test)
test_an_icon_draws_from_the_largest_natural_height_that_fits :: proc(t: ^testing.T) {
	// Alert_Fill has 12, 16 and 24px designs; Accessibility only 16 and 24.
	for c in ([]struct {
			i:          Icon,
			size, want: f32,
		}{{.Alert_Fill, 12, 12}, {.Alert_Fill, 14, 12}, {.Alert_Fill, 16, 16}, {.Alert_Fill, 20, 16}, {.Alert_Fill, 32, 24}, {.Accessibility, 12, 16}}) {
		_, h := icon_paths(c.i, c.size)
		testing.expectf(t, h == c.want, "%v at %v: drawn from %v, want %v", c.i, c.size, h, c.want)
	}
	testing.expect_value(t, icon_width(.Logo_Gist, 16), f32(25))
	testing.expect_value(t, icon_width(.Logo_Gist, 32), f32(32 * 38.0 / 24))
	testing.expect_value(t, icon_width(.X, 20), f32(20))
	p, _ := icon_paths(.None, 16)
	testing.expect_value(t, len(p), 0)
}

@(test)
test_a_press_snaps_while_other_changes_fade :: proc(t: ^testing.T) {
	red, blue := ops.Color{255, 0, 0, 255}, ops.Color{0, 0, 255, 255}
	gtx: ui.Ctx
	gtx.dt = 0.04
	f: design.Fades
	c: Control
	c.fades = &f
	c.state = .Hovered
	testing.expect_value(t, blend(&gtx, c, 0, red), red)
	mid := blend(&gtx, c, 0, blue) // 40 of 80ms
	testing.expect(t, mid != red && mid != blue)
	c.state = .Pressed
	testing.expect_value(t, blend(&gtx, c, 0, red), red)
}

@(test)
test_a_shadow_paints_its_layers_last_first_in_the_active_theme :: proc(t: ^testing.T) {
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	gtx := ui.Ctx{scene = &sc, allocator = context.temp_allocator}
	defer free_all(context.temp_allocator)
	s := theme_scheme(.Dark)
	use(&s, .Dark)
	defer use(nil)
	paint_shadow(&gtx, {{10, 10, 100, 40}, 6}, tok.SHADOW_RESTING_SMALL)
	shadows := make([dynamic]ops.Shadow, context.temp_allocator)
	for op in sc.ops {
		if sh, ok := op.(ops.Shadow); ok {
			append(&shadows, sh)
		}
	}
	dark := tok.SHADOW_RESTING_SMALL[.Dark]
	testing.expect_value(t, len(shadows), dark.count)
	// The last listed layer is painted first, under the rest, in dark's
	// geometry: --shadow-resting-small's second layer blurs 3px in dark.
	testing.expect_value(t, shadows[0].blur, dark.layers[1].blur)
	testing.expect_value(t, shadows[0].blur, f32(3))
	testing.expect_value(t, shadows[0].color, s[dark.layers[1].color])
}

@(private = "file")
Custom_Model :: struct {
	icon: Icon,
}

@(private = "file")
custom_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Custom_Model)(user)
	button(gtx, "Coins", leading = m.icon)
}

@(test)
test_a_registered_icon_draws_wherever_an_icon_does :: proc(t: ^testing.T) {
	square := design.Icon_Paths {
		d        = {0 = "M0 0h16v16H0Z M4 4v8h8V4Z", 1 = "M6 6h4v4H6Z"},
		even_odd = {0},
	}
	i := register_icon(square)
	testing.expect(t, u16(i) > u16(max(Icon)), "past the octicons")
	paths, height := icon_paths(i, 32)
	testing.expect_value(t, len(paths), 2)
	testing.expect_value(t, height, 16)
	testing.expect_value(t, paths[0].rule, ops.Fill_Rule.Even_Odd)
	testing.expect_value(t, icon_width(i, 32), 32)
	wide := register_icon({d = {0 = "M0 0h24v12H0Z"}}, 12, 24)
	testing.expect(t, wide != i)
	testing.expect_value(t, icon_width(wide, 12), 24)
	// As a button's leading icon: its two paths are filled.
	m := Custom_Model{icon = i}
	p: ui.Probe
	ui.probe_init(&p, custom_view, &m, {200, 60}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	path_fills := 0
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if _, is_path := f.shape.(ops.Path_Ref); is_path {
				path_fills += 1
			}
		}
	}
	testing.expect_value(t, path_fills, 2)
}
