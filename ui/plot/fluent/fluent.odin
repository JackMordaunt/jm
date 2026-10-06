/*
Package plot_fluent is jm:ui/plot in Fluent 2: a Plot_Style built from a
Fluent theme, so a chart sits among Fluent's components in any of its five
themes.

	style := plot_fluent.style(gtx, .Web_Dark)
	plot.bar_chart(gtx, &chart, &style)

The series colours are Fluent's palette tokens, each hue's BorderActive
shade (colorPalette<Hue>BorderActive), eight of them in an order chosen by
computation: every slot clears 3:1 against the theme's background,
neighbours stay apart under protanopia and deuteranopia and for full
colour vision, and the first five are apart pair by pair for full colour
vision. High contrast gives every palette token the same colour, so
there the series take CanvasText, LinkText and Highlight in turn, each
round with its own dash, and a marker per slot: identity is carried by
shape there, not by hue. plot_fluent_test checks all of it.
*/
package plot_fluent

import "jm:ui"
import "jm:ui/fluent"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"
import "jm:ui/plot"

// SLOTS are the palette roles the series take, in slot order: blue,
// cranberry, navy, brass, lilac, dark green, berry, dark orange.
SLOTS :: [plot.MAX_SLOTS]tok.Role {
	.Palette_Blue_Border_Active,
	.Palette_Cranberry_Border_Active,
	.Palette_Navy_Border_Active,
	.Palette_Brass_Border_Active,
	.Palette_Lilac_Border_Active,
	.Palette_Dark_Green_Border_Active,
	.Palette_Berry_Border_Active,
	.Palette_Dark_Orange_Border_Active,
}

// HIGH_CONTRAST_SLOTS are the system colours high contrast's series take
// in turn: CanvasText, LinkText and Highlight.
HIGH_CONTRAST_SLOTS :: [3]tok.Role {
	.Neutral_Foreground1,
	.Brand_Foreground_Link,
	.Compound_Brand_Foreground1,
}

// HIGH_CONTRAST_DASHES are each round of HIGH_CONTRAST_SLOTS' dashes:
// solid, then dashed, then dotted.
HIGH_CONTRAST_DASHES :: [3][2]f32{{0, 0}, {7, 4}, {2, 3}}

// style is a Plot_Style for theme, in the fonts fluent.use_fonts gave or
// the frame's.
style :: proc(gtx: ^ui.Ctx, theme: fluent.Theme) -> plot.Plot_Style {
	s := fluent.theme_scheme(theme)
	return style_for(gtx, theme, &s)
}

// style_for is style with the scheme s given.
style_for :: proc(gtx: ^ui.Ctx, theme: fluent.Theme, s: ^fluent.Scheme) -> (st: plot.Plot_Style) {
	if theme == .High_Contrast {
		hc := HIGH_CONTRAST_SLOTS
		dashes := HIGH_CONTRAST_DASHES
		for i in 0 ..< plot.MAX_SLOTS {
			st.series[i] = {
				color  = s[hc[i % 3]],
				dash   = dashes[i / 3 % 3],
				marker = plot.Marker(i % len(plot.Marker)),
			}
		}
	} else {
		for role, i in SLOTS {
			st.series[i] = {
				color = s[role],
			}
		}
	}
	st.slots = plot.MAX_SLOTS
	st.background, st.text, st.muted =
		s[.Neutral_Background1], s[.Neutral_Foreground1], s[.Neutral_Foreground3]
	st.grid, st.axis = s[.Neutral_Stroke2], s[.Neutral_Stroke_Accessible]
	st.crosshair, st.focus, st.error =
		s[.Neutral_Foreground3], s[.Stroke_Focus2], s[.Palette_Red_Foreground1]
	st.hover, st.other = ops.with_alpha(s[.Neutral_Foreground1], 0.06), s[.Neutral_Foreground3]
	st.tooltip = {
		background = s[.Neutral_Background1],
		border     = s[.Neutral_Stroke2],
		text       = s[.Neutral_Foreground1],
		muted      = s[.Neutral_Foreground3],
		shadow     = s[.Neutral_Shadow_Key],
		radius     = tok.BORDER_RADIUS_MEDIUM,
	}
	plot.set_sizes(&st)
	st.font = fluent.font_for(gtx, 400)
	st.font_strong = fluent.font_for(gtx, 600)
	return
}
