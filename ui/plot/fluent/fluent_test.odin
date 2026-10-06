package plot_fluent

import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/fluent"
import "jm:ui/ops"
import "jm:ui/plot"

// The palette's promises in each colour theme, measured: see
// check_palette. Fluent's BorderActive shades fall outside the lightness
// band plot_primer's test holds Primer's data hues to, so the band is not
// asked of them; contrast and separation are.
@(test)
test_the_palette_is_safe_in_every_colour_theme :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	for theme in fluent.Theme {
		if theme == .High_Contrast {
			continue
		}
		s := fluent.theme_scheme(theme)
		st := style_for(&gtx, theme, &s)
		colors: [plot.MAX_SLOTS]ops.Color
		for l, i in st.series {
			colors[i] = l.color
		}
		r := plot.check_palette(colors[:], st.background)
		name := NAMES[theme]
		testing.expectf(
			t,
			r.min_contrast >= plot.CONTRAST_MIN,
			"%s: a slot at %.2f:1",
			name,
			r.min_contrast,
		)
		testing.expectf(
			t,
			r.min_chroma >= plot.CHROMA_FLOOR,
			"%s: a slot reads grey, chroma %.3f",
			name,
			r.min_chroma,
		)
		testing.expectf(
			t,
			r.adjacent_cvd >= plot.CVD_TARGET,
			"%s: slots %d and %d %.1f apart under CVD",
			name,
			r.adjacent_at,
			r.adjacent_at + 1,
			r.adjacent_cvd,
		)
		testing.expectf(
			t,
			r.adjacent_normal >= plot.NORMAL_FLOOR,
			"%s: neighbours %.1f apart",
			name,
			r.adjacent_normal,
		)
		testing.expectf(
			t,
			r.prefix_cvd >= plot.CVD_TARGET,
			"%s: the first three %.1f apart under CVD",
			name,
			r.prefix_cvd,
		)
		for i in 0 ..< 5 {
			for j in i + 1 ..< 5 {
				d := plot.delta_e(colors[i], colors[j])
				testing.expectf(
					t,
					d >= plot.NORMAL_FLOOR,
					"%s: slots %d and %d, among the first five, are %.1f apart",
					name,
					i,
					j,
					d,
				)
			}
		}
	}
}

// High contrast has three colours, so a slot is its colour and dash
// together: no two slots share both, neighbours always differ in one the
// eye can tell, and every one stands out from the background.
@(test)
test_high_contrast_tells_series_by_shape :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	s := fluent.theme_scheme(.High_Contrast)
	st := style_for(&gtx, .High_Contrast, &s)
	for a, i in st.series {
		testing.expectf(
			t,
			design.wcag_ratio(a.color, st.background) >= 7,
			"slot %d at %.2f:1",
			i,
			design.wcag_ratio(a.color, st.background),
		)
		for b, j in st.series[i + 1:] {
			testing.expectf(
				t,
				a.color != b.color || a.dash != b.dash,
				"slots %d and %d look alike",
				i,
				i + 1 + j,
			)
		}
		if i + 1 < plot.MAX_SLOTS {
			b := st.series[i + 1]
			apart :=
				plot.delta_e(a.color, b.color) >= plot.NORMAL_FLOOR &&
				plot.cvd_distance(a.color, b.color) >= plot.CVD_TARGET
			testing.expectf(
				t,
				apart || a.dash != b.dash,
				"neighbours %d and %d differ in neither",
				i,
				i + 1,
			)
			testing.expect(t, a.marker != b.marker, "neighbours share a marker")
		}
	}
}

@(test)
test_chart_text_is_legible_in_every_theme :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	for theme in fluent.Theme {
		s := fluent.theme_scheme(theme)
		st := style_for(&gtx, theme, &s)
		pairs := [?][2]ops.Color {
			{st.text, st.background},
			{st.muted, st.background},
			{st.tooltip.text, st.tooltip.background},
			{st.tooltip.muted, st.tooltip.background},
		}
		for p, i in pairs {
			r := design.wcag_ratio(p[0], p[1])
			testing.expectf(t, r >= 4.5, "%s: text pair %d at %.2f:1", NAMES[theme], i, r)
		}
	}
}

// NAMES is the themes' names, indexable at run time.
@(private = "file", rodata)
NAMES := fluent.THEME_NAMES

// High contrast is drawn from system colours, not from SLOTS, because the
// theme gives every palette hue the same colour: SLOTS would draw eight
// series alike.
@(test)
test_high_contrast_binds_the_palette_to_one_colour :: proc(t: ^testing.T) {
	s := fluent.theme_scheme(.High_Contrast)
	slots := SLOTS
	for role in slots[1:] {
		testing.expect_value(t, s[role], s[slots[0]])
	}
}
