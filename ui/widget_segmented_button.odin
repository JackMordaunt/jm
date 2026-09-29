package ui

// segmented_button is a row of len(labels) toggle segments sharing one
// pill outline and thin dividers between them — M3's own shape for it, per
// _md-comp-outlined-segmented-button.scss: 'shape' = corner-full and
// 'outline-width' = 1px are both properties of the whole control, not
// repeated per segment. Each segment is independently hoverable/pressable/
// focusable; selected ones get secondary_container fill, an
// on_secondary_container leading check mark and label, unselected ones
// get plain fg text on no fill. selected is caller-owned, one bool per
// label — segmented_button flips whichever segment was clicked (or
// activated by Enter/Space while focused) and returns its index, or -1
// if none changed this frame; the caller decides whether that means
// single-select (clearing the rest itself) or independent multi-select.
segmented_button :: proc(
	gtx: ^Ctx,
	labels: []string,
	selected: []bool,
	style := Segmented_Button_Style{},
	disabled := false,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	p := widget_open(gtx, key, loc)
	s := resolve_segmented_button(gtx.theme, style)
	n := min(len(labels), len(selected))
	changed := -1
	if n == 0 {
		widget_close(gtx, &p, {})
		return changed
	}

	pad_x: f32 = 16
	check_w: f32 = 18
	gap: f32 = 4
	runs := make([]Glyph_Run, n, gtx.allocator)
	widths := make([]f32, n, gtx.allocator)
	m: Font_Metrics
	total: f32 = 0
	for i in 0 ..< n {
		run, mm := shape_line(gtx, labels[i], s.size)
		runs[i] = run
		m = mm
		// check_w + gap is reserved on every segment, selected or not, so
		// toggling selection never changes a segment's width — the check
		// mark fills space that was already there rather than growing into
		// it, which is what was popping/jittering the whole row before.
		w := run.advance + pad_x * 2 + check_w + gap
		widths[i] = w
		total += w
	}
	lh := line_height(m)
	size := constrain_min(gtx.constraints, {total, max(s.height, lh)})
	radius := size.y / 2
	rr := Round_Rect{{0, 0, size.x, size.y}, radius}

	// Pass 1: resolve interaction state per segment (may flip selected[i]).
	// Kept clear of the clip/paint pass below, the same order button() uses
	// (state resolved, then painted).
	contents := make([]Color, n, gtx.allocator)
	containers := make([]Color, n, gtx.allocator)
	layers := make([]f32, n, gtx.allocator)
	states := make([]^Widget_State, n, gtx.allocator)
	x: f32 = 0
	for i in 0 ..< n {
		seg := Rect{x, 0, widths[i], size.y}
		seg_id := id_mix(p.id, u64(i))
		contents[i] = selected[i] ? s.selected_text : s.text
		containers[i] = selected[i] ? s.selected_fill : CLEAR
		if disabled {
			contents[i] = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTENT_OPACITY)
			if painted(containers[i]) {
				containers[i] = with_alpha(gtx.theme.fg, STATE_DISABLED_CONTAINER_OPACITY)
			}
		} else {
			st := widget_state(gtx, seg_id)
			states[i] = st
			if click_from_events(gtx, seg_id, st, seg) {
				selected[i] = !selected[i]
				changed = i
			}
			switch {
			case st.pressed:
				layers[i] = STATE_PRESSED_OPACITY
			case st.focused:
				layers[i] = STATE_FOCUS_OPACITY
			case st.hovered:
				layers[i] = STATE_HOVER_OPACITY
			}
		}
		x += widths[i]
	}

	// Pass 2: paint, clipped to the shared pill silhouette so square segment
	// fills never poke past the rounded ends.
	clip_push(gtx.ops, rr)
	x = 0
	for i in 0 ..< n {
		w := widths[i]
		seg := Rect{x, 0, w, size.y}
		content, container := contents[i], containers[i]
		if painted(container) {
			fill(gtx.ops, seg, container)
		}
		if layers[i] > 0 {
			fill(gtx.ops, seg, with_alpha(content, layers[i]))
		}
		if states[i] != nil {
		}
		// The check mark's slot (check_w + gap) is reserved whether or not
		// this segment is selected, so the label always starts at the same
		// x regardless — only the mark itself appears/disappears.
		tx := x + pad_x
		if selected[i] && painted(content) {
			cy := (size.y - check_w) / 2
			mark := polyline(
				gtx,
				[]Point {
					{tx + 0.24 * check_w, cy + 0.52 * check_w},
					{tx + 0.42 * check_w, cy + 0.70 * check_w},
					{tx + 0.76 * check_w, cy + 0.30 * check_w},
				},
			)
			stroke(gtx.ops, mark, content, {width = max(check_w / 8, 1.5), cap = .Round, join = .Round})
		}
		tx += check_w + gap
		if painted(content) {
			glyphs(gtx.ops, add_run(gtx.ops, runs[i]), {tx, (size.y - lh) / 2 + m.ascent}, content)
		}
		x += w
	}
	clip_pop(gtx.ops)

	// Pass 3: input areas and tags, unclipped.
	x = 0
	for i in 0 ..< n {
		seg := Rect{x, 0, widths[i], size.y}
		seg_id := id_mix(p.id, u64(i))
		if !disabled {
			input_area(gtx.ops, seg_id, seg, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Focus, .Blur})
		}
		tag(gtx.ops, seg_id, frame_string(gtx, labels[i]))
		x += widths[i]
	}

	if painted(s.outline) {
		sw := max(gtx.theme.stroke, 1)
		half := sw / 2
		stroke(gtx.ops, Round_Rect{{half, half, size.x - sw, size.y - sw}, max(radius - half, 0)}, s.outline, {width = sw})
		x = 0
		for i in 0 ..< n - 1 {
			x += widths[i]
			stroke(gtx.ops, line(gtx, {x, 4}, {x, size.y - 4}), s.outline, {width = sw})
		}
	}

	widget_close(gtx, &p, {size, (size.y - lh) / 2 + m.ascent})
	return changed
}
