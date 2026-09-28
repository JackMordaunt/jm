package ui

// button is one of M3's five common buttons (style.kind), a round-rect
// with its text centred. It returns true on the frame a Release or an
// Enter/Space arrives while it has focus. Hover, press and focus each
// paint style.text over the container at STATE_*_OPACITY (see with_alpha
// in theme.odin) rather than a pre-mixed colour, so the same code paints
// every kind's state layer regardless of its container colour — including
// Outlined and Text, whose container is transparent. A Press or a
// keyboard activation also starts an ink ripple (see paint_ripple) from
// wherever it landed. A disabled button dims container, outline and text
// by STATE_DISABLED_*_OPACITY, tracks no pointer or focus state and shows
// no ripple, and never returns true. Buttons made in a loop need a
// distinct key each.
button :: proc(
	gtx: ^Ctx,
	text: string,
	style := Button_Style{},
	disabled := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_begin(gtx, key, loc)
	s := resolve_button(gtx.theme, style)
	run, m := shape_line(gtx, text, s.size)
	lh := line_height(m)
	pd := s.padding
	size := constrain_min(gtx.constraints, {run.advance + pd.left + pd.right, lh + pd.top + pd.bottom})
	area := Rect{0, 0, size.x, size.y}
	radius := or_size(s.radius, size.y / 2) // M3's corner-full: fully rounded
	rr := Round_Rect{area, radius}

	clicked := false
	container := s.fill
	outline := s.outline
	content := s.text
	layer_opacity: f32
	st: ^Widget_State
	if disabled {
		if painted(container) {
			container = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTAINER_OPACITY)
		}
		if painted(outline) {
			outline = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTAINER_OPACITY)
		}
		content = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTENT_OPACITY)
	} else {
		st = widget_state(gtx, p.id)
		clicked = click_from_events(gtx, p.id, st, area)
		switch {
		case st.pressed:
			layer_opacity = STATE_PRESSED_OPACITY
		case st.focused:
			layer_opacity = STATE_FOCUS_OPACITY
		case st.hovered:
			layer_opacity = STATE_HOVER_OPACITY
		}
	}

	if painted(container) {
		fill(gtx.ops, rr, container)
	}
	if painted(outline) {
		sw := max(gtx.theme.stroke, 1)
		half := sw / 2
		stroke(gtx.ops, Round_Rect{{half, half, size.x - sw, size.y - sw}, max(radius - half, 0)}, outline, {width = sw})
	}
	if layer_opacity > 0 {
		fill(gtx.ops, rr, with_alpha(s.text, layer_opacity))
	}
	if st != nil {
		paint_ripple(gtx, st, rr, s.text)
	}
	origin := Point{(size.x - run.advance) / 2, (size.y - lh) / 2 + m.ascent}
	if painted(content) {
		glyphs(gtx.ops, add_run(gtx.ops, run), origin, content)
	}
	if !disabled {
		input_area(gtx.ops, p.id, rr, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur})
	}
	tag(gtx.ops, p.id, frame_string(gtx, text))
	widget_end(gtx, &p, {size, origin.y})
	return clicked
}

// click_from_events applies this frame's events for area to st and reports
// a click: a left Release inside area while pressed, or an Enter/Space Key
// while focused — a widget that registers .Key and .Focus/.Blur in its
// input_area (button, icon_button, fab) becomes keyboard-activatable for
// free; one that doesn't (checkbox) sees no Key or Focus/Blur events at
// all, since the router only delivers what an area registered. Exported
// for widgets built outside this package (jm:ui/material's controls).
click_from_events :: proc(gtx: ^Ctx, area: Area_Id, st: ^Widget_State, bounds: Rect) -> bool {
	clicked := false
	for e in events(gtx, area) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
		case .Press:
			if e.button == .Left {
				st.pressed = true
				start_ripple(st, e.pos)
			}
		case .Release:
			if e.button == .Left {
				if st.pressed && rect_contains(bounds, e.pos) {
					clicked = true
				}
				st.pressed = false
			}
		case .Key:
			if e.key == .Enter || e.key == .Space {
				clicked = true
				start_ripple(st, {bounds.x + bounds.w / 2, bounds.y + bounds.h / 2}) // no pointer position for a keyboard activation
			}
		}
	}
	return clicked
}

// start_ripple (re)starts st's ink-ripple tween from origin, overwriting
// whatever ripple was already running — a second click restarts the
// animation rather than queuing or blending with the first. Simpler than
// tracking multiple concurrent ripples per widget; revisit if a rapid
// double-click ever needs to show two overlapping ripples at once.
start_ripple :: proc(st: ^Widget_State, origin: Point) {
	st.ripple = {to = 1, duration = RIPPLE_DURATION}
	st.ripple_origin = origin
}

// paint_ripple draws st's ink-ripple, if one is still running, as an
// expanding, fading circle of tint at alpha, clipped to shape — the
// button family's click feedback. Not M3-token-sourced like the state-
// layer opacities: Material's motion spec doesn't reduce to one number,
// so RIPPLE_DURATION and RIPPLE_PEAK_OPACITY are a deliberate, reasonable
// choice (the same intensity as the pressed state layer, fading out),
// not a verified value.
paint_ripple :: proc(gtx: ^Ctx, st: ^Widget_State, shape: Shape, tint: Color) {
	if st.ripple.t >= st.ripple.duration {
		return
	}
	t := tween_update(&st.ripple, gtx)
	bounds := shape_bounds(gtx.ops, shape)
	r := t * (bounds.w + bounds.h) // a cheap, safely-oversized bound on the
	// origin-to-farthest-corner distance, without a sqrt
	push_clip(gtx.ops, shape)
	fill(gtx.ops, Ellipse{{st.ripple_origin.x - r, st.ripple_origin.y - r, r * 2, r * 2}}, with_alpha(tint, (1 - t) * RIPPLE_PEAK_OPACITY))
	pop_clip(gtx.ops)
}
