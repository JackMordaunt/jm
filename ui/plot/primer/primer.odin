/*
Package plot_primer is jm:ui/plot in GitHub's Primer: a Plot_Style built
from the active Primer theme, so a chart sits among Primer's components in
any of its fourteen themes.

	primer.use(&scheme, theme)
	style := plot_primer.style(gtx)
	plot.line_chart(gtx, &chart, &style)

The series colours are Primer's own data-visualisation tokens
(data.<hue>.color.emphasis in @primer/primitives 11.10.0's
src/tokens/functional/color/data-vis.json5, resolved per theme in its
dist/docs/functional/themes/<theme>.json), which the kit's token generator does
not emit, so they are written out here. Primer binds them once for its
light themes and once for its dark ones. Of its seventeen hues, eight are
used, in an order chosen by computation: every slot clears 3:1 against
each theme's page, neighbours stay apart under protanopia and
deuteranopia, the first three are apart pair by pair, and the first four
are apart for a reader with full colour vision. plot_primer_test checks
all of it in every theme.
*/
package plot_primer

import "jm:ui"
import "jm:ui/ops"
import "jm:ui/plot"
import "jm:ui/primer"
import tok "jm:ui/primer/tokens"

// HUES names the slots: Primer's data hues, in slot order.
HUES :: [plot.MAX_SLOTS]string{"blue", "coral", "pine", "plum", "lemon", "pink", "lime", "purple"}

// DATA_LIGHT and DATA_DARK are HUES' data.<hue>.color.emphasis values in
// Primer's light and dark themes.
DATA_LIGHT :: [plot.MAX_SLOTS]u32 {
	0x006edbff,
	0xd43511ff,
	0x167e53ff,
	0xa830e8ff,
	0x866e04ff,
	0xce2c85ff,
	0x527a29ff,
	0x894cebff,
}
DATA_DARK  :: [plot.MAX_SLOTS]u32 {
	0x0576ffff,
	0xe1430eff,
	0x18915eff,
	0xb643efff,
	0x977b0cff,
	0xd34591ff,
	0x5f892fff,
	0x975bf1ff,
}

// style is a Plot_Style for the active Primer theme, in its fonts.
style :: proc(gtx: ^ui.Ctx) -> plot.Plot_Style {
	return style_for(gtx, primer.theme(), primer.scheme())
}

// style_for is a Plot_Style for theme, whose colours are s, in the fonts
// primer.use_fonts gave, or gtx's without them. The high-contrast,
// colour-blind and tritanopia themes give each slot its own marker too,
// so a series is told by shape where its colour fails a reader.
style_for :: proc(gtx: ^ui.Ctx, theme: primer.Theme, s: ^primer.Scheme) -> (st: plot.Plot_Style) {
	data := DATA_DARK if primer.mode_of(theme) == .Dark else DATA_LIGHT
	shapes := assisted(theme)
	for hex, i in data {
		st.series[i] = {
			color = ops.rgba(hex),
		}
		if shapes {
			st.series[i].marker = plot.Marker(i % len(plot.Marker))
		}
	}
	st.slots = plot.MAX_SLOTS
	st.background, st.text, st.muted =
		s[.Bg_Color_Default], s[.Fg_Color_Default], s[.Fg_Color_Muted]
	st.grid, st.axis = s[.Border_Color_Muted], s[.Border_Color_Default]
	st.crosshair, st.focus, st.error =
		s[.Fg_Color_Muted], s[.Focus_Outline_Color], s[.Fg_Color_Danger]
	st.hover, st.other = s[.Bg_Color_Neutral_Muted], s[.Fg_Color_Muted]
	// The page's colour, not the overlay's: muted text on dark dimmed's
	// overlay falls just under 4.5:1.
	st.tooltip = {
		background = s[.Bg_Color_Default],
		border     = s[.Border_Color_Default],
		text       = s[.Fg_Color_Default],
		muted      = s[.Fg_Color_Muted],
		shadow     = s[.Shadow_Floating_Small_2],
		radius     = tok.BORDER_RADIUS_MEDIUM,
	}
	plot.set_sizes(&st)
	st.font = primer.font_for(gtx, tok.BASE_TEXT_WEIGHT_NORMAL)
	st.font_strong = primer.font_for(gtx, tok.BASE_TEXT_WEIGHT_SEMIBOLD)
	st.tick_size, st.label_size = tok.TEXT_BODY_SIZE_SMALL, tok.TEXT_BODY_SIZE_SMALL
	return
}

// assisted reports whether theme is one a reader picks for help telling
// colours apart.
assisted :: proc(theme: primer.Theme) -> bool {
	#partial switch theme {
	case .Light, .Dark, .Dark_Dimmed:
		return false
	}
	return true
}
