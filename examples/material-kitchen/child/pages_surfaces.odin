package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import m3 "jm:ui/material"

SUGGESTIONS := [?]string{"Material Design", "Material Symbols", "Motion", "Color roles", "Typography", "Shape scale", "Elevation"}

page_search :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Search bar", "comp.search-bar: 56dp surface-container-high pill, 360-720dp wide, icons 16dp from the edges")
	state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			q: ui.Text_State
			m3.search_bar(gtx, &q, "Search", state = st, key = key)
		}
		state_row(gtx, m, "Placeholder", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			q: ui.Text_State
			m3.search_bar(gtx, &q, "Search mail", .Menu, .Account_Circle, state = st, key = key)
		}
		state_row(gtx, m, "Menu + avatar", cell, 2)
	}

	section(gtx, "Search view, expanded", "comp.search-view: docked (one popup, 28dp corners, a divider under the 56dp header) and docked with a gap (the bar stays)")
	{
		r := ui.wrap_open(gtx, gap = 48)
		defer ui.close(&r)
		VIEWS := [2]m3.Search_View{.Docked, .Docked_With_Gap}
		for v, i in VIEWS {
			c := ui.column_open(gtx, gap = 0, key = u64(10 + i))
			q: ui.Text_State
			q.buf = make([dynamic]u8, gtx.allocator)
			append(&q.buf, "Mat")
			q.cursor = 3
			open := true
			m3.search_bar(gtx, &q, "Search", .Search, .None, SUGGESTIONS[:], 400, v, &open, m.window, state = .Enabled, key = u64(20 + i))
			ui.spacer(gtx, m3.SEARCH_DOCKED_MIN_RESULTS + (v == .Docked_With_Gap ? m3.SEARCH_GAP : 0) + 16)
			ui.close(&c)
		}
	}

	section(gtx, "Live", "click a bar: docked follows focus; the others are caller-owned. Full screen covers the window, contained keeps the bar as its header")
	{
		r := ui.wrap_open(gtx, gap = 24, align = .Start)
		defer ui.close(&r)
		if i := m3.search_bar(gtx, &m.query, "Search the spec", .Search, .Account_Circle, SUGGESTIONS[:], 360, window = m.window, submitted = &m.searched, key = 30); i >= 0 {
			m.searched = false
		}
		m3.search_bar(gtx, &m.queries[0], "Docked with gap", .Search, .None, SUGGESTIONS[:], 360, .Docked_With_Gap, &m.search_open[1], m.window, key = 31)
	}
	r := ui.wrap_open(gtx, gap = 24, align = .Start)
	defer ui.close(&r)
	m3.search_bar(gtx, &m.queries[1], "Full screen search", .Search, .None, SUGGESTIONS[:], 360, .Full_Screen, &m.search_open[2], m.window, key = 32)
	m3.search_bar(gtx, &m.queries[2], "Contained search", .Search, .Account_Circle, SUGGESTIONS[:], 360, .Full_Screen_Contained, &m.search_open[3], m.window, key = 33)
}

page_bottom_sheet :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Bottom sheets", "comp.sheet-bottom: surface-container-low, top corners 28, a 32x4 handle 22dp down; springs in on default-spatial, out on fast-effects. Drag it, or click the handle to cycle")
	{
		r := ui.row_open(gtx, gap = 12, align = .Center)
		defer ui.close(&r)
		if m3.button(gtx, "Show modal sheet", .Filled, key = 1) {
			m.bottom = true
		}
		if m3.button(gtx, m.bottom_std ? "Hide standard sheet" : "Show standard sheet", .Outlined, key = 2) {
			m.bottom_std = !m.bottom_std
		}
		NAMES := [m3.Sheet_Value]string {
			.Hidden             = "hidden",
			.Partially_Expanded = "partially expanded",
			.Expanded           = "expanded",
		}
		base.label(gtx, fmt.tprintf("modal sheet: %s", NAMES[m.sheet_value]), {color = m3.scheme()[.On_Surface_Variant]})
	}
	{
		sh := m3.bottom_sheet_open(gtx, &m.bottom, m.window, value = &m.sheet_value, key = 3)
		defer m3.sheet_close(&sh)
		if sh.visible {
			ITEMS := [?]m3.List_Item {
				{headline = "Share", leading_icon = .Share},
				{headline = "Get link", leading_icon = .Attach_File},
				{headline = "Edit name", leading_icon = .Edit},
				{headline = "Delete", leading_icon = .Delete},
				{headline = "Download", leading_icon = .Download},
				{headline = "Bookmark", leading_icon = .Bookmark},
				{headline = "Archive", leading_icon = .Archive},
				{headline = "Settings", leading_icon = .Settings},
			}
			for it, i in ITEMS {
				if m3.list_item(gtx, it, sh.width, key = u64(10 + i)) {
					m.bottom = false
				}
			}
		}
	}
	{
		sh := m3.bottom_sheet_open(gtx, &m.bottom_std, m.window, modal = false, skip_partial = true, max_width = 480, key = 4)
		defer m3.sheet_close(&sh)
		if sh.visible {
			base.label(gtx, "Standard: no scrim, the page stays live", {size = 16, color = m3.scheme()[.On_Surface]})
			ui.spacer(gtx, 8)
			base.label(gtx, "Now playing: Clair de lune", {color = m3.scheme()[.On_Surface_Variant]})
			ui.spacer(gtx, 16)
		}
	}

	section(gtx, "Drag handle", "comp.drag-handle: the grip between resizable panes, 4x48 outline, 12x52 on-surface pressed or dragged")
	state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			m3.drag_handle(gtx, st, key = key)
		}
		state_row(gtx, m, "Drag handle", cell, 5)
	}
	{
		r := ui.row_open(gtx, gap = 8, align = .Center)
		defer ui.close(&r)
		base.label(gtx, "Dragged", {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		ui.spacer(gtx, 60)
		m3.drag_handle(gtx, .Dragged, key = 6)
	}
	section(gtx, "Live", "drag the handle between the panes")
	if m.pane == 0 {
		m.pane = 240
	}
	r := ui.row_open(gtx, align = .Center)
	defer ui.close(&r)
	pane :: proc(gtx: ^ui.Ctx, w: f32, label: string, key: u64) {
		b := base.panel_open(gtx, {fill = m3.scheme()[.Surface_Container], radius = m3.CORNER_MEDIUM, padding = ui.pad_all(16)}, key = key)
		defer ui.close(&b)
		m3.strut(gtx, w - 32)
		base.label(gtx, label, {color = m3.scheme()[.On_Surface]})
		ui.spacer(gtx, 80)
	}
	pane(gtx, m.pane, fmt.tprintf("%.0fdp", m.pane), 7)
	m.pane = clamp(m.pane + m3.drag_handle(gtx, key = 8), 120, 600)
	pane(gtx, 720 - m.pane, "the other pane", 9)
}

page_side_sheet :: proc(gtx: ^ui.Ctx, m: ^Model) {
	r := ui.row_open(gtx, gap = 24)
	defer ui.close(&r)
	{
		col := ui.column_open(gtx, gap = 10)
		defer ui.close(&col)
		section(gtx, "Side sheets", "comp.navigation-drawer stands in (no side-sheet tokens)")
		base.label(gtx, "standard: surface, inline, beside this column", {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		base.label(gtx, "modal: surface-container-low over a scrim", {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		if m3.button(gtx, "Show modal sheet", .Filled, key = 1) {
			m.side, m.side_left = true, false
		}
		if m3.button(gtx, "Show from the left", .Outlined, key = 4) {
			m.side, m.side_left = true, true
		}
	}
	filters :: proc(gtx: ^ui.Ctx, m: ^Model, key: u64) {
		m3.checkbox(gtx, &m.checks[1], "In stock", key = key + 1)
		m3.checkbox(gtx, &m.checks[2], "On sale", key = key + 2)
		m3.switch_(gtx, &m.switches[2], "Free delivery", key = key + 3)
		r := ui.row_open(gtx, gap = 8)
		m3.button(gtx, "Apply", .Filled, key = key + 4)
		m3.button(gtx, "Reset", .Outlined, key = key + 5)
		ui.close(&r)
	}
	{
		unused := false
		sh := m3.side_sheet_open(gtx, &unused, m.window, modal = false, width = 280, headline = "Filters", key = 2)
		defer m3.sheet_close(&sh)
		filters(gtx, m, 20)
	}
	sh := m3.side_sheet_open(gtx, &m.side, m.window, left = m.side_left, headline = "Filters", key = 3)
	defer m3.sheet_close(&sh)
	if sh.visible {
		filters(gtx, m, 40)
	}
}

page_date_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	s := m3.scheme()
	section(gtx, "Day cells", "48dp touch target, 40dp circle; selected fills primary, today is ringed primary, a range band is secondary-container")
	state_header(gtx)
	NAMES := [?]string{"Unselected", "Selected", "Today", "In range"}
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			kind := key / 16 - 1
			m3.date_cell(gtx, 14, selected = kind == 1, today = kind == 2, in_range = kind == 3, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1))
	}

	if m.range_view == {} {
		m.range_start, m.range_end, m.range_view = {2026, 9, 22}, {2026, 9, 26}, {2026, 9, 1}
		m.input_mode, m.input_date = .Input, TODAY
		ui.text_set(&m.input_text, "09282026")
	}
	section(gtx, "Modal date picker", "comp.date-picker-modal: 360dp, surface-container-high, corner 28; the pencil switches to input mode, the month label opens the years")
	r := ui.wrap_open(gtx, gap = 24, line_gap = 24)
	defer ui.close(&r)
	ACTIONS := [?]string{"Cancel", "OK"}
	m3.date_picker(gtx, &m.date, &m.date_view, TODAY, mode = &m.date_mode, input = &m.date_input, actions = ACTIONS[:], action = &m.date_action, key = 1)
	m3.date_picker(gtx, &m.range_start, &m.range_view, TODAY, range_end = &m.range_end, key = 2)
	{
		c := ui.column_open(gtx, gap = 10)
		defer ui.close(&c)
		m3.date_picker(gtx, &m.input_date, &m.input_view, TODAY, mode = &m.input_mode, input = &m.input_text, key = 3)
		base.label(gtx, fmt.tprintf("Selected %04d-%02d-%02d", m.date.year, m.date.month, m.date.day), {color = s[.On_Surface_Variant]})
		base.label(gtx, fmt.tprintf("Range %d/%d - %d/%d", m.range_start.month, m.range_start.day, m.range_end.month, m.range_end.day), {color = s[.On_Surface_Variant]})
	}
}

page_time_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	s := m3.scheme()
	if m.times == {} {
		m.times = {{21, 5}, {14, 30}, {7, 15}}
	}
	section(gtx, "Dial", "comp.time-picker: 96x80 selectors, the AM/PM toggle, a 256dp dial; drag on the dial, a tap snaps minutes to fives, an hour moves on to minutes")
	{
		r := ui.wrap_open(gtx, gap = 24, align = .Start)
		defer ui.close(&r)
		m3.time_picker(gtx, &m.time, &m.minutes, key = 1)
		m3.time_picker(gtx, &m.times[0], &m.editing[0], is_24h = true, key = 2)
		{
			c := ui.column_open(gtx, gap = 10)
			defer ui.close(&c)
			m3.time_picker(gtx, &m.times[1], &m.editing[1], mode = .Input, key = 3)
			base.label(gtx, "Input mode (comp.time-input): click a field, type digits, Up/Down", {size = 12, color = s[.On_Surface_Variant]})
			base.label(gtx, fmt.tprintf("%02d:%02d   %02d:%02d   %02d:%02d", m.time.hour, m.time.minute, m.times[0].hour, m.times[0].minute, m.times[1].hour, m.times[1].minute), {color = s[.On_Surface_Variant]})
		}
	}
	section(gtx, "Horizontal layout", "landscape: the selectors beside the dial, the period toggle below them")
	m3.time_picker(gtx, &m.times[2], &m.editing[2], layout = .Horizontal, key = 4)
	section(gtx, "Forced", "state forces the selectors and the period toggle")
	r := ui.wrap_open(gtx, gap = 24, align = .Start)
	defer ui.close(&r)
	STATES := [2]m3.Interaction{.Hovered, .Disabled}
	for st, i in STATES {
		t := m3.Time{9, 41}
		e := false
		m3.time_picker(gtx, &t, &e, mode = .Input, state = st, key = u64(10 + i))
	}
}

page_carousel :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	s := m3.scheme()
	ITEMS := [?]m3.Carousel_Item {
		{"Coast", s[.Primary], s[.Tertiary]},
		{"Forest", s[.Secondary], s[.Primary]},
		{"Desert", s[.Tertiary], s[.Error]},
		{"Tundra", s[.Primary], s[.Secondary]},
		{"Reef", s[.Tertiary], s[.Primary]},
		{"Canyon", s[.Error], s[.Tertiary]},
		{"Lagoon", s[.Secondary], s[.Tertiary]},
	}
	STRATS := [?]m3.Carousel_Strategy{.Multi_Browse, .Hero_Start, .Hero_Center, .Uncontained, .Full_Screen}
	NAMES := [?]string{"Multi-browse", "Hero, start-aligned", "Hero, centre-aligned", "Uncontained", "Full screen"}
	NOTES := [?]string {
		"large, medium and small items solved to fill the width; items collapse around their centre as they scroll",
		"one large item and a small peek at the end",
		"a large item between two small peeks",
		"one width throughout, the last cut off; no snapping",
		"one item filling the viewport",
	}
	for st, i in STRATS {
		section(gtx, NAMES[i], NOTES[i])
		w: f32 = st == .Full_Screen ? 360 : 720
		if hit := m3.carousel(gtx, ITEMS[:], w, st == .Full_Screen ? 240 : 200, st, st == .Uncontained ? 240 : (st == .Multi_Browse ? 186 : 300), 8, key = u64(1 + i)); hit >= 0 {
			m.carousel_hit = hit + 1
		}
	}
	if m.carousel_hit > 0 {
		base.label(gtx, fmt.tprintf("Clicked %s", ITEMS[m.carousel_hit - 1].label), {color = s[.On_Surface_Variant]})
	}
}
