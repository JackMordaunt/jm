package fluent

import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// The rest of the button family, each on the fluent-kit's spec and the
// styles file it cites: toggle_button (toggle-button.json,
// useToggleButtonStyles.styles.ts), menu_button (menu-button.json,
// useMenuButtonStyles.styles.ts), split_button (split-button.json,
// useSplitButtonStyles.styles.ts) and compound_button
// (compound-button.json, useCompoundButtonStyles.styles.ts). Each is
// button's geometry and states (button.odin's private metrics and roles)
// with its own layout or Selected colours on top, painted through a
// shared frame: the box, its border on the sides it has one, the focus
// ring, and the four blended colours.

// Frame is one button-like box's resolved state and colours.
@(private)
Frame :: struct {
	c:                  Control,
	sz:                 ops.Size,
	area:               ops.Rect,
	k, ring:            Corners,
	bg, stroke, fg, ic: ops.Color,
}

// frame_corners is a button's corners for shape at size, and its focus
// ring's (button.json states.focused, useButtonStyles.styles.ts:464-500).
@(private)
frame_corners :: proc(shape: Shape, mt: Button_Metrics, area: ops.Rect) -> (k, ring: Corners) {
	switch shape {
	case .Rounded:
		return corners_all(tok.BORDER_RADIUS_MEDIUM), corners_all(mt.ring)
	case .Circular:
		r := radius(tok.BORDER_RADIUS_CIRCULAR, area)
		return corners_all(r), corners_all(r)
	case .Square:
	}
	return {}, {}
}

// frame_control resolves the control for a button-like box of sz and
// blends its four colours from roles: background, border, text and
// icon, the border turning Stroke_Focus2 while focused unless
// focus_border is off (a checked outline toggle keeps its own).
@(private)
frame_control :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, sz: ops.Size, roles: Button_Roles, state: Interaction, k, ring: Corners, focus_border := true) -> (f: Frame) {
	f.sz = sz
	f.area = {0, 0, sz.x, sz.y}
	f.k, f.ring = k, ring
	f.c = control(gtx, id, f.area, state)
	border := color_for(roles.border, f.c)
	if f.c.focus_visible && !f.c.disabled && focus_border {
		border = color(.Stroke_Focus2)
	}
	f.bg = blend(gtx, f.c, 0, color_for(roles.bg, f.c))
	f.stroke = blend(gtx, f.c, 1, border)
	f.fg = blend(gtx, f.c, 2, color_for(roles.text, f.c))
	f.ic = blend(gtx, f.c, 3, color_for(roles.icon, f.c))
	return
}

// Sides is which edges of a frame carry its border: all four, or all
// but one for a split button's joined halves.
@(private)
Sides :: bit_set[Side]
@(private)
Side :: enum u8 {
	Left,
	Top,
	Right,
	Bottom,
}
@(private)
ALL_SIDES :: Sides{.Left, .Top, .Right, .Bottom}

// frame_paint paints f's background and border (width wide, on sides),
// plus the focus style's shadow2 on a primary button.
@(private)
frame_paint :: proc(gtx: ^ui.Ctx, f: Frame, appearance: Appearance, width: f32 = tok.STROKE_WIDTH_THIN, sides := ALL_SIDES) {
	path := rounded(gtx, f.area, f.k)
	if appearance == .Primary && f.c.focus_visible && !f.c.disabled {
		paint_shadow(gtx, {f.area, f.k.tl}, tok.SHADOW2)
	}
	if ui.painted(f.bg) {
		ops.fill(gtx.scene, path, f.bg)
	}
	if !ui.painted(f.stroke) {
		return
	}
	if sides == ALL_SIDES {
		stroke_inside_corners(gtx, f.area, f.k, f.stroke, width)
		return
	}
	// A joined half: the border on its outer sides only, its corners
	// square on the joined side, so the halves share one line.
	ops.clip_push(gtx.scene, ops.Rect{f.area.x, f.area.y, f.area.w, f.area.h})
	grown := f.area
	if .Left not_in sides {
		grown.x -= width
		grown.w += width
	}
	if .Right not_in sides {
		grown.w += width
	}
	stroke_inside_corners(gtx, grown, f.k, f.stroke, width)
	ops.clip_pop(gtx.scene)
}

// frame_focus paints the inset focus ring (button.odin's) with primary's
// on-brand inner ring except while hovered.
@(private)
frame_focus :: proc(gtx: ^ui.Ctx, f: Frame, appearance: Appearance, border: f32 = tok.STROKE_WIDTH_THIN) {
	inner := appearance == .Primary && !f.c.hovered ? tok.STROKE_WIDTH_THICK : 0
	paint_focus_inset(gtx, f.c, f.area, f.ring, border, paint_border = false, inner = inner, inner_color = color(.Neutral_Foreground_On_Brand))
}

// selected_roles is appearance a's roles with the rest colours swapped
// for their Selected tokens: what a checked toggle and an expanded menu
// button paint (toggle-button.json and menu-button.json variants). Hover
// and press read the ordinary tokens, so an on button under the pointer
// looks like an off one (both specs' gotcha). border_width is the border
// an outline appearance widens to.
@(private)
selected_roles :: proc(a: Appearance) -> (r: Button_Roles, border_width: f32) {
	r = appearance_roles(a)
	border_width = tok.STROKE_WIDTH_THIN
	switch a {
	case .Secondary:
		r.bg.rest = .Neutral_Background1_Selected
		r.border.rest = .Neutral_Stroke1_Selected
		r.text.rest = .Neutral_Foreground1_Selected
		r.icon.rest = .Neutral_Foreground1_Selected
	case .Primary:
		r.bg.rest = .Brand_Background_Selected
	case .Outline:
		r.bg.rest = .Transparent_Background_Selected
		r.border.rest = .Neutral_Stroke1_Selected
		r.text.rest = .Neutral_Foreground1_Selected
		r.icon.rest = .Neutral_Foreground1_Selected
		border_width = tok.STROKE_WIDTH_THICKER
	case .Subtle:
		r.bg.rest = .Subtle_Background_Selected
		r.text.rest = .Neutral_Foreground2_Selected
		r.icon.rest = .Neutral_Foreground2_Brand_Selected
	case .Transparent:
		r.bg.rest = .Transparent_Background_Selected
		r.text.rest = .Neutral_Foreground2_Brand_Selected
		r.icon.rest = .Neutral_Foreground2_Brand_Selected
	}
	return
}

// label_size is a button's content box for a label and an optional icon
// at metrics mt: the text, the icon slot and the gap (button.json layout).
@(private)
label_size :: proc(t: Text, has_icon, icon_only: bool, mt: Button_Metrics) -> (content: ops.Size, pad_v: f32) {
	pad_v = has_icon ? mt.pad_v_icon : mt.pad_v
	content = {t.width, t.height}
	if has_icon {
		content.y = max(content.y, mt.icon)
		content.x += mt.icon + (icon_only ? 0 : mt.gap)
	}
	if icon_only {
		content.x = mt.icon
	}
	return
}

// paint_label draws a button's icon and label centred in f, the icon on
// the side icon_position says, in f's colours; extra is laid out after
// the label (a menu button's chevron), width wide.
@(private)
paint_label :: proc(gtx: ^ui.Ctx, f: Frame, t: Text, shown: Icon, icon_position: Icon_Position, mt: Button_Metrics, content: ops.Size, icon_only: bool) -> (x: f32) {
	x = (f.sz.x - content.x) / 2
	y_icon := (f.sz.y - mt.icon) / 2
	y_text := (f.sz.y - t.height) / 2
	if shown != .None && icon_position == .Before {
		icon(gtx, shown, {x, y_icon}, mt.icon, f.ic)
		x += mt.icon + (icon_only ? 0 : mt.gap)
	}
	if !icon_only {
		draw_text(gtx, t, {x, y_text}, f.fg)
		x += t.width
	}
	if shown != .None && icon_position == .After {
		x += mt.gap
		icon(gtx, shown, {x, y_icon}, mt.icon, f.ic)
		x += mt.icon
	}
	return
}

// toggle_button is a button that stays pressed: a click, Enter or Space
// flips checked^, and while checked it paints the appearance's Selected
// colours (toggle-button.json variants) with the filled icon. A checked
// outline widens its border to strokeWidthThicker inside the same box,
// and keeps Neutral_Stroke1 while focused rather than Stroke_Focus2.
// Disabled overrides checked. Sizes, shapes and the icon are button's.
//
// Departures: isAccessible (brand fill for the on state on every
// appearance) is not built; disabledFocusable has no jm:ui semantics.
toggle_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	checked: ^bool,
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
	has_icon, icon_only := ic != .None, ic != .None && label == ""
	content, pad_v := label_size(t, has_icon, icon_only, mt)
	border := tok.STROKE_WIDTH_THIN
	h := pad_v * 2 + content.y + 2 * border
	w := icon_only ? h : max(mt.pad_h * 2 + content.x + 2 * border, mt.min_width)
	sz := ui.constrain_min(gtx.constraints, {w, h})
	on := checked != nil && checked^
	roles := appearance_roles(appearance)
	width := border
	if on {
		roles, width = selected_roles(appearance)
	}
	k, ring := frame_corners(shape, mt, {0, 0, sz.x, sz.y})
	f := frame_control(gtx, p.id, sz, roles, state, k, ring, focus_border = !(on && appearance == .Outline))
	if f.c.clicked && checked != nil {
		checked^ = !checked^
	}
	frame_paint(gtx, f, appearance, width)
	shown := ic
	if !f.c.disabled && (on || ((appearance == .Subtle || appearance == .Transparent) && (f.c.hovered || f.c.pressed))) {
		shown = filled(ic)
	}
	paint_label(gtx, f, t, shown, icon_position, mt, content, icon_only)
	frame_focus(gtx, f, appearance, width)
	listen(gtx, f.c.st, p.id, f.area)
	said := ui.frame_string(gtx, icon_only ? name : label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Button, label = said, states = design.state_if(on, {.Selected}) + design.state_if(f.c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return f.c.clicked
}

// MENU_ICON_SMALL and MENU_ICON_LARGE are the menu button's chevron
// sizes (menu-button.json layout, useMenuButtonStyles.styles.ts:77-106).
@(private)
MENU_ICON_SMALL :: f32(12)
@(private)
MENU_ICON_LARGE :: f32(16)

// menu_button is a button that opens a menu: a Chevron_Down after the
// label (12px, 16px at large, spacingHorizontalXS after the label) and,
// while open^, the appearance's Selected colours with filled icons
// (menu-button.json states.expanded). A click, Enter, Space or ArrowDown
// flips open^ on (a click while open closes). The icon always sits
// before the label. Compose the menu itself with fluent.menu in a stack
// with this trigger.
menu_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	open: ^bool,
	appearance := Appearance.Secondary,
	ic := Icon.None,
	size := Size.Medium,
	shape := Shape.Rounded,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	mt := button_metrics(size)
	t := shape_style(gtx, label, mt.style)
	has_icon, icon_only := ic != .None, ic != .None && label == ""
	content, pad_v := label_size(t, has_icon, icon_only, mt)
	chev := size == .Large ? MENU_ICON_LARGE : MENU_ICON_SMALL
	content.x += chev + (icon_only ? 0 : tok.SPACING_HORIZONTAL_XS)
	border := tok.STROKE_WIDTH_THIN
	h := pad_v * 2 + content.y + 2 * border
	w := max(mt.pad_h * 2 + content.x + 2 * border, icon_only ? 0 : mt.min_width)
	sz := ui.constrain_min(gtx.constraints, {w, h})
	expanded := open != nil && open^
	roles := appearance_roles(appearance)
	width := border
	if expanded {
		roles, width = selected_roles(appearance)
	}
	k, ring := frame_corners(shape, mt, {0, 0, sz.x, sz.y})
	f := frame_control(gtx, p.id, sz, roles, state, k, ring)
	toggled := f.c.clicked
	if f.c.st != nil && f.c.focused && !expanded {
		for e in ui.events(gtx, p.id) {
			if e.kind == .Key && e.key == .Down {
				toggled = true
			}
		}
	}
	if toggled && open != nil {
		open^ = !open^
	}
	frame_paint(gtx, f, appearance, width)
	shown := ic
	if !f.c.disabled && (expanded || ((appearance == .Subtle || appearance == .Transparent) && (f.c.hovered || f.c.pressed))) {
		shown = filled(ic)
	}
	x := paint_label(gtx, f, t, shown, .Before, mt, content, icon_only)
	x += icon_only ? 0 : tok.SPACING_HORIZONTAL_XS
	icon(gtx, expanded ? .Chevron_Down_Filled : .Chevron_Down, {x, (sz.y - chev) / 2}, chev, f.ic)
	frame_focus(gtx, f, appearance, width)
	listen(gtx, f.c.st, p.id, f.area)
	said := ui.frame_string(gtx, icon_only ? name : label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Button, label = said, states = ops.States{.Expandable} + design.state_if(expanded, {.Expanded}) + design.state_if(f.c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return toggled
}

// SPLIT_MENU_MIN_WIDTH is the menu half's minimum width, WCAG 2.2's
// 2.5.8 Target Size minimum (split-button.json layout,
// useSplitButtonStyles.styles.ts:15-17).
@(private)
SPLIT_MENU_MIN_WIDTH :: f32(24)

// split_button is two joined buttons: the primary action, whose click
// returns true, and a chevron menu half that flips menu_open^ (its own
// tab stop, opening on Enter, Space or ArrowDown too). The halves share
// one line between them: the primary action's end border, in the
// appearance's stroke (Neutral_Stroke_On_Brand on primary, nothing on
// subtle and transparent), and only the outer corners round. Each half
// draws its own focus ring, squared on the joined side. Sizes, shapes
// and the icon are button's.
split_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	menu_open: ^bool,
	appearance := Appearance.Secondary,
	ic := Icon.None,
	size := Size.Medium,
	shape := Shape.Rounded,
	icon_position := Icon_Position.Before,
	menu_name := "Menu",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	r := ui.row_open(gtx, key = key, loc = loc)
	defer ui.close(&r)
	mt := button_metrics(size)
	clicked := false
	// The divider is the primary half's end border; it follows that
	// half's own state on secondary and outline (split-button.json
	// states.hovered), stays On_Brand on primary, and is nothing on
	// subtle and transparent.
	divider: State_Roles
	switch appearance {
	case .Secondary, .Outline:
		divider = appearance_roles(appearance).border
	case .Primary:
		divider = {.Neutral_Stroke_On_Brand, .Neutral_Stroke_On_Brand, .Neutral_Stroke_On_Brand, .Neutral_Stroke_Disabled}
	case .Subtle, .Transparent:
		divider = {.Transparent_Background, .Transparent_Background_Hover, .Transparent_Background_Pressed, .Transparent_Background}
	}
	{
		// The primary action: a button with its end corners squared and
		// its end border the divider.
		p := ui.widget_open(gtx, 1)
		t := shape_style(gtx, label, mt.style)
		has_icon, icon_only := ic != .None, ic != .None && label == ""
		content, pad_v := label_size(t, has_icon, icon_only, mt)
		border := tok.STROKE_WIDTH_THIN
		h := pad_v * 2 + content.y + 2 * border
		w := icon_only ? h : max(mt.pad_h * 2 + content.x + 2 * border, mt.min_width)
		sz := ui.constrain_min(gtx.constraints, {w, h})
		roles := appearance_roles(appearance)
		k, ring := frame_corners(shape, mt, {0, 0, sz.x, sz.y})
		k.tr, k.br, ring.tr, ring.br = 0, 0, 0, 0
		f := frame_control(gtx, p.id, sz, roles, state, k, ring)
		clicked = f.c.clicked
		frame_paint(gtx, f, appearance, border, {.Left, .Top, .Bottom})
		// The end border in the divider's colour, over the whole height.
		div := color_for(divider, f.c)
		if f.c.focus_visible && !f.c.disabled {
			div = color(.Stroke_Focus2)
		}
		if ui.painted(div) {
			ops.fill(gtx.scene, ops.Rect{sz.x - border, 0, border, sz.y}, div)
		}
		shown := ic
		if !f.c.disabled && (appearance == .Subtle || appearance == .Transparent) && (f.c.hovered || f.c.pressed) {
			shown = filled(ic)
		}
		paint_label(gtx, f, t, shown, icon_position, mt, content, icon_only)
		frame_focus(gtx, f, appearance)
		listen(gtx, f.c.st, p.id, f.area)
		ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
		ui.semantics(gtx, &p, {role = .Button, label = label, states = design.state_if(f.c.disabled, {.Disabled})})
		ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	}
	{
		// The menu half: an icon-only menu button with no start border,
		// its start corners squared, at least 24px wide.
		p := ui.widget_open(gtx, 2)
		chev := size == .Large ? MENU_ICON_LARGE : MENU_ICON_SMALL
		border := tok.STROKE_WIDTH_THIN
		h := mt.pad_v_icon * 2 + mt.icon + 2 * border
		w := max(h, SPLIT_MENU_MIN_WIDTH)
		sz := ui.constrain_min(gtx.constraints, {w, h})
		expanded := menu_open != nil && menu_open^
		roles := appearance_roles(appearance)
		width := border
		if expanded {
			roles, width = selected_roles(appearance)
		}
		k, ring := frame_corners(shape, mt, {0, 0, sz.x, sz.y})
		k.tl, k.bl, ring.tl, ring.bl = 0, 0, 0, 0
		f := frame_control(gtx, p.id, sz, roles, state, k, ring)
		toggled := f.c.clicked
		if f.c.st != nil && f.c.focused && !expanded {
			for e in ui.events(gtx, p.id) {
				if e.kind == .Key && e.key == .Down {
					toggled = true
				}
			}
		}
		if toggled && menu_open != nil {
			menu_open^ = !menu_open^
		}
		frame_paint(gtx, f, appearance, width, {.Top, .Right, .Bottom})
		icon(gtx, expanded ? .Chevron_Down_Filled : .Chevron_Down, {(sz.x - chev) / 2, (sz.y - chev) / 2}, chev, f.ic)
		frame_focus(gtx, f, appearance, width)
		listen(gtx, f.c.st, p.id, f.area)
		ops.tag(gtx.scene, p.id, ui.frame_string(gtx, menu_name))
		ui.semantics(gtx, &p, {role = .Button, label = menu_name, states = ops.States{.Expandable} + design.state_if(expanded, {.Expanded}) + design.state_if(f.c.disabled, {.Disabled})})
		ui.widget_close(gtx, &p, {size = sz})
	}
	return clicked
}

// COMPOUND_* are the compound button's constants (compound-button.json
// layout, useCompoundButtonStyles.styles.ts:134-151,194-231).
@(private)
COMPOUND_ICON :: f32(40)
@(private)
COMPOUND_TOP := [Size]f32{.Small = tok.SPACING_HORIZONTAL_S, .Medium = 14, .Large = 18}
@(private)
COMPOUND_BOTTOM := [Size]f32{.Small = tok.SPACING_HORIZONTAL_MNUDGE, .Medium = tok.SPACING_HORIZONTAL_L, .Large = tok.SPACING_HORIZONTAL_XL}
@(private)
COMPOUND_ICON_ONLY_WIDTH := [Size]f32{.Small = 48, .Medium = 52, .Large = 56}
@(private)
COMPOUND_ICON_ONLY_PAD := [Size]f32{.Small = tok.SPACING_HORIZONTAL_XS, .Medium = tok.SPACING_HORIZONTAL_SNUDGE, .Large = tok.SPACING_HORIZONTAL_S}

// compound_button is a tall button with a 40px icon, a label and a line
// of secondary text under it (compound-button.json). Its height grows
// with the icon and the two lines rather than holding button's; the
// padding is the size's (8/14/18px on top, spacingHorizontalS/M/L at
// the sides, MNudge/L/XL at the bottom); the label is fontSizeBase300
// regular at small, semibold at medium, fontSizeBase400 semibold at
// large, and the secondary text fontSizeBase200 (300 at large) on a
// line its own size in Neutral_Foreground2, stepping with hover and
// press as the label's family does. An icon-only compound button is
// 48, 52 or 56px square. Colours, focus and the transition are button's.
compound_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	secondary: string,
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
	label_style := mt.style
	if size == .Small {
		label_style.size, label_style.line_height = tok.FONT_SIZE_BASE300, tok.LINE_HEIGHT_BASE300
	}
	sec_style := tok.Type_Style{weight = tok.FONT_WEIGHT_REGULAR, size = tok.FONT_SIZE_BASE200, line_height = tok.FONT_SIZE_BASE200}
	if size == .Large {
		sec_style.size, sec_style.line_height = tok.FONT_SIZE_BASE300, tok.FONT_SIZE_BASE300
	}
	t := shape_style(gtx, label, label_style)
	s := shape_style(gtx, secondary, sec_style)
	has_icon, icon_only := ic != .None, ic != .None && label == "" && secondary == ""
	border := tok.STROKE_WIDTH_THIN
	text_w := max(t.width, s.width)
	text_h := t.height + (secondary != "" ? s.height : 0)
	content := ops.Size{text_w, text_h}
	if has_icon {
		content.x += COMPOUND_ICON + tok.SPACING_HORIZONTAL_M
		content.y = max(content.y, COMPOUND_ICON)
	}
	sz: ops.Size
	if icon_only {
		side := COMPOUND_ICON_ONLY_WIDTH[size]
		sz = ui.constrain_min(gtx.constraints, {side, side})
	} else {
		h := COMPOUND_TOP[size] + content.y + COMPOUND_BOTTOM[size] + 2 * border
		w := max(mt.pad_h * 2 + content.x + 2 * border, mt.min_width)
		sz = ui.constrain_min(gtx.constraints, {w, h})
	}
	roles := appearance_roles(appearance)
	k, ring := frame_corners(shape, mt, {0, 0, sz.x, sz.y})
	f := frame_control(gtx, p.id, sz, roles, state, k, ring)
	// The secondary text's family: Foreground 2 stepping with hover and
	// press, on-brand on primary, brand on transparent (variants).
	sec_roles: State_Roles
	switch appearance {
	case .Secondary, .Outline, .Subtle:
		sec_roles = {.Neutral_Foreground2, .Neutral_Foreground2_Hover, .Neutral_Foreground2_Pressed, .Neutral_Foreground_Disabled}
	case .Primary:
		sec_roles = roles.text
	case .Transparent:
		sec_roles = {.Neutral_Foreground2, .Neutral_Foreground2_Brand_Hover, .Neutral_Foreground2_Brand_Pressed, .Neutral_Foreground_Disabled}
	}
	sec_color := color_for(sec_roles, f.c)
	frame_paint(gtx, f, appearance)
	shown := ic
	if !f.c.disabled && (appearance == .Subtle || appearance == .Transparent) && (f.c.hovered || f.c.pressed) {
		shown = filled(ic)
	}
	if icon_only {
		pad := COMPOUND_ICON_ONLY_PAD[size]
		icon(gtx, shown, {(sz.x - COMPOUND_ICON) / 2, (sz.y - COMPOUND_ICON) / 2}, min(COMPOUND_ICON, sz.x - 2 * pad), f.ic)
	} else {
		x := (sz.x - content.x) / 2
		y_icon := (sz.y - COMPOUND_ICON) / 2
		y_text := (sz.y - text_h) / 2
		if has_icon && icon_position == .Before {
			icon(gtx, shown, {x, y_icon}, COMPOUND_ICON, f.ic)
			x += COMPOUND_ICON + tok.SPACING_HORIZONTAL_M
		}
		draw_text(gtx, t, {x, y_text}, f.fg)
		if secondary != "" {
			draw_text(gtx, s, {x, y_text + t.height}, sec_color)
		}
		if has_icon && icon_position == .After {
			icon(gtx, shown, {x + text_w + tok.SPACING_HORIZONTAL_M, y_icon}, COMPOUND_ICON, f.ic)
		}
	}
	frame_focus(gtx, f, appearance)
	listen(gtx, f.c.st, p.id, f.area)
	said := ui.frame_string(gtx, icon_only ? name : label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Button, label = said, description = secondary, states = design.state_if(f.c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - text_h) / 2 + baseline_of(t)})
	return f.c.clicked
}
