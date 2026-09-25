package ui

// SKELETON, owned by work package C (see the plan). Rewrite freely but keep
// the names other packages use: Theme, default_theme.

Theme :: struct {
	font:      Font_Id,
	text_size: f32,
	fg:        Color,
	bg:        Color,
	accent:    Color,
	surface:   Color,
	outline:   Color,
	radius:    f32,
	spacing:   f32,
}

default_theme :: proc(font: Font_Id) -> Theme {
	return {
		font = font,
		text_size = 14,
		fg = {30, 30, 30, 255},
		bg = {250, 250, 250, 255},
		accent = {51, 102, 255, 255},
		surface = {255, 255, 255, 255},
		outline = {200, 200, 200, 255},
		radius = 6,
		spacing = 8,
	}
}
