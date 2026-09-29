package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of calendar, date_picker and time_picker, driven through
// ui.Probe by their tags, and the date and time arithmetic under them.

@(private = "file")
TODAY :: Date{2026, 9, 28}

@(test)
test_date_arithmetic :: proc(t: ^testing.T) {
	testing.expect_value(t, weekday({2026, 9, 1}), 2) // a Tuesday
	testing.expect_value(t, weekday({2000, 1, 1}), 6) // a Saturday
	testing.expect_value(t, weekday({2024, 2, 29}), 4) // a Thursday
	testing.expect_value(t, days_in_month(2024, 2), 29)
	testing.expect_value(t, days_in_month(1900, 2), 28) // a century, not leap
	testing.expect_value(t, days_in_month(2000, 2), 29) // a 400th year, leap
	testing.expect_value(t, days_in_month(2026, 9), 30)
	testing.expect_value(t, date_add_days({2026, 12, 30}, 3), Date{2027, 1, 2})
	testing.expect_value(t, date_add_days({2024, 3, 1}, -1), Date{2024, 2, 29})
	testing.expect_value(t, date_add_months({2026, 1, 31}, 1), Date{2026, 2, 28})
	testing.expect_value(t, date_add_months({2026, 1, 15}, -1), Date{2025, 12, 15})
	d, ok := parse_date("9/28/2026")
	testing.expect(t, ok)
	testing.expect_value(t, d, TODAY)
	d, ok = parse_date("2026-02-29")
	testing.expect(t, !ok) // not a leap year
	testing.expect_value(t, format_date(TODAY, context.temp_allocator), "Mon Sep 28 2026")
	free_all(context.temp_allocator)
}

@(test)
test_time_options_and_parsing :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, len(time_options(allocator = context.temp_allocator)), 48) // 0 to 24 by 30
	testing.expect_value(t, len(time_options(9, 17, 15, context.temp_allocator)), 32)
	wrap := time_options(22, 2, 60, context.temp_allocator) // wraps past midnight
	testing.expect_value(t, len(wrap), 4)
	testing.expect_value(t, wrap[3], Time{1, 0, 0})
	testing.expect_value(t, len(time_options(0, 24, 0, context.temp_allocator)), 0)
	tm, ok := parse_time("9:30 AM")
	testing.expect(t, ok)
	testing.expect_value(t, tm, Time{9, 30, 0})
	tm, ok = parse_time("12:05 am")
	testing.expect_value(t, tm, Time{0, 5, 0})
	tm, ok = parse_time("12:00 PM")
	testing.expect_value(t, tm, Time{12, 0, 0})
	_, ok = parse_time("13:00 PM")
	testing.expect(t, !ok)
	_, ok = parse_time("9:30") // a 12-hour cycle needs a meridiem
	testing.expect(t, !ok)
	tm, ok = parse_time("17:45", hour12 = false)
	testing.expect(t, ok)
	testing.expect_value(t, tm, Time{17, 45, 0})
	tm, ok = parse_time("17:45:09", hour12 = false, seconds = true)
	testing.expect_value(t, tm, Time{17, 45, 9})
	testing.expect_value(t, format_time({9, 30, 0}, allocator = context.temp_allocator), "9:30 AM")
	testing.expect_value(t, format_time({0, 5, 0}, allocator = context.temp_allocator), "12:05 AM")
	testing.expect_value(t, format_time({17, 45, 0}, false, allocator = context.temp_allocator), "17:45")
}

@(private = "file")
Dates_Model :: struct {
	selected, view: Date,
	picked:         int,
	text:           ui.Text_State,
	date:           Date,
	open:           bool,
	time_text:      ui.Text_State,
	time:           Time,
	time_valid:     bool,
	time_open:      bool,
}

@(private = "file")
cal_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Dates_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if calendar(gtx, &m.selected, &m.view, TODAY).picked {
		m.picked += 1
	}
}

@(test)
test_calendar_picks_a_day_and_navigates_months :: proc(t: ^testing.T) {
	m: Dates_Model
	p: ui.Probe
	ui.probe_init(&p, cal_view, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, m.view, Date{2026, 9, 1}) // today's month
	testing.expect(t, ui.probe_click(&p, "15 Sep 2026"))
	testing.expect_value(t, m.selected, Date{2026, 9, 15})
	testing.expect_value(t, m.picked, 1)
	// A day of the next month shown in the grid picks that day, and the
	// grid follows it there.
	testing.expect(t, ui.probe_click(&p, "2 Oct 2026"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.selected, Date{2026, 10, 2})
	testing.expect_value(t, m.view, Date{2026, 10, 1})
	testing.expect(t, ui.probe_click(&p, "Next month"))
	testing.expect_value(t, m.view, Date{2026, 11, 1})
	testing.expect(t, ui.probe_click(&p, "Previous month"))
	testing.expect(t, ui.probe_click(&p, "Previous month"))
	testing.expect(t, ui.probe_click(&p, "Previous month"))
	testing.expect_value(t, m.view, Date{2026, 8, 1})
	// The month picker beside it jumps the grid; the year button pages years.
	testing.expect(t, ui.probe_click(&p, "Mar"))
	testing.expect_value(t, m.view, Date{2026, 3, 1})
	testing.expect(t, p.wants_frame) // March is a week shorter than August: lay out again
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Go to today"))
	testing.expect_value(t, m.view, Date{2026, 9, 1})
	ui.probe_advance(&p, 30, 0.016) // the grid's slide settles
	// A focused day's arrow keys move the cursor, and Enter picks it.
	testing.expect(t, ui.probe_click(&p, "10 Sep 2026"))
	ui.probe_key(&p, .Right)
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.selected, Date{2026, 9, 18})
	// A day cell is 28px square.
	cell := ui.probe_bounds(&p, "18 Sep 2026")
	testing.expect_value(t, cell.w, 28)
	testing.expect_value(t, cell.h, 28)
}

@(private = "file")
picker_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Dates_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	date_picker(gtx, &m.text, &m.date, &m.open, TODAY, name = "Start date")
	ui.spacer(gtx, 400)
	time_picker(gtx, &m.time_text, &m.time, &m.time_valid, &m.time_open, name = "Start time", key = 1)
}

@(test)
test_date_picker_opens_and_a_pick_closes_it :: proc(t: ^testing.T) {
	m: Dates_Model
	defer ui.text_destroy(&m.text)
	defer ui.text_destroy(&m.time_text)
	p: ui.Probe
	ui.probe_init(&p, picker_view, &m, {600, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	_, shown := ui.probe_find(&p, "15 Sep 2026")
	testing.expect(t, !shown)
	testing.expect(t, ui.probe_click(&p, "Start date")) // focus opens it
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	testing.expect(t, ui.probe_click(&p, "15 Sep 2026"))
	ui.probe_frame(&p)
	testing.expect(t, !m.open)
	testing.expect_value(t, m.date, Date{2026, 9, 15})
	testing.expect_value(t, ui.text_string(&m.text), "Tue Sep 15 2026")
}

@(test)
test_time_picker_lists_times_and_picks_one :: proc(t: ^testing.T) {
	m: Dates_Model
	defer ui.text_destroy(&m.text)
	defer ui.text_destroy(&m.time_text)
	p: ui.Probe
	ui.probe_init(&p, picker_view, &m, {600, 1400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Start time"))
	ui.probe_frame(&p)
	testing.expect(t, m.time_open)
	testing.expect(t, ui.probe_click(&p, "12:30 AM"))
	ui.probe_frame(&p)
	testing.expect(t, !m.time_open)
	testing.expect(t, m.time_valid)
	testing.expect_value(t, m.time, Time{0, 30, 0})
	testing.expect_value(t, ui.text_string(&m.time_text), "12:30 AM")
}

@(private = "file")
freeform_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Dates_Model)(user)
	time_picker(gtx, &m.time_text, &m.time, &m.time_valid, &m.time_open, freeform = true, name = "Free time")
}

@(test)
test_time_picker_freeform_parses_on_enter :: proc(t: ^testing.T) {
	m: Dates_Model
	defer ui.text_destroy(&m.time_text)
	p: ui.Probe
	ui.probe_init(&p, freeform_view, &m, {600, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Free time"))
	ui.probe_type(&p, "9:30 AM")
	ui.probe_key(&p, .Enter)
	testing.expect(t, m.time_valid)
	testing.expect_value(t, m.time, Time{9, 30, 0})
	testing.expect(t, !m.time_open)
}

// DATE_BOTTOM_WINDOW is a short window whose last 40px holds a date picker.
@(private = "file")
DATE_BOTTOM_WINDOW :: ops.Size{600, 500}

@(private = "file")
bottom_picker_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Dates_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	ui.spacer(gtx, DATE_BOTTOM_WINDOW.y - 40)
	date_picker(gtx, &m.text, &m.date, &m.open, TODAY, name = "Start date")
}

@(test)
test_date_picker_near_the_bottom_opens_above_its_input :: proc(t: ^testing.T) {
	m: Dates_Model
	defer ui.text_destroy(&m.text)
	defer ui.text_destroy(&m.time_text)
	p: ui.Probe
	ui.probe_init(&p, bottom_picker_view, &m, DATE_BOTTOM_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Start date"))
	ui.probe_frame(&p)
	testing.expect(t, m.open)
	input := ui.probe_bounds(&p, "Start date")
	for name in ([]string{"1 Sep 2026", "30 Sep 2026"}) {
		r := ui.probe_bounds(&p, name)
		testing.expectf(t, r.h > 0 && r.y >= 0 && r.y + r.h <= DATE_BOTTOM_WINDOW.y, "%s at %v leaves the window", name, r)
		testing.expectf(t, r.y + r.h <= input.y, "%s at %v is not above the input at %v", name, r, input)
	}
	testing.expect(t, ui.probe_click(&p, "15 Sep 2026"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.date, Date{2026, 9, 15})
}
