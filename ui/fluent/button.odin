package fluent

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/fluent/tokens"

// Button is Fluent's single-action control (fluent-kit components/
// button.json, useButtonStyles.styles.ts at the kit's commit). Its sizes
// are the numbers the styles file hard-codes, cited where they are used
// as useButtonStyles.styles.ts:lines; its colours are alias tokens, one
// per state, chosen by color_for from the control's state and eased by
// blend over DURATION_FASTER with CURVE_EASY_EASE.
//
// Departures: disabledFocusable (looks disabled, keeps focus) has no
// jm:ui semantics to carry it; under high contrast every colour is what
// the theme binds, so a focused border is Stroke_Focus2 and a primary
// button at rest is Brand_Background (white), not the styles file's
// forced-colours overrides (ButtonText, Highlight: useButtonStyles.
// styles.ts:80-100,168-185,372-407); and a large button's 24px icon
// draws the 20px asset scaled.

// Appearance is a button's colour treatment, in falling emphasis.
Appearance :: enum u8 {
	Secondary, // the neutral filled default
	Primary, // the brand fill
	Outline, // a border, no fill
	Subtle, // no border or fill at rest; a neutral tint on hover
	Transparent, // no border or fill at rest; brand text on hover
}

// Shape is a button's corner treatment: the size's radius, a pill, or none.
Shape :: enum u8 {
	Rounded,
	Circular,
	Square,
}

// Icon_Position is which side of the label the icon sits on.
Icon_Position :: enum u8 {
	Before,
	After,
}

// Button_Metrics are one size's dimensions (useButtonStyles.styles.ts:
// 17-21, 59-61, 126-136, 291-319, 502-540): the height a control of
// that size stands, the vertical padding with and without an icon, the
// horizontal padding token, the minimum width, the icon slot, the
// icon-label gap, the focus ring's radius and the label's style.
@(private)
Button_Metrics :: struct {
	height, pad_v, pad_v_icon: f32,
	pad_h, min_width:          f32,
	icon, gap, ring:           f32,
	style:                     tok.Type_Style,
}

@(private)
button_metrics :: proc(size: Size) -> Button_Metrics {
	switch size {
	case .Small:
		return {
			height = CONTROL_HEIGHT[.Small],
			pad_v = 3,
			pad_v_icon = 1,
			pad_h = tok.SPACING_HORIZONTAL_S,
			min_width = 64,
			icon = 20,
			gap = tok.SPACING_HORIZONTAL_XS,
			ring = tok.BORDER_RADIUS_SMALL,
			style = control_style(.Small, tok.FONT_WEIGHT_REGULAR),
		}
	case .Medium:
	case .Large:
		return {
			height = CONTROL_HEIGHT[.Large],
			pad_v = 8,
			pad_v_icon = 7,
			pad_h = tok.SPACING_HORIZONTAL_L,
			min_width = 96,
			icon = 24,
			gap = tok.SPACING_HORIZONTAL_SNUDGE,
			ring = tok.BORDER_RADIUS_LARGE,
			style = control_style(.Large, tok.FONT_WEIGHT_SEMIBOLD),
		}
	}
	return {
		height = CONTROL_HEIGHT[.Medium],
		pad_v = 5,
		pad_v_icon = 5,
		pad_h = tok.SPACING_HORIZONTAL_M,
		min_width = 96,
		icon = 20,
		gap = tok.SPACING_HORIZONTAL_SNUDGE,
		ring = tok.BORDER_RADIUS_MEDIUM,
		style = control_style(.Medium, tok.FONT_WEIGHT_SEMIBOLD),
	}
}

// Button_Roles are one appearance's colour roles per state for each of
// its three transitioned properties, and the icon's, which only the
// subtle appearance colours apart from the text.
@(private)
Button_Roles :: struct {
	bg, border, text, icon: State_Roles,
}

// appearance_roles is a's roles (useButtonStyles.styles.ts:39-60,
// 139-270, 322-370, 409-462). Disabled backgrounds go to
// Neutral_Background_Disabled, except that outline, subtle and
// transparent keep a transparent one; disabled borders to
// Neutral_Stroke_Disabled, except that primary, subtle and transparent
// keep a transparent one.
@(private)
appearance_roles :: proc(a: Appearance) -> (r: Button_Roles) {
	NEUTRAL_TEXT :: State_Roles{.Neutral_Foreground1, .Neutral_Foreground1_Hover, .Neutral_Foreground1_Pressed, .Neutral_Foreground_Disabled}
	NEUTRAL_STROKE :: State_Roles{.Neutral_Stroke1, .Neutral_Stroke1_Hover, .Neutral_Stroke1_Pressed, .Neutral_Stroke_Disabled}
	NO_STROKE :: State_Roles{.Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke, .Transparent_Stroke}
	TRANSPARENT_BG :: State_Roles{.Transparent_Background, .Transparent_Background_Hover, .Transparent_Background_Pressed, .Transparent_Background}
	SECONDARY_TEXT :: State_Roles{.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}
	BRAND_ON_HOVER :: State_Roles{.Neutral_Foreground2, .Neutral_Foreground2_Brand_Hover, .Neutral_Foreground2_Brand_Pressed, .Neutral_Foreground_Disabled}
	switch a {
	case .Secondary:
		r.bg = {.Neutral_Background1, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background_Disabled}
		r.border = NEUTRAL_STROKE
		r.text = NEUTRAL_TEXT
		r.icon = NEUTRAL_TEXT
	case .Primary:
		r.bg = {.Brand_Background, .Brand_Background_Hover, .Brand_Background_Pressed, .Neutral_Background_Disabled}
		r.border = NO_STROKE
		r.text = {.Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_On_Brand, .Neutral_Foreground_Disabled}
		r.icon = r.text
	case .Outline:
		r.bg = TRANSPARENT_BG
		r.border = NEUTRAL_STROKE
		r.text = NEUTRAL_TEXT
		r.icon = NEUTRAL_TEXT
	case .Subtle:
		r.bg = {.Subtle_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Transparent_Background}
		r.border = NO_STROKE
		r.text = SECONDARY_TEXT
		r.icon = BRAND_ON_HOVER
	case .Transparent:
		r.bg = TRANSPARENT_BG
		r.border = NO_STROKE
		r.text = BRAND_ON_HOVER
		r.icon = BRAND_ON_HOVER
	}
	return
}

// button is one of Fluent's buttons. size picks height, padding,
// minimum width, text style and icon size together; shape the corners;
// ic an optional icon before or after the label, and a button with an
// icon and no label lays out square. name is an icon-only button's
// accessible name, what its tag carries in place of a label. Returns
// true on the frame it is clicked, or activated by Enter or Space while
// focused.
button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	appearance := Appearance.Secondary,
	ic := Icon.None,
	size := Size.Medium,
	shape := Shape.Rounded,
	icon_position := Icon_Position.Before,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	mt := button_metrics(size)
	t := shape_style(gtx, label, mt.style)
	has_icon := ic != .None
	icon_only := has_icon && label == ""
	pad_v := has_icon ? mt.pad_v_icon : mt.pad_v
	border := tok.STROKE_WIDTH_THIN
	content := ops.Size{t.width, t.height}
	if has_icon {
		content.y = max(content.y, mt.icon)
		content.x += mt.icon + (icon_only ? 0 : mt.gap)
	}
	if icon_only {
		content.x = mt.icon
	}
	h := pad_v * 2 + content.y + 2 * border
	w := icon_only ? h : max(mt.pad_h * 2 + content.x + 2 * border, mt.min_width)
	sz := ui.constrain_min(gtx.constraints, {w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}

	c := control(gtx, p.id, area, state)
	r := appearance_roles(appearance)
	rad: f32
	ring: f32
	switch shape {
	case .Rounded:
		rad, ring = tok.BORDER_RADIUS_MEDIUM, mt.ring
	case .Circular:
		rad = radius(tok.BORDER_RADIUS_CIRCULAR, area)
		ring = rad
	case .Square:
		rad, ring = tok.BORDER_RADIUS_NONE, tok.BORDER_RADIUS_NONE
	}
	k := corners_all(rad)
	path := rounded(gtx, area, k)
	// Slots 0-3: background, border, text and icon, the properties the
	// styles file transitions together. A focused border turns
	// Stroke_Focus2 (styles.ts:102-113).
	border_color := color_for(r.border, c)
	if c.focus_visible && !c.disabled {
		border_color = color(.Stroke_Focus2)
	}
	bg := blend(gtx, c, 0, color_for(r.bg, c))
	stroke := blend(gtx, c, 1, border_color)
	fg := blend(gtx, c, 2, color_for(r.text, c))
	icon_color := blend(gtx, c, 3, color_for(r.icon, c))

	if appearance == .Primary && c.focus_visible && !c.disabled {
		paint_shadow(gtx, {area, rad}, tok.SHADOW2) // the primary focus style composes shadow2
	}
	if ui.painted(bg) {
		ops.fill(gtx.scene, path, bg)
	}
	if ui.painted(stroke) {
		stroke_inside_corners(gtx, area, k, stroke, border)
	}
	// Subtle and transparent show an icon's filled twin while hovered or
	// pressed, unless disabled (behaviour icon-swap).
	shown := ic
	if (appearance == .Subtle || appearance == .Transparent) && (c.hovered || c.pressed) && !c.disabled {
		shown = filled(ic)
	}
	x := (sz.x - content.x) / 2
	y_icon := (sz.y - mt.icon) / 2
	y_text := (sz.y - t.height) / 2
	if has_icon && icon_position == .Before {
		icon(gtx, shown, {x, y_icon}, mt.icon, icon_color)
		x += mt.icon + (icon_only ? 0 : mt.gap)
	}
	if !icon_only {
		draw_text(gtx, t, {x, y_text}, fg)
		x += t.width
	}
	if has_icon && icon_position == .After {
		x += mt.gap
		icon(gtx, shown, {x, y_icon}, mt.icon, icon_color)
	}
	// The inset ring: the border already carries the focus colour, so
	// only the 1px ring inside it, plus primary's on-brand ring except
	// while hovered (styles.ts:464-478).
	inner := appearance == .Primary && !c.hovered ? tok.STROKE_WIDTH_THICK : 0
	paint_focus_inset(gtx, c, area, corners_all(ring), border, paint_border = false, inner = inner, inner_color = color(.Neutral_Foreground_On_Brand))
	listen(gtx, c.st, p.id, area)
	said := ui.frame_string(gtx, icon_only ? name : label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Button, label = said, states = design.state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, y_text + baseline_of(t)})
	return c.clicked
}
