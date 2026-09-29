package material

import "core:math"
import "jm:ui/ops"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Selection controls: checkbox, radio button, switch, per the m3e-kit's
// components/{checkbox,radio-button,switch}.json. Each takes the kit's
// 48dp minimum touch target (foundations.json interaction.touchTarget),
// with its 40dp state layer centred in it, and an optional body-large
// label to its right that is part of the hit target (the specs'
// "whole row is one tap target" list-item pattern).
//
// Hover, focus and press never recolour these controls: comp.checkbox,
// comp.radio-button and comp.switch carry per-interaction colour tokens,
// but every spec's notes say Compose never reads them. Feedback is the
// state layer (and the switch handle's press squish) alone.

// STROKE is the checkmark and radio ring width: hard-coded in Compose, not
// a token (checkbox.json layout, Checkbox.kt:485,662; radio-button.json
// layout, RadioButton.kt:186,322-323). The checkbox outline has tokens.
@(private = "file")
STROKE :: f32(2)

// CHECK_SNAP_DELAY is how long an unchecked checkbox keeps its mark while the
// box fades out, in seconds (checkbox.json behaviour, Checkbox.kt:1049).
@(private = "file")
CHECK_SNAP_DELAY :: f32(0.1)

// RADIO_DOT is the selected radio's dot radius at rest; comp.radio-button
// has no token for it (radio-button.json layout, RadioButton.kt:187,320-321).
@(private = "file")
RADIO_DOT :: f32(6)

// selection_label lays text after a control's touch target, body-large
// on_surface, vertically centred in h.
@(private)
selection_label :: proc(gtx: ^ui.Ctx, label: string, x: f32, h: f32, disabled: bool) -> f32 {
	if label == "" {
		return 0
	}
	t := shape_text(gtx, label, .Body_Large)
	draw_text(gtx, t, {x, (h - t.height) / 2}, disabled ? disabled_content() : scheme()[.On_Surface])
	return t.width
}

// label_width is the room a label takes after a control: its width and a
// 4dp end gap, or nothing without one.
@(private)
label_width :: proc(gtx: ^ui.Ctx, label: string) -> f32 {
	if label == "" {
		return 0
	}
	return shape_text(gtx, label, .Body_Large).width + 4
}

// token_color is role r at a token's opacity: a disabled-*-color plus its
// disabled-*-opacity.
@(private)
token_color :: proc(r: tok.Role, opacity: f32 = 1) -> ops.Color {
	return ops.with_alpha(color(r), opacity)
}

// snap_spring puts spring slot of c at v with no motion, for the values a
// spec says jump rather than animate.
@(private)
snap_spring :: proc(c: Control, slot: int, v: f32) {
	if c.st != nil {
		c.st.springs[slot] = {value = v, target = v, started = true}
	}
}

// Check_Snap_Clock is how long an unchecked checkbox has held its mark, in
// seconds: the mark drops once it passes CHECK_SNAP_DELAY. Zero while
// checked and once the mark has dropped.
@(private = "file")
Check_Snap_Clock :: struct {
	seconds: f32,
}

// checkbox is M3's checkbox (checkbox.json): an 18dp box with a 2dp
// outline, filled with a checkmark when checked^ and with a dash when
// indeterminate (which a click resolves by setting checked^ true: a tap
// never cycles into indeterminate, the caller sets it). error takes the
// error colours. Returns true when clicked.
//
// Motion: the mark draws in on the default-spatial spring and morphs
// between check and dash on it too; the box colour fades in on
// default-effects and out on fast-effects; on uncheck the mark holds for
// 100ms and then vanishes in one frame. Disabled colours cut, not fade.
checkbox :: proc(
	gtx: ^ui.Ctx,
	checked: ^bool,
	label := "",
	indeterminate := false,
	error := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	lw := label_width(gtx, label)
	size := ui.constrain_min(gtx.constraints, {MIN_TOUCH + lw, MIN_TOUCH})
	c := control(gtx, p.id, {0, 0, size.x, size.y}, state)
	if c.clicked {
		checked^ = indeterminate ? true : !checked^
	}
	on := checked^ || indeterminate

	// Springs: 0 box colour in (0-1), 1 mark drawn (0-1), 2 check-to-dash
	// shift (0-1). The uncheck snap delay runs on its own Check_Snap_Clock.
	fill := animate(gtx, c, 0, on ? 1 : 0, on ? .Default_Effects : .Fast_Effects)
	shift := animate(gtx, c, 2, indeterminate ? 1 : 0, .Default_Spatial)
	draw: f32 = on ? 1 : 0
	if c.st != nil {
		d, clock := &c.st.springs[1], ui.widget_data(gtx, p.id, Check_Snap_Clock)
		switch {
		case on:
			clock^ = {}
			draw = animate(gtx, c, 1, 1, .Default_Spatial)
		case d.started && d.target != 0:
			// Box out: hold the mark while the colour fades, then drop it.
			clock.seconds += gtx.dt
			if clock.seconds < CHECK_SNAP_DELAY {
				draw = d.value
				ui.request_frame(gtx, CHECK_SNAP_DELAY - clock.seconds)
			} else {
				snap_spring(c, 1, 0)
				clock^ = {}
				draw = 0
			}
		case:
			draw = animate(gtx, c, 1, 0, .Default_Spatial)
		}
	}

	sel_box := color(error ? tok.CHECKBOX_SELECTED_ERROR_CONTAINER_COLOR : tok.CHECKBOX_SELECTED_CONTAINER_COLOR)
	mark := color(error ? tok.CHECKBOX_SELECTED_ERROR_ICON_COLOR : tok.CHECKBOX_SELECTED_ICON_COLOR)
	edge := color(error ? tok.CHECKBOX_UNSELECTED_ERROR_OUTLINE_COLOR : tok.CHECKBOX_UNSELECTED_OUTLINE_COLOR)
	if c.disabled {
		sel_box = token_color(tok.CHECKBOX_SELECTED_DISABLED_CONTAINER_COLOR, tok.CHECKBOX_SELECTED_DISABLED_CONTAINER_OPACITY)
		mark = color(tok.CHECKBOX_SELECTED_DISABLED_ICON_COLOR)
		edge = token_color(tok.CHECKBOX_UNSELECTED_DISABLED_OUTLINE_COLOR, tok.CHECKBOX_UNSELECTED_DISABLED_CONTAINER_OPACITY)
	}
	// The border fades from the outline colour to the box colour, so a
	// checked box is one filled shape (Checkbox.kt:675-698).
	border := ops.mix(edge, sel_box, fill)

	mid := ops.Point{MIN_TOUCH / 2, size.y / 2}
	layer := ui.circle(mid, tok.CHECKBOX_STATE_LAYER_SIZE / 2)
	paint_state_layer(gtx, c, layer, on ? sel_box : edge)

	cs := tok.CHECKBOX_CONTAINER_SIZE
	box := ops.Rect{mid.x - cs / 2, mid.y - cs / 2, cs, cs}
	rr := ops.Round_Rect{box, tok.CHECKBOX_CONTAINER_SHAPE.radii[0]}
	if fill > 0 {
		ops.fill(gtx.scene, rr, fade(sel_box, fill))
	}
	outline_w := c.disabled ? tok.CHECKBOX_UNSELECTED_DISABLED_OUTLINE_WIDTH : tok.CHECKBOX_UNSELECTED_OUTLINE_WIDTH
	stroke_inside(gtx, rr, border, outline_w)
	if draw > 0 {
		paint_checkmark(gtx, box, draw, shift, fade(mark, fill))
	}

	selection_label(gtx, label, MIN_TOUCH, size.y, c.disabled)
	paint_focus_ring(gtx, c, {{mid.x - 20, mid.y - 20, 40, 40}, 20})
	listen(gtx, c, p.id, ops.Rect{0, 0, size.x, size.y})
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label == "" ? "checkbox" : label))
	ui.widget_close(gtx, &p, {size = size})
	return c.clicked
}

// paint_checkmark strokes the checkbox mark in box: the check polyline
// (0.25, 0.5) (0.4, 0.65) (0.75, 0.3) of the box width, flattened toward
// a dash at y 0.5 as shift rises, drawn along its length to fraction draw
// (checkbox.json layout, Checkbox.kt:718-731).
@(private = "file")
paint_checkmark :: proc(gtx: ^ui.Ctx, box: ops.Rect, draw, shift: f32, col: ops.Color) {
	lerp :: proc(a, b, t: f32) -> f32 {return a + (b - a) * t}
	at :: proc(box: ops.Rect, x, y: f32) -> ops.Point {return {box.x + x * box.w, box.y + y * box.h}}
	a := at(box, 0.25, 0.5)
	b := at(box, lerp(0.4, 0.5, shift), lerp(0.65, 0.5, shift))
	e := at(box, 0.75, lerp(0.3, 0.5, shift))
	l1, l2 := math.hypot_f32((b - a).x, (b - a).y), math.hypot_f32((e - b).x, (e - b).y)
	d := clamp(draw, 0, 1) * (l1 + l2)
	pts: [3]ops.Point
	n := 2
	pts[0] = a
	if d <= l1 {
		pts[1] = l1 > 0 ? a + (b - a) * (d / l1) : a
	} else {
		pts[1] = b
		pts[2] = l2 > 0 ? b + (e - b) * ((d - l1) / l2) : b
		n = 3
	}
	ops.stroke(gtx.scene, ui.polyline(gtx, pts[:n]), col, {width = STROKE, cap = .Square, join = .Miter})
}

// radio_button is M3's radio (radio-button.json): a 20dp ring, 2dp, with a
// dot when selected; ring and dot share one colour. value is the caller's
// selection and index this button's; a click sets value^ = index. Returns
// true when that changed the selection.
//
// Motion: the dot grows from 0 and shrinks back on the fast-spatial
// spring; the colour moves on default-effects. radio-button.json
// accessibility.keyboard asks for arrow keys to move the selection within
// a group; they do not here, since a button does not know its group and
// jm:ui cannot move focus to a sibling. Space or Enter selects.
radio_button :: proc(
	gtx: ^ui.Ctx,
	value: ^int,
	index: int,
	label := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	lw := label_width(gtx, label)
	size := ui.constrain_min(gtx.constraints, {MIN_TOUCH + lw, MIN_TOUCH})
	c := control(gtx, p.id, {0, 0, size.x, size.y}, state)
	changed := c.clicked && value^ != index
	if c.clicked {
		value^ = index
	}
	on := value^ == index

	// Springs: 0 dot radius (dp), 1 colour toward selected (0-1).
	dot := animate(gtx, c, 0, on ? RADIO_DOT : 0, .Fast_Spatial, 0.1)
	f := animate(gtx, c, 1, on ? 1 : 0, .Default_Effects)
	sel := color(tok.RADIO_BUTTON_SELECTED_ICON_COLOR)
	unsel := color(tok.RADIO_BUTTON_UNSELECTED_ICON_COLOR)
	if c.disabled {
		sel = token_color(tok.RADIO_BUTTON_DISABLED_SELECTED_ICON_COLOR, tok.RADIO_BUTTON_DISABLED_SELECTED_ICON_OPACITY)
		unsel = token_color(tok.RADIO_BUTTON_DISABLED_UNSELECTED_ICON_COLOR, tok.RADIO_BUTTON_DISABLED_UNSELECTED_ICON_OPACITY)
	}
	col := ops.mix(unsel, sel, f)

	mid := ops.Point{MIN_TOUCH / 2, size.y / 2}
	paint_state_layer(gtx, c, ui.circle(mid, tok.RADIO_BUTTON_STATE_LAYER_SIZE / 2), on ? sel : color(.On_Surface))
	// Ring and dot both sit inside the icon box by half the stroke
	// (RadioButton.kt:182-189).
	ops.stroke(gtx.scene, ui.circle(mid, tok.RADIO_BUTTON_ICON_SIZE / 2 - STROKE / 2), col, {width = STROKE})
	if r := dot - STROKE / 2; r > 0 {
		ops.fill(gtx.scene, ui.circle(mid, r), col)
	}
	selection_label(gtx, label, MIN_TOUCH, size.y, c.disabled)
	paint_focus_ring(gtx, c, {{mid.x - 20, mid.y - 20, 40, 40}, 20})
	listen(gtx, c, p.id, ops.Rect{0, 0, size.x, size.y})
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label == "" ? "radio" : label))
	ui.widget_close(gtx, &p, {size = size})
	return changed
}

// switch_ is M3's switch (switch.json; switch is an Odin keyword): a
// 52x32 track and a handle that is 16dp off, 24dp on, and 28dp while
// pressed, hugging the track's near edge. icons puts a check on the on
// handle and a close on the off one, which also sizes the off handle as
// the on one. Returns true when clicked (on^ has flipped).
//
// Motion: handle size and position follow the fast-spatial spring, except
// while pressed, when both snap (Switch.kt:188,307-317). Colours cut.
switch_ :: proc(
	gtx: ^ui.Ctx,
	on: ^bool,
	label := "",
	icons := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	lw := label_width(gtx, label)
	TW :: tok.SWITCH_TRACK_WIDTH
	TH :: tok.SWITCH_TRACK_HEIGHT
	OUTLINE :: tok.SWITCH_TRACK_OUTLINE_WIDTH
	size := ui.constrain_min(gtx.constraints, {TW + (lw > 0 ? lw + 12 : 0), MIN_TOUCH})
	track := ops.Rect{0, (size.y - TH) / 2, TW, TH}
	c := control(gtx, p.id, {0, 0, size.x, size.y}, state)
	if c.clicked {
		on^ = !on^
	}
	sel := on^

	// Handle diameter: three tiers plus the icon override (Switch.kt:283-291).
	d := tok.SWITCH_UNSELECTED_HANDLE_WIDTH
	if sel || icons {
		d = tok.SWITCH_SELECTED_HANDLE_WIDTH
	}
	if c.pressed {
		d = tok.SWITCH_PRESSED_HANDLE_WIDTH
	}
	// Handle start edge: centred at rest; while pressed, one outline width
	// from the edge it travels toward. Travel is fixed by the selected size
	// whatever size is drawn (Switch.kt:295-305,670).
	travel_end := TW - tok.SWITCH_SELECTED_HANDLE_WIDTH - (TH - tok.SWITCH_SELECTED_HANDLE_HEIGHT) / 2
	x: f32
	switch {
	case c.pressed && sel:
		x = travel_end - OUTLINE
	case c.pressed:
		x = OUTLINE
	case sel:
		x = travel_end
	case:
		x = (TH - d) / 2
	}
	// Springs: 0 handle start x (dp), 1 handle diameter (dp).
	if c.pressed {
		snap_spring(c, 0, x)
		snap_spring(c, 1, d)
	} else {
		x = animate(gtx, c, 0, x, .Fast_Spatial, 0.1)
		d = animate(gtx, c, 1, d, .Fast_Spatial, 0.1)
	}

	track_col := color(sel ? tok.SWITCH_SELECTED_TRACK_COLOR : tok.SWITCH_UNSELECTED_TRACK_COLOR)
	outline := sel ? ops.Color{} : color(tok.SWITCH_UNSELECTED_TRACK_OUTLINE_COLOR)
	handle := color(sel ? tok.SWITCH_SELECTED_HANDLE_COLOR : tok.SWITCH_UNSELECTED_HANDLE_COLOR)
	icon_col := color(sel ? tok.SWITCH_SELECTED_ICON_COLOR : tok.SWITCH_UNSELECTED_ICON_COLOR)
	if c.disabled {
		if sel {
			track_col = token_color(tok.SWITCH_DISABLED_SELECTED_TRACK_COLOR, tok.SWITCH_DISABLED_TRACK_OPACITY)
			handle = token_color(tok.SWITCH_DISABLED_SELECTED_HANDLE_COLOR, tok.SWITCH_DISABLED_SELECTED_HANDLE_OPACITY)
			icon_col = token_color(tok.SWITCH_DISABLED_SELECTED_ICON_COLOR, tok.SWITCH_DISABLED_SELECTED_ICON_OPACITY)
		} else {
			track_col = token_color(tok.SWITCH_DISABLED_UNSELECTED_TRACK_COLOR, tok.SWITCH_DISABLED_TRACK_OPACITY)
			// No outline opacity token: Compose dims it by the track's (Switch.kt:437).
			outline = token_color(tok.SWITCH_DISABLED_UNSELECTED_TRACK_OUTLINE_COLOR, tok.SWITCH_DISABLED_TRACK_OPACITY)
			handle = token_color(tok.SWITCH_DISABLED_UNSELECTED_HANDLE_COLOR, tok.SWITCH_DISABLED_UNSELECTED_HANDLE_OPACITY)
			icon_col = token_color(tok.SWITCH_DISABLED_UNSELECTED_ICON_COLOR, tok.SWITCH_DISABLED_UNSELECTED_ICON_OPACITY)
		}
	}
	rr := ops.Round_Rect{track, TH / 2}
	ops.fill(gtx.scene, rr, track_col)
	if ui.painted(outline) {
		stroke_inside(gtx, rr, outline, OUTLINE)
	}
	centre := ops.Point{track.x + x + d / 2, track.y + TH / 2}
	// State layer and focus ring sit on the handle, not the track
	// (switch.json accessibility).
	paint_state_layer(gtx, c, ui.circle(centre, tok.SWITCH_STATE_LAYER_SIZE / 2), sel ? color(.Primary) : color(.On_Surface))
	ops.fill(gtx.scene, ui.circle(centre, max(d, 0) / 2), handle)
	if icons {
		is := sel ? tok.SWITCH_SELECTED_ICON_SIZE : tok.SWITCH_UNSELECTED_ICON_SIZE
		icon(gtx, sel ? .Check : .Close, {centre.x - is / 2, centre.y - is / 2}, is, icon_col)
	}
	selection_label(gtx, label, TW + 12, size.y, c.disabled)
	h := tok.SWITCH_STATE_LAYER_SIZE / 2
	paint_focus_ring(gtx, c, {{centre.x - h, centre.y - h, 2 * h, 2 * h}, h})
	listen(gtx, c, p.id, ops.Rect{0, 0, size.x, size.y})
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label == "" ? "switch" : label))
	ui.widget_close(gtx, &p, {size = size})
	return c.clicked
}
