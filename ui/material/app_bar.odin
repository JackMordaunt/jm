package material

import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/material/tokens"

// Top app bars and tabs (m3e-kit components/app-bar.json and tabs.json).

// App_Bar_Kind is the bar's size (app-bar.json variants): each maps to a
// token group. Center is Small with its title centred, kept as a kind for
// the callers that already name it; centered does the same for any kind.
App_Bar_Kind :: enum u8 {
	Small, // one 64dp row, comp.app-bar-small
	Center, // Small, title centred
	Medium, // two rows, 112dp, comp.app-bar-medium
	Large, // two rows, 152dp, comp.app-bar-large
	Medium_Flexible, // two rows, 112dp or 136dp with a subtitle
	Large_Flexible, // two rows, 120dp or 152dp with a subtitle
	Search, // Small whose title slot is a comp.search-bar field
}

App_Bar_Result :: struct {
	navigation: bool, // the leading navigation icon was clicked
	action:     int, // index into actions clicked this frame, or -1
	search:     bool, // Search: the field was clicked, to open a search view
}

// Title placement (app-bar.json layout, AppBar.kt:3606-3615): a single
// row's title sits at least TITLE_INSET past the leading edge padding;
// a two-row bar's expanded title's last baseline sits its size's padding
// above the bar's bottom.
@(private = "file")
APP_BAR_TITLE_INSET :: f32(12)
@(private = "file")
APP_BAR_MEDIUM_TITLE_BOTTOM :: f32(24)
@(private = "file")
APP_BAR_LARGE_TITLE_BOTTOM :: f32(28)

// BAR_ICON_TARGET is an icon button's touch target (foundations.json
// touchTarget), what bars and rails lay their icons out in.
@(private)
BAR_ICON_TARGET :: MIN_TOUCH

// top_app_bar is M3's top app bar across width (the offered width when
// 0): a leading navigation icon (navigation != .None), the title with an
// optional subtitle, and trailing action icons laid out end to start.
// The title is start-aligned unless centered (or kind .Center), centring
// on the whole bar and nudged clear of the icons. Search puts a
// search-bar field in the title's place, with title as its placeholder.
//
// Single-row bars cross-fade from container-color to on-scroll-container-
// color on the default-effects spring while scrolled. Two-row bars stack
// a collapsed row (the small title) over an expanded row (the kind's
// title); collapsed, 0 to 1, is the caller's collapsed fraction: the
// height shrinks toward the small bar's 64dp, the colour interpolates,
// the expanded title fades out and the small one fades in along
// cubic-bezier(.8, 0, .8, .15) (app-bar.json title-alpha-crossfade). The
// scroll behaviours that would drive collapsed are the caller's: jm:ui
// has no nested-scroll connection. Titles do not wrap (jm:ui text does
// not), and the on-scroll elevation is tonal, not a shadow (app-bar.json
// notes: AppBar.kt fills a plain rectangle).
//
// The bar is a toolbar: one roving focus scope, so one tab stop, whose
// Left and Right move between its buttons, wrapping, as the toolbar
// pattern has them.
top_app_bar :: proc(
	gtx: ^ui.Ctx,
	title: string,
	kind := App_Bar_Kind.Small,
	navigation := Icon.Menu,
	actions: []Icon = nil,
	scrolled := false,
	width: f32 = 0,
	subtitle := "",
	centered := false,
	collapsed: f32 = 0,
	key: u64 = 0,
	loc := #caller_location,
) -> App_Bar_Result {
	p := ui.widget_open(gtx, key, loc)
	ui.semantics(gtx, &p, {role = .Toolbar, label = title})
	ui.focus_scope_open(gtx, p.id, rove = .Horizontal, wrap = true)
	res := App_Bar_Result {
		action = -1,
	}
	centre := centered || kind == .Center
	small_h := tok.APP_BAR_SMALL_CONTAINER_HEIGHT
	full_h := small_h
	title_font, sub_font := tok.APP_BAR_SMALL_TITLE_FONT, tok.APP_BAR_SMALL_SUBTITLE_FONT
	bottom: f32
	two_row := true
	switch kind {
	case .Small, .Center, .Search:
		two_row = false
	case .Medium:
		// The fixed medium and large groups have no subtitle font: they
		// borrow their flexible twin's.
		full_h, title_font, sub_font, bottom = tok.APP_BAR_MEDIUM_CONTAINER_HEIGHT, tok.APP_BAR_MEDIUM_TITLE_FONT, tok.APP_BAR_MEDIUM_FLEXIBLE_SUBTITLE_FONT, APP_BAR_MEDIUM_TITLE_BOTTOM
	case .Large:
		full_h, title_font, sub_font, bottom = tok.APP_BAR_LARGE_CONTAINER_HEIGHT, tok.APP_BAR_LARGE_TITLE_FONT, tok.APP_BAR_LARGE_FLEXIBLE_SUBTITLE_FONT, APP_BAR_LARGE_TITLE_BOTTOM
	case .Medium_Flexible:
		full_h = subtitle != "" ? tok.APP_BAR_MEDIUM_FLEXIBLE_LARGE_CONTAINER_HEIGHT : tok.APP_BAR_MEDIUM_FLEXIBLE_CONTAINER_HEIGHT
		title_font, sub_font, bottom = tok.APP_BAR_MEDIUM_FLEXIBLE_TITLE_FONT, tok.APP_BAR_MEDIUM_FLEXIBLE_SUBTITLE_FONT, APP_BAR_MEDIUM_TITLE_BOTTOM
	case .Large_Flexible:
		full_h = subtitle != "" ? tok.APP_BAR_LARGE_FLEXIBLE_LARGE_CONTAINER_HEIGHT : tok.APP_BAR_LARGE_FLEXIBLE_CONTAINER_HEIGHT
		title_font, sub_font, bottom = tok.APP_BAR_LARGE_FLEXIBLE_TITLE_FONT, tok.APP_BAR_LARGE_FLEXIBLE_SUBTITLE_FONT, APP_BAR_LARGE_TITLE_BOTTOM
	}
	f := two_row ? clamp(collapsed, 0, 1) : 0
	h := full_h + (small_h - full_h) * f
	w := width > 0 ? width : (gtx.constraints.max.x < ui.INF ? gtx.constraints.max.x : 412)
	size := ui.constrain(gtx.constraints, {w, h})

	// Slot 0 is the single-row scrolled tint. Read before the icon buttons'
	// control() calls, which may move the state map.
	bc := Control {
		st = ui.widget_state(gtx, p.id),
	}
	tint := f
	if !two_row {
		tint = clamp(animate(gtx, bc, 0, scrolled ? 1 : 0, .Default_Effects), 0, 1)
	}
	view := ops.Rect{0, 0, size.x, size.y}
	ops.fill(gtx.scene, rounded(gtx, view, corners(tok.APP_BAR_CONTAINER_SHAPE, view)), ops.mix(color(tok.APP_BAR_CONTAINER_COLOR), color(tok.APP_BAR_ON_SCROLL_CONTAINER_COLOR), tint))

	// The top row: icons in 48dp targets, leading-space and trailing-space
	// from the edges, icon-button-space apart.
	iy := (small_h - BAR_ICON_TARGET) / 2
	left := tok.APP_BAR_LEADING_SPACE + APP_BAR_TITLE_INSET
	if navigation != .None {
		nid := ui.id_mix(p.id, 1)
		if bar_icon_button(gtx, nid, {tok.APP_BAR_LEADING_SPACE, iy}, navigation, color(tok.APP_BAR_LEADING_ICON_COLOR), name = "navigation") {
			res.navigation = true
		}
		ui.part_semantics(gtx, &p, nid, {tok.APP_BAR_LEADING_SPACE, iy, BAR_ICON_TARGET, BAR_ICON_TARGET}, {role = .Button, label = "navigation"})
		left = tok.APP_BAR_LEADING_SPACE + max(APP_BAR_TITLE_INSET, BAR_ICON_TARGET)
	}
	right := size.x - tok.APP_BAR_TRAILING_SPACE
	for i := len(actions) - 1; i >= 0; i -= 1 {
		right -= BAR_ICON_TARGET
		aid := ui.id_mix(p.id, u64(10 + i))
		if bar_icon_button(gtx, aid, {right, iy}, actions[i], color(tok.APP_BAR_TRAILING_ICON_COLOR)) {
			res.action = i
		}
		ui.part_semantics(gtx, &p, aid, {right, iy, BAR_ICON_TARGET, BAR_ICON_TARGET}, {role = .Button, label = icon_name(actions[i])})
		right -= tok.APP_BAR_ICON_BUTTON_SPACE
	}
	if len(actions) == 0 {
		right = size.x - tok.APP_BAR_TRAILING_SPACE - APP_BAR_TITLE_INSET
	}

	title_col, sub_col := color(tok.APP_BAR_TITLE_COLOR), color(tok.APP_BAR_SUBTITLE_COLOR)
	if kind == .Search {
		sid := ui.id_mix(p.id, 2)
		sr := ops.Rect{left, (small_h - tok.SEARCH_BAR_CONTAINER_HEIGHT) / 2, max(right - left, 0), tok.SEARCH_BAR_CONTAINER_HEIGHT}
		res.search = paint_search_bar(gtx, sid, sr, title)
		ui.part_semantics(gtx, &p, sid, sr, {role = .Button, label = title})
	} else {
		// The small (collapsed) title: a single row's only title, or a
		// two-row bar's top one, fading in as it collapses.
		top_alpha: f32 = 1
		if two_row {
			// app-bar.json title-alpha-crossfade values (AppBar.kt:3604).
			top_alpha = bezier_ease({0.8, 0, 0.8, 0.15}, f)
		}
		if top_alpha > 0.01 {
			t := shape_style(gtx, title, tok.APP_BAR_SMALL_TITLE_FONT)
			st := shape_style(gtx, subtitle, tok.APP_BAR_SMALL_SUBTITLE_FONT)
			block := t.height + (subtitle != "" ? st.height : 0)
			y := (small_h - block) / 2
			draw_text(gtx, t, {title_x(t.width, size.x, left, right, centre), y}, ops.with_alpha(title_col, top_alpha))
			if subtitle != "" {
				draw_text(gtx, st, {title_x(st.width, size.x, left, right, centre), y + t.height}, ops.with_alpha(sub_col, top_alpha))
			}
		}
		if two_row && f < 0.99 {
			// The expanded row, below the top one, clipped as it shrinks;
			// its last line's baseline sits bottom above the bar's bottom.
			ops.clip_push(gtx.scene, ops.Rect{0, small_h, size.x, max(size.y - small_h, 0)})
			t := shape_style(gtx, title, title_font)
			st := shape_style(gtx, subtitle, sub_font)
			last := subtitle != "" ? st : t
			last_top := size.y - bottom - baseline_of(last)
			title_top := subtitle != "" ? last_top - t.height : last_top
			a := 1 - f
			edge := tok.APP_BAR_LEADING_SPACE + APP_BAR_TITLE_INSET
			draw_text(gtx, t, {title_x(t.width, size.x, edge, size.x - edge, centre), title_top}, ops.with_alpha(title_col, a))
			if subtitle != "" {
				draw_text(gtx, st, {title_x(st.width, size.x, edge, size.x - edge, centre), last_top}, ops.with_alpha(sub_col, a))
			}
			ops.clip_pop(gtx.scene)
		}
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, title))
	ui.focus_scope_close(gtx)
	ui.widget_close(gtx, &p, {size = size})
	return res
}

// title_x places a line w wide between left and right: at left, or
// centred on the whole bar (bar_w) and then nudged inside [left, right]
// (app-bar.json single-row-title-centering).
@(private = "file")
title_x :: proc(w, bar_w, left, right: f32, centre: bool) -> f32 {
	if !centre {
		return left
	}
	return max(min((bar_w - w) / 2, right - w), left)
}

// paint_search_bar is the search app bar's field in r: a comp.search-bar
// pill with a leading search icon and hint as its placeholder. It is not
// an input: a click reports true so the caller can open a search view,
// as MDC's search app bar does (app-bar.json search-app-bar-composition).
@(private = "file")
paint_search_bar :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, r: ops.Rect, hint: string) -> bool {
	c := control(gtx, id, r, .Live)
	shape := rounded(gtx, r, corners(tok.SEARCH_BAR_CONTAINER_SHAPE, r))
	ops.fill(gtx.scene, shape, color(tok.SEARCH_BAR_CONTAINER_COLOR))
	paint_state_layer(gtx, c, shape, color(tok.SEARCH_BAR_INPUT_TEXT_COLOR))
	// The icon in a 48dp target at the pill's start, then the hint.
	isz := tok.APP_BAR_ICON_SIZE
	icon(gtx, .Search, {r.x + (BAR_ICON_TARGET - isz) / 2 + 4, r.y + (r.h - isz) / 2}, isz, color(tok.SEARCH_BAR_LEADING_ICON_COLOR))
	t := shape_style(gtx, hint, tok.SEARCH_BAR_SUPPORTING_TEXT_FONT)
	ops.clip_push(gtx.scene, r)
	draw_text(gtx, t, {r.x + BAR_ICON_TARGET + 8, r.y + (r.h - t.height) / 2}, color(tok.SEARCH_BAR_SUPPORTING_TEXT_COLOR))
	ops.clip_pop(gtx.scene)
	paint_focus_ring_corners(gtx, c, r, corners(tok.SEARCH_BAR_CONTAINER_SHAPE, r))
	listen(gtx, c, id, r)
	ops.tag(gtx.scene, id, ui.frame_string(gtx, hint))
	return c.clicked
}

// bar_icon_button is a standard icon button painted at pos inside another
// widget: a 48dp target around the small icon button's 40dp container
// (comp.icon-button-small) as its state layer, for bars that lay out
// their own icons. name, when set, tags it. Returns true when clicked.
@(private)
bar_icon_button :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, pos: ops.Point, g: Icon, tint: ops.Color, state := Interaction.Live, name := "") -> bool {
	area := ops.Rect{pos.x, pos.y, BAR_ICON_TARGET, BAR_ICON_TARGET}
	c := control(gtx, id, area, state)
	d := tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT
	isz := tok.SMALL_ICON_BUTTON_ICON_SIZE
	col := c.disabled ? disabled_content() : tint
	ctr := ops.Point{pos.x + BAR_ICON_TARGET / 2, pos.y + BAR_ICON_TARGET / 2}
	paint_state_layer(gtx, c, ui.circle(ctr, d / 2), col)
	icon(gtx, g, {ctr.x - isz / 2, ctr.y - isz / 2}, isz, col)
	paint_focus_ring(gtx, c, {{ctr.x - d / 2, ctr.y - d / 2, d, d}, d / 2})
	listen(gtx, c, id, area)
	if name != "" {
		ops.tag(gtx.scene, id, name)
	}
	return c.clicked
}

// Tab geometry the kit gives as values, not tokens (tabs.json layout).
@(private = "file")
TAB_TEXT_PADDING :: f32(16) // horizontalTextPadding, Tab.kt:423-424
@(private = "file")
TAB_ICON_GAP :: f32(8) // textDistanceFromLeadingIcon, Tab.kt:441-442
@(private = "file")
TAB_EDGE_PADDING :: f32(52) // scrollable edgePadding, TabRow.kt:259
@(private = "file")
TAB_MIN_WIDTH :: f32(90) // scrollable minTabWidth, TabRow.kt:268
@(private = "file")
TAB_INDICATOR_MIN :: f32(24) // indicatorMinWidth, TabRow.kt:460-461

// MAX_TABS bounds a row's tabs, so its layout fits in stack arrays.
@(private = "file")
MAX_TABS :: 32

// Tabs_Scroll is a scrollable tab row's scroll position: target is where
// the row is headed (wheel input and a newly selected tab move it, clamped
// to the overflow), offset the default-spatial spring that carries the
// drawn offset there. Set target to scroll the row; leave offset zero to
// have it jump there on the first frame.
Tabs_Scroll :: struct {
	target: f32,
	offset: ui.Spring,
}

// tabs is M3's tab row (comp.primary-navigation-tab, or secondary). Fixed
// rows share the offered width (width when > 0) equally; scrollable rows
// lay tabs out at their natural width (min 90) from a 52dp edge padding
// and scroll the overflow, bringing a newly selected tab to the centre.
// Primary tabs mark the active one with a 3dp primary indicator as wide
// as its content (min 24) and colour it primary; secondary tabs span the
// indicator across the tab and use an on-surface label. icons (one per
// label) puts a 24dp icon above each primary label, making the row 64dp,
// or beside each secondary label. A divider runs under the row.
//
// Motion: the indicator's position and width each follow the default-
// spatial spring (tabs.json indicator-motion); a tab's colour fades in on
// default-effects and out on fast-effects. state forces the look of tab
// state_tab only. Returns true when selected^ changed.
//
// The row is one roving focus scope, so one tab stop, entered at the
// selected tab: Left and Right move focus between tabs, wrapping, Home
// and End to the ends, and Enter or Space selects (tabs.json); a tab the
// arrows reach in a scrollable row scrolls to the centre.
//
// scroll is a scrollable row's scroll position (see Tabs_Scroll). Pass one
// to keep it yourself: to restore it, persist it, or keep it when the row
// is rebuilt under another id; nil keeps it in the row's own widget_data.
tabs :: proc(
	gtx: ^ui.Ctx,
	labels: []string,
	selected: ^int,
	icons: []Icon = nil,
	secondary := false,
	width: f32 = 0,
	state := Interaction.Live,
	state_tab := -1,
	scrollable := false,
	scroll: ^Tabs_Scroll = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	ui.semantics(gtx, &p, {role = .Tab_List})
	n := min(len(labels), MAX_TABS)
	with_icons := len(icons) >= n && n > 0
	stacked := with_icons && !secondary
	h := secondary ? tok.SECONDARY_NAVIGATION_TAB_CONTAINER_HEIGHT : (stacked ? tok.PRIMARY_NAVIGATION_TAB_ICON_AND_LABEL_TEXT_CONTAINER_HEIGHT : tok.PRIMARY_NAVIGATION_TAB_CONTAINER_HEIGHT)
	font := secondary ? tok.SECONDARY_NAVIGATION_TAB_LABEL_TEXT_FONT : tok.PRIMARY_NAVIGATION_TAB_LABEL_TEXT_FONT
	isz := secondary ? tok.SECONDARY_NAVIGATION_TAB_ICON_SIZE : tok.PRIMARY_NAVIGATION_TAB_ICON_SIZE
	w := width > 0 ? width : (gtx.constraints.max.x < ui.INF ? gtx.constraints.max.x : 412)
	size := ui.constrain(gtx.constraints, {w, h})
	view := ops.Rect{0, 0, size.x, size.y}
	ops.fill(gtx.scene, view, color(secondary ? tok.SECONDARY_NAVIGATION_TAB_CONTAINER_COLOR : tok.PRIMARY_NAVIGATION_TAB_CONTAINER_COLOR))
	// The divider is the secondary group's (the primary has none), drawn
	// under both rows as Compose's TabRow does (TabRow.kt:161,212).
	dh := tok.SECONDARY_NAVIGATION_TAB_DIVIDER_HEIGHT
	ops.fill(gtx.scene, ops.Rect{0, size.y - dh, size.x, dh}, color(tok.SECONDARY_NAVIGATION_TAB_DIVIDER_COLOR))
	if n == 0 {
		ui.widget_close(gtx, &p, {size = size})
		return false
	}

	// Layout, in row coordinates before scrolling.
	texts: [MAX_TABS]Text
	xs, ws, cws: [MAX_TABS]f32
	x: f32 = scrollable ? TAB_EDGE_PADDING : 0
	for i in 0 ..< n {
		t := shape_style(gtx, labels[i], font)
		cw := t.width
		if with_icons {
			cw = stacked ? max(t.width, isz) : isz + TAB_ICON_GAP + t.width
		}
		tw := size.x / f32(n)
		if scrollable {
			tw = max(cw + 2 * TAB_TEXT_PADDING, TAB_MIN_WIDTH)
		}
		texts[i], xs[i], ws[i], cws[i] = t, x, tw, cw
		x += tw
	}
	max_scroll := scrollable ? max(x + TAB_EDGE_PADDING - size.x, 0) : 0
	sel := clamp(selected^, 0, n - 1)
	target_x, target_w := xs[sel], ws[sel]
	if !secondary {
		target_w = max(cws[sel], TAB_INDICATOR_MIN)
		target_x = xs[sel] + (ws[sel] - target_w) / 2
	}

	// The row's springs: 0 indicator x, 1 indicator width; the scroll
	// lives in sc. A forced row has no retained state and sits at its
	// targets.
	ind_x, ind_w, off := target_x, target_w, f32(0)
	sc: ^Tabs_Scroll
	if state == .Live {
		rc := Control {
			st = ui.widget_state(gtx, p.id),
		}
		sc = scroll if scroll != nil else ui.widget_data(gtx, p.id, Tabs_Scroll)
		if scrollable {
			for e in ui.events(gtx, p.id) {
				if e.kind == .Scroll {
					sc.target += (e.scroll.x != 0 ? e.scroll.x : e.scroll.y) * ui.SCROLL_STEP
				}
			}
			sc.target = clamp(sc.target, 0, max_scroll)
			off = clamp(ui.spring_update(&sc.offset, gtx, sc.target, spring_params(.Default_Spatial), 0.1), 0, max_scroll)
			ops.input_area(gtx.scene, p.id, view, {.Scroll})
		}
		ind_x = animate(gtx, rc, 0, target_x, .Default_Spatial, 0.1)
		ind_w = animate(gtx, rc, 1, target_w, .Default_Spatial, 0.1)
	}
	if scrollable {
		ops.clip_push(gtx.scene, view)
	}

	changed := false
	ui.focus_scope_open(gtx, p.id, rove = .Horizontal, wrap = true)
	for i in 0 ..< n {
		r := ops.Rect{xs[i] - off, 0, ws[i], h}
		id := ui.id_mix(p.id, u64(i))
		st := state_tab == i ? state : (state == .Live ? Interaction.Live : Interaction.Enabled)
		c := control(gtx, id, r, st)
		active := selected^ == i
		tone := clamp(animate(gtx, c, 0, active ? 1 : 0, active ? .Default_Effects : .Fast_Effects), 0, 1)
		if c.clicked && selected^ != i {
			selected^ = i
			changed = true
		}
		for e in ui.events(gtx, id) {
			if scrollable && sc != nil && e.kind == .Focus && e.key != .None {
				sc.target = clamp(xs[i] + ws[i] / 2 - size.x / 2, 0, max_scroll)
			}
		}
		content := ops.mix(color(tab_role(secondary, false, c)), color(tab_role(secondary, true, c)), tone)
		if c.disabled {
			content = disabled_content()
		}
		layer := secondary ? color(tok.SECONDARY_NAVIGATION_TAB_HOVER_LABEL_TEXT_COLOR) : ops.mix(color(tok.PRIMARY_NAVIGATION_TAB_INACTIVE_HOVER_LABEL_TEXT_COLOR), color(tok.PRIMARY_NAVIGATION_TAB_ACTIVE_HOVER_LABEL_TEXT_COLOR), tone)
		paint_state_layer(gtx, c, r, layer)
		t := texts[i]
		switch {
		case stacked:
			// The kit gives no gap for a stacked icon and label: the pair
			// is one block, centred.
			y := (h - isz - t.height) / 2
			icon(gtx, icons[i], {r.x + (r.w - isz) / 2, y}, isz, content)
			draw_text(gtx, t, {r.x + (r.w - t.width) / 2, y + isz}, content)
		case with_icons:
			x0 := r.x + (r.w - cws[i]) / 2
			icon(gtx, icons[i], {x0, (h - isz) / 2}, isz, content)
			draw_text(gtx, t, {x0 + isz + TAB_ICON_GAP, (h - t.height) / 2}, content)
		case:
			draw_text(gtx, t, {r.x + (r.w - t.width) / 2, (h - t.height) / 2}, content)
		}
		// Tabs abut, so the ring sits just inside the tab, not outside.
		gap := FOCUS_RING_OFFSET + FOCUS_RING_WIDTH
		paint_focus_ring_corners(gtx, c, {r.x + gap, r.y + gap, r.w - 2 * gap, r.h - 2 * gap}, {}, inward = true)
		listen(gtx, c, id, r)
		ops.tag(gtx.scene, id, ui.frame_string(gtx, labels[i]))
		// selected^ rather than active: a click this frame already moved it.
		ui.part_semantics(gtx, &p, id, r, {role = .Tab, label = labels[i], states = states_of(c, selected^ == i)})
	}
	ui.focus_scope_close(gtx, ui.id_mix(p.id, u64(sel)))

	ih := tok.PRIMARY_NAVIGATION_TAB_ACTIVE_INDICATOR_HEIGHT
	bar := ops.Rect{ind_x - off, h - ih, ind_w, ih}
	if secondary {
		// The secondary group has no indicator tokens, so this reuses the
		// primary's height and colour, square.
		ops.fill(gtx.scene, bar, color(tok.PRIMARY_NAVIGATION_TAB_ACTIVE_INDICATOR_COLOR))
	} else {
		ops.fill(gtx.scene, rounded(gtx, bar, corners(tok.PRIMARY_NAVIGATION_TAB_ACTIVE_INDICATOR_SHAPE, bar)), color(tok.PRIMARY_NAVIGATION_TAB_ACTIVE_INDICATOR_COLOR))
	}
	if scrollable {
		ops.clip_pop(gtx.scene)
		if changed && sc != nil {
			// Bring the new tab to the centre; the offset springs there.
			s := selected^
			sc.target = clamp(xs[s] + ws[s] / 2 - size.x / 2, 0, max_scroll)
		}
	}
	ui.widget_close(gtx, &p, {size = size})
	return changed
}

// tab_role is a tab's content colour token for its interaction state,
// active or not.
@(private = "file")
tab_role :: proc(secondary, active: bool, c: Control) -> tok.Role {
	if secondary {
		switch {
		case active:
			return tok.SECONDARY_NAVIGATION_TAB_ACTIVE_LABEL_TEXT_COLOR
		case c.pressed:
			return tok.SECONDARY_NAVIGATION_TAB_PRESSED_LABEL_TEXT_COLOR
		case c.focused:
			return tok.SECONDARY_NAVIGATION_TAB_FOCUS_LABEL_TEXT_COLOR
		case c.hovered:
			return tok.SECONDARY_NAVIGATION_TAB_HOVER_LABEL_TEXT_COLOR
		}
		return tok.SECONDARY_NAVIGATION_TAB_INACTIVE_LABEL_TEXT_COLOR
	}
	switch {
	case active && c.pressed:
		return tok.PRIMARY_NAVIGATION_TAB_ACTIVE_PRESSED_LABEL_TEXT_COLOR
	case active && c.focused:
		return tok.PRIMARY_NAVIGATION_TAB_ACTIVE_FOCUS_LABEL_TEXT_COLOR
	case active && c.hovered:
		return tok.PRIMARY_NAVIGATION_TAB_ACTIVE_HOVER_LABEL_TEXT_COLOR
	case active:
		return tok.PRIMARY_NAVIGATION_TAB_ACTIVE_LABEL_TEXT_COLOR
	case c.pressed:
		return tok.PRIMARY_NAVIGATION_TAB_INACTIVE_PRESSED_LABEL_TEXT_COLOR
	case c.focused:
		return tok.PRIMARY_NAVIGATION_TAB_INACTIVE_FOCUS_LABEL_TEXT_COLOR
	case c.hovered:
		return tok.PRIMARY_NAVIGATION_TAB_INACTIVE_HOVER_LABEL_TEXT_COLOR
	}
	return tok.PRIMARY_NAVIGATION_TAB_INACTIVE_LABEL_TEXT_COLOR
}
