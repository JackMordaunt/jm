package ui

// icon_button is M3's "standard" icon button: no container, a single
// glyph centred in a hit target defaulting to 40x40 (_md-comp-icon-button.
// scss's state-layer-height/-width), and a caller-owned
// selected^ toggle — the same shape checkbox uses for value^, but round
// and icon-only. It flips selected^ on click or Enter/Space while
// focused, and returns true on the frame it did. glyph is shaped through
// the ordinary text path, so any font that has the character works;
// jm:ui has no icon-font/vector-icon asset pipeline, so callers pass a
// Unicode symbol ("+", "✓", "⚙") rather than a named icon.
icon_button :: proc(
	gtx: ^Ctx,
	glyph: string,
	selected: ^bool,
	style := Icon_Button_Style{},
	disabled := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_begin(gtx, key, loc)
	s := resolve_icon_button(gtx.theme, style)
	run, m := shape_line(gtx, glyph, s.size)
	lh := line_height(m)
	size := constrain_min(gtx.constraints, {max(s.box, run.advance), max(s.box, lh)})
	area := Rect{0, 0, size.x, size.y}
	rr := Round_Rect{area, size.y / 2}

	toggled := false
	content := selected^ ? s.selected_icon : s.icon
	layer_opacity: f32
	st: ^Widget_State
	if disabled {
		content = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTENT_OPACITY)
	} else {
		st = widget_state(gtx, p.id)
		if click_from_events(gtx, p.id, st, area) {
			selected^ = !selected^
			toggled = true
		}
		switch {
		case st.pressed:
			layer_opacity = STATE_PRESSED_OPACITY
		case st.focused:
			layer_opacity = STATE_FOCUS_OPACITY
		case st.hovered:
			layer_opacity = STATE_HOVER_OPACITY
		}
	}

	if layer_opacity > 0 {
		fill(gtx.ops, rr, with_alpha(content, layer_opacity))
	}
	if st != nil {
		paint_ripple(gtx, st, rr, content)
	}
	origin := Point{(size.x - run.advance) / 2, (size.y - lh) / 2 + m.ascent}
	if painted(content) {
		glyphs(gtx.ops, add_run(gtx.ops, run), origin, content)
	}
	if !disabled {
		input_area(gtx.ops, p.id, rr, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur})
	}
	tag(gtx.ops, p.id, frame_string(gtx, glyph))
	widget_end(gtx, &p, {size, origin.y})
	return toggled
}
