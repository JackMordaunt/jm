package material

import "core:math"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Navigation: drawer, rail, bar and badge (m3e-kit components/navigation-
// {drawer,rail,bar}.json and badge.json). Each navigation component is one
// widget over a slice of Nav_Item rather than a container of item widgets:
// jm:ui containers cannot be defined outside package ui, and a data-driven
// list also gives the drawer its own scroll.
//
// Not built, for want of jm:ui support: drag gestures (drawer swipe, rail
// anchor drag), arrow-key focus movement inside a group, and moving focus
// into a drawer or rail when it opens.

Nav_Item :: struct {
	label:       string,
	icon:        Icon,
	active_icon: Icon, // shown while active; .None reuses icon
	headline:    bool, // a section headline, not a destination
	badge:       string, // "" none; a small dot when " "
	disabled:    bool,
}

// Nav_Icon_Position is where a rail or bar item puts its icon: Top stacks
// it over the label (the vertical item), Start sets it beside the label
// (the horizontal item). Auto follows the component's own rule: the
// rail's expanded state, or the flexible bar's width.
Nav_Icon_Position :: enum u8 {
	Auto,
	Top,
	Start,
}

// Nav_Arrangement is how a flexible navigation bar spreads its items.
Nav_Arrangement :: enum u8 {
	Equal_Weight, // equal shares of the width, as the standard bar
	Centered, // grouped in the middle, padded by item count
}

// Badges (badge.json). A badge overlays its anchor's top-trailing corner
// and takes no space of its own. " " asks for the dot; any other label a
// numeral badge that widens to fit it. Overflow formatting ("999+") is the
// caller's: Compose's Badge.kt has none.

// BADGE_PADDING is the numeral badge's side padding around its label
// (badge.json layout extraHorizontalPadding, Badge.kt:200-202).
@(private = "file")
BADGE_PADDING :: f32(4)

// The badge's pull-in from its anchor's top-trailing corner (badge.json
// layout, Badge.kt:206-218): the badge's left edge sits x in from the
// anchor's right edge, and its bottom edge y below the anchor's top.
@(private = "file")
BADGE_DOT_OFFSET :: ui.Point{6, 6}
@(private = "file")
BADGE_NUMERAL_OFFSET :: ui.Point{12, 14}

// badge_size is the size label's badge draws at: the dot for " ", else at
// least comp.badge.large-size square, wider for a longer label.
badge_size :: proc(gtx: ^ui.Ctx, label: string) -> ui.Size {
	switch label {
	case "":
		return {}
	case " ":
		return {tok.BADGE_SIZE, tok.BADGE_SIZE}
	}
	t := shape_style(gtx, label, tok.BADGE_LARGE_LABEL_TEXT_FONT)
	return {max(t.width + 2 * BADGE_PADDING, tok.BADGE_LARGE_SIZE), tok.BADGE_LARGE_SIZE}
}

// paint_badge draws label's badge with its top-left corner at at: the
// comp.badge dot for " ", else the numeral badge (comp.badge.large-*).
// "" draws nothing. Returns the badge's size.
paint_badge :: proc(gtx: ^ui.Ctx, at: ui.Point, label: string) -> ui.Size {
	size := badge_size(gtx, label)
	if label == "" {
		return size
	}
	r := ui.Rect{at.x, at.y, size.x, size.y}
	if label == " " {
		ui.fill(gtx.ops, rounded(gtx, r, corners(tok.BADGE_SHAPE, r)), color(tok.BADGE_COLOR))
		return size
	}
	ui.fill(gtx.ops, rounded(gtx, r, corners(tok.BADGE_LARGE_SHAPE, r)), color(tok.BADGE_LARGE_COLOR))
	t := shape_style(gtx, label, tok.BADGE_LARGE_LABEL_TEXT_FONT)
	draw_text(gtx, t, {r.x + (r.w - t.width) / 2, r.y + (r.h - t.height) / 2}, color(tok.BADGE_LARGE_LABEL_TEXT_COLOR))
	return size
}

// paint_badge_on draws label's badge over anchor's top-trailing corner, at
// the dot's or the numeral's own offset (Compose places it at x = anchor
// width - offset.x, y = offset.y - badge height).
paint_badge_on :: proc(gtx: ^ui.Ctx, anchor: ui.Rect, label: string) {
	if label == "" {
		return
	}
	off := label == " " ? BADGE_DOT_OFFSET : BADGE_NUMERAL_OFFSET
	size := badge_size(gtx, label)
	paint_badge(gtx, {anchor.x + anchor.w - off.x, anchor.y + off.y - size.y}, label)
}

// badge is a badge on its own, as a widget of its own size.
badge :: proc(gtx: ^ui.Ctx, label: string, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	size := paint_badge(gtx, {}, label)
	ui.widget_close(gtx, &p, {size = size})
}

// badged_icon is a size-dp icon anchoring label's badge. The widget is the
// icon's size: the badge overhangs it and takes no space, as in Compose's
// BadgedBox.
badged_icon :: proc(gtx: ^ui.Ctx, g: Icon, label: string, size: f32 = 24, tint := tok.Role.On_Surface_Variant, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	icon(gtx, g, {}, size, color(tint))
	paint_badge_on(gtx, {0, 0, size, size}, label)
	ui.widget_close(gtx, &p, {size = {size, size}})
}

// Navigation drawer (navigation-drawer.json). Deprecated in Expressive:
// replacedBy navigation-rail (the expanded rail); kept for parity.

// Drawer_Kind is how a drawer sits against the screen's content.
Drawer_Kind :: enum u8 {
	Permanent, // always laid out beside the content
	Dismissible, // slides in and out of the layout; the content reflows
	Modal, // floats over the content behind a scrim
}

// DRAWER_MARGIN is the gap either side of an item's active indicator: what
// the 360dp container leaves around the 336dp indicator.
@(private = "file")
DRAWER_MARGIN :: (tok.NAVIGATION_DRAWER_CONTAINER_WIDTH - tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_WIDTH) / 2

// DRAWER_HEADLINE_HEIGHT is a headline row's height: a chosen value, the
// minimum touch height, as navigation-drawer.json gives headlines a font
// and colour but no height.
@(private = "file")
DRAWER_HEADLINE_HEIGHT :: f32(48)

// Item padding (navigation-drawer.json layout item-padding,
// NavigationDrawer.kt:1140-1148).
@(private = "file")
DRAWER_ITEM_LEADING :: f32(16)
@(private = "file")
DRAWER_ITEM_TRAILING :: f32(24)
@(private = "file")
DRAWER_ITEM_GAP :: f32(12)

// Drawer_Scroll is a navigation drawer's item list scroll: offset is how
// far down the list is scrolled, in dp, clamped to its overflow each frame.
Drawer_Scroll :: struct {
	offset: f32,
}

// navigation_drawer is M3's navigation drawer sheet: width wide (at most
// comp.navigation-drawer.container-width, 360), height tall (0: the
// height it is offered, or its content's when unbounded), headlines and 56dp destinations whose active one sits on a
// secondary-container pill. It scrolls, with a scroll bar, when the items overflow. Clicking
// a destination sets selected^ and returns true.
//
// variant picks the presentation (modal = true is the older spelling of
// .Modal): Permanent is always laid out, square-edged; Dismissible and
// Modal show while open^ (nil = always) with the trailing corners rounded.
// Dismissible takes layout width as it slides in, so the content reflows;
// Modal takes none and draws over the content, in an overlay, behind a
// scrim that closes it on a press, as does Escape on a focused item. Open
// runs on the default-spatial spring and close on fast-effects, as the
// spec's asymmetric motion asks.
//
// scroll is the item list's scroll position (see Drawer_Scroll). Pass one
// to keep it yourself: to restore it, persist it, or share it between the
// drawer's variants; nil keeps it in the drawer's own widget_data.
navigation_drawer :: proc(
	gtx: ^ui.Ctx,
	items: []Nav_Item,
	selected: ^int,
	width: f32 = tok.NAVIGATION_DRAWER_CONTAINER_WIDTH,
	height: f32 = 0,
	modal := false,
	variant := Drawer_Kind.Permanent,
	open: ^bool = nil,
	scroll: ^Drawer_Scroll = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	v := modal ? Drawer_Kind.Modal : variant
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	w := min(width, tok.NAVIGATION_DRAWER_CONTAINER_WIDTH)
	content: f32 = 2 * DRAWER_MARGIN
	for it in items {
		content += it.headline ? DRAWER_HEADLINE_HEIGHT : tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_HEIGHT
	}
	h := height > 0 ? height : (cs.max.y < ui.INF ? cs.max.y : content)
	shown := v == .Permanent || open == nil || open^

	// The drawer's own state: spring 0 is the open progress; sc the item
	// list's scroll.
	dc := Control {
		st = ui.widget_state(gtx, p.id),
	}
	sc := scroll if scroll != nil else ui.widget_data(gtx, p.id, Drawer_Scroll)
	prog: f32 = 1
	if v != .Permanent {
		prog = animate(gtx, dc, 0, shown ? 1 : 0, shown ? .Default_Spatial : .Fast_Effects)
	}
	for e in ui.events(gtx, p.id) {
		if e.kind == .Scroll {
			sc.offset += e.scroll.y * ui.SCROLL_STEP
		}
	}
	bar_id := ui.id_mix(p.id, 0xfffe)
	sc.offset = ui.scroll_bar_handle(gtx, bar_id, .Vertical, {w, h}, content, clamp(sc.offset, 0, max(content - h, 0)), ends = drawer_bar_ends(v))
	offset := sc.offset

	layout_w := w
	switch v {
	case .Permanent:
	case .Dismissible:
		layout_w = w * clamp(prog, 0, 1)
	case .Modal:
		layout_w = 0
	}
	size := ui.constrain(cs, {layout_w, h})
	if !shown && prog <= 0 {
		ui.widget_close(gtx, &p, {size = size})
		return false
	}

	o: ui.Overlay
	if v == .Modal {
		o = ui.overlay_open(gtx)
		scrim_id := ui.id_mix(p.id, 0xffff)
		ui.fill(gtx.ops, ui.Rect{-1e5, -1e5, 2e5, 2e5}, ui.with_alpha(color(tok.SCRIM_CONTAINER_COLOR), tok.SCRIM_CONTAINER_OPACITY * clamp(prog, 0, 1)))
		if shown && open != nil {
			for e in ui.events(gtx, scrim_id) {
				if e.kind == .Press {
					open^ = false
				}
			}
			ui.input_area(gtx.ops, scrim_id, ui.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		}
	}

	sheet := ui.Rect{-(1 - prog) * w, 0, w, h}
	k := v == .Permanent ? Corners{} : corners(tok.NAVIGATION_DRAWER_CONTAINER_SHAPE, sheet)
	// The modal sheet's token elevation is 1dp, but the spec (layout
	// elevation, NavigationDrawer.kt) draws it at level 0: the scrim is its
	// depth cue. So neither variant casts a shadow.
	fill := v == .Modal ? tok.NAVIGATION_DRAWER_MODAL_CONTAINER_COLOR : tok.NAVIGATION_DRAWER_STANDARD_CONTAINER_COLOR
	outline := rounded(gtx, sheet, k)
	ui.fill(gtx.ops, outline, color(fill))
	ui.input_area(gtx.ops, p.id, sheet, {.Scroll, .Press, .Release})

	changed := false
	// Clip to the sheet's own outline, not its bounds, so the items and the
	// scroll bar along its edge stay inside its rounded corners.
	ui.clip_push(gtx.ops, outline)
	// Items start a margin down, the same margin as their sides: the kit
	// gives no top inset.
	y := DRAWER_MARGIN - offset
	item_w := min(tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_WIDTH, w - 2 * DRAWER_MARGIN)
	for it, i in items {
		if it.headline {
			if y + DRAWER_HEADLINE_HEIGHT > 0 && y < h {
				t := shape_style(gtx, it.label, tok.NAVIGATION_DRAWER_HEADLINE_FONT)
				// Aligned with the items' icons: their margin plus leading inset.
				draw_text(gtx, t, {sheet.x + DRAWER_MARGIN + DRAWER_ITEM_LEADING, y + (DRAWER_HEADLINE_HEIGHT - t.height) / 2}, color(tok.NAVIGATION_DRAWER_HEADLINE_COLOR))
			}
			y += DRAWER_HEADLINE_HEIGHT
			continue
		}
		ih := tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_HEIGHT
		r := ui.Rect{sheet.x + DRAWER_MARGIN, y, item_w, ih}
		if y + ih > 0 && y < h {
			id := ui.id_mix(p.id, u64(i))
			if paint_drawer_item(gtx, id, r, it, selected^ == i, .Live) {
				selected^ = i
				changed = true
			}
			if v != .Permanent && open != nil && escape_pressed(gtx, id) {
				open^ = false
			}
		}
		y += ih
	}
	ui.transform_push(gtx.ops, ui.translate(sheet.x, 0))
	ui.scroll_bar_paint(gtx, bar_id, .Vertical, {w, h}, content, offset, ends = drawer_bar_ends(v))
	ui.transform_pop(gtx.ops)
	ui.clip_pop(gtx.ops)
	if v == .Modal {
		ui.close(&o)
	}
	ui.widget_close(gtx, &p, {size = size})
	return changed
}

// escape_pressed reports whether an Escape key reached id this frame.
@(private = "file")
escape_pressed :: proc(gtx: ^ui.Ctx, id: ui.Area_Id) -> bool {
	for e in ui.events(gtx, id) {
		if e.kind == .Key && e.key == .Escape {
			return true
		}
	}
	return false
}

// drawer_item is one navigation-drawer destination as a standalone
// widget, width wide (the 336dp active indicator by default), so its
// states can be shown on their own.
drawer_item :: proc(
	gtx: ^ui.Ctx,
	item: Nav_Item,
	active: bool,
	width: f32 = tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_WIDTH,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	size := ui.constrain(gtx.constraints, {width, tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_HEIGHT})
	clicked := paint_drawer_item(gtx, p.id, {0, 0, size.x, size.y}, item, active, state)
	ui.widget_close(gtx, &p, {size = size})
	return clicked
}

// paint_drawer_item is one drawer destination in r: the active indicator
// pill when active, a 24dp icon, the label and an optional trailing badge
// label. Hover, focus and press recolour an inactive item's icon and label
// from on-surface-variant to on-surface; an active item stays
// on-secondary-container. The state layer is the content colour over the
// indicator's pill.
@(private = "file")
paint_drawer_item :: proc(gtx: ^ui.Ctx, id: ui.Area_Id, r: ui.Rect, it: Nav_Item, active: bool, state: Interaction) -> bool {
	c := control(gtx, id, r, it.disabled ? .Disabled : state)
	shape := rounded(gtx, r, corners(tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_SHAPE, r))
	ico, lab: tok.Role
	switch {
	case active && c.pressed:
		ico, lab = tok.NAVIGATION_DRAWER_ACTIVE_PRESSED_ICON_COLOR, tok.NAVIGATION_DRAWER_ACTIVE_PRESSED_LABEL_TEXT_COLOR
	case active && c.focused:
		ico, lab = tok.NAVIGATION_DRAWER_ACTIVE_FOCUS_ICON_COLOR, tok.NAVIGATION_DRAWER_ACTIVE_FOCUS_LABEL_TEXT_COLOR
	case active && c.hovered:
		ico, lab = tok.NAVIGATION_DRAWER_ACTIVE_HOVER_ICON_COLOR, tok.NAVIGATION_DRAWER_ACTIVE_HOVER_LABEL_TEXT_COLOR
	case active:
		ico, lab = tok.NAVIGATION_DRAWER_ACTIVE_ICON_COLOR, tok.NAVIGATION_DRAWER_ACTIVE_LABEL_TEXT_COLOR
	case c.pressed:
		ico, lab = tok.NAVIGATION_DRAWER_INACTIVE_PRESSED_ICON_COLOR, tok.NAVIGATION_DRAWER_INACTIVE_PRESSED_LABEL_TEXT_COLOR
	case c.focused:
		ico, lab = tok.NAVIGATION_DRAWER_INACTIVE_FOCUS_ICON_COLOR, tok.NAVIGATION_DRAWER_INACTIVE_FOCUS_LABEL_TEXT_COLOR
	case c.hovered:
		ico, lab = tok.NAVIGATION_DRAWER_INACTIVE_HOVER_ICON_COLOR, tok.NAVIGATION_DRAWER_INACTIVE_HOVER_LABEL_TEXT_COLOR
	case:
		ico, lab = tok.NAVIGATION_DRAWER_INACTIVE_ICON_COLOR, tok.NAVIGATION_DRAWER_INACTIVE_LABEL_TEXT_COLOR
	}
	icon_col, label_col := color(ico), color(lab)
	badge_col := active ? label_col : color(tok.NAVIGATION_DRAWER_LARGE_BADGE_LABEL_COLOR)
	if active {
		ui.fill(gtx.ops, shape, color(tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_COLOR))
	}
	if c.disabled {
		icon_col, label_col, badge_col = disabled_content(), disabled_content(), disabled_content()
	}
	paint_state_layer(gtx, c, shape, label_col)
	x := r.x + DRAWER_ITEM_LEADING
	g := active && it.active_icon != .None ? it.active_icon : it.icon
	if g != .None {
		sz := tok.NAVIGATION_DRAWER_ICON_SIZE
		icon(gtx, g, {x, r.y + (r.h - sz) / 2}, sz, icon_col)
		x += sz + DRAWER_ITEM_GAP
	}
	t := shape_style(gtx, it.label, tok.NAVIGATION_DRAWER_LABEL_TEXT_FONT)
	draw_text(gtx, t, {x, r.y + (r.h - t.height) / 2}, label_col)
	if it.badge != "" {
		b := shape_style(gtx, it.badge, tok.NAVIGATION_DRAWER_LARGE_BADGE_LABEL_FONT)
		draw_text(gtx, b, {r.x + r.w - DRAWER_ITEM_TRAILING - b.width, r.y + (r.h - b.height) / 2}, badge_col)
	}
	paint_focus_ring_corners(gtx, c, r, corners(tok.NAVIGATION_DRAWER_ACTIVE_INDICATOR_SHAPE, r), inward = true)
	listen(gtx, c, id, r)
	ui.tag(gtx.ops, id, ui.frame_string(gtx, it.label))
	return c.clicked
}

// Rail and bar items share one painter: an item is a vertical (icon over
// label) or horizontal (icon beside label) layout of the same parts, and
// the two animate into each other.

// Nav_Style is one component's item geometry and colours, from its token
// groups.
@(private = "file")
Nav_Style :: struct {
	v_indicator:    ui.Size, // vertical item's indicator
	v_gap:          f32, // indicator to label
	v_font:         tok.Type_Style,
	h_height:       f32, // horizontal item's indicator height
	h_leading:      f32, // indicator edge to icon
	h_trailing:     f32, // label to indicator edge
	h_gap:          f32, // icon to label
	h_font:         tok.Type_Style,
	icon:           f32,
	indicator:      tok.Role,
	active_icon:    tok.Role,
	inactive_icon:  tok.Role,
	active_label:   tok.Role,
	inactive_label: tok.Role,
	active_layer:   tok.Role,
	inactive_layer: tok.Role,
}

// BAR_STYLE is comp.navigation-bar-{vertical,horizontal}-item. The kit
// has no horizontal-item label font or state-layer colours for the bar:
// both layouts use label-text-font, and the state layer is the icon's
// colour (foundations.json stateLayer: the component's content colour).
@(private = "file")
BAR_STYLE :: Nav_Style {
	v_indicator    = {tok.NAVIGATION_BAR_VERTICAL_ITEM_ACTIVE_INDICATOR_WIDTH, tok.NAVIGATION_BAR_VERTICAL_ITEM_ACTIVE_INDICATOR_HEIGHT},
	v_gap          = tok.NAVIGATION_BAR_ITEM_ACTIVE_INDICATOR_ICON_LABEL_SPACE,
	v_font         = tok.NAVIGATION_BAR_LABEL_TEXT_FONT,
	h_height       = tok.NAVIGATION_BAR_HORIZONTAL_ITEM_ACTIVE_INDICATOR_HEIGHT,
	h_leading      = tok.NAVIGATION_BAR_HORIZONTAL_ITEM_ACTIVE_INDICATOR_LEADING_SPACE,
	h_trailing     = tok.NAVIGATION_BAR_HORIZONTAL_ITEM_ACTIVE_INDICATOR_TRAILING_SPACE,
	h_gap          = tok.NAVIGATION_BAR_ITEM_ACTIVE_INDICATOR_ICON_LABEL_SPACE,
	h_font         = tok.NAVIGATION_BAR_LABEL_TEXT_FONT,
	icon           = tok.NAVIGATION_BAR_VERTICAL_ITEM_ICON_SIZE,
	indicator      = tok.NAVIGATION_BAR_ITEM_ACTIVE_INDICATOR_COLOR,
	active_icon    = tok.NAVIGATION_BAR_ITEM_ACTIVE_ICON_COLOR,
	inactive_icon  = tok.NAVIGATION_BAR_ITEM_INACTIVE_ICON_COLOR,
	active_label   = tok.NAVIGATION_BAR_ITEM_ACTIVE_LABEL_TEXT_COLOR,
	inactive_label = tok.NAVIGATION_BAR_ITEM_INACTIVE_LABEL_TEXT_COLOR,
	active_layer   = tok.NAVIGATION_BAR_ITEM_ACTIVE_ICON_COLOR,
	inactive_layer = tok.NAVIGATION_BAR_ITEM_INACTIVE_ICON_COLOR,
}

// RAIL_STYLE is comp.navigation-rail-{vertical,horizontal,baseline}-item
// and comp.navigation-rail-color.
@(private = "file")
RAIL_STYLE :: Nav_Style {
	v_indicator    = {tok.NAVIGATION_RAIL_VERTICAL_ITEM_ACTIVE_INDICATOR_WIDTH, tok.NAVIGATION_RAIL_VERTICAL_ITEM_ACTIVE_INDICATOR_HEIGHT},
	v_gap          = tok.NAVIGATION_RAIL_VERTICAL_ITEM_ICON_LABEL_SPACE,
	v_font         = tok.NAVIGATION_RAIL_VERTICAL_ITEM_LABEL_TEXT_FONT,
	h_height       = tok.NAVIGATION_RAIL_HORIZONTAL_ITEM_ACTIVE_INDICATOR_HEIGHT,
	h_leading      = tok.NAVIGATION_RAIL_BASELINE_ITEM_ACTIVE_INDICATOR_LEADING_SPACE,
	h_trailing     = tok.NAVIGATION_RAIL_BASELINE_ITEM_ACTIVE_INDICATOR_TRAILING_SPACE,
	h_gap          = tok.NAVIGATION_RAIL_HORIZONTAL_ITEM_ICON_LABEL_SPACE,
	h_font         = tok.NAVIGATION_RAIL_HORIZONTAL_ITEM_LABEL_TEXT_FONT,
	icon           = tok.NAVIGATION_RAIL_BASELINE_ITEM_ICON_SIZE,
	indicator      = tok.NAVIGATION_RAIL_COLOR_ITEM_ACTIVE_INDICATOR,
	active_icon    = tok.NAVIGATION_RAIL_COLOR_ITEM_ACTIVE_ICON,
	inactive_icon  = tok.NAVIGATION_RAIL_COLOR_ITEM_INACTIVE_ICON,
	active_label   = tok.NAVIGATION_RAIL_COLOR_ITEM_ACTIVE_LABEL_TEXT,
	inactive_label = tok.NAVIGATION_RAIL_COLOR_ITEM_INACTIVE_LABEL_TEXT,
	active_layer   = tok.NAVIGATION_RAIL_COLOR_ITEM_ACTIVE_HOVERED_STATE_LAYER,
	inactive_layer = tok.NAVIGATION_RAIL_COLOR_ITEM_INACTIVE_HOVERED_STATE_LAYER,
}

// nav_item_width is a horizontal item's indicator width for label.
@(private = "file")
nav_item_width :: proc(gtx: ^ui.Ctx, sty: Nav_Style, label: string) -> f32 {
	w := sty.h_leading + sty.icon + sty.h_trailing
	if label != "" {
		w += sty.h_gap + shape_style(gtx, label, sty.h_font).width
	}
	return w
}

@(private = "file")
lerp_rect :: proc(a, b: ui.Rect, t: f32) -> ui.Rect {
	return {math.lerp(a.x, b.x, t), math.lerp(a.y, b.y, t), math.lerp(a.w, b.w, t), math.lerp(a.h, b.h, t)}
}

// paint_nav_item is one rail or bar destination in r. pos is its icon
// position, 0 on top to 1 at the start, in between while it animates:
// the indicator, icon and label each move between their two layouts, and
// the label swaps type style halfway (navigation-bar.json
// icon-position-reflow). inset places a horizontal item's indicator from
// r's left edge; < 0 centres it. label_always false shows the label only
// while active.
//
// Selection animates per item (Widget_State.springs): slot 0 grows the
// indicator's width from its centre on the fast-spatial spring, slot 1
// cross-fades icon and label colours on default-effects (navigation-
// bar.json indicator-motion and colour-motion). The state layer fills the
// indicator's full pill whatever its animated width, and the whole of r
// takes input.
@(private = "file")
paint_nav_item :: proc(
	gtx: ^ui.Ctx,
	id: ui.Area_Id,
	r: ui.Rect,
	it: Nav_Item,
	active: bool,
	sty: Nav_Style,
	pos: f32,
	inset: f32,
	label_always: bool,
	state: Interaction,
) -> bool {
	s := scheme()
	c := control(gtx, id, r, it.disabled ? .Disabled : state)
	sel := animate(gtx, c, 0, active ? 1 : 0, .Fast_Spatial)
	tone := clamp(animate(gtx, c, 1, active ? 1 : 0, .Default_Effects), 0, 1)
	shown: f32 = label_always ? 1 : tone // the label's share of the layout and its alpha
	has_label := it.label != ""
	t := shape_style(gtx, it.label, pos < 0.5 ? sty.v_font : sty.h_font)

	// Vertical: the indicator, then the label, as one block centred in r.
	block := sty.v_indicator.y + (has_label ? (sty.v_gap + t.height) * shown : 0)
	v_ind := ui.Rect{r.x + (r.w - sty.v_indicator.x) / 2, r.y + (r.h - block) / 2, sty.v_indicator.x, sty.v_indicator.y}
	v_label := ui.Point{r.x + (r.w - t.width) / 2, v_ind.y + v_ind.h + sty.v_gap}
	// Horizontal: the indicator wraps icon and label as one group.
	hw := sty.h_leading + sty.icon + sty.h_trailing + (has_label ? sty.h_gap + t.width : 0)
	hx := inset >= 0 ? r.x + inset : r.x + (r.w - hw) / 2
	h_ind := ui.Rect{hx, r.y + (r.h - sty.h_height) / 2, hw, sty.h_height}
	h_label := ui.Point{hx + sty.h_leading + sty.icon + sty.h_gap, h_ind.y + (h_ind.h - t.height) / 2}

	ind := lerp_rect(v_ind, h_ind, pos)
	icon_at := ui.Point {
		math.lerp(v_ind.x + (v_ind.w - sty.icon) / 2, h_ind.x + sty.h_leading, pos),
		ind.y + (ind.h - sty.icon) / 2,
	}
	label_at := ui.Point{math.lerp(v_label.x, h_label.x, pos), math.lerp(v_label.y, h_label.y, pos)}

	icon_col := ui.mix(s[sty.inactive_icon], s[sty.active_icon], tone)
	label_col := ui.mix(s[sty.inactive_label], s[sty.active_label], tone)
	if c.disabled {
		icon_col, label_col = disabled_content(), disabled_content()
	}
	if sel > 0.001 {
		// Grow from the centre; the spring's overshoot widens it briefly.
		gw := ind.w * sel
		g := ui.Rect{ind.x + (ind.w - gw) / 2, ind.y, gw, ind.h}
		ui.fill(gtx.ops, rounded(gtx, g, corners(tok.NAVIGATION_BAR_ITEM_ACTIVE_INDICATOR_SHAPE, g)), ui.with_alpha(s[sty.indicator], clamp(sel, 0, 1)))
	}
	pill := corners(tok.NAVIGATION_BAR_ITEM_ACTIVE_INDICATOR_SHAPE, ind)
	paint_state_layer(gtx, c, rounded(gtx, ind, pill), ui.mix(s[sty.inactive_layer], s[sty.active_layer], tone))
	g := active && it.active_icon != .None ? it.active_icon : it.icon
	icon(gtx, g, icon_at, sty.icon, icon_col)
	paint_badge_on(gtx, {icon_at.x, icon_at.y, sty.icon, sty.icon}, it.badge)
	if has_label && shown > 0.01 {
		label_col[3] = u8(f32(label_col[3]) * shown)
		draw_text(gtx, t, label_at, label_col)
	}
	paint_focus_ring_corners(gtx, c, ind, pill)
	listen(gtx, c, id, r)
	ui.tag(gtx.ops, id, ui.frame_string(gtx, it.label))
	return c.clicked
}

// nav_destination is one rail (bar = false) or bar destination as a
// standalone widget, to show its states: a vertical item (icon on top)
// 96x64, or with horizontal a horizontal item (icon at the start) as wide
// as its indicator. Colours and indicator animate as in the rail and bar.
nav_destination :: proc(
	gtx: ^ui.Ctx,
	it: Nav_Item,
	active: bool,
	bar := false,
	horizontal := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	sty := bar ? BAR_STYLE : RAIL_STYLE
	want := ui.Size{tok.NAVIGATION_RAIL_COLLAPSED_CONTAINER_WIDTH, tok.NAVIGATION_RAIL_BASELINE_ITEM_CONTAINER_HEIGHT}
	if bar {
		want.y = tok.NAVIGATION_BAR_CONTAINER_HEIGHT
	}
	if horizontal {
		want.x = nav_item_width(gtx, sty, it.label)
		if !bar {
			want.y = tok.NAVIGATION_RAIL_HORIZONTAL_ITEM_ACTIVE_INDICATOR_HEIGHT
		}
	}
	size := ui.constrain(gtx.constraints, want)
	clicked := paint_nav_item(gtx, p.id, {0, 0, size.x, size.y}, it, active, sty, horizontal ? 1 : 0, -1, true, state)
	ui.widget_close(gtx, &p, {size = size})
	return clicked
}

// Navigation rail (navigation-rail.json).

// RAIL_SCRIM_SETTLE is how far a modal rail's width must animate before
// its scrim shows (modal-default modalScrimSettlePoint,
// WideNavigationRail.kt:599-600).
@(private = "file")
RAIL_SCRIM_SETTLE :: f32(0.3)

// navigation_rail is M3's navigation rail, height tall (0: the offered
// height, or a natural one when unbounded): an
// optional header (a menu button when menu, then a FAB when fab_icon is
// set), then the destinations. Headline items are skipped. Returns
// whether selected^ changed and whether the FAB was clicked.
//
// Without expanded it is the plain rail: narrow-container-width (80),
// vertical items. With expanded it is the expandable rail (container-width
// 96) and the menu button toggles expanded^: the rail widens to hug its
// widest item within [220, 360], items turn horizontal (icon_position
// .Auto; pin .Top or .Start to override), their gap closes and their
// height drops, and a FAB with a fab_label becomes an extended FAB — all
// on one default-spatial spring. modal floats the expanded rail over the
// content (fast-spatial spring) on surface-container with rounded corners
// and elevation, behind a scrim that shows past 30% of the width change;
// a scrim press or Escape collapses it. hide_on_collapse (modal only)
// slides the collapsed rail fully offscreen, a dismissible drawer.
navigation_rail :: proc(
	gtx: ^ui.Ctx,
	items: []Nav_Item,
	selected: ^int,
	fab_icon := Icon.None,
	menu := false,
	expanded: ^bool = nil,
	modal := false,
	hide_on_collapse := false,
	fab_label := "",
	icon_position := Nav_Icon_Position.Auto,
	height: f32 = 0,
	key: u64 = 0,
	loc := #caller_location,
) -> (
	changed: bool,
	fab_clicked: bool,
) {
	p := ui.widget_open(gtx, key, loc)
	s := scheme()
	cs := gtx.constraints
	sty := RAIL_STYLE
	expandable := expanded != nil
	open := expandable && expanded^
	hide := modal && hide_on_collapse && expandable
	collapsed_w := expandable ? tok.NAVIGATION_RAIL_COLLAPSED_CONTAINER_WIDTH : tok.NAVIGATION_RAIL_COLLAPSED_NARROW_CONTAINER_WIDTH
	// Items keep the collapsed indicator's left edge when horizontal, so
	// the icon stays put while the rail widens.
	inset := (collapsed_w - sty.v_indicator.x) / 2

	widest: f32
	for it in items {
		if !it.headline {
			widest = max(widest, nav_item_width(gtx, sty, it.label))
		}
	}
	ext_w := tok.FAB_BASELINE_CONTAINER_WIDTH
	if fab_icon != .None && fab_label != "" {
		ext_w = tok.EXTENDED_FAB_SMALL_LEADING_SPACE + tok.EXTENDED_FAB_SMALL_ICON_SIZE + tok.EXTENDED_FAB_SMALL_ICON_LABEL_SPACE + shape_text(gtx, fab_label, .Title_Medium).width + tok.EXTENDED_FAB_SMALL_TRAILING_SPACE
		widest = max(widest, ext_w)
	}
	expanded_w := clamp(2 * inset + widest, tok.NAVIGATION_RAIL_EXPANDED_CONTAINER_WIDTH_MINIMUM, tok.NAVIGATION_RAIL_EXPANDED_CONTAINER_WIDTH_MAXIMUM)

	// The rail's own springs: slot 0 the expand progress, slot 1 the scrim.
	rc := Control {
		st = ui.widget_state(gtx, p.id),
	}
	prog := animate(gtx, rc, 0, open ? 1 : 0, modal ? .Fast_Spatial : .Default_Spatial)
	scrim: f32
	if modal {
		scrim = clamp(animate(gtx, rc, 1, open && prog > RAIL_SCRIM_SETTLE ? 1 : 0, .Default_Effects), 0, 1)
	}
	t := clamp(prog, 0, 1)
	pos := t
	switch {
	case hide || icon_position == .Start:
		pos = 1
	case icon_position == .Top:
		pos = 0
	}

	natural := tok.NAVIGATION_RAIL_COLLAPSED_TOP_SPACE
	if menu {
		natural += BAR_ICON_TARGET
	}
	if fab_icon != .None {
		natural += tok.FAB_BASELINE_CONTAINER_HEIGHT
	}
	if menu || fab_icon != .None {
		natural += tok.NAVIGATION_RAIL_BASELINE_ITEM_HEADER_SPACE_MINIMUM
	}
	for it in items {
		if !it.headline {
			natural += tok.NAVIGATION_RAIL_BASELINE_ITEM_CONTAINER_HEIGHT + tok.NAVIGATION_RAIL_COLLAPSED_ITEM_VERTICAL_SPACE
		}
	}
	h := height > 0 ? height : (cs.max.y < ui.INF ? cs.max.y : natural)
	w := hide ? expanded_w : math.lerp(collapsed_w, expanded_w, prog)
	layout_w := w
	if modal {
		layout_w = hide ? 0 : collapsed_w
	}
	size := ui.constrain(cs, {layout_w, h})
	if hide && !open && prog <= 0.001 {
		ui.widget_close(gtx, &p, {size = size})
		return
	}

	o: ui.Overlay
	if modal {
		o = ui.overlay_open(gtx)
		if scrim > 0 {
			ui.fill(gtx.ops, ui.Rect{-1e5, -1e5, 2e5, 2e5}, ui.with_alpha(color(tok.SCRIM_CONTAINER_COLOR), tok.SCRIM_CONTAINER_OPACITY * scrim))
		}
		if open {
			scrim_id := ui.id_mix(p.id, 0xffff)
			for e in ui.events(gtx, scrim_id) {
				if e.kind == .Press {
					expanded^ = false
				}
			}
			ui.input_area(gtx.ops, scrim_id, ui.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		}
	}

	x0: f32 = hide ? -(1 - prog) * expanded_w : 0
	view := ui.Rect{x0, 0, w, h}
	if modal {
		// Collapsed, a modal rail is the flat docked rail; expanding, it
		// takes the modal container's colour, shape and elevation.
		k := lerp_corners({}, corners(tok.NAVIGATION_RAIL_EXPANDED_MODAL_CONTAINER_SHAPE, view), hide ? 1 : t)
		col := ui.mix(color(tok.NAVIGATION_RAIL_COLLAPSED_CONTAINER_COLOR), color(tok.NAVIGATION_RAIL_EXPANDED_MODAL_CONTAINER_COLOR), hide ? 1 : t)
		if t > 0 {
			paint_elevation(gtx, {view, k.tr}, elevation_level(tok.NAVIGATION_RAIL_EXPANDED_MODAL_CONTAINER_ELEVATION))
		}
		ui.fill(gtx.ops, rounded(gtx, view, k), col)
		// The rail swallows presses on its own background, so they do not
		// reach the scrim.
		ui.input_area(gtx.ops, ui.id_mix(p.id, 0xfffe), view, {.Press, .Release})
	} else {
		ui.fill(gtx.ops, view, color(tok.NAVIGATION_RAIL_COLLAPSED_CONTAINER_COLOR))
	}
	ui.clip_push(gtx.ops, view)

	y := tok.NAVIGATION_RAIL_COLLAPSED_TOP_SPACE
	if menu {
		// A 48dp target centred on the items' icon column.
		mid := ui.id_mix(p.id, 998)
		name := open ? "Collapse navigation" : "Expand navigation"
		if bar_icon_button(gtx, mid, {x0 + inset + (sty.v_indicator.x - BAR_ICON_TARGET) / 2, y}, .Menu, s[.On_Surface_Variant], name = name) && expandable {
			expanded^ = !expanded^
		}
		y += BAR_ICON_TARGET
	}
	if fab_icon != .None {
		fid := ui.id_mix(p.id, 999)
		fw := math.lerp(tok.FAB_BASELINE_CONTAINER_WIDTH, ext_w, pos)
		area := ui.Rect{x0 + inset, y, fw, tok.FAB_BASELINE_CONTAINER_HEIGHT}
		shape := rounded(gtx, area, corners(tok.FAB_BASELINE_CONTAINER_SHAPE, area))
		c := control(gtx, fid, area, .Live)
		fg := color(tok.FAB_PRIMARY_CONTAINER_ICON_COLOR)
		// No shadow: the FAB sits flat on the rail, a chosen look, as the
		// rail spec gives its header no elevation.
		ui.fill(gtx.ops, shape, color(tok.FAB_PRIMARY_CONTAINER_CONTAINER_COLOR))
		paint_state_layer(gtx, c, shape, fg)
		isz := tok.FAB_BASELINE_ICON_SIZE
		icon(gtx, fab_icon, {area.x + (tok.FAB_BASELINE_CONTAINER_WIDTH - isz) / 2 + (tok.EXTENDED_FAB_SMALL_LEADING_SPACE - (tok.FAB_BASELINE_CONTAINER_WIDTH - isz) / 2) * pos, area.y + (area.h - isz) / 2}, isz, fg)
		if fab_label != "" && pos > 0.5 {
			lt := shape_text(gtx, fab_label, .Title_Medium)
			ui.clip_push(gtx.ops, area)
			draw_text(gtx, lt, {area.x + tok.EXTENDED_FAB_SMALL_LEADING_SPACE + isz + tok.EXTENDED_FAB_SMALL_ICON_LABEL_SPACE, area.y + (area.h - lt.height) / 2}, ui.with_alpha(fg, (pos - 0.5) * 2))
			ui.clip_pop(gtx.ops)
		}
		paint_focus_ring_corners(gtx, c, area, corners(tok.FAB_BASELINE_CONTAINER_SHAPE, area))
		listen(gtx, c, fid, area)
		ui.tag(gtx.ops, fid, fab_label != "" ? fab_label : "FAB")
		fab_clicked = c.clicked
		y += tok.FAB_BASELINE_CONTAINER_HEIGHT
	}
	if menu || fab_icon != .None {
		y += tok.NAVIGATION_RAIL_BASELINE_ITEM_HEADER_SPACE_MINIMUM
	}
	// Collapsed items are container-height tall, item-vertical-space apart;
	// expanded rows are as tall as their indicator, with no gap.
	item_h := math.lerp(tok.NAVIGATION_RAIL_BASELINE_ITEM_CONTAINER_HEIGHT, tok.NAVIGATION_RAIL_HORIZONTAL_ITEM_ACTIVE_INDICATOR_HEIGHT, pos)
	item_gap := math.lerp(tok.NAVIGATION_RAIL_COLLAPSED_ITEM_VERTICAL_SPACE, 0, pos)
	for it, i in items {
		if it.headline {
			continue
		}
		id := ui.id_mix(p.id, u64(i))
		if paint_nav_item(gtx, id, {x0, y, w, item_h}, it, selected^ == i, sty, pos, inset, true, .Live) {
			changed = selected^ != i
			selected^ = i
		}
		if modal && open && escape_pressed(gtx, id) {
			expanded^ = false
		}
		y += item_h + item_gap
	}
	ui.clip_pop(gtx.ops)
	if modal {
		ui.close(&o)
	}
	ui.widget_close(gtx, &p, {size = size})
	return
}

// drawer_bar_ends keeps a drawer's scroll bar clear of its rounded
// trailing corners, where the sheet's clip would cut the thumb short.
@(private = "file")
drawer_bar_ends :: proc(v: Drawer_Kind) -> f32 {
	if v == .Permanent {
		return 0
	}
	sh := tok.NAVIGATION_DRAWER_CONTAINER_SHAPE
	return max(sh.radii[1], sh.radii[2])
}

// Navigation bar (navigation-bar.json).

// navigation_bar is M3's navigation bar: comp.navigation-bar.container-
// height (64) tall across width (the offered width when 0), on
// surface-container. Returns true when selected^ changed.
//
// The standard bar shares its width equally among vertical items. The
// flexible bar also takes horizontal items — icon_position .Auto picks
// them at 600dp and wider — and arrangement .Centered groups the items in
// the middle, padded by their count. A width change that flips .Auto
// animates the items between layouts on the default-spatial spring.
// always_show_label false shows only the active item's label. The bar
// casts no shadow: foundations.json carries depth by surface tone first,
// and its surface-container colour is that tone.
navigation_bar :: proc(
	gtx: ^ui.Ctx,
	items: []Nav_Item,
	selected: ^int,
	width: f32 = 0,
	flexible := false,
	icon_position := Nav_Icon_Position.Auto,
	arrangement := Nav_Arrangement.Equal_Weight,
	always_show_label := true,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	cs := gtx.constraints
	sty := BAR_STYLE
	w := width > 0 ? width : (cs.max.x < ui.INF ? cs.max.x : 412)
	size := ui.constrain(cs, {w, tok.NAVIGATION_BAR_CONTAINER_HEIGHT})
	bar := ui.Rect{0, 0, size.x, size.y}
	ui.fill(gtx.ops, rounded(gtx, bar, corners(tok.NAVIGATION_BAR_NAV_SHAPE, bar)), color(tok.NAVIGATION_BAR_CONTAINER_COLOR))

	horizontal := false
	if flexible {
		switch icon_position {
		case .Auto:
			// mdc:BottomNavigation.md: medium windows and wider.
			horizontal = size.x >= 600
		case .Start:
			horizontal = true
		case .Top:
		}
	}
	bc := Control {
		st = ui.widget_state(gtx, p.id),
	}
	pos := clamp(animate(gtx, bc, 0, horizontal ? 1 : 0, .Default_Spatial), 0, 1)

	n := 0
	for it in items {
		if !it.headline {
			n += 1
		}
	}
	changed := false
	if n == 0 {
		ui.widget_close(gtx, &p, {size = size})
		return false
	}
	// Item widths: equal shares, or (centered) at least an equal share of
	// the padded group and at most an equal share of the bar, the group
	// re-centred as items grow (ShortNavigationBar.kt:596-615).
	WIDTHS :: 16
	widths: [WIDTHS]f32
	total: f32
	share := size.x / f32(n)
	pad: f32
	if flexible && arrangement == .Centered {
		pad = max((100 - 10 * f32(min(n, 6) + 3)) / 2 / 100, 0) * size.x
	}
	min_share := (size.x - 2 * pad) / f32(n)
	k := 0
	for it in items {
		if it.headline || k >= WIDTHS {
			continue
		}
		iw := share
		if pad > 0 {
			natural := math.lerp(sty.v_indicator.x, nav_item_width(gtx, sty, it.label), pos)
			iw = clamp(natural, min_share, share)
		}
		widths[k] = iw
		total += iw
		k += 1
	}
	x := (size.x - total) / 2
	k = 0
	for it, i in items {
		if it.headline || k >= WIDTHS {
			continue
		}
		r := ui.Rect{x, 0, widths[k], size.y}
		if paint_nav_item(gtx, ui.id_mix(p.id, u64(i)), r, it, selected^ == i, sty, pos, -1, always_show_label, .Live) {
			changed = selected^ != i
			selected^ = i
		}
		x += widths[k]
		k += 1
	}
	ui.widget_close(gtx, &p, {size = size})
	return changed
}
