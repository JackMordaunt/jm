package main

import "core:fmt"
import "jm:ui"
import m3 "jm:ui/material"

// state_label is a state grid's row label, padded to LABEL_W.
state_label :: proc(gtx: ^ui.Ctx, name: string) {
	ui.label(gtx, name, {size = 12, color = m3.scheme()[.On_Surface_Variant]})
	ui.spacer(gtx, max(LABEL_W - 16 - label_width(gtx, name), 0))
}

page_button_groups :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	LABELS := [?]string{"Day", "Week", "Month"}
	ICONS := [?]m3.Icon{.Format_Bold, .Format_Italic, .Format_Underlined, .Palette}
	NO_LABELS := [?]string{"", "", "", ""}
	section(gtx, "Standard and connected", "standard: 12dp apart, round, 12 once selected, 8 pressed. Connected: 2dp apart, inner 8 (middle: small), pressed inner 4, selected a full pill")
	ui.label(gtx, "Hover, focus and press land on the second child: a press widens it by 15% into its neighbours", {size = 12, color = m3.scheme()[.On_Surface_Variant]})
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 24, align = .Center, key = u64(i))
		defer ui.close(&r)
		state_label(gtx, STATE_NAMES[i])
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		sel := [3]bool{true, false, false}
		m3.button_group(gtx, LABELS[:], sel[:], state = st, key = u64(10 + i))
		sel2 := [3]bool{true, false, false}
		m3.button_group(gtx, LABELS[:], sel2[:], connected = true, state = st, key = u64(20 + i))
		sel3 := [4]bool{false, true, false, true}
		m3.button_group(gtx, NO_LABELS[:], sel3[:], connected = true, single = false, icons = ICONS[:], state = st, key = u64(30 + i))
	}
	section(gtx, "Tonal and action children", "each child keeps its own colour group: tonal toggles, then plain filled and tonal actions (selected nil)")
	{
		r := ui.row_open(gtx, gap = 24, align = .Center)
		defer ui.close(&r)
		state_label(gtx, "Enabled")
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		sel := [3]bool{false, true, false}
		m3.button_group(gtx, LABELS[:], sel[:], style = .Tonal, key = 40)
		sel2 := [3]bool{false, true, false}
		m3.button_group(gtx, LABELS[:], sel2[:], connected = true, style = .Tonal, key = 41)
		ACTS := [?]string{"Cancel", "Save"}
		m3.button_group(gtx, ACTS[:], nil, style = .Tonal, key = 42)
		m3.button_group(gtx, ACTS[:], nil, key = 43)
	}
	section(gtx, "Weighted, per-child disabled, overflow", "a 480dp row whose weighted children share what the fixed one leaves; the third child disabled; a 250dp row whose tail moves into a More options menu")
	{
		r := ui.row_open(gtx, gap = 24, align = .Center)
		defer ui.close(&r)
		state_label(gtx, "Enabled")
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		W := [?]f32{0, 1, 2}
		DIS := [?]bool{false, false, true}
		sel := [3]bool{true, false, false}
		m3.button_group(gtx, LABELS[:], sel[:], connected = true, disabled = DIS[:], weights = W[:], width = min(480, gtx.constraints.max.x), key = 50)
		FIVE := [?]string{"Mon", "Tue", "Wed", "Thu", "Fri"}
		m3.button_group(gtx, FIVE[:], m.group_c[:], width = 250, overflow = &m.group_menu, key = 51)
	}
	section(gtx, "Live", "single-select standard, multi-select connected with icons, press and hold to see the squeeze")
	m3.button_group(gtx, LABELS[:], m.group_a[:], key = 60)
	TEXT := [?]string{"Bold", "Italic", "Underline", "Strike"}
	TICONS := [?]m3.Icon{.Format_Bold, .Format_Italic, .Format_Underlined, .None}
	m3.button_group(gtx, TEXT[:], m.group_b[:], connected = true, single = false, icons = TICONS[:], key = 61)
}

page_toolbars :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	ACTIONS := [?]m3.Icon{.Undo, .Redo, .Format_Bold, .Format_Italic, .Format_Underlined, .Palette}
	section(gtx, "Docked", "64dp, square, across the width; actions centred 4-32dp apart. Standard, then vibrant")
	if i := m3.toolbar(gtx, ACTIONS[:], .Docked, m.tool_sel, 640, key = 1); i >= 0 {
		m.tool_sel = i
	}
	if i := m3.toolbar(gtx, ACTIONS[:], .Docked_Vibrant, m.tool_sel, 640, key = 2); i >= 0 {
		m.tool_sel = i
	}
	section(gtx, "Floating", "a 64dp pill, 8dp padding, 4dp between; the selected action squares from a circle. Standard and vibrant across the states (on the selected action)")
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 24, align = .Center, key = u64(i))
		defer ui.close(&r)
		state_label(gtx, STATE_NAMES[i])
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		m3.toolbar(gtx, ACTIONS[:4], .Floating, 2, key = u64(10 + i), state = st)
		m3.toolbar(gtx, ACTIONS[:4], .Floating_Vibrant, 2, key = u64(20 + i), state = st)
	}
	section(gtx, "Paired FAB and vertical", "expanded, then collapsed: the toolbar folds away and its FAB grows from 56 to 80dp. Vertical, with a leading-side FAB")
	{
		r := ui.wrap_open(gtx, gap = 32, align = .Center)
		defer ui.close(&r)
		m3.toolbar(gtx, ACTIONS[:4], .Floating, -1, key = 30, fab = .Edit, state = .Enabled)
		m3.toolbar(gtx, ACTIONS[:4], .Floating_Vibrant, -1, key = 31, fab = .Edit, state = .Enabled)
		m3.toolbar(gtx, ACTIONS[:4], .Floating_Vibrant, -1, key = 32, expanded = false, fab = .Edit, state = .Enabled)
		m3.toolbar(gtx, ACTIONS[:3], .Floating, 0, key = 33, vertical = true, fab = .Add, fab_leading = true, state = .Enabled)
		m3.toolbar(gtx, ACTIONS[:3], .Floating_Vibrant, 1, key = 34, vertical = true, state = .Enabled)
	}
	section(gtx, "Live", "the toggle expands and collapses both: the first and last actions are side groups, shown only while expanded")
	{
		r := ui.wrap_open(gtx, gap = 32, align = .Center)
		defer ui.close(&r)
		if m3.button(gtx, m.tool_folded ? "Expand" : "Collapse", key = 40) {
			m.tool_folded = !m.tool_folded
		}
		if i := m3.toolbar(gtx, ACTIONS[:], .Floating, m.tool_sel, key = 41, expanded = !m.tool_folded, leading = 1, trailing = 1); i >= 0 {
			m.tool_sel = i
		}
		if i := m3.toolbar(gtx, ACTIONS[:4], .Floating_Vibrant, m.tool_sel, key = 42, expanded = !m.tool_folded, fab = .Edit); i >= 0 {
			m.tool_sel = i
		}
	}
}

page_fab_menu :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	ITEMS := [?]m3.Fab_Menu_Item{{"First", .Mail}, {"Second", .Chat_Bubble}, {"Third", .Event}, {"Fourth", .Photo}, {"Fifth", .Flag}}
	section(gtx, "Closed", "the trigger at baseline (56, corner 16), medium (80, 20) and large (96, 28), across the states")
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 24, align = .Center, key = u64(i))
		defer ui.close(&r)
		state_label(gtx, STATE_NAMES[i])
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		shut := false
		for size, j in m3.Fab_Menu_Size {
			m3.fab_menu(gtx, .Add, ITEMS[:], &shut, key = u64(10 * i + j), size = size, state = st)
		}
	}
	section(gtx, "Open", "the trigger becomes a 56dp primary close button; the items stack above it in list order, 4dp apart, 8dp above it. End-aligned, then start-aligned")
	ui.spacer(gtx, 320)
	{
		r := ui.wrap_open(gtx, gap = 200, align = .End)
		defer ui.close(&r)
		ui.spacer(gtx, 100)
		open := true
		m3.fab_menu(gtx, .Add, ITEMS[:], &open, key = 100, size = .Medium, state = .Enabled)
		open2 := true
		m3.fab_menu(gtx, .Add, ITEMS[:3], &open2, key = 101, align_start = true, state = .Enabled)
	}
	section(gtx, "Live", m.fab_pick == "" ? "open the menu and pick an item" : fmt.tprintf("picked: %s", m.fab_pick))
	ui.spacer(gtx, 330)
	r := ui.row_open(gtx)
	defer ui.close(&r)
	ui.spacer(gtx, 300)
	if i := m3.fab_menu(gtx, .Add, ITEMS[:], &m.fab_open, key = 200); i >= 0 {
		m.fab_pick = ITEMS[i].label
	}
}

page_bottom_app_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	ACTIONS := [?]m3.Icon{.Check, .Edit, .Mic, .Image}
	W :: 640
	section(gtx, "Fixed", "deprecated for the docked toolbar. 80dp, no shadow, actions from the start, a secondary-container FAB at the top end, no cradle")
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 24, align = .Center, key = u64(i))
		defer ui.close(&r)
		state_label(gtx, STATE_NAMES[i])
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		m3.bottom_app_bar(gtx, ACTIONS[:], .Add, width = W, state = st, key = u64(10 + i))
	}
	section(gtx, "Flexible", "the docked toolbar's 64dp and 16dp end padding; space-between, then fixed-centered (at most 32dp apart), the FAB just the last item")
	m3.bottom_app_bar(gtx, ACTIONS[:], .Add, flexible = true, width = W, key = 20)
	m3.bottom_app_bar(gtx, ACTIONS[:], .Add, flexible = true, arrangement = .Fixed_Centered, width = W, key = 21)
	section(gtx, "Live", fmt.tprintf("clicks: %d. Scroll hides the bar 1:1; here a slider stands in for scroll (%.0fdp hidden)", m.bab_clicks, m.bab_hide))
	m3.slider(gtx, &m.bab_hide, 0, 80, width = 320, key = 30)
	if i := m3.bottom_app_bar(gtx, ACTIONS[:], .Add, width = W, height_offset = -m.bab_hide, key = 31); i != -1 {
		m.bab_clicks += 1
	}
}
