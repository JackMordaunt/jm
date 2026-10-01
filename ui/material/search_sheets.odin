package material

import "base:runtime"

import "core:strings"
import "jm:ui/ops"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Search (m3e-kit components/search.json: comp.search-bar, comp.search-view)
// and sheets (components/sheets.json: comp.sheet-bottom, comp.drag-handle,
// comp.scrim, and comp.navigation-drawer standing in for the side sheet,
// which has no token group of its own).

// Search_View is how an expanded search bar presents its results
// (search.json inputs.presentation).
Search_View :: enum u8 {
	Docked, // the bar grows down into one bounded popup: tablets and desktop
	Docked_With_Gap, // the bar stays; the popup opens below it, a gap apart
	Full_Screen, // the bar grows into a surface covering the window
	Full_Screen_Contained, // Expressive: full screen, the bar kept as the header, no divider
}

// Values search.json gives without tokens, cited where they are used.
SEARCH_MIN_WIDTH :: f32(360) // layout collapsed-width, SearchBar.kt:4177-4180
SEARCH_MAX_WIDTH :: f32(720)
SEARCH_ICON_INSET :: f32(16) // layout icon-edge-padding, SearchBar.kt:4185-4186
SEARCH_BAR_PADDING :: f32(8) // layout collapsed-vertical-padding, SearchBar.kt:4181-4182
SEARCH_DOCKED_MIN_RESULTS :: f32(240) // layout docked-results-height, SearchBar.kt:4176-4178
// SEARCH_GAP is the gap between the bar and a Docked_With_Gap popup. The
// kit gives no value for it; 8 is the grid step (foundations.json layout).
SEARCH_GAP :: f32(8)

// search_bar is M3 Expressive's search bar and its search view, one state
// machine (search.json behaviour one-state-machine): a pill of
// comp.search-bar (56dp, surface-container-high, body-large input, icons
// 16dp from the edges, 360-720dp wide) that expands into the view chosen by
// view. The expansion is a spring-driven progress, not a swap: the
// container's bounds and corners interpolate from the bar's to the view's
// every frame (states shape-morph), with the spring the spec names per
// presentation. Suggestions containing the text (case-insensitive) list
// under the header; clicking one puts it in s, collapses the view and
// returns its index (else -1). Enter sets submitted^ and collapses; Escape
// collapses.
//
// expanded, when given, is the caller's: a press on the bar sets it, and
// Escape, Enter, a pick or a press outside the view clear it. When nil the
// view follows focus instead, and a pick keeps it shut until the text next
// changes. window is the window's size: full-screen views cover it and the
// docked results cap at a fraction of its height; without it the
// full-screen views fall back to Docked. state forces the collapsed bar's
// look (and takes no input).
//
// Departures: jm:ui has no widget-to-window query, so a full-screen view
// grows from where the bar was last hit-tested (router hover, press or
// focus), which is its real position whenever it was clicked to open. No
// predictive back (states predictive-back): jm:ui has no back gesture. The
// Full_Screen_Contained background is surface, which the kit does not
// token, so the kept pill (surface-container-high) reads against it.
search_bar :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	placeholder := "Search",
	leading := Icon.Search,
	trailing := Icon.None,
	suggestions: []string = nil,
	width: f32 = SEARCH_MIN_WIDTH,
	view := Search_View.Docked,
	expanded: ^bool = nil,
	window := ops.Size{},
	submitted: ^bool = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	p := ui.widget_open(gtx, key, loc)
	H :: tok.SEARCH_BAR_CONTAINER_HEIGHT
	size := ui.constrain(gtx.constraints, {clamp(width, SEARCH_MIN_WIDTH, SEARCH_MAX_WIDTH), H})
	bar := ops.Rect{0, 0, size.x, H}
	mode := view
	if window == {} && (mode == .Full_Screen || mode == .Full_Screen_Contained) {
		mode = .Docked
	}
	live := state == .Live
	ui.text_clamp(s)
	pad_l, pad_r := search_padding(leading, trailing)
	inner := max(size.x - pad_l - pad_r, 0)

	vs := ui.widget_data(gtx, p.id, Search_View_State)
	st: ^ui.Widget_State // the input's, while live
	changed, enter, escape, blurred, pressed := false, false, false, false, false
	focused, hovered, bar_pressed: bool
	scroll: f32
	if live {
		st = ui.widget_state(gtx, p.id)
		changed, enter, escape, blurred, pressed = search_text_events(gtx, p.id, st, s, pad_l, vs.scroll)
		focused, hovered, bar_pressed = st.focused, st.hovered, st.pressed
	}
	str := string(s.buf[:])
	typed := layout_style(gtx, str, tok.SEARCH_BAR_INPUT_TEXT_FONT)
	full := typed.width
	_, caret := ui.paragraph_caret(typed, s.cursor)
	if live {
		vs.scroll = max(clamp(min(vs.scroll, max(full + 2 - inner, 0)), caret + 2 - inner, caret), 0)
		scroll = vs.scroll
	}

	// Expanded: the caller's, or focus unless a pick dismissed it.
	if changed || pressed {
		vs.dismissed = false
	}
	open: bool
	if expanded != nil {
		if pressed {
			expanded^ = true
		}
		if escape || enter || (blurred && mode != .Full_Screen && mode != .Full_Screen_Contained) {
			expanded^ = false
		}
		open = expanded^
	} else {
		if escape || enter {
			vs.dismissed = true
		}
		open = live ? focused && !vs.dismissed && len(suggestions) > 0 : false
	}
	if enter && submitted != nil {
		submitted^ = true
	}
	// The bar's window origin, read from its hit while it was last fully
	// collapsed (once expanded, the header takes the same id elsewhere).
	if live && gtx.router != nil && st.springs[0].value <= 0.001 {
		r := gtx.router
		switch {
		case r.pressed == p.id:
			vs.origin = ops.apply(r.pressed_hit.transform, {})
		case r.focus == p.id:
			vs.origin = ops.apply(r.focus_hit.transform, {})
		case r.hover == p.id:
			vs.origin = ops.apply(r.hover_hit.transform, {})
		}
	}

	// Progress: 0 collapsed, 1 expanded, overshooting under a spatial spring.
	c := Control{st = st}
	t := animate(gtx, c, 0, open ? 1 : 0, search_spring(mode, open))

	// The collapsed bar, in place. It paints its forced state; live it
	// shows hover and press, and the caret while focused.
	fc := Control{}
	#partial switch state {
	case .Live:
		fc = {hovered = hovered, pressed = bar_pressed, focused = false}
		fc.layer = bar_pressed ? PRESSED_OPACITY : hovered ? HOVER_OPACITY : 0
	case:
		fc = control(gtx, p.id, bar, state)
	}
	show_caret := (live && focused) || (!live && fc.focused)
	bar_k := corners(tok.SEARCH_BAR_CONTAINER_SHAPE, bar)
	if !(t > 0 && (mode == .Docked || mode == .Full_Screen_Contained)) {
		// Docked and Contained repaint the bar as their header.
		paint_search_field(gtx, bar, bar_k, s, str, placeholder, leading, trailing, scroll, caret, show_caret, fc, false)
		paint_focus_ring_corners(gtx, fc, bar, bar_k)
	}
	if live {
		ops.input_area(gtx.scene, p.id, bar, SEARCH_KINDS, .Text)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, placeholder))
	full_screen := mode == .Full_Screen || mode == .Full_Screen_Contained
	if live && open && full_screen {
		// A full-screen view covers the page, so Escape closes it whether or
		// not the input holds focus; search_text_events reads it.
		ui.key_interest(gtx, p.id, .Escape)
	}
	bar_states := ops.States{.Expandable}
	if open {
		bar_states += {.Expanded}
	}
	if state == .Disabled {
		bar_states += {.Disabled}
	}
	ui.semantics(gtx, &p, {role = .Text_Field, label = placeholder, value = str, states = bar_states})

	picked := -1
	if t > 0.001 {
		picked = search_view(gtx, p.id, mode, s, str, placeholder, leading, trailing, suggestions, size.x, window, vs.origin, t, open, live, scroll, caret, focused)
	}
	if picked >= 0 {
		ui.text_set(s, suggestions[picked])
	}
	closed := vs.close
	vs.close = false
	if picked >= 0 || (open && closed) {
		if expanded != nil {
			expanded^ = false
		} else {
			vs.dismissed = true
		}
	}
	ui.widget_close(gtx, &p, {size = size})
	return picked
}

@(private)
SEARCH_KINDS :: ops.Event_Kinds{.Press, .Release, .Enter, .Leave, .Move, .Key, .Text, .Focus, .Blur}

// Search_View_State is what a search bar keeps for its view between
// frames, beside the Widget_State its input uses.
@(private)
Search_View_State :: struct {
	// dismissed keeps a view that follows focus shut after a pick, Enter or
	// Escape, until the text next changes or the bar is pressed.
	dismissed: bool,
	// close is the view's own areas (the outside catcher, the back arrow)
	// asking search_bar to collapse, set and read in the same frame.
	close:     bool,
	// scroll is the input's horizontal scroll, kept so the caret stays in view.
	scroll:    f32,
	// origin is the bar's window origin as last hit-tested while fully
	// collapsed: where a full-screen view grows from.
	origin:    ops.Point,
}

// search_padding is the input text's start and end inset: an icon sits
// SEARCH_ICON_INSET from each edge and the text as far again past it.
@(private)
search_padding :: proc(leading, trailing: Icon) -> (l, r: f32) {
	l = leading != .None ? 2 * SEARCH_ICON_INSET + tok.SMALL_ICON_BUTTON_ICON_SIZE : SEARCH_ICON_INSET
	r = trailing != .None ? 2 * SEARCH_ICON_INSET + tok.SMALL_ICON_BUTTON_ICON_SIZE : SEARCH_ICON_INSET
	return
}

// search_spring is the spring search.json names for a presentation's
// expand or collapse (states full-screen-motion, contained-full-screen-
// motion, docked-with-gap-motion). The spec names none for plain Docked;
// it takes Docked_With_Gap's.
@(private)
search_spring :: proc(v: Search_View, expanding: bool) -> Spring {
	switch v {
	case .Full_Screen:
		return expanding ? .Slow_Spatial : .Default_Spatial
	case .Full_Screen_Contained:
		return .Fast_Spatial
	case .Docked, .Docked_With_Gap:
	}
	return expanding ? .Default_Spatial : .Fast_Spatial
}

// search_text_events applies this frame's events for the input area id to
// st and s: hover, focus, a press placing the cursor, typed text and
// editing keys. pad_l is where the text starts in the area.
@(private)
search_text_events :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	st: ^ui.Widget_State,
	s: ^ui.Text_State,
	pad_l: f32,
	scroll: f32, // the input's caret scroll, for hit-testing a press
) -> (
	changed, enter, escape, blurred, pressed: bool,
) {
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
			blurred = true
		case .Press, .Move, .Release:
			if e.kind == .Press {
				st.pressed = true
				pressed = true
			} else if e.kind == .Release {
				st.pressed = false
			}
			font := tok.SEARCH_BAR_INPUT_TEXT_FONT
			ui.text_follow_pointer(s, layout_style(gtx, string(s.buf[:]), font), e, {e.pos.x - pad_l + scroll, 0}, text_stops(gtx, s, font))
		case .Text, .Paste:
			changed |= ui.text_edit(gtx, s, id, e, text_stops(gtx, s, tok.SEARCH_BAR_INPUT_TEXT_FONT))
		case .Key:
			#partial switch e.key {
			case .Enter:
				enter = true
			case .Escape:
				escape = true
			case:
				changed |= ui.text_edit(gtx, s, id, e, text_stops(gtx, s, tok.SEARCH_BAR_INPUT_TEXT_FONT))
			}
		}
	}
	return
}

// paint_search_field paints a search input row in r with corners k: the
// container, a state layer, the leading icon, the text or placeholder, the
// caret and the trailing icon. header picks the comp.search-view header
// colours over the comp.search-bar ones.
@(private)
paint_search_field :: proc(
	gtx: ^ui.Ctx,
	r: ops.Rect,
	k: Corners,
	s: ^ui.Text_State,
	str, placeholder: string,
	leading, trailing: Icon,
	scroll, caret: f32,
	show_caret: bool,
	c: Control,
	header: bool,
	fill := true,
) {
	shape := rounded(gtx, r, k)
	if fill {
		if !header {
			paint_elevation(gtx, {r, k.tl}, elevation_level(tok.SEARCH_BAR_CONTAINER_ELEVATION))
		}
		ops.fill(gtx.scene, shape, color(header ? tok.SEARCH_VIEW_CONTAINER_COLOR : tok.SEARCH_BAR_CONTAINER_COLOR))
	}
	paint_state_layer(gtx, c, shape, color(tok.SEARCH_BAR_INPUT_TEXT_COLOR))
	lead := color(header ? tok.SEARCH_VIEW_HEADER_LEADING_ICON_COLOR : tok.SEARCH_BAR_LEADING_ICON_COLOR)
	trail := color(header ? tok.SEARCH_VIEW_HEADER_TRAILING_ICON_COLOR : tok.SEARCH_BAR_TRAILING_ICON_COLOR)
	input := color(header ? tok.SEARCH_VIEW_HEADER_INPUT_TEXT_COLOR : tok.SEARCH_BAR_INPUT_TEXT_COLOR)
	hint := color(header ? tok.SEARCH_VIEW_HEADER_SUPPORTING_TEXT_COLOR : tok.SEARCH_BAR_SUPPORTING_TEXT_COLOR)
	if c.disabled {
		lead, trail, input, hint = disabled_content(), disabled_content(), disabled_content(), disabled_content()
	}
	ICON :: tok.SMALL_ICON_BUTTON_ICON_SIZE
	pad_l, pad_r := search_padding(leading, trailing)
	cy := r.y + r.h / 2
	if leading != .None {
		icon(gtx, leading, {r.x + SEARCH_ICON_INSET, cy - ICON / 2}, ICON, lead)
	}
	inner := max(r.w - pad_l - pad_r, 0)
	ops.clip_push(gtx.scene, ops.Rect{r.x + pad_l, r.y, inner, r.h})
	font := header ? tok.SEARCH_VIEW_HEADER_INPUT_TEXT_FONT : tok.SEARCH_BAR_INPUT_TEXT_FONT
	if len(str) > 0 {
		draw_paragraph(gtx, layout_style(gtx, str, font), {r.x + pad_l - scroll, cy - font.line_height / 2}, input, selection_paint(s, show_caret))
	} else {
		t := shape_style(gtx, placeholder, header ? tok.SEARCH_VIEW_HEADER_SUPPORTING_TEXT_FONT : tok.SEARCH_BAR_SUPPORTING_TEXT_FONT)
		draw_text(gtx, t, {r.x + pad_l, cy - t.height / 2}, hint)
	}
	if show_caret && !c.disabled {
		// The caret is the focus indicator colour; the kit tokens no caret for the bar.
		lh := font.line_height
		ops.fill(gtx.scene, ops.Rect{r.x + pad_l + caret - scroll, cy - lh / 2, 2, lh}, color(tok.SEARCH_BAR_FOCUS_INDICATOR_COLOR))
	}
	ops.clip_pop(gtx.scene)
	if trailing != .None {
		icon(gtx, trailing, {r.x + r.w - SEARCH_ICON_INSET - ICON, cy - ICON / 2}, ICON, trail)
	}
}

// search_view paints the expanded view at progress t in an overlay and
// runs its rows. Returns the picked suggestion's index, or -1.
@(private)
search_view :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	mode: Search_View,
	s: ^ui.Text_State,
	str, placeholder: string,
	leading, trailing: Icon,
	suggestions: []string,
	w: f32,
	window: ops.Size,
	origin: ops.Point,
	t: f32,
	open, live: bool,
	scroll, caret: f32,
	focused: bool,
) -> int {
	H :: tok.SEARCH_BAR_CONTAINER_HEIGHT
	ROW :: tok.LIST_ITEM_ONE_LINE_CONTAINER_HEIGHT
	fade := clamp(t, 0, 1)
	// Up to 64 matches, filtered without allocating per suggestion beyond the frame.
	matches: [64]int
	n := 0
	needle := strings.to_lower(str, gtx.allocator)
	for sug, i in suggestions {
		if n == len(matches) {
			break
		}
		if strings.contains(strings.to_lower(sug, gtx.allocator), needle) {
			matches[n] = i
			n += 1
		}
	}
	full_screen := mode == .Full_Screen || mode == .Full_Screen_Contained
	o: ui.Overlay
	if full_screen {
		o = ui.overlay_open(gtx, cs = ui.exact(window), root = true, cover = true)
	} else {
		o = ui.overlay_open(gtx)
	}
	defer ui.close(&o)
	catch_id := ui.id_mix(id, 2)
	bar_from := full_screen ? ops.Rect{origin.x, origin.y, w, H} : ops.Rect{0, 0, w, H}
	bar_k := corners(tok.SEARCH_BAR_CONTAINER_SHAPE, bar_from)

	// Container, header and the results area, per presentation.
	cont: ops.Rect
	k: Corners
	header: ops.Rect
	results: ops.Rect
	divider := true
	color_role := tok.SEARCH_VIEW_CONTAINER_COLOR
	switch mode {
	case .Docked:
		max_h := window.y > 0 ? window.y * 2 / 3 - H : f32(6) * ROW
		res_h := clamp(f32(n) * ROW + 8, SEARCH_DOCKED_MIN_RESULTS, max(max_h, SEARCH_DOCKED_MIN_RESULTS))
		cont = {0, 0, w, H + max((1 + res_h) * t, 0)}
		k = lerp_corners(bar_k, corners(tok.SEARCH_VIEW_DOCKED_CONTAINER_SHAPE, cont), fade)
		header = {0, 0, w, tok.SEARCH_VIEW_DOCKED_HEADER_CONTAINER_HEIGHT}
		results = {0, header.h + 1, w, res_h}
	case .Docked_With_Gap:
		max_h := window.y > 0 ? window.y / 2 : f32(6) * ROW
		res_h := clamp(f32(n) * ROW + 16, SEARCH_DOCKED_MIN_RESULTS, max(max_h, SEARCH_DOCKED_MIN_RESULTS))
		cont = {0, H + SEARCH_GAP, w, max(res_h * t, 0)}
		k = corners(tok.SEARCH_VIEW_DOCKED_CONTAINER_SHAPE, cont)
		results = {0, cont.y + 8, w, res_h - 16}
		divider = false
	case .Full_Screen:
		to := ops.Rect{0, 0, window.x, window.y}
		cont = search_lerp_rect(bar_from, to, t)
		k = lerp_corners(bar_k, corners(tok.SEARCH_VIEW_FULL_SCREEN_CONTAINER_SHAPE, to), fade)
		// The bar's top padding shrinks to 0 as the header grows to its
		// full-screen height (layout expanded-header-height).
		hh := H + (tok.SEARCH_VIEW_FULL_SCREEN_HEADER_CONTAINER_HEIGHT - H) * fade
		header = {cont.x, cont.y, cont.w, hh}
		results = {cont.x, cont.y + hh + 1, cont.w, max(cont.h - hh - 1, 0)}
	case .Full_Screen_Contained:
		to := ops.Rect{0, 0, window.x, window.y}
		cont = search_lerp_rect(bar_from, to, t)
		k = lerp_corners(bar_k, corners(tok.SEARCH_VIEW_FULL_SCREEN_CONTAINER_SHAPE, to), fade)
		color_role = .Surface
		// The kept pill rises to the collapsed padding below the top edge.
		header = {bar_from.x, bar_from.y + (SEARCH_BAR_PADDING - bar_from.y) * fade, w, H}
		results = {0, header.y + H + SEARCH_BAR_PADDING, window.x, max(window.y - header.y - H - SEARCH_BAR_PADDING, 0)}
		divider = false
	}

	if full_screen {
		// Full screen only: a scrim dims the page during the transition.
		ops.fill(gtx.scene, ops.Rect{0, 0, window.x, window.y}, ops.with_alpha(color(tok.SCRIM_CONTAINER_COLOR), tok.SCRIM_CONTAINER_OPACITY * fade))
	}
	if live && open {
		// A press anywhere outside the view collapses it, and reaches nothing else.
		for e in ui.events(gtx, catch_id) {
			if e.kind == .Press {
				ui.widget_data(gtx, id, Search_View_State).close = true
			}
		}
		ops.input_area(gtx.scene, catch_id, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	}
	shape := rounded(gtx, cont, k)
	if cont.h > 0 {
		paint_elevation(gtx, {cont, k.tl}, elevation_level(tok.SEARCH_VIEW_CONTAINER_ELEVATION))
		ops.fill(gtx.scene, shape, color(color_role))
		if live && open {
			ops.input_area(gtx.scene, ui.id_mix(id, 3), shape, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		}
	}

	// Header: the bar's input row again, over the container.
	lead := leading
	back := false
	if mode == .Full_Screen && fade > 0.5 {
		lead = .Arrow_Back // full screen leads with a way back
		back = true
	}
	hc := Control{}
	if mode == .Docked || mode == .Full_Screen {
		paint_search_field(gtx, header, {}, s, str, placeholder, lead, trailing, scroll, caret, focused, hc, true, fill = false)
	} else if mode == .Full_Screen_Contained {
		paint_search_field(gtx, header, corners(tok.SEARCH_BAR_CONTAINER_SHAPE, header), s, str, placeholder, lead, trailing, scroll, caret, focused, hc, false)
	}
	if live && open && mode != .Docked_With_Gap {
		// The header takes the bar's own input: the same id, on top.
		ops.transform_push(gtx.scene, ops.translate(header.x, header.y + (header.h - H) / 2))
		ops.input_area(gtx.scene, id, ops.Rect{0, 0, header.w, H}, SEARCH_KINDS, .Text)
		ops.transform_pop(gtx.scene)
	} else if live && open {
		ops.input_area(gtx.scene, id, ops.Rect{0, 0, w, H}, SEARCH_KINDS, .Text)
	}
	if back && live {
		bid := ui.id_mix(id, 4)
		bc := control(gtx, bid, ops.Rect{header.x + 4, header.y + (header.h - 48) / 2, 48, 48}, .Live)
		if bc.clicked {
			ui.widget_data(gtx, id, Search_View_State).close = true
		}
		listen(gtx, bc, bid, ops.Rect{header.x + 4, header.y + (header.h - 48) / 2, 48, 48}, {.Press, .Release, .Enter, .Leave, .Move})
		ops.tag(gtx.scene, bid, "search back")
		// An undeclared bracket: the button is a root of the view's layer.
		bp := ui.widget_open(gtx, u64(bid))
		ui.part_semantics(gtx, &bp, bid, {header.x + 4, header.y + (header.h - 48) / 2, 48, 48}, {role = .Button, label = "search back"})
		ui.widget_close(gtx, &bp, {})
	}
	if divider && fade > 0 {
		ops.fill(gtx.scene, ops.Rect{cont.x, header.y + header.h, cont.w, 1}, ops.with_alpha(color(tok.SEARCH_VIEW_DIVIDER_COLOR), fade))
	}

	// Results, clipped to the container; the contained view fades them in.
	picked := -1
	ops.clip_push(gtx.scene, shape)
	rows := min(n, int(max(results.h, 0) / ROW))
	text_c := color(tok.LIST_ITEM_LABEL_TEXT_COLOR)
	icon_c := color(tok.LIST_ITEM_LEADING_ICON_COLOR)
	if mode == .Full_Screen_Contained {
		text_c, icon_c = ops.with_alpha(text_c, fade), ops.with_alpha(icon_c, fade)
	}
	// The rows are declared once painted, as parts of a list widget at
	// the results' origin.
	Shown :: struct {
		id:    ops.Area_Id,
		r:     ops.Rect,
		label: string,
	}
	shown: [64]Shown
	for row in 0 ..< rows {
		mi := matches[row]
		r := ops.Rect{results.x, results.y + f32(row) * ROW, results.w, ROW}
		rid := ui.id_mix(id, u64(100 + mi))
		c := control(gtx, rid, r, open && live ? .Live : .Enabled)
		if c.clicked {
			picked = mi
		}
		paint_state_layer(gtx, c, r, text_c)
		icon(gtx, .Schedule, {r.x + tok.LIST_ITEM_LEADING_SPACE, r.y + (ROW - tok.LIST_ITEM_LEADING_ICON_SIZE) / 2}, tok.LIST_ITEM_LEADING_ICON_SIZE, icon_c)
		lt := shape_style(gtx, suggestions[mi], tok.LIST_ITEM_LABEL_TEXT_FONT)
		draw_text(gtx, lt, {r.x + 2 * tok.LIST_ITEM_LEADING_SPACE + tok.LIST_ITEM_LEADING_ICON_SIZE, r.y + (ROW - lt.height) / 2}, text_c)
		if open && live {
			// Pointer only: an area wanting Key takes focus on a press, which
			// would blur the bar and close the view before the click lands.
			listen(gtx, c, rid, r, {.Press, .Release, .Enter, .Leave, .Move})
			ops.tag(gtx.scene, rid, ui.frame_string(gtx, suggestions[mi]))
		}
		shown[row] = {rid, {0, f32(row) * ROW, results.w, ROW}, suggestions[mi]}
	}
	ops.transform_push(gtx.scene, ops.translate(results.x, results.y))
	lp := ui.widget_open(gtx, u64(ui.id_mix(id, 5)))
	ui.semantics(gtx, &lp, {role = .List, label = placeholder})
	for sh in shown[:rows] {
		ui.part_semantics(gtx, &lp, sh.id, sh.r, {role = .List_Item, label = sh.label})
	}
	ui.widget_close(gtx, &lp, {size = {results.w, results.h}})
	ops.transform_pop(gtx.scene)
	ops.clip_pop(gtx.scene)
	return picked
}

// lerp_rect is the rect between a and b at t, per edge.
@(private)
search_lerp_rect :: proc(a, b: ops.Rect, t: f32) -> ops.Rect {
	return {a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, max(a.w + (b.w - a.w) * t, 0), max(a.h + (b.h - a.h) * t, 0)}
}

// Sheet_Value is a bottom sheet's anchor (sheets.json inputs.sheetState).
Sheet_Value :: enum u8 {
	Hidden,
	Partially_Expanded,
	Expanded,
}

// Sheet is an open bottom or side sheet; see bottom_sheet and side_sheet.
Sheet :: struct {
	visible: bool,
	overlay: ui.Overlay,
	boxes:   [3]ui.Box, // the sheet itself and its placement wrappers
	flexes:  [2]ui.Flex,
	nflex:   int,
	nbox:    int,
	width:   f32, // the width left for content inside the sheet's padding
}

@(private)
Sheet_Kind :: enum u8 {
	Bottom,
	Side_Modal,
	Side_Standard,
}

@(private)
Sheet_Paint :: struct {
	kind:    Sheet_Kind,
	left:    bool, // side sheets: anchored to the left edge
	drag_id: ops.Area_Id, // the area the sheet registers for drags and Escape
	state:   ^Sheet_State, // bottom sheets: where paint records the measured height
}

// Values sheets.json gives without tokens, cited where they are used.
SHEET_MAX_WIDTH :: f32(640) // layout bottom-max-width, SheetDefaults.kt:536
SHEET_POSITIONAL_THRESHOLD :: f32(56) // layout bottom-drag-thresholds, SheetDefaults.kt:559
SHEET_VELOCITY_THRESHOLD :: f32(125) // dp/s, the same
SHEET_HANDLE_PADDING :: f32(22) // layout bottom-drag-handle-shape, SheetDefaults.kt:575,788

// bottom_sheet opens M3 Expressive's bottom sheet while open^ (sheets.json
// comp.sheet-bottom): the widgets up to sheet_close sit on a
// surface-container-low sheet with 28dp top corners, anchored to the bottom
// of window (SHEET_MAX_WIDTH at most, centred). modal adds a scrim that
// fades in with a default-effects spring and closes the sheet on a press;
// standard coexists with the page. The sheet enters on a default-spatial
// spring and leaves on a fast-effects one (states enter, dismiss), staying
// visible until it is off screen, so call sheet_close whatever visible says
// and draw content while visible.
//
// value, when given, is the caller's anchor (Hidden, Partially_Expanded,
// Expanded); it is kept internally otherwise. Partially_Expanded shows
// min(half the window, the sheet's height) (layout bottom-anchors); with
// skip_partial the sheet opens and settles only Expanded. Dragging the
// sheet or its handle moves it; the release settles on the next anchor
// once the drag passes SHEET_POSITIONAL_THRESHOLD or its speed passes
// SHEET_VELOCITY_THRESHOLD, and settling on Hidden closes it. Clicking the
// handle cycles the anchor (states click-cycle). Escape closes a sheet that
// has focus.
//
// state, when given, is the caller's Sheet_State: the anchor (when value
// is nil), the drag in progress and the measured height. Pass it to keep a
// sheet's drag and place through a rebuild that changes its id, or to
// inspect or reset them; it is kept internally otherwise.
//
// Departures: the fling's velocity only picks the anchor; the settle
// spring starts from rest, so the boundary damping near Hidden (layout
// bottom-boundary-damping) has nothing to damp. No predictive back.
bottom_sheet_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	window: ops.Size,
	modal := true,
	handle := true,
	value: ^Sheet_Value = nil,
	skip_partial := false,
	max_width := SHEET_MAX_WIDTH,
	state: ^Sheet_State = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> Sheet {
	sh: Sheet
	id := ui.claim_id(gtx, key, loc)
	drag_id := ui.id_mix(id, 1)
	handle_id := ui.id_mix(id, 2)
	ss := state if state != nil else ui.widget_data(gtx, id, Sheet_State)
	anchor := value != nil ? value^ : ss.anchor
	h := ss.height
	hidden_at := h > 0 ? h : window.y
	partial_at := h - min(window.y / 2, h)
	if skip_partial {
		partial_at = 0
	}
	if open^ && anchor == .Hidden {
		anchor = skip_partial ? .Expanded : .Partially_Expanded
	}
	if !open^ {
		anchor = .Hidden
	}

	// Drags: from the sheet body and from its handle, one gesture state.
	d := &ss.drag
	settle, clicked, escape := false, false, false
	areas := [2]ops.Area_Id{drag_id, handle_id}
	for area in areas {
		for e in ui.events(gtx, area) {
			s, c, esc := sheet_drag_event(d, e, area == handle_id, gtx.dt)
			settle |= s
			clicked |= c
			escape |= esc
		}
	}
	if clicked && anchor != .Hidden {
		// The handle's click cycles: Expanded hides, Partially_Expanded expands.
		anchor = anchor == .Expanded ? .Hidden : .Expanded
	}
	if settle {
		anchor = sheet_settle(anchor, d.delta, d.velocity, partial_at, hidden_at, skip_partial)
	}
	if escape {
		anchor = .Hidden
	}
	if anchor == .Hidden {
		open^ = false
	}
	if value != nil {
		value^ = anchor
	}
	ss.anchor = anchor

	// Offset below the fully shown position: a spring to the anchor, or the
	// pointer while dragging. While closed and never measured, the target
	// is a window's height, so the first opening slides in from off screen.
	st := ui.widget_state(gtx, id)
	c := Control{st = st}
	target: f32
	switch anchor {
	case .Hidden:
		target = hidden_at
	case .Partially_Expanded:
		target = partial_at
	case .Expanded:
	}
	offset: f32
	if d.dragging {
		offset = clamp(d.start + d.delta, 0, hidden_at)
		st.springs[0] = {value = offset, target = offset, started = true}
	} else {
		offset = animate(gtx, c, 0, target, anchor == .Hidden ? .Fast_Effects : .Default_Spatial, 0.1)
	}
	scrim := animate(gtx, c, 1, open^ ? 1 : 0, .Default_Effects)
	if !d.dragging {
		d.start = offset
	}

	if !open^ && offset >= hidden_at - 0.5 {
		return sh // closed and off screen
	}
	sh.visible = true
	if open^ {
		// Escape hides the sheet whether or not it holds focus; the drag
		// events above read it.
		ui.key_interest(gtx, drag_id, .Escape)
	}
	w := min(window.x, max_width)
	sh.width = w - 2 * tok.LIST_ITEM_LEADING_SPACE
	if modal {
		so := ui.overlay_open(gtx, cs = ui.exact(window), root = true, cover = true)
		scrim_id := ui.id_mix(id, 5)
		for e in ui.events(gtx, scrim_id) {
			if e.kind == .Press {
				open^ = false
			}
		}
		ops.fill(gtx.scene, ops.Rect{0, 0, window.x, window.y}, ops.with_alpha(color(tok.SCRIM_CONTAINER_COLOR), tok.SCRIM_CONTAINER_OPACITY * clamp(scrim, 0, 1)))
		if open^ {
			ops.input_area(gtx.scene, scrim_id, ops.Rect{0, 0, window.x, window.y}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		}
		ui.close(&so)
	}
	sh.overlay = ui.overlay_open(gtx, {0, max(offset, 0)}, ui.exact(window), root = true, cover = modal)
	col := ui.column_open(gtx, align = .Center)
	sh.flexes[0] = col
	sh.nflex = 1
	ui.fill_space(gtx)
	sp := new(Sheet_Paint, gtx.allocator)
	sp^ = {kind = .Bottom, drag_id = drag_id, state = ss}
	b := ui.box_open(gtx, {padding = {tok.LIST_ITEM_LEADING_SPACE, 0, tok.LIST_ITEM_LEADING_SPACE, 24}, paint = paint_sheet, user = sp}, key = 1)
	sh.boxes[0] = b
	sh.nbox = 1
	// A modal sheet is a dialog to a reader; a standard one a region of the page.
	ui.container_semantics(gtx, {role = modal ? .Dialog : .Group, states = modal ? {.Modal} : {}})
	inner := ui.column_open(gtx)
	sh.flexes[1] = inner
	sh.nflex = 2
	if handle {
		sheet_handle(gtx, handle_id, sh.width) // also sets the sheet's width
	} else {
		strut(gtx, sh.width)
		ui.spacer(gtx, 24)
	}
	return sh
}

// Sheet_State is what a bottom sheet keeps between frames: see
// bottom_sheet's state parameter. The zero value is a hidden sheet, never
// measured, with no drag.
Sheet_State :: struct {
	anchor: Sheet_Value, // where the sheet rests, when the caller keeps no value
	drag:   Sheet_Drag,
	height: f32, // the sheet's height as last painted; 0 before it first shows
}

// Sheet_Drag is a bottom sheet's drag gesture, kept across frames.
Sheet_Drag :: struct {
	dragging: bool,
	delta:    f32, // how far the pointer has moved since the press
	start:    f32, // the sheet's offset when the press landed
	velocity: f32, // dp/s, from the last move
}

// sheet_drag_event applies e, from the sheet body or its handle, to d.
// It adds up each Move's travel, which does not change as the sheet
// itself moves, so the sheet following the pointer cannot feed back into
// the drag. settle reports a release after a drag, click a
// release on the handle that did not move; dt is the frame's, for velocity.
@(private)
sheet_drag_event :: proc(d: ^Sheet_Drag, e: ui.Event, on_handle: bool, dt: f32) -> (settle, click, escape: bool) {
	#partial switch e.kind {
	case .Press:
		d.dragging = true
		d.delta = 0
		d.velocity = 0
	case .Move:
		if d.dragging {
			if dt > 0 {
				d.velocity = e.travel.y / dt
			}
			d.delta += e.travel.y
		}
	case .Release:
		if d.dragging {
			d.dragging = false
			if abs(d.delta) < 4 {
				click = on_handle
			} else {
				settle = true
			}
		}
	case .Key:
		#partial switch e.key {
		case .Escape:
			escape = true
		case .Enter, .Space:
			click = on_handle
		}
	}
	return
}

// sheet_settle is the anchor a drag of delta (down positive) released at
// velocity settles on, from anchor a.
@(private)
sheet_settle :: proc(a: Sheet_Value, delta, velocity, partial_at, hidden_at: f32, skip_partial: bool) -> Sheet_Value {
	far := abs(delta) >= SHEET_POSITIONAL_THRESHOLD || abs(velocity) >= SHEET_VELOCITY_THRESHOLD
	if !far {
		return a
	}
	has_partial := !skip_partial && partial_at > 0
	if delta > 0 {
		if a == .Expanded && has_partial {
			return .Partially_Expanded
		}
		return .Hidden
	}
	if a == .Hidden && has_partial {
		return .Partially_Expanded
	}
	return .Expanded
}

// sheet_handle is the bottom sheet's own drag handle (comp.sheet-bottom
// docked-drag-handle-*, not comp.drag-handle; behaviour two-drag-handle-
// specs): a static 32x4 pill with no pressed or dragged look, 22dp below
// the sheet's top and above its content, centred in a w-wide slot. Its
// shape is the theme's extra-large corner, which clamps to a pill. The slot
// is 48dp tall, the touch target MDC enforces (sheets.json
// accessibility.semantics).
@(private)
sheet_handle :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, w: f32, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	HW, HH :: tok.SHEET_BOTTOM_DOCKED_DRAG_HANDLE_WIDTH, tok.SHEET_BOTTOM_DOCKED_DRAG_HANDLE_HEIGHT
	slot := ops.Rect{0, 0, w, 2 * SHEET_HANDLE_PADDING + HH}
	pill := ops.Rect{(w - HW) / 2, SHEET_HANDLE_PADDING, HW, HH}
	ops.fill(gtx.scene, rounded(gtx, pill, corners(tok.SYS_SHAPE_CORNER_EXTRA_LARGE, pill)), color(tok.SHEET_BOTTOM_DOCKED_DRAG_HANDLE_COLOR))
	st := ui.widget_state(gtx, id)
	if st.focused {
		paint_focus_ring(gtx, {focused = true}, {pill, HH / 2})
	}
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
		}
	}
	hit := ops.Rect{(w - 48) / 2, 0, 48, slot.h}
	ops.input_area(gtx.scene, id, hit, {.Press, .Release, .Move, .Enter, .Leave, .Key, .Focus, .Blur})
	ops.tag(gtx.scene, id, "drag handle")
	// The handle's own id, not the widget's, so focus shows on the node.
	ui.part_semantics(gtx, &p, id, hit, {role = .Button, label = "drag handle"})
	ui.widget_close(gtx, &p, {size = {w, slot.h}})
}

// side_sheet opens a side sheet (sheets.json side-standard, side-modal).
// The kit has no side-sheet tokens; like the spec it substitutes
// comp.navigation-drawer: container-width (360dp default), a
// container-shape rounded only on the edge away from the screen border,
// and the standard (surface, level 0) / modal (surface-container-low,
// level 1) colour split. Modal slides in from the window's right edge (left
// with left) over a scrim, on a default-spatial spring, and closes on a
// press on the scrim, its close button or Escape; standard sits inline
// with a divider on its inner edge, and ignores open. headline, when set,
// heads the sheet with a close icon button (modal) at its end. Call
// bottom_sheet and side_sheet are the sheet openers as guards: the if body
// is the sheet's content and runs only while the sheet is visible, and
// the sheet closes at the end of the if. The Sheet handle lives in the
// widget's own data slot between open and close.
@(deferred_in = bottom_sheet_guard_close)
bottom_sheet :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	window: ops.Size,
	modal := true,
	handle := true,
	value: ^Sheet_Value = nil,
	skip_partial := false,
	max_width := SHEET_MAX_WIDTH,
	state: ^Sheet_State = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	sh := ui.guard_hold(gtx, Sheet)
	sh^ = bottom_sheet_open(gtx, open, window, modal, handle, value, skip_partial, max_width, state, key, loc)
	return sh.visible
}

@(private = "file")
bottom_sheet_guard_close :: proc(gtx: ^ui.Ctx, open: ^bool, window: ops.Size, modal: bool, handle: bool, value: ^Sheet_Value, skip_partial: bool, max_width: f32, state: ^Sheet_State, key: u64, loc: runtime.Source_Code_Location) {
	sheet_close(ui.guard_take(gtx, Sheet))
}

@(deferred_in = side_sheet_guard_close)
side_sheet :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	window: ops.Size,
	modal := true,
	width: f32 = tok.NAVIGATION_DRAWER_CONTAINER_WIDTH,
	left := false,
	headline := "",
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	sh := ui.guard_hold(gtx, Sheet)
	sh^ = side_sheet_open(gtx, open, window, modal, width, left, headline, key, loc)
	return sh.visible
}

@(private = "file")
side_sheet_guard_close :: proc(gtx: ^ui.Ctx, open: ^bool, window: ops.Size, modal: bool, width: f32, left: bool, headline: string, key: u64, loc: runtime.Source_Code_Location) {
	sheet_close(ui.guard_take(gtx, Sheet))
}

// sheet_close whatever visible says. The spec gives no width;
// MDC's example uses 256 (layout side-sheet-width, mdc:SideSheet.md).
side_sheet_open :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	window: ops.Size,
	modal := true,
	width: f32 = tok.NAVIGATION_DRAWER_CONTAINER_WIDTH,
	left := false,
	headline := "",
	key: u64 = 0,
	loc := #caller_location,
) -> Sheet {
	sh: Sheet
	id := ui.claim_id(gtx, key, loc)
	sp := new(Sheet_Paint, gtx.allocator)
	sp^ = {kind = modal ? .Side_Modal : .Side_Standard, left = left, drag_id = ui.id_mix(id, 1)}
	sh.width = width - 48
	if modal {
		for e in ui.events(gtx, sp.drag_id) {
			if e.kind == .Key && e.key == .Escape {
				open^ = false
			}
		}
		if open^ {
			ui.key_interest(gtx, sp.drag_id, .Escape)
		}
		st := ui.widget_state(gtx, id)
		// Offset toward the edge it hides behind: 0 shown, width hidden.
		slide := animate(gtx, {st = st}, 0, open^ ? 0 : width, .Default_Spatial, 0.1)
		scrim := animate(gtx, {st = st}, 1, open^ ? 1 : 0, .Default_Effects)
		if !open^ && slide >= width - 0.5 {
			return sh
		}
		sh.visible = true
		so := ui.overlay_open(gtx, cs = ui.exact(window), root = true, cover = true)
		scrim_id := ui.id_mix(id, 2)
		for e in ui.events(gtx, scrim_id) {
			if e.kind == .Press {
				open^ = false
			}
		}
		ops.fill(gtx.scene, ops.Rect{0, 0, window.x, window.y}, ops.with_alpha(color(tok.SCRIM_CONTAINER_COLOR), tok.SCRIM_CONTAINER_OPACITY * clamp(scrim, 0, 1)))
		if open^ {
			ops.input_area(gtx.scene, scrim_id, ops.Rect{0, 0, window.x, window.y}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		}
		ui.close(&so)
		sh.overlay = ui.overlay_open(gtx, {left ? -slide : slide, 0.001}, ui.exact(window), root = true, cover = true)
		r := ui.row_open(gtx, align = .Fill)
		sh.flexes[0] = r
		sh.nflex = 1
		if !left {
			ui.fill_space(gtx)
		}
	} else {
		sh.visible = true
		sh.flexes[0] = {index = -1} // no placement wrapper inline
		sh.nflex = 1
	}
	b := ui.box_open(gtx, {padding = ui.pad_all(24), paint = paint_sheet, user = sp}, key = 1)
	sh.boxes[0] = b
	sh.nbox = 1
	ui.container_semantics(gtx, {role = modal ? .Dialog : .Group, label = headline, states = modal ? {.Modal} : {}})
	inner := ui.column_open(gtx, gap = 16)
	sh.flexes[1] = inner
	sh.nflex = 2
	strut(gtx, sh.width) // the sheet's width
	if headline != "" {
		hr := ui.row_open(gtx, align = .Center)
		t := sheet_headline(gtx, headline)
		if modal {
			// The close button sits at the end: the row's width is the sheet's.
			ui.spacer(gtx, max(sh.width - t.width - tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT, 0))
		}
		if modal && icon_button(gtx, .Close, key = 7) {
			open^ = false
		}
		ui.close(&hr)
	}
	return sh
}

// sheet_headline is a side sheet's headline. The kit tokens only its
// colour (comp.navigation-drawer.headline-color); the kit gives no size,
// so this uses title-large.
@(private)
sheet_headline :: proc(gtx: ^ui.Ctx, s: string, loc := #caller_location) -> Text {
	p := ui.widget_open(gtx, 0, loc)
	t := shape_text(gtx, s, .Title_Large)
	draw_text(gtx, t, {}, color(tok.NAVIGATION_DRAWER_HEADLINE_COLOR))
	ui.semantics(gtx, &p, {role = .Heading, label = s})
	ui.widget_close(gtx, &p, {ops.Size{t.width, t.height}, baseline_of(t)})
	return t
}

// sheet_close closes a sheet opened by bottom_sheet or side_sheet.
sheet_close :: proc(sh: ^Sheet) {
	if !sh.visible {
		return
	}
	for i := sh.nflex - 1; i >= 1; i -= 1 {
		ui.close(&sh.flexes[i])
	}
	for i := sh.nbox - 1; i >= 0; i -= 1 {
		ui.close(&sh.boxes[i])
	}
	if sh.nflex >= 1 {
		ui.close(&sh.flexes[0])
	}
	if sh.overlay.active {
		ui.close(&sh.overlay)
	}
	sh.visible = false
}

@(private)
paint_sheet :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	sp := (^Sheet_Paint)(user)
	r := ops.Rect{0, 0, size.x, size.y}
	shape: ops.Shape
	switch sp.kind {
	case .Bottom:
		k := corners(tok.SHEET_BOTTOM_DOCKED_CONTAINER_SHAPE, r)
		shape = rounded(gtx, r, k)
		paint_elevation(gtx, {r, k.tl}, elevation_level(tok.SHEET_BOTTOM_DOCKED_MODAL_CONTAINER_ELEVATION))
		ops.fill(gtx.scene, shape, color(tok.SHEET_BOTTOM_DOCKED_CONTAINER_COLOR))
		// The measured height, for next frame's anchors.
		sp.state.height = size.y
	case .Side_Modal:
		// The drawer's shape rounds its end edge; a right-edge sheet mirrors it.
		k := corners(tok.NAVIGATION_DRAWER_CONTAINER_SHAPE, r)
		if !sp.left {
			k = {k.tr, k.tl, k.bl, k.br}
		}
		shape = rounded(gtx, r, k)
		paint_elevation(gtx, {r, max(k.tl, k.tr)}, elevation_level(tok.NAVIGATION_DRAWER_MODAL_CONTAINER_ELEVATION))
		ops.fill(gtx.scene, shape, color(tok.NAVIGATION_DRAWER_MODAL_CONTAINER_COLOR))
	case .Side_Standard:
		shape = r
		ops.fill(gtx.scene, r, color(tok.NAVIGATION_DRAWER_STANDARD_CONTAINER_COLOR))
		// The optional divider (anatomy divider), on the edge facing the content.
		ops.fill(gtx.scene, ops.Rect{sp.left ? size.x - 1 : 0, 0, 1, size.y}, color(.Outline_Variant))
	}
	// The sheet swallows its own presses so they do not reach the scrim,
	// takes drags, and takes focus on a press so Escape reaches it.
	ops.input_area(gtx.scene, sp.drag_id, shape, {.Press, .Release, .Move, .Enter, .Leave, .Scroll, .Key, .Focus, .Blur})
	ops.tag(gtx.scene, sp.drag_id, "sheet")
}

// drag_handle is M3 Expressive's drag handle (comp.drag-handle): the
// vertical grip between two resizable panes, not the bottom sheet's pill
// (sheets.json behaviour two-drag-handle-specs). A 4x48dp outline pill in a
// 24dp-wide slot that grows to 12x52dp on_surface with 12dp corners while
// pressed or dragged, on a fast-spatial spring (the kit names none; this is
// foundations' spring for small quick moves). The hit area is 48dp wide
// (foundations touchTarget). Returns how far the pointer has moved across
// this frame while it holds the handle: move the handle by it each frame
// and the grip stays under the pointer. state forces a look (Dragged included).
drag_handle :: proc(gtx: ^ui.Ctx, state := Interaction.Live, key: u64 = 0, loc := #caller_location) -> f32 {
	p := ui.widget_open(gtx, key, loc)
	W :: tok.DRAG_HANDLE_CONTAINER_WIDTH
	H := max(tok.DRAG_HANDLE_PRESSED_HEIGHT, tok.DRAG_HANDLE_DRAGGED_HEIGHT)
	hit := ops.Rect{(W - 48) / 2, 0, 48, H}
	c := Control{}
	dx: f32
	dragged := state == .Dragged
	#partial switch state {
	case .Live:
		st := ui.widget_state(gtx, p.id)
		grab := ui.widget_data(gtx, p.id, Handle_Grab)
		// Each Move adds its travel, which (unlike a difference of positions
		// local to the handle) does not change when the handle itself moves,
		// so the handle following the pointer cannot feed back into the next
		// delta.
		for e in ui.events(gtx, p.id) {
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
				st.pressed = true
				grab.moved = false
			case .Move:
				if st.pressed {
					dx += e.travel.x
					if e.travel.x != 0 {
						grab.moved = true
					}
				}
			case .Release:
				st.pressed = false
				grab.moved = false
			}
		}
		c = {st = st, hovered = st.hovered, pressed = st.pressed, focused = st.focused}
		dragged = st.pressed && grab.moved
	case:
		c = control(gtx, p.id, hit, state)
	}
	active := c.pressed || dragged
	pw := dragged ? tok.DRAG_HANDLE_DRAGGED_WIDTH : tok.DRAG_HANDLE_PRESSED_WIDTH
	ph := dragged ? tok.DRAG_HANDLE_DRAGGED_HEIGHT : tok.DRAG_HANDLE_PRESSED_HEIGHT
	w := animate(gtx, c, 0, active ? pw : tok.DRAG_HANDLE_WIDTH, .Fast_Spatial, 0.1)
	h := animate(gtx, c, 1, active ? ph : tok.DRAG_HANDLE_HEIGHT, .Fast_Spatial, 0.1)
	k := animate(gtx, c, 2, active ? 1 : 0, .Fast_Effects)
	pill := ops.Rect{(W - w) / 2, (H - h) / 2, w, h}
	shape_to := dragged ? tok.DRAG_HANDLE_DRAGGED_SHAPE : tok.DRAG_HANDLE_PRESSED_SHAPE
	ks := lerp_corners(corners(tok.DRAG_HANDLE_SHAPE, pill), corners(shape_to, pill), clamp(k, 0, 1))
	col := ops.mix(color(tok.DRAG_HANDLE_COLOR), color(dragged ? tok.DRAG_HANDLE_DRAGGED_COLOR : tok.DRAG_HANDLE_PRESSED_COLOR), clamp(k, 0, 1))
	if c.disabled {
		col = disabled_content()
	}
	ops.fill(gtx.scene, rounded(gtx, pill, ks), col)
	paint_focus_ring_corners(gtx, c, pill, ks)
	if state == .Live {
		ops.input_area(gtx.scene, p.id, hit, CLICK_KINDS)
	}
	ops.tag(gtx.scene, p.id, "drag_handle")
	ui.widget_close(gtx, &p, {size = {W, H}})
	return dx
}

// Handle_Grab is a drag handle's grab: whether it has moved since the
// press, which makes it a drag (the Dragged look) rather than a press.
@(private)
Handle_Grab :: struct {
	moved: bool,
}

// strut is an empty widget w wide and 0 tall: a minimum width for the
// column it sits in (spacer only runs along a flex's main axis).
strut :: proc(gtx: ^ui.Ctx, w: f32, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	ui.widget_close(gtx, &p, {size = {w, 0}})
}
