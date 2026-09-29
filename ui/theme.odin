package ui

import "jm:ui/ops"

// Styling. Theme is a plain value: palette, type scale, spacing, radii and
// the font. Each widget takes an X_Style struct whose zero value means "take
// it from the theme", so `label(gtx, "Delete", {color = th.danger})`
// overrides one field and inherits the rest. resolve_x fills the zero fields.
// No cascade, no selectors: a style is a value, scoped by being passed.
//
// Zero means default: a Color of {0,0,0,0} and a size of 0 take the theme's
// value. To ask for "no paint", use CLEAR (transparent but not zero); a
// widget skips any paint whose alpha is 0. To ask for a size of exactly 0
// (square corners, no outline), pass a negative value.

// CLEAR is an explicit transparent colour, distinct from the zero Color
// that means "use the theme".
CLEAR :: ops.Color{255, 255, 255, 0}

Theme :: struct {
	font:                    ops.Font_Id,
	text_size:               f32,
	small_size:              f32,
	heading_size:            f32,
	bg:                      ops.Color, // window background
	surface:                 ops.Color, // panels, fields, unchecked boxes
	surface_hover:           ops.Color,
	surface_active:          ops.Color,
	fg:                      ops.Color, // body text
	muted:                   ops.Color, // secondary text, placeholders
	accent:                  ops.Color, // buttons, checked boxes, slider fill, focus ring
	on_accent:               ops.Color, // text and marks drawn on accent
	outline:                 ops.Color, // borders, dividers, slider track
	danger:                  ops.Color,
	success:                 ops.Color,
	radius:                  f32,
	spacing:                 f32, // base unit; paddings and gaps are multiples of it
	stroke:                  f32, // outline width
}

// light_theme is a light palette on font.
light_theme :: proc(font: ops.Font_Id) -> Theme {
	th := Theme {
		font = font,
		text_size = 14,
		small_size = 12,
		heading_size = 20,
		bg = {246, 246, 248, 255},
		surface = {255, 255, 255, 255},
		surface_hover = {240, 240, 244, 255},
		surface_active = {226, 226, 232, 255},
		fg = {28, 28, 32, 255},
		muted = {110, 110, 120, 255},
		accent = {51, 102, 255, 255},
		on_accent = {255, 255, 255, 255},
		outline = {200, 200, 208, 255},
		danger = {214, 48, 49, 255},
		success = {32, 150, 80, 255},
		radius = 6,
		spacing = 8,
		stroke = 1,
	}
	return th
}

// dark_theme is a dark palette on font, with the same scale as light_theme.
dark_theme :: proc(font: ops.Font_Id) -> Theme {
	th := light_theme(font)
	th.bg = {24, 24, 28, 255}
	th.surface = {36, 36, 42, 255}
	th.surface_hover = {46, 46, 54, 255}
	th.surface_active = {58, 58, 68, 255}
	th.fg = {232, 232, 238, 255}
	th.muted = {150, 150, 162, 255}
	th.accent = {92, 136, 255, 255}
	th.on_accent = {255, 255, 255, 255}
	th.outline = {70, 70, 82, 255}
	th.danger = {240, 90, 90, 255}
	th.success = {70, 190, 120, 255}
	return th
}

// default_theme is light_theme.
default_theme :: proc(font: ops.Font_Id) -> Theme {
	return light_theme(font)
}

// Padding is space inside an edge, per side.
Padding :: struct {
	left, top, right, bottom: f32,
}

// pad_all pads every side by v.
pad_all :: proc(v: f32) -> Padding {
	return {v, v, v, v}
}

// pad_xy pads left and right by x, top and bottom by y.
pad_xy :: proc(x, y: f32) -> Padding {
	return {x, y, x, y}
}

// pad builds a Padding from one value (all sides) or two (x, y).
pad :: proc {
	pad_all,
	pad_xy,
}

// or_color is c, or def when c is the zero Color ("take the theme's").
or_color :: proc(c, def: ops.Color) -> ops.Color {
	return c == {} ? def : c
}

// or_size resolves a size field: 0 takes def, negative means exactly 0.
@(private)
or_size :: proc(v, def: f32) -> f32 {
	if v == 0 {
		return def
	}
	return max(v, 0)
}

// or_padding resolves a padding field like or_size: all-zero takes def,
// and a negative side means exactly 0 — so pad_all(-1) is "no padding",
// which the zero value cannot say.
@(private)
or_padding :: proc(p, def: Padding) -> Padding {
	if p == {} {
		return def
	}
	return {max(p.left, 0), max(p.top, 0), max(p.right, 0), max(p.bottom, 0)}
}

// painted reports whether c has any alpha: a widget skips paint that has none.
painted :: proc(c: ops.Color) -> bool {
	return c[3] != 0
}

Label_Style :: struct {
	color: ops.Color, // default fg
	size:  f32, // default text_size
}

// resolve_label fills s's zero fields from th.
resolve_label :: proc(th: ^Theme, s: Label_Style) -> Label_Style {
	return {color = or_color(s.color, th.fg), size = or_size(s.size, th.text_size)}
}

Box_Style :: struct {
	fill:    ops.Color, // default surface
	outline: ops.Color, // default outline; CLEAR for none
	stroke:  f32, // outline width, default stroke
	radius:  f32, // default radius
	padding: Padding, // default spacing on every side
	// paint, when set, replaces the fill and outline: it is called once the
	// box's size is known, under the body, with the box's own id — so a
	// design system can paint its own surface (a shadow, per-corner radii,
	// a state layer) and register an input area the body sits on top of.
	paint:   Box_Paint,
	user:    rawptr, // passed to paint
}

// Box_Paint paints a box's background at size; id is the box's Area_Id.
Box_Paint :: proc(gtx: ^Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr)

// resolve_box fills s's zero fields from th.
resolve_box :: proc(th: ^Theme, s: Box_Style) -> Box_Style {
	return {
		fill = or_color(s.fill, th.surface),
		outline = or_color(s.outline, th.outline),
		stroke = or_size(s.stroke, th.stroke),
		radius = or_size(s.radius, th.radius),
		padding = or_padding(s.padding, pad_all(th.spacing)),
		paint = s.paint,
		user = s.user,
	}
}
