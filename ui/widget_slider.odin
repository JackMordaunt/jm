package ui

// slider sets value^ in [lo, hi] from the pointer: a Press jumps the knob
// there and Moves drag it while pressed (the router keeps delivering to the
// pressed area). Returns true when value^ changed. Its width is
// style.width clamped to the constraints, so a Fill-aligned column or
// flexible stretches it. name, if given, tags it for a probe.
slider :: proc(
	gtx: ^Ctx,
	value: ^f32,
	lo, hi: f32,
	name := "",
	style := Slider_Style{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_begin(gtx, key, loc)
	s := resolve_slider(gtx.theme, style)
	size := constrain(gtx.constraints, {s.width, s.knob_size})
	r := min(s.knob_size, size.y) / 2
	usable := max(size.x - 2 * r, 0)
	span := hi - lo

	st := widget_state(gtx, p.id)
	old := value^
	set :: proc(value: ^f32, x, r, usable, lo, span: f32) {
		t: f32 = usable > 0 ? clamp((x - r) / usable, 0, 1) : 0
		value^ = lo + t * span
	}
	for e in events(gtx, p.id) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Press:
			if e.button == .Left {
				st.pressed = true
				set(value, e.pos.x, r, usable, lo, span)
			}
		case .Move:
			if st.pressed {
				set(value, e.pos.x, r, usable, lo, span)
			}
		case .Release:
			if e.button == .Left {
				st.pressed = false
			}
		}
	}
	changed := value^ != old

	t: f32 = span != 0 ? clamp((value^ - lo) / span, 0, 1) : 0
	o := gtx.ops
	ts := min(s.track_size, size.y)
	ty := (size.y - ts) / 2
	if painted(s.track) {
		fill(o, Round_Rect{{r, ty, usable, ts}, ts / 2}, s.track)
	}
	if painted(s.fill) && t > 0 {
		fill(o, Round_Rect{{r, ty, t * usable, ts}, ts / 2}, s.fill)
	}
	knob := s.knob
	if st.pressed {
		knob = mix(knob, {0, 0, 0, knob[3]}, 0.2)
	} else if st.hovered {
		knob = mix(knob, {255, 255, 255, knob[3]}, 0.15)
	}
	cy := size.y / 2
	if painted(knob) {
		fill(o, Ellipse{{t * usable, cy - r, 2 * r, 2 * r}}, knob)
	}
	input_area(o, p.id, Rect{0, 0, size.x, size.y}, {.Press, .Release, .Move, .Enter, .Leave})
	if len(name) > 0 {
		tag(o, p.id, frame_string(gtx, name))
	}
	widget_end(gtx, &p, {size = size})
	return changed
}
