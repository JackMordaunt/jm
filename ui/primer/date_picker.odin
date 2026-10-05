package primer

import "core:fmt"
import "core:strings"
import "core:time"
import "jm:timefmt"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// The date pickers: date_picker for one date and date_range_picker for a
// span, each an anchor that opens the calendar (calendar.odin) in an
// anchored overlay. Their props follow GitHub's internal DatePicker
// (primer.style/product/internal-components/date-picker, read
// 2026-10-05): the button, input and icon-only anchors, confirmation
// (Apply and Cancel, else a pick commits and closes), showTodayButton,
// showClearButton, minDate and maxDate, weekStartsOn, the 1-month and
// 2-month views, and the "Choose date..." placeholder. The presets beside
// a range, the typed input's formats and the footer's Today and Clear
// follow the SAZ admin's DateRangeButton and DatePicker, which these
// replace.

// date_today is today's date in this machine's time zone: what a picker
// marks as today and its Today button picks.
date_today :: proc() -> Date {
	p := timefmt.local_parts(time.now())
	return {p.year, p.month, p.day}
}

// DATE_FORMATS are the layouts typed text is read in (jm:timefmt), tried
// in order: 10/5/2026 or 10/05/2026, 2026-10-05, Oct 5, 2026 and
// October 5, 2026. DATE_INPUT_FORMAT is the one a picked date is written
// back in. A year is four digits.
DATE_FORMATS := [?]string{"%m/%d/%Y", "%Y-%m-%d", "%b %d, %Y"}
DATE_INPUT_FORMAT      :: "%m/%d/%Y"
DATE_INPUT_PLACEHOLDER :: "MM/DD/YYYY"

// parse_date reads s, trimmed, in the first of DATE_FORMATS that takes
// it whole; false when none does or the day does not exist (02/30/2026).
parse_date :: proc(s: string) -> (Date, bool) {
	t := strings.trim_space(s)
	for layout in DATE_FORMATS {
		if at, ok := timefmt.parse(t, layout); ok {
			p := timefmt.utc_parts(at)
			return {p.year, p.month, p.day}, true
		}
	}
	return {}, false
}

// format_date is d in DATE_INPUT_FORMAT, 10/05/2026.
format_date :: proc(d: Date, allocator := context.allocator) -> string {
	return timefmt.format_parts(
		{year = d.year, month = d.month, day = d.day},
		DATE_INPUT_FORMAT,
		allocator,
	)
}

// format_date_short is d as an anchor shows it, Oct 5, 2026 (the
// DatePicker's dateFormat short).
format_date_short :: proc(d: Date, allocator := context.allocator) -> string {
	return fmt.aprintf(
		"%s %d, %d",
		timefmt.MONTHS[d.month - 1][:3],
		d.day,
		d.year,
		allocator = allocator,
	)
}

// format_range is r, inclusive, as an anchor shows it: Oct 1, 2026 –
// Oct 5, 2026, one date when it is one day, "" when it is none.
format_range :: proc(r: Date_Range, allocator := context.allocator) -> string {
	switch {
	case r.start == {}:
		return ""
	case r.end == {} || r.end == r.start:
		return format_date_short(r.start, allocator)
	}
	a := format_date_short(r.start, context.temp_allocator)
	b := format_date_short(r.end, context.temp_allocator)
	return strings.concatenate({a, " – ", b}, allocator)
}

// Date_Error is why typed text is not a date that can be picked.
Date_Error :: enum u8 {
	None,
	Format, // not a date in any of DATE_FORMATS
	Before_Min,
	After_Max,
	Unavailable, // rejected by Calendar_Options.disabled
}

// date_check reads typed text as a date o allows: the zero Date with no
// error for empty text, else the date or why it is not one.
date_check :: proc(s: string, o: Calendar_Options) -> (Date, Date_Error) {
	if strings.trim_space(s) == "" {
		return {}, .None
	}
	d, ok := parse_date(s)
	switch {
	case !ok:
		return {}, .Format
	case o.min_date != {} && date_less(d, o.min_date):
		return d, .Before_Min
	case o.max_date != {} && date_less(o.max_date, d):
		return d, .After_Max
	case !date_selectable(o, d):
		return d, .Unavailable
	}
	return d, .None
}

// date_error_message is the validation message for e under o.
date_error_message :: proc(
	e: Date_Error,
	o: Calendar_Options,
	allocator := context.allocator,
) -> string {
	switch e {
	case .None:
		return ""
	case .Format:
		return strings.clone("Enter a date as " + DATE_INPUT_PLACEHOLDER, allocator)
	case .Before_Min:
		return fmt.aprintf(
			"Choose a date on or after %s",
			format_date_short(o.min_date, context.temp_allocator),
			allocator = allocator,
		)
	case .After_Max:
		return fmt.aprintf(
			"Choose a date on or before %s",
			format_date_short(o.max_date, context.temp_allocator),
			allocator = allocator,
		)
	case .Unavailable:
		return strings.clone("That date cannot be chosen", allocator)
	}
	return ""
}

// Range_Bounds is how a range picker's value reads its end. Inclusive:
// end is the last day in the range, as the calendar shows it. Half_Open:
// end is the day after the last, so a query reads start <= day < end and
// a one-day range ends the next day. Either way the calendar, the anchor
// and Date_Preset ranges show and take the inclusive end.
Range_Bounds :: enum u8 {
	Inclusive,
	Half_Open,
}

// range_shown is value, read in bounds, as the calendar shows it.
range_shown :: proc(value: Date_Range, bounds: Range_Bounds) -> Date_Range {
	if bounds == .Half_Open && value.end != {} {
		return {value.start, date_add_days(value.end, -1)}
	}
	return value
}

// range_stored is r, as the calendar shows it, written in bounds.
range_stored :: proc(r: Date_Range, bounds: Range_Bounds) -> Date_Range {
	if bounds == .Half_Open && r.end != {} {
		return {r.start, date_add_days(r.end, 1)}
	}
	return r
}

// range_pick takes a pick of day into a range being chosen: the first
// pick anchors it, the second ends it, whichever of the two is earlier
// starting it. It reports whether the range is complete.
@(private)
range_pick :: proc(cal: ^Calendar, pending: ^Date_Range, day: Date) -> (complete: bool) {
	if cal.anchor == {} {
		cal.anchor = day
		pending^ = {day, {}}
		return false
	}
	pending.start, pending.end = sort_dates(cal.anchor, day)
	cal.anchor = {}
	return true
}

// Date_Preset is a named range a range picker offers beside its
// calendar, inclusive.
Date_Preset :: struct {
	label: string,
	range: Date_Range,
}

// standard_presets are the ranges an operations dashboard offers, as of
// today: Today, Last 7 days and Last 30 days (each ending today), This
// month (its first day to today), Last month (all of it) and Year to
// date. The app passes these, or its own, to date_range_picker, which
// adds Custom.
standard_presets :: proc(today: Date) -> [6]Date_Preset {
	this_month := month_of(today)
	last_month := date_add_months(this_month, -1)
	return {
		{"Today", {today, today}},
		{"Last 7 days", {date_add_days(today, -6), today}},
		{"Last 30 days", {date_add_days(today, -29), today}},
		{"This month", {this_month, today}},
		{"Last month", {last_month, date_add_days(this_month, -1)}},
		{"Year to date", {{today.year, 1, 1}, today}},
	}
}

// Date_Picker_Anchor is what a date picker draws in the page to open its
// calendar (the DatePicker's anchor).
Date_Picker_Anchor :: enum u8 {
	Button, // a button naming the date, with a leading calendar icon
	Input, // a text input to type the date in, with a trailing calendar action
	Icon_Only, // a calendar icon button
}

// Picker_Data is what a picker keeps between frames.
@(private)
Picker_Data :: struct {
	open:       bool,
	cal:        Calendar,
	pending:    Date_Range, // the choice shown in the calendar until it is committed
	error:      Date_Error, // the typed text's
	show_error: bool, // shown once the text is submitted or left
	shown:      Date, // the date the text input was last written with
	focused:    bool, // the text input had focus last frame
}

// PRESETS_W is the presets list's width: its longest standard label,
// Year to date, with the checkmark column and the inset, and room over.
PRESETS_W :: f32(160)

// PICKER_PAD is the calendar's inset in the overlay, 12px
// (--base-size-12): no Primer component insets a calendar, so it sits
// between the overlay's condensed and normal paddings
// (tok.OVERLAY_PADDING_CONDENSED, tok.OVERLAY_PADDING_NORMAL).
PICKER_PAD :: tok.BASE_SIZE_12

// date_picker is a date picker (GitHub's DatePicker, single): anchor
// opens an anchored overlay holding the calendar, a day picked there
// sets value^ and closes it, and focus goes back to the anchor; the
// zero Date is no date. today marks today (date_today) and is what Today
// picks. options bound what can be picked and lay the grid out.
//
// anchor Button shows the date, Oct 5, 2026, or placeholder; Icon_Only
// is a calendar icon button; Input is a text input over text
// (the caller's, required for it) that takes a typed date in any of
// DATE_FORMATS, sets value^ as soon as the text is a date options
// allow, and empties it with the text. Typed text that is no such date
// leaves value^ alone and, once submitted with Enter or left, marks the
// input invalid and, inside a form_control, shows why as its validation
// message (date_error_message). A pick writes the date back as
// DATE_INPUT_FORMAT.
//
// confirm holds a pick until Apply, and Cancel drops it (the
// DatePicker's confirmation). today_button adds Today, which picks
// today, unless it cannot be picked; clear_button adds Clear, which
// empties value^. Escape or a press outside closes the overlay without a
// change. name is what a reader calls the picker (the DatePicker's
// fieldName), "Date" when empty; an Input with no name takes the open
// form_control's label, as text_input does. Returns true on the frame
// value^ changes.
//
// Departures: the DatePicker's inputs inside the overlay, its
// compressed header's dropdowns, confirmUnsavedClose and its other
// dateFormats are not offered; the anchor's label is not reserved at its
// widest, so the button's width follows the date.
date_picker :: proc(
	gtx: ^ui.Ctx,
	value: ^Date,
	today: Date,
	options := Calendar_Options{},
	anchor := Date_Picker_Anchor.Button,
	text: ^ui.Text_State = nil,
	placeholder := "Choose date...",
	confirm := false,
	today_button := true,
	clear_button := false,
	name := "",
	size := Button_Size.Medium,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (
	changed: bool,
) {
	assert(anchor != .Input || text != nil, "date_picker: the Input anchor needs text")
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Picker_Data)
	stack := ui.stack_open(gtx, key = u64(ui.id_mix(id, 1)))
	defer ui.close(&stack)
	if !d.open {
		calendar_reset(&d.cal, value^ != {} ? value^ : today, options)
		d.pending = {value^, {}}
	}
	look := Picker_Look{name != "" ? name : "Date", placeholder, size, state}
	switch anchor {
	case .Button:
		label := value^ != {} ? format_date_short(value^, gtx.allocator) : placeholder
		picker_button(gtx, id, d, label, look)
	case .Icon_Only:
		if icon_button(
			gtx,
			.Calendar,
			look.name,
			expanded = d.open,
			state = state,
			key = u64(ui.id_mix(id, 2)),
		) {
			d.open = !d.open
		}
	case .Input:
		look.name = name
		changed |= picker_input(gtx, id, d, value, text, options, look)
	}
	cal_id := ui.id_mix(id, 3)
	a := anchored_overlay_open(
		gtx,
		&d.open,
		ui.last_widget(gtx),
		focus = {initial = calendar_cell_id(cal_id, d.cal.cursor)},
		role = .Dialog,
		name = name != "" ? name : "Date",
		key = u64(ui.id_mix(id, 4)),
	)
	if a.visible {
		f := Single_Footer{confirm, today_button && date_selectable(options, today), clear_button}
		changed |= single_body(gtx, id, d, value, today, options, f)
	}
	anchored_overlay_close(&a)
	return
}

// Picker_Look is how a picker's anchor reads.
@(private)
Picker_Look :: struct {
	name, placeholder: string,
	size:              Button_Size,
	state:             Interaction,
}

// picker_button is a picker's Button anchor: label between a leading
// calendar and a trailing triangle, toggling the overlay, expanded while
// it is open, named "name: label" for a reader.
@(private)
picker_button :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	d: ^Picker_Data,
	label: string,
	look: Picker_Look,
) {
	said := fmt.aprintf("%s: %s", look.name, label, allocator = gtx.allocator)
	if button(
		gtx,
		label,
		.Default,
		look.size,
		leading = .Calendar,
		action = .Triangle_Down,
		name = said,
		expanded = d.open,
		state = look.state,
		key = u64(ui.id_mix(id, 2)),
	) {
		d.open = !d.open
	}
}

// picker_input is a date picker's Input anchor: it writes value^ into
// text when value^ changes from outside while the input is not being
// typed in, reads the typed text into value^, and keeps the error the
// text has, shown once the text is submitted or left.
@(private)
picker_input :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	d: ^Picker_Data,
	value: ^Date,
	text: ^ui.Text_State,
	o: Calendar_Options,
	look: Picker_Look,
) -> (
	changed: bool,
) {
	if value^ != d.shown && !d.focused {
		ui.text_set(text, value^ == {} ? "" : format_date(value^, context.temp_allocator))
		d.shown = value^
		d.error, d.show_error = .None, false
	}
	if f := open_form(); d.show_error && f != nil && f.message == "" {
		f.message = date_error_message(d.error, o, gtx.allocator)
		f.status = .Error
	}
	validation := d.show_error ? Validation_Status.Error : .None
	e := text_input(
		gtx,
		text,
		DATE_INPUT_PLACEHOLDER,
		action = .Calendar,
		action_name = "Choose date",
		validation = validation,
		name = look.name,
		state = look.state,
		key = u64(ui.id_mix(id, 2)),
	)
	if e.action {
		d.open = !d.open
	}
	if e.changed {
		v, err := date_check(ui.text_string(text), o)
		d.error = err
		if err == .None {
			changed = value^ != v
			value^, d.shown = v, v
			d.show_error = false
		}
	}
	if e.submitted || (d.focused && !e.focused) {
		show := d.error != .None
		if show != d.show_error {
			d.show_error = show
			ui.request_frame(gtx)
		}
	}
	d.focused = e.focused
	return
}

// Single_Footer is which of a date picker's footer buttons show.
@(private)
Single_Footer :: struct {
	confirm, today, clear: bool,
}

// single_body is a date picker's overlay content: the calendar, inset
// PICKER_PAD, over the footer when it has buttons.
@(private)
single_body :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	d: ^Picker_Data,
	value: ^Date,
	today: Date,
	o: Calendar_Options,
	f: Single_Footer,
) -> (
	changed: bool,
) {
	w := calendar_width(o) + 2 * PICKER_PAD
	sz := ui.sized_open(gtx, {{w, 0}, {w, ui.INF}}, key = u64(ui.id_mix(id, 15)))
	defer ui.close(&sz)
	col := ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(id, 5)))
	defer ui.close(&col)
	picked: Date
	{
		pad := ui.inset_open(gtx, ui.pad_all(PICKER_PAD), key = u64(ui.id_mix(id, 6)))
		look := Calendar_Look {
			sel   = {d.pending.start, {}},
			today = today,
		}
		picked = calendar_panel(gtx, ui.id_mix(id, 3), &d.cal, look, o, .Live)
		ui.close(&pad)
	}
	act := Footer_Action.None
	if f.confirm || f.today || f.clear {
		act = picker_footer(gtx, id, "", f.today, f.clear ? "Clear" : "", f.confirm, true)
	}
	#partial switch act {
	case .Today:
		picked = today
		d.cal.cursor, d.cal.refocus = today, true
		calendar_follow(&d.cal, shown_months(o))
	case .Clear:
		d.pending = {}
		if !f.confirm {
			changed = value^ != {}
			value^, d.open = {}, false
		}
	case .Apply:
		changed = value^ != d.pending.start
		value^, d.open = d.pending.start, false
	case .Cancel:
		d.open = false
	}
	if picked != {} {
		ui.request_frame(gtx)
		d.pending = {picked, {}}
		if !f.confirm {
			changed = value^ != picked
			value^, d.open = picked, false
		}
	}
	return
}

// Footer_Action is the footer button activated this frame.
@(private)
Footer_Action :: enum u8 {
	None,
	Today,
	Clear,
	Cancel,
	Apply,
}

// picker_footer is a picker's footer, padded 8px under a 1px
// --borderColor-default rule (the SelectPanel footer's look): summary in
// small muted text, or Today, and clear (its label) as invisible small
// buttons at the start; Cancel and a primary Apply at the end when
// confirm, Apply disabled until can_apply.
@(private)
picker_footer :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	summary: string,
	today: bool,
	clear: string,
	confirm, can_apply: bool,
) -> (
	act: Footer_Action,
) {
	band := ui.box_open(
		gtx,
		{padding = ui.pad_all(tok.BASE_SIZE_8), paint = paint_top_rule},
		key = u64(ui.id_mix(id, 7)),
	)
	defer ui.close(&band)
	row := ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center, key = u64(ui.id_mix(id, 8)))
	defer ui.close(&row)
	if summary != "" {
		text(gtx, summary, .Small, color = color(.Fg_Color_Muted), key = u64(ui.id_mix(id, 9)))
	}
	if today && button(gtx, "Today", .Invisible, .Small, key = u64(ui.id_mix(id, 10))) {
		act = .Today
	}
	if clear != "" && button(gtx, clear, .Invisible, .Small, key = u64(ui.id_mix(id, 11))) {
		act = .Clear
	}
	ui.fill_space(gtx)
	if !confirm {
		return
	}
	if button(gtx, "Cancel", .Default, .Small, key = u64(ui.id_mix(id, 12))) {
		act = .Cancel
	}
	if button(
		gtx,
		"Apply",
		.Primary,
		.Small,
		state = can_apply ? .Live : .Disabled,
		key = u64(ui.id_mix(id, 13)),
	) {
		act = .Apply
	}
	return
}

// date_range_picker is a date range picker (GitHub's DatePicker, range,
// and the admin's DateRangeButton): a button naming the range, Oct 1,
// 2026 – Oct 5, 2026, or placeholder, opens an anchored overlay holding
// the calendar beside presets. In the calendar a first pick starts the
// range and a second ends it, whichever is earlier becoming its start;
// until the second, the days from the first to the day under the
// pointer (or the keyboard's cursor) show as the range would be, the
// proposed end ringed. A preset sets the range at once. value^ is
// written in bounds (Range_Bounds), the zero Date_Range for none.
//
// presets are the app's (standard_presets offers the usual six); the
// list adds Custom, selected when the range is none of them, which puts
// focus in the calendar. With no presets there is no list. Without
// confirm, a complete range or a preset commits and closes; with it,
// they wait for Apply, which a range half picked keeps disabled, and
// Cancel drops them. clear, when set, is the label of a button that
// empties the range (the admin's "Month to date" reset). The footer
// says what is chosen. options.months 2 lays two months side by side.
// Escape or a press outside closes the overlay without a change, and
// focus goes back to the button. Returns true on the frame value^
// changes.
//
// Departures: GitHub's in-overlay start and end inputs and its
// confirmUnsavedClose are not offered; a half-picked range is never
// committed, so a range without an end cannot be chosen.
date_range_picker :: proc(
	gtx: ^ui.Ctx,
	value: ^Date_Range,
	today: Date,
	presets: []Date_Preset = nil,
	options := Calendar_Options{},
	bounds := Range_Bounds.Inclusive,
	confirm := false,
	placeholder := "Choose dates...",
	clear := "",
	name := "Date range",
	size := Button_Size.Medium,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (
	changed: bool,
) {
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Picker_Data)
	stack := ui.stack_open(gtx, key = u64(ui.id_mix(id, 1)))
	defer ui.close(&stack)
	shown := range_shown(value^, bounds)
	if !d.open {
		calendar_reset(&d.cal, shown.start != {} ? shown.start : today, options)
		d.pending = shown
	}
	label := shown.start != {} ? format_range(shown, gtx.allocator) : placeholder
	picker_button(gtx, id, d, label, {name, placeholder, size, state})
	cal_id := ui.id_mix(id, 3)
	a := anchored_overlay_open(
		gtx,
		&d.open,
		ui.last_widget(gtx),
		focus = {initial = calendar_cell_id(cal_id, d.cal.cursor)},
		role = .Dialog,
		name = name,
		key = u64(ui.id_mix(id, 4)),
	)
	if a.visible {
		r := Range_Opts{presets, options, bounds, confirm, clear, today}
		changed |= range_body(gtx, id, d, value, r)
	}
	anchored_overlay_close(&a)
	return
}

// Range_Opts are a range picker's options, past its value.
@(private)
Range_Opts :: struct {
	presets: []Date_Preset,
	o:       Calendar_Options,
	bounds:  Range_Bounds,
	confirm: bool,
	clear:   string,
	today:   Date,
}

// range_body is a range picker's overlay content: the presets list and
// the calendar side by side, a 1px rule between, over the footer.
@(private)
range_body :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	d: ^Picker_Data,
	value: ^Date_Range,
	r: Range_Opts,
) -> (
	changed: bool,
) {
	w := calendar_width(r.o) + 2 * PICKER_PAD + (len(r.presets) > 0 ? PRESETS_W : 0)
	sz := ui.sized_open(gtx, {{w, 0}, {w, ui.INF}}, key = u64(ui.id_mix(id, 15)))
	defer ui.close(&sz)
	col := ui.column_open(gtx, align = .Fill, key = u64(ui.id_mix(id, 5)))
	defer ui.close(&col)
	picked: Date
	chose := -1
	{
		row := ui.row_open(gtx, key = u64(ui.id_mix(id, 20)))
		defer ui.close(&row)
		if len(r.presets) > 0 {
			chose = preset_list(gtx, id, d, r.presets)
		}
		rule := ui.box_open(
			gtx,
			{
				padding = ui.pad_all(PICKER_PAD),
				paint = len(r.presets) > 0 ? paint_start_rule : nil,
			},
			key = u64(ui.id_mix(id, 6)),
		)
		look := Calendar_Look {
			sel   = d.pending,
			range = true,
			today = r.today,
		}
		picked = calendar_panel(gtx, ui.id_mix(id, 3), &d.cal, look, r.o, .Live)
		ui.close(&rule)
	}
	commit := false
	switch {
	case chose >= 0 && chose < len(r.presets):
		p := r.presets[chose].range
		d.pending, d.cal.anchor = p, {}
		d.cal.cursor, _ = nearest_selectable(p.end, -1, r.o)
		calendar_follow(&d.cal, shown_months(r.o))
		commit = !r.confirm
	case chose == len(r.presets):
		d.cal.anchor = {}
		ui.focus_request(gtx, calendar_cell_id(ui.id_mix(id, 3), d.cal.cursor))
	case picked != {}:
		commit = range_pick(&d.cal, &d.pending, picked) && !r.confirm
	}
	if chose >= 0 || picked != {} {
		ui.request_frame(gtx) // the calendar was drawn with the selection before it
	}
	summary :=
		"Choose an end date" if d.cal.anchor != {} else format_range(d.pending, gtx.allocator)
	act := picker_footer(gtx, id, summary, false, r.clear, r.confirm, d.cal.anchor == {})
	#partial switch act {
	case .Clear:
		d.pending, d.cal.anchor = {}, {}
		commit = !r.confirm
	case .Apply:
		commit = true
	case .Cancel:
		d.open = false
	}
	if commit {
		v := range_stored(d.pending, r.bounds)
		changed = value^ != v
		value^, d.open = v, false
	}
	return
}

// preset_list is a range picker's presets as a single-select listbox,
// inset, its own Tab stop that arrows move through: each preset,
// selected while the range is it, then Custom, selected while the range
// is set and none of them. It reports the index activated, len(presets)
// for Custom, -1 for none.
@(private)
preset_list :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	d: ^Picker_Data,
	presets: []Date_Preset,
) -> (
	chose: int,
) {
	chose = -1
	sz := ui.sized_open(gtx, {{PRESETS_W, 0}, {PRESETS_W, ui.INF}}, key = u64(ui.id_mix(id, 22)))
	defer ui.close(&sz)
	l := action_list_open(
		gtx,
		.Inset,
		.Single,
		.Listbox,
		name = "Presets",
		key = u64(ui.id_mix(id, 21)),
	)
	defer action_list_close(&l)
	matched := false
	for p, i in presets {
		on := d.cal.anchor == {} && d.pending == p.range
		matched ||= on
		if action_list_item(&l, p.label, selected = on) {
			chose = i
		}
	}
	custom := !matched && (d.pending.start != {} || d.cal.anchor != {})
	if action_list_item(&l, "Custom", selected = custom) {
		chose = len(presets)
	}
	return
}

// paint_start_rule draws the calendar's 1px --borderColor-default rule
// on its start edge, between it and the presets.
@(private)
paint_start_rule :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	ops.fill(
		gtx.scene,
		ops.Rect{0, 0, tok.BORDER_WIDTH_THIN, size.y},
		color(.Border_Color_Default),
	)
}
