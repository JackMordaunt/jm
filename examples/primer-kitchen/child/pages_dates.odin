package main

import "jm:ui"
import "jm:ui/primer"

import "../../kitchen"

// Dates is the date pickers' demo state. TODAY is fixed, so a rendered
// page reads the same whatever day it is drawn.
Dates :: struct {
	due, start, review: primer.Date,
	start_text:         ui.Text_State,
	window, sales:      primer.Date_Range,
	seeded:             bool,
}

@(private = "file")
TODAY :: primer.Date{2026, 10, 5}

@(private = "file")
dates_seed :: proc(d: ^Dates) {
	if d.seeded {
		return
	}
	d.seeded = true
	d.due = {2026, 10, 22}
	d.window = {{2026, 10, 6}, {2026, 10, 16}}
}

// weekend reports whether a date falls on a Saturday or Sunday.
@(private = "file")
weekend :: proc(d: primer.Date, user: rawptr) -> bool {
	wd := primer.weekday(d)
	return wd == 0 || wd == 6
}

DATE_CELL_W :: f32(190)

page_date_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	d := &m.dates
	dates_seed(d)
	ui.column(gtx, gap = 10)
	kitchen.section(
		gtx,
		"Anchors",
		"a button naming the date, or the placeholder, and an icon button",
	)
	kitchen.state_header(gtx, DATE_CELL_W)
	rows := [?]string{"Date", "Placeholder", "Icon only"}
	for n, i in rows {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			due, none := primer.Date{2026, 10, 14}, primer.Date{}
			switch key / 16 - 1 {
			case 0:
				primer.date_picker(gtx, &due, TODAY, state = st, key = key)
			case 1:
				primer.date_picker(gtx, &none, TODAY, state = st, key = key)
			case 2:
				primer.date_picker(gtx, &due, TODAY, anchor = .Icon_Only, state = st, key = key)
			}
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), DATE_CELL_W)
	}
	kitchen.section(
		gtx,
		"Live",
		"arrows move a day or a week, Page Up and Down a month (Shift: a year), " +
		"Home and End the week; Enter picks, Escape closes",
	)
	ui.wrap(gtx, gap = 24, align = .Start)
	{
		primer.form_control(gtx, "Due date", caption = "Today and Clear in the footer")
		primer.date_picker(gtx, &d.due, TODAY, clear_button = true, name = "Due date")
	}
	{
		primer.form_control(
			gtx,
			"Start date",
			caption = "Type MM/DD/YYYY, YYYY-MM-DD or Oct 5, 2026",
		)
		primer.date_picker(
			gtx,
			&d.start,
			TODAY,
			{min_date = {2026, 1, 1}, max_date = {2026, 12, 31}},
			anchor = .Input,
			text = &d.start_text,
		)
	}
	{
		primer.form_control(
			gtx,
			"Review day",
			caption = "Weekdays this month, Monday first, Apply to keep",
		)
		o := primer.Calendar_Options {
			min_date   = {2026, 10, 1},
			max_date   = {2026, 10, 31},
			disabled   = weekend,
			week_start = 1,
		}
		primer.date_picker(gtx, &d.review, TODAY, o, confirm = true, name = "Review day")
	}
}

page_date_range_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	d := &m.dates
	dates_seed(d)
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Anchor", "the range, or the placeholder")
	kitchen.state_header(gtx, DATE_CELL_W)
	rows := [?]string{"Range", "Placeholder"}
	for n, i in rows {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			some, none := primer.Date_Range{{2026, 10, 1}, {2026, 10, 5}}, primer.Date_Range{}
			r := &some if key / 16 == 1 else &none
			primer.date_range_picker(gtx, r, TODAY, size = .Small, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), DATE_CELL_W)
	}
	presets := primer.standard_presets(TODAY)
	kitchen.section(
		gtx,
		"Live",
		"two picks make a range, the pointer previews it; presets set it at once",
	)
	ui.wrap(gtx, gap = 24, align = .Start)
	{
		primer.form_control(gtx, "Window", caption = "Two months, Apply to keep, half-open")
		primer.date_range_picker(
			gtx,
			&d.window,
			TODAY,
			presets[:],
			{months = 2},
			bounds = .Half_Open,
			confirm = true,
			name = "Window",
		)
	}
	{
		primer.form_control(gtx, "Sales", caption = "One month; a pick or preset commits")
		primer.date_range_picker(
			gtx,
			&d.sales,
			TODAY,
			presets[:],
			clear = "Month to date",
			placeholder = "Month to date",
			name = "Sales",
		)
	}
}
