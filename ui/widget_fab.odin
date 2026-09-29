package ui

// fab is Material's "signature action": a fixed-size container (size,
// via fab_box) holding one centred glyph, always in the primary-container
// colour pair. M3 defines no disabled FAB — it's meant to always be
// available — so fab takes no disabled parameter.
fab :: proc(
	gtx: ^Ctx,
	glyph: string,
	size := Fab_Size.Regular,
	style := Fab_Style{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_begin(gtx, key, loc)
	s := resolve_fab(gtx.theme, style)
	box, radius, icon_size := fab_box(size)
	run, m := shape_line(gtx, glyph, icon_size)
	lh := line_height(m)
	sz := constrain_min(gtx.constraints, {max(box, run.advance), max(box, lh)})
	area := Rect{0, 0, sz.x, sz.y}
	rr := Round_Rect{area, radius}

	st := widget_state(gtx, p.id)
	clicked := click_from_events(gtx, p.id, st, area)
	layer_opacity: f32
	switch {
	case st.pressed:
		layer_opacity = STATE_PRESSED_OPACITY
	case st.focused:
		layer_opacity = STATE_FOCUS_OPACITY
	case st.hovered:
		layer_opacity = STATE_HOVER_OPACITY
	}

	if painted(s.fill) {
		fill(gtx.ops, rr, s.fill)
	}
	if layer_opacity > 0 {
		fill(gtx.ops, rr, with_alpha(s.icon, layer_opacity))
	}
	origin := Point{(sz.x - run.advance) / 2, (sz.y - lh) / 2 + m.ascent}
	if painted(s.icon) {
		glyphs(gtx.ops, add_run(gtx.ops, run), origin, s.icon)
	}
	input_area(gtx.ops, p.id, rr, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur})
	tag(gtx.ops, p.id, frame_string(gtx, glyph))
	widget_end(gtx, &p, {sz, origin.y})
	return clicked
}

// extended_fab is fab with a label beside the icon, at the regular size's
// 56px height and corner-large radius, and a pill width that grows to fit
// icon + gap + label.
extended_fab :: proc(
	gtx: ^Ctx,
	glyph: string,
	text: string,
	style := Fab_Style{},
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := widget_begin(gtx, key, loc)
	s := resolve_fab(gtx.theme, style)
	_, radius, icon_size := fab_box(.Regular)
	height: f32 = 56
	gap: f32 = 12
	pad_x: f32 = 20

	irun, im := shape_line(gtx, glyph, icon_size)
	trun, tm := shape_line(gtx, text, gtx.theme.text_size)
	w := pad_x + irun.advance + gap + trun.advance + pad_x
	size := constrain_min(gtx.constraints, {w, max(height, line_height(im), line_height(tm))})
	area := Rect{0, 0, size.x, size.y}
	rr := Round_Rect{area, radius}

	st := widget_state(gtx, p.id)
	clicked := click_from_events(gtx, p.id, st, area)
	layer_opacity: f32
	switch {
	case st.pressed:
		layer_opacity = STATE_PRESSED_OPACITY
	case st.focused:
		layer_opacity = STATE_FOCUS_OPACITY
	case st.hovered:
		layer_opacity = STATE_HOVER_OPACITY
	}

	if painted(s.fill) {
		fill(gtx.ops, rr, s.fill)
	}
	if layer_opacity > 0 {
		fill(gtx.ops, rr, with_alpha(s.text, layer_opacity))
	}
	iy := (size.y - line_height(im)) / 2 + im.ascent
	if painted(s.icon) {
		glyphs(gtx.ops, add_run(gtx.ops, irun), {pad_x, iy}, s.icon)
	}
	ty := (size.y - line_height(tm)) / 2 + tm.ascent
	if painted(s.text) {
		glyphs(gtx.ops, add_run(gtx.ops, trun), {pad_x + irun.advance + gap, ty}, s.text)
	}
	input_area(gtx.ops, p.id, rr, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur})
	tag(gtx.ops, p.id, frame_string(gtx, text))
	widget_end(gtx, &p, {size, ty})
	return clicked
}
