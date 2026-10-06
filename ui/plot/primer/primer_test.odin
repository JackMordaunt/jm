package plot_primer

import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import "jm:ui/plot"
import "jm:ui/primer"

// The palette's promises, measured in every one of Primer's themes rather
// than chosen by eye: see check_palette for what each measure is.
@(test)
test_the_palette_is_safe_in_every_theme :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	for theme in primer.Theme {
		s := primer.theme_scheme(theme)
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
			"%s: a slot at %.2f:1 on the page",
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
			"%s: slots %d and %d are %.1f apart under CVD",
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
			"%s: the first three are %.1f apart under CVD",
			name,
			r.prefix_cvd,
		)
		dark := primer.mode_of(theme) == .Dark
		band := [2]f64{0.48, 0.67} if dark else {0.43, 0.77}
		testing.expectf(
			t,
			r.lightness[0] >= band[0] && r.lightness[1] <= band[1],
			"%s: lightness %v outside %v",
			name,
			r.lightness,
			band,
		)
		for i in 0 ..< 4 {
			for j in i + 1 ..< 4 {
				d := plot.delta_e(colors[i], colors[j])
				testing.expectf(
					t,
					d >= plot.NORMAL_FLOOR,
					"%s: slots %d and %d, among the first four, are %.1f apart",
					name,
					i,
					j,
					d,
				)
			}
		}
	}
}

// Text on the chart is read, so it is held to WCAG's 4.5:1 for text.
@(test)
test_chart_text_is_legible_in_every_theme :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	for theme in primer.Theme {
		s := primer.theme_scheme(theme)
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

// The themes a reader picks for help with colour give each slot a shape
// too; tritanopia is not what the order was chosen for, so there the
// draw_marker is what keeps neighbours apart.
@(test)
test_assisted_themes_mark_neighbours_apart :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	for theme in primer.Theme {
		s := primer.theme_scheme(theme)
		st := style_for(&gtx, theme, &s)
		for i in 0 ..< plot.MAX_SLOTS - 1 {
			a, b := st.series[i], st.series[i + 1]
			if assisted(theme) {
				testing.expectf(
					t,
					a.marker != b.marker,
					"%s: slots %d and %d share a marker",
					NAMES[theme],
					i,
					i + 1,
				)
			} else {
				testing.expect_value(t, a.marker, plot.Marker.Circle)
			}
		}
	}
}

// NAMES is the themes' names, indexable at run time.
@(private = "file", rodata)
NAMES := primer.THEME_NAMES

// The tooltip sits on the page's colour because Primer's overlay colour
// fails muted text in dark dimmed; this keeps that reason true.
@(test)
test_the_overlay_would_fail_muted_text_in_dark_dimmed :: proc(t: ^testing.T) {
	s := primer.theme_scheme(.Dark_Dimmed)
	r := design.wcag_ratio(s[.Fg_Color_Muted], s[.Overlay_Bg_Color])
	testing.expectf(t, r < 4.5, "muted text on the overlay is %.2f:1; the tooltip could use it", r)
}

// Gridlines carry no data, so in every theme, high contrast included,
// they stay visible yet below GRID_MAX against the plot, and every series
// stands out from them as it does from the background.
@(test)
test_gridlines_recede_behind_the_series :: proc(t: ^testing.T) {
	gtx: ui.Ctx
	for theme in primer.Theme {
		s := primer.theme_scheme(theme)
		st := style_for(&gtx, theme, &s)
		g := design.wcag_ratio(st.grid, st.background)
		testing.expectf(t, g >= 1.2 && g <= plot.GRID_MAX, "%s: grid at %.2f:1", NAMES[theme], g)
		for l, i in st.series {
			r := design.wcag_ratio(l.color, st.grid)
			testing.expectf(t, r >= 1.5, "%s: slot %d at %.2f:1 on a gridline", NAMES[theme], i, r)
		}
	}
}
