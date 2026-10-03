/*
Package design is what every design system built on jm:ui shares, and
nothing any one of them owns. A system (ui/material, ui/fluent) supplies
three inputs and gets its components from them:

  - semantics: a Role enum for its colours and a Context enum for its
    modes (light, dark, high contrast);
  - a Theme(Role, Context): the binding from every context and role to a
    colour, however the system's aesthetic produced it;
  - axioms: relations over role pairs, as data, that check verifies in
    every context — "on-primary reads on primary", "outline is visible on
    surface".

What this package holds is the machinery under those inputs, in four
parts:

  - Interaction: the states a control can be in and Control, one frame's
    resolved state for a widget (control, listen, animate). How a state
    is painted is the system's: Material overlays a translucent layer,
    Fluent and Primer bind a colour role per state, which State_Roles
    and role_for pick and blend eases between. All read the same Control.
  - Geometry: per-corner radii (Corners, rounded), arcs, inside strokes,
    focus rings, touch targets, box-shadow layers and CSS easing.
  - Text: a composite type style, a weight-to-face lookup, and shaping
    and drawing a run inside a line box.
  - Theme and check: the generic binding table, axioms and the colour
    metrics (OKLab lightness, APCA and WCAG contrast) that measure them.

Nothing here is thread-local or global. A system keeps its own active
scheme, faces and motion set, and passes what these procs need.
*/
package design

import "jm:ui"
import "jm:ui/ops"

// Interaction is the state a component paints. Live follows real input;
// the rest force one look and take no input, so a gallery can show every
// state of a component side by side.
Interaction :: enum u8 {
	Live,
	Enabled,
	Hovered,
	Focused,
	Pressed,
	Dragged,
	Disabled,
}

// STATES is every forced Interaction, in the order specs show them.
STATES :: [?]Interaction{.Enabled, .Hovered, .Focused, .Pressed, .Disabled}

// Control is one frame's interaction outcome for a component: whether it
// was activated, what it is doing, and the single state that summarises
// that for painting.
Control :: struct {
	st:            ^ui.Widget_State, // nil unless Live
	clicked:       bool,
	hovered:       bool,
	pressed:       bool,
	focused:       bool, // paint a focus ring
	focus_visible: bool, // focused by keyboard (ui.focus_visible), for a system that rings only then
	disabled:      bool,
	state:         Interaction, // never Live: the strongest of the flags, by effective_state's order
	press:         bool, // a left press or keyboard activation landed this frame, at press_at
	press_at:      ops.Point,
	clicks:        u8, // that press's count: 2 for a double click
}

// control resolves state for the component with id and bounds. Live reads
// this frame's events, so a click or an Enter/Space while focused sets
// clicked; the forced states only set what to paint.
control :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, bounds: ops.Rect, state: Interaction) -> Control {
	c: Control
	switch state {
	case .Live:
		c.st = ui.widget_state(gtx, id)
		a := ui.activate_from_events(gtx, id, c.st, bounds)
		c.clicked, c.press, c.press_at, c.clicks = a.clicked, a.press, a.at, a.clicks
		c.hovered, c.pressed, c.focused = c.st.hovered, c.st.pressed, c.st.focused
		c.focus_visible = c.focused && ui.focus_visible(gtx)
	case .Enabled:
	case .Hovered:
		c.hovered = true
	case .Focused:
		c.focused, c.focus_visible = true, true
	case .Pressed, .Dragged:
		c.pressed = true
	case .Disabled:
		c.disabled = true
	}
	c.state = state == .Dragged ? .Dragged : effective_state(c)
	return c
}

// effective_state is the one state c's flags amount to, strongest first:
// disabled, pressed, focused, hovered, else enabled. Dragged is not a
// flag, so it is only ever forced.
effective_state :: proc(c: Control) -> Interaction {
	switch {
	case c.disabled:
		return .Disabled
	case c.pressed:
		return .Pressed
	case c.focused:
		return .Focused
	case c.hovered:
		return .Hovered
	}
	return .Enabled
}

// CLICK_KINDS is what a clickable component's input area asks for.
CLICK_KINDS :: ops.Event_Kinds{.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur}

// EDIT_KINDS is what a text field's input area asks for: a click's kinds
// plus typed text and the wheel, which scrolls a field's text.
EDIT_KINDS :: CLICK_KINDS + {.Text, .Scroll}

// listen registers id's input area when st is live (a Control's st, nil
// for a forced state); no_tab keeps it out of Tab's order (see
// ops.Input_Area).
listen :: proc(gtx: ^ui.Ctx, st: ^ui.Widget_State, id: ops.Area_Id, shape: ops.Shape, kinds := CLICK_KINDS, cursor := ops.Cursor.Default, no_tab := false) {
	if st != nil {
		ops.input_area(gtx.scene, id, shape, kinds, cursor, no_tab = no_tab)
	}
}

// animate moves c's spring slot (0-3, numbered by the component) toward
// target along a spring with params p and returns its value. A forced
// state (c.st nil) has no retained state, so it is the target at once.
// threshold is the settle distance in the value's own unit: 0.01 for a
// 0-1 fraction, 0.1 for dp.
animate :: proc(gtx: ^ui.Ctx, c: Control, slot: int, target: f32, p: ui.Spring_Params, threshold := ui.SPRING_THRESHOLD) -> f32 {
	if c.st == nil {
		return target
	}
	return ui.spring_update(&c.st.springs[slot], gtx, target, p, threshold)
}

// fade is c with its alpha scaled by t, for content fading in or out.
fade :: proc(c: ops.Color, t: f32) -> ops.Color {
	return ops.with_alpha(c, f32(c[3]) / 255 * clamp(t, 0, 1))
}

// touch_target is r grown to at least min on each axis, about its centre.
touch_target :: proc(r: ops.Rect, min_side: f32) -> ops.Rect {
	dw, dh := max(min_side - r.w, 0), max(min_side - r.h, 0)
	return {r.x - dw / 2, r.y - dh / 2, r.w + dw, r.h + dh}
}

// Focus_Ring is how a system draws keyboard focus: a stroke of width
// sitting offset outside the component's edge.
Focus_Ring :: struct {
	width:  f32,
	offset: f32,
	color:  ops.Color,
}

// paint_focus_ring paints ring around rr when c is focused and enabled.
paint_focus_ring :: proc(gtx: ^ui.Ctx, c: Control, rr: ops.Round_Rect, ring: Focus_Ring, inward := false) {
	paint_focus_ring_corners(gtx, c, rr.rect, corners_all(rr.radius), ring, inward)
}

// paint_focus_ring_corners is paint_focus_ring for per-corner radii k.
//
// inward draws the ring just inside the shape instead, its outer edge on
// the shape's: for controls packed closer than the ring's reach
// (connected groups, segments, list and menu rows, tabs, calendar days),
// where an outward ring would cross into the neighbours.
paint_focus_ring_corners :: proc(gtx: ^ui.Ctx, c: Control, r: ops.Rect, k: Corners, ring: Focus_Ring, inward := false) {
	if !c.focused || c.disabled {
		return
	}
	o := inward ? -ring.width / 2 : ring.offset + ring.width / 2
	rect := ops.Rect{r.x - o, r.y - o, r.w + 2 * o, r.h + 2 * o}
	ops.stroke(gtx.scene, rounded(gtx, rect, grow_corners(k, o)), ring.color, {width = ring.width})
}

// paint_focus_visible_ring is paint_focus_ring_corners shown only while
// c.focus_visible, keyboard focus: a control focused by a click shows
// nothing. Fluent's and Primer's kits cite :focus-visible for their
// indicators (createFocusOutlineStyle.ts, focusOutline.css).
paint_focus_visible_ring :: proc(gtx: ^ui.Ctx, c: Control, r: ops.Rect, k: Corners, ring: Focus_Ring) {
	b := c
	b.focused = c.focus_visible
	paint_focus_ring_corners(gtx, b, r, k, ring)
}

// stroke_inside strokes the inside edge of rr at width w.
stroke_inside :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, color: ops.Color, w: f32 = 1) {
	h := w / 2
	r := rr.rect
	ops.stroke(gtx.scene, ops.Round_Rect{{r.x + h, r.y + h, r.w - w, r.h - w}, max(rr.radius - h, 0)}, color, {width = w})
}

// stroke_inside_corners strokes the inside edge of r with per-corner
// radii k at width w: stroke_inside for a shape a Round_Rect cannot hold.
stroke_inside_corners :: proc(gtx: ^ui.Ctx, r: ops.Rect, k: Corners, color: ops.Color, w: f32) {
	h := w / 2
	ops.stroke(gtx.scene, rounded(gtx, {r.x + h, r.y + h, r.w - w, r.h - w}, grow_corners(k, -h)), color, {width = w})
}

// Bezier is a CSS-style cubic-bezier easing, [x1, y1, x2, y2].
Bezier :: [4]f32

// bezier_ease is easing b at x in [0, 1]: it solves the curve's x for its
// parameter, then returns y there.
bezier_ease :: proc(b: Bezier, x: f32) -> f32 {
	if x <= 0 {
		return 0
	}
	if x >= 1 {
		return 1
	}
	curve :: proc(p1, p2, u: f32) -> f32 {
		v := 1 - u
		return 3 * v * v * u * p1 + 3 * v * u * u * p2 + u * u * u
	}
	// Bisection: x(u) rises monotonically for any easing whose control
	// points' x lie in [0, 1], and 24 halvings are finer than f32.
	lo, hi: f32 = 0, 1
	for _ in 0 ..< 24 {
		mid := (lo + hi) / 2
		if curve(b[0], b[2], mid) < x {
			lo = mid
		} else {
			hi = mid
		}
	}
	return curve(b[1], b[3], (lo + hi) / 2)
}

// Box_Shadow is one layer of a CSS box-shadow: offset by x and y, blurred
// by blur (the CSS blur radius), grown by spread, in color. A system's
// shadow or elevation token is one or more of these.
Box_Shadow :: struct {
	x, y, blur, spread: f32,
	color:              ops.Color,
}

// paint_box_shadow paints layer s of rr's shadow: rr offset and spread,
// corners growing with the spread, as an ops.Shadow the renderer computes
// exactly. paint_inset_shadow paints a layer cast inward instead.
paint_box_shadow :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, s: Box_Shadow) {
	if s.color[3] == 0 {
		return
	}
	r := rr.rect
	e := s.spread
	ops.shadow(gtx.scene, {r.x + s.x - e, r.y + s.y - e, r.w + 2 * e, r.h + 2 * e}, max(rr.radius + e, 0), max(s.blur, 0), s.color)
}

// paint_shadow_layer is paint_box_shadow for a layer with no spread.
paint_shadow_layer :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, x, y, blur: f32, color: ops.Color) {
	paint_box_shadow(gtx, rr, {x, y, blur, 0, color})
}

// paint_inset_shadow paints layer s cast inward, inside rr: CSS's inset
// box-shadow, rr less a hole that is rr offset by x and y and shrunk by
// spread, its corners shrinking with it, clipped to rr. Only a sharp
// layer (blur 0) is drawn: ops.Shadow, which the renderer computes in
// closed form, is the blur of a shape cast outward, and the one inset
// token among the kits, the primer-kit's --shadow-inset, has blur 0.
paint_inset_shadow :: proc(gtx: ^ui.Ctx, rr: ops.Round_Rect, s: Box_Shadow) {
	assert(s.blur == 0, "design: a blurred inset shadow is not drawn; only blur 0 is supported")
	if s.color[3] == 0 {
		return
	}
	r, e := rr.rect, s.spread
	hole := ops.Rect{r.x + s.x + e, r.y + s.y + e, r.w - 2 * e, r.h - 2 * e}
	ops.clip_push(gtx.scene, rr)
	defer ops.clip_pop(gtx.scene)
	if hole.w <= 0 || hole.h <= 0 {
		ops.fill(gtx.scene, rr, s.color)
		return
	}
	k := corners_all(rr.radius)
	ops.fill(gtx.scene, ring_path(gtx, r, k, hole, grow_corners(k, -e)), s.color)
}
