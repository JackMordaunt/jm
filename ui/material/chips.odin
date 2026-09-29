package material

import "core:fmt"
import "jm:ui/ops"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Chips, per the m3e-kit's components/chips.json: assist, filter, input
// and suggestion, flat or elevated, with filter and input chips optionally
// morphing their corners (the Expressive ChipShapes API). Colours come
// from each kind's comp.<kind>-chip group, not comp.chips: the spec's notes
// say Compose reads only comp.chips' three morph shapes.

Chip_Kind :: enum u8 {
	Assist,
	Filter,
	Input,
	Suggestion,
}

// ELEMENT_GAP is the untokenised gap between a chip's elements, and the
// padding around its label (chips.json layout element-gap, Chip.kt:4303-4304).
@(private = "file")
ELEMENT_GAP :: f32(8)

// INSET_WIDE and INSET_NARROW are a chip's start and end content insets
// (chips.json layout assist-suggestion-padding and input-padding,
// Chip.kt:1962,4292-4300).
@(private = "file")
INSET_WIDE :: f32(8)
@(private = "file")
INSET_NARROW :: f32(4)

// Chip_Colors are one chip's resolved paint.
@(private = "file")
Chip_Colors :: struct {
	container, outline:  ops.Color, // either may be unpainted
	label, lead, trail:  ops.Color,
	elevation:           f32, // dp
}

// chip_colors resolves kind's tokens for its style, selection and
// interaction. Only elevation follows hover, focus, press and drag: the
// content colour tokens for those states are unread in Compose (chips.json
// notes), so they are unread here.
@(private = "file")
chip_colors :: proc(kind: Chip_Kind, elevated, on: bool, c: Control, dragged: bool) -> (col: Chip_Colors) {
	switch kind {
	case .Assist:
		col.label = color(tok.ASSIST_CHIP_LABEL_TEXT_COLOR)
		col.lead = color(tok.ASSIST_CHIP_ICON_COLOR)
		col.trail = col.lead
		if elevated {
			col.container = color(tok.ASSIST_CHIP_ELEVATED_CONTAINER_COLOR)
			col.elevation = chip_elevation(c, tok.ASSIST_CHIP_ELEVATED_CONTAINER_ELEVATION, tok.ASSIST_CHIP_ELEVATED_HOVER_CONTAINER_ELEVATION, tok.ASSIST_CHIP_ELEVATED_FOCUS_CONTAINER_ELEVATION, tok.ASSIST_CHIP_ELEVATED_PRESSED_CONTAINER_ELEVATION)
		} else {
			col.outline = color(tok.ASSIST_CHIP_FLAT_OUTLINE_COLOR)
			col.elevation = tok.ASSIST_CHIP_FLAT_CONTAINER_ELEVATION
		}
		if dragged {
			col.elevation = tok.ASSIST_CHIP_DRAGGED_CONTAINER_ELEVATION
		}
		if c.disabled {
			col.label = token_color(tok.ASSIST_CHIP_DISABLED_LABEL_TEXT_COLOR, tok.ASSIST_CHIP_DISABLED_LABEL_TEXT_OPACITY)
			col.lead = token_color(tok.ASSIST_CHIP_DISABLED_ICON_COLOR, tok.ASSIST_CHIP_DISABLED_ICON_OPACITY)
			col.trail = col.lead
			if elevated {
				col.container = token_color(tok.ASSIST_CHIP_ELEVATED_DISABLED_CONTAINER_COLOR, tok.ASSIST_CHIP_ELEVATED_DISABLED_CONTAINER_OPACITY)
				col.elevation = tok.ASSIST_CHIP_ELEVATED_DISABLED_CONTAINER_ELEVATION
			} else {
				col.outline = token_color(tok.ASSIST_CHIP_FLAT_DISABLED_OUTLINE_COLOR, tok.ASSIST_CHIP_FLAT_DISABLED_OUTLINE_OPACITY)
			}
		}
	case .Suggestion:
		col.label = color(tok.SUGGESTION_CHIP_LABEL_TEXT_COLOR)
		col.lead = color(tok.SUGGESTION_CHIP_LEADING_ICON_COLOR)
		if elevated {
			col.container = color(tok.SUGGESTION_CHIP_ELEVATED_CONTAINER_COLOR)
			col.elevation = chip_elevation(c, tok.SUGGESTION_CHIP_ELEVATED_CONTAINER_ELEVATION, tok.SUGGESTION_CHIP_ELEVATED_HOVER_CONTAINER_ELEVATION, tok.SUGGESTION_CHIP_ELEVATED_FOCUS_CONTAINER_ELEVATION, tok.SUGGESTION_CHIP_ELEVATED_PRESSED_CONTAINER_ELEVATION)
		} else {
			col.outline = color(tok.SUGGESTION_CHIP_FLAT_OUTLINE_COLOR)
			col.elevation = tok.SUGGESTION_CHIP_FLAT_CONTAINER_ELEVATION
		}
		if dragged {
			col.elevation = tok.SUGGESTION_CHIP_DRAGGED_CONTAINER_ELEVATION
		}
		if c.disabled {
			col.label = token_color(tok.SUGGESTION_CHIP_DISABLED_LABEL_TEXT_COLOR, tok.SUGGESTION_CHIP_DISABLED_LABEL_TEXT_OPACITY)
			col.lead = token_color(tok.SUGGESTION_CHIP_DISABLED_LEADING_ICON_COLOR, tok.SUGGESTION_CHIP_DISABLED_LEADING_ICON_OPACITY)
			if elevated {
				col.container = token_color(tok.SUGGESTION_CHIP_ELEVATED_DISABLED_CONTAINER_COLOR, tok.SUGGESTION_CHIP_ELEVATED_DISABLED_CONTAINER_OPACITY)
				col.elevation = tok.SUGGESTION_CHIP_ELEVATED_DISABLED_CONTAINER_ELEVATION
			} else {
				col.outline = token_color(tok.SUGGESTION_CHIP_FLAT_DISABLED_OUTLINE_COLOR, tok.SUGGESTION_CHIP_FLAT_DISABLED_OUTLINE_OPACITY)
			}
		}
	case .Filter:
		if on {
			col.label = color(tok.FILTER_CHIP_SELECTED_LABEL_TEXT_COLOR)
			col.lead = color(tok.FILTER_CHIP_SELECTED_LEADING_ICON_COLOR)
			col.trail = color(tok.FILTER_CHIP_SELECTED_TRAILING_ICON_COLOR)
		} else {
			col.label = color(tok.FILTER_CHIP_UNSELECTED_LABEL_TEXT_COLOR)
			col.lead = color(tok.FILTER_CHIP_UNSELECTED_LEADING_ICON_COLOR)
			col.trail = color(tok.FILTER_CHIP_UNSELECTED_TRAILING_ICON_COLOR)
		}
		switch {
		case elevated:
			col.container = color(on ? tok.FILTER_CHIP_ELEVATED_SELECTED_CONTAINER_COLOR : tok.FILTER_CHIP_ELEVATED_UNSELECTED_CONTAINER_COLOR)
			col.elevation = chip_elevation(c, tok.FILTER_CHIP_ELEVATED_CONTAINER_ELEVATION, tok.FILTER_CHIP_ELEVATED_HOVER_CONTAINER_ELEVATION, tok.FILTER_CHIP_ELEVATED_FOCUS_CONTAINER_ELEVATION, tok.FILTER_CHIP_ELEVATED_PRESSED_CONTAINER_ELEVATION)
		case on:
			col.container = color(tok.FILTER_CHIP_FLAT_SELECTED_CONTAINER_COLOR)
			col.elevation = chip_elevation(c, tok.FILTER_CHIP_FLAT_CONTAINER_ELEVATION, tok.FILTER_CHIP_FLAT_SELECTED_HOVER_CONTAINER_ELEVATION, tok.FILTER_CHIP_FLAT_SELECTED_FOCUS_CONTAINER_ELEVATION, tok.FILTER_CHIP_FLAT_SELECTED_PRESSED_CONTAINER_ELEVATION)
		case:
			col.outline = color(tok.FILTER_CHIP_FLAT_UNSELECTED_OUTLINE_COLOR)
			col.elevation = chip_elevation(c, tok.FILTER_CHIP_FLAT_CONTAINER_ELEVATION, tok.FILTER_CHIP_FLAT_UNSELECTED_HOVER_CONTAINER_ELEVATION, tok.FILTER_CHIP_FLAT_UNSELECTED_FOCUS_CONTAINER_ELEVATION, tok.FILTER_CHIP_FLAT_UNSELECTED_PRESSED_CONTAINER_ELEVATION)
		}
		if dragged {
			col.elevation = tok.FILTER_CHIP_DRAGGED_CONTAINER_ELEVATION
		}
		if c.disabled {
			col.label = token_color(tok.FILTER_CHIP_DISABLED_LABEL_TEXT_COLOR, tok.FILTER_CHIP_DISABLED_LABEL_TEXT_OPACITY)
			col.lead = token_color(tok.FILTER_CHIP_DISABLED_LEADING_ICON_COLOR, tok.FILTER_CHIP_DISABLED_LEADING_ICON_OPACITY)
			col.trail = token_color(tok.FILTER_CHIP_DISABLED_TRAILING_ICON_COLOR, tok.FILTER_CHIP_DISABLED_TRAILING_ICON_OPACITY)
			switch {
			case elevated:
				col.container = token_color(tok.FILTER_CHIP_ELEVATED_DISABLED_CONTAINER_COLOR, tok.FILTER_CHIP_ELEVATED_DISABLED_CONTAINER_OPACITY)
				col.elevation = tok.FILTER_CHIP_ELEVATED_DISABLED_CONTAINER_ELEVATION
			case on:
				col.container = token_color(tok.FILTER_CHIP_FLAT_DISABLED_SELECTED_CONTAINER_COLOR, tok.FILTER_CHIP_FLAT_DISABLED_SELECTED_CONTAINER_OPACITY)
			case:
				col.outline = token_color(tok.FILTER_CHIP_FLAT_DISABLED_UNSELECTED_OUTLINE_COLOR, tok.FILTER_CHIP_FLAT_DISABLED_UNSELECTED_OUTLINE_OPACITY)
			}
		}
	case .Input:
		// One flat style only: there is no elevated input chip.
		if on {
			col.container = color(tok.INPUT_CHIP_SELECTED_CONTAINER_COLOR)
			col.label = color(tok.INPUT_CHIP_SELECTED_LABEL_TEXT_COLOR)
			col.lead = color(tok.INPUT_CHIP_SELECTED_LEADING_ICON_COLOR)
			col.trail = color(tok.INPUT_CHIP_SELECTED_TRAILING_ICON_COLOR)
		} else {
			col.outline = color(tok.INPUT_CHIP_UNSELECTED_OUTLINE_COLOR)
			col.label = color(tok.INPUT_CHIP_UNSELECTED_LABEL_TEXT_COLOR)
			col.lead = color(tok.INPUT_CHIP_UNSELECTED_LEADING_ICON_COLOR)
			col.trail = color(tok.INPUT_CHIP_UNSELECTED_TRAILING_ICON_COLOR)
		}
		col.elevation = dragged ? tok.INPUT_CHIP_DRAGGED_CONTAINER_ELEVATION : tok.INPUT_CHIP_CONTAINER_ELEVATION
		if c.disabled {
			col.label = token_color(tok.INPUT_CHIP_DISABLED_LABEL_TEXT_COLOR, tok.INPUT_CHIP_DISABLED_LABEL_TEXT_OPACITY)
			col.lead = token_color(tok.INPUT_CHIP_DISABLED_LEADING_ICON_COLOR, tok.INPUT_CHIP_DISABLED_LEADING_ICON_OPACITY)
			col.trail = token_color(tok.INPUT_CHIP_DISABLED_TRAILING_ICON_COLOR, tok.INPUT_CHIP_DISABLED_TRAILING_ICON_OPACITY)
			if on {
				col.container = token_color(tok.INPUT_CHIP_DISABLED_SELECTED_CONTAINER_COLOR, tok.INPUT_CHIP_DISABLED_SELECTED_CONTAINER_OPACITY)
			} else {
				col.outline = token_color(tok.INPUT_CHIP_DISABLED_UNSELECTED_OUTLINE_COLOR, tok.INPUT_CHIP_DISABLED_UNSELECTED_OUTLINE_OPACITY)
			}
		}
	}
	return
}

// chip_elevation picks a chip's elevation (dp) for c's interaction.
@(private = "file")
chip_elevation :: proc(c: Control, rest, hover, focus, pressed: f32) -> f32 {
	switch {
	case c.disabled:
		return 0
	case c.pressed:
		return pressed
	case c.focused:
		return focus
	case c.hovered:
		return hover
	}
	return rest
}

// chip is one M3 chip (chips.json). label is its text; kind picks its
// tokens and role:
//
//	Assist      a contextual action; leading is its icon.
//	Filter      a toggle: selected, when non-nil, is flipped on click and
//	            draws a leading check while true (chips.json states: MDC's
//	            checkedIcon, which Compose leaves to the caller, Chip.kt:610-612);
//	            trailing is decorative.
//	Input       entered data: avatar, when set, replaces leading; trailing
//	            defaults to a close icon with its own hit target that sets
//	            removed^; selected, when non-nil, toggles like a filter chip.
//	Suggestion  a generated hint: one optional leading icon, no trailing.
//
// elevated trades the outline for a raised surface (not for Input, which
// has no elevated style). shape_morph (Filter and Input only) opts into the
// Expressive corner morph: 12dp at rest, full when selected, 8dp while
// pressed. Returns true on the frame the chip was activated.
//
// Motion: the filter check expands in on fast-spatial and fades in on
// slow-effects, shrinking on default-effects and fading on fast-effects
// (with shape_morph, fast-spatial and default-effects both ways), kept on
// screen while it leaves (Chip.kt:3280-3283,3339-3343,3562-3564). Selection
// colour and the outline's fade move on default-effects; the corner morph
// uses default-effects too, since the source names no spring for it
// (chips.json notes). An avatar is an Icon here: jm:ui/material has no image
// slot, so it draws the glyph at avatar size.
chip :: proc(
	gtx: ^ui.Ctx,
	label: string,
	kind := Chip_Kind.Assist,
	selected: ^bool = nil,
	leading := Icon.None,
	elevated := false,
	removed: ^bool = nil,
	trailing := Icon.None,
	avatar := Icon.None,
	shape_morph := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	selectable := kind == .Filter || kind == .Input
	morph := shape_morph && selectable
	raised := elevated && kind != .Input
	on := selectable && selected != nil && selected^

	icon_size, trail_size, height: f32
	st: tok.Type_Style
	shape: tok.Shape
	switch kind {
	case .Assist:
		st, icon_size, height, shape = tok.ASSIST_CHIP_LABEL_TEXT_FONT, tok.ASSIST_CHIP_ICON_SIZE, tok.ASSIST_CHIP_CONTAINER_HEIGHT, tok.ASSIST_CHIP_CONTAINER_SHAPE
	case .Filter:
		st, icon_size, height, shape = tok.FILTER_CHIP_LABEL_TEXT_FONT, tok.FILTER_CHIP_ICON_SIZE, tok.FILTER_CHIP_CONTAINER_HEIGHT, tok.FILTER_CHIP_CONTAINER_SHAPE
	case .Input:
		st, icon_size, height, shape = tok.INPUT_CHIP_LABEL_TEXT_FONT, tok.INPUT_CHIP_LEADING_ICON_SIZE, tok.INPUT_CHIP_CONTAINER_HEIGHT, tok.INPUT_CHIP_CONTAINER_SHAPE
	case .Suggestion:
		st, icon_size, height, shape = tok.SUGGESTION_CHIP_LABEL_TEXT_FONT, tok.SUGGESTION_CHIP_LEADING_ICON_SIZE, tok.SUGGESTION_CHIP_CONTAINER_HEIGHT, tok.SUGGESTION_CHIP_CONTAINER_SHAPE
	}
	// No trailing size is exposed for most kinds; match the leading one
	// (chips.json notes).
	trail_size = kind == .Input ? tok.INPUT_CHIP_TRAILING_ICON_SIZE : icon_size
	t := shape_style(gtx, label, st)

	// What sits at each end. The filter check stands in for leading while
	// selected; an input chip's avatar outranks its leading icon.
	av := kind == .Input ? avatar : Icon.None
	lead := av != .None ? av : leading
	if kind == .Filter && on {
		lead = .Check
	}
	lead_size := av != .None ? tok.INPUT_CHIP_AVATAR_SIZE : icon_size
	trail := kind == .Suggestion ? Icon.None : trailing
	if kind == .Input && trail == .None {
		trail = .Close
	}

	// The width needs the leading slot's spring, which needs the Control,
	// which needs the width: size from last frame's spring value.
	lead_f: f32 = lead != .None ? 1 : 0
	if state == .Live {
		if sp := ui.widget_state(gtx, p.id).springs[1]; sp.started {
			lead_f = sp.value
		}
	}

	start := INSET_WIDE
	end := INSET_WIDE
	if kind == .Input {
		start = (av != .None || lead == .None) ? INSET_NARROW : INSET_WIDE
		end = trail != .None ? INSET_WIDE : INSET_NARROW
	}
	lead_w := lead_size * clamp(lead_f, 0, 1)
	w := start + lead_w + ELEMENT_GAP + t.width + ELEMENT_GAP + end
	if trail != .None {
		w += trail_size
	}
	// The 32dp chip is centred in a 48dp touch target, as MDC's
	// ensureAccessibleTouchTarget does (chips.json notes).
	size := ui.constrain_min(gtx.constraints, {w, max(MIN_TOUCH, height)})
	vis := ops.Rect{0, (size.y - height) / 2, size.x, height}
	body := ops.Rect{0, 0, size.x, size.y}
	if trail != .None && kind == .Input {
		body.w -= end + trail_size + ELEMENT_GAP / 2 // the close icon is its own target
	}
	c := control(gtx, p.id, body, state)
	if c.clicked && selectable && selected != nil {
		selected^ = !selected^
		on = selected^
		if kind == .Filter {
			lead = on ? .Check : (av != .None ? av : leading)
		}
	}
	dragged := state == .Dragged

	// Springs: 0 corner radius (dp), 1 leading width (0-1), 2 leading
	// alpha (0-1), 3 selection (0-1).
	has_lead := lead != .None
	expand, shrink, fade_in, fade_out: Spring = .Fast_Spatial, .Default_Effects, .Slow_Effects, .Fast_Effects
	if morph {
		expand, shrink, fade_in, fade_out = .Fast_Spatial, .Fast_Spatial, .Default_Effects, .Default_Effects
	}
	lead_f = animate(gtx, c, 1, has_lead ? 1 : 0, has_lead ? expand : shrink)
	lead_a := animate(gtx, c, 2, has_lead ? 1 : 0, has_lead ? fade_in : fade_out)
	sel_f := animate(gtx, c, 3, on ? 1 : 0, .Default_Effects)
	// A leaving check stays on screen until it has faded (Chip.kt:3339-3343).
	glyph := lead
	if glyph == .None && lead_a > 0 {
		glyph = kind == .Filter ? .Check : leading
	}

	radius := corners(shape, vis).tl
	if morph {
		target := corners(tok.CHIPS_UNSELECTED_SHAPE, vis).tl
		if on {
			target = corners(tok.CHIPS_SELECTED_SHAPE, vis).tl
		}
		if c.pressed {
			target = corners(tok.CHIPS_PRESSED_SHAPE, vis).tl // pressed wins over selected (Chip.kt:4269-4288)
		}
		radius = clamp(animate(gtx, c, 0, target, .Default_Effects, 0.1), 0, height / 2)
	}
	rr := ops.Round_Rect{vis, radius}

	// Selection cross-fades the two looks rather than cutting.
	col := chip_colors(kind, raised, on, c, dragged)
	if selectable && sel_f > 0 && sel_f < 1 {
		off := chip_colors(kind, raised, false, c, dragged)
		sel := chip_colors(kind, raised, true, c, dragged)
		col.container = cross_fade(off.container, sel.container, sel_f)
		col.outline = cross_fade(off.outline, sel.outline, sel_f)
		col.label = ops.mix(off.label, sel.label, sel_f)
		col.lead = ops.mix(off.lead, sel.lead, sel_f)
		col.trail = ops.mix(off.trail, sel.trail, sel_f)
	}

	paint_elevation(gtx, rr, elevation_level(col.elevation))
	if ui.painted(col.container) {
		ops.fill(gtx.scene, rr, col.container)
	}
	if ui.painted(col.outline) {
		stroke_inside(gtx, rr, col.outline, tok.CHIPS_UNSELECTED_OUTLINE_WIDTH)
	}
	paint_state_layer(gtx, c, rr, col.label)

	x := start
	if lead_w > 0 && glyph != .None {
		ops.clip_push(gtx.scene, ops.Rect{x, vis.y, lead_w, height})
		gc := col.lead
		if av != .None && c.disabled {
			gc = token_color(tok.INPUT_CHIP_DISABLED_LEADING_ICON_COLOR, tok.INPUT_CHIP_DISABLED_AVATAR_OPACITY)
		}
		icon(gtx, glyph, {x, vis.y + (height - lead_size) / 2}, lead_size, fade(gc, lead_a))
		ops.clip_pop(gtx.scene)
	}
	x += lead_w + ELEMENT_GAP
	draw_text(gtx, t, {x, vis.y + (height - t.height) / 2}, col.label)
	paint_focus_ring(gtx, c, rr)
	listen(gtx, c, p.id, body)
	if trail != .None {
		tx := size.x - end - trail_size
		icon(gtx, trail, {tx, vis.y + (height - trail_size) / 2}, trail_size, col.trail)
		if kind == .Input && state == .Live {
			// The remove control gets its own target and name (chips.json
			// accessibility): from half the gap before it to the chip's end.
			rid := ui.id_mix(p.id, 1)
			hit := ops.Rect{body.w, 0, size.x - body.w, size.y}
			rst := ui.widget_state(gtx, rid)
			if ui.click_from_events(gtx, rid, rst, hit) && removed != nil {
				removed^ = true
			}
			ops.input_area(gtx.scene, rid, hit, CLICK_KINDS)
			ops.tag(gtx.scene, rid, fmt.aprintf("remove %s", label, allocator = gtx.allocator))
		}
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	ui.widget_close(gtx, &p, {size, vis.y + (height - t.height) / 2 + baseline_of(t)})
	return c.clicked
}

// cross_fade blends a toward b by t, treating an unpainted end as b (or a)
// at no alpha, so a colour fades in or out rather than through black.
@(private = "file")
cross_fade :: proc(a, b: ops.Color, t: f32) -> ops.Color {
	switch {
	case !ui.painted(a) && !ui.painted(b):
		return {}
	case !ui.painted(a):
		return fade(b, t)
	case !ui.painted(b):
		return fade(a, 1 - t)
	}
	return ops.mix(a, b, t)
}
