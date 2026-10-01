package material

import "base:runtime"

import "core:fmt"
import "jm:ui/ops"
import "core:math"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Containment: cards, list items and dividers, from the m3e-kit's
// components/card.json, list.json and divider.json.

// Card_Kind is card.json's variant axis; each maps to its own token group.
Card_Kind :: enum u8 {
	Elevated, // comp.elevated-card
	Filled, // comp.filled-card
	Outlined, // comp.outlined-card
}

@(private)
Card_Paint :: struct {
	kind:      Card_Kind,
	clickable: bool,
	state:     Interaction,
	clicked:   ^bool,
}

// Card_Tokens are one card variant's tokens, per interaction state.
@(private)
Card_Tokens :: struct {
	container, disabled_container:                  tok.Role,
	disabled_opacity:                               f32,
	shape:                                          tok.Shape,
	rest, hover, focus, pressed, dragged, disabled: f32, // container elevation, dp
}

@(private)
card_tokens :: proc(kind: Card_Kind) -> Card_Tokens {
	switch kind {
	case .Elevated:
		return {
			tok.ELEVATED_CARD_CONTAINER_COLOR,
			tok.ELEVATED_CARD_DISABLED_CONTAINER_COLOR,
			tok.ELEVATED_CARD_DISABLED_CONTAINER_OPACITY,
			tok.ELEVATED_CARD_CONTAINER_SHAPE,
			tok.ELEVATED_CARD_CONTAINER_ELEVATION,
			tok.ELEVATED_CARD_HOVER_CONTAINER_ELEVATION,
			tok.ELEVATED_CARD_FOCUS_CONTAINER_ELEVATION,
			tok.ELEVATED_CARD_PRESSED_CONTAINER_ELEVATION,
			tok.ELEVATED_CARD_DRAGGED_CONTAINER_ELEVATION,
			tok.ELEVATED_CARD_DISABLED_CONTAINER_ELEVATION,
		}
	case .Filled:
		return {
			tok.FILLED_CARD_CONTAINER_COLOR,
			tok.FILLED_CARD_DISABLED_CONTAINER_COLOR,
			tok.FILLED_CARD_DISABLED_CONTAINER_OPACITY,
			tok.FILLED_CARD_CONTAINER_SHAPE,
			tok.FILLED_CARD_CONTAINER_ELEVATION,
			tok.FILLED_CARD_HOVER_CONTAINER_ELEVATION,
			tok.FILLED_CARD_FOCUS_CONTAINER_ELEVATION,
			tok.FILLED_CARD_PRESSED_CONTAINER_ELEVATION,
			tok.FILLED_CARD_DRAGGED_CONTAINER_ELEVATION,
			tok.FILLED_CARD_DISABLED_CONTAINER_ELEVATION,
		}
	case .Outlined:
		// An outlined card's disabled treatment is its outline, not its
		// container, so the container keeps its colour at full opacity.
		return {
			tok.OUTLINED_CARD_CONTAINER_COLOR,
			tok.OUTLINED_CARD_CONTAINER_COLOR,
			0,
			tok.OUTLINED_CARD_CONTAINER_SHAPE,
			tok.OUTLINED_CARD_CONTAINER_ELEVATION,
			tok.OUTLINED_CARD_HOVER_CONTAINER_ELEVATION,
			tok.OUTLINED_CARD_FOCUS_CONTAINER_ELEVATION,
			tok.OUTLINED_CARD_PRESSED_CONTAINER_ELEVATION,
			tok.OUTLINED_CARD_DRAGGED_CONTAINER_ELEVATION,
			tok.OUTLINED_CARD_DISABLED_CONTAINER_ELEVATION,
		}
	}
	return {}
}

// card_open opens an M3 card around the widgets up to ui.close, padded by
// padding (the kit gives no padding token; 16 keeps this proc's earlier
// default).
// Shape, fill, outline and the elevation of each state come from the
// variant's comp.*-card tokens. A clickable card is one tap target: it
// takes hover, focus, press and a forced Dragged state, each moving its
// elevation along Compose's 120/150ms tweens, and sets clicked^ when
// activated — known only at ui.close, so read it after. A disabled card
// composites its disabled colour over its container (the outlined card
// its disabled outline), as Card.kt:618-628 does.
//
// The outlined card's outline does not react to hover, focus, press or
// drag even though comp.outlined-card has tokens for it: Compose's
// outlinedCardBorder never reads them (card.json notes), and this follows
// Compose.
card_open :: proc(
	gtx: ^ui.Ctx,
	kind := Card_Kind.Elevated,
	clickable := false,
	clicked: ^bool = nil,
	state := Interaction.Live,
	padding := f32(16),
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Box {
	cp := new(Card_Paint, gtx.allocator)
	cp^ = {kind, clickable, state, clicked}
	// ui's zero padding means "theme default"; negative means exactly 0.
	b := ui.box_open(gtx, {padding = ui.pad_all(padding), paint = paint_card, user = cp}, key, loc)
	ui.container_semantics(gtx, {role = clickable ? .Button : .Group, states = state == .Disabled ? {.Disabled} : {}})
	return b
}

@(private)

// card is card_open as a guard: `if m3.card(gtx, .Filled) { … }` lays the
// block out inside the card and closes it at the end of the if, as ui's
// own container guards do (ui/guards.odin).
@(deferred_in = card_guard_close)
card :: proc(
	gtx: ^ui.Ctx,
	kind := Card_Kind.Elevated,
	clickable := false,
	clicked: ^bool = nil,
	state := Interaction.Live,
	padding := f32(16),
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	card_open(gtx, kind, clickable, clicked, state, padding, key, loc)
	return true
}

@(private = "file")
card_guard_close :: proc(gtx: ^ui.Ctx, kind: Card_Kind, clickable: bool, clicked: ^bool, state: Interaction, padding: f32, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Box)
}

paint_card :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	cp := (^Card_Paint)(user)
	t := card_tokens(cp.kind)
	area := ops.Rect{0, 0, size.x, size.y}
	rr := ops.Round_Rect{area, corners(t.shape, area).tl}
	c: Control
	if cp.clickable {
		c = control(gtx, id, area, cp.state)
		if cp.clicked != nil {
			cp.clicked^ = c.clicked
		}
	} else if cp.state == .Disabled {
		c.disabled = true
	}
	// CardElevation's order (Card.kt:640-654): disabled, pressed, hovered,
	// focused, dragged, then rest.
	target := t.rest
	switch {
	case c.disabled:
		target = t.disabled
	case c.pressed && cp.state != .Dragged:
		target = t.pressed
	case c.hovered:
		target = t.hover
	case c.focused:
		target = t.focus
	case cp.state == .Dragged:
		target = t.dragged
	}
	dp := target
	if c.st != nil {
		dp = elevation_tween(gtx, ui.widget_data(gtx, id, Elevation_Tween), target, t.rest, t.hover)
	}
	container := color(t.container)
	edge: ops.Color
	if cp.kind == .Outlined {
		edge = color(tok.OUTLINED_CARD_OUTLINE_COLOR)
	}
	if c.disabled {
		if cp.kind == .Outlined {
			edge = ops.mix(container, color(tok.OUTLINED_CARD_DISABLED_OUTLINE_COLOR), tok.OUTLINED_CARD_DISABLED_OUTLINE_OPACITY)
		} else {
			container = ops.mix(container, color(t.disabled_container), t.disabled_opacity)
		}
	}
	paint_elevation_dp(gtx, rr, dp)
	ops.fill(gtx.scene, rr, container)
	if ui.painted(edge) {
		stroke_inside(gtx, rr, edge, tok.OUTLINED_CARD_OUTLINE_WIDTH)
	}
	paint_state_layer(gtx, c, rr, color(.On_Surface))
	paint_focus_ring(gtx, c, rr)
	listen(gtx, c, id, rr)
}

// card_icon places an icon the way a card's icon tokens ask: 24dp in
// primary (the same in all three variants).
card_icon :: proc(gtx: ^ui.Ctx, glyph: Icon, kind := Card_Kind.Elevated, loc := #caller_location) {
	role, size := tok.ELEVATED_CARD_ICON_COLOR, tok.ELEVATED_CARD_ICON_SIZE
	switch kind {
	case .Elevated:
	case .Filled:
		role, size = tok.FILLED_CARD_ICON_COLOR, tok.FILLED_CARD_ICON_SIZE
	case .Outlined:
		role, size = tok.OUTLINED_CARD_ICON_COLOR, tok.OUTLINED_CARD_ICON_SIZE
	}
	icon_widget(gtx, glyph, size, color(role), loc)
}

// ELEVATION_OUT_EASING is Compose's easing back to rest from a raised
// state; no sys token has it (card.json behaviour, Elevation.kt:111-113).
@(private)
ELEVATION_OUT_EASING :: tok.Bezier{0.4, 0, 0.6, 1}

// Elevation_Tween is a card's elevation on its way to a target: an eased
// tween of fixed length, as Compose's animateElevation is (a tween
// AnimationSpec, Elevation.kt:109-113), not a spring, so it keeps its own
// record in the card's widget_data.
@(private)
Elevation_Tween :: struct {
	value:    f32, // dp now
	target:   f32, // dp it is heading for
	from:     f32, // dp when the target last changed
	t:        f32, // seconds since then
	duration: f32, // seconds the move takes
	started:  bool, // false until the first frame, which starts at target
}

// elevation_tween moves e toward target (dp) along Compose's elevation
// tweens (Elevation.kt:109-113): into a raised state over 120ms with
// FastOutSlowIn (sys.motion.easing.legacy); back to rest over 120ms from
// hover or 150ms from anything else, with ELEVATION_OUT_EASING.
@(private)
elevation_tween :: proc(gtx: ^ui.Ctx, e: ^Elevation_Tween, target, rest, hover: f32) -> f32 {
	if !e.started {
		e^ = {value = target, target = target, started = true}
		return target
	}
	if target != e.target {
		from_hover := e.target == hover && hover != rest
		e.from, e.t = e.value, 0
		e.duration = target == rest && !from_hover ? 0.150 : 0.120
		e.target = target
	}
	if e.value == e.target {
		return e.value
	}
	e.t += gtx.dt
	f := e.duration > 0 ? clamp(e.t / e.duration, 0, 1) : 1
	ease := e.target == rest ? ELEVATION_OUT_EASING : tok.SYS_MOTION_EASING_LEGACY
	e.value = e.from + (e.target - e.from) * bezier_ease(ease, f)
	if f >= 1 {
		e.value = e.target
	} else {
		ui.request_frame(gtx)
	}
	return e.value
}

// spring_progress is where a 0→1 move along spring s stands t seconds
// after it began (foundations.json motion.algorithm, from rest). It needs
// no retained state, so a component whose only memory is a timer (a
// tooltip's hover time, a snackbar's age) can still move on a spring.
@(private)
spring_progress :: proc(s: Spring, t: f32) -> f32 {
	p := spring_params(s)
	w := math.sqrt(p.stiffness)
	z := p.damping
	x0 := f32(-1)
	x: f32
	if z < 1 {
		wd := w * math.sqrt(1 - z * z)
		x = math.exp(-z * w * t) * (x0 * math.cos(wd * t) + (z * w * x0 / wd) * math.sin(wd * t))
	} else {
		x = math.exp(-w * t) * (x0 + w * x0 * t)
	}
	if abs(x) < 0.001 {
		return 1
	}
	return 1 + x
}

// scale_about is a scale by k about point c.
@(private)
scale_about :: proc(c: ops.Point, k: f32) -> ops.Affine {
	return ops.mul(ops.mul(ops.translate(-c.x, -c.y), ops.scale(k, k)), ops.translate(c.x, c.y))
}

// List_Selection is list.json's selectionMode: how a row takes a click.
List_Selection :: enum u8 {
	Click, // activatable: list_item returns true (first, so older callers keep it)
	None, // informational: no input, no state layer
	Single, // radio-like: the caller sets selected from the click
	Multi, // checkbox-like: a click flips checked^, which shows as selected
}

// List_Kind is list.json's variant axis: the Expressive additions to the
// standard row, each with its own token group.
List_Kind :: enum u8 {
	Standard, // comp.list
	Expanded, // comp.expanded-list: a disclosure that toggles expanded^
	Reorder, // comp.reorder-list: a drag handle; drag or Up/Down reports moved^
	Reveal, // comp.reveal-list: swipe left to show actions behind the row
}

// List_Media is a leading image or video slot. jm:ui has no media to
// show, so it paints a placeholder of the token size and shape, with the
// item's leading_icon centred in it.
List_Media :: enum u8 {
	None,
	Image, // 56×56
	Small_Video, // 100×56
	Large_Video, // 114×64
}

// List_Item describes one M3 list item's slots and behaviour; empty
// strings, .None and nil leave a slot out.
List_Item :: struct {
	overline:       string,
	headline:       string,
	supporting:     string,
	leading_icon:   Icon,
	leading_avatar: string, // a monogram on a primary_container circle
	leading_media:  List_Media,
	trailing_icon:  Icon,
	trailing_text:  string,
	three_line:     bool, // supporting wraps to two lines
	selected:       bool, // the selected colours and shape
	divider:        bool, // an outline_variant line under the item, inset 16/16
	selection:      List_Selection,
	checked:        ^bool, // Multi: flipped on click and shown as selected
	// A segmented run: rows in a column with gap tok.LIST_SEGMENTED_GAP,
	// each on the segmented container colour; the first and last take the
	// list's large outer corners. segment_count 0 is no run.
	segment_index:  int,
	segment_count:  int,
	kind:           List_Kind,
	expanded:       ^bool, // Expanded: flipped by a click on the row
	moved:          ^int, // Reorder: set to the rows a drag or key moved it (+ down)
	actions:        []Icon, // Reveal: the buttons behind the row, the last the primary one
	action:         ^int, // Reveal: set to the index of the action clicked
	revealed:       bool, // Reveal, forced states: paint the row slid open
	dragged:        bool, // paint lifted, as a reorder drag does
}

// List_Colors are one row's resolved content colours.
@(private)
List_Colors :: struct {
	container, label, overline, supporting, leading, trailing, trailing_text: ops.Color,
}

// list_colors resolves comp.list's colour tokens for c. selected picks
// the selected family; dragged the reorder-list one (list.json states).
@(private)
list_colors :: proc(c: Control, selected, dragged: bool) -> (col: List_Colors) {
	if c.disabled {
		if selected {
			col.container = ops.with_alpha(color(tok.LIST_ITEM_SELECTED_DISABLED_CONTAINER_COLOR), tok.LIST_ITEM_SELECTED_DISABLED_CONTAINER_OPACITY)
			col.label = ops.with_alpha(color(tok.LIST_ITEM_SELECTED_DISABLED_LABEL_TEXT_COLOR), tok.LIST_ITEM_SELECTED_DISABLED_LABEL_TEXT_OPACITY)
			col.overline = ops.with_alpha(color(tok.LIST_ITEM_SELECTED_DISABLED_OVERLINE_COLOR), tok.LIST_ITEM_SELECTED_DISABLED_OVERLINE_OPACITY)
			col.supporting = ops.with_alpha(color(tok.LIST_ITEM_SELECTED_DISABLED_SUPPORTING_TEXT_COLOR), tok.LIST_ITEM_SELECTED_DISABLED_SUPPORTING_TEXT_OPACITY)
			col.leading = ops.with_alpha(color(tok.LIST_ITEM_SELECTED_DISABLED_LEADING_ICON_COLOR), tok.LIST_ITEM_SELECTED_DISABLED_LEADING_ICON_OPACITY)
			col.trailing = ops.with_alpha(color(tok.LIST_ITEM_SELECTED_DISABLED_TRAILING_ICON_COLOR), tok.LIST_ITEM_SELECTED_DISABLED_TRAILING_ICON_OPACITY)
			col.trailing_text = ops.with_alpha(color(tok.LIST_ITEM_SELECTED_DISABLED_TRAILING_SUPPORTING_TEXT_COLOR), tok.LIST_ITEM_SELECTED_DISABLED_TRAILING_SUPPORTING_TEXT_OPACITY)
			return
		}
		col.label = ops.with_alpha(color(tok.LIST_ITEM_DISABLED_LABEL_TEXT_COLOR), tok.LIST_ITEM_DISABLED_LABEL_TEXT_OPACITY)
		col.overline = ops.with_alpha(color(tok.LIST_ITEM_DISABLED_OVERLINE_COLOR), tok.LIST_ITEM_DISABLED_OVERLINE_OPACITY)
		col.supporting = ops.with_alpha(color(tok.LIST_ITEM_DISABLED_SUPPORTING_TEXT_COLOR), tok.LIST_ITEM_DISABLED_SUPPORTING_TEXT_OPACITY)
		col.leading = ops.with_alpha(color(tok.LIST_ITEM_DISABLED_LEADING_ICON_COLOR), tok.LIST_ITEM_DISABLED_LEADING_ICON_OPACITY)
		col.trailing = ops.with_alpha(color(tok.LIST_ITEM_DISABLED_TRAILING_ICON_COLOR), tok.LIST_ITEM_DISABLED_TRAILING_ICON_OPACITY)
		col.trailing_text = col.supporting
		return
	}
	if dragged {
		return {
			color(tok.REORDER_LIST_ITEM_CONTAINER_COLOR),
			color(tok.REORDER_LIST_ITEM_LABEL_TEXT_COLOR),
			color(tok.REORDER_LIST_ITEM_OVERLINE_COLOR),
			color(tok.REORDER_LIST_ITEM_SUPPORTING_TEXT_COLOR),
			color(tok.REORDER_LIST_ITEM_LEADING_ICON_COLOR),
			color(tok.REORDER_LIST_ITEM_TRAILING_ICON_COLOR),
			color(tok.REORDER_LIST_ITEM_TRAILING_SUPPORTING_TEXT_COLOR),
		}
	}
	if selected {
		col = {
			color(tok.LIST_ITEM_SELECTED_CONTAINER_COLOR),
			color(tok.LIST_ITEM_SELECTED_LABEL_TEXT_COLOR),
			color(tok.LIST_ITEM_SELECTED_OVERLINE_COLOR),
			color(tok.LIST_ITEM_SELECTED_SUPPORTING_TEXT_COLOR),
			color(tok.LIST_ITEM_SELECTED_LEADING_ICON_COLOR),
			color(tok.LIST_ITEM_SELECTED_TRAILING_ICON_COLOR),
			color(tok.LIST_ITEM_SELECTED_TRAILING_SUPPORTING_TEXT_COLOR),
		}
		// The selected hover/focus/press families swap only the label and
		// icon colours; the tokens set those icons back to on-surface.
		switch {
		case c.pressed:
			col.label = color(tok.LIST_ITEM_SELECTED_PRESSED_LABEL_TEXT_COLOR)
			col.leading = color(tok.LIST_ITEM_SELECTED_PRESSED_LEADING_ICON_COLOR)
			col.trailing = color(tok.LIST_ITEM_SELECTED_PRESSED_TRAILING_ICON_COLOR)
		case c.focused:
			col.label = color(tok.LIST_ITEM_SELECTED_FOCUS_LABEL_TEXT_COLOR)
			col.leading = color(tok.LIST_ITEM_SELECTED_FOCUS_LEADING_ICON_COLOR)
			col.trailing = color(tok.LIST_ITEM_SELECTED_FOCUS_TRAILING_ICON_COLOR)
		case c.hovered:
			col.label = color(tok.LIST_ITEM_SELECTED_HOVER_LABEL_TEXT_COLOR)
			col.leading = color(tok.LIST_ITEM_SELECTED_HOVER_LEADING_ICON_COLOR)
			col.trailing = color(tok.LIST_ITEM_SELECTED_HOVER_TRAILING_ICON_COLOR)
		}
		return
	}
	col = {
		color(tok.LIST_ITEM_CONTAINER_COLOR),
		color(tok.LIST_ITEM_LABEL_TEXT_COLOR),
		color(tok.LIST_ITEM_OVERLINE_COLOR),
		color(tok.LIST_ITEM_SUPPORTING_TEXT_COLOR),
		color(tok.LIST_ITEM_LEADING_ICON_COLOR),
		color(tok.LIST_ITEM_TRAILING_ICON_COLOR),
		color(tok.LIST_ITEM_TRAILING_SUPPORTING_TEXT_COLOR),
	}
	switch {
	case c.pressed:
		col.label = color(tok.LIST_ITEM_PRESSED_LABEL_TEXT_COLOR)
		col.leading = color(tok.LIST_ITEM_PRESSED_LEADING_ICON_ICON_COLOR)
		col.trailing = color(tok.LIST_ITEM_PRESSED_TRAILING_ICON_ICON_COLOR)
	case c.focused:
		col.label = color(tok.LIST_ITEM_FOCUS_LABEL_TEXT_COLOR)
		col.leading = color(tok.LIST_ITEM_FOCUS_LEADING_ICON_ICON_COLOR)
		col.trailing = color(tok.LIST_ITEM_FOCUS_TRAILING_ICON_ICON_COLOR)
	case c.hovered:
		col.label = color(tok.LIST_ITEM_HOVER_LABEL_TEXT_COLOR)
		col.leading = color(tok.LIST_ITEM_HOVER_LEADING_ICON_ICON_COLOR)
		col.trailing = color(tok.LIST_ITEM_HOVER_TRAILING_ICON_ICON_COLOR)
	}
	return
}

// mix_list_colors is a cross-fade from a to b at t, per part.
@(private)
mix_list_colors :: proc(a, b: List_Colors, t: f32) -> List_Colors {
	if t <= 0 {
		return a
	}
	if t >= 1 {
		return b
	}
	return {
		ops.mix(a.container, b.container, t),
		ops.mix(a.label, b.label, t),
		ops.mix(a.overline, b.overline, t),
		ops.mix(a.supporting, b.supporting, t),
		ops.mix(a.leading, b.leading, t),
		ops.mix(a.trailing, b.trailing, t),
		ops.mix(a.trailing_text, b.trailing_text, t),
	}
}

// list_radius is the row's corner radius for its state: comp.list's
// *-container-expressive-shape tokens. Pressed and selected take the large
// corner, hovered the medium one (list.json states).
@(private)
list_radius :: proc(c: Control, selected, dragged: bool) -> f32 {
	sh := tok.LIST_ITEM_CONTAINER_EXPRESSIVE_SHAPE
	switch {
	case c.disabled && selected:
		sh = tok.LIST_ITEM_SELECTED_DISABLED_CONTAINER_EXPRESSIVE_SHAPE
	case c.disabled:
		sh = tok.LIST_ITEM_DISABLED_CONTAINER_EXPRESSIVE_SHAPE
	case dragged:
		sh = selected ? tok.LIST_ITEM_SELECTED_DRAGGED_CONTAINER_EXPRESSIVE_SHAPE : tok.REORDER_LIST_ITEM_SHAPE
	case selected && c.pressed:
		sh = tok.LIST_ITEM_SELECTED_PRESSED_CONTAINER_EXPRESSIVE_SHAPE
	case selected && c.focused:
		sh = tok.LIST_ITEM_SELECTED_FOCUSED_CONTAINER_EXPRESSIVE_SHAPE
	case selected && c.hovered:
		sh = tok.LIST_ITEM_SELECTED_HOVERED_CONTAINER_EXPRESSIVE_SHAPE
	case selected:
		sh = tok.LIST_ITEM_SELECTED_CONTAINER_EXPRESSIVE_SHAPE
	case c.pressed:
		sh = tok.LIST_ITEM_PRESSED_CONTAINER_EXPRESSIVE_SHAPE
	case c.focused:
		sh = tok.LIST_ITEM_FOCUSED_CONTAINER_EXPRESSIVE_SHAPE
	case c.hovered:
		sh = tok.LIST_ITEM_HOVERED_CONTAINER_EXPRESSIVE_SHAPE
	}
	return sh.radii[0]
}

// Vertical padding inside a row: 8dp for one and two lines, 12dp for
// three (list.json layout row-vertical-padding, ListItemDefaults.kt:51-58;
// comp.list.item-top-space says 10, which Compose does not use).
@(private)
LIST_PAD_Y :: f32(8)
@(private)
LIST_PAD_Y_THREE :: f32(12)

// DRAG_SLOP is how far a press must move before it is a drag, not a click.
@(private)
DRAG_SLOP :: f32(8)

// List_Item_State is a reorder or reveal row's gesture and resting place,
// kept across frames. list_item keeps one per row by itself; pass your
// own to keep a reveal row open (or a drag going) through a reorder of the
// list, to persist it, or to open or close a reveal row from outside by
// setting reveal.target.
List_Item_State :: struct {
	drag:   f32, // the pointer's travel along the row's drag axis since the press, once past DRAG_SLOP; 0 when not dragging
	grab:   ops.Point, // where that press landed, local to the row
	reveal: ui.Spring, // a reveal row's offset (dp, 0 or less); its target is where it rests: 0 closed, minus the actions' width open
}

// list_item is M3's list item on the Expressive tokens: 56/72/88dp for
// one/two/three lines (taller when its content is), 16dp side space, 12dp
// between slots, a body-large headline, body-medium supporting text,
// label-small overline and trailing text, 20dp icons, a 40dp avatar or a
// media placeholder. Its corners morph on a fast-spatial spring from 4dp
// at rest to 12 hovered and 16 pressed, focused or selected; colours
// cross-fade on default-effects. Returns true when activated (never for
// selection .None). width 0 fills the offered width.
//
// Variants: Expanded shows a disclosure button whose chevron turns as a
// click flips expanded^ (the caller lays out the revealed rows); Reorder
// shows a drag handle, lifts the row on a drag (tertiary colours, 8dp
// elevation, a drop zone left behind) and on release sets moved^ to the
// rows travelled — Up/Down while focused move it by one, list.json's
// keyboard affordance; Reveal slides left on a horizontal drag, or
// Left/Right while focused, to uncover actions and sets action^ to the
// one clicked. Compose at the kit's pinned commit has none of these three
// (list.json behaviour compose-gap): their interaction is list.json's
// inference. A long press (onLongClick) has no jm:ui event.
//
// row_state holds a Reorder or Reveal row's drag and a Reveal row's
// resting offset (see List_Item_State); nil keeps them in the row's own
// widget_data, which follows the row's id.
list_item :: proc(
	gtx: ^ui.Ctx,
	it: List_Item,
	width: f32 = 0,
	state := Interaction.Live,
	row_state: ^List_Item_State = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	lines := 1
	if it.supporting != "" || it.overline != "" {
		lines = 2
	}
	if it.three_line || (it.supporting != "" && it.overline != "") {
		lines = 3
	}
	pad_y := lines == 3 ? LIST_PAD_Y_THREE : LIST_PAD_Y
	h := lines == 1 ? tok.LIST_ITEM_ONE_LINE_CONTAINER_HEIGHT : (lines == 2 ? tok.LIST_ITEM_TWO_LINE_CONTAINER_HEIGHT : tok.LIST_ITEM_THREE_LINE_CONTAINER_HEIGHT)
	// A row is never shorter than its content (list.json row-height).
	_, media_h := list_media_size(it.leading_media)
	h = max(h, media_h + 2 * pad_y, list_text_height(it, lines) + 2 * pad_y)
	w := width
	if w <= 0 {
		w = gtx.constraints.max.x < ui.INF ? gtx.constraints.max.x : 360
	}
	size := ui.constrain(gtx.constraints, {w, h})
	area := ops.Rect{0, 0, size.x, size.y}

	st := state
	if it.selection == .None && st != .Disabled {
		st = .Enabled
	}
	c := control(gtx, p.id, area, st)
	activated := c.clicked
	selected := it.selected
	if it.selection == .Multi && it.checked != nil {
		selected = it.checked^
	}

	// Drags: a press that moves past DRAG_SLOP lifts a reorder row or
	// slides a reveal row.
	drag: f32
	reveal_w := list_reveal_width(len(it.actions))
	gs: ^List_Item_State
	if c.st != nil && (it.kind == .Reorder || it.kind == .Reveal) {
		gs = row_state if row_state != nil else ui.widget_data(gtx, p.id, List_Item_State)
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left {
					gs.grab = e.pos
				}
			case .Move:
				if c.st.pressed {
					d := it.kind == .Reorder ? e.pos.y - gs.grab.y : e.pos.x - gs.grab.x
					if abs(d) > DRAG_SLOP || gs.drag != 0 {
						gs.drag = d
					}
				}
			case .Key:
				#partial switch e.key {
				case .Up:
					if it.kind == .Reorder && it.moved != nil {
						it.moved^ = -1
					}
				case .Down:
					if it.kind == .Reorder && it.moved != nil {
						it.moved^ = 1
					}
				case .Left:
					if it.kind == .Reveal {
						gs.reveal.target = -reveal_w
					}
				case .Right, .Escape:
					if it.kind == .Reveal {
						gs.reveal.target = 0
					}
				}
			}
		}
		drag = gs.drag
		if !c.st.pressed && drag != 0 {
			// Released after a drag: it was not a click.
			activated = false
			if it.kind == .Reorder && it.moved != nil {
				it.moved^ = int(math.round(drag / size.y))
			}
			if it.kind == .Reveal {
				rv := &gs.reveal
				rv.value = clamp(rv.target + drag, -reveal_w, 0)
				rv.velocity = 0
				rv.target = rv.value < -reveal_w / 2 ? -reveal_w : 0
				rv.x0 = rv.value - rv.target
				rv.v0, rv.t = 0, 0
			}
			gs.drag, drag = 0, 0
		}
	}
	if activated {
		if it.selection == .Multi && it.checked != nil {
			it.checked^ = !it.checked^
			selected = it.checked^
		}
		if it.kind == .Expanded && it.expanded != nil {
			it.expanded^ = !it.expanded^
		}
	}
	lifted := it.dragged || state == .Dragged || (it.kind == .Reorder && drag != 0)

	sel := animate(gtx, c, 1, selected ? 1 : 0, .Default_Effects)
	col := mix_list_colors(list_colors(c, false, false), list_colors(c, true, false), sel)
	if c.disabled {
		col = list_colors(c, selected, false)
	}
	if lifted && !c.disabled {
		col = list_colors(c, selected, true)
	}
	r := animate(gtx, c, 0, list_radius(c, selected, lifted), .Fast_Spatial, 0.1)
	k := corners_all(r)
	if it.segment_count > 0 {
		outer := tok.LIST_CONTAINER_SHAPE.radii[0]
		if it.segment_index == 0 {
			k.tl, k.tr = max(k.tl, outer), max(k.tr, outer)
		}
		if it.segment_index == it.segment_count - 1 {
			k.bl, k.br = max(k.bl, outer), max(k.br, outer)
		}
	}
	// The container colour is surface, the page's own colour in the usual
	// case, so a plain row paints it only once it differs (selected,
	// lifted) — a row laid on a sheet or card then takes that surface, as
	// Compose's ListItem would only if given the sheet's colour.
	container := ops.with_alpha(col.container, sel)
	if it.segment_count > 0 || it.kind == .Reveal {
		base := it.segment_count > 0 ? color(tok.LIST_ITEM_SEGMENTED_CONTAINER_COLOR) : color(tok.REVEAL_LIST_ITEM_CONTAINER_COLOR)
		container = ops.mix(base, col.container, sel)
		if c.disabled {
			container = selected ? col.container : base
		}
	}
	if lifted || c.disabled && selected {
		container = col.container
	}

	expand: f32
	if it.kind == .Expanded {
		expand = animate(gtx, c, 2, it.expanded != nil && it.expanded^ ? 1 : 0, .Default_Spatial)
	}
	elev := animate(gtx, c, 3, lifted ? tok.LIST_ITEM_DRAGGED_CONTAINER_ELEVATION : 0, .Fast_Spatial, 0.1)

	body := List_Body {
		it        = it,
		size      = size,
		lines     = lines,
		pad_y     = pad_y,
		col       = col,
		corners   = k,
		container = container,
		expand    = expand,
		elevation = elev,
	}
	switch {
	case it.kind == .Reorder && drag != 0:
		// Lifted: a drop zone holds the row's place, and the row follows
		// the pointer in an overlay so the rows after it pass beneath.
		ops.fill(gtx.scene, rounded(gtx, area, corners(tok.REORDER_LIST_ITEM_SHAPE, area)), color(tok.REORDER_LIST_ITEM_DROP_ZONE_COLOR))
		o := ui.overlay_open(gtx, {0, drag})
		paint_list_body(gtx, body, c)
		ui.close(&o)
	case it.kind == .Reveal:
		offset: f32 = it.revealed ? -reveal_w : 0
		if gs != nil {
			offset = clamp(gs.reveal.target + drag, -reveal_w, 0)
			if drag == 0 {
				offset = ui.spring_update(&gs.reveal, gtx, gs.reveal.target, spring_params(.Fast_Spatial), 0.5)
			}
		}
		ops.clip_push(gtx.scene, area)
		paint_reveal_actions(gtx, it, p.id, size, offset, c, gs)
		open := reveal_w > 0 ? -offset / reveal_w : 0
		body.corners = lerp_corners(k, corners(tok.REVEAL_LIST_ITEM_CONTAINER_SHAPE, area), open)
		ops.transform_push(gtx.scene, ops.translate(offset, 0))
		paint_list_body(gtx, body, c)
		ops.transform_pop(gtx.scene)
		ops.clip_pop(gtx.scene)
		// Only the row's visible part takes presses, so the uncovered
		// actions take their own.
		if c.st != nil {
			ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, max(size.x + offset, 0), size.y}, CLICK_KINDS)
		}
	case:
		paint_list_body(gtx, body, c)
	}
	if it.divider {
		ops.fill(
			gtx.scene,
			ops.Rect{tok.LIST_DIVIDER_LEADING_SPACE, size.y - tok.DIVIDER_THICKNESS, max(size.x - tok.LIST_DIVIDER_LEADING_SPACE - tok.LIST_DIVIDER_TRAILING_SPACE, 0), tok.DIVIDER_THICKNESS},
			color(tok.DIVIDER_COLOR),
		)
	}
	paint_focus_ring_corners(gtx, c, area, k, inward = true)
	if it.kind != .Reveal {
		listen(gtx, c, p.id, area)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, it.headline))
	ui.semantics(gtx, &p, {role = .List_Item, label = it.headline, description = it.supporting, states = states_of(c, selected)})
	ui.widget_close(gtx, &p, {size = size})
	return activated && it.selection != .None
}

// List_Body is what paint_list_body needs to draw one row.
@(private)
List_Body :: struct {
	it:        List_Item,
	size:      ops.Size,
	lines:     int,
	pad_y:     f32,
	col:       List_Colors,
	corners:   Corners,
	container: ops.Color,
	expand:    f32, // Expanded: 0 collapsed to 1 expanded
	elevation: f32, // dp
}

// paint_list_body draws a row's container, state layer and slots at the
// origin: in place, or in the overlay a reorder drag lifts it into.
@(private)
paint_list_body :: proc(gtx: ^ui.Ctx, b: List_Body, c: Control) {
	it, size := b.it, b.size
	area := ops.Rect{0, 0, size.x, size.y}
	shape := rounded(gtx, area, b.corners)
	if b.elevation > 0 {
		paint_elevation_dp(gtx, {area, b.corners.tl}, b.elevation)
	}
	if b.container[3] > 0 {
		ops.fill(gtx.scene, shape, b.container)
	}
	if it.selection != .None {
		paint_state_layer(gtx, c, shape, b.col.label)
	}

	top := b.lines == 3 // three-line rows align their slots to the top
	x := tok.LIST_ITEM_LEADING_SPACE
	slot_y :: proc(top: bool, pad, h, slot: f32) -> f32 {
		return top ? pad : (h - slot) / 2
	}
	switch {
	case it.leading_media != .None:
		mw, mh := list_media_size(it.leading_media)
		y := slot_y(top, b.pad_y, size.y, mh)
		sh := it.leading_media == .Image ? tok.LIST_ITEM_LEADING_IMAGE_EXPRESSIVE_SHAPE : tok.LIST_ITEM_LEADING_VIDEO_SHAPE
		r := ops.Rect{x, y, mw, mh}
		ops.fill(gtx.scene, rounded(gtx, r, corners(sh, r)), color(.Surface_Container_Highest))
		g := it.leading_icon != .None ? it.leading_icon : (it.leading_media == .Image ? Icon.Image : Icon.Movie)
		ICON :: tok.LIST_ITEM_LEADING_ICON_SIZE
		icon(gtx, g, {x + (mw - ICON) / 2, y + (mh - ICON) / 2}, ICON, b.col.leading)
		x += mw + tok.LIST_ITEM_BETWEEN_SPACE
	case it.leading_avatar != "":
		AV :: tok.LIST_ITEM_LEADING_AVATAR_SIZE
		y := slot_y(top, b.pad_y, size.y, AV)
		fill := color(tok.LIST_ITEM_LEADING_AVATAR_COLOR)
		ink := color(tok.LIST_ITEM_LEADING_AVATAR_LABEL_COLOR)
		if c.disabled {
			fill, ink = disabled_container(), b.col.leading
		}
		ops.fill(gtx.scene, ui.circle({x + AV / 2, y + AV / 2}, AV / 2), fill)
		t := shape_style(gtx, it.leading_avatar, tok.LIST_ITEM_LEADING_AVATAR_LABEL_FONT)
		draw_text(gtx, t, {x + (AV - t.width) / 2, y + (AV - t.height) / 2}, ink)
		x += AV + tok.LIST_ITEM_BETWEEN_SPACE
	case it.leading_icon != .None:
		ICON :: tok.LIST_ITEM_LEADING_ICON_EXPRESSIVE_SIZE
		icon(gtx, it.leading_icon, {x, slot_y(top, b.pad_y, size.y, ICON)}, ICON, b.col.leading)
		x += ICON + tok.LIST_ITEM_BETWEEN_SPACE
	}

	right := size.x - tok.LIST_ITEM_TRAILING_SPACE
	switch it.kind {
	case .Standard, .Reveal:
	case .Expanded:
		// The disclosure: an extra-small icon button, full shape, whose
		// container darkens and chevron turns as the row expands.
		BOX :: tok.X_SMALL_ICON_BUTTON_CONTAINER_HEIGHT
		ICON :: tok.X_SMALL_ICON_BUTTON_ICON_SIZE
		right -= BOX
		y := slot_y(top, b.pad_y, size.y, BOX)
		ctr := ops.Point{right + BOX / 2, y + BOX / 2}
		fill := ops.mix(color(tok.EXPANDED_LIST_COLLAPSED_ITEM_TRAILING_ICON_CONTAINER_COLOR), color(tok.EXPANDED_LIST_EXPANDED_ITEM_TRAILING_ICON_CONTAINER_COLOR), b.expand)
		ink := ops.mix(color(tok.EXPANDED_LIST_COLLAPSED_ITEM_TRAILING_ICON_ICON_COLOR), color(tok.EXPANDED_LIST_EXPANDED_ITEM_TRAILING_ICON_ICON_COLOR), b.expand)
		if c.disabled {
			ink = b.col.trailing
		}
		ops.fill(gtx.scene, ui.circle(ctr, BOX / 2), fill)
		turn := ops.mul(ops.mul(ops.translate(-ctr.x, -ctr.y), ops.rotate(-math.PI * b.expand)), ops.translate(ctr.x, ctr.y))
		ops.transform_push(gtx.scene, turn)
		icon(gtx, .Expand_More, {ctr.x - ICON / 2, ctr.y - ICON / 2}, ICON, ink)
		ops.transform_pop(gtx.scene)
		right -= tok.LIST_ITEM_BETWEEN_SPACE
	case .Reorder:
		ICON :: tok.LIST_ITEM_TRAILING_ICON_SIZE
		right -= ICON
		paint_drag_handle(gtx, {right, slot_y(top, b.pad_y, size.y, ICON)}, ICON, b.col.trailing)
		right -= tok.LIST_ITEM_BETWEEN_SPACE
	}
	if it.trailing_icon != .None {
		ICON :: tok.LIST_ITEM_TRAILING_ICON_EXPRESSIVE_SIZE
		right -= ICON
		icon(gtx, it.trailing_icon, {right, slot_y(top, b.pad_y, size.y, ICON)}, ICON, b.col.trailing)
		right -= tok.LIST_ITEM_BETWEEN_SPACE
	}
	if it.trailing_text != "" {
		t := shape_style(gtx, it.trailing_text, tok.LIST_ITEM_TRAILING_SUPPORTING_TEXT_FONT)
		right -= t.width
		draw_text(gtx, t, {right, slot_y(top, b.pad_y, size.y, t.height)}, b.col.trailing_text)
		right -= tok.LIST_ITEM_BETWEEN_SPACE
	}
	right += tok.LIST_ITEM_BETWEEN_SPACE

	tw := max(right - x, 0)
	y := slot_y(top, b.pad_y, size.y, list_text_height(it, b.lines))
	ops.clip_push(gtx.scene, ops.Rect{x, 0, tw, size.y})
	if it.overline != "" {
		y += draw_style_text(gtx, it.overline, {x, y}, tok.LIST_ITEM_OVERLINE_FONT, b.col.overline).height
	}
	y += draw_style_text(gtx, it.headline, {x, y}, tok.LIST_ITEM_LABEL_TEXT_FONT, b.col.label).height
	if it.supporting != "" {
		max_lines := b.lines == 3 && it.overline == "" ? 2 : 1
		sup := layout_style(gtx, it.supporting, tok.LIST_ITEM_SUPPORTING_TEXT_FONT, tw, max_lines = max_lines)
		draw_paragraph(gtx, sup, {x, y}, b.col.supporting)
	}
	ops.clip_pop(gtx.scene)
}

// list_text_height is the height of a row's text block.
@(private)
list_text_height :: proc(it: List_Item, lines: int) -> f32 {
	h := tok.LIST_ITEM_LABEL_TEXT_FONT.line_height
	if it.overline != "" {
		h += tok.LIST_ITEM_OVERLINE_FONT.line_height
	}
	if it.supporting != "" {
		n := f32(lines == 3 && it.overline == "" ? 2 : 1)
		h += n * tok.LIST_ITEM_SUPPORTING_TEXT_FONT.line_height
	}
	return h
}

// list_media_size is a leading media slot's token size.
@(private)
list_media_size :: proc(m: List_Media) -> (w, h: f32) {
	switch m {
	case .None:
	case .Image:
		return tok.LIST_ITEM_LEADING_IMAGE_WIDTH, tok.LIST_ITEM_LEADING_IMAGE_HEIGHT
	case .Small_Video:
		return tok.LIST_ITEM_SMALL_LEADING_VIDEO_WIDTH, tok.LIST_ITEM_SMALL_LEADING_VIDEO_HEIGHT
	case .Large_Video:
		return tok.LIST_ITEM_LARGE_LEADING_VIDEO_WIDTH, tok.LIST_ITEM_LARGE_LEADING_VIDEO_HEIGHT
	}
	return
}

// REVEAL_GAP is the space between a reveal row's action buttons; the kit
// has no token for it.
@(private)
REVEAL_GAP :: f32(8)

// list_reveal_width is how far a reveal row slides to uncover n actions:
// small icon buttons, REVEAL_GAP apart and REVEAL_GAP clear of the row,
// plus the row's trailing space.
@(private)
list_reveal_width :: proc(n: int) -> f32 {
	if n == 0 {
		return 0
	}
	return f32(n) * (tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT + REVEAL_GAP) + tok.LIST_ITEM_TRAILING_SPACE
}

// paint_reveal_actions draws a reveal row's actions at its trailing edge
// and, while the row is open, takes their clicks. The last is the primary
// action (primary container, rounded square); the rest are secondary
// containers, full shape (comp.reveal-list).
@(private)
paint_reveal_actions :: proc(gtx: ^ui.Ctx, it: List_Item, row: ops.Area_Id, size: ops.Size, offset: f32, rc: Control, gs: ^List_Item_State) {
	n := len(it.actions)
	if n == 0 {
		return
	}
	BOX :: tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT
	ICON :: tok.SMALL_ICON_BUTTON_ICON_SIZE
	x := size.x - tok.LIST_ITEM_TRAILING_SPACE - f32(n) * BOX - f32(n - 1) * REVEAL_GAP
	y := (size.y - BOX) / 2
	open := -offset > 1
	for g, i in it.actions {
		r := ops.Rect{x, y, BOX, BOX}
		primary := i == n - 1
		sh := primary ? tok.REVEAL_LIST_ITEM_ICON_BUTTON_ACTION_CONTAINER_SHAPE : tok.REVEAL_LIST_ITEM_ICON_BUTTON_CONTAINER_SHAPE
		fill := color(primary ? tok.REVEAL_LIST_ITEM_ACTION_ICON_BUTTON_CONTAINER_COLOR : tok.REVEAL_LIST_ITEM_ICON_BUTTON_CONTAINER_COLOR)
		ink := color(primary ? tok.REVEAL_LIST_ITEM_ACTION_BUTTON_ICON_ICON_COLOR : tok.REVEAL_LIST_ITEM_BUTTON_ICON_ICON_COLOR)
		shape := rounded(gtx, r, corners(sh, r))
		id := ui.id_mix(row, u64(100 + i))
		ac := control(gtx, id, r, open && rc.st != nil ? .Live : .Enabled)
		if ac.clicked && it.action != nil {
			it.action^ = i
			if gs != nil {
				gs.reveal.target = 0
			}
		}
		ops.fill(gtx.scene, shape, fill)
		paint_state_layer(gtx, ac, shape, ink)
		icon(gtx, g, {x + (BOX - ICON) / 2, y + (BOX - ICON) / 2}, ICON, ink)
		paint_focus_ring_corners(gtx, ac, r, corners(sh, r))
		listen(gtx, ac, id, r)
		if ac.st != nil {
			ops.tag(gtx.scene, id, fmt.aprintf("%s action %d", it.headline, i, allocator = gtx.allocator))
		}
		x += BOX + REVEAL_GAP
	}
}

// paint_drag_handle draws a size-px drag handle, two columns of three
// dots: the icon set has no drag_indicator glyph.
@(private)
paint_drag_handle :: proc(gtx: ^ui.Ctx, at: ops.Point, size: f32, ink: ops.Color) {
	r := size / 12
	for col in 0 ..< 2 {
		for row in 0 ..< 3 {
			cx := at.x + size * (col == 0 ? 0.375 : 0.625)
			cy := at.y + size * (0.25 + 0.25 * f32(row))
			ops.fill(gtx.scene, ui.circle({cx, cy}, r), ink)
		}
	}
}

// divider is M3's divider: a comp.divider.thickness line of
// comp.divider.color across the offered width (height when vertical).
// Compose leaves insets to the caller's layout (Divider.kt:49-89); inset
// and inset_end do it here for convenience, and a middle-inset divider
// passes the same to both. thickness overrides the token: 8 is the heavy
// divider of mdc:Divider.md, per divider.json. line_color, when painted,
// overrides the colour. length is the line's extent when the constraints
// leave it unbounded (a vertical divider in a row inside a scroll view),
// which otherwise draws nothing.
divider :: proc(
	gtx: ^ui.Ctx,
	inset: f32 = 0,
	inset_end: f32 = 0,
	vertical := false,
	thickness: f32 = tok.DIVIDER_THICKNESS,
	line_color := ops.Color{},
	length: f32 = 0,
	key: u64 = 0,
	loc := #caller_location,
) {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	ink := ui.painted(line_color) ? line_color : color(tok.DIVIDER_COLOR)
	size: ops.Size
	if vertical {
		size = {thickness, cs.max.y < ui.INF ? cs.max.y : max(cs.min.y, length)}
		ops.fill(gtx.scene, ops.Rect{0, inset, thickness, max(size.y - inset - inset_end, 0)}, ink)
	} else {
		size = {cs.max.x < ui.INF ? cs.max.x : max(cs.min.x, length), thickness}
		ops.fill(gtx.scene, ops.Rect{inset, 0, max(size.x - inset - inset_end, 0), thickness}, ink)
	}
	ui.semantics(gtx, &p, {role = .Separator})
	ui.widget_close(gtx, &p, {size = ui.constrain(cs, size)})
}
