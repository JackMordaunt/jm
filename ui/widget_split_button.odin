package ui

// split_button is a leading action fused to a trailing chevron toggle in
// one continuous pill, M3's own shape for it. It exists in the M3 spec
// (m3.material.io/components/split-button) but material-web's tokens
// (github.com/material-components/material-web, tokens/versions/v0_192,
// checked this session) has no _md-comp-split-button*.scss — this reuses
// button()'s own colour roles (style.kind, same as Button_Style) and
// state-layer opacities rather than fabricated split-button-specific
// numbers, since every button-family component checked this session
// (filled, tonal, outlined, text, elevated, icon, FAB, segmented) draws
// its state layer from the same md-sys-state opacities. The trailing
// half doesn't open a menu — jm:ui
// has no popup/overlay system — it just flips expanded^ and swaps the
// chevron glyph, the same caller-owned toggle icon_button uses; a real
// caller decides what expanded^ does. Returns (leading was clicked,
// trailing was toggled).
split_button :: proc(
	gtx: ^Ctx,
	text: string,
	expanded: ^bool,
	style := Button_Style{},
	disabled := false,
	key: u64 = 0,
	loc := #caller_location,
) -> (clicked: bool, toggled: bool) {
	p := widget_open(gtx, key, loc)
	s := resolve_button(gtx.theme, style)
	run, m := shape_line(gtx, text, s.size)
	lh := line_height(m)
	pd := s.padding
	chevron_w: f32 = 40 // a fixed square trailing segment, icon_button's own default box
	leading_w := run.advance + pd.left + pd.right
	height := lh + pd.top + pd.bottom
	size := constrain_min(gtx.constraints, {leading_w + chevron_w, height})
	leading_w = size.x - chevron_w // keep the chevron fixed-width if constrained wider
	radius := size.y / 2
	rr := Round_Rect{{0, 0, size.x, size.y}, radius}

	lead_rect := Rect{0, 0, leading_w, size.y}
	trail_rect := Rect{leading_w, 0, chevron_w, size.y}
	lead_id := id_mix(p.id, 1)
	trail_id := id_mix(p.id, 2)

	lead_container, trail_container := s.fill, s.fill
	lead_outline := s.outline
	lead_content, trail_content := s.text, s.text
	lead_layer, trail_layer: f32
	lst, tst: ^Widget_State
	if disabled {
		if painted(lead_container) {
			lead_container = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTAINER_OPACITY)
			trail_container = lead_container
		}
		if painted(lead_outline) {
			lead_outline = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTAINER_OPACITY)
		}
		lead_content = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTENT_OPACITY)
		trail_content = lead_content
	} else {
		lst = widget_state(gtx, lead_id)
		clicked = click_from_events(gtx, lead_id, lst, lead_rect)
		switch {
		case lst.pressed:
			lead_layer = STATE_PRESSED_OPACITY
		case lst.focused:
			lead_layer = STATE_FOCUS_OPACITY
		case lst.hovered:
			lead_layer = STATE_HOVER_OPACITY
		}
		tst = widget_state(gtx, trail_id)
		if click_from_events(gtx, trail_id, tst, trail_rect) {
			expanded^ = !expanded^
			toggled = true
		}
		switch {
		case tst.pressed:
			trail_layer = STATE_PRESSED_OPACITY
		case tst.focused:
			trail_layer = STATE_FOCUS_OPACITY
		case tst.hovered:
			trail_layer = STATE_HOVER_OPACITY
		}
	}

	clip_push(gtx.ops, rr)
	if painted(lead_container) {
		fill(gtx.ops, lead_rect, lead_container)
	}
	if painted(trail_container) {
		fill(gtx.ops, trail_rect, trail_container)
	}
	if lead_layer > 0 {
		fill(gtx.ops, lead_rect, with_alpha(lead_content, lead_layer))
	}
	if trail_layer > 0 {
		fill(gtx.ops, trail_rect, with_alpha(trail_content, trail_layer))
	}
	if lst != nil {
	}
	if tst != nil {
	}
	clip_pop(gtx.ops)

	if painted(lead_outline) {
		sw := max(gtx.theme.stroke, 1)
		half := sw / 2
		stroke(gtx.ops, Round_Rect{{half, half, size.x - sw, size.y - sw}, max(radius - half, 0)}, lead_outline, {width = sw})
	}
	if painted(lead_content) {
		divider := max(gtx.theme.stroke, 1)
		stroke(gtx.ops, line(gtx, {leading_w, 6}, {leading_w, size.y - 6}), with_alpha(lead_content, 0.24), {width = divider})
	}

	origin := Point{pd.left, (size.y - lh) / 2 + m.ascent}
	if painted(lead_content) {
		glyphs(gtx.ops, add_run(gtx.ops, run), origin, lead_content)
	}
	chevron := expanded^ ? "^" : "v" // ▴/▾ would be the real glyphs, but arial.ttf (the demo font) has no such symbol coverage
	crun, cm := shape_line(gtx, chevron, s.size)
	clh := line_height(cm)
	corigin := Point{leading_w + (chevron_w - crun.advance) / 2, (size.y - clh) / 2 + cm.ascent}
	if painted(trail_content) {
		glyphs(gtx.ops, add_run(gtx.ops, crun), corigin, trail_content)
	}

	if !disabled {
		input_area(gtx.ops, lead_id, lead_rect, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur})
		input_area(gtx.ops, trail_id, trail_rect, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur})
	}
	tag(gtx.ops, lead_id, frame_string(gtx, text))
	tag(gtx.ops, trail_id, frame_string(gtx, "chevron"))
	widget_close(gtx, &p, {size, origin.y})
	return
}
