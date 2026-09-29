package main

import "jm:ui"
import m3 "jm:ui/material"

// NAV_ITEMS are the rail and bar demos' destinations: a numeral badge, a
// dot badge, and two plain ones.
NAV_ITEMS := [?]m3.Nav_Item {
	{label = "Mail", icon = .Mail, active_icon = .Mail_Fill1, badge = "3"},
	{label = "Chat", icon = .Chat_Bubble, active_icon = .Chat_Bubble_Fill1, badge = " "},
	{label = "Rooms", icon = .Home, active_icon = .Home_Fill1},
	{label = "Meet", icon = .Photo, active_icon = .Photo_Fill1},
}

// DRAWER_ITEMS are the drawer demos' contents: two headed groups, more
// than fit, so the drawer scrolls.
DRAWER_ITEMS := [?]m3.Nav_Item {
	{label = "Mail", headline = true},
	{label = "Inbox", icon = .Inbox, active_icon = .Inbox_Fill1, badge = "24"},
	{label = "Outbox", icon = .Send, active_icon = .Send_Fill1},
	{label = "Favorites", icon = .Favorite, active_icon = .Favorite_Fill1},
	{label = "Trash", icon = .Delete, active_icon = .Delete_Fill1},
	{label = "Labels", headline = true},
	{label = "Family", icon = .Bookmark, active_icon = .Bookmark_Fill1},
	{label = "School", icon = .School, active_icon = .School_Fill1},
	{label = "Work", icon = .Work, active_icon = .Work_Fill1, disabled = true},
}

// DRAWER_H and RAIL_H are the heights of the drawer and rail demos.
DRAWER_H :: 420
RAIL_H :: 480

// demo_pane is the content beside a drawer or rail demo: a filled card w
// wide and h tall, naming the selection.
demo_pane :: proc(gtx: ^ui.Ctx, title: string, w: f32, h: f32 = DRAWER_H, key: u64 = 0, loc := #caller_location) {
	c := m3.card_open(gtx, .Filled, key = key, loc = loc)
	defer ui.close(&c)
	r := ui.row_open(gtx)
	defer ui.close(&r)
	{
		col := ui.column_open(gtx, gap = 8)
		defer ui.close(&col)
		ui.label(gtx, title, {size = 18, color = m3.scheme()[.On_Surface]})
		ui.spacer(gtx, 0)
		wide := ui.row_open(gtx)
		defer ui.close(&wide)
		ui.spacer(gtx, w - 32)
	}
	ui.spacer(gtx, 0)
	tall := ui.column_open(gtx)
	defer ui.close(&tall)
	ui.spacer(gtx, h - 32)
}

page_drawer :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Destinations", "deprecated in Expressive (the expanded rail replaces it); 56dp items, active on a secondary-container pill; inactive content turns on-surface under hover, focus and press")
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(i))
		defer ui.close(&r)
		ui.label(gtx, STATE_NAMES[i], {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		ui.spacer(gtx, max(LABEL_W - label_width(gtx, STATE_NAMES[i]), 0))
		wr := ui.wrap_open(gtx, gap = 16, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		m3.drawer_item(gtx, {label = "Inbox", icon = .Inbox, badge = "24"}, false, 280, st, key = u64(10 + i))
		m3.drawer_item(gtx, {label = "Inbox", icon = .Inbox, active_icon = .Inbox_Fill1, badge = "24"}, true, 280, st, key = u64(20 + i))
	}
	if DRAWER_ITEMS[m.drawer_sel].headline {
		m.drawer_sel = 1 // the model starts at 0, a headline: start on Inbox
	}
	section(gtx, "Variants", "permanent: square, beside the content; dismissible: slides in and out and the content reflows; modal: over a scrim, closed by the scrim or Escape")
	r := ui.wrap_open(gtx, gap = 32)
	defer ui.close(&r)
	{
		c := ui.column_open(gtx, gap = 8, key = 1)
		defer ui.close(&c)
		ui.label(gtx, "Permanent", {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		m3.navigation_drawer(gtx, DRAWER_ITEMS[:], &m.drawer_sel, width = 300, height = DRAWER_H, key = 1)
	}
	{
		c := ui.column_open(gtx, gap = 8, key = 2)
		defer ui.close(&c)
		if m3.button(gtx, m.drawer_open ? "Close dismissible" : "Open dismissible", .Tonal, .Menu, key = 2) {
			m.drawer_open = !m.drawer_open
		}
		rr := ui.row_open(gtx, key = 2)
		defer ui.close(&rr)
		m3.navigation_drawer(gtx, DRAWER_ITEMS[:], &m.drawer_sel, width = 300, height = DRAWER_H, variant = .Dismissible, open = &m.drawer_open, key = 2)
		demo_pane(gtx, "Content", 200, key = 2)
	}
	{
		c := ui.column_open(gtx, gap = 8, key = 3)
		defer ui.close(&c)
		if m3.button(gtx, "Open modal", .Tonal, .Menu, key = 3) {
			m.drawer_modal = true
		}
		rr := ui.row_open(gtx, key = 3)
		defer ui.close(&rr)
		m3.navigation_drawer(gtx, DRAWER_ITEMS[:], &m.drawer_sel, width = 300, height = DRAWER_H, variant = .Modal, open = &m.drawer_modal, key = 3)
		demo_pane(gtx, "Content", 300, key = 3)
	}
}

// destination_states is a nav destination (rail or bar) across the
// states: vertical items inactive, active and badged, then horizontal
// items inactive and active.
destination_states :: proc(gtx: ^ui.Ctx, m: ^Model, bar: bool) {
	state_header(gtx)
	NAMES := [?]string{"Inactive", "Active", "With badge", "Start, inactive", "Start, active"}
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			v := key / 16
			bar := v >= 10
			v %= 10
			it := m3.Nav_Item{label = "Label", icon = .Home, active_icon = .Home_Fill1}
			if v == 3 {
				it.badge = "12"
			}
			m3.nav_destination(gtx, it, v == 2 || v == 3 || v == 5, bar, v >= 4, st, key)
		}
		state_row(gtx, m, n, cell, u64(i + 1 + (bar ? 10 : 0)))
	}
}

page_rail :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Destinations", "vertical (collapsed) items: 56x32 indicator, 12sp label; horizontal (expanded) items: 56dp pill around icon and 14sp label; active label in secondary")
	destination_states(gtx, m, false)
	section(gtx, "Live", "plain 80dp rail; expandable 96dp rail whose menu widens it to hug its items and extends the FAB; modal rail expanding over its content behind a scrim")
	r := ui.wrap_open(gtx, gap = 32)
	defer ui.close(&r)
	{
		rr := ui.row_open(gtx, key = 1)
		defer ui.close(&rr)
		m3.navigation_rail(gtx, NAV_ITEMS[:], &m.rail_plain, height = RAIL_H, key = 1)
		demo_pane(gtx, NAV_ITEMS[m.rail_plain].label, 160, RAIL_H, key = 1)
	}
	{
		rr := ui.row_open(gtx, key = 2)
		defer ui.close(&rr)
		m3.navigation_rail(gtx, NAV_ITEMS[:], &m.rail_sel, .Edit, true, &m.rail_expanded, fab_label = "Compose", height = RAIL_H, key = 2)
		demo_pane(gtx, NAV_ITEMS[m.rail_sel].label, 200, RAIL_H, key = 2)
	}
	{
		rr := ui.row_open(gtx, key = 3)
		defer ui.close(&rr)
		m3.navigation_rail(gtx, NAV_ITEMS[:], &m.rail_modal_sel, .Edit, true, &m.rail_modal, modal = true, fab_label = "Compose", height = RAIL_H, key = 3)
		demo_pane(gtx, NAV_ITEMS[m.rail_modal_sel].label, 280, RAIL_H, key = 3)
	}
}

page_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Destinations", "vertical items: 56x32 indicator; horizontal items: 40dp pill around icon and label; 12sp label, active in secondary")
	destination_states(gtx, m, true)
	section(gtx, "Standard", "64dp on surface-container, equal shares, vertical items; the indicator grows on the fast-spatial spring")
	m3.navigation_bar(gtx, NAV_ITEMS[:], &m.bar_sel, 412, key = 1)
	section(gtx, "Flexible, compact", "equal weight; vertical items below 600dp")
	m3.navigation_bar(gtx, NAV_ITEMS[:], &m.bar_flex, 412, flexible = true, key = 2)
	section(gtx, "Flexible, medium", "centered arrangement; horizontal items at 600dp and wider")
	m3.navigation_bar(gtx, NAV_ITEMS[:], &m.bar_wide, 800, flexible = true, arrangement = .Centered, key = 3)
	section(gtx, "Label only when active", "always_show_label = false")
	m3.navigation_bar(gtx, NAV_ITEMS[:], &m.bar_quiet, 412, always_show_label = false, key = 4)
}

page_badges :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Badges", "small: 6dp error dot; large: 16dp min, 11sp on-error, 4dp side padding once the label outgrows the circle")
	{
		r := ui.wrap_open(gtx, gap = 24, align = .Center)
		defer ui.close(&r)
		m3.badge(gtx, " ", key = 1)
		m3.badge(gtx, "3", key = 2)
		m3.badge(gtx, "42", key = 3)
		m3.badge(gtx, "999+", key = 4)
	}
	section(gtx, "On icons", "over the anchor's top-trailing corner: the dot 6dp in and down, a numeral 12dp in and 14dp down less its height; the badge takes no space")
	{
		r := ui.wrap_open(gtx, gap = 32, align = .Center)
		defer ui.close(&r)
		ui.spacer(gtx, 8)
		m3.badged_icon(gtx, .Notifications, " ", key = 1)
		m3.badged_icon(gtx, .Mail, "3", key = 2)
		m3.badged_icon(gtx, .Chat_Bubble, "42", key = 3)
		m3.badged_icon(gtx, .Shopping_Cart, "999+", key = 4)
	}
	section(gtx, "On navigation")
	sel := 0
	m3.navigation_bar(gtx, NAV_ITEMS[:], &sel, 412)
}

page_app_bars :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	ACTIONS := [?]m3.Icon{.Attach_File, .Event, .More_Vert}
	W :: 600
	section(gtx, "Small", "64dp, 22sp title, optional 12sp subtitle; leading icon on-surface, trailing on-surface-variant, 4dp from the edges")
	m3.top_app_bar(gtx, "Title", .Small, .Arrow_Back, ACTIONS[:], width = W, key = 1)
	m3.top_app_bar(gtx, "Title", .Small, .Arrow_Back, ACTIONS[:], width = W, subtitle = "Subtitle", key = 2)
	section(gtx, "Small, scrolled", "on-scroll-container-color once content scrolls under it, cross-faded on the default-effects spring")
	m3.top_app_bar(gtx, "Title", .Small, .Arrow_Back, ACTIONS[:], scrolled = true, width = W, key = 3)
	section(gtx, "Center aligned", "centred on the whole bar")
	m3.top_app_bar(gtx, "Title", .Center, .Menu, ACTIONS[2:], width = W, key = 4)
	m3.top_app_bar(gtx, "Title", .Small, .Menu, ACTIONS[2:], width = W, subtitle = "Subtitle", centered = true, key = 5)
	section(gtx, "Search", "a search-bar field in the title's place")
	m3.top_app_bar(gtx, "Search messages", .Search, .Menu, ACTIONS[2:], width = W, key = 6)
	section(gtx, "Medium", "112dp; 24sp title, its baseline 24dp above the bottom")
	m3.top_app_bar(gtx, "Medium title", .Medium, .Arrow_Back, ACTIONS[:], width = W, key = 7)
	section(gtx, "Medium flexible", "112dp, or 136dp with a subtitle; 28sp title")
	m3.top_app_bar(gtx, "Medium flexible", .Medium_Flexible, .Arrow_Back, ACTIONS[:], width = W, key = 8)
	m3.top_app_bar(gtx, "Medium flexible", .Medium_Flexible, .Arrow_Back, ACTIONS[:], width = W, subtitle = "Subtitle", key = 9)
	section(gtx, "Large", "152dp; 28sp title, its baseline 28dp above the bottom")
	m3.top_app_bar(gtx, "Large title", .Large, .Arrow_Back, ACTIONS[:], width = W, key = 10)
	section(gtx, "Large flexible", "120dp, or 152dp with a subtitle; 36sp title; the second centred")
	m3.top_app_bar(gtx, "Large flexible", .Large_Flexible, .Arrow_Back, ACTIONS[:], width = W, key = 11)
	m3.top_app_bar(gtx, "Large flexible", .Large_Flexible, .Arrow_Back, ACTIONS[:], width = W, subtitle = "Subtitle", centered = true, key = 12)
	section(gtx, "Collapsing", "medium flexible 0, 0.5 and 1 collapsed: the height falls to 64dp, the colour turns, the titles cross-fade")
	FRACTIONS := [?]f32{0, 0.5, 1}
	for f, i in FRACTIONS {
		m3.top_app_bar(gtx, "Medium flexible", .Medium_Flexible, .Arrow_Back, ACTIONS[:], width = W, subtitle = "Subtitle", collapsed = f, key = u64(20 + i))
	}
}

page_tabs :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	LABELS := [?]string{"Video", "Photos", "Audio"}
	ICONS := [?]m3.Icon{.Movie, .Photo, .Music_Note}
	W :: 420
	section(gtx, "Primary tabs, state of the first tab", "48dp (64 with icons), 14sp label; 3dp primary indicator as wide as the content; inactive content on-surface under hover, focus and press")
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(i))
		defer ui.close(&r)
		ui.label(gtx, STATE_NAMES[i], {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		ui.spacer(gtx, max(LABEL_W - 16 - label_width(gtx, STATE_NAMES[i]), 0))
		wr := ui.wrap_open(gtx, gap = 16, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		sel := 0
		m3.tabs(gtx, LABELS[:], &sel, width = W, state = st, state_tab = 0, key = u64(10 + i))
		sel2 := 1
		m3.tabs(gtx, LABELS[:], &sel2, ICONS[:], width = W, state = st, state_tab = 0, key = u64(20 + i))
	}
	section(gtx, "Secondary tabs", "indicator across the tab; on-surface active label; icons beside the label")
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(30 + i))
		defer ui.close(&r)
		ui.label(gtx, STATE_NAMES[i], {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		ui.spacer(gtx, max(LABEL_W - 16 - label_width(gtx, STATE_NAMES[i]), 0))
		wr := ui.wrap_open(gtx, gap = 16, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		sel := 0
		m3.tabs(gtx, LABELS[:], &sel, secondary = true, width = W, state = st, state_tab = 0, key = u64(40 + i))
		sel2 := 1
		m3.tabs(gtx, LABELS[:], &sel2, ICONS[:], secondary = true, width = W, state = st, state_tab = 0, key = u64(50 + i))
	}
	section(gtx, "Live", "the indicator's position and width follow the default-spatial spring")
	m3.tabs(gtx, LABELS[:], &m.tab_a, width = W, key = 60)
	m3.tabs(gtx, LABELS[:], &m.tab_b, ICONS[:], width = W, key = 61)
	m3.tabs(gtx, LABELS[:], &m.tab_c, secondary = true, width = W, key = 62)
	section(gtx, "Scrollable", "natural widths (min 90dp) from a 52dp edge; the wheel scrolls, and a new selection scrolls to the centre")
	MANY := [?]string{"Overview", "Specifications", "Reviews", "Accessories", "Support", "Warranty", "Downloads", "Community"}
	m3.tabs(gtx, MANY[:], &m.tab_d, width = 600, scrollable = true, key = 63)
	m3.tabs(gtx, MANY[:], &m.tab_e, secondary = true, width = 600, scrollable = true, key = 64)
}

EDIT_MENU := [?]m3.Menu_Item {
	{label = "Cut", leading = .Content_Cut, trailing = "Ctrl+X"},
	{label = "Copy", leading = .Content_Copy, trailing = "Ctrl+C"},
	{label = "Paste", leading = .Content_Paste, trailing = "Ctrl+V", divider = true},
	{label = "Undo", leading = .Undo},
	{label = "Redo", leading = .Redo, disabled = true},
}
