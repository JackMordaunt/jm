package ui

// Styling. Theme is a plain value: palette, type scale, spacing, radii and
// the font. Each widget takes an X_Style struct whose zero value means "take
// it from the theme", so `button(gtx, "Delete", {fill = th.danger})`
// overrides one field and inherits the rest. resolve_x fills the zero fields.
// No cascade, no selectors: a style is a value, scoped by being passed.
//
// Zero means default: a Color of {0,0,0,0} and a size of 0 take the theme's
// value. To ask for "no paint", use CLEAR (transparent but not zero); a
// widget skips any paint whose alpha is 0. To ask for a size of exactly 0
// (square corners, no outline), pass a negative value.

// CLEAR is an explicit transparent colour, distinct from the zero Color
// that means "use the theme".
CLEAR :: Color{255, 255, 255, 0}

Theme :: struct {
	font:           Font_Id,
	text_size:      f32,
	small_size:     f32,
	heading_size:   f32,
	bg:             Color, // window background
	surface:        Color, // panels, fields, unchecked boxes
	surface_hover:  Color,
	surface_active: Color,
	fg:             Color, // body text
	muted:          Color, // secondary text, placeholders
	accent:         Color, // buttons, checked boxes, slider fill, focus ring
	on_accent:      Color, // text and marks drawn on accent
	outline:        Color, // borders, dividers, slider track
	danger:         Color,
	success:        Color,
	radius:         f32,
	spacing:        f32, // base unit; paddings and gaps are multiples of it
	stroke:         f32, // outline width
}

// light_theme is a light palette on font.
light_theme :: proc(font: Font_Id) -> Theme {
	return {
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
}

// dark_theme is a dark palette on font, with the same scale as light_theme.
dark_theme :: proc(font: Font_Id) -> Theme {
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
default_theme :: proc(font: Font_Id) -> Theme {
	return light_theme(font)
}

// mix blends a toward b by t in [0, 1], channel by channel.
mix :: proc(a, b: Color, t: f32) -> Color {
	out: Color
	for i in 0 ..< 4 {
		out[i] = u8(f32(a[i]) + (f32(b[i]) - f32(a[i])) * clamp(t, 0, 1) + 0.5)
	}
	return out
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

@(private)
or_color :: proc(c, def: Color) -> Color {
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

@(private)
or_padding :: proc(p, def: Padding) -> Padding {
	return p == {} ? def : p
}

@(private)
painted :: proc(c: Color) -> bool {
	return c[3] != 0
}

Label_Style :: struct {
	color: Color, // default fg
	size:  f32, // default text_size
}

// resolve_label fills s's zero fields from th.
resolve_label :: proc(th: ^Theme, s: Label_Style) -> Label_Style {
	return {color = or_color(s.color, th.fg), size = or_size(s.size, th.text_size)}
}

Button_Style :: struct {
	fill:    Color, // default accent
	hover:   Color, // default fill lightened
	active:  Color, // default fill darkened
	text:    Color, // default on_accent
	size:    f32, // text size, default text_size
	radius:  f32, // default radius
	padding: Padding, // default 1.5 x spacing by 0.75 x spacing
}

// resolve_button fills s's zero fields from th; hover and active derive from
// the resolved fill, so overriding fill alone recolours every state.
resolve_button :: proc(th: ^Theme, s: Button_Style) -> Button_Style {
	r := s
	r.fill = or_color(s.fill, th.accent)
	r.hover = or_color(s.hover, mix(r.fill, {255, 255, 255, r.fill[3]}, 0.15))
	r.active = or_color(s.active, mix(r.fill, {0, 0, 0, r.fill[3]}, 0.2))
	r.text = or_color(s.text, th.on_accent)
	r.size = or_size(s.size, th.text_size)
	r.radius = or_size(s.radius, th.radius)
	r.padding = or_padding(s.padding, pad_xy(th.spacing * 1.5, th.spacing * 0.75))
	return r
}

Box_Style :: struct {
	fill:    Color, // default surface
	outline: Color, // default outline; CLEAR for none
	stroke:  f32, // outline width, default stroke
	radius:  f32, // default radius
	padding: Padding, // default spacing on every side
}

// resolve_box fills s's zero fields from th.
resolve_box :: proc(th: ^Theme, s: Box_Style) -> Box_Style {
	return {
		fill = or_color(s.fill, th.surface),
		outline = or_color(s.outline, th.outline),
		stroke = or_size(s.stroke, th.stroke),
		radius = or_size(s.radius, th.radius),
		padding = or_padding(s.padding, pad_all(th.spacing)),
	}
}

Checkbox_Style :: struct {
	box:     Color, // unchecked fill, default surface
	outline: Color, // unchecked border, default outline (accent on hover)
	checked: Color, // checked fill, default accent
	mark:    Color, // check mark, default on_accent
	text:    Color, // default fg
	size:    f32, // text size, default text_size
	gap:     f32, // box to text, default spacing
	radius:  f32, // default radius / 2
}

// resolve_checkbox fills s's zero fields from th.
resolve_checkbox :: proc(th: ^Theme, s: Checkbox_Style) -> Checkbox_Style {
	return {
		box = or_color(s.box, th.surface),
		outline = or_color(s.outline, th.outline),
		checked = or_color(s.checked, th.accent),
		mark = or_color(s.mark, th.on_accent),
		text = or_color(s.text, th.fg),
		size = or_size(s.size, th.text_size),
		gap = or_size(s.gap, th.spacing),
		radius = or_size(s.radius, th.radius / 2),
	}
}

Slider_Style :: struct {
	track:      Color, // default outline
	fill:       Color, // the part below the value, default accent
	knob:       Color, // default accent
	width:      f32, // preferred width, default 20 x spacing
	knob_size:  f32, // knob diameter and slider height, default text_size + 4
	track_size: f32, // track thickness, default spacing / 2
}

// resolve_slider fills s's zero fields from th.
resolve_slider :: proc(th: ^Theme, s: Slider_Style) -> Slider_Style {
	return {
		track = or_color(s.track, th.outline),
		fill = or_color(s.fill, th.accent),
		knob = or_color(s.knob, th.accent),
		width = or_size(s.width, th.spacing * 20),
		knob_size = or_size(s.knob_size, th.text_size + 4),
		track_size = or_size(s.track_size, th.spacing / 2),
	}
}

Text_Field_Style :: struct {
	fill:    Color, // default surface
	outline: Color, // default outline
	focus:   Color, // outline while focused, default accent
	text:    Color, // default fg
	caret:   Color, // default fg
	size:    f32, // text size, default text_size
	width:   f32, // minimum width, default 20 x spacing
	stroke:  f32, // outline width, default stroke
	radius:  f32, // default radius
	padding: Padding, // default spacing by spacing / 2
}

// resolve_text_field fills s's zero fields from th.
resolve_text_field :: proc(th: ^Theme, s: Text_Field_Style) -> Text_Field_Style {
	return {
		fill = or_color(s.fill, th.surface),
		outline = or_color(s.outline, th.outline),
		focus = or_color(s.focus, th.accent),
		text = or_color(s.text, th.fg),
		caret = or_color(s.caret, th.fg),
		size = or_size(s.size, th.text_size),
		width = or_size(s.width, th.spacing * 20),
		stroke = or_size(s.stroke, th.stroke),
		radius = or_size(s.radius, th.radius),
		padding = or_padding(s.padding, pad_xy(th.spacing, th.spacing / 2)),
	}
}
