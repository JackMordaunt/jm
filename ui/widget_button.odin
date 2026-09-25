package ui

// button is a round-rect with its text centered. It returns true on the
// frame a Release arrives inside it after a Press on it. Hover and press
// colours follow Enter, Leave, Press and Release, kept in the layout's
// retained state under the button's id. Buttons made in a loop need a
// distinct key each.
button :: proc(
	gtx: ^Ctx,
	text: string,
	style := Button_Style{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_begin(gtx, key, loc)
	s := resolve_button(gtx.theme, style)
	run, m := shape_line(gtx, text, s.size)
	lh := line_height(m)
	pd := s.padding
	size := constrain(gtx.constraints, {run.advance + pd.left + pd.right, lh + pd.top + pd.bottom})
	area := Rect{0, 0, size.x, size.y}

	st := widget_state(gtx, p.id)
	clicked := click_from_events(gtx, p.id, st, area)

	paint := s.fill
	if st.pressed {
		paint = s.active
	} else if st.hovered {
		paint = s.hover
	}
	rr := Round_Rect{area, s.radius}
	if painted(paint) {
		fill(gtx.ops, rr, paint)
	}
	origin := Point{(size.x - run.advance) / 2, (size.y - lh) / 2 + m.ascent}
	if painted(s.text) {
		glyphs(gtx.ops, add_run(gtx.ops, run), origin, s.text)
	}
	input_area(gtx.ops, p.id, rr, {.Press, .Release, .Enter, .Leave, .Move})
	tag(gtx.ops, p.id, frame_string(gtx, text))
	widget_end(gtx, &p, {size, origin.y})
	return clicked
}

// click_from_events applies this frame's pointer events for area to st and
// reports a click: a left Release inside area while pressed.
@(private)
click_from_events :: proc(gtx: ^Ctx, area: Area_Id, st: ^Widget_State, bounds: Rect) -> bool {
	clicked := false
	for e in events(gtx, area) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Press:
			if e.button == .Left {
				st.pressed = true
			}
		case .Release:
			if e.button == .Left {
				if st.pressed && rect_contains(bounds, e.pos) {
					clicked = true
				}
				st.pressed = false
			}
		}
	}
	return clicked
}
