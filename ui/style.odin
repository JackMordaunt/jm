package ui

import "jm:ui/ops"

// Styling. A style is a plain value passed to the widget: no cascade, no
// selectors, scoped by being passed. ui has no theme of its own; a zero
// field here means nothing — no paint, no padding — and it is the design
// system above (ui/base, ui/material) that fills a zero from its theme
// before calling. CLEAR paints nothing where a colour is expected, for a
// system whose zero means "from the theme".

// CLEAR is an explicit transparent colour, distinct from the zero Color
// that means "use the theme".
CLEAR :: ops.Color{255, 255, 255, 0}

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

// painted reports whether c has any alpha: a widget skips paint that has none.
painted :: proc(c: ops.Color) -> bool {
	return c[3] != 0
}

Box_Style :: struct {
	fill:    ops.Color, // zero paints nothing
	outline: ops.Color, // zero paints nothing
	stroke:  f32, // outline width
	radius:  f32,
	padding: Padding,
	// paint, when set, replaces the fill and outline: it is called once the
	// box's size is known, under the body, with the box's own id — so a
	// design system can paint its own surface (a shadow, per-corner radii,
	// a state layer) and register an input area the body sits on top of.
	paint:   Box_Paint,
	user:    rawptr, // passed to paint
}

// Box_Paint paints a box's background at size; id is the box's Area_Id.
Box_Paint :: proc(gtx: ^Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr)
