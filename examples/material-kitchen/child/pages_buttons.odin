package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import m3 "jm:ui/material"

// The buttons group: common and toggle buttons, icon buttons, FABs,
// segmented and split buttons, each on the M3 Expressive kit's spec.

BUTTON_KINDS := [?]m3.Button_Kind{.Elevated, .Filled, .Tonal, .Outlined, .Text}
BUTTON_KIND_NAMES := [?]string{"Elevated", "Filled", "Filled tonal", "Outlined", "Text"}
SIZE_NAMES := [?]string{"X-small", "Small", "Medium", "Large", "X-large"}

page_buttons :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Common buttons", "small: 40dp, corner full, label-large; the pressed column shows the 8dp press morph")
	kitchen.state_header(gtx, CELL_W)
	for n, i in BUTTON_KIND_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.button(gtx, "Label", BUTTON_KINDS[key / 16 - 1], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), CELL_W)
	}
	section(gtx, "With an icon", "20dp icon, 8dp from the label; leading, or trailing on the last row")
	kitchen.state_header(gtx, CELL_W)
	for n, i in BUTTON_KIND_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.button(gtx, "Send", BUTTON_KINDS[key / 16 - 11], leading = .Send, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), CELL_W)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.button(gtx, "Next", .Filled, trailing = .Arrow_Forward, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Trailing", cell, 20, CELL_W)
	}
	section(gtx, "Live", "hover, press, Tab and Enter these")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	for k, i in BUTTON_KINDS {
		if m3.button(gtx, fmt.tprintf("Clicked %d", m.clicks), k, key = u64(100 + i)) {
			m.clicks += 1
		}
	}
}

// SIZE_CELL_W is a state cell wide enough for an x-large button.
SIZE_CELL_W :: f32(190)

page_button_sizes :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Round", "x-small 32 / small 40 / medium 56 / large 96 / x-large 136dp; label type grows with size")
	kitchen.state_header(gtx, SIZE_CELL_W)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.button(gtx, "Go", .Filled, size = m3.Button_Size(key / 16 - 1), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), SIZE_CELL_W)
	}
	section(gtx, "Square", "corner 12 / 12 / 16 / 28 / 28dp at rest")
	kitchen.state_header(gtx, SIZE_CELL_W)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.button(gtx, "Go", .Tonal, .Check, size = m3.Button_Size(key / 16 - 11), shape = .Square, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), SIZE_CELL_W)
	}
	section(gtx, "Live", "press and hold to see each size's squish")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	for _, i in SIZE_NAMES {
		if m3.button(gtx, "Go", .Outlined, size = m3.Button_Size(i), key = u64(100 + i)) {
			m.clicks += 1
		}
	}
}

page_toggle_buttons :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	TOGGLE_NAMES := [?]string{"Elevated", "Filled", "Tonal", "Outlined"}
	section(gtx, "Unchecked", "checkable buttons: text has no toggle")
	kitchen.state_header(gtx, CELL_W)
	for n, i in TOGGLE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			off := false
			m3.button(gtx, "Like", BUTTON_KINDS[key / 16 - 1], .Favorite, checked = &off, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), CELL_W)
	}
	section(gtx, "Checked", "round morphs to the size's square corner; colours from each style's selected-* tokens")
	kitchen.state_header(gtx, CELL_W)
	for n, i in TOGGLE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			on := true
			m3.button(gtx, "Like", BUTTON_KINDS[key / 16 - 11], .Favorite_Fill1, checked = &on, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), CELL_W)
	}
	section(gtx, "Live", "click to toggle; a square button morphs round when checked")
	{
		r := ui.wrap_open(gtx, gap = 12, align = .Center)
		defer ui.close(&r)
		for n, i in TOGGLE_NAMES {
			g := m.btn_checked[i] ? m3.Icon.Favorite_Fill1 : m3.Icon.Favorite
			m3.button(gtx, n, BUTTON_KINDS[i], g, checked = &m.btn_checked[i], key = u64(100 + i))
		}
	}
	r := ui.row_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	for i in 0 ..< 4 {
		shape := i % 2 == 0 ? m3.Button_Shape.Round : m3.Button_Shape.Square
		m3.button(gtx, "Star", .Filled, m.size_checked[i] ? .Star_Fill1 : .Star, size = m3.Button_Size(i), shape = shape, checked = &m.size_checked[i], key = u64(110 + i))
	}
}

ICON_BUTTON_NAMES := [?]string{"Standard", "Filled", "Tonal", "Outlined"}

page_icon_buttons :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Default", "small, uniform: 40dp, 24dp icon; the pressed column shows the 8dp press morph")
	kitchen.state_header(gtx, CELL_W)
	for n, i in ICON_BUTTON_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.icon_button(gtx, .Settings, m3.Icon_Button_Kind(key / 16 - 1), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), CELL_W)
	}
	section(gtx, "Toggle, unselected")
	kitchen.state_header(gtx, CELL_W)
	for n, i in ICON_BUTTON_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			off := false
			m3.icon_button(gtx, .Favorite, m3.Icon_Button_Kind(key / 16 - 11), &off, .Favorite_Fill1, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), CELL_W)
	}
	section(gtx, "Toggle, selected", "round morphs to the size's square corner")
	kitchen.state_header(gtx, CELL_W)
	for n, i in ICON_BUTTON_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			on := true
			m3.icon_button(gtx, .Favorite, m3.Icon_Button_Kind(key / 16 - 21), &on, .Favorite_Fill1, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 21), CELL_W)
	}
	section(gtx, "Live toggles", "round, then square resting shapes")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	for i in 0 ..< 8 {
		shape := i < 4 ? m3.Button_Shape.Round : m3.Button_Shape.Square
		m3.icon_button(gtx, .Favorite, m3.Icon_Button_Kind(i % 4), &m.toggles[i], .Favorite_Fill1, tooltip = "Favourite", shape = shape, key = u64(200 + i))
	}
}

page_icon_button_sizes :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Live", "every size, outlined; press to squish")
	{
		r := ui.wrap_open(gtx, gap = 12, align = .Center)
		defer ui.close(&r)
		for _, i in SIZE_NAMES {
			m3.icon_button(gtx, .Edit, .Outlined, size = m3.Button_Size(i), key = u64(300 + i))
		}
	}
	WIDTHS := [?]string{"Narrow", "Uniform", "Wide"}
	widths :: proc(gtx: ^ui.Ctx, size: m3.Button_Size, column: int, key: u64) {
		W := [3]m3.Icon_Button_Width{.Narrow, .Uniform, .Wide}
		m3.icon_button(gtx, .Edit, .Tonal, size = size, width = W[column], state = .Enabled, key = key)
	}
	size_grid(gtx, "Widths", "filled tonal; width = icon + the option's leading and trailing space, height fixed per size", WIDTHS[:], widths, 100)
	SHAPES := [?]string{"Square", "Selected", "Square, selected", "Pressed"}
	shapes :: proc(gtx: ^ui.Ctx, size: m3.Button_Size, column: int, key: u64) {
		on := true
		switch column {
		case 0:
			m3.icon_button(gtx, .Edit, .Tonal, size = size, shape = .Square, state = .Enabled, key = key)
		case 1:
			m3.icon_button(gtx, .Favorite, .Tonal, &on, .Favorite_Fill1, size = size, state = .Enabled, key = key)
		case 2:
			m3.icon_button(gtx, .Favorite, .Tonal, &on, .Favorite_Fill1, size = size, shape = .Square, state = .Enabled, key = key)
		case 3:
			m3.icon_button(gtx, .Edit, .Tonal, size = size, state = .Pressed, key = key)
		}
	}
	size_grid(gtx, "Shapes", "a toggle morphs to the other silhouette when selected; press squishes to the size's pressed corner", SHAPES[:], shapes, 200)
}

// Size_Cell draws column's variant of a component at size.
Size_Cell :: proc(gtx: ^ui.Ctx, size: m3.Button_Size, column: int, key: u64)

// SIZE_GRID_CELL_W is a size grid cell wide enough for an x-large wide
// icon button.
SIZE_GRID_CELL_W :: f32(200)

// size_grid is a titled grid: one row per Button_Size, one cell per column.
// Where the columns do not fit beside the labels, each size's cells wrap
// below its label instead, each captioned with its column.
size_grid :: proc(gtx: ^ui.Ctx, title, note: string, columns: []string, cell: Size_Cell, key: u64) {
	s := m3.scheme()
	section(gtx, title, note)
	if gtx.constraints.max.x < kitchen.LABEL_W + f32(len(columns)) * SIZE_GRID_CELL_W {
		for n, i in SIZE_NAMES {
			col := ui.column_open(gtx, gap = 8, key = key + u64(i + 1))
			defer ui.close(&col)
			base.label(gtx, n, {size = 12, color = s[.On_Surface]})
			wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .End)
			defer ui.close(&wr)
			for name, j in columns {
				cc := ui.column_open(gtx, gap = 4, key = u64(j))
				base.label(gtx, name, {size = 12, color = s[.On_Surface_Variant]})
				cell(gtx, m3.Button_Size(i), j, key * 16 + u64(i * len(columns) + j))
				ui.close(&cc)
			}
		}
		return
	}
	// The heads, across the top.
	{
		r := ui.row_open(gtx, key = key)
		defer ui.close(&r)
		cell_fixed(gtx, kitchen.LABEL_W)
		for name in columns {
			ui.flexible(gtx, 1)
			c := ui.stack_open(gtx)
			base.label(gtx, name, {size = 12, color = s[.On_Surface_Variant]})
			ui.close(&c)
		}
	}
	for n, i in SIZE_NAMES {
		r := ui.row_open(gtx, align = .Center, key = key + u64(i + 1))
		defer ui.close(&r)
		{
			c := ui.stack_open(gtx)
			base.label(gtx, n, {size = 12, color = s[.On_Surface_Variant]})
			ui.close(&c)
		}
		ui.spacer(gtx, max(kitchen.LABEL_W - label_width(gtx, n), 0))
		for j in 0 ..< len(columns) {
			ui.flexible(gtx, 1)
			c := ui.stack_open(gtx, key = u64(j))
			cell(gtx, m3.Button_Size(i), j, key * 16 + u64(i * len(columns) + j))
			ui.close(&c)
		}
	}
}

page_fab :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Sizes", "small 40 / baseline 56 / medium 80 / large 96dp; elevation 3, 4 on hover; no disabled state in M3")
	kitchen.state_header(gtx, CELL_W)
	SIZES := [?]string{"Small", "Baseline", "Medium", "Large"}
	for n, i in SIZES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.fab(gtx, .Edit, m3.Fab_Size(key / 16 - 1), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), CELL_W)
	}
	section(gtx, "Colours", "primary, secondary and tertiary container; surface is baseline M3's")
	kitchen.state_header(gtx, CELL_W)
	COLORS := [?]string{"Primary", "Secondary", "Tertiary", "Surface"}
	for n, i in COLORS {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.fab(gtx, .Edit, .Regular, m3.Fab_Color(key / 16 - 11), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), CELL_W)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.fab(gtx, .Edit, .Regular, lowered = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Lowered", cell, 20, CELL_W)
	}
}

page_extended_fab :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Generic", "56dp, corner 16, label-large; 16 / 12 / 20dp padding")
	kitchen.state_header(gtx, CELL_W)
	COLORS := [?]string{"Primary", "Secondary", "Tertiary"}
	for n, i in COLORS {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.extended_fab(gtx, .Edit, "Compose", m3.Fab_Color(key / 16 - 1), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), CELL_W)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.extended_fab(gtx, .None, "Compose", state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Text only", cell, 5, CELL_W)
	}
	section(gtx, "Sizes", "small 56 / medium 80 / large 96dp; title-medium, title-large, headline-small")
	kitchen.state_header(gtx, CELL_W)
	SIZES := [?]string{"Small", "Medium", "Large"}
	for n, i in SIZES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			m3.extended_fab(gtx, .Edit, "Edit", size = m3.Extended_Fab_Size(key / 16 - 10), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), CELL_W)
	}
	section(gtx, "Live", "the switch collapses each FAB to its icon square: width on fast-spatial, label on fast-effects")
	{
		r := ui.wrap_open(gtx, gap = 12, align = .Center)
		defer ui.close(&r)
		m3.switch_(gtx, &m.fab_collapsed, "Collapsed")
	}
	r := ui.wrap_open(gtx, gap = 16, align = .Center)
	defer ui.close(&r)
	for i in 0 ..< 4 {
		if m3.extended_fab(gtx, .Edit, "Compose", size = m3.Extended_Fab_Size(i), expanded = !m.fab_collapsed, key = u64(100 + i)) {
			m.clicks += 1
		}
	}
}

page_segmented :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	LABELS := [?]string{"Day", "Week", "Month"}
	section(gtx, "Single select", "deprecated in Expressive for the connected button group; 40dp, selected: secondary-container and a check")
	for st, i in m3.STATES {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(i))
		defer ui.close(&r)
		base.label(gtx, kitchen.STATE_NAMES[i], {size = 12, color = m3.scheme()[.On_Surface_Variant]})
		ui.spacer(gtx, max(kitchen.LABEL_W - label_width(gtx, kitchen.STATE_NAMES[i]), 0))
		wr := ui.wrap_open(gtx, gap = 16, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		sel := [3]bool{false, true, false}
		m3.segmented_button(gtx, LABELS[:], sel[:], state = st, key = u64(10 + i))
	}
	section(gtx, "Live", "single select, then multi-select; the check scales in from its bottom-left")
	m3.segmented_button(gtx, LABELS[:], m.segments[:], key = 30)
	MULTI := [?]string{"$", "$$", "$$$", "$$$$"}
	m3.segmented_button(gtx, MULTI[:], m.multi[:], single = false, key = 31)
}

page_split :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Split button", "small: two buttons 2dp apart, inner corners 4dp, 12dp on the pressed half")
	kitchen.state_header(gtx, CELL_W)
	NAMES := [?]string{"Elevated", "Filled", "Filled tonal", "Outlined"}
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			open := false
			m3.split_button(gtx, "Save", &open, BUTTON_KINDS[key / 16 - 1], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), CELL_W)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			open := true
			m3.split_button(gtx, "Save", &open, .Filled, .Edit, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Expanded", cell, 11, CELL_W)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: m3.Interaction, key: u64) {
			open := false
			m3.split_button(gtx, "Save", &open, .Tonal, .Edit, trailing_enabled = false, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Menu disabled", cell, 12, CELL_W)
	}
	section(gtx, "Sizes", "at rest, pressed (but x-large), and expanded: the trailing half turns circular, the chevron flips")
	for n, i in SIZE_NAMES {
		s := m3.scheme()
		r := ui.row_open(gtx, gap = 24, align = .Center, key = u64(20 + i))
		defer ui.close(&r)
		base.label(gtx, n, {size = 12, color = s[.On_Surface_Variant]})
		ui.spacer(gtx, max(kitchen.LABEL_W - 24 - label_width(gtx, n), 0))
		wr := ui.wrap_open(gtx, gap = 24, line_gap = 12, align = .Center)
		defer ui.close(&wr)
		size := m3.Button_Size(i)
		shut, open := false, true
		m3.split_button(gtx, "Save", &shut, .Filled, size = size, state = .Enabled, key = u64(200 + i * 4))
		m3.split_button(gtx, "Save", &shut, .Filled, size = size, state = .Pressed, key = u64(201 + i * 4))
		m3.split_button(gtx, "Save", &open, .Filled, size = size, state = .Enabled, key = u64(202 + i * 4))
	}
	section(gtx, "Live")
	r := ui.wrap_open(gtx, gap = 16, align = .Center)
	defer ui.close(&r)
	m3.split_button(gtx, "Save", &m.expanded, .Filled, .Edit, key = 40)
	m3.split_button(gtx, "Share", &m.split_open, .Outlined, .Share, size = .Medium, key = 41)
}
