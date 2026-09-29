package material

import "core:math"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Common buttons, icon buttons, FABs, segmented and split buttons: M3's
// "Actions" group, on the M3 Expressive kit's specs (components/button,
// icon-button, fab, segmented-button and split-button.json). Every size,
// colour and shape is a comp token; the few values Compose hard-codes
// cite their source where they are used, as File.kt:line at androidx
// 1358a48, the commit the kit is read from.
//
// Motion: press morphs run on the fast-spatial spring, as foundations.json
// motion.springs assigns "button and icon-button press morphs". The
// component specs' pressed states name default-effects instead; that is
// the state-layer fade, and an effects spring cannot overshoot, which
// would flatten the Expressive squish, so foundations wins. Checked and
// expanded morphs use the spring each spec's own motion field names.
//
// Touch target: every control takes at least 48x48 of hit area centred on
// its visual (foundations.json interaction.touchTarget), extended past its
// laid-out size rather than growing it, so an x-small button still lays
// out 32 tall and neighbours may share the overhang.

// Button_Kind is jm:ui's own: the same M3 variants, one owner.
Button_Kind :: ui.Button_Kind

// Button_Size is the Expressive size scale shared by buttons, icon buttons
// and split buttons: one comp.*-{x-small,small,medium,large,x-large} token
// group each. Small is the default and M3's classic 40dp.
Button_Size :: enum u8 {
	X_Small,
	Small,
	Medium,
	Large,
	X_Large,
}

// Button_Shape is a button's resting silhouette: fully round, or the
// size's square corner. A checkable button morphs to the other when checked.
Button_Shape :: enum u8 {
	Round,
	Square,
}

// Button_Metrics are one size's dimensions and shapes (comp.button-<size>).
@(private)
Button_Metrics :: struct {
	height, leading, trailing: f32,
	icon, gap:                 f32, // icon size and icon-label space
	outline:                   f32, // outlined style's outline width
	round, square, pressed:    tok.Shape,
	checked_round:             tok.Shape, // checked shape of a round-resting toggle: square
	checked_square:            tok.Shape, // checked shape of a square-resting toggle: round
	role:                      Type_Role,
}

// button_metrics is size's comp.button-<size> group. The label type is
// not tokenized in the kit (no comp.button-*.label-text-font); it follows
// Compose's ButtonDefaults.textStyleFor(height): label-large up to small,
// then title-medium, headline-small and headline-large.
@(private)
button_metrics :: proc(size: Button_Size) -> Button_Metrics {
	switch size {
	case .X_Small:
		return {
			height = tok.BUTTON_X_SMALL_CONTAINER_HEIGHT,
			leading = tok.BUTTON_X_SMALL_LEADING_SPACE,
			trailing = tok.BUTTON_X_SMALL_TRAILING_SPACE,
			icon = tok.BUTTON_X_SMALL_ICON_SIZE,
			gap = 4, // Button.kt:1107-1108: hard-coded pending a fix to the x-small token
			outline = tok.BUTTON_X_SMALL_OUTLINED_OUTLINE_WIDTH,
			round = tok.BUTTON_X_SMALL_CONTAINER_SHAPE_ROUND,
			square = tok.BUTTON_X_SMALL_CONTAINER_SHAPE_SQUARE,
			pressed = tok.BUTTON_X_SMALL_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.BUTTON_X_SMALL_SELECTED_CONTAINER_SHAPE_SQUARE,
			checked_square = tok.BUTTON_X_SMALL_SELECTED_CONTAINER_SHAPE_ROUND,
			role = .Label_Large,
		}
	case .Small:
	case .Medium:
		return {
			height = tok.BUTTON_MEDIUM_CONTAINER_HEIGHT,
			leading = tok.BUTTON_MEDIUM_LEADING_SPACE,
			trailing = tok.BUTTON_MEDIUM_TRAILING_SPACE,
			icon = tok.BUTTON_MEDIUM_ICON_SIZE,
			gap = tok.BUTTON_MEDIUM_ICON_LABEL_SPACE,
			outline = tok.BUTTON_MEDIUM_OUTLINED_OUTLINE_WIDTH,
			round = tok.BUTTON_MEDIUM_CONTAINER_SHAPE_ROUND,
			square = tok.BUTTON_MEDIUM_CONTAINER_SHAPE_SQUARE,
			pressed = tok.BUTTON_MEDIUM_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.BUTTON_MEDIUM_SELECTED_CONTAINER_SHAPE_SQUARE,
			checked_square = tok.BUTTON_MEDIUM_SELECTED_CONTAINER_SHAPE_ROUND,
			role = .Title_Medium,
		}
	case .Large:
		return {
			height = tok.BUTTON_LARGE_CONTAINER_HEIGHT,
			leading = tok.BUTTON_LARGE_LEADING_SPACE,
			trailing = tok.BUTTON_LARGE_TRAILING_SPACE,
			icon = tok.BUTTON_LARGE_ICON_SIZE,
			gap = tok.BUTTON_LARGE_ICON_LABEL_SPACE,
			outline = tok.BUTTON_LARGE_OUTLINED_OUTLINE_WIDTH,
			round = tok.BUTTON_LARGE_CONTAINER_SHAPE_ROUND,
			square = tok.BUTTON_LARGE_CONTAINER_SHAPE_SQUARE,
			pressed = tok.BUTTON_LARGE_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.BUTTON_LARGE_SELECTED_CONTAINER_SHAPE_SQUARE,
			checked_square = tok.BUTTON_LARGE_SELECTED_CONTAINER_SHAPE_ROUND,
			role = .Headline_Small,
		}
	case .X_Large:
		return {
			height = tok.BUTTON_X_LARGE_CONTAINER_HEIGHT,
			leading = tok.BUTTON_X_LARGE_LEADING_SPACE,
			trailing = tok.BUTTON_X_LARGE_TRAILING_SPACE,
			icon = tok.BUTTON_X_LARGE_ICON_SIZE,
			gap = tok.BUTTON_X_LARGE_ICON_LABEL_SPACE,
			outline = tok.BUTTON_X_LARGE_OUTLINED_OUTLINE_WIDTH,
			round = tok.BUTTON_X_LARGE_CONTAINER_SHAPE_ROUND,
			square = tok.BUTTON_X_LARGE_CONTAINER_SHAPE_SQUARE,
			pressed = tok.BUTTON_X_LARGE_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.BUTTON_X_LARGE_SELECTED_CONTAINER_SHAPE_SQUARE,
			checked_square = tok.BUTTON_X_LARGE_SELECTED_CONTAINER_SHAPE_ROUND,
			role = .Headline_Large,
		}
	}
	return {
		height = tok.BUTTON_SMALL_CONTAINER_HEIGHT,
		leading = tok.BUTTON_SMALL_LEADING_SPACE,
		trailing = tok.BUTTON_SMALL_TRAILING_SPACE,
		icon = tok.BUTTON_SMALL_ICON_SIZE,
		gap = tok.BUTTON_SMALL_ICON_LABEL_SPACE,
		outline = tok.BUTTON_SMALL_OUTLINED_OUTLINE_WIDTH,
		round = tok.BUTTON_SMALL_CONTAINER_SHAPE_ROUND,
		square = tok.BUTTON_SMALL_CONTAINER_SHAPE_SQUARE,
		pressed = tok.BUTTON_SMALL_PRESSED_CONTAINER_SHAPE,
		checked_round = tok.BUTTON_SMALL_SELECTED_CONTAINER_SHAPE_SQUARE,
		checked_square = tok.BUTTON_SMALL_SELECTED_CONTAINER_SHAPE_ROUND,
		role = .Label_Large,
	}
}

// BUTTON_MIN_WIDTH is Compose's flat, untokenized minimum (Button.kt:1053).
@(private)
BUTTON_MIN_WIDTH :: f32(58)

// ICON_ONLY_LEADING is the leading padding of a button with an icon and no
// label, in place of the leading-space token (Button.kt:912,932).
@(private)
ICON_ONLY_LEADING :: f32(16)

// Button_Colors are one button kind's resolved colours and elevations.
@(private)
Button_Colors :: struct {
	container, content, outline: ui.Color,
	level, hover_level:          int, // elevation at rest and on hover
	focus_level, press_level:    int,
}

// button_colors is kind's enabled colours: plain, or with toggle its
// checked (on) or unchecked ones. Each style's hovered/focused/pressed
// colour tokens equal its enabled ones, so one content colour serves every
// state. The tonal toggle reads comp.tonal-button, not the plain tonal's
// comp.filled-tonal-button (button.json notes). Text has no toggle.
@(private)
button_colors :: proc(kind: Button_Kind, toggle := false, on := false) -> Button_Colors {
	col: Button_Colors
	switch kind {
	case .Filled:
		col = {
			container   = color(tok.FILLED_BUTTON_CONTAINER_COLOR),
			content     = color(tok.FILLED_BUTTON_LABEL_TEXT_COLOR),
			level       = elevation_level(tok.FILLED_BUTTON_CONTAINER_ELEVATION),
			hover_level = elevation_level(tok.FILLED_BUTTON_HOVERED_CONTAINER_ELEVATION),
			focus_level = elevation_level(tok.FILLED_BUTTON_FOCUSED_CONTAINER_ELEVATION),
			press_level = elevation_level(tok.FILLED_BUTTON_PRESSED_CONTAINER_ELEVATION),
		}
		if toggle {
			col.container = color(on ? tok.FILLED_BUTTON_SELECTED_CONTAINER_COLOR : tok.FILLED_BUTTON_UNSELECTED_CONTAINER_COLOR)
			col.content = color(on ? tok.FILLED_BUTTON_LABEL_TEXT_SELECTED_COLOR : tok.FILLED_BUTTON_LABEL_TEXT_UNSELECTED_COLOR)
		}
	case .Tonal:
		if toggle {
			col = {
				container   = color(on ? tok.TONAL_BUTTON_SELECTED_CONTAINER_COLOR : tok.TONAL_BUTTON_UNSELECTED_CONTAINER_COLOR),
				content     = color(on ? tok.TONAL_BUTTON_SELECTED_LABEL_TEXT_COLOR : tok.TONAL_BUTTON_UNSELECTED_LABEL_TEXT_COLOR),
				level       = elevation_level(tok.TONAL_BUTTON_CONTAINER_ELEVATION),
				hover_level = elevation_level(tok.TONAL_BUTTON_HOVERED_CONTAINER_ELEVATION),
				focus_level = elevation_level(tok.TONAL_BUTTON_FOCUSED_CONTAINER_ELEVATION),
				press_level = elevation_level(tok.TONAL_BUTTON_PRESSED_CONTAINER_ELEVATION),
			}
		} else {
			col = {
				container   = color(tok.FILLED_TONAL_BUTTON_CONTAINER_COLOR),
				content     = color(tok.FILLED_TONAL_BUTTON_LABEL_TEXT_COLOR),
				level       = elevation_level(tok.FILLED_TONAL_BUTTON_CONTAINER_ELEVATION),
				hover_level = elevation_level(tok.FILLED_TONAL_BUTTON_HOVER_CONTAINER_ELEVATION),
				focus_level = elevation_level(tok.FILLED_TONAL_BUTTON_FOCUS_CONTAINER_ELEVATION),
				press_level = elevation_level(tok.FILLED_TONAL_BUTTON_PRESSED_CONTAINER_ELEVATION),
			}
		}
	case .Outlined:
		// Checked, the outline gives way to an inverse-surface fill.
		col.content = color(tok.OUTLINED_BUTTON_LABEL_TEXT_COLOR)
		col.outline = color(tok.OUTLINED_BUTTON_OUTLINE_COLOR)
		if toggle && on {
			col.container = color(tok.OUTLINED_BUTTON_SELECTED_CONTAINER_COLOR)
			col.content = color(tok.OUTLINED_BUTTON_SELECTED_LABEL_TEXT_COLOR)
			col.outline = {}
		} else if toggle {
			col.content = color(tok.OUTLINED_BUTTON_UNSELECTED_LABEL_TEXT_COLOR)
		}
	case .Text:
		col.content = color(tok.TEXT_BUTTON_LABEL_COLOR)
	case .Elevated:
		col = {
			container   = color(tok.ELEVATED_BUTTON_CONTAINER_COLOR),
			content     = color(tok.ELEVATED_BUTTON_LABEL_TEXT_COLOR),
			level       = elevation_level(tok.ELEVATED_BUTTON_CONTAINER_ELEVATION),
			hover_level = elevation_level(tok.ELEVATED_BUTTON_HOVERED_CONTAINER_ELEVATION),
			focus_level = elevation_level(tok.ELEVATED_BUTTON_FOCUSED_CONTAINER_ELEVATION),
			press_level = elevation_level(tok.ELEVATED_BUTTON_PRESSED_CONTAINER_ELEVATION),
		}
		// The label tokens, not the icon ones, colour the icon too:
		// elevated-button.unselected-icon-color is on-primary, invisible on
		// its surface-container-low container, an upstream token slip.
		if toggle {
			col.container = color(on ? tok.ELEVATED_BUTTON_SELECTED_CONTAINER_COLOR : tok.ELEVATED_BUTTON_UNSELECTED_CONTAINER_COLOR)
			col.content = color(on ? tok.ELEVATED_BUTTON_LABEL_TEXT_SELECTED_COLOR : tok.ELEVATED_BUTTON_LABEL_TEXT_UNSELECTED_COLOR)
		}
	}
	return col
}

// button_disabled_colors is kind's disabled colours: each style's own
// disabled-* colour and opacity tokens, nothing layered on top. The
// outlined outline has a disabled colour token and no opacity one, so it
// paints at full strength.
@(private)
button_disabled_colors :: proc(kind: Button_Kind, toggle := false, on := false) -> (container, content, outline: ui.Color) {
	switch kind {
	case .Filled:
		container = ui.with_alpha(color(tok.FILLED_BUTTON_DISABLED_CONTAINER_COLOR), tok.FILLED_BUTTON_DISABLED_CONTAINER_OPACITY)
		content = ui.with_alpha(color(tok.FILLED_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.FILLED_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
	case .Tonal:
		if toggle {
			container = ui.with_alpha(color(tok.TONAL_BUTTON_DISABLED_CONTAINER_COLOR), tok.TONAL_BUTTON_DISABLED_CONTAINER_OPACITY)
			content = ui.with_alpha(color(tok.TONAL_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.TONAL_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
		} else {
			container = ui.with_alpha(color(tok.FILLED_TONAL_BUTTON_DISABLED_CONTAINER_COLOR), tok.FILLED_TONAL_BUTTON_DISABLED_CONTAINER_OPACITY)
			content = ui.with_alpha(color(tok.FILLED_TONAL_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.FILLED_TONAL_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
		}
	case .Outlined:
		if toggle && on {
			container = ui.with_alpha(color(tok.OUTLINED_BUTTON_SELECTED_DISABLED_CONTAINER_COLOR), tok.OUTLINED_BUTTON_DISABLED_CONTAINER_OPACITY)
		} else {
			outline = color(toggle ? tok.OUTLINED_BUTTON_UNSELECTED_DISABLED_OUTLINE_COLOR : tok.OUTLINED_BUTTON_DISABLED_OUTLINE_COLOR)
		}
		content = ui.with_alpha(color(tok.OUTLINED_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.OUTLINED_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
	case .Text:
		content = ui.with_alpha(color(tok.TEXT_BUTTON_DISABLED_LABEL_COLOR), tok.TEXT_BUTTON_DISABLED_LABEL_OPACITY)
	case .Elevated:
		container = ui.with_alpha(color(tok.ELEVATED_BUTTON_DISABLED_CONTAINER_COLOR), tok.ELEVATED_BUTTON_DISABLED_CONTAINER_OPACITY)
		content = ui.with_alpha(color(tok.ELEVATED_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.ELEVATED_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
	}
	return
}

// button_elevation is col's elevation for c's state: pressed, then hovered,
// then focused; 0 when disabled (the disabled-container-elevation tokens).
@(private)
button_elevation :: proc(col: Button_Colors, c: Control) -> int {
	switch {
	case c.disabled:
		return 0
	case c.pressed:
		return col.press_level
	case c.hovered:
		return col.hover_level
	case c.focused:
		return col.focus_level
	}
	return col.level
}

// button is one of M3's five common buttons (button.json): size picks the
// comp.button-<size> group (height, padding, icon size and gap, outline
// width, label type) and shape the round or square resting silhouette,
// which morphs to the size's pressed shape on press. leading and trailing
// are optional icons; Expressive favours one or the other. With checked
// non-nil it is a toggle button (Compose ToggleButton): a click flips
// checked^, and it paints the style's checked or unchecked colours and
// morphs to the other resting shape when checked. .Text has no toggle, so
// it ignores checked. Returns true on the frame it is clicked, or activated
// by Enter/Space while focused.
//
// Departures: the precision-pointer overrides (36dp small height, 8dp
// vertical and 12dp leading padding, Button.kt:1059-1065,1652-1656) are
// not applied, as jm:ui does not say whether input is a mouse or a finger;
// and the toggle's checkbox role has no jm:ui semantics to carry it.
button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	kind := Button_Kind.Filled,
	leading := Icon.None,
	size := Button_Size.Small,
	shape := Button_Shape.Round,
	trailing := Icon.None,
	checked: ^bool = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	mt := button_metrics(size)
	t := shape_text(gtx, label, mt.role)
	lead := label == "" && leading != .None ? ICON_ONLY_LEADING : mt.leading
	w := lead + t.width + mt.trailing
	if leading != .None {
		w += mt.icon + (label == "" ? 0 : mt.gap)
	}
	if trailing != .None {
		w += mt.icon + (label == "" ? 0 : mt.gap)
	}
	sz := ui.constrain_min(gtx.constraints, {max(w, BUTTON_MIN_WIDTH), mt.height})
	area := ui.Rect{0, 0, sz.x, sz.y}
	hit := touch_target(area)

	c := control(gtx, p.id, hit, state)
	toggle := checked != nil && kind != .Text
	if c.clicked && toggle {
		checked^ = !checked^
	}
	on := toggle && checked^
	rest, checked_shape := mt.round, mt.checked_round
	if shape == .Square {
		rest, checked_shape = mt.square, mt.checked_square
	}
	// Slot 0 is the press morph, slot 1 the checked morph (button.json
	// states: checked on fast-spatial).
	tp := animate(gtx, c, 0, c.pressed ? 1 : 0, .Fast_Spatial)
	tc := animate(gtx, c, 1, on ? 1 : 0, .Fast_Spatial)
	k := lerp_corners(lerp_corners(corners(rest, area), corners(checked_shape, area), tc), corners(mt.pressed, area), tp)
	path := rounded(gtx, area, k)

	col := button_colors(kind, toggle, on)
	container, content, outline := col.container, col.content, col.outline
	level := button_elevation(col, c)
	if c.disabled {
		container, content, outline = button_disabled_colors(kind, toggle, on)
	}
	if ui.painted(container) {
		paint_elevation(gtx, {area, k.tl}, level)
		ui.fill(gtx.ops, path, container)
	}
	if ui.painted(outline) {
		stroke_inside_corners(gtx, area, k, outline, mt.outline)
	}
	paint_state_layer(gtx, c, path, col.content)
	x := (sz.x - w) / 2 + lead
	if leading != .None {
		icon(gtx, leading, {x, (sz.y - mt.icon) / 2}, mt.icon, content)
		x += mt.icon + (label == "" ? 0 : mt.gap)
	}
	draw_text(gtx, t, {x, (sz.y - t.height) / 2}, content)
	x += t.width
	if trailing != .None {
		x += label == "" ? 0 : mt.gap
		icon(gtx, trailing, {x, (sz.y - mt.icon) / 2}, mt.icon, content)
	}
	paint_focus_ring_corners(gtx, c, area, k)
	listen(gtx, c, p.id, hit)
	ui.tag(gtx.ops, p.id, ui.frame_string(gtx, label))
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked
}

// Icon_Button_Kind is an icon button's colour style.
Icon_Button_Kind :: enum u8 {
	Standard,
	Filled,
	Tonal,
	Outlined,
}

// Icon_Button_Width is the Expressive width option, independent of size:
// the container is icon-size plus that option's leading and trailing space.
Icon_Button_Width :: enum u8 {
	Uniform,
	Narrow,
	Wide,
}

// Icon_Button_Metrics are one size and width's dimensions and shapes.
@(private)
Icon_Button_Metrics :: struct {
	height, icon, leading, trailing, outline: f32,
	round, square, pressed:                   tok.Shape,
	checked_round, checked_square:            tok.Shape,
}

// icon_button_metrics is the comp.<size>-icon-button group at width. The
// uniform option reads default-*-space, or uniform-*-space at large, where
// the kit names the same thing differently. The group's own
// selected-container-shape-round is the checked shape of a round button,
// and it is square: a toggle morphs to the other silhouette.
@(private)
icon_button_metrics :: proc(size: Button_Size, width: Icon_Button_Width) -> (m: Icon_Button_Metrics) {
	lead, trail: [Icon_Button_Width]f32
	switch size {
	case .X_Small:
		m = {
			height = tok.X_SMALL_ICON_BUTTON_CONTAINER_HEIGHT,
			icon = tok.X_SMALL_ICON_BUTTON_ICON_SIZE,
			outline = tok.X_SMALL_ICON_BUTTON_OUTLINED_OUTLINE_WIDTH,
			round = tok.X_SMALL_ICON_BUTTON_CONTAINER_SHAPE_ROUND,
			square = tok.X_SMALL_ICON_BUTTON_CONTAINER_SHAPE_SQUARE,
			pressed = tok.X_SMALL_ICON_BUTTON_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.X_SMALL_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_ROUND,
			checked_square = tok.X_SMALL_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_SQUARE,
		}
		lead = {.Uniform = tok.X_SMALL_ICON_BUTTON_DEFAULT_LEADING_SPACE, .Narrow = tok.X_SMALL_ICON_BUTTON_NARROW_LEADING_SPACE, .Wide = tok.X_SMALL_ICON_BUTTON_WIDE_LEADING_SPACE}
		trail = {.Uniform = tok.X_SMALL_ICON_BUTTON_DEFAULT_TRAILING_SPACE, .Narrow = tok.X_SMALL_ICON_BUTTON_NARROW_TRAILING_SPACE, .Wide = tok.X_SMALL_ICON_BUTTON_WIDE_TRAILING_SPACE}
	case .Small:
		m = {
			height = tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT,
			icon = tok.SMALL_ICON_BUTTON_ICON_SIZE,
			outline = tok.SMALL_ICON_BUTTON_OUTLINED_OUTLINE_WIDTH,
			round = tok.SMALL_ICON_BUTTON_CONTAINER_SHAPE_ROUND,
			square = tok.SMALL_ICON_BUTTON_CONTAINER_SHAPE_SQUARE,
			pressed = tok.SMALL_ICON_BUTTON_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.SMALL_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_ROUND,
			checked_square = tok.SMALL_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_SQUARE,
		}
		lead = {.Uniform = tok.SMALL_ICON_BUTTON_DEFAULT_LEADING_SPACE, .Narrow = tok.SMALL_ICON_BUTTON_NARROW_LEADING_SPACE, .Wide = tok.SMALL_ICON_BUTTON_WIDE_LEADING_SPACE}
		trail = {.Uniform = tok.SMALL_ICON_BUTTON_DEFAULT_TRAILING_SPACE, .Narrow = tok.SMALL_ICON_BUTTON_NARROW_TRAILING_SPACE, .Wide = tok.SMALL_ICON_BUTTON_WIDE_TRAILING_SPACE}
	case .Medium:
		m = {
			height = tok.MEDIUM_ICON_BUTTON_CONTAINER_HEIGHT,
			icon = tok.MEDIUM_ICON_BUTTON_ICON_SIZE,
			outline = tok.MEDIUM_ICON_BUTTON_OUTLINED_OUTLINE_WIDTH,
			round = tok.MEDIUM_ICON_BUTTON_CONTAINER_SHAPE_ROUND,
			square = tok.MEDIUM_ICON_BUTTON_CONTAINER_SHAPE_SQUARE,
			pressed = tok.MEDIUM_ICON_BUTTON_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.MEDIUM_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_ROUND,
			checked_square = tok.MEDIUM_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_SQUARE,
		}
		lead = {.Uniform = tok.MEDIUM_ICON_BUTTON_DEFAULT_LEADING_SPACE, .Narrow = tok.MEDIUM_ICON_BUTTON_NARROW_LEADING_SPACE, .Wide = tok.MEDIUM_ICON_BUTTON_WIDE_LEADING_SPACE}
		trail = {.Uniform = tok.MEDIUM_ICON_BUTTON_DEFAULT_TRAILING_SPACE, .Narrow = tok.MEDIUM_ICON_BUTTON_NARROW_TRAILING_SPACE, .Wide = tok.MEDIUM_ICON_BUTTON_WIDE_TRAILING_SPACE}
	case .Large:
		m = {
			height = tok.LARGE_ICON_BUTTON_CONTAINER_HEIGHT,
			icon = tok.LARGE_ICON_BUTTON_ICON_SIZE,
			outline = tok.LARGE_ICON_BUTTON_OUTLINED_OUTLINE_WIDTH,
			round = tok.LARGE_ICON_BUTTON_CONTAINER_SHAPE_ROUND,
			square = tok.LARGE_ICON_BUTTON_CONTAINER_SHAPE_SQUARE,
			pressed = tok.LARGE_ICON_BUTTON_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.LARGE_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_ROUND,
			checked_square = tok.LARGE_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_SQUARE,
		}
		lead = {.Uniform = tok.LARGE_ICON_BUTTON_UNIFORM_LEADING_SPACE, .Narrow = tok.LARGE_ICON_BUTTON_NARROW_LEADING_SPACE, .Wide = tok.LARGE_ICON_BUTTON_WIDE_LEADING_SPACE}
		trail = {.Uniform = tok.LARGE_ICON_BUTTON_UNIFORM_TRAILING_SPACE, .Narrow = tok.LARGE_ICON_BUTTON_NARROW_TRAILING_SPACE, .Wide = tok.LARGE_ICON_BUTTON_WIDE_TRAILING_SPACE}
	case .X_Large:
		m = {
			height = tok.X_LARGE_ICON_BUTTON_CONTAINER_HEIGHT,
			icon = tok.X_LARGE_ICON_BUTTON_ICON_SIZE,
			outline = tok.X_LARGE_ICON_BUTTON_OUTLINED_OUTLINE_WIDTH,
			round = tok.X_LARGE_ICON_BUTTON_CONTAINER_SHAPE_ROUND,
			square = tok.X_LARGE_ICON_BUTTON_CONTAINER_SHAPE_SQUARE,
			pressed = tok.X_LARGE_ICON_BUTTON_PRESSED_CONTAINER_SHAPE,
			checked_round = tok.X_LARGE_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_ROUND,
			checked_square = tok.X_LARGE_ICON_BUTTON_SELECTED_CONTAINER_SHAPE_SQUARE,
		}
		lead = {.Uniform = tok.X_LARGE_ICON_BUTTON_DEFAULT_LEADING_SPACE, .Narrow = tok.X_LARGE_ICON_BUTTON_NARROW_LEADING_SPACE, .Wide = tok.X_LARGE_ICON_BUTTON_WIDE_LEADING_SPACE}
		trail = {.Uniform = tok.X_LARGE_ICON_BUTTON_DEFAULT_TRAILING_SPACE, .Narrow = tok.X_LARGE_ICON_BUTTON_NARROW_TRAILING_SPACE, .Wide = tok.X_LARGE_ICON_BUTTON_WIDE_TRAILING_SPACE}
	}
	m.leading, m.trailing = lead[width], trail[width]
	return
}

// icon_button_colors is kind's colours, plain or (with toggle) checked or
// unchecked, enabled or disabled. Every style's hovered/focused/pressed
// colour token equals its enabled one.
@(private)
icon_button_colors :: proc(kind: Icon_Button_Kind, toggle, on, disabled: bool) -> (container, content, outline: ui.Color) {
	switch kind {
	case .Standard:
		content = color(!toggle ? tok.STANDARD_ICON_BUTTON_COLOR : on ? tok.STANDARD_ICON_BUTTON_SELECTED_COLOR : tok.STANDARD_ICON_BUTTON_UNSELECTED_COLOR)
		if disabled {
			content = ui.with_alpha(color(tok.STANDARD_ICON_BUTTON_DISABLED_COLOR), tok.STANDARD_ICON_BUTTON_DISABLED_OPACITY)
		}
	case .Filled:
		container = color(!toggle ? tok.FILLED_ICON_BUTTON_CONTAINER_COLOR : on ? tok.FILLED_ICON_BUTTON_SELECTED_CONTAINER_COLOR : tok.FILLED_ICON_BUTTON_UNSELECTED_CONTAINER_COLOR)
		content = color(!toggle ? tok.FILLED_ICON_BUTTON_COLOR : on ? tok.FILLED_ICON_BUTTON_SELECTED_COLOR : tok.FILLED_ICON_BUTTON_UNSELECTED_COLOR)
		if disabled {
			container = ui.with_alpha(color(tok.FILLED_ICON_BUTTON_DISABLED_CONTAINER_COLOR), tok.FILLED_ICON_BUTTON_DISABLED_CONTAINER_OPACITY)
			content = ui.with_alpha(color(tok.FILLED_ICON_BUTTON_DISABLED_COLOR), tok.FILLED_ICON_BUTTON_DISABLED_OPACITY)
		}
	case .Tonal:
		container = color(!toggle ? tok.FILLED_TONAL_ICON_BUTTON_CONTAINER_COLOR : on ? tok.FILLED_TONAL_ICON_BUTTON_SELECTED_CONTAINER_COLOR : tok.FILLED_TONAL_ICON_BUTTON_UNSELECTED_CONTAINER_COLOR)
		content = color(!toggle ? tok.FILLED_TONAL_ICON_BUTTON_COLOR : on ? tok.FILLED_TONAL_ICON_BUTTON_SELECTED_COLOR : tok.FILLED_TONAL_ICON_BUTTON_UNSELECTED_COLOR)
		if disabled {
			container = ui.with_alpha(color(tok.FILLED_TONAL_ICON_BUTTON_DISABLED_CONTAINER_COLOR), tok.FILLED_TONAL_ICON_BUTTON_DISABLED_CONTAINER_OPACITY)
			content = ui.with_alpha(color(tok.FILLED_TONAL_ICON_BUTTON_DISABLED_COLOR), tok.FILLED_TONAL_ICON_BUTTON_DISABLED_OPACITY)
		}
	case .Outlined:
		// Checked, the outline gives way to an inverse-surface fill. The
		// disabled outline takes the disabled opacity too (icon-button.json
		// states.disabled).
		if on {
			container = color(tok.OUTLINED_ICON_BUTTON_SELECTED_CONTAINER_COLOR)
			content = color(tok.OUTLINED_ICON_BUTTON_SELECTED_COLOR)
			if disabled {
				container = ui.with_alpha(color(tok.OUTLINED_ICON_BUTTON_SELECTED_DISABLED_CONTAINER_COLOR), tok.OUTLINED_ICON_BUTTON_SELECTED_DISABLED_CONTAINER_OPACITY)
			}
		} else {
			content = color(toggle ? tok.OUTLINED_ICON_BUTTON_UNSELECTED_COLOR : tok.OUTLINED_ICON_BUTTON_COLOR)
			outline = color(toggle ? tok.OUTLINED_ICON_BUTTON_UNSELECTED_OUTLINE_COLOR : tok.OUTLINED_ICON_BUTTON_OUTLINE_COLOR)
			if disabled {
				dis := toggle ? tok.OUTLINED_ICON_BUTTON_UNSELECTED_DISABLED_OUTLINE_COLOR : tok.OUTLINED_ICON_BUTTON_DISABLED_OUTLINE_COLOR
				outline = ui.with_alpha(color(dis), tok.OUTLINED_ICON_BUTTON_DISABLED_OPACITY)
			}
		}
		if disabled {
			content = ui.with_alpha(color(tok.OUTLINED_ICON_BUTTON_DISABLED_COLOR), tok.OUTLINED_ICON_BUTTON_DISABLED_OPACITY)
		}
	}
	return
}

// Tooltip_Timer is how long an icon button has been hovered, for its
// tooltip: its own widget_data, not a borrowed Widget_State field.
@(private)
Tooltip_Timer :: struct {
	seconds: f32,
}

// icon_button is M3's icon button (icon-button.json): size picks the
// comp.<size>-icon-button group (height, icon size, outline width), width
// the narrow, uniform or wide spacing either side of the icon, and shape
// the round or square resting silhouette, which morphs to the size's
// pressed shape on press. With selected nil it is a plain action; with
// selected non-nil it is a toggle, flipped on click, painting the checked
// colours (and selected_icon, when given) while selected^ is true, and
// morphing to the size's selected shape. tooltip, when set, shows as a
// plain tooltip under it while hovered. Returns true on
// the frame it was activated.
//
// content is the ambient content colour a plain standard or outlined icon
// button inherits in Compose (LocalContentColor): pass the colour of the
// surface it sits on, such as an app bar's. Zero paints the style's colour
// token, which is Compose's vibrant variant; jm:ui has no ambient colour.
icon_button :: proc(
	gtx: ^ui.Ctx,
	glyph: Icon,
	kind := Icon_Button_Kind.Standard,
	selected: ^bool = nil,
	selected_icon := Icon.None,
	tooltip := "",
	size := Button_Size.Small,
	width := Icon_Button_Width.Uniform,
	shape := Button_Shape.Round,
	content := ui.Color{},
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	mt := icon_button_metrics(size, width)
	sz := ui.constrain_min(gtx.constraints, {mt.leading + mt.icon + mt.trailing, mt.height})
	area := ui.Rect{0, 0, sz.x, sz.y}
	hit := touch_target(area)
	c := control(gtx, p.id, hit, state)
	if c.clicked && selected != nil {
		selected^ = !selected^
	}
	toggle := selected != nil
	on := toggle && selected^

	rest, checked_shape := mt.round, mt.checked_round
	if shape == .Square {
		rest, checked_shape = mt.square, mt.checked_square
	}
	// Slot 0 is the press morph; slot 1 the checked morph, which
	// icon-button.json puts on default-effects.
	tp := animate(gtx, c, 0, c.pressed ? 1 : 0, .Fast_Spatial)
	tc := animate(gtx, c, 1, on ? 1 : 0, .Default_Effects)
	k := lerp_corners(lerp_corners(corners(rest, area), corners(checked_shape, area), tc), corners(mt.pressed, area), tp)
	path := rounded(gtx, area, k)

	container, fg, outline := icon_button_colors(kind, toggle, on, false)
	if !toggle && ui.painted(content) && (kind == .Standard || kind == .Outlined) {
		fg = content
	}
	layer_color := fg
	if c.disabled {
		container, fg, outline = icon_button_colors(kind, toggle, on, true)
	}
	if ui.painted(container) {
		ui.fill(gtx.ops, path, container)
	}
	if ui.painted(outline) {
		stroke_inside_corners(gtx, area, k, outline, mt.outline)
	}
	paint_state_layer(gtx, c, path, layer_color)
	g := on && selected_icon != .None ? selected_icon : glyph
	icon(gtx, g, {(sz.x - mt.icon) / 2, (sz.y - mt.icon) / 2}, mt.icon, fg)
	paint_focus_ring_corners(gtx, c, area, k)
	listen(gtx, c, p.id, hit)
	if c.st != nil {
		hover_tooltip(gtx, c.st.hovered, &ui.widget_data(gtx, p.id, Tooltip_Timer).seconds, tooltip, sz)
	}
	ui.tag(gtx.ops, p.id, ui.frame_string(gtx, tooltip != "" ? tooltip : "icon_button"))
	ui.widget_close(gtx, &p, {size = sz})
	return c.clicked
}

// Fab_Size is a FAB's size group: comp.fab-small, -baseline (Regular),
// -medium (new in Expressive) and -large. It is material's own rather than
// an alias of ui.Fab_Size, which has no Medium; the shared names keep
// callers of the old alias compiling.
Fab_Size :: enum u8 {
	Small,
	Regular,
	Medium,
	Large,
}

// Fab_Color is a FAB's container colour role. fab.json names primary,
// secondary and tertiary; Surface is not among them and stays only for
// callers of the old enum.
Fab_Color :: enum u8 {
	Primary_Container,
	Secondary_Container,
	Tertiary_Container,
	Surface,
}

// fab_colors is color's container and content. Tertiary has no token
// group (fab.json variants): it is the tertiary-container pair.
@(private)
fab_colors :: proc(c: Fab_Color) -> (container, content: ui.Color) {
	switch c {
	case .Primary_Container:
		return color(tok.FAB_PRIMARY_CONTAINER_CONTAINER_COLOR), color(tok.FAB_PRIMARY_CONTAINER_ICON_COLOR)
	case .Secondary_Container:
		return color(tok.FAB_SECONDARY_CONTAINER_CONTAINER_COLOR), color(tok.FAB_SECONDARY_CONTAINER_ICON_COLOR)
	case .Tertiary_Container:
		return color(.Tertiary_Container), color(.On_Tertiary_Container)
	case .Surface:
		return color(.Surface_Container_High), color(.Primary)
	}
	return {}, {}
}

// fab_level is the FAB's elevation level for c's state (fab.json states):
// comp.fab-primary-container's, or with lowered level 1, rising to 2 on
// hover. Every colour role shares the primary group's elevations: Compose
// reads no comp.fab-secondary-container token (FloatingActionButton.kt:131-138).
@(private)
fab_level :: proc(c: Control, lowered: bool) -> int {
	if lowered {
		return elevation_level(c.hovered && !c.pressed ? tok.SYS_ELEVATION_LEVEL2 : tok.SYS_ELEVATION_LEVEL1)
	}
	switch {
	case c.pressed:
		return elevation_level(tok.FAB_PRIMARY_CONTAINER_PRESSED_CONTAINER_ELEVATION)
	case c.hovered:
		return elevation_level(tok.FAB_PRIMARY_CONTAINER_HOVERED_CONTAINER_ELEVATION)
	case c.focused:
		return elevation_level(tok.FAB_PRIMARY_CONTAINER_FOCUSED_CONTAINER_ELEVATION)
	}
	return elevation_level(tok.FAB_PRIMARY_CONTAINER_CONTAINER_ELEVATION)
}

// fab_metrics is size's container, icon size and shape (fab.json layout).
// Medium has no shape token: Compose hard-codes the large-increased
// corner (FloatingActionButton.kt:1022). Large's icon is Compose's 36dp
// (FloatingActionButton.kt:1010); fab.json notes comp.fab-large.icon-size
// (32) as stale.
@(private)
fab_metrics :: proc(size: Fab_Size) -> (box: ui.Size, icon_size: f32, sh: tok.Shape) {
	switch size {
	case .Small:
		return {tok.FAB_SMALL_CONTAINER_WIDTH, tok.FAB_SMALL_CONTAINER_HEIGHT}, tok.FAB_SMALL_ICON_SIZE, tok.FAB_SMALL_CONTAINER_SHAPE
	case .Regular:
	case .Medium:
		r := CORNER_LARGE_INCREASED // FloatingActionButton.kt:1022
		return {tok.FAB_MEDIUM_CONTAINER_WIDTH, tok.FAB_MEDIUM_CONTAINER_HEIGHT}, tok.FAB_MEDIUM_ICON_SIZE, {radii = {r, r, r, r}}
	case .Large:
		return {tok.FAB_LARGE_CONTAINER_WIDTH, tok.FAB_LARGE_CONTAINER_HEIGHT}, 36, tok.FAB_LARGE_CONTAINER_SHAPE // 36: FloatingActionButton.kt:1010
	}
	return {tok.FAB_BASELINE_CONTAINER_WIDTH, tok.FAB_BASELINE_CONTAINER_HEIGHT}, tok.FAB_BASELINE_ICON_SIZE, tok.FAB_BASELINE_CONTAINER_SHAPE
}

// fab is M3's floating action button (fab.json): size picks the small,
// baseline, medium or large group, color the container role, and lowered
// the lower elevation set for less prominent placements. The container
// sits at elevation level 3, rising to 4 on hover. A FAB has no disabled
// state, so a forced Disabled paints as Enabled. The small FAB takes a
// 48dp touch target around its 40dp container.
fab :: proc(
	gtx: ^ui.Ctx,
	glyph: Icon,
	size := Fab_Size.Regular,
	color := Fab_Color.Primary_Container,
	lowered := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	box, isz, sh := fab_metrics(size)
	sz := ui.constrain_min(gtx.constraints, box)
	area := ui.Rect{0, 0, sz.x, sz.y}
	hit := touch_target(area)
	st := state == .Disabled ? Interaction.Enabled : state
	c := control(gtx, p.id, hit, st)
	container, content := fab_colors(color)
	k := corners(sh, area)
	path := rounded(gtx, area, k)
	paint_elevation(gtx, {area, k.tl}, fab_level(c, lowered))
	ui.fill(gtx.ops, path, container)
	paint_state_layer(gtx, c, path, content)
	icon(gtx, glyph, {(sz.x - isz) / 2, (sz.y - isz) / 2}, isz, content)
	paint_focus_ring_corners(gtx, c, area, k)
	listen(gtx, c, p.id, hit)
	ui.tag(gtx.ops, p.id, ui.frame_string(gtx, "fab"))
	ui.widget_close(gtx, &p, {size = sz})
	return c.clicked
}

// Extended_Fab_Size is an extended FAB's size: Generic is Compose's unsized
// ExtendedFloatingActionButton (comp.extended-fab-primary, baseline
// height); Small, Medium and Large are comp.extended-fab-<size>.
Extended_Fab_Size :: enum u8 {
	Generic,
	Small,
	Medium,
	Large,
}

// extended_fab is a FAB with a label after the icon (fab.json). Generic
// lays out 16 before the icon, 12 between, 20 after the label, at least
// 80 wide, in label-large; the sized ones take their group's height,
// padding and shape, with title-medium, title-large and headline-small
// labels. With expanded false it collapses to the square FAB: the width
// springs on fast-spatial while the label fades on fast-effects (the
// sized pairing; fab.json notes to pick one). A label-only generic FAB
// has 20 either side and never collapses. Like fab it has no disabled
// state, and lowered picks the lower elevation set.
extended_fab :: proc(
	gtx: ^ui.Ctx,
	glyph: Icon,
	label: string,
	color := Fab_Color.Primary_Container,
	size := Extended_Fab_Size.Generic,
	expanded := true,
	lowered := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	h, lead, trail, gap, isz, min_w, collapsed: f32
	sh: tok.Shape
	font: tok.Type_Style
	switch size {
	case .Generic:
		// FloatingActionButton.kt:898-913,1471-1482: padding and minimum
		// width exist only in code; collapsed is the baseline FAB.
		h, lead, gap, trail, min_w = tok.EXTENDED_FAB_PRIMARY_CONTAINER_HEIGHT, 16, 12, 20, 80
		isz, sh, font = tok.EXTENDED_FAB_PRIMARY_ICON_SIZE, tok.EXTENDED_FAB_PRIMARY_CONTAINER_SHAPE, tok.EXTENDED_FAB_PRIMARY_LABEL_TEXT_FONT
		collapsed = tok.FAB_BASELINE_CONTAINER_WIDTH
		if glyph == .None {
			lead = 20 // label only: FloatingActionButton.kt:620-625
		}
	case .Small:
		h, lead, trail, gap = tok.EXTENDED_FAB_SMALL_CONTAINER_HEIGHT, tok.EXTENDED_FAB_SMALL_LEADING_SPACE, tok.EXTENDED_FAB_SMALL_TRAILING_SPACE, tok.EXTENDED_FAB_SMALL_ICON_LABEL_SPACE
		isz, sh, font = tok.EXTENDED_FAB_SMALL_ICON_SIZE, tok.EXTENDED_FAB_SMALL_CONTAINER_SHAPE, TYPE_STYLES[.Title_Medium]
	case .Medium:
		r := CORNER_LARGE_INCREASED // no shape token: FloatingActionButton.kt:1037
		h, lead, trail, gap = tok.EXTENDED_FAB_MEDIUM_CONTAINER_HEIGHT, tok.EXTENDED_FAB_MEDIUM_LEADING_SPACE, tok.EXTENDED_FAB_MEDIUM_TRAILING_SPACE, 12 // 12, not the token: FloatingActionButton.kt:1454-1456
		isz, sh, font = tok.EXTENDED_FAB_MEDIUM_ICON_SIZE, {radii = {r, r, r, r}}, TYPE_STYLES[.Title_Large]
	case .Large:
		h, lead, trail, gap = tok.EXTENDED_FAB_LARGE_CONTAINER_HEIGHT, tok.EXTENDED_FAB_LARGE_LEADING_SPACE, tok.EXTENDED_FAB_LARGE_TRAILING_SPACE, 16 // 16, not the token: FloatingActionButton.kt:1467-1469
		isz, sh, font = tok.EXTENDED_FAB_LARGE_ICON_SIZE, tok.EXTENDED_FAB_LARGE_CONTAINER_SHAPE, TYPE_STYLES[.Headline_Small]
	}
	if size != .Generic {
		min_w, collapsed = h, h // a sized FAB's minimum is its height square
	}
	t := shape_style(gtx, label, font)
	full := lead + t.width + trail
	if glyph != .None {
		full += isz + gap
	}
	full = max(full, min_w)
	can_collapse := glyph != .None
	target_w := expanded || !can_collapse ? full : collapsed
	st := state == .Disabled ? Interaction.Enabled : state
	c := control(gtx, p.id, touch_target({0, 0, target_w, h}), st)
	// Slot 0 is the width, slot 1 the label's alpha.
	te, alpha: f32 = 1, 1
	if can_collapse {
		te = animate(gtx, c, 0, expanded ? 1 : 0, .Fast_Spatial)
		alpha = animate(gtx, c, 1, expanded ? 1 : 0, .Fast_Effects)
	}
	sz := ui.constrain_min(gtx.constraints, {max(collapsed + (full - collapsed) * te, 0), h})
	area := ui.Rect{0, 0, sz.x, sz.y}
	container, content := fab_colors(color)
	k := corners(sh, area)
	path := rounded(gtx, area, k)
	paint_elevation(gtx, {area, k.tl}, fab_level(c, lowered))
	ui.fill(gtx.ops, path, container)
	paint_state_layer(gtx, c, path, content)
	ui.clip_push(gtx.ops, path)
	// Collapsed, the icon centres in the square; expanded it sits at lead.
	// The two agree for every size (the square's margin is lead), so this
	// lerp only matters if a caller stretches the FAB.
	x := (collapsed - isz) / 2 + (lead - (collapsed - isz) / 2) * te
	if glyph != .None {
		icon(gtx, glyph, {x, (sz.y - isz) / 2}, isz, content)
		x += isz + gap
	} else {
		x = (sz.x - t.width) / 2
	}
	if alpha > 0 {
		draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fade(content, alpha))
	}
	ui.clip_pop(gtx.ops)
	paint_focus_ring_corners(gtx, c, area, k)
	listen(gtx, c, p.id, touch_target(area))
	ui.tag(gtx.ops, p.id, ui.frame_string(gtx, label))
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked
}

// SEGMENT_PADDING is a segment's start and end padding, hard-coded in
// Compose with no token (SegmentedButton.kt:617-622).
@(private)
SEGMENT_PADDING :: f32(12)

// segmented_button is M3's outlined segmented button (segmented-button.json):
// one outline around len(labels) segments, the outer two rounded, with
// dividers between. A selected segment fills with secondary-container and
// its check icon scales in from its bottom-left on fast-spatial and fades
// in on default-effects, sliding the label over. selected is caller-owned,
// one bool per label; the clicked segment is flipped and its index
// returned (-1 if none), and single makes it single-select by clearing the
// others, which Compose leaves to the caller (SegmentedButton.kt:210-253).
// state forces every segment at once.
//
// Deprecated in Expressive: segmented-button.json's deprecated.replacedBy
// is button-group (mdc:ToggleButtonGroup.md), here button_group's
// connected variant. Not done: arrow keys moving a single-select row's selection, and custom
// active/inactive icons; jm:ui has no radio-group focus model to hang them on.
segmented_button :: proc(
	gtx: ^ui.Ctx,
	labels: []string,
	selected: []bool,
	single := true,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	p := ui.widget_open(gtx, key, loc)
	n := min(len(labels), len(selected))
	changed := -1
	if n == 0 {
		ui.widget_close(gtx, &p, {})
		return changed
	}
	ICON :: tok.OUTLINED_SEGMENTED_BUTTON_ICON_SIZE
	GAP :: tok.BUTTON_SMALL_ICON_LABEL_SPACE // the common button's icon-label space
	LINE :: tok.OUTLINED_SEGMENTED_BUTTON_OUTLINE_WIDTH
	texts := make([]Text, n, gtx.allocator)
	widths := make([]f32, n, gtx.allocator)
	total: f32
	for i in 0 ..< n {
		texts[i] = shape_style(gtx, labels[i], tok.OUTLINED_SEGMENTED_BUTTON_LABEL_TEXT_FONT)
		widths[i] = max(SEGMENT_PADDING + ICON + GAP + texts[i].width + SEGMENT_PADDING, BUTTON_MIN_WIDTH)
		total += widths[i]
	}
	size := ui.constrain_min(gtx.constraints, {total, tok.OUTLINED_SEGMENTED_BUTTON_CONTAINER_HEIGHT})
	extra := (size.x - total) / f32(n)
	whole := ui.Rect{0, 0, size.x, size.y}
	outer := corners(tok.OUTLINED_SEGMENTED_BUTTON_SHAPE, whole)
	disabled := state == .Disabled

	ui.clip_push(gtx.ops, rounded(gtx, whole, outer))
	x: f32
	for i in 0 ..< n {
		w := widths[i] + extra
		seg := ui.Rect{x, 0, w, size.y}
		// Only the ends round: the first segment's start, the last's end.
		k: Corners
		if i == 0 {
			k.tl, k.bl = outer.tl, outer.bl
		}
		if i == n - 1 {
			k.tr, k.br = outer.tr, outer.br
		}
		id := ui.id_mix(p.id, u64(i))
		c := control(gtx, id, touch_target(seg), state)
		if c.clicked {
			if single {
				for j in 0 ..< n {
					selected[j] = j == i
				}
			} else {
				selected[i] = !selected[i]
			}
			changed = i
		}
		on := selected[i]
		// Slot 0 scales the check in, slot 1 fades it (segmented-button.json states.selected).
		grow := animate(gtx, c, 0, on ? 1 : 0, .Fast_Spatial)
		alpha := animate(gtx, c, 1, on ? 1 : 0, .Default_Effects)
		content := color(on ? tok.OUTLINED_SEGMENTED_BUTTON_SELECTED_LABEL_TEXT_COLOR : tok.OUTLINED_SEGMENTED_BUTTON_UNSELECTED_LABEL_TEXT_COLOR)
		icon_color := color(on ? tok.OUTLINED_SEGMENTED_BUTTON_SELECTED_ICON_COLOR : tok.OUTLINED_SEGMENTED_BUTTON_UNSELECTED_ICON_COLOR)
		layer := content
		if c.disabled {
			content = ui.with_alpha(color(tok.OUTLINED_SEGMENTED_BUTTON_DISABLED_LABEL_TEXT_COLOR), tok.OUTLINED_SEGMENTED_BUTTON_DISABLED_LABEL_TEXT_OPACITY)
			icon_color = ui.with_alpha(color(tok.OUTLINED_SEGMENTED_BUTTON_DISABLED_ICON_COLOR), tok.OUTLINED_SEGMENTED_BUTTON_DISABLED_ICON_OPACITY)
		} else if on {
			ui.fill(gtx.ops, seg, color(tok.OUTLINED_SEGMENTED_BUTTON_SELECTED_CONTAINER_COLOR))
		}
		paint_state_layer(gtx, c, seg, layer)
		g := max(grow, 0)
		tw := texts[i].width + (ICON + GAP) * g
		tx := x + (w - tw) / 2
		if g > 0 {
			s := ICON * g
			icon(gtx, .Check, {tx, (size.y + ICON) / 2 - s}, s, fade(icon_color, alpha))
			tx += (ICON + GAP) * g
		}
		draw_text(gtx, texts[i], {tx, (size.y - texts[i].height) / 2}, content)
		if c.st != nil {
			paint_focus_ring_corners(gtx, c, seg, k, inward = true)
		}
		listen(gtx, c, id, touch_target(seg))
		ui.tag(gtx.ops, id, ui.frame_string(gtx, labels[i]))
		x += w
	}
	ui.clip_pop(gtx.ops)
	edge := color(tok.OUTLINED_SEGMENTED_BUTTON_OUTLINE_COLOR)
	if disabled {
		edge = ui.with_alpha(color(tok.OUTLINED_SEGMENTED_BUTTON_DISABLED_OUTLINE_COLOR), tok.OUTLINED_SEGMENTED_BUTTON_DISABLED_OUTLINE_OPACITY)
	}
	stroke_inside_corners(gtx, whole, outer, edge, LINE)
	x = 0
	for i in 0 ..< n - 1 {
		x += widths[i] + extra
		ui.fill(gtx.ops, ui.Rect{x - LINE / 2, 0, LINE, size.y}, edge)
	}
	if state == .Focused {
		paint_focus_ring_corners(gtx, {focused = true}, whole, outer)
	}
	ui.widget_close(gtx, &p, {size, (size.y - texts[0].height) / 2 + baseline_of(texts[0])})
	return changed
}

// draw_icon_rotated is icon turned by turn half-turns about its centre.
@(private)
draw_icon_rotated :: proc(gtx: ^ui.Ctx, i: Icon, pos: ui.Point, size: f32, color: ui.Color, turn: f32) {
	cx, cy := pos.x + size / 2, pos.y + size / 2
	ui.transform_push(gtx.ops, ui.mul(ui.mul(ui.translate(-cx, -cy), ui.rotate(math.PI * turn)), ui.translate(cx, cy)))
	icon(gtx, i, pos, size, color)
	ui.transform_pop(gtx.ops)
}

// Split_Metrics are one size's comp.split-button-<size> group.
@(private)
Split_Metrics :: struct {
	height, between, inner, inner_pressed: f32,
	lead_leading, lead_trailing:           f32, // the leading button's padding
	trail_leading, trail_trailing:         f32, // the trailing button's padding
	trail_icon:                            f32,
}

@(private)
split_metrics :: proc(size: Button_Size) -> Split_Metrics {
	switch size {
	case .X_Small:
		return {
			tok.SPLIT_BUTTON_X_SMALL_CONTAINER_HEIGHT,
			tok.SPLIT_BUTTON_X_SMALL_BETWEEN_SPACE,
			tok.SPLIT_BUTTON_X_SMALL_INNER_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_X_SMALL_INNER_PRESSED_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_X_SMALL_LEADING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_X_SMALL_LEADING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_X_SMALL_TRAILING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_X_SMALL_TRAILING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_X_SMALL_TRAILING_ICON_SIZE,
		}
	case .Small:
	case .Medium:
		return {
			tok.SPLIT_BUTTON_MEDIUM_CONTAINER_HEIGHT,
			tok.SPLIT_BUTTON_MEDIUM_BETWEEN_SPACE,
			tok.SPLIT_BUTTON_MEDIUM_INNER_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_MEDIUM_INNER_PRESSED_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_MEDIUM_LEADING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_MEDIUM_LEADING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_MEDIUM_TRAILING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_MEDIUM_TRAILING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_MEDIUM_TRAILING_ICON_SIZE,
		}
	case .Large:
		return {
			tok.SPLIT_BUTTON_LARGE_CONTAINER_HEIGHT,
			tok.SPLIT_BUTTON_LARGE_BETWEEN_SPACE,
			tok.SPLIT_BUTTON_LARGE_INNER_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_LARGE_INNER_PRESSED_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_LARGE_LEADING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_LARGE_LEADING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_LARGE_TRAILING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_LARGE_TRAILING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_LARGE_TRAILING_ICON_SIZE,
		}
	case .X_Large:
		return {
			tok.SPLIT_BUTTON_X_LARGE_CONTAINER_HEIGHT,
			tok.SPLIT_BUTTON_X_LARGE_BETWEEN_SPACE,
			tok.SPLIT_BUTTON_X_LARGE_INNER_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_X_LARGE_INNER_PRESSED_CORNER_CORNER_SIZE,
			tok.SPLIT_BUTTON_X_LARGE_LEADING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_X_LARGE_LEADING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_X_LARGE_TRAILING_BUTTON_LEADING_SPACE,
			tok.SPLIT_BUTTON_X_LARGE_TRAILING_BUTTON_TRAILING_SPACE,
			tok.SPLIT_BUTTON_X_LARGE_TRAILING_ICON_SIZE,
		}
	}
	return {
		tok.SPLIT_BUTTON_SMALL_CONTAINER_HEIGHT,
		tok.SPLIT_BUTTON_SMALL_BETWEEN_SPACE,
		tok.SPLIT_BUTTON_SMALL_INNER_CORNER_CORNER_SIZE,
		tok.SPLIT_BUTTON_SMALL_INNER_PRESSED_CORNER_CORNER_SIZE,
		tok.SPLIT_BUTTON_SMALL_LEADING_BUTTON_LEADING_SPACE,
		tok.SPLIT_BUTTON_SMALL_LEADING_BUTTON_TRAILING_SPACE,
		tok.SPLIT_BUTTON_SMALL_TRAILING_BUTTON_LEADING_SPACE,
		tok.SPLIT_BUTTON_SMALL_TRAILING_BUTTON_TRAILING_SPACE,
		tok.SPLIT_BUTTON_SMALL_TRAILING_ICON_SIZE,
	}
}

// draw_split_half paints one half of a split button: elevation, fill, outline
// and state layer over path, whose corners are k.
@(private)
draw_split_half :: proc(gtx: ^ui.Ctx, c: Control, r: ui.Rect, k: Corners, col: Button_Colors, container, outline: ui.Color, line: f32) {
	path := rounded(gtx, r, k)
	if ui.painted(container) {
		// paint_elevation takes one radius; the outer one keeps the shadow
		// inside the rounded end, and the inner edge's is hidden by the gap.
		paint_elevation(gtx, {r, max(k.tl, k.tr, k.br, k.bl)}, button_elevation(col, c))
		ui.fill(gtx.ops, path, container)
	}
	if ui.painted(outline) {
		stroke_inside_corners(gtx, r, k, outline, line)
	}
	paint_state_layer(gtx, c, path, col.content)
}

// split_button is M3's split button (split-button.json): a leading action
// and a trailing menu toggle, between-space apart, in one style's colours
// at one size. Outer corners are full; the inner ones take the size's
// inner corner and morph to its pressed corner on the pressed half only.
// While expanded^ the trailing half becomes a circle (default-effects),
// carries a pressed-opacity content layer, and its chevron turns 180°
// (fast-spatial). It flips expanded^ itself; opening a menu is the
// caller's (see menu). leading_enabled and trailing_enabled disable each
// half on its own; menu_label names the trailing half for probes and
// screen readers. Returns (leading clicked, trailing toggled).
split_button :: proc(
	gtx: ^ui.Ctx,
	label: string,
	expanded: ^bool,
	kind := Button_Kind.Filled,
	leading := Icon.None,
	size := Button_Size.Small,
	leading_enabled := true,
	trailing_enabled := true,
	menu_label := "More options",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (
	clicked: bool,
	toggled: bool,
) {
	p := ui.widget_open(gtx, key, loc)
	sm := split_metrics(size)
	bm := button_metrics(size)
	col := button_colors(kind)
	t := shape_text(gtx, label, bm.role)
	h := sm.height
	lead_w := sm.lead_leading + t.width + sm.lead_trailing
	if leading != .None {
		lead_w += bm.icon + bm.gap
	}
	trail_w := sm.trail_leading + sm.trail_icon + sm.trail_trailing
	sz := ui.constrain_min(gtx.constraints, {lead_w + sm.between + trail_w, h})
	lead_w = sz.x - sm.between - trail_w
	lead := ui.Rect{0, 0, lead_w, h}
	trail := ui.Rect{lead_w + sm.between, 0, trail_w, h}
	lead_id, trail_id := ui.id_mix(p.id, 1), ui.id_mix(p.id, 2)
	full := h / 2 // outer corners: SplitButton.kt:279,425,467

	// colors resolves one half's paint, disabled or not.
	colors :: proc(kind: Button_Kind, col: Button_Colors, disabled: bool) -> (container, content, outline: ui.Color) {
		if disabled {
			return button_disabled_colors(kind)
		}
		return col.container, col.content, col.outline
	}

	// Each half is resolved and painted before the next control call: a
	// ui.widget_state pointer is only valid until the next widget_state.
	lc := control(gtx, lead_id, touch_target(lead), leading_enabled ? state : .Disabled)
	lp := animate(gtx, lc, 0, lc.pressed ? 1 : 0, .Fast_Spatial)
	lin := sm.inner + (sm.inner_pressed - sm.inner) * lp
	lk := Corners{full, lin, lin, full}
	container, content, outline := colors(kind, col, lc.disabled)
	draw_split_half(gtx, lc, lead, lk, col, container, outline, bm.outline)
	x := sm.lead_leading
	if leading != .None {
		icon(gtx, leading, {x, (h - bm.icon) / 2}, bm.icon, content)
		x += bm.icon + bm.gap
	}
	draw_text(gtx, t, {x, (h - t.height) / 2}, content)
	paint_focus_ring_corners(gtx, lc, lead, lk, inward = true)
	listen(gtx, lc, lead_id, touch_target(lead))

	tc := control(gtx, trail_id, touch_target(trail), trailing_enabled ? state : .Disabled)
	if tc.clicked {
		expanded^ = !expanded^
	}
	// Slot 0 is the press morph, slot 1 the checked circle, slot 2 the
	// chevron's turn.
	tp := animate(gtx, tc, 0, tc.pressed ? 1 : 0, .Fast_Spatial)
	te := animate(gtx, tc, 1, expanded^ ? 1 : 0, .Default_Effects)
	turn := animate(gtx, tc, 2, expanded^ ? 1 : 0, .Fast_Spatial)
	round := min(trail.w, trail.h) / 2 // the checked 50%: SplitButton.kt:427
	tin := sm.inner + (sm.inner_pressed - sm.inner) * tp
	tin += (round - tin) * te
	tk := Corners{tin, full + (round - full) * te, full + (round - full) * te, tin}
	container, content, outline = colors(kind, col, tc.disabled)
	draw_split_half(gtx, tc, trail, tk, col, container, outline, bm.outline)
	if expanded^ && !tc.disabled {
		// SplitButton.kt:421,905-910: checked draws a pressed-opacity layer.
		ui.fill(gtx.ops, rounded(gtx, trail, tk), ui.with_alpha(col.content, PRESSED_OPACITY))
	}
	ip := ui.Point{trail.x + sm.trail_leading, (h - sm.trail_icon) / 2}
	draw_icon_rotated(gtx, .Keyboard_Arrow_Down, ip, sm.trail_icon, content, turn)
	paint_focus_ring_corners(gtx, tc, trail, tk, inward = true)
	listen(gtx, tc, trail_id, touch_target(trail))
	ui.tag(gtx.ops, lead_id, ui.frame_string(gtx, label))
	ui.tag(gtx.ops, trail_id, ui.frame_string(gtx, menu_label))
	ui.widget_close(gtx, &p, {sz, (h - t.height) / 2 + baseline_of(t)})
	return lc.clicked, tc.clicked
}
