package plot

import "jm:ui/ops"

// Marker is the shape a series' points take where they are drawn: the
// point under the crosshair, a focused point, a box plot's outliers. A
// palette that needs more than hue to tell series apart (high contrast)
// gives each slot its own.
Marker :: enum u8 {
	Circle,
	Square,
	Diamond,
	Triangle,
}

// Series_Look is how one palette slot draws: its colour, a dash (on, off,
// in units; zero is solid) for a line, and its marker.
Series_Look :: struct {
	color:  ops.Color,
	dash:   [2]f32,
	marker: Marker,
}

// MAX_SLOTS is the most series a palette tells apart. A series past the
// slots a style fills is drawn in its other colour, as one more series
// folded into "other" would be, never a colour made up on the spot.
MAX_SLOTS :: 8

// Tooltip_Style is how the readout over a hovered point looks.
Tooltip_Style :: struct {
	background: ops.Color,
	border:     ops.Color,
	text:       ops.Color, // the values, which lead
	muted:      ops.Color, // the series names and the heading
	shadow:     ops.Color, // a soft shadow under it; zero alpha for none
	radius:     f32,
}

// Plot_Style is everything a chart takes from a design system: colours,
// fonts and the sizes of its marks. ui/plot reads nothing else, so any
// system can draw charts by filling one (see ui/plot/primer and
// ui/plot/fluent), and default_style is one that stands alone.
Plot_Style :: struct {
	background:  ops.Color, // the plot's surface: what marks are drawn on and checked against
	text:        ops.Color, // primary ink: legend names, messages
	muted:       ops.Color, // secondary ink: tick labels, axis titles
	grid:        ops.Color, // gridlines, recessive
	axis:        ops.Color, // the baseline and the zero line
	crosshair:   ops.Color, // the hairline that follows the pointer
	hover:       ops.Color, // the wash behind a hovered category
	focus:       ops.Color, // the ring round a focused plot or legend entry
	error:       ops.Color, // the text of a chart that failed to load
	other:       ops.Color, // series past the palette's slots
	series:      [MAX_SLOTS]Series_Look,
	slots:       int, // how many of series the palette fills, 1 to MAX_SLOTS
	tooltip:     Tooltip_Style,
	font:        ops.Font_Id, // labels and ticks
	font_strong: ops.Font_Id, // tooltip values
	tick_size:   f32, // tick labels and axis titles
	label_size:  f32, // legend and tooltip text
	line_width:  f32, // a series' line: 2
	area_alpha:  f32, // an area's fill, a wash of its line's colour: 0.1
	bar_radius:  f32, // a bar's rounded data end: 4
	bar_max:     f32, // the thickest a bar is drawn: 24
	box_max:     f32, // the widest a box plot's box is drawn
	gap:         f32, // the surface left between touching marks: 2
	marker_size: f32, // a marker's radius: 4, so 8 across
	focus_width: f32,
}

// look is the look of a series in slot, which follows the series, not its
// rank among those shown: hiding one never repaints another.
look :: proc(s: ^Plot_Style, slot: int) -> Series_Look {
	n := clamp(s.slots, 1, MAX_SLOTS)
	if slot < 0 || slot >= n {
		return {color = s.other, marker = .Circle}
	}
	return s.series[slot]
}

// default_style is a light style that needs no design system: the data
// visualisation reference palette (blue, orange, aqua, yellow, magenta,
// green, violet, red, in that order, validated together) on an off-white
// surface, with the platform's default font. dark is its dark twin, the
// same hues stepped for a dark surface.
default_style :: proc(dark := false, font: ops.Font_Id = 0) -> (s: Plot_Style) {
	light_hex := [MAX_SLOTS]u32 {
		0x2a78d6ff,
		0xeb6834ff,
		0x1baf7aff,
		0xeda100ff,
		0xe87ba4ff,
		0x008300ff,
		0x4a3aa7ff,
		0xe34948ff,
	}
	dark_hex := [MAX_SLOTS]u32 {
		0x3987e5ff,
		0xd95926ff,
		0x199e70ff,
		0xc98500ff,
		0xd55181ff,
		0x008300ff,
		0x9085e9ff,
		0xe66767ff,
	}
	hexes := dark_hex if dark else light_hex
	for h, i in hexes {
		s.series[i] = {
			color = ops.rgba(h),
		}
	}
	s.slots = MAX_SLOTS
	if dark {
		s.background, s.text, s.muted =
			ops.rgba(0x1a1a19ff), ops.rgba(0xffffffff), ops.rgba(0xc3c2b7ff)
		s.grid, s.axis, s.error = ops.rgba(0x2c2c2aff), ops.rgba(0x383835ff), ops.rgba(0xe66767ff)
		s.tooltip = {
			ops.rgba(0x262624ff),
			ops.rgba(0x383835ff),
			ops.rgba(0xffffffff),
			ops.rgba(0xc3c2b7ff),
			ops.rgba(0x00000080),
			6,
		}
	} else {
		s.background, s.text, s.muted =
			ops.rgba(0xfcfcfbff), ops.rgba(0x0b0b0bff), ops.rgba(0x52514eff)
		s.grid, s.axis, s.error = ops.rgba(0xe1e0d9ff), ops.rgba(0xc3c2b7ff), ops.rgba(0xd03b3bff)
		s.tooltip = {
			ops.rgba(0xffffffff),
			ops.rgba(0xe1e0d9ff),
			ops.rgba(0x0b0b0bff),
			ops.rgba(0x52514eff),
			ops.rgba(0x0b0b0b29),
			6,
		}
	}
	s.crosshair, s.focus, s.other = s.muted, s.text, ops.rgba(0x898781ff)
	s.hover = ops.with_alpha(s.text, 0.06)
	s.font, s.font_strong = font, font
	set_sizes(&s)
	return
}

// set_sizes fills s's mark sizes with the defaults every style starts from.
set_sizes :: proc(s: ^Plot_Style) {
	s.tick_size, s.label_size = 11, 12
	s.line_width, s.area_alpha = 2, 0.1
	s.bar_radius, s.bar_max, s.box_max = 4, 24, 36
	s.gap, s.marker_size, s.focus_width = 2, 4, 2
}
