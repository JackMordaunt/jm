package material

import "base:runtime"
import "core:strings"
import "jm:ui/ops"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Components that paint above the page: menus, tooltips, dialogs and the
// snackbar, from the m3e-kit's components/menu.json, tooltip.json,
// dialog.json and snackbar.json. A menu or dialog opens a ui.overlay, so
// it draws last and takes no space in the layout around it. To anchor one
// to a widget, put both in a ui.stack: the overlay is placed from the
// stack's origin.

// Menu_Style is menu.json's style axis: the legacy flat dropdown
// (comp.menu) or an Expressive menu in the standard or vibrant colours.
Menu_Style :: enum u8 {
	Legacy, // comp.menu: surface-container, 48dp label-large items
	Standard, // comp.standard-menu: surface-container-low, tertiary selection
	Vibrant, // comp.vibrant-menu: tertiary-container, tertiary selection
}

Menu_Item :: struct {
	label:         string,
	leading:       Icon,
	trailing:      string, // trailing supporting text, e.g. a shortcut
	disabled:      bool,
	divider:       bool, // flat: a divider after this item; grouped: the group ends here
	supporting:    string, // Expressive: a second line under the label
	trailing_icon: Icon,
	selected:      bool, // the selected colours (and, Expressive, shape)
	selected_icon: Icon, // shown in place of leading while selected, e.g. .Check
	submenu:       bool, // a trailing arrow: the item opens a submenu the caller composes
	heading:       bool, // Expressive: a group label, not an item
	state:         Interaction, // Live, or a forced look (the kitchen's state rows)
}

// MENU_* are the legacy dropdown's hard-coded metrics: 48dp items,
// 112-280dp wide, 12dp side padding, 8dp above and below the list
// (menu.json layout, Menu.kt:2374-2390).
@(private)
MENU_ITEM_HEIGHT :: f32(48)
@(private)
MENU_MIN_WIDTH :: f32(112)
@(private)
MENU_MAX_WIDTH :: f32(280)
@(private)
MENU_PAD_X :: f32(12)
@(private)
MENU_PAD_Y :: f32(8)
// MENU_DIVIDER_PAD is the space either side of a menu divider, which has
// no token (menu.json notes: 12dp horizontal, 2dp vertical).
@(private)
MENU_DIVIDER_PAD :: [2]f32{12, 2}
// MENU_GROUP_PAD_Y and MENU_GROUP_MIN_H are an Expressive group's 2dp
// vertical padding and 32dp minimum height (Menu.kt:2378,2393).
@(private)
MENU_GROUP_PAD_Y :: f32(2)
@(private)
MENU_GROUP_MIN_H :: f32(32)
// MENU_CLOSED_SCALE is the scale a menu, tooltip or snackbar grows from
// as it appears (Menu.kt:2402-2405, Tooltip.kt:212-230, SnackbarHost.kt:370-420).
@(private)
MENU_CLOSED_SCALE :: f32(0.8)

// Menu_Colors are one menu item's resolved colours.
@(private)
Menu_Colors :: struct {
	container, label, supporting, leading, trailing, trailing_text: ops.Color,
}

// menu_colors resolves an item's colours for style, from the style's own
// token group: legacy comp.menu, or comp.standard-menu / comp.vibrant-menu
// with their selected, disabled and selected-disabled families.
@(private)
menu_colors :: proc(style: Menu_Style, c: Control, selected: bool) -> (col: Menu_Colors) {
	switch style {
	case .Legacy:
		col = {{}, color(.On_Surface), color(.On_Surface_Variant), color(.On_Surface_Variant), color(.On_Surface_Variant), color(.On_Surface_Variant)}
		if selected {
			col.container = color(tok.MENU_LIST_ITEM_SELECTED_CONTAINER_COLOR)
			col.label = color(tok.MENU_LIST_ITEM_SELECTED_LABEL_TEXT_COLOR)
			col.leading = color(tok.MENU_LIST_ITEM_SELECTED_LEADING_TRAILING_ICON_COLOR)
			col.trailing = col.leading
			col.supporting, col.trailing_text = col.label, col.label
		}
		if c.disabled {
			d := disabled_content()
			col.label, col.supporting, col.leading, col.trailing, col.trailing_text = d, d, d, d, d
			if selected {
				col.container = ops.with_alpha(col.container, DISABLED_CONTENT_OPACITY)
			}
		}
	case .Standard:
		if selected {
			col = {
				color(tok.STANDARD_MENU_ITEM_SELECTED_CONTAINER_COLOR),
				color(tok.STANDARD_MENU_ITEM_SELECTED_LABEL_TEXT_COLOR),
				color(tok.STANDARD_MENU_ITEM_SELECTED_SUPPORTING_TEXT_COLOR),
				color(tok.STANDARD_MENU_ITEM_SELECTED_LEADING_ICON_COLOR),
				color(tok.STANDARD_MENU_ITEM_SELECTED_TRAILING_ICON_COLOR),
				color(tok.STANDARD_MENU_ITEM_SELECTED_TRAILING_SUPPORTING_TEXT_COLOR),
			}
			if c.disabled {
				col.container = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_CONTAINER_COLOR), tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_CONTAINER_OPACITY)
				col.label = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_LABEL_TEXT_COLOR), tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_LABEL_TEXT_OPACITY)
				col.leading = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_LEADING_ICON_COLOR), tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_LEADING_ICON_OPACITY)
				col.trailing = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_TRAILING_ICON_COLOR), tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_TRAILING_ICON_OPACITY)
				col.supporting, col.trailing_text = col.label, ops.with_alpha(color(tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_TRAILING_SUPPORTING_TEXT_COLOR), tok.STANDARD_MENU_ITEM_SELECTED_DISABLED_LABEL_TEXT_OPACITY)
			}
			return
		}
		col = {
			{},
			color(tok.STANDARD_MENU_ITEM_LABEL_TEXT_COLOR),
			color(tok.STANDARD_MENU_ITEM_SUPPORTING_TEXT_COLOR),
			color(tok.STANDARD_MENU_ITEM_LEADING_ICON_COLOR),
			color(tok.STANDARD_MENU_ITEM_TRAILING_ICON_COLOR),
			color(tok.STANDARD_MENU_ITEM_TRAILING_SUPPORTING_TEXT_COLOR),
		}
		switch {
		case c.disabled:
			col.label = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_DISABLED_LABEL_TEXT_COLOR), tok.STANDARD_MENU_ITEM_DISABLED_LABEL_TEXT_OPACITY)
			col.supporting = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_DISABLED_SUPPORTING_TEXT_COLOR), tok.STANDARD_MENU_ITEM_DISABLED_SUPPORTING_TEXT_OPACITY)
			col.leading = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_DISABLED_LEADING_ICON_COLOR), tok.STANDARD_MENU_ITEM_DISABLED_LEADING_ICON_OPACITY)
			col.trailing = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_DISABLED_TRAILING_ICON_COLOR), tok.STANDARD_MENU_ITEM_DISABLED_TRAILING_ICON_OPACITY)
			col.trailing_text = ops.with_alpha(color(tok.STANDARD_MENU_ITEM_DISABLED_TRAILING_SUPPORTING_TEXT_COLOR), tok.STANDARD_MENU_ITEM_DISABLED_TRAILING_SUPPORTING_TEXT_OPACITY)
		case c.pressed:
			col.label = color(tok.STANDARD_MENU_ITEM_PRESSED_LABEL_TEXT_COLOR)
			col.leading = color(tok.STANDARD_MENU_ITEM_PRESSED_LEADING_ICON_COLOR)
			col.trailing = color(tok.STANDARD_MENU_ITEM_PRESSED_TRAILING_ICON_COLOR)
		case c.focused:
			col.label = color(tok.STANDARD_MENU_ITEM_FOCUSED_LABEL_TEXT_COLOR)
			col.leading = color(tok.STANDARD_MENU_ITEM_FOCUSED_LEADING_ICON_COLOR)
			col.trailing = color(tok.STANDARD_MENU_ITEM_FOCUSED_TRAILING_ICON_COLOR)
		case c.hovered:
			col.label = color(tok.STANDARD_MENU_ITEM_HOVERED_LABEL_TEXT_COLOR)
			col.leading = color(tok.STANDARD_MENU_ITEM_HOVERED_LEADING_ICON_COLOR)
			col.trailing = color(tok.STANDARD_MENU_ITEM_HOVERED_TRAILING_ICON_COLOR)
		}
	case .Vibrant:
		if selected {
			col = {
				color(tok.VIBRANT_MENU_ITEM_SELECTED_CONTAINER_COLOR),
				color(tok.VIBRANT_MENU_ITEM_SELECTED_LABEL_TEXT_COLOR),
				color(tok.VIBRANT_MENU_ITEM_SELECTED_SUPPORTING_TEXT_COLOR),
				color(tok.VIBRANT_MENU_ITEM_SELECTED_LEADING_ICON_COLOR),
				color(tok.VIBRANT_MENU_ITEM_SELECTED_TRAILING_ICON_COLOR),
				color(tok.VIBRANT_MENU_ITEM_SELECTED_TRAILING_SUPPORTING_TEXT_COLOR),
			}
			switch {
			case c.disabled:
				// comp.vibrant-menu has no selected-disabled container: keep the
				// selected container, dim the content (menu.json notes).
				col.label = ops.with_alpha(col.label, tok.VIBRANT_MENU_ITEM_SELECTED_DISABLED_LABEL_TEXT_OPACITY)
				col.supporting = ops.with_alpha(col.supporting, tok.VIBRANT_MENU_ITEM_SELECTED_DISABLED_SUPPORTING_TEXT_OPACITY)
				col.leading = ops.with_alpha(col.leading, tok.VIBRANT_MENU_ITEM_SELECTED_DISABLED_LEADING_ICON_OPACITY)
				col.trailing = ops.with_alpha(col.trailing, tok.VIBRANT_MENU_ITEM_SELECTED_DISABLED_TRAILING_ICON_OPACITY)
				col.trailing_text = ops.with_alpha(col.trailing_text, tok.VIBRANT_MENU_ITEM_SELECTED_DISABLED_TRAILING_SUPPORTING_TEXT_OPACITY)
			case c.pressed:
				col.label = color(tok.VIBRANT_MENU_ITEM_SELECTED_PRESSED_LABEL_TEXT_COLOR)
			case c.focused:
				col.label = color(tok.VIBRANT_MENU_ITEM_SELECTED_FOCUSED_LABEL_TEXT_COLOR)
			case c.hovered:
				col.label = color(tok.VIBRANT_MENU_ITEM_SELECTED_HOVERED_LABEL_TEXT_COLOR)
			}
			return
		}
		col = {
			{},
			color(tok.VIBRANT_MENU_ITEM_LABEL_TEXT_COLOR),
			color(tok.VIBRANT_MENU_ITEM_SUPPORTING_TEXT_COLOR),
			color(tok.VIBRANT_MENU_ITEM_LEADING_ICON_COLOR),
			color(tok.VIBRANT_MENU_ITEM_TRAILING_ICON_COLOR),
			color(tok.VIBRANT_MENU_ITEM_TRAILING_SUPPORTING_TEXT_COLOR),
		}
		switch {
		case c.disabled:
			col.label = ops.with_alpha(color(tok.VIBRANT_MENU_ITEM_DISABLED_LABEL_TEXT_COLOR), tok.VIBRANT_MENU_ITEM_DISABLED_LABEL_TEXT_OPACITY)
			col.supporting = ops.with_alpha(color(tok.VIBRANT_MENU_ITEM_DISABLED_SUPPORTING_TEXT_COLOR), tok.VIBRANT_MENU_ITEM_DISABLED_SUPPORTING_TEXT_OPACITY)
			col.leading = ops.with_alpha(color(tok.VIBRANT_MENU_ITEM_DISABLED_LEADING_ICON_COLOR), tok.VIBRANT_MENU_ITEM_DISABLED_LEADING_ICON_OPACITY)
			col.trailing = ops.with_alpha(color(tok.VIBRANT_MENU_ITEM_DISABLED_TRAILING_ICON_COLOR), tok.VIBRANT_MENU_ITEM_DISABLED_TRAILING_ICON_OPACITY)
			col.trailing_text = ops.with_alpha(color(tok.VIBRANT_MENU_ITEM_DISABLED_TRAILING_SUPPORTING_TEXT_COLOR), tok.VIBRANT_MENU_ITEM_DISABLED_TRAILING_SUPPORTING_TEXT_OPACITY)
		case c.pressed:
			col.label = color(tok.VIBRANT_MENU_ITEM_PRESSED_LABEL_TEXT_COLOR)
			col.leading = color(tok.VIBRANT_MENU_ITEM_PRESSED_LEADING_ICON_COLOR)
			col.trailing = color(tok.VIBRANT_MENU_ITEM_PRESSED_TRAILING_ICON_COLOR)
		case c.focused:
			col.label = color(tok.VIBRANT_MENU_ITEM_FOCUSED_LABEL_TEXT_COLOR)
			col.leading = color(tok.VIBRANT_MENU_ITEM_FOCUSED_LEADING_ICON_COLOR)
			col.trailing = color(tok.VIBRANT_MENU_ITEM_FOCUSED_TRAILING_ICON_COLOR)
		case c.hovered:
			col.label = color(tok.VIBRANT_MENU_ITEM_HOVERED_LABEL_TEXT_COLOR)
			col.leading = color(tok.VIBRANT_MENU_ITEM_HOVERED_LEADING_ICON_COLOR)
			col.trailing = color(tok.VIBRANT_MENU_ITEM_HOVERED_TRAILING_ICON_COLOR)
		}
	}
	return
}

// menu_container_color is the popup (or group) surface for style.
@(private)
menu_container_color :: proc(style: Menu_Style) -> ops.Color {
	switch style {
	case .Legacy:
		return color(tok.MENU_CONTAINER_COLOR)
	case .Standard:
		return color(tok.STANDARD_MENU_CONTAINER_COLOR)
	case .Vibrant:
		return color(tok.VIBRANT_MENU_CONTAINER_COLOR)
	}
	return {}
}

// Menu_Row is one laid-out menu row: an item, a group label, or (legacy
// and flat) the divider after an item.
@(private)
Menu_Row :: struct {
	item:          int,
	y, h:          f32,
	group:         int,
	first, last:   bool, // first or last item of its group
	divider_after: bool,
}

// menu shows items while open^, below its origin by offset (usually the
// anchor's height). A click on an item returns its index and closes the
// menu; while modal, a press anywhere outside closes it too (and reaches
// nothing else). Returns -1 otherwise. The popup scales from 0.8 and
// fades in on the fast-spatial and fast-effects springs as it opens, and
// back as it closes (menu.json states), taking no input once closed.
//
// Legacy is the flat dropdown: comp.menu's surface-container at 3dp,
// corner 4, 48dp label-large items, 112-280dp wide. Standard and Vibrant
// are the Expressive menus: body-large 44dp items with 20dp icons, 16dp
// corners, tertiary selection whose shape morphs (fast-spatial) to the
// selected corner. grouped splits the items into rounded groups at each
// divider, 2dp apart, the outer groups taking the large corner on their
// outside edge and the small one inside (MenuDefaults.kt:104-127); items
// take the medium corner on their group's outer edge (comp.segmented-menu).
//
// inline lays the menu out in place, taking its size in the enclosing
// container, instead of as an overlay: for a menu pinned open as a
// specimen, which must not draw over popups opened near it.
//
// Placement is ui.popup_open's: the menu opens offset below its origin,
// flips above the origin when below would leave the window, and shifts
// sideways to stay inside it; it grows from the corner nearest the
// anchor. Not done, for want of jm:ui support: keyboard travel between items — jm:ui moves focus only by
// pointer press, so arrow keys cannot. A focused item still takes
// Enter/Space, and Escape on it closes the menu. comp.segmented-menu's
// horizontal icon-only row has no Compose consumer and is not built.
menu :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	items: []Menu_Item,
	offset := ops.Point{0, 40},
	modal := true,
	style := Menu_Style.Legacy,
	grouped := false,
	inline := false,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	// No widget slot, unless inline: a menu takes no space where it is called. Its
	// springs live in the widget state of its own id, read every frame so
	// they outlast a close and play it out.
	menu_id := ui.claim_id(gtx, key, loc)
	mc := Control {
		st = ui.widget_state(gtx, menu_id),
	}
	shown := animate(gtx, mc, 0, open^ ? 1 : 0, .Fast_Spatial)
	alpha := animate(gtx, mc, 1, open^ ? 1 : 0, .Fast_Effects)
	if !open^ && alpha <= 0.01 {
		return -1
	}
	live := open^
	expressive := style != .Legacy
	groups := grouped && expressive

	// Layout: every row's position, and the popup's width.
	rows := make([]Menu_Row, len(items), gtx.allocator)
	w: f32
	// An Expressive menu is one group unless grouped: 2dp above and below
	// each group; a legacy one has 8dp above and below the list.
	y := expressive ? f32(0) : MENU_PAD_Y
	group := 0
	for it, i in items {
		iw := menu_item_width(gtx, it, style)
		w = max(w, iw)
		if expressive && (i == 0 || (groups && items[i - 1].divider)) {
			y += MENU_GROUP_PAD_Y
		}
		h := menu_item_height(it, style)
		rows[i] = {
			item  = i,
			y     = y,
			h     = h,
			group = group,
			first = i == 0 || (groups && items[i - 1].divider) || items[i - 1].heading,
			last  = i == len(items) - 1 || (groups && it.divider) || items[i + 1].heading,
		}
		y += h
		if it.divider && i < len(items) - 1 {
			if groups {
				y += MENU_GROUP_PAD_Y + tok.SEGMENTED_MENU_SEGMENTED_GAP
				group += 1
			} else {
				rows[i].divider_after = true
				y += 2 * MENU_DIVIDER_PAD.y + tok.DIVIDER_THICKNESS
			}
		}
	}
	h := y + (expressive ? MENU_GROUP_PAD_Y : MENU_PAD_Y)
	if expressive {
		w += 2 * tok.SEGMENTED_MENU_GROUP_PADDING
	} else {
		w = clamp(w, MENU_MIN_WIDTH, MENU_MAX_WIDTH)
	}

	// Input first, so an item chosen this frame can close the menu before
	// any input area is laid down: a closed menu must catch nothing.
	chosen := -1
	scrim_id := ui.id_mix(menu_id, 0xffff)
	if live && modal {
		for e in ui.events(gtx, scrim_id) {
			if e.kind == .Press {
				open^ = false
			}
		}
	}
	ctrl := make([]Control, len(items), gtx.allocator)
	for it, i in items {
		st := it.state
		switch {
		case it.heading:
			st = .Enabled
		case it.disabled:
			st = .Disabled
		case !live && st == .Live:
			st = .Enabled
		}
		r := ops.Rect{0, rows[i].y, w, rows[i].h}
		ctrl[i] = control(gtx, ui.id_mix(menu_id, u64(i)), r, st)
		if ctrl[i].clicked {
			chosen = i
			open^ = false
		}
		if ctrl[i].st != nil && ctrl[i].focused {
			for e in ui.events(gtx, ui.id_mix(menu_id, u64(i))) {
				if e.kind == .Key && e.key == .Escape {
					open^ = false
				}
			}
		}
	}
	live = open^

	if inline {
		p := ui.widget_open(gtx, u64(ui.id_mix(menu_id, 1)), loc)
		defer ui.widget_close(gtx, &p, {size = ui.constrain(gtx.constraints, {w, h})})
		menu_paint(gtx, items, rows, ctrl, menu_id, scrim_id, w, h, group, shown, alpha, live, modal, style, groups, .Below)
	} else {
		// The anchor runs from the menu's origin down to offset, as wide as
		// the menu, so the menu opens at offset below it, or flips above
		// the origin when below would leave the window (ui.popup_open). It
		// must have area: placement leaves a popup whose anchor is off
		// screen where it asked to be, and a zero-width one never shows.
		anchor := ops.Rect{offset.x, min(offset.y, 0), w, abs(offset.y)}
		o := ui.popup_open(gtx, anchor, menu_id)
		side := ui.placed_side(gtx, menu_id, .Below)
		menu_paint(gtx, items, rows, ctrl, menu_id, scrim_id, w, h, group, shown, alpha, live, modal, style, groups, side)
		ui.popup_close(&o, {w, h})
	}
	return chosen
}

// menu_paint draws menu's popup at the origin: the scrim while live and
// modal, the containers, then the items.
@(private = "file")
menu_paint :: proc(
	gtx: ^ui.Ctx,
	items: []Menu_Item,
	rows: []Menu_Row,
	ctrl: []Control,
	menu_id, scrim_id: ops.Area_Id,
	w, h: f32,
	group: int,
	shown, alpha: f32,
	live, modal: bool,
	style: Menu_Style,
	groups: bool,
	side: ops.Side,
) {
	expressive := style != .Legacy
	// Grow from the start corner nearest the anchor: the top when the menu
	// opened below it, the bottom when placement flipped it above.
	k := MENU_CLOSED_SCALE + (1 - MENU_CLOSED_SCALE) * shown
	pivot := side == .Above ? ops.Point{0, h} : ops.Point{}
	ops.transform_push(gtx.scene, scale_about(pivot, k))
	defer ops.transform_pop(gtx.scene)
	if live && modal {
		// Scrim: an invisible catch-all under the menu; a press on it closes.
		ops.input_area(gtx.scene, scrim_id, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	}

	// Containers: one popup, or one surface per group.
	fill := menu_container_color(style)
	if groups {
		for g in 0 ..= group {
			top, bottom := f32(-1), f32(0)
			for r in rows {
				if r.group == g {
					if top < 0 {
						top = r.y - MENU_GROUP_PAD_Y
					}
					bottom = r.y + r.h + MENU_GROUP_PAD_Y
				}
			}
			gr := ops.Rect{0, top, w, max(bottom - top, MENU_GROUP_MIN_H)}
			gk := menu_group_corners(g, group + 1, gr)
			paint_elevation_dp(gtx, {gr, gk.tl}, tok.SEGMENTED_MENU_CONTAINER_ELEVATION * alpha)
			ops.fill(gtx.scene, rounded(gtx, gr, gk), fade(fill, alpha))
			if live {
				ops.input_area(gtx.scene, ui.id_mix(menu_id, 0xfff0 + u64(g)), rounded(gtx, gr, gk), {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
			}
		}
	} else {
		sh := expressive ? tok.SEGMENTED_MENU_CONTAINER_SHAPE : tok.MENU_CONTAINER_SHAPE
		elev := expressive ? tok.SEGMENTED_MENU_CONTAINER_ELEVATION : tok.MENU_CONTAINER_ELEVATION
		area := ops.Rect{0, 0, w, h}
		rr := ops.Round_Rect{area, corners(sh, area).tl}
		paint_elevation_dp(gtx, rr, elev * alpha)
		ops.fill(gtx.scene, rr, fade(fill, alpha))
		// Block presses on the menu's own padding from reaching the scrim.
		if live {
			ops.input_area(gtx.scene, ui.id_mix(menu_id, 0xfffe), rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		}
	}

	for it, i in items {
		row := rows[i]
		c := ctrl[i]
		id := ui.id_mix(menu_id, u64(i))
		if it.heading {
			t := shape_text(gtx, it.label, .Title_Small)
			draw_text(gtx, t, {tok.SEGMENTED_MENU_ITEM_LEADING_SPACE, row.y + (row.h - t.height) / 2}, fade(color(.On_Surface_Variant), alpha))
			continue
		}
		paint_menu_item(gtx, it, row, w, style, c, alpha)
		if live {
			listen(gtx, c, id, ops.Rect{0, row.y, w, row.h})
		}
		ops.tag(gtx.scene, id, ui.frame_string(gtx, it.label))
		if row.divider_after {
			ops.fill(
				gtx.scene,
				ops.Rect{MENU_DIVIDER_PAD.x, row.y + row.h + MENU_DIVIDER_PAD.y, w - 2 * MENU_DIVIDER_PAD.x, tok.DIVIDER_THICKNESS},
				fade(color(tok.DIVIDER_COLOR), alpha),
			)
		}
	}
}

// menu_group_corners is group g of n's shape: large on the menu's outer
// edge, small between groups (MenuDefaults.kt:104-127); a lone group is
// the whole container's shape.
@(private)
menu_group_corners :: proc(g, n: int, r: ops.Rect) -> Corners {
	if n == 1 {
		return corners(tok.SEGMENTED_MENU_CONTAINER_SHAPE, r)
	}
	large := tok.SYS_SHAPE_CORNER_LARGE.radii[0]
	small := tok.SYS_SHAPE_CORNER_SMALL.radii[0]
	switch g {
	case 0:
		return {large, large, small, small}
	case n - 1:
		return {small, small, large, large}
	}
	return corners(tok.SEGMENTED_MENU_GROUP_SHAPE, r)
}

// menu_item_height is an item's row height for style.
@(private)
menu_item_height :: proc(it: Menu_Item, style: Menu_Style) -> f32 {
	if style == .Legacy {
		return MENU_ITEM_HEIGHT
	}
	if it.heading {
		return MENU_GROUP_MIN_H
	}
	text := tok.SEGMENTED_MENU_ITEM_LABEL_TEXT_FONT.line_height
	if it.supporting != "" {
		text += tok.SEGMENTED_MENU_ITEM_SUPPORTING_TEXT_FONT.line_height
	}
	return max(tok.SEGMENTED_MENU_ITEM, text + tok.SEGMENTED_MENU_ITEM_TOP_SPACE + tok.SEGMENTED_MENU_ITEM_BOTTOM_SPACE)
}

// Menu_Metrics are an item's horizontal slots for style.
@(private)
Menu_Metrics :: struct {
	lead, trail, gap, icon: f32,
	label, supporting, trailing: tok.Type_Style,
}

@(private)
menu_metrics :: proc(style: Menu_Style) -> Menu_Metrics {
	if style == .Legacy {
		return {MENU_PAD_X, MENU_PAD_X, MENU_PAD_X, 24, TYPE_STYLES[.Label_Large], TYPE_STYLES[.Body_Small], TYPE_STYLES[.Label_Large]}
	}
	return {
		tok.SEGMENTED_MENU_ITEM_LEADING_SPACE,
		tok.SEGMENTED_MENU_ITEM_TRAILING_SPACE,
		tok.SEGMENTED_MENU_ITEM_BETWEEN_SPACE,
		tok.SEGMENTED_MENU_ITEM_LEADING_ICON_SIZE,
		tok.SEGMENTED_MENU_ITEM_LABEL_TEXT_FONT,
		tok.SEGMENTED_MENU_ITEM_SUPPORTING_TEXT_FONT,
		tok.SEGMENTED_MENU_ITEM_TRAILING_SUPPORTING_TEXT_FONT,
	}
}

// menu_item_width is an item's natural width for style.
@(private)
menu_item_width :: proc(gtx: ^ui.Ctx, it: Menu_Item, style: Menu_Style) -> f32 {
	m := menu_metrics(style)
	if it.heading {
		return m.lead + shape_text(gtx, it.label, .Title_Small).width + m.trail
	}
	w := m.lead + shape_style(gtx, it.label, m.label).width + m.trail
	if it.supporting != "" {
		w = max(w, m.lead + shape_style(gtx, it.supporting, m.supporting).width + m.trail)
	}
	if it.leading != .None || it.selected_icon != .None {
		w += m.icon + m.gap
	}
	if it.trailing != "" {
		w += 2 * m.gap + shape_style(gtx, it.trailing, m.trailing).width
	}
	if it.trailing_icon != .None || it.submenu {
		w += m.gap + m.icon
	}
	return w
}

// paint_menu_item draws one item's container, state layer and slots.
@(private)
paint_menu_item :: proc(gtx: ^ui.Ctx, it: Menu_Item, row: Menu_Row, w: f32, style: Menu_Style, c: Control, alpha: f32) {
	m := menu_metrics(style)
	col := menu_colors(style, c, it.selected)
	inset: f32 = style == .Legacy ? 0 : tok.SEGMENTED_MENU_GROUP_PADDING
	r := ops.Rect{inset, row.y, w - 2 * inset, row.h}
	k: Corners
	if style != .Legacy {
		// Outer corners of a group's first and last items take the medium
		// corner, the seams the extra-small one; selection morphs every
		// corner to item-selected-shape on the fast-spatial spring.
		base := corners(tok.SEGMENTED_MENU_ITEM_SHAPE, r)
		if row.first {
			base.tl, base.tr = tok.SEGMENTED_MENU_ITEM_FIRST_CHILD_SHAPE.radii[0], tok.SEGMENTED_MENU_ITEM_FIRST_CHILD_SHAPE.radii[1]
			base.bl, base.br = tok.SEGMENTED_MENU_ITEM_FIRST_CHILD_INNER_CORNER_CORNER_SIZE.radii[3], tok.SEGMENTED_MENU_ITEM_FIRST_CHILD_INNER_CORNER_CORNER_SIZE.radii[2]
		}
		if row.last {
			base.bl, base.br = tok.SEGMENTED_MENU_ITEM_LAST_CHILD_SHAPE.radii[3], tok.SEGMENTED_MENU_ITEM_LAST_CHILD_SHAPE.radii[2]
			if !row.first {
				base.tl, base.tr = tok.SEGMENTED_MENU_ITEM_LAST_CHILD_INNER_CORNER_CORNER_SIZE.radii[0], tok.SEGMENTED_MENU_ITEM_LAST_CHILD_INNER_CORNER_CORNER_SIZE.radii[1]
			}
		}
		sel := animate(gtx, c, 0, it.selected ? 1 : 0, .Fast_Spatial)
		k = lerp_corners(base, corners(tok.SEGMENTED_MENU_ITEM_SELECTED_SHAPE, r), sel)
	}
	shape := rounded(gtx, r, k)
	if ui.painted(col.container) {
		ops.fill(gtx.scene, shape, fade(col.container, alpha))
	}
	paint_state_layer(gtx, c, shape, col.label)
	x := r.x + m.lead
	g := it.selected && it.selected_icon != .None ? it.selected_icon : it.leading
	if g != .None {
		icon(gtx, g, {x, row.y + (row.h - m.icon) / 2}, m.icon, fade(col.leading, alpha))
		x += m.icon + m.gap
	} else if it.selected_icon != .None {
		x += m.icon + m.gap // keep labels aligned with the selected rows'
	}
	right := r.x + r.w - m.trail
	if it.trailing_icon != .None || it.submenu {
		right -= m.icon
		ti := it.submenu ? Icon.Chevron_Right : it.trailing_icon
		icon(gtx, ti, {right, row.y + (row.h - m.icon) / 2}, m.icon, fade(col.trailing, alpha))
		right -= m.gap
	}
	if it.trailing != "" {
		tt := shape_style(gtx, it.trailing, m.trailing)
		draw_text(gtx, tt, {right - tt.width, row.y + (row.h - tt.height) / 2}, fade(col.trailing_text, alpha))
	}
	t := shape_style(gtx, it.label, m.label)
	if it.supporting == "" {
		draw_text(gtx, t, {x, row.y + (row.h - t.height) / 2}, fade(col.label, alpha))
	} else {
		st := shape_style(gtx, it.supporting, m.supporting)
		ty := row.y + (row.h - t.height - st.height) / 2
		draw_text(gtx, t, {x, ty}, fade(col.label, alpha))
		draw_text(gtx, st, {x, ty + t.height}, fade(col.supporting, alpha))
	}
	paint_focus_ring_corners(gtx, c, r, k, inward = true)
}

// Tooltip_Caret is the side a tooltip's caret points to: toward its
// anchor. The caret is 16×8dp, joined to the container (Tooltip.kt:532).
Tooltip_Caret :: enum u8 {
	None,
	Up, // the anchor is above
	Down, // the anchor is below
	Left,
	Right,
}

// CARET_W and CARET_H are the caret's base and height (tooltip.json layout).
@(private)
CARET_W :: f32(16)
@(private)
CARET_H :: f32(8)
// Plain tooltip metrics: 200dp max width, 8×4dp padding, a 40×24dp floor
// (tooltip.json layout, Tooltip.kt:535,1450-1459).
@(private)
PLAIN_TIP_MAX_W :: f32(200)
@(private)
PLAIN_TIP_PAD :: [2]f32{8, 4}
@(private)
TIP_MIN :: ops.Size{40, 24}
// TOOLTIP_GAP is the space between a tooltip and its anchor (Tooltip.kt:1449).
@(private)
TOOLTIP_GAP :: f32(4)

// plain_tooltip is M3's plain tooltip as a widget: comp.plain-tooltip's
// body-small inverse-on-surface text on inverse-surface, corner 4, 8×4dp
// padding, wrapping at 200dp, never under 40×24dp; caret adds the 16×8dp
// pointer on that side. See tooltip for one that follows hover over any
// control, and icon_button's own tooltip.
plain_tooltip :: proc(gtx: ^ui.Ctx, label: string, caret := Tooltip_Caret.None, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	size := paint_plain_tooltip(gtx, {}, label, caret)
	ui.widget_close(gtx, &p, {size = size})
}

// paint_plain_tooltip draws a plain tooltip with its top-left (caret
// included) at at and returns its size. alpha fades it and scale grows it
// about its centre, for the show animation.
paint_plain_tooltip :: proc(gtx: ^ui.Ctx, at: ops.Point, label: string, caret := Tooltip_Caret.None, alpha: f32 = 1, scale: f32 = 1) -> ops.Size {
	lines := wrap_lines(gtx, label, tok.PLAIN_TOOLTIP_SUPPORTING_TEXT_FONT, PLAIN_TIP_MAX_W - 2 * PLAIN_TIP_PAD.x)
	tw, th := lines_size(lines)
	box := ops.Size{max(tw + 2 * PLAIN_TIP_PAD.x, TIP_MIN.x), max(th + 2 * PLAIN_TIP_PAD.y, TIP_MIN.y)}
	r, size := caret_layout(at, box, caret)
	ctr := ops.Point{at.x + size.x / 2, at.y + size.y / 2}
	ops.transform_push(gtx.scene, scale_about(ctr, scale))
	fill := fade(color(tok.PLAIN_TOOLTIP_CONTAINER_COLOR), alpha)
	ops.fill(gtx.scene, rounded(gtx, r, corners(tok.PLAIN_TOOLTIP_CONTAINER_SHAPE, r)), fill)
	paint_caret(gtx, r, caret, fill)
	y := r.y + (r.h - th) / 2
	for t in lines {
		// Lines are start-aligned; the block centres in a box at its floor.
		draw_text(gtx, t, {r.x + (r.w - tw) / 2, y}, fade(color(tok.PLAIN_TOOLTIP_SUPPORTING_TEXT_COLOR), alpha))
		y += t.height
	}
	ops.transform_pop(gtx.scene)
	return size
}

// caret_layout places a box-sized container inside the whole tooltip at
// at, leaving room on the caret's side; size is the whole.
@(private)
caret_layout :: proc(at: ops.Point, box: ops.Size, caret: Tooltip_Caret) -> (r: ops.Rect, size: ops.Size) {
	r = {at.x, at.y, box.x, box.y}
	size = box
	switch caret {
	case .None:
	case .Up:
		r.y += CARET_H
		size.y += CARET_H
	case .Down:
		size.y += CARET_H
	case .Left:
		r.x += CARET_H
		size.x += CARET_H
	case .Right:
		size.x += CARET_H
	}
	return
}

// paint_caret fills the caret on r's caret side, centred on that edge.
@(private)
paint_caret :: proc(gtx: ^ui.Ctx, r: ops.Rect, caret: Tooltip_Caret, fill: ops.Color) {
	cx, cy := r.x + r.w / 2, r.y + r.h / 2
	hw := CARET_W / 2
	pts: [3]ops.Point
	switch caret {
	case .None:
		return
	case .Up:
		pts = {{cx - hw, r.y}, {cx + hw, r.y}, {cx, r.y - CARET_H}}
	case .Down:
		pts = {{cx - hw, r.y + r.h}, {cx + hw, r.y + r.h}, {cx, r.y + r.h + CARET_H}}
	case .Left:
		pts = {{r.x, cy - hw}, {r.x, cy + hw}, {r.x - CARET_H, cy}}
	case .Right:
		pts = {{r.x + r.w, cy - hw}, {r.x + r.w, cy + hw}, {r.x + r.w + CARET_H, cy}}
	}
	ops.fill(gtx.scene, ui.polygon(gtx, pts[:]), fill)
}

// TOOLTIP_DELAY is how long hover must rest before a tooltip shows: none,
// since a mouse shows it at once (tooltip.json behaviour, Tooltip.kt:220-283).
TOOLTIP_DELAY :: f32(0)

// TOOLTIP_DISMISS is when a non-persistent tooltip hides itself, however
// long hover stays (Tooltip.kt:465).
TOOLTIP_DISMISS :: f32(1.5)

// hover_tooltip shows label in an overlay centred TOOLTIP_GAP under a
// box-sized anchor while hovered, fading in on fast-effects and growing
// from 0.8 on fast-spatial, and hides it after TOOLTIP_DISMISS. hover_t
// is the caller's timer (seconds hovered); it is advanced here and reset
// when not hovered. It hides at once on leave: a timer alone cannot play
// the fade out.
//
// It is placed by ui.popup_open under the anchor, flipping above it or
// shifting sideways to stay in the window; key names it.
@(private)
hover_tooltip :: proc(gtx: ^ui.Ctx, hovered: bool, hover_t: ^f32, label: string, box: ops.Size, key: ops.Area_Id) {
	if !hovered || label == "" {
		hover_t^ = 0
		return
	}
	hover_t^ += gtx.dt
	t := hover_t^ - TOOLTIP_DELAY
	if t < 0 {
		ui.request_frame(gtx, -t)
		return
	}
	if t >= TOOLTIP_DISMISS {
		return
	}
	a := spring_progress(.Fast_Effects, t)
	k := MENU_CLOSED_SCALE + (1 - MENU_CLOSED_SCALE) * spring_progress(.Fast_Spatial, t)
	if a < 1 || k < 1 {
		ui.request_frame(gtx)
	} else {
		ui.request_frame(gtx, TOOLTIP_DISMISS - t)
	}
	o := ui.popup_open(gtx, {0, 0, box.x, box.y}, key, .Below, .Center, TOOLTIP_GAP)
	size := paint_plain_tooltip(gtx, {}, label, .None, a, k)
	ui.popup_close(&o, size)
}

// tooltip_open wraps whatever is laid out inside it, any control or
// group of them, with a plain tooltip that follows hover as icon_button's
// does: shown under the body, flipping or shifting to stay in the window,
// hidden on leave or after TOOLTIP_DISMISS. The wrapper hears the
// pointer through an observer area (ops.Input_Area.observes), so the
// control inside keeps its own hover, presses and cursor. It paints
// nothing else and adds nothing to the body's size.
tooltip_open :: proc(gtx: ^ui.Ctx, label: string, key: u64 = 0, loc := #caller_location) -> ui.Box {
	tp := new(Tooltip_Anchor, gtx.allocator)
	tp.label = label
	return ui.box_open(gtx, {paint = paint_tooltip_anchor, user = tp}, key, loc)
}

// tooltip is tooltip_open as a guard: `if m3.tooltip(gtx, "Why") { … }`
// closes itself at the end of the if.
@(deferred_in = tooltip_guard_close)
tooltip :: proc(gtx: ^ui.Ctx, label: string, key: u64 = 0, loc := #caller_location) -> bool {
	tooltip_open(gtx, label, key, loc)
	return true
}

@(private = "file")
tooltip_guard_close :: proc(gtx: ^ui.Ctx, label: string, key: u64, loc: runtime.Source_Code_Location) {
	ui.innermost_close(gtx, .Box)
}

@(private = "file")
Tooltip_Anchor :: struct {
	label: string,
}

// Tooltip_Hover is a wrapping tooltip's state between frames: whether
// the pointer is over its body, and for how long.
@(private = "file")
Tooltip_Hover :: struct {
	over:    bool,
	seconds: f32,
}

// paint_tooltip_anchor runs once the body's size is known: it lays the
// observer over the body and shows the tooltip while the pointer is on it.
@(private = "file")
paint_tooltip_anchor :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	tp := (^Tooltip_Anchor)(user)
	h := ui.widget_data(gtx, id, Tooltip_Hover)
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Enter:
			h.over = true
		case .Leave:
			h.over = false
		}
	}
	ops.observer_area(gtx.scene, id, ops.Rect{0, 0, size.x, size.y})
	hover_tooltip(gtx, h.over, &h.seconds, tp.label, size, ui.id_mix(id, 0x746f6f6c))
}

// Rich tooltip metrics (tooltip.json layout, Tooltip.kt:538,1460-1471):
// 320dp max width, 16dp side padding, the subhead's first baseline 28dp
// from the top, the body's first baseline 24dp under the subhead's, 16dp
// under the body when there is no action, and an action row at least 36dp
// tall with 8dp under it.
@(private)
RICH_TIP_MAX_W :: f32(320)
@(private)
RICH_TIP_PAD_X :: f32(16)
@(private)
RICH_TIP_SUBHEAD_BASELINE :: f32(28)
@(private)
RICH_TIP_BODY_BASELINE :: f32(24)
@(private)
RICH_TIP_BODY_BOTTOM :: f32(16)
@(private)
RICH_TIP_ACTION_MIN_H :: f32(36)
@(private)
RICH_TIP_ACTION_BOTTOM :: f32(8)
// RICH_TIP_TOP is the body's top padding when there is no subhead: the
// kit gives none, so this is the 12dp of M3's rich tooltip guidance.
@(private)
RICH_TIP_TOP :: f32(12)

@(private)
Rich_Tip_Paint :: struct {
	caret: Tooltip_Caret,
}

// rich_tooltip is M3's rich tooltip as a widget: comp.rich-tooltip's
// optional title-small subhead, body-medium supporting text wrapping at
// 320dp, and an optional text action in its own row, on surface-container
// at 3dp, corner 12, with an optional caret. Returns true when its action
// was clicked. The action is an ordinary text button, whose own tokens
// match the tooltip's action tokens.
rich_tooltip :: proc(
	gtx: ^ui.Ctx,
	subhead: string,
	supporting: string,
	action := "",
	caret := Tooltip_Caret.None,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	clicked := false
	pad := ui.Padding{RICH_TIP_PAD_X, 0, RICH_TIP_PAD_X, 0}
	switch caret {
	case .None:
	case .Up:
		pad.top += CARET_H
	case .Down:
		pad.bottom += CARET_H
	case .Left:
		pad.left += CARET_H
	case .Right:
		pad.right += CARET_H
	}
	rp := new(Rich_Tip_Paint, gtx.allocator)
	rp.caret = caret
	b := ui.box_open(gtx, {padding = pad, paint = paint_rich_tooltip, user = rp}, key, loc)
	defer ui.close(&b)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	body := layout_style(gtx, supporting, tok.RICH_TOOLTIP_SUPPORTING_TEXT_FONT, RICH_TIP_MAX_W - 2 * RICH_TIP_PAD_X)
	if subhead != "" {
		t := shape_style(gtx, subhead, tok.RICH_TOOLTIP_SUBHEAD_FONT)
		ui.spacer(gtx, RICH_TIP_SUBHEAD_BASELINE - baseline_of(t))
		label_widget(gtx, t, color(tok.RICH_TOOLTIP_SUBHEAD_COLOR))
		ui.spacer(gtx, RICH_TIP_BODY_BASELINE - (t.height - baseline_of(t)) - body.lines[0].baseline)
	} else {
		ui.spacer(gtx, RICH_TIP_TOP)
	}
	paragraph_widget(gtx, body, color(tok.RICH_TOOLTIP_SUPPORTING_TEXT_COLOR))
	if action != "" {
		// The action row: at least 36dp, 8dp under it; the button's own
		// 12dp label padding sits it in from the text's edge, as in Compose.
		// A text button is 40dp, already past the row's 36dp minimum.
		clicked = button(gtx, action, .Text)
		ui.spacer(gtx, RICH_TIP_ACTION_BOTTOM)
	} else {
		ui.spacer(gtx, RICH_TIP_BODY_BOTTOM)
	}
	return clicked
}

@(private)
paint_rich_tooltip :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	rp := (^Rich_Tip_Paint)(user)
	box := size
	if rp.caret == .Up || rp.caret == .Down {
		box.y -= CARET_H
	} else if rp.caret != .None {
		box.x -= CARET_H
	}
	r, _ := caret_layout({}, box, rp.caret)
	rr := ops.Round_Rect{r, corners(tok.RICH_TOOLTIP_CONTAINER_SHAPE, r).tl}
	fill := color(tok.RICH_TOOLTIP_CONTAINER_COLOR)
	paint_elevation_dp(gtx, rr, tok.RICH_TOOLTIP_CONTAINER_ELEVATION)
	ops.fill(gtx.scene, rr, fill)
	paint_caret(gtx, r, rp.caret, fill)
}

// label_widget places a shaped Text as a widget of its own size.
@(private)
label_widget :: proc(gtx: ^ui.Ctx, t: Text, color: ops.Color, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	draw_text(gtx, t, {}, color)
	ui.widget_close(gtx, &p, {ops.Size{t.width, t.height}, baseline_of(t)})
}

// paragraph_widget places laid-out text as one selectable widget at least
// width wide, each line start-aligned or, with centre, centred in that
// width.
@(private)
paragraph_widget :: proc(gtx: ^ui.Ctx, para: ui.Paragraph, color: ops.Color, width: f32 = 0, centre := false, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	para := para
	w := max(para.width, width)
	if centre {
		for &ln in para.lines {
			ln.x = (w - ln.width) / 2
		}
	}
	selectable_paragraph(gtx, p.id, para, {}, color, {0, 0, w, para.height})
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, para.text))
	ui.widget_close(gtx, &p, {ops.Size{w, para.height}, para.lines[0].baseline})
}

// DIALOG_* are the dialog's hard-coded metrics (dialog.json layout,
// AlertDialog.kt): 280-560dp wide, 24dp padding, 16dp under the icon and
// the headline, 24dp under the supporting text, 8dp between actions.
@(private)
DIALOG_MIN_W :: f32(280)
@(private)
DIALOG_MAX_W :: f32(560)
@(private)
DIALOG_PAD :: f32(24)
@(private)
DIALOG_ICON_GAP :: f32(16)
@(private)
DIALOG_HEADLINE_GAP :: f32(16)
@(private)
DIALOG_TEXT_GAP :: f32(24)
@(private)
DIALOG_ACTION_GAP :: f32(8)
// DIALOG_SCRIM is the scrim's opacity: the kit has none (Compose leaves
// it to the platform window); 0.32 is Android's dialog dim.
@(private)
DIALOG_SCRIM :: f32(0.32)

@(private)
Dialog_Paint :: struct {
	open: ^bool,
}

// dialog shows M3's basic dialog while open^, centred over the window
// behind a scrim: comp.dialog's surface-container-high, corner 28, 6dp
// elevation, an optional 24dp secondary icon that centres the headline
// under it, a headline-small headline and body-medium supporting text,
// then the actions end-aligned 8dp apart — stacked, confirm first, when
// they do not fit on one row (AlertDialog.kt:381-417). actions run
// dismiss to confirm: the last is the confirming one. window is the
// window's size (the root constraints). A click on an action closes it
// and returns the action's index; a click on the scrim, or Escape once the
// dialog has focus, closes it and returns -1.
//
// comp.dialog.container-elevation is not wired to a shadow in Compose
// (dialog.json notes); this paints it. Long supporting text is not
// scrolled, as in Compose, and focus is not trapped: jm:ui has no Tab
// traversal to trap.
dialog :: proc(
	gtx: ^ui.Ctx,
	open: ^bool,
	window: ops.Size,
	headline: string,
	supporting: string,
	actions: []string,
	glyph := Icon.None,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	if !open^ {
		return -1
	}
	chosen := -1
	id := ui.claim_id(gtx, key, loc)
	o := ui.overlay_open(gtx, cs = ui.loose(window), root = true)
	defer ui.close(&o)
	defer o.discard = !open^ // closed this frame: draw nothing, catch nothing
	for e in ui.events(gtx, id) {
		if e.kind == .Press {
			open^ = false
		}
	}
	ops.fill(gtx.scene, ops.Rect{0, 0, window.x, window.y}, ops.with_alpha(color(.Scrim), DIALOG_SCRIM))
	ops.input_area(gtx.scene, id, ops.Rect{0, 0, window.x, window.y}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})

	// Width: the content's, within 280-560 and the window.
	max_w := clamp(window.x - 2 * DIALOG_PAD, DIALOG_MIN_W, DIALOG_MAX_W)
	inner := max_w - 2 * DIALOG_PAD
	head := layout_style(gtx, headline, tok.DIALOG_HEADLINE_FONT, inner)
	text := layout_style(gtx, supporting, tok.DIALOG_SUPPORTING_TEXT_FONT, inner)
	hw, sw := head.width, text.width
	aw := actions_width(gtx, actions)
	w := clamp(max(hw, sw, aw) + 2 * DIALOG_PAD, DIALOG_MIN_W, max_w)
	inner = w - 2 * DIALOG_PAD
	stacked := aw > inner

	c := ui.centered_open(gtx)
	defer ui.close(&c)
	dp := new(Dialog_Paint, gtx.allocator)
	dp.open = open
	d := ui.box_open(gtx, {padding = ui.pad_all(DIALOG_PAD), paint = paint_dialog, user = dp}, key = 1)
	defer ui.close(&d)
	col := ui.column_open(gtx, align = glyph != .None ? .Center : .Start)
	defer ui.close(&col)
	if glyph != .None {
		icon_widget(gtx, glyph, tok.DIALOG_ICON_SIZE, color(tok.DIALOG_ICON_COLOR))
		ui.spacer(gtx, DIALOG_ICON_GAP)
	}
	if headline != "" {
		paragraph_widget(gtx, head, color(tok.DIALOG_HEADLINE_COLOR), glyph != .None ? inner : 0, glyph != .None)
		ui.spacer(gtx, DIALOG_HEADLINE_GAP)
	}
	if supporting != "" {
		// Supporting text is start-aligned even under an icon.
		paragraph_widget(gtx, text, color(tok.DIALOG_SUPPORTING_TEXT_COLOR), inner)
		ui.spacer(gtx, DIALOG_TEXT_GAP)
	}
	if stacked {
		ac := ui.column_open(gtx, gap = DIALOG_ACTION_GAP)
		defer ui.close(&ac)
		for i := len(actions) - 1; i >= 0; i -= 1 {
			r := ui.row_open(gtx, key = u64(i))
			ui.spacer(gtx, max(inner - actions_width(gtx, actions[i:i + 1]), 0))
			if button(gtx, actions[i], .Text, key = u64(i)) {
				chosen = i
				open^ = false
			}
			ui.close(&r)
		}
	} else {
		r := ui.row_open(gtx, gap = DIALOG_ACTION_GAP)
		defer ui.close(&r)
		ui.spacer(gtx, max(inner - aw - DIALOG_ACTION_GAP, 0))
		for a, i in actions {
			if button(gtx, a, .Text, key = u64(i)) {
				chosen = i
				open^ = false
			}
		}
	}
	return chosen
}

@(private)
paint_dialog :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	dp := (^Dialog_Paint)(user)
	area := ops.Rect{0, 0, size.x, size.y}
	rr := ops.Round_Rect{area, corners(tok.DIALOG_CONTAINER_SHAPE, area).tl}
	for e in ui.events(gtx, id) {
		if e.kind == .Key && e.key == .Escape {
			dp.open^ = false
		}
	}
	paint_elevation_dp(gtx, rr, tok.DIALOG_CONTAINER_ELEVATION)
	ops.fill(gtx.scene, rr, color(tok.DIALOG_CONTAINER_COLOR))
	// The dialog swallows its own presses so they do not reach the scrim,
	// and takes focus on one so Escape reaches it.
	ops.input_area(gtx.scene, id, rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll, .Key})
}

// actions_width is a row of text-button actions' width.
@(private)
actions_width :: proc(gtx: ^ui.Ctx, actions: []string) -> f32 {
	w: f32
	for a, i in actions {
		w += shape_style(gtx, a, tok.DIALOG_ACTION_LABEL_TEXT_FONT).width + 24
		if i > 0 {
			w += DIALOG_ACTION_GAP
		}
	}
	return w
}

// icon_widget places a size-px icon as a widget.
icon_widget :: proc(gtx: ^ui.Ctx, g: Icon, size: f32, color: ops.Color, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	icon(gtx, g, {}, size, color)
	ui.widget_close(gtx, &p, {size = {size, size}})
}

// wrap_lines breaks s at spaces into shaped lines no wider than width —
// a word wider than width keeps a line to itself — on gtx.allocator.
@(private)
wrap_lines :: proc(gtx: ^ui.Ctx, s: string, st: tok.Type_Style, width: f32) -> []Text {
	out := make([dynamic]Text, gtx.allocator)
	start := 0
	for {
		end := -1
		fit: Text
		i := start
		for {
			j := strings.index_byte(s[i:], ' ')
			j = j < 0 ? len(s) : i + j
			t := shape_style(gtx, s[start:j], st)
			if t.width > width + 0.5 && end >= 0 { // 0.5: slack for a width measured from this same text
				break
			}
			end, fit = j, t
			if j == len(s) {
				break
			}
			i = j + 1
		}
		append(&out, fit)
		if end >= len(s) {
			break
		}
		start = end + 1
	}
	return out[:]
}

// lines_size is the widest line and the lines' total height.
@(private)
lines_size :: proc(lines: []Text) -> (w, h: f32) {
	for t in lines {
		w = max(w, t.width)
		h += t.height
	}
	return
}

// Snackbar_Duration is how long a snackbar with a timer stays up.
Snackbar_Duration :: enum u8 {
	Default, // Short without an action, Indefinite with one (SnackbarHost.kt:104-105)
	Short, // 4s
	Long, // 10s
	Indefinite, // until its action or close icon
}

// SNACKBAR_SHORT and SNACKBAR_LONG are the timed durations in seconds
// (SnackbarHost.kt:298-306).
SNACKBAR_SHORT :: f32(4)
SNACKBAR_LONG :: f32(10)

// Snackbar metrics (snackbar.json layout, Snackbar.kt:604-622): 600dp at
// most, 16dp text inset, 8dp on a button's side, 14dp above and below a
// one-line message, 8dp after the text when there is no close icon; with
// the action on its own row, the first baseline 30dp down, the button row
// 12dp under the last baseline and 2dp extra below it.
@(private)
SNACK_MAX_W :: f32(600)
@(private)
SNACK_PAD_X :: f32(16)
@(private)
SNACK_PAD_BUTTON :: f32(8)
@(private)
SNACK_PAD_Y :: f32(14)
@(private)
SNACK_TEXT_END :: f32(8)
@(private)
SNACK_FIRST_BASELINE :: f32(30)
@(private)
SNACK_BUTTON_OFFSET :: f32(12)
@(private)
SNACK_BUTTON_EXTRA :: f32(2)
// SNACK_BUTTON_H and SNACK_CLOSE are the action's and close icon's boxes:
// a text button and a 48dp icon-button touch target.
@(private)
SNACK_BUTTON_H :: f32(40)
@(private)
SNACK_CLOSE :: f32(48)

// snackbar is M3's snackbar as a widget: comp.snackbar's body-medium
// inverse-on-surface message on inverse-surface, corner 4, 6dp elevation,
// an optional inverse-primary text action and close icon. It is one line
// (48dp) when the message fits beside the action, else two (68dp, the
// message wrapping beside it); action_on_new_line puts the action on its
// own row, the only way Compose moves it (Snackbar.kt). width
// 0 sizes to content, never past 600dp. With timer, the snackbar ages by
// gtx.dt, fades and grows in on the fast springs as it appears, and
// reports closed once duration has passed. state forces the action's and
// close icon's look. Returns (action clicked, closed); the caller hides
// it on either. Queueing, one at a time, is the caller's.
snackbar :: proc(
	gtx: ^ui.Ctx,
	message: string,
	action := "",
	closable := false,
	width: f32 = 0,
	action_on_new_line := false,
	timer: ^f32 = nil,
	duration := Snackbar_Duration.Default,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (
	acted: bool,
	closed: bool,
) {
	p := ui.widget_open(gtx, key, loc)
	alpha, scale := f32(1), f32(1)
	if timer != nil {
		timer^ += gtx.dt
		d := duration
		if d == .Default {
			d = action == "" ? .Short : .Indefinite
		}
		limit := d == .Short ? SNACKBAR_SHORT : (d == .Long ? SNACKBAR_LONG : -1)
		if limit > 0 {
			if timer^ >= limit {
				closed = true
			} else {
				ui.request_frame(gtx, limit - timer^)
			}
		}
		alpha = spring_progress(.Fast_Effects, timer^)
		scale = MENU_CLOSED_SCALE + (1 - MENU_CLOSED_SCALE) * spring_progress(.Fast_Spatial, timer^)
		if alpha < 1 || scale < 1 {
			ui.request_frame(gtx)
		}
	}

	at := action != "" ? shape_style(gtx, action, tok.SNACKBAR_ACTION_LABEL_TEXT_FONT) : Text{}
	aw := action != "" ? at.width + 24 : 0
	end := closable ? SNACK_CLOSE : SNACK_TEXT_END // the close slot, or the text's extra end space
	one_line := shape_style(gtx, message, tok.SNACKBAR_SUPPORTING_TEXT_FONT)
	natural := SNACK_PAD_X + one_line.width + end + (action != "" ? aw + SNACK_PAD_BUTTON : SNACK_PAD_BUTTON)
	w := width > 0 ? width : natural
	w = min(w, SNACK_MAX_W, gtx.constraints.max.x)
	w = max(w, gtx.constraints.min.x)
	beside := action != "" && !action_on_new_line
	text_w := w - SNACK_PAD_X - end - SNACK_PAD_BUTTON - (beside ? aw : 0)
	msg := layout_style(gtx, message, tok.SNACKBAR_SUPPORTING_TEXT_FONT, text_w)
	th := msg.height
	two := len(msg.lines) > 1 || (action != "" && !beside)
	h: f32
	text_y: f32
	button_y: f32
	if action != "" && !beside {
		text_y = SNACK_FIRST_BASELINE - msg.lines[0].baseline
		button_y = text_y + msg.lines[len(msg.lines) - 1].baseline + SNACK_BUTTON_OFFSET
		h = button_y + SNACK_BUTTON_H + SNACK_BUTTON_EXTRA
	} else {
		h = max(two ? tok.SNACKBAR_TWO_LINES_CONTAINER_HEIGHT : tok.SNACKBAR_SINGLE_LINE_CONTAINER_HEIGHT, th + 2 * SNACK_PAD_Y)
		text_y = (h - th) / 2
		button_y = (h - SNACK_BUTTON_H) / 2
	}
	size := ops.Size{w, h}
	area := ops.Rect{0, 0, size.x, size.y}
	ops.transform_push(gtx.scene, scale_about({size.x / 2, size.y / 2}, scale))
	rr := ops.Round_Rect{area, corners(tok.SNACKBAR_CONTAINER_SHAPE, area).tl}
	paint_elevation_dp(gtx, rr, tok.SNACKBAR_CONTAINER_ELEVATION * alpha)
	ops.fill(gtx.scene, rr, fade(color(tok.SNACKBAR_CONTAINER_COLOR), alpha))
	// The message selectable over the snackbar, which it yields to.
	selectable_paragraph(gtx, ui.id_mix(p.id, 3), msg, {SNACK_PAD_X, text_y}, fade(color(tok.SNACKBAR_SUPPORTING_TEXT_COLOR), alpha), {SNACK_PAD_X, text_y, text_w, th})
	right := size.x - SNACK_PAD_BUTTON
	if closable {
		right -= SNACK_CLOSE
		cid := ui.id_mix(p.id, 2)
		r := ops.Rect{right, (beside || action == "" ? (h - SNACK_CLOSE) / 2 : 0), SNACK_CLOSE, SNACK_CLOSE}
		c := control(gtx, cid, r, state)
		ink := color(tok.SNACKBAR_ICON_COLOR)
		switch {
		case c.pressed:
			ink = color(tok.SNACKBAR_PRESSED_ICON_COLOR)
		case c.focused:
			ink = color(tok.SNACKBAR_FOCUS_ICON_COLOR)
		case c.hovered:
			ink = color(tok.SNACKBAR_HOVER_ICON_COLOR)
		}
		if c.disabled {
			ink = ops.with_alpha(ink, DISABLED_CONTENT_OPACITY)
		}
		ctr := ops.Point{r.x + r.w / 2, r.y + r.h / 2}
		half := tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT / 2
		ring := ui.circle(ctr, half)
		paint_state_layer(gtx, c, ring, ink)
		ICON :: tok.SNACKBAR_ICON_SIZE
		icon(gtx, .Close, {ctr.x - ICON / 2, ctr.y - ICON / 2}, ICON, fade(ink, alpha))
		paint_focus_ring(gtx, c, {{ctr.x - half, ctr.y - half, 2 * half, 2 * half}, half})
		listen(gtx, c, cid, r)
		ops.tag(gtx.scene, cid, "close snackbar")
		closed = closed || c.clicked
	}
	if action != "" {
		ax := beside ? right - aw : size.x - SNACK_PAD_BUTTON - aw
		aid := ui.id_mix(p.id, 1)
		r := ops.Rect{ax, button_y, aw, SNACK_BUTTON_H}
		c := control(gtx, aid, r, state)
		ink := color(tok.SNACKBAR_ACTION_LABEL_TEXT_COLOR)
		switch {
		case c.pressed:
			ink = color(tok.SNACKBAR_ACTION_PRESSED_LABEL_TEXT_COLOR)
		case c.focused:
			ink = color(tok.SNACKBAR_ACTION_FOCUS_LABEL_TEXT_COLOR)
		case c.hovered:
			ink = color(tok.SNACKBAR_ACTION_HOVER_LABEL_TEXT_COLOR)
		}
		if c.disabled {
			ink = ops.with_alpha(ink, DISABLED_CONTENT_OPACITY)
		}
		pill := ops.Round_Rect{r, r.h / 2}
		paint_state_layer(gtx, c, pill, ink)
		draw_text(gtx, at, {ax + 12, button_y + (SNACK_BUTTON_H - at.height) / 2}, fade(ink, alpha))
		paint_focus_ring(gtx, c, pill)
		listen(gtx, c, aid, r)
		ops.tag(gtx.scene, aid, ui.frame_string(gtx, action))
		acted = c.clicked
	}
	ops.transform_pop(gtx.scene)
	ui.widget_close(gtx, &p, {size = size})
	return
}
