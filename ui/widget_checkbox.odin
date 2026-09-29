package ui

// checkbox is a box, a check mark when value^ is set, and text, in a row.
// A click anywhere on it flips value^; it returns true on that frame.
checkbox :: proc(
	gtx: ^Ctx,
	text: string,
	value: ^bool,
	style := Checkbox_Style{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_open(gtx, key, loc)
	s := resolve_checkbox(gtx.theme, style)
	run, m := shape_line(gtx, text, s.size)
	lh := line_height(m)
	side := s.size + 2
	h := max(side, lh)
	w := side
	if len(text) > 0 {
		w += s.gap + run.advance
	}
	size := constrain(gtx.constraints, {w, h})
	area := Rect{0, 0, size.x, size.y}

	st := widget_state(gtx, p.id)
	changed := click_from_events(gtx, p.id, st, area)
	if changed {
		value^ = !value^
	}

	o := gtx.ops
	y := (h - side) / 2
	bx := Round_Rect{{0, y, side, side}, s.radius}
	if value^ {
		if painted(s.checked) {
			fill(o, bx, s.checked)
		}
		if painted(s.mark) {
			mark := polyline(
				gtx,
				[]Point {
					{0.24 * side, y + 0.52 * side},
					{0.42 * side, y + 0.70 * side},
					{0.76 * side, y + 0.30 * side},
				},
			)
			stroke(o, mark, s.mark, {width = max(side / 8, 1.5), cap = .Round, join = .Round})
		}
	} else {
		if painted(s.box) {
			fill(o, bx, s.box)
		}
		edge := st.hovered ? gtx.theme.accent : s.outline
		width := max(gtx.theme.stroke, 1)
		if painted(edge) {
			half := width / 2
			stroke(
				o,
				Round_Rect{{half, y + half, side - width, side - width}, s.radius},
				edge,
				{width = width},
			)
		}
	}
	origin := Point{side + s.gap, (h - lh) / 2 + m.ascent}
	if len(text) > 0 && painted(s.text) {
		glyphs(o, add_run(o, run), origin, s.text)
	}
	input_area(o, p.id, area, {.Press, .Release, .Enter, .Leave, .Move})
	tag(o, p.id, frame_string(gtx, text))
	widget_close(gtx, &p, {size, origin.y})
	return changed
}
