package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/fluent"

// The dates: calendar, date picker and time picker, on the fluent-kit's
// calendar.json, date-picker.json and time-picker.json.

// TODAY is fixed rather than read from the clock, so -png renders are
// reproducible.
TODAY :: fluent.Date{2026, 9, 28}

// DATE_CELL_W is a state cell wide enough for a date picker's input.
DATE_CELL_W :: f32(210)

// MARKED are the days the live calendar marks with a dot.
MARKED := [?]fluent.Date{{2026, 9, 3}, {2026, 9, 14}, {2026, 9, 28}}

page_calendar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Day grid and month picker", "440px: 28px cells with 24px buttons, a 20px brand disc for today, a 4px dot on marked days; the grid slides 20px on navigation over durationSlower")
	{
		r := ui.wrap_open(gtx, gap = 24, line_gap = 16)
		defer ui.close(&r)
		if fluent.calendar(gtx, &m.cal_selected, &m.cal_view, TODAY, MARKED[:], highlight_current_month = true, highlight_selected_month = true).picked {
			m.cal_picks += 1
		}
		picked := m.cal_selected.year != 0 ? fluent.format_date(m.cal_selected, context.temp_allocator) : "none"
		fluent.label(gtx, fmt.tprintf("Selected: %s (%d picks)", picked, m.cal_picks))
	}
	kitchen.section(gtx, "Day grid alone", "220px; the header names the month and only the arrows navigate")
	fluent.calendar(gtx, &m.cal_selected2, &m.cal_view2, TODAY, month_picker = .None, go_today = false, key = 1)
	kitchen.section(gtx, "States", "a forced state paints one day in it; disabled greys the whole calendar; days outside September 7 to 25 take no pointer here")
	{
		r := ui.wrap_open(gtx, gap = 24, line_gap = 16)
		defer ui.close(&r)
		STATES := [?]fluent.Interaction{.Hovered, .Focused, .Pressed, .Disabled}
		for st, i in STATES {
			c := ui.column_open(gtx, gap = 4, key = u64(10 + i))
			fluent.label(gtx, kitchen.STATE_NAMES[i + 1], size = .Small, key = u64(30 + i))
			sel := fluent.Date{2026, 9, 16}
			view := fluent.Date{2026, 9, 1}
			fluent.calendar(gtx, &sel, &view, TODAY, month_picker = .None, go_today = false, min_date = {2026, 9, 7}, max_date = {2026, 9, 25}, state = st, key = u64(20 + i))
			ui.close(&c)
		}
	}
}

page_date_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	NAMES := [?]string{"Outline", "Underline", "Filled lighter"}
	kitchen.section(gtx, "Appearances", "the Input with the calendar icon after; the calendar pops up below-start on a Neutral_Background1 surface with shadow16")
	kitchen.state_header(gtx, DATE_CELL_W)
	for n, i in NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			APP := [?]fluent.Date_Picker_Appearance{.Outline, .Underline, .Filled_Lighter}
			open := false
			sel: fluent.Date
			fluent.date_picker(gtx, &m.date_cells[key % 16 + 5 * (key / 16 - 1)], &sel, &open, TODAY, appearance = APP[key / 16 - 1], width = 190, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), DATE_CELL_W)
	}
	kitchen.section(gtx, "Live", "focus or Enter opens it; a pick, Escape or a press outside closes it; the second takes typed M/D/YYYY and validates on Enter and blur")
	r := ui.wrap_open(gtx, gap = 24, line_gap = 16, align = .Start)
	defer ui.close(&r)
	{
		c := ui.column_open(gtx, gap = 4, key = 100)
		defer ui.close(&c)
		fluent.label(gtx, "Start date")
		fluent.date_picker(gtx, &m.date_text, &m.date_value, &m.date_open, TODAY, width = 240, name = "Start date", key = 101)
	}
	{
		c := ui.column_open(gtx, gap = 4, key = 102)
		defer ui.close(&c)
		fluent.label(gtx, "Due date (typed)")
		_, v := fluent.date_picker(gtx, &m.due_text, &m.due_value, &m.due_open, TODAY, allow_text_input = true, required = true, min_date = TODAY, width = 240, name = "Due date", key = 103)
		if v != .Ok || m.due_check == .Ok {
			m.due_check = v
		}
		msg := ""
		switch m.due_check {
		case .Ok:
		case .Invalid_Input:
			msg = "Not a date: use M/D/YYYY"
		case .Out_Of_Bounds:
			msg = "Pick today or later"
		case .Required_Input:
			msg = "A due date is required"
		}
		if msg != "" {
			fluent.label(gtx, msg, size = .Small)
		}
	}
}

page_time_picker :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "States", "the Input with the chevron after; the list holds every 30 minutes from midnight, at most 416px tall")
	kitchen.state_header(gtx, DATE_CELL_W)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			open, valid := false, false
			t: fluent.Time
			fluent.time_picker(gtx, &m.time_cells[key % 16], &t, &valid, &open, width = 190, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Outline", cell, 1, DATE_CELL_W)
	}
	kitchen.section(gtx, "Live", "a list from 9 AM to 5 PM by 15 minutes; a 24-hour list; and freeform, which parses typed text on Enter and blur")
	r := ui.wrap_open(gtx, gap = 24, line_gap = 16, align = .Start)
	defer ui.close(&r)
	{
		c := ui.column_open(gtx, gap = 4, key = 100)
		defer ui.close(&c)
		fluent.label(gtx, "Meeting")
		fluent.time_picker(gtx, &m.time_text, &m.time_value, &m.time_valid, &m.time_open, start_hour = 9, end_hour = 17, increment = 15, window_h = m.window.y, width = 200, name = "Meeting", key = 101)
	}
	{
		c := ui.column_open(gtx, gap = 4, key = 102)
		defer ui.close(&c)
		fluent.label(gtx, "Departure (24-hour)")
		fluent.time_picker(gtx, &m.time24_text, &m.time24_value, &m.time24_valid, &m.time24_open, hour12 = false, window_h = m.window.y, width = 200, name = "Departure", key = 103)
	}
	{
		c := ui.column_open(gtx, gap = 4, key = 104)
		defer ui.close(&c)
		fluent.label(gtx, "Reminder (freeform)")
		_, err := fluent.time_picker(gtx, &m.free_text, &m.free_value, &m.free_valid, &m.free_open, freeform = true, window_h = m.window.y, width = 200, name = "Reminder", key = 105)
		if err != .None || m.free_valid {
			m.free_err = err
		}
		if m.free_err == .Invalid_Input {
			fluent.label(gtx, "Not a time: use h:mm AM", size = .Small)
		} else if m.free_valid {
			fluent.label(gtx, fmt.tprintf("Set for %s", fluent.format_time(m.free_value, allocator = context.temp_allocator)), size = .Small)
		}
	}
}
