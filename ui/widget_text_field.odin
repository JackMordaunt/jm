package ui

import "core:unicode/utf8"

// Text_State is a single-line text buffer and its cursor, a byte offset
// that always sits on a rune boundary. The caller owns it; text_destroy
// frees the buffer.
Text_State :: struct {
	buf:    [dynamic]u8,
	cursor: int,
}

// text_string views the buffer as a string; valid until the next edit.
text_string :: proc(s: ^Text_State) -> string {
	return string(s.buf[:])
}

// text_set replaces the buffer with str and puts the cursor at its end.
text_set :: proc(s: ^Text_State, str: string) {
	clear(&s.buf)
	append(&s.buf, str)
	s.cursor = len(s.buf)
}

// text_destroy frees the buffer.
text_destroy :: proc(s: ^Text_State) {
	delete(s.buf)
	s^ = {}
}

// text_field edits s on one line. Text events insert at the cursor;
// Backspace, Delete, Left, Right, Home and End edit and move it; a Press
// puts the cursor under the pointer. It draws a caret while focused (Focus
// and Blur events, sent by the router) and scrolls horizontally to keep the
// caret in view. Text is clipped to the field. It is tagged with name, or
// "text field" when name is empty. Returns true when the text changed.
text_field :: proc(
	gtx: ^Ctx,
	s: ^Text_State,
	name := "",
	style := Text_Field_Style{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_begin(gtx, key, loc)
	fs := resolve_text_field(gtx.theme, style)
	m := metrics(gtx.shaper, gtx.theme.font, fs.size)
	lh := line_height(m)
	pd := fs.padding
	size := constrain(gtx.constraints, {fs.width, lh + pd.top + pd.bottom})
	inner := max(size.x - pd.left - pd.right, 0)

	st := widget_state(gtx, p.id)
	s.cursor = clamp(s.cursor, 0, len(s.buf))
	changed := false
	for e in events(gtx, p.id) {
		#partial switch e.kind {
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
		case .Press:
			s.cursor = text_hit(gtx, s, fs.size, e.pos.x - pd.left + st.scroll)
		case .Text:
			if len(e.text) > 0 {
				inject_at_elems(&s.buf, s.cursor, ..transmute([]u8)e.text)
				s.cursor += len(e.text)
				changed = true
			}
		case .Key:
			changed |= text_key(s, e.key)
		}
	}

	str := string(s.buf[:])
	run := shape(gtx.shaper, gtx.theme.font, fs.size, str, gtx.allocator)
	caret := run.advance
	if s.cursor < len(s.buf) {
		caret = shape(gtx.shaper, gtx.theme.font, fs.size, str[:s.cursor], gtx.allocator).advance
	}
	// Keep the caret (1px wide) inside the field, and don't scroll past the
	// end of the text.
	st.scroll = min(st.scroll, max(run.advance + 1 - inner, 0))
	st.scroll = clamp(st.scroll, caret + 1 - inner, caret)
	st.scroll = max(st.scroll, 0)

	o := gtx.ops
	rr := Round_Rect{{0, 0, size.x, size.y}, fs.radius}
	if painted(fs.fill) {
		fill(o, rr, fs.fill)
	}
	edge := st.focused ? fs.focus : fs.outline
	if fs.stroke > 0 && painted(edge) {
		h := fs.stroke / 2
		stroke(
			o,
			Round_Rect{{h, h, size.x - fs.stroke, size.y - fs.stroke}, max(fs.radius - h, 0)},
			edge,
			{width = fs.stroke},
		)
	}
	push_clip(o, Rect{pd.left, 0, inner, size.y})
	if painted(fs.text) && len(str) > 0 {
		glyphs(o, add_run(o, run), {pd.left - st.scroll, pd.top + m.ascent}, fs.text)
	}
	if st.focused && painted(fs.caret) {
		fill(o, Rect{pd.left + caret - st.scroll, pd.top, 1, lh}, fs.caret)
	}
	pop_clip(o)
	input_area(o, p.id, rr, {.Press, .Release, .Key, .Text, .Focus, .Blur})
	tag(o, p.id, frame_string(gtx, len(name) > 0 ? name : "text field"))
	widget_end(gtx, &p, {size, pd.top + m.ascent})
	return changed
}

// text_key applies an editing key to s; true when the text changed.
// Exported for text inputs built outside this package.
text_key :: proc(s: ^Text_State, k: Key) -> bool {
	#partial switch k {
	case .Backspace:
		if s.cursor > 0 {
			_, n := utf8.decode_last_rune(s.buf[:s.cursor])
			remove_range(&s.buf, s.cursor - n, s.cursor)
			s.cursor -= n
			return true
		}
	case .Delete:
		if s.cursor < len(s.buf) {
			_, n := utf8.decode_rune(s.buf[s.cursor:])
			remove_range(&s.buf, s.cursor, s.cursor + n)
			return true
		}
	case .Left:
		if s.cursor > 0 {
			_, n := utf8.decode_last_rune(s.buf[:s.cursor])
			s.cursor -= n
		}
	case .Right:
		if s.cursor < len(s.buf) {
			_, n := utf8.decode_rune(s.buf[s.cursor:])
			s.cursor += n
		}
	case .Home:
		s.cursor = 0
	case .End:
		s.cursor = len(s.buf)
	}
	return false
}

// text_hit returns the rune boundary nearest x (in text space). It shapes
// each prefix, which is exact for any shaper and cheap for one line.
text_hit :: proc(gtx: ^Ctx, s: ^Text_State, size: f32, x: f32) -> int {
	str := string(s.buf[:])
	best, best_d := 0, abs(x)
	for _, i in str {
		if i == 0 {
			continue
		}
		adv := shape(gtx.shaper, gtx.theme.font, size, str[:i], gtx.allocator).advance
		if d := abs(x - adv); d < best_d {
			best, best_d = i, d
		}
	}
	end := shape(gtx.shaper, gtx.theme.font, size, str, gtx.allocator).advance
	if abs(x - end) < best_d {
		best = len(str)
	}
	return best
}
