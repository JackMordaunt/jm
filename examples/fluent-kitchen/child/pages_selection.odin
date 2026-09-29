package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"

// The form controls, on the fluent-kit's checkbox, radio-group, switch
// and slider specs.

page_checkbox :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Medium", "16px box in a 32px row; the label reads Foreground 3 unchecked, 1 checked; colours snap")
	state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			off := false
			fluent.checkbox(gtx, &off, "Option", state = st, key = key)
		}
		state_row(gtx, m, "Unchecked", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			on := true
			fluent.checkbox(gtx, &on, "Option", state = st, key = key)
		}
		state_row(gtx, m, "Checked", cell, 2)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			off := false
			fluent.checkbox(gtx, &off, "Option", mixed = true, state = st, key = key)
		}
		state_row(gtx, m, "Mixed", cell, 3)
	}
	section(gtx, "Large and circular", "20px box with a 16px glyph in a 36px row; circular rounds the box fully")
	state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			on := true
			fluent.checkbox(gtx, &on, "Option", size = .Large, state = st, key = key)
		}
		state_row(gtx, m, "Large", cell, 4)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			on := true
			fluent.checkbox(gtx, &on, "Option", circular = true, state = st, key = key)
		}
		state_row(gtx, m, "Circular", cell, 5)
	}
	section(gtx, "Live", "click, Tab and Space; the label may sit before the box")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	LABELS := [?]string{"Email me", "Text me", "Call me", "Write to me"}
	for l, i in LABELS {
		fluent.checkbox(gtx, &m.checks[i], l, side = i == 3 ? .Before : .After, key = u64(100 + i))
	}
	fluent.checkbox(gtx, &m.all, "All of them", mixed = m.all_mixed, key = 110)
	m.all_mixed = false
	n := 0
	for c in m.checks {
		if c {
			n += 1
		}
	}
	m.all_mixed = n > 0 && n < len(m.checks)
	m.all = n == len(m.checks)
}

page_radio :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Radio", "16px ring in a 32px row, a 10px brand dot when checked; the ring stays hollow")
	state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			ONE := [?]string{"Option"}
			none := -1
			fluent.radio_group(gtx, ONE[:], &none, state = st, key = key)
		}
		state_row(gtx, m, "Unchecked", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			ONE := [?]string{"Option"}
			first := 0
			fluent.radio_group(gtx, ONE[:], &first, state = st, key = key)
		}
		state_row(gtx, m, "Checked", cell, 2)
	}
	section(gtx, "Live", "click a row, or move the selection with the arrow keys once one has focus")
	base.label(gtx, "Vertical", {size = 12, color = fluent.color(.Neutral_Foreground2)})
	SIZES := [?]string{"Small", "Medium", "Large"}
	fluent.radio_group(gtx, SIZES[:], &m.radio, key = 100)
	base.label(gtx, "Horizontal", {size = 12, color = fluent.color(.Neutral_Foreground2)})
	SHAPES := [?]string{"Square", "Round", "Pill"}
	fluent.radio_group(gtx, SHAPES[:], &m.radio2, horizontal = true, key = 101)
}

page_switch :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Medium", "40 by 20px track in a 36px row; on fills brand and slides the thumb over durationNormal")
	state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			off := false
			fluent.toggle_switch(gtx, &off, "Off", state = st, key = key)
		}
		state_row(gtx, m, "Off", cell, 1)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			on := true
			fluent.toggle_switch(gtx, &on, "On", state = st, key = key)
		}
		state_row(gtx, m, "On", cell, 2)
	}
	section(gtx, "Small", "32 by 16px track in a 32px row")
	state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			on := true
			fluent.toggle_switch(gtx, &on, "On", size = .Small, state = st, key = key)
		}
		state_row(gtx, m, "Small", cell, 3)
	}
	section(gtx, "Live", "click, or Tab and Space; the thumb eases across")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	LABELS := [?]string{"Wi-Fi", "Bluetooth", "Aeroplane mode"}
	for l, i in LABELS {
		fluent.toggle_switch(gtx, &m.switches[i], l, side = i == 2 ? .Before : .After, key = u64(100 + i))
	}
}

page_slider :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Medium", "20px thumb with a Background 1 ring, a 4px rail; a step draws ticks; the fill and thumb step to hover and pressed")
	state_header(gtx, 150)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			v: f32 = 40
			fluent.slider(gtx, &v, state = st, key = key)
		}
		state_row(gtx, m, "Continuous", cell, 1, 150)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			v: f32 = 60
			fluent.slider(gtx, &v, 0, 100, 20, state = st, key = key)
		}
		state_row(gtx, m, "Stepped", cell, 2, 150)
	}
	section(gtx, "Small", "16px thumb, 2px rail, 24px row")
	state_header(gtx, 150)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			v: f32 = 40
			fluent.slider(gtx, &v, size = .Small, state = st, key = key)
		}
		state_row(gtx, m, "Small", cell, 3, 150)
	}
	section(gtx, "Live", "press to jump, drag, or use the arrow, Page, Home and End keys")
	r := ui.row_open(gtx, gap = 24, align = .Center)
	defer ui.close(&r)
	fluent.slider(gtx, &m.volume, 0, 100, 0, 240, name = "Volume", key = 100)
	base.label(gtx, fmt.tprintf("%.0f", m.volume), {color = fluent.color(.Neutral_Foreground2)})
	fluent.slider(gtx, &m.steps, 0, 50, 10, 200, name = "Steps", key = 101)
	base.label(gtx, fmt.tprintf("%.0f", m.steps), {color = fluent.color(.Neutral_Foreground2)})
	fluent.slider(gtx, &m.level, 0, 1, 0, 160, vertical = true, name = "Level", key = 102)
}
