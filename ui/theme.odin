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
	font:                    Font_Id,
	text_size:               f32,
	small_size:              f32,
	heading_size:            f32,
	bg:                      Color, // window background
	surface:                 Color, // panels, fields, unchecked boxes
	surface_hover:           Color,
	surface_active:          Color,
	fg:                      Color, // body text
	muted:                   Color, // secondary text, placeholders
	accent:                  Color, // buttons, checked boxes, slider fill, focus ring
	on_accent:               Color, // text and marks drawn on accent
	outline:                 Color, // borders, dividers, slider track
	danger:                  Color,
	success:                 Color,
	// M3's "tonal" container pair, for filled-tonal buttons and FABs: a
	// muted background with a colour of its own, one step below the full
	// accent. jm:ui has a single accent hue rather than M3's full
	// primary/secondary/tertiary tonal palette, so primary_container is
	// derived from accent (a light tint of it, dark text for contrast) and
	// secondary_container reuses surface_active rather than inventing a
	// second hue from nothing.
	primary_container:       Color, // FAB container; default a light tint of accent
	on_primary_container:    Color, // default accent, shifted enough to read on primary_container
	secondary_container:     Color, // filled-tonal container; default surface_active
	on_secondary_container:  Color, // default fg
	radius:                  f32,
	spacing:                 f32, // base unit; paddings and gaps are multiples of it
	stroke:                  f32, // outline width
}

// light_theme is a light palette on font.
light_theme :: proc(font: Font_Id) -> Theme {
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
	derive_tonal_containers(&th)
	return th
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
	derive_tonal_containers(&th) // accent/bg/fg/surface_active just changed; rederive from them
	return th
}

// derive_tonal_containers fills the primary/secondary container pair from
// th's own accent, bg, fg and surface_active — called after any of those
// change, so a theme built by overriding fields (as dark_theme does on
// light_theme) still gets containers that match.
@(private)
derive_tonal_containers :: proc(th: ^Theme) {
	th.primary_container = mix(th.accent, th.bg, 0.75)
	th.on_primary_container = mix(th.accent, th.fg, 0.4)
	th.secondary_container = th.surface_active
	th.on_secondary_container = th.fg
}

// default_theme is light_theme.
default_theme :: proc(font: Font_Id) -> Theme {
	return light_theme(font)
}

// mix blends a toward b by t in [0, 1], channel by channel (alpha included).
mix :: proc(a, b: Color, t: f32) -> Color {
	out: Color
	for i in 0 ..< 4 {
		out[i] = u8(f32(a[i]) + (f32(b[i]) - f32(a[i])) * clamp(t, 0, 1) + 0.5)
	}
	return out
}

// with_alpha is c with its alpha channel set to t in [0, 1], RGB unchanged
// — a real translucent colour, not a pre-mixed solid one. State layers and
// disabled dimming both use this: painted on top of whatever is already
// there, the way Material's own state layers and disabled scrims work,
// rather than baking a flattened colour ahead of time per widget state.
with_alpha :: proc(c: Color, t: f32) -> Color {
	out := c
	out[3] = u8(255 * clamp(t, 0, 1))
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

// or_color is c, or def when c is the zero Color ("take the theme's").
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

// State-layer opacities, straight from Material 3's own token generator
// (md-sys-state, material-web tokens/versions/v0_192/_md-sys-state.scss):
// the interaction feedback for every M3 component is its content colour
// painted translucently on top of its container at one of these opacities,
// not a per-widget guess and not a pre-mixed solid colour — see with_alpha.
// (md-sys-state also defines a fourth, dragged-state-layer-opacity: 0.16,
// for drag-reorder; left out here since jm:ui has no drag-reorder input to
// drive it.) Disabled dims container and content by a fixed alpha instead
// of switching colour, so a disabled control loses its identity colour
// rather than looking like a duller version of it — checked across the
// three button kinds that have a container (_md-comp-filled-button.scss,
// -filled-tonal-button.scss, -elevated-button.scss), all three agreeing on
// disabled-container-opacity 0.12, disabled-label-text-opacity 0.38.
STATE_HOVER_OPACITY :: 0.08
STATE_FOCUS_OPACITY :: 0.12
STATE_PRESSED_OPACITY :: 0.12
STATE_DISABLED_CONTAINER_OPACITY :: 0.12
STATE_DISABLED_CONTENT_OPACITY :: 0.38


// Button_Kind selects which of M3's five common buttons to resolve
// defaults from — the type is what picks the colour roles (container vs.
// transparent, accent vs. on-accent vs. on-secondary-container); state and
// disabled handling are identical across all five and live in button()
// itself. Elevated's real differentiator, per _md-comp-elevated-button.scss,
// is elevation: container-elevation level1 at rest, rising to level2 on
// hover (every other kind sits at level0); jm:ui has no shadow primitive to
// render that lift, so Elevated here is only a surface-coloured Text
// button — a known, deliberate simplification.
Button_Kind :: enum u8 {
	Filled,
	Tonal,
	Outlined,
	Text,
	Elevated,
}

Button_Style :: struct {
	kind:    Button_Kind, // default Filled
	fill:    Color, // container colour; default per kind, CLEAR for Outlined/Text
	outline: Color, // border colour; default th.outline for Outlined, CLEAR otherwise
	text:    Color, // label colour; default per kind
	size:    f32, // text size, default text_size
	radius:  f32, // default fully rounded (pill), M3's own corner-full
	padding: Padding, // default 1.5 x spacing by 0.75 x spacing
}

// resolve_button fills s's zero fields from th, per s.kind's colour roles.
resolve_button :: proc(th: ^Theme, s: Button_Style) -> Button_Style {
	r := s
	fill_def, text_def, outline_def: Color
	switch s.kind {
	case .Filled:
		fill_def, text_def, outline_def = th.accent, th.on_accent, CLEAR
	case .Tonal:
		fill_def, text_def, outline_def = th.secondary_container, th.on_secondary_container, CLEAR
	case .Elevated:
		fill_def, text_def, outline_def = th.surface, th.accent, CLEAR
	case .Outlined:
		fill_def, text_def, outline_def = CLEAR, th.accent, th.outline
	case .Text:
		fill_def, text_def, outline_def = CLEAR, th.accent, CLEAR
	}
	r.fill = or_color(s.fill, fill_def)
	r.text = or_color(s.text, text_def)
	r.outline = or_color(s.outline, outline_def)
	r.size = or_size(s.size, th.text_size)
	r.padding = or_padding(s.padding, pad_xy(th.spacing * 1.5, th.spacing * 0.75))
	return r
}

// Icon_Button_Style is M3's "standard" icon button: no container, just a
// glyph whose colour switches between unselected and selected (a
// caller-owned toggle, the same shape as checkbox).
Icon_Button_Style :: struct {
	icon:          Color, // unselected glyph colour; default muted (on-surface-variant)
	selected_icon: Color, // selected glyph colour; default accent
	size:          f32, // glyph size, default 24
	box:           f32, // hit target / state-layer square, default 40
}

resolve_icon_button :: proc(th: ^Theme, s: Icon_Button_Style) -> Icon_Button_Style {
	return {
		icon = or_color(s.icon, th.muted),
		selected_icon = or_color(s.selected_icon, th.accent),
		size = or_size(s.size, 24),
		box = or_size(s.box, 40),
	}
}

// Fab_Size picks one of M3's three fixed FAB footprints.
Fab_Size :: enum u8 {
	Small,
	Regular,
	Large,
}

// fab_box returns size's container box, corner radius and icon size — M3's
// own fixed values (_md-comp-fab-primary{,-small,-large}.scss): 40/12/24,
// 56/16/24, 96/28/36.
fab_box :: proc(size: Fab_Size) -> (box, radius, icon_size: f32) {
	switch size {
	case .Small:
		return 40, 12, 24
	case .Large:
		return 96, 28, 36
	case .Regular:
	}
	return 56, 16, 24
}

// Fab_Style is shared by fab and extended_fab: always the primary
// container pair, at every size — none of _md-comp-fab-primary{,-small,
// -large}.scss's tokens define a disabled-* field the way every button
// kind's own token file does, consistent with a FAB being meant to always
// be available, so there is no disabled field here either.
Fab_Style :: struct {
	fill: Color, // container; default primary_container
	icon: Color, // default on_primary_container
	text: Color, // extended_fab's label colour; default on_primary_container
}

resolve_fab :: proc(th: ^Theme, s: Fab_Style) -> Fab_Style {
	return {
		fill = or_color(s.fill, th.primary_container),
		icon = or_color(s.icon, th.on_primary_container),
		text = or_color(s.text, th.on_primary_container),
	}
}

Box_Style :: struct {
	fill:    Color, // default surface
	outline: Color, // default outline; CLEAR for none
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
Box_Paint :: proc(gtx: ^Ctx, id: Area_Id, size: Size, user: rawptr)

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

// Segmented_Button_Style is M3's segmented button: one shared pill
// outline around N toggle segments, tokens verified against material-web
// (_md-comp-outlined-segmented-button.scss) — unselected segments are
// on-surface text on no fill, selected ones get the same secondary-
// container/on-secondary-container pair as a filled-tonal button.
Segmented_Button_Style :: struct {
	outline:       Color, // shared border; default th.outline
	text:          Color, // unselected label colour; default fg (M3's on-surface)
	selected_fill: Color, // default secondary_container
	selected_text: Color, // default on_secondary_container
	size:          f32, // text size, default text_size
	height:        f32, // default 40
}

resolve_segmented_button :: proc(th: ^Theme, s: Segmented_Button_Style) -> Segmented_Button_Style {
	return {
		outline = or_color(s.outline, th.outline),
		text = or_color(s.text, th.fg),
		selected_fill = or_color(s.selected_fill, th.secondary_container),
		selected_text = or_color(s.selected_text, th.on_secondary_container),
		size = or_size(s.size, th.text_size),
		height = or_size(s.height, 40),
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
