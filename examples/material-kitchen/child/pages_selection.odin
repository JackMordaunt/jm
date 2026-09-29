package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import m3 "jm:ui/material"

page_checkbox :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Checkbox", "18dp box, corner 2, 2dp outline; a 40dp state layer in a 48dp target; hover and press recolour nothing")
	state_header(gtx)
	NAMES := [?]string{"Unselected", "Selected", "Indeterminate", "Error", "Error, selected", "Error, indeterminate"}
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			v := key / 16 - 1
			on := v == 1 || v == 4
			m3.checkbox(gtx, &on, indeterminate = v == 2 || v == 5, error = v >= 3, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1))
	}
	section(gtx, "Live", "the mark draws in on default-spatial and morphs to the parent's dash; unchecking holds it 100ms, then drops it")
	all := m.checks[1] && m.checks[2] && m.checks[3]
	some := m.checks[1] || m.checks[2] || m.checks[3]
	parent := all
	if m3.checkbox(gtx, &parent, "All toppings", indeterminate = some && !all, key = 40) {
		for i in 1 ..< 4 {
			m.checks[i] = !all
		}
	}
	NAMES2 := [?]string{"", "Cheese", "Olives", "Basil"}
	for i in 1 ..< 4 {
		r := ui.inset_open(gtx, {32, 0, 0, 0}, key = u64(50 + i))
		m3.checkbox(gtx, &m.checks[i], NAMES2[i], key = u64(60 + i))
		ui.close(&r)
	}
	m3.checkbox(gtx, &m.agree, "I accept the terms", error = !m.agree, key = 70)
}

page_radio :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Radio button", "20dp ring, 2dp; a 6dp dot; ring and dot share one colour; a 40dp state layer in a 48dp target")
	state_header(gtx)
	NAMES := [?]string{"Unselected", "Selected"}
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			v := int(key / 16 - 1)
			m3.radio_button(gtx, &v, 1, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1))
	}
	section(gtx, "Live", "the dot grows and shrinks on fast-spatial; the colour moves on default-effects")
	OPTIONS := [?]string{"Small", "Medium", "Large"}
	for o, i in OPTIONS {
		m3.radio_button(gtx, &m.radio, i, o, key = u64(40 + i))
	}
}

page_switch :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Switch", "52x32 track; handle 16dp off, 24dp on or with icons, 28dp pressed and hugging the near edge")
	state_header(gtx)
	NAMES := [?]string{"Off", "On", "Off, icons", "On, icons"}
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			v := key / 16 - 1
			on := v % 2 == 1
			m3.switch_(gtx, &on, icons = v >= 2, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1))
	}
	section(gtx, "Live", "the handle slides and resizes on fast-spatial; hold it to see the squish snap")
	m3.switch_(gtx, &m.switches[0], "Wi-Fi", key = 40)
	m3.switch_(gtx, &m.switches[1], "Bluetooth", icons = true, key = 41)
}

// frame_text is a throwaway Text_State holding str, for forced-state cells.
frame_text :: proc(gtx: ^ui.Ctx, str: string) -> ^ui.Text_State {
	t := new(ui.Text_State, gtx.allocator)
	t.buf = make([dynamic]u8, gtx.allocator)
	ui.text_set(t, str)
	return t
}

// FIELD_W is a text field's width in the grids: the 280dp minimum of
// text-field.json layout (TextFieldDefaults.kt:89).
FIELD_W :: 280

// Field_Cell draws one text field of column col in state.
Field_Cell :: proc(gtx: ^ui.Ctx, col: int, st: m3.Interaction, key: u64)

// field_grid is a text field state grid: heads across, STATES down. Where
// the columns do not fit beside the labels, each state's fields wrap below
// its label instead, each captioned with its head.
field_grid :: proc(gtx: ^ui.Ctx, heads: []string, cell: Field_Cell, key: u64) {
	if gtx.constraints.max.x < LABEL_W + f32(len(heads)) * (FIELD_W + 24) {
		s := m3.scheme()
		for st, i in m3.STATES {
			k := key * 100 + u64(10 * (i + 1))
			col := ui.column_open(gtx, gap = 8, key = k)
			defer ui.close(&col)
			base.label(gtx, STATE_NAMES[i], {size = 12, color = s[.On_Surface]})
			wr := ui.wrap_open(gtx, gap = 24, line_gap = 12)
			defer ui.close(&wr)
			for h, c in heads {
				cc := ui.column_open(gtx, gap = 4, key = u64(c))
				base.label(gtx, h, {size = 12, color = s[.On_Surface_Variant]})
				cell(gtx, c, st, k + u64(c + 1))
				ui.close(&cc)
			}
		}
		return
	}
	// The heads, across the top.
	{
		r := ui.row_open(gtx, gap = 24, key = key)
		defer ui.close(&r)
		ui.spacer(gtx, LABEL_W - 24)
		for h, i in heads {
			c := ui.stack_open(gtx, key = u64(i))
			base.label(gtx, h, {size = 12, color = m3.scheme()[.On_Surface_Variant]})
			ui.close(&c)
			ui.spacer(gtx, FIELD_W - label_width(gtx, h))
		}
	}
	for st, i in m3.STATES {
		// Top-aligned, so a field's supporting row hangs below its row
		// rather than pushing the container off the others' line.
		k := key * 100 + u64(10 * (i + 1))
		r := ui.row_open(gtx, gap = 24, key = k)
		defer ui.close(&r)
		{
			c := ui.inset_open(gtx, {0, 20, 0, 0})
			base.label(gtx, STATE_NAMES[i], {size = 12, color = m3.scheme()[.On_Surface_Variant]})
			ui.close(&c)
		}
		ui.spacer(gtx, max(LABEL_W - 48 - label_width(gtx, STATE_NAMES[i]), 0))
		for _, c in heads {
			cell(gtx, c, st, k + u64(c + 1))
		}
	}
}

page_text_fields :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 16) // room for an outlined label floated above its row
	defer ui.close(&col)
	HEADS := [?]string{"Empty", "Filled in, icons", "Error, supporting"}
	section(gtx, "Filled", "56dp, top corners 4; 1dp indicator, 2dp on focus; the label floats from body-large to body-small")
	filled :: proc(gtx: ^ui.Ctx, c: int, st: m3.Interaction, key: u64) {
		switch c {
		case 0:
			m3.text_field(gtx, frame_text(gtx, ""), "Label", .Filled, placeholder = "Placeholder", width = FIELD_W, state = st, key = key)
		case 1:
			m3.text_field(gtx, frame_text(gtx, "Input text"), "Label", .Filled, .Search, .Close, width = FIELD_W, state = st, key = key)
		case 2:
			m3.text_field(gtx, frame_text(gtx, "Input"), "Label", .Filled, trailing = .Error, supporting = "Error message", error = true, width = FIELD_W, state = st, key = key)
		}
	}
	field_grid(gtx, HEADS[:], filled, 1)
	section(gtx, "Outlined", "56dp, corner 4; 1dp outline, 2dp on focus; the floated label cuts a notch in it")
	outlined :: proc(gtx: ^ui.Ctx, c: int, st: m3.Interaction, key: u64) {
		switch c {
		case 0:
			m3.text_field(gtx, frame_text(gtx, ""), "Label", .Outlined, placeholder = "Placeholder", width = FIELD_W, state = st, key = key)
		case 1:
			m3.text_field(gtx, frame_text(gtx, "Input text"), "Label", .Outlined, .Search, .Close, width = FIELD_W, state = st, key = key)
		case 2:
			m3.text_field(gtx, frame_text(gtx, "Input"), "Label", .Outlined, trailing = .Error, supporting = "Error message", error = true, width = FIELD_W, state = st, key = key)
		}
	}
	field_grid(gtx, HEADS[:], outlined, 2)
	HEADS2 := [?]string{"Label above, prefix, suffix", "Counter", "Counter past its limit"}
	section(gtx, "Label position, affixes, counter", "a label above never floats; prefix and suffix show once the label is out of the way; the counter turns error past its limit")
	extras :: proc(gtx: ^ui.Ctx, c: int, st: m3.Interaction, key: u64) {
		switch c {
		case 0:
			m3.text_field(gtx, frame_text(gtx, "42"), "Price", .Filled, prefix = "$", suffix = "USD", label_above = true, width = FIELD_W, state = st, key = key)
		case 1:
			m3.text_field(gtx, frame_text(gtx, "Ada"), "Username", .Outlined, supporting = "Letters only", max_length = 12, width = FIELD_W, state = st, key = key)
		case 2:
			m3.text_field(gtx, frame_text(gtx, "Too long a name"), "Username", .Outlined, max_length = 12, width = FIELD_W, state = st, key = key)
		}
	}
	field_grid(gtx, HEADS2[:], extras, 3)

	section(gtx, "Autocomplete", "a field composed with a menu of options as wide as it; type to filter, arrows and Enter to pick, Escape to close")
	FRUIT := [?]string{"Apple", "Apricot", "Banana", "Blueberry", "Cherry", "Grape"}
	{
		r := ui.wrap_open(gtx, gap = 24, line_gap = 12, key = 400)
		defer ui.close(&r)
		if i := m3.autocomplete(gtx, &m.fruit, "Fruit", FRUIT[:], &m.fruit_open, .Filled, key = 401); i >= 0 {
			m.fruit_pick = FRUIT[i]
		}
		if i := m3.autocomplete(gtx, &m.fruit2, "Fruit", FRUIT[:], &m.fruit2_open, .Outlined, leading = .Search, key = 402); i >= 0 {
			m.fruit_pick = FRUIT[i]
		}
		base.label(gtx, m.fruit_pick == "" ? "" : fmt.tprintf("Picked: %s", m.fruit_pick), {color = m3.scheme()[.On_Surface_Variant]})
	}
	ui.spacer(gtx, 8)

	section(gtx, "Live", "click to focus, then type")
	r := ui.wrap_open(gtx, gap = 24, line_gap = 12)
	defer ui.close(&r)
	m3.text_field(gtx, &m.name, "Name", .Filled, supporting = "As it appears on your card", key = 500)
	m3.text_field(gtx, &m.email, "Email", .Outlined, .Mail, placeholder = "you@example.com", key = 501)
	if m3.text_field(gtx, &m.amount, "Amount", .Outlined, trailing = .Cancel, prefix = "$", max_length = 8, trailing_action = &m.amount_clear, key = 502) || m.amount_clear {
		if m.amount_clear {
			ui.text_set(&m.amount, "")
			m.amount_clear = false
		}
	}
}

page_chips :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 4)
	defer ui.close(&col)
	section(gtx, "Chips", "32dp, corner 8, label-large, in a 48dp target; outline-variant edge unless elevated or selected")
	state_header(gtx)
	NAMES := [?]string {
		"Assist",
		"Assist, elevated",
		"Filter",
		"Filter, selected",
		"Filter, elevated",
		"Elevated, selected",
		"Filter, morph",
		"Morph, selected",
		"Input",
		"Input, selected",
		"Input, avatar",
		"Suggestion",
		"Suggestion, elev.",
	}
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: m3.Interaction, key: u64) {
			off, on := false, true
			switch key / 16 - 1 {
			case 0:
				m3.chip(gtx, "Assist", .Assist, leading = .Event, state = st, key = key)
			case 1:
				m3.chip(gtx, "Assist", .Assist, leading = .Event, elevated = true, state = st, key = key)
			case 2:
				m3.chip(gtx, "Filter", .Filter, &off, state = st, key = key)
			case 3:
				m3.chip(gtx, "Filter", .Filter, &on, state = st, key = key)
			case 4:
				m3.chip(gtx, "Filter", .Filter, &off, trailing = .Arrow_Drop_Down, elevated = true, state = st, key = key)
			case 5:
				m3.chip(gtx, "Filter", .Filter, &on, trailing = .Arrow_Drop_Down, elevated = true, state = st, key = key)
			case 6:
				m3.chip(gtx, "Filter", .Filter, &off, shape_morph = true, state = st, key = key)
			case 7:
				m3.chip(gtx, "Filter", .Filter, &on, shape_morph = true, state = st, key = key)
			case 8:
				m3.chip(gtx, "Input", .Input, &off, state = st, key = key)
			case 9:
				m3.chip(gtx, "Input", .Input, &on, leading = .Mail, state = st, key = key)
			case 10:
				m3.chip(gtx, "Input", .Input, &off, avatar = .Account_Circle, state = st, key = key)
			case 11:
				m3.chip(gtx, "Suggestion", .Suggestion, state = st, key = key)
			case 12:
				m3.chip(gtx, "Suggestion", .Suggestion, leading = .Bolt, elevated = true, state = st, key = key)
			}
		}
		state_row(gtx, m, n, cell, u64(i + 1))
	}
	section(gtx, "Dragged", "every kind lifts to 8dp while dragged")
	{
		r := ui.wrap_open(gtx, gap = 16, key = 200)
		defer ui.close(&r)
		off := false
		m3.chip(gtx, "Assist", .Assist, leading = .Event, state = .Dragged, key = 201)
		m3.chip(gtx, "Filter", .Filter, &off, state = .Dragged, key = 202)
		m3.chip(gtx, "Input", .Input, &off, state = .Dragged, key = 203)
		m3.chip(gtx, "Suggestion", .Suggestion, state = .Dragged, key = 204)
	}
	section(gtx, "Live", "filter chips toggle (the check slides in); the second row morphs its corners; input chips remove themselves")
	{
		r := ui.wrap_open(gtx, gap = 8, key = 300)
		defer ui.close(&r)
		FOOD := [?]string{"Breakfast", "Brunch", "Lunch", "Dinner", "Late night"}
		for f, i in FOOD {
			m3.chip(gtx, f, .Filter, &m.filters[i], key = u64(300 + i))
		}
	}
	{
		r := ui.wrap_open(gtx, gap = 8, key = 310)
		defer ui.close(&r)
		SIZES := [?]string{"Small", "Medium", "Large", "Extra large"}
		for f, i in SIZES {
			m3.chip(gtx, f, .Filter, &m.morph_filters[i], shape_morph = true, key = u64(310 + i))
		}
	}
	{
		r := ui.wrap_open(gtx, gap = 8, key = 320)
		defer ui.close(&r)
		PEOPLE := [?]string{"Ali", "Sandra", "Trevor", "Britta"}
		for name, i in PEOPLE {
			if m.inputs[i] {
				continue
			}
			m3.chip(gtx, name, .Input, &m.input_sel[i], avatar = .Account_Circle, removed = &m.inputs[i], shape_morph = i % 2 == 1, key = u64(320 + i))
		}
		if m3.chip(gtx, "Reset", .Assist, leading = .Refresh, elevated = true, key = 330) {
			m.inputs = {}
		}
	}
	{
		r := ui.wrap_open(gtx, gap = 8, key = 340)
		defer ui.close(&r)
		HINTS := [?]string{"Sounds good", "On my way", "Call me"}
		for h, i in HINTS {
			if m3.chip(gtx, h, .Suggestion, key = u64(340 + i)) {
				m.suggestion = h
			}
		}
		base.label(gtx, m.suggestion == "" ? "" : fmt.tprintf("Sent: %s", m.suggestion), {color = m3.scheme()[.On_Surface_Variant]})
	}
}

DESTINATIONS := [?]m3.Nav_Item {
	{label = "Mail", icon = .Mail, active_icon = .Mail_Fill1, badge = "3"},
	{label = "Chat", icon = .Chat_Bubble, active_icon = .Chat_Bubble_Fill1, badge = " "},
	{label = "Rooms", icon = .Home, active_icon = .Home_Fill1},
	{label = "Meet", icon = .Photo, active_icon = .Photo_Fill1},
}
