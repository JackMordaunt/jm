package primer

import "core:strings"
import "core:testing"
import "jm:ui"

// The date pickers: the calendar arithmetic, what can be picked, range
// order, presets, the typed input, and through ui.Probe by tags the
// keyboard model, Escape and focus going back to the anchor.

@(private = "file")
TODAY :: Date{2026, 10, 5}

@(private = "file")
no_weekends :: proc(d: Date, user: rawptr) -> bool {
	wd := weekday(d)
	return wd == 0 || wd == 6
}

@(test)
test_bounds_and_the_predicate_decide_what_can_be_picked :: proc(t: ^testing.T) {
	o := Calendar_Options {
		min_date = {2026, 10, 2},
		max_date = {2026, 10, 20},
		disabled = no_weekends,
	}
	testing.expect(t, date_selectable(o, {2026, 10, 2})) // the bounds are included
	testing.expect(t, date_selectable(o, {2026, 10, 20}))
	testing.expect(t, !date_selectable(o, {2026, 10, 1}))
	testing.expect(t, !date_selectable(o, {2026, 10, 21}))
	testing.expect(t, !date_selectable(o, {2026, 10, 10})) // a Saturday
	// A move onto a day that cannot be picked goes on its way.
	d, ok := calendar_step({2026, 10, 9}, .Right, {}, o) // Friday to Monday
	testing.expect(t, ok)
	testing.expect_value(t, d, Date{2026, 10, 12})
	d, ok = calendar_step({2026, 10, 12}, .Left, {}, o)
	testing.expect_value(t, d, Date{2026, 10, 9})
	// Home and End look back towards the cursor.
	d, _ = calendar_step({2026, 10, 7}, .Home, {}, o)
	testing.expect_value(t, d, Date{2026, 10, 5})
	d, _ = calendar_step({2026, 10, 7}, .End, {}, o)
	testing.expect_value(t, d, Date{2026, 10, 9})
	// A move past a bound stops at the nearest day inside it.
	d, ok = calendar_step({2026, 10, 2}, .Up, {}, o)
	testing.expect_value(t, d, Date{2026, 10, 2}) // stays on the bound
	d, ok = calendar_step({2026, 10, 16}, .Page_Down, {}, o)
	testing.expect(t, ok)
	testing.expect_value(t, d, Date{2026, 10, 20})
	// Nothing to pick in a direction: stay.
	none := Calendar_Options {
		min_date = {2026, 10, 10},
		max_date = {2026, 10, 11},
		disabled = no_weekends,
	}
	_, ok = nearest_selectable({2026, 10, 10}, 1, none)
	testing.expect(t, !ok)
}

@(test)
test_today_is_a_real_date :: proc(t: ^testing.T) {
	testing.expect(t, date_valid(date_today()))
}

@(test)
test_the_keys_move_by_day_week_month_and_year :: proc(t: ^testing.T) {
	o := Calendar_Options{}
	step :: proc(d: Date, k: ui.Key, mods: ui.Mods = {}) -> Date {
		r, _ := calendar_step(d, k, mods, {})
		return r
	}
	_ = o
	testing.expect_value(t, step({2026, 10, 31}, .Right), Date{2026, 11, 1})
	testing.expect_value(t, step({2026, 10, 1}, .Left), Date{2026, 9, 30})
	testing.expect_value(t, step({2026, 10, 29}, .Down), Date{2026, 11, 5})
	testing.expect_value(t, step({2026, 10, 3}, .Up), Date{2026, 9, 26})
	testing.expect_value(t, step({2026, 10, 31}, .Page_Down), Date{2026, 11, 30})
	testing.expect_value(t, step({2026, 3, 31}, .Page_Up), Date{2026, 2, 28})
	testing.expect_value(t, step({2024, 2, 29}, .Page_Down, {.Shift}), Date{2025, 2, 28})
	testing.expect_value(t, step({2026, 10, 7}, .Home), Date{2026, 10, 4})
	testing.expect_value(t, step({2026, 10, 7}, .End), Date{2026, 10, 10})
	_, ok := calendar_step(TODAY, .Enter, {}, {})
	testing.expect(t, !ok)
}

@(test)
test_a_range_is_ordered_whichever_end_is_picked_first :: proc(t: ^testing.T) {
	cal: Calendar
	r: Date_Range
	testing.expect(t, !range_pick(&cal, &r, {2026, 10, 20}))
	testing.expect_value(t, cal.anchor, Date{2026, 10, 20})
	testing.expect(t, range_pick(&cal, &r, {2026, 10, 3})) // the end before the start
	testing.expect_value(t, r, Date_Range{{2026, 10, 3}, {2026, 10, 20}})
	testing.expect_value(t, cal.anchor, Date{})
	testing.expect(t, !range_pick(&cal, &r, {2026, 10, 7}))
	testing.expect(t, range_pick(&cal, &r, {2026, 10, 7})) // one day
	testing.expect_value(t, r, Date_Range{{2026, 10, 7}, {2026, 10, 7}})
}

@(test)
test_half_open_bounds_end_the_day_after :: proc(t: ^testing.T) {
	shown := Date_Range{{2026, 10, 1}, {2026, 10, 31}}
	stored := range_stored(shown, .Half_Open)
	testing.expect_value(t, stored, Date_Range{{2026, 10, 1}, {2026, 11, 1}})
	testing.expect_value(t, range_shown(stored, .Half_Open), shown)
	testing.expect_value(t, range_stored(shown, .Inclusive), shown)
	testing.expect_value(t, range_stored({}, .Half_Open), Date_Range{})
}

@(test)
test_the_standard_presets_are_relative_to_today :: proc(t: ^testing.T) {
	p := standard_presets({2026, 3, 15})
	testing.expect_value(t, p[0].range, Date_Range{{2026, 3, 15}, {2026, 3, 15}})
	// 7 days, today included.
	testing.expect_value(t, p[1].range, Date_Range{{2026, 3, 9}, {2026, 3, 15}})
	// 30 days, across February.
	testing.expect_value(t, p[2].range, Date_Range{{2026, 2, 14}, {2026, 3, 15}})
	testing.expect_value(t, p[3].range, Date_Range{{2026, 3, 1}, {2026, 3, 15}})
	testing.expect_value(t, p[4].range, Date_Range{{2026, 2, 1}, {2026, 2, 28}})
	testing.expect_value(t, p[5].range, Date_Range{{2026, 1, 1}, {2026, 3, 15}})
	jan := standard_presets({2026, 1, 10})
	// Last month is last year's.
	testing.expect_value(t, jan[4].range, Date_Range{{2025, 12, 1}, {2025, 12, 31}})
	testing.expect_value(t, jan[4].label, "Last month")
}

@(test)
test_typed_dates_parse_in_the_accepted_formats :: proc(t: ^testing.T) {
	cases := []struct {
		text: string,
		want: Date,
		ok:   bool,
	} {
		{"10/05/2026", {2026, 10, 5}, true},
		{"10/5/2026", {2026, 10, 5}, true},
		{" 2026-10-05 ", {2026, 10, 5}, true},
		{"Oct 5, 2026", {2026, 10, 5}, true},
		{"October 5, 2026", {2026, 10, 5}, true},
		{"02/29/2024", {2024, 2, 29}, true},
		{"02/29/2026", {}, false}, // no such day
		{"13/01/2026", {}, false},
		{"10/5/26", {}, false}, // a year is four digits
		{"10/05/2026x", {}, false},
		{"tomorrow", {}, false},
	}
	for c in cases {
		d, ok := parse_typed_date(c.text)
		testing.expectf(t, ok == c.ok && d == c.want, "%q: got %v %v", c.text, d, ok)
	}
	o := Calendar_Options {
		min_date = {2026, 10, 1},
		max_date = {2026, 10, 31},
		disabled = no_weekends,
	}
	_, e := date_check("", o)
	testing.expect_value(t, e, Date_Error.None)
	_, e = date_check("1/2", o)
	testing.expect_value(t, e, Date_Error.Format)
	_, e = date_check("09/30/2026", o)
	testing.expect_value(t, e, Date_Error.Before_Min)
	_, e = date_check("11/02/2026", o)
	testing.expect_value(t, e, Date_Error.After_Max)
	_, e = date_check("10/10/2026", o)
	testing.expect_value(t, e, Date_Error.Unavailable)
	testing.expect_value(
		t,
		date_error_message(.Before_Min, o, context.temp_allocator),
		"Choose a date on or after Oct 1, 2026",
	)
	testing.expect_value(t, format_typed_date({2026, 1, 2}, context.temp_allocator), "01/02/2026")
	testing.expect_value(
		t,
		format_range({{2026, 10, 1}, {2026, 10, 5}}, context.temp_allocator),
		"Oct 1, 2026 – Oct 5, 2026",
	)
	free_all(context.temp_allocator)
}

// Through a probe.

@(private = "file")
Picker_Model :: struct {
	value:   Date,
	range:   Date_Range,
	text:    ui.Text_State,
	o:       Calendar_Options,
	anchor:  Date_Picker_Anchor,
	confirm: bool,
	ranged:  bool,
	bounds:  Range_Bounds,
	presets: [6]Date_Preset,
	changed: int,
	inputs:  Range_Inputs,
	typing:  bool, // the range picker shows its inputs
	reserve: bool, // the single picker reserves its anchor's width
}

@(private = "file")
picker_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Picker_Model)(user)
	col := ui.column_open(gtx, gap = 8, align = .Start)
	defer ui.close(&col)
	button(gtx, "Before")
	switch {
	case m.ranged:
		inputs := &m.inputs if m.typing else nil
		r := date_range_picker(
			gtx,
			&m.range,
			TODAY,
			m.presets[:],
			m.o,
			m.bounds,
			m.confirm,
			inputs = inputs,
		)
		if r {
			m.changed += 1
		}
	case m.anchor == .Input:
		if form_control(gtx, "Start date") {
			if date_picker(gtx, &m.value, TODAY, m.o, .Input, &m.text, confirm = m.confirm) {
				m.changed += 1
			}
		}
	case:
		if date_picker(
			gtx,
			&m.value,
			TODAY,
			m.o,
			m.anchor,
			confirm = m.confirm,
			clear_button = true,
			reserve = m.reserve,
		) {
			m.changed += 1
		}
	}
	button(gtx, "After")
}

@(private = "file")
picker_probe :: proc(p: ^ui.Probe, m: ^Picker_Model) {
	m.presets = standard_presets(TODAY)
	ui.probe_init(p, picker_view, m, {900, 700}, allocator = context.temp_allocator)
}

// day is a day cell's tag: its full date.
@(private = "file")
day :: proc(d: Date) -> string {
	return day_label(d, context.temp_allocator)
}

@(test)
test_a_date_picker_opens_on_the_date_and_a_pick_closes_it :: proc(t: ^testing.T) {
	m := Picker_Model {
		value = {2026, 10, 20},
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Oct 20, 2026"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, day({2026, 10, 1})))
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 10, 20})) // focus lands on the date
	testing.expect(
		t,
		strings.contains(
			ui.probe_semantics(&p, context.temp_allocator),
			"grid cell \"Monday, October 5, 2026\" current date",
		),
	)
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 22})))
	ui.probe_frame(&p)
	testing.expect_value(t, m.value, Date{2026, 10, 22})
	testing.expect_value(t, m.changed, 1)
	testing.expect(t, !ui.probe_tagged(&p, day({2026, 10, 1})))
	testing.expect_value(t, ui.probe_focus_name(&p), "Oct 22, 2026") // back on the anchor
}

@(test)
test_the_keyboard_walks_days_across_months_and_escape_returns_focus :: proc(t: ^testing.T) {
	m := Picker_Model {
		value = {2026, 10, 30},
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Before"))
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "Oct 30, 2026")
	ui.probe_key(&p, .Down) // ArrowDown on the anchor opens it
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 10, 30}))
	ui.probe_key(&p, .Right)
	ui.probe_key(&p, .Right) // past the month's end
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 11, 1}))
	testing.expect(t, !ui.probe_tagged(&p, day({2026, 10, 30}))) // November shows now
	ui.probe_key(&p, .Up)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 10, 25}))
	ui.probe_key(&p, .Page_Down)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 11, 25}))
	ui.probe_key(&p, .Page_Up, {.Shift})
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), day({2025, 11, 25}))
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	// Saturday ends a Sunday week.
	testing.expect_value(t, ui.probe_focus_name(&p), day({2025, 11, 29}))
	// The grid is one Tab stop: Tab leaves it for the footer.
	ui.probe_key(&p, .Tab)
	testing.expect(
		t,
		strings.has_prefix(ui.probe_focus_name(&p), "Today") || ui.probe_focus_name(&p) == "Clear",
		ui.probe_focus_name(&p),
	)
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, ui.probe_focus_name(&p), day({2025, 11, 29}))

	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, day({2025, 11, 29})))
	// Closed, focus back, no change.
	testing.expect_value(t, ui.probe_focus_name(&p), "Oct 30, 2026")
	testing.expect_value(t, m.value, Date{2026, 10, 30})
	testing.expect_value(t, m.changed, 0)

	// Enter picks the cursor's day.
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Left)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect_value(t, m.value, Date{2026, 10, 29})
}

@(test)
test_days_that_cannot_be_picked_ignore_the_pointer_and_the_keys :: proc(t: ^testing.T) {
	m := Picker_Model {
		value = {2026, 10, 9},
		o = {min_date = {2026, 10, 2}, disabled = no_weekends},
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Oct 9, 2026"))
	// A Saturday: the press lands, nothing picks.
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 10})))
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 1}))) // before min_date
	ui.probe_frame(&p)
	testing.expect_value(t, m.changed, 0)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(
		t,
		strings.contains(sem, "grid cell \"Saturday, October 10, 2026\" disabled"),
		sem,
	)
	testing.expect(t, strings.contains(sem, "grid cell \"Friday, October 9, 2026\" selected"), sem)
	testing.expect(t, strings.contains(sem, "column header \"Sunday\""), sem)
	ui.probe_key(&p, .Tab, {.Shift})
	ui.probe_key(&p, .Tab) // back into the grid at its cursor
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 10, 9}))
	ui.probe_key(&p, .Right) // over the weekend
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 10, 12}))
	ui.probe_key(&p, .Page_Up) // to Sep 12, before min_date: the bound's nearest day
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 10, 2}))
	// The previous month holds nothing to pick, so its chevron is disabled.
	testing.expect(
		t,
		strings.contains(
			ui.probe_semantics(&p, context.temp_allocator),
			"button \"Previous month\" disabled",
		),
	)
}

@(test)
test_a_range_takes_two_picks_in_either_order :: proc(t: ^testing.T) {
	m := Picker_Model {
		ranged = true,
		bounds = .Half_Open,
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Choose dates..."))
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 14})))
	testing.expect(t, ui.probe_tagged(&p, "Choose an end date"))
	testing.expect_value(t, m.changed, 0)
	// The pointer previews the range: the days between read as selected.
	c, ok := ui.probe_center(&p, day({2026, 10, 9}))
	testing.expect(t, ok)
	ui.probe_move(&p, c.x, c.y)
	ui.probe_frame(&p)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(
		t,
		strings.contains(sem, "grid cell \"Monday, October 12, 2026\" selected"),
		sem,
	)
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 9}))) // the end before the start
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, Date_Range{{2026, 10, 9}, {2026, 10, 15}}) // half-open
	testing.expect_value(t, m.changed, 1)
	testing.expect(t, ui.probe_tagged(&p, "Oct 9, 2026 – Oct 14, 2026"))
}

@(test)
test_a_preset_commits_and_custom_goes_to_the_calendar :: proc(t: ^testing.T) {
	m := Picker_Model {
		ranged = true,
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Choose dates..."))
	testing.expect(t, ui.probe_click(&p, "Last 7 days"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, Date_Range{{2026, 9, 29}, TODAY})
	testing.expect(t, !ui.probe_tagged(&p, "Custom")) // closed

	testing.expect(t, ui.probe_click(&p, "Sep 29, 2026 – Oct 5, 2026"))
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "option \"Last 7 days\" selected"), sem)
	testing.expect(t, ui.probe_click(&p, "Custom"))
	ui.probe_frame(&p)
	// Reopened on the range's start.
	testing.expect_value(t, ui.probe_focus_name(&p), day({2026, 9, 29}))
	testing.expect_value(t, m.changed, 1)
}

@(test)
test_confirm_holds_a_range_until_apply :: proc(t: ^testing.T) {
	m := Picker_Model {
		ranged  = true,
		confirm = true,
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Choose dates..."))
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 1})))
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "button \"Apply\" disabled"), sem) // half a range
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 3})))
	testing.expect(t, ui.probe_click(&p, "Cancel"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, Date_Range{})
	testing.expect(t, ui.probe_click(&p, "Choose dates..."))
	testing.expect(t, ui.probe_click(&p, "This month"))
	testing.expect_value(t, m.changed, 0)
	testing.expect(t, ui.probe_click(&p, "Apply"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, Date_Range{{2026, 10, 1}, TODAY})
	testing.expect_value(t, m.changed, 1)
}

@(test)
test_typed_text_sets_the_date_and_a_bad_date_shows_why :: proc(t: ^testing.T) {
	m := Picker_Model {
		anchor = .Input,
		o = {max_date = {2026, 12, 31}},
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer ui.text_destroy(&m.text)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Start date"))
	ui.probe_type(&p, "10/7/2026")
	ui.probe_frame(&p)
	testing.expect_value(t, m.value, Date{2026, 10, 7})
	// Half typed, nothing shows until Enter.
	ui.text_set(&m.text, "")
	ui.probe_type(&p, "1/32/2026")
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Enter a date as MM/DD/YYYY"))
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Enter a date as MM/DD/YYYY"))
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(
		t,
		strings.contains(sem, "text field \"Start date\"") && strings.contains(sem, "invalid"),
		sem,
	)
	testing.expect_value(t, m.value, Date{2026, 10, 7}) // a bad date leaves the value
	// Past max_date, the message says the bound.
	ui.text_set(&m.text, "")
	ui.probe_type(&p, "01/05/2027")
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Choose a date on or before Dec 31, 2026"))
	// Typing a good date clears it.
	ui.text_set(&m.text, "")
	ui.probe_type(&p, "10/08/2026")
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Choose a date on or before Dec 31, 2026"))
	testing.expect_value(t, m.value, Date{2026, 10, 8})
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, !strings.contains(sem, "invalid"), sem)
	// The calendar action opens it; a pick writes the date back.
	testing.expect(t, ui.probe_click(&p, "Choose date"))
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 12})))
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.text), "10/12/2026")
	testing.expect_value(t, m.value, Date{2026, 10, 12})
}

@(test)
test_a_reserved_anchor_keeps_its_width_as_the_label_changes :: proc(t: ^testing.T) {
	m := Picker_Model {
		ranged = true,
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	empty := ui.probe_bounds(&p, "Choose dates...")
	m.range = {{2026, 10, 5}, {2026, 10, 5}}
	ui.probe_frame(&p)
	one := ui.probe_bounds(&p, "Oct 5, 2026")
	m.range = {{2026, 9, 28}, {2026, 12, 30}}
	ui.probe_frame(&p)
	long := ui.probe_bounds(&p, "Sep 28, 2026 – Dec 30, 2026")
	testing.expect(t, empty.w > 0)
	testing.expect_value(t, one.w, empty.w)
	testing.expect_value(t, long.w, empty.w)
	// Unreserved, a single picker's button follows its label.
	n := Picker_Model {
		value = {2026, 10, 5},
	}
	q: ui.Probe
	picker_probe(&q, &n)
	defer ui.probe_destroy(&q)
	short := ui.probe_bounds(&q, "Oct 5, 2026")
	n.value = {2026, 12, 30}
	ui.probe_frame(&q)
	testing.expect(t, ui.probe_bounds(&q, "Dec 30, 2026").w > short.w)
	n.reserve = true
	ui.probe_frame(&q)
	reserved := ui.probe_bounds(&q, "Dec 30, 2026").w
	n.value = {2026, 10, 5}
	ui.probe_frame(&q)
	testing.expect_value(t, ui.probe_bounds(&q, "Oct 5, 2026").w, reserved)
}

@(test)
test_the_months_page_takes_arrows_home_end_and_enter :: proc(t: ^testing.T) {
	m := Picker_Model {
		value = {2026, 10, 20},
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Oct 20, 2026"))
	ui.probe_frame(&p)
	ui.probe_key(&p, .Tab, {.Shift}) // back from the grid to Next month, then the title
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, ui.probe_focus_name(&p), "October 2026")
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Oct") // the months page, on the month shown
	ui.probe_key(&p, .Tab) // the months are one Tab stop
	testing.expect_value(t, ui.probe_focus_name(&p), "Today")
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, ui.probe_focus_name(&p), "Oct")
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Nov")
	ui.probe_key(&p, .Down) // a row down, into next year
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Feb")
	testing.expect(t, ui.probe_tagged(&p, "2027"))
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Mar")
	ui.probe_key(&p, .Home)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Jan")
	ui.probe_key(&p, .Page_Up)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "2026"))
	ui.probe_key(&p, .Up) // from January, back a row into last year
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Oct")
	testing.expect(t, ui.probe_tagged(&p, "2025"))
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	// Back on the days, the cursor's day kept.
	testing.expect_value(t, ui.probe_focus_name(&p), day({2025, 10, 20}))
	testing.expect_value(t, m.changed, 0)
}

@(test)
test_months_outside_the_bounds_stop_the_months_keys :: proc(t: ^testing.T) {
	o := Calendar_Options {
		min_date = {2026, 3, 15},
		max_date = {2026, 11, 2},
	}
	m, ok := month_step({2026, 3, 1}, .Left, o)
	testing.expect(t, !ok)
	testing.expect_value(t, m, Date{2026, 3, 1})
	m, ok = month_step({2026, 11, 1}, .Right, o)
	testing.expect(t, !ok)
	m, ok = month_step({2026, 8, 1}, .Down, o)
	testing.expect_value(t, m, Date{2026, 11, 1})
	_, ok = month_step({2026, 8, 1}, .Page_Down, o)
	testing.expect(t, !ok)
	m, ok = month_step({2026, 5, 1}, .End, o)
	testing.expect_value(t, m, Date{2026, 6, 1})
	m, ok = month_step({2026, 5, 1}, .Home, o)
	testing.expect_value(t, m, Date{2026, 4, 1})
	testing.expect_value(t, nearest_month_in(2027, 6, o), 6) // no month of 2027 is in: stays
	testing.expect_value(t, nearest_month_in(2026, 1, o), 3)
	testing.expect_value(t, nearest_month_in(2026, 12, o), 11)
}

@(test)
test_start_and_end_inputs_and_the_grid_follow_each_other :: proc(t: ^testing.T) {
	m := Picker_Model {
		ranged = true,
		confirm = true,
		typing = true,
		o = {max_date = {2026, 12, 31}},
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer range_inputs_destroy(&m.inputs)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Choose dates..."))
	testing.expect(t, ui.probe_click(&p, "Start date"))
	ui.probe_type(&p, "10/20/2026")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Choose an end date")) // a first pick
	testing.expect(t, ui.probe_click(&p, "End date"))
	ui.probe_type(&p, "10/12/2026") // before the start: the two in order
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(
		t,
		strings.contains(sem, "grid cell \"Thursday, October 15, 2026\" selected"),
		sem,
	)
	testing.expect(t, ui.probe_tagged(&p, "Oct 12, 2026 – Oct 20, 2026"))
	// Leaving the inputs writes the range back in order.
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 3})))
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.inputs.start), "10/03/2026")
	testing.expect_value(t, ui.text_string(&m.inputs.end), "")
	testing.expect(t, ui.probe_click(&p, day({2026, 10, 9})))
	ui.probe_frame(&p)
	testing.expect_value(t, ui.text_string(&m.inputs.end), "10/09/2026")
	// A bad date shows why once left, and changes nothing.
	testing.expect(t, ui.probe_click(&p, "End date"))
	ui.text_set(&m.inputs.end, "")
	ui.probe_type(&p, "01/04/2027")
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Choose a date on or before Dec 31, 2026"))
	// A start typed after the end swaps them.
	testing.expect(t, ui.probe_click(&p, "Start date"))
	ui.text_set(&m.inputs.start, "")
	ui.probe_type(&p, "10/30/2026")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Oct 9, 2026 – Oct 30, 2026"))
	testing.expect(t, ui.probe_click(&p, "Apply"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, Date_Range{{2026, 10, 9}, {2026, 10, 30}})
}

@(test)
test_a_half_picked_range_is_never_committed :: proc(t: ^testing.T) {
	before := Date_Range{{2026, 9, 1}, {2026, 9, 10}}
	m := Picker_Model {
		ranged  = true,
		confirm = true,
		range   = before,
	}
	p: ui.Probe
	picker_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	label := "Sep 1, 2026 – Sep 10, 2026"
	testing.expect(t, ui.probe_click(&p, label))
	testing.expect(t, ui.probe_click(&p, day({2026, 9, 20})))
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "button \"Apply\" disabled"), sem)
	testing.expect(t, !ui.probe_click(&p, "Apply")) // disabled: nothing to press
	testing.expect(t, ui.probe_click(&p, "Cancel"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, before)
	testing.expect_value(t, m.changed, 0)
	// Reopened, it starts from the value; a preset replaces a first pick.
	testing.expect(t, ui.probe_click(&p, label))
	testing.expect(t, ui.probe_tagged(&p, label))
	testing.expect(t, ui.probe_click(&p, day({2026, 9, 20})))
	testing.expect(t, ui.probe_click(&p, "Last month"))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Choose an end date"))
	testing.expect(t, ui.probe_click(&p, "Apply"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, Date_Range{{2026, 9, 1}, {2026, 9, 30}})
	// Without confirm, Escape drops a first pick.
	m.confirm = false
	m.range = before
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, label))
	testing.expect(t, ui.probe_click(&p, day({2026, 9, 25})))
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect_value(t, m.range, before)
	testing.expect(t, ui.probe_click(&p, label))
	testing.expect(t, !ui.probe_tagged(&p, "Choose an end date"))
}
