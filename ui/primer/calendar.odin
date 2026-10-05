package primer

import "core:fmt"
import "jm:timefmt"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// The calendar the date pickers open (date_picker.odin): month grids of
// plain calendar dates, a header that pages them, a months page that
// pages years, and the WAI-ARIA date picker dialog's keyboard model on
// the grid. Primer React has no public date picker; GitHub's internal
// DatePicker documents its props but not its look
// (primer.style/product/internal-components/date-picker, read
// 2026-10-05), so the props follow it and the look is composed from
// Primer's primitives: 32px day cells (--control-medium-size) with
// --borderRadius-medium corners, the selection on --bgColor-accent-
// emphasis under --fgColor-onEmphasis, a range's days between on
// --bgColor-accent-muted, hover on the transparent control's
// --control-transparent-bgColor-hover, today in semibold --fgColor-
// accent, and invisible small buttons for the header.
//
// Dates are calendar dates with no time and no zone (Date, design's), so
// a picker's value means the same day wherever it is read.
//
// Keyboard (the grid is one Tab stop, the day the cursor sits on):
// Left and Right move a day, Up and Down a week, Home and End to the
// week's first and last day, PageUp and PageDown a month and with Shift
// a year; a move that lands on a date that cannot be picked goes on in
// its direction to the nearest that can (Home and End towards the
// cursor), and a move past the shown months pages them. Enter or Space
// picks the cursor's day. The roving Tab stop is a no_tab area per day
// but the cursor's and a ui.focus_request after each move: jm:ui's
// roving scopes walk members in frame order (route_rove in
// ui/input.odin), which a calendar cannot
// use, as its cursor moves by date into months not yet drawn and over
// days that cannot be picked.

Date          :: design.Date
days_in_month :: design.days_in_month
weekday       :: design.weekday
date_less     :: design.date_less

date_days       :: design.date_days
date_from_days  :: design.date_from_days
date_add_days   :: design.date_add_days
date_add_months :: design.date_add_months
date_valid      :: design.date_valid
month_of        :: design.month_of
week_first      :: design.week_first
week_last       :: design.week_last

// Date_Range is a span of calendar dates, start to end, both days
// included, the zero Date_Range none; a picker's value is read and
// written in its Range_Bounds.
Date_Range :: struct {
	start, end: Date,
}

// Calendar_Options are what may be picked and how the grid is laid out,
// shared by date_picker and date_range_picker (GitHub's DatePicker
// minDate, maxDate, disableWeekends generalised, weekStartsOn and view).
// min_date and max_date bound the dates that can be picked, both
// included, the zero Date for no bound; disabled, when set, rejects a
// date besides (a weekend, a holiday), called with user. week_start is
// the first column, 0 Sunday to 6 Saturday. months is how many months
// sit side by side, 1 or 2 (0 reads as 1).
Calendar_Options :: struct {
	min_date, max_date: Date,
	disabled:           proc(d: Date, user: rawptr) -> bool,
	user:               rawptr,
	week_start:         int,
	months:             int,
}

// date_selectable reports whether d can be picked under o.
date_selectable :: proc(o: Calendar_Options, d: Date) -> bool {
	if !date_in_bounds(o, d) {
		return false
	}
	return o.disabled == nil || !o.disabled(d, o.user)
}

// date_in_bounds reports whether d lies within o's min_date and max_date.
date_in_bounds :: proc(o: Calendar_Options, d: Date) -> bool {
	if o.min_date != {} && date_less(d, o.min_date) {
		return false
	}
	return o.max_date == {} || !date_less(o.max_date, d)
}

// SEARCH_DAYS is how far a move looks for a date that can be picked
// before it gives up and stays.
@(private)
SEARCH_DAYS :: 366

// nearest_selectable is the first date that can be picked from d,
// stepping dir (1 or -1) days at a time, d first clamped into o's
// bounds; false when there is none within SEARCH_DAYS or the bounds.
nearest_selectable :: proc(d: Date, dir: int, o: Calendar_Options) -> (Date, bool) {
	t := d
	if o.min_date != {} && date_less(t, o.min_date) {
		t = o.min_date
	}
	if o.max_date != {} && date_less(o.max_date, t) {
		t = o.max_date
	}
	for _ in 0 ..< SEARCH_DAYS {
		if date_selectable(o, t) {
			return t, true
		}
		t = date_add_days(t, dir)
		if !date_in_bounds(o, t) {
			break
		}
	}
	return d, false
}

// calendar_target is where key (with mods) moves a cursor on d, and the
// direction to search in when that date cannot be picked: Home and End
// search back towards d; false for a key that moves nothing.
calendar_target :: proc(
	d: Date,
	key: ui.Key,
	mods: ui.Mods,
	week_start: int,
) -> (
	t: Date,
	dir: int,
	ok: bool,
) {
	months := .Shift in mods ? 12 : 1
	#partial switch key {
	case .Left:
		return date_add_days(d, -1), -1, true
	case .Right:
		return date_add_days(d, 1), 1, true
	case .Up:
		return date_add_days(d, -7), -1, true
	case .Down:
		return date_add_days(d, 7), 1, true
	case .Home:
		return week_first(d, week_start), 1, true
	case .End:
		return week_last(d, week_start), -1, true
	case .Page_Up:
		return date_add_months(d, -months), -1, true
	case .Page_Down:
		return date_add_months(d, months), 1, true
	}
	return d, 0, false
}

// calendar_step is the cursor on d moved by key: its target, or the
// nearest date past it that can be picked; false when key moves nothing
// or nothing can be picked that way.
calendar_step :: proc(d: Date, key: ui.Key, mods: ui.Mods, o: Calendar_Options) -> (Date, bool) {
	t, dir, ok := calendar_target(d, key, mods, o.week_start)
	if !ok {
		return d, false
	}
	return nearest_selectable(t, dir, o)
}

// Calendar_Page is what a calendar shows: the days of its months, or the
// months of a year to jump to.
@(private)
Calendar_Page :: enum u8 {
	Days,
	Months,
}

// Calendar is what a picker's calendar keeps between frames.
@(private)
Calendar :: struct {
	view:    Date, // the first month shown, its first day
	cursor:  Date, // the day the keyboard sits on: the grid's one Tab stop
	anchor:  Date, // a range's first pick, until its second
	hover:   Date, // the day under the pointer last frame
	page:    Calendar_Page,
	year:    int, // the year the months page shows
	refocus: bool, // put focus on the cursor's day once it is drawn
}

// shown_months is how many months o lays side by side.
@(private)
shown_months :: proc(o: Calendar_Options) -> int {
	return clamp(o.months, 1, 2)
}

// calendar_reset points cal at at: the cursor on the nearest day that
// can be picked, its month first, back on the days page.
@(private)
calendar_reset :: proc(cal: ^Calendar, at: Date, o: Calendar_Options) {
	cal.cursor, _ = nearest_selectable(at, 1, o)
	cal.view = month_of(cal.cursor)
	cal.anchor, cal.hover, cal.page = {}, {}, .Days
}

// calendar_follow pages cal's view so the cursor's month shows: the
// first shown when the cursor went back, the last when it went on.
@(private)
calendar_follow :: proc(cal: ^Calendar, months: int) {
	cm := month_of(cal.cursor)
	if date_less(cm, cal.view) {
		cal.view = cm
	}
	if last := date_add_months(cal.view, months - 1); date_less(last, cm) {
		cal.view = date_add_months(cm, -(months - 1))
	}
}

// cursor_into_view moves cal's cursor into the shown months when paging
// left it outside: the same day of the first shown month, or the
// nearest that can be picked, so the grid keeps its Tab stop.
@(private)
cursor_into_view :: proc(cal: ^Calendar, o: Calendar_Options) {
	cm := month_of(cal.cursor)
	last := date_add_months(cal.view, shown_months(o) - 1)
	if !date_less(cm, cal.view) && !date_less(last, cm) {
		return
	}
	at := Date {
		cal.view.year,
		cal.view.month,
		min(cal.cursor.day, days_in_month(cal.view.year, cal.view.month)),
	}
	if d, ok := nearest_selectable(at, 1, o); ok {
		cal.cursor = d
	}
}

// calendar_cell_id is the id of the cell for d in the calendar id: one
// per date, whichever month grid shows it, so focus stays on a date as
// the view pages.
@(private)
calendar_cell_id :: proc(id: ops.Area_Id, d: Date) -> ops.Area_Id {
	return ui.id_mix(id, u64(0x0da7e) << 32 | u64(d.year * 10000 + d.month * 100 + d.day))
}

// Calendar dimensions: a day cell is a medium control's square
// (--control-medium-size), the weekday row 24px of caption, months 16px
// apart (--stack-gap-normal), the header 8px over the grid
// (--stack-gap-condensed); six week rows always, so a picker keeps one
// height across months.
CALENDAR_CELL       :: tok.CONTROL_MEDIUM_SIZE
CALENDAR_WEEKDAYS_H :: tok.BASE_SIZE_24
CALENDAR_WEEKS      :: 6
CALENDAR_GRID_W     :: 7 * CALENDAR_CELL
CALENDAR_GRID_H     :: CALENDAR_WEEKDAYS_H + CALENDAR_WEEKS * CALENDAR_CELL
CALENDAR_MONTH_GAP  :: tok.STACK_GAP_NORMAL
CALENDAR_HEADER_GAP :: tok.STACK_GAP_CONDENSED

// calendar_width is the width of o's months side by side.
@(private)
calendar_width :: proc(o: Calendar_Options) -> f32 {
	n := shown_months(o)
	return f32(n) * CALENDAR_GRID_W + f32(n - 1) * CALENDAR_MONTH_GAP
}

// Calendar_Look is what a calendar shows picked: a single date (start
// only) or a range, today, and whether a range is being picked.
@(private)
Calendar_Look :: struct {
	sel:   Date_Range, // inclusive; start alone for a single date
	range: bool,
	today: Date,
}

// Day_Band is how a day sits in the selection a calendar paints.
@(private)
Day_Band :: struct {
	lo, hi:  Date, // the selection, ordered, both included; zero for none
	preview: Date, // the end the pointer or cursor proposes, not yet picked
}

// day_band is the band cal paints for look: a range's anchor stretched to
// the day under the pointer (or the keyboard's cursor), else the
// selection.
@(private)
day_band :: proc(cal: ^Calendar, look: Calendar_Look, keyboard: bool) -> (b: Day_Band) {
	if look.range && cal.anchor != {} {
		end := cal.hover
		if end == {} && keyboard {
			end = cal.cursor
		}
		if end == {} {
			end = cal.anchor
		}
		b.lo, b.hi = sort_dates(cal.anchor, end)
		if end != cal.anchor {
			b.preview = end
		}
		return
	}
	b.lo = look.sel.start
	b.hi = look.range && look.sel.end != {} ? look.sel.end : look.sel.start
	return
}

// sort_dates is a and b, earlier first.
sort_dates :: proc(a, b: Date) -> (lo, hi: Date) {
	return date_less(b, a) ? b : a, date_less(b, a) ? a : b
}

// calendar_keys moves cal's cursor by the keys its day heard, pages the
// view after it and asks focus to follow it to its new day.
@(private)
calendar_keys :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, cal: ^Calendar, o: Calendar_Options) {
	moved := false
	for e in ui.events(gtx, calendar_cell_id(id, cal.cursor)) {
		if e.kind != .Key {
			continue
		}
		if d, ok := calendar_step(cal.cursor, e.key, e.mods, o); ok && d != cal.cursor {
			cal.cursor = d
			moved = true
		}
	}
	if moved {
		calendar_follow(cal, shown_months(o))
		cal.refocus = true
	}
}

// calendar_panel draws cal: the header and the day grids, or the months
// page, in a column CALENDAR_HEADER_GAP apart. It reports the day picked
// this frame, by click, Enter or Space; the zero Date for none.
@(private)
calendar_panel :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	cal: ^Calendar,
	look: Calendar_Look,
	o: Calendar_Options,
	state: Interaction,
) -> (
	picked: Date,
) {
	if state == .Live {
		calendar_keys(gtx, id, cal, o)
	}
	col := ui.column_open(gtx, gap = CALENDAR_HEADER_GAP, key = u64(ui.id_mix(id, 1)))
	defer ui.close(&col)
	if cal.page == .Months {
		calendar_months_page(gtx, id, cal, o, state)
		return
	}
	calendar_header(gtx, id, cal, o, state)
	band := day_band(cal, look, ui.focus_visible(gtx))
	hovered: Date
	{
		row := ui.row_open(gtx, gap = CALENDAR_MONTH_GAP, key = u64(ui.id_mix(id, 2)))
		defer ui.close(&row)
		for i in 0 ..< shown_months(o) {
			g := Day_Grid{id, date_add_months(cal.view, i), band, look, o, state}
			if d := day_grid(gtx, cal, g, &hovered); d != {} {
				picked = d
			}
		}
	}
	if hovered != cal.hover {
		cal.hover = hovered
		ui.request_frame(gtx)
	}
	if cal.refocus {
		ui.focus_request(gtx, calendar_cell_id(id, cal.cursor))
		cal.refocus = false
	}
	return
}

// calendar_header is a row per month over its grid: the month and year
// as an invisible small button that opens the months page, the previous
// month's chevron at the far left and the next's at the far right.
@(private)
calendar_header :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	cal: ^Calendar,
	o: Calendar_Options,
	state: Interaction,
) {
	n := shown_months(o)
	nav := button_metrics(.Small).height
	row := ui.row_open(gtx, gap = CALENDAR_MONTH_GAP, align = .Center, key = u64(ui.id_mix(id, 3)))
	defer ui.close(&row)
	for i in 0 ..< n {
		month := date_add_months(cal.view, i)
		cell := ui.sized_open(
			gtx,
			{{CALENDAR_GRID_W, nav}, {CALENDAR_GRID_W, nav}},
			key = u64(ui.id_mix(id, u64(10 + i))),
		)
		line := ui.row_open(gtx, align = .Center, key = u64(ui.id_mix(id, u64(20 + i))))
		if i == 0 {
			before := date_add_days(cal.view, -1)
			st := o.min_date != {} && date_less(before, o.min_date) ? Interaction.Disabled : state
			if icon_button(
				gtx,
				.Chevron_Left,
				"Previous month",
				.Invisible,
				.Small,
				no_tooltip = true,
				state = st,
				key = u64(ui.id_mix(id, 4)),
			) {
				calendar_page_by(cal, -1, o)
			}
		} else {
			ui.spacer(gtx, nav)
		}
		ui.flexible(gtx, 1)
		{
			c := ui.centered_open(gtx, key = u64(ui.id_mix(id, u64(30 + i))))
			title := fmt.aprintf(
				"%s %d",
				timefmt.MONTHS[month.month - 1],
				month.year,
				allocator = gtx.allocator,
			)
			if button(
				gtx,
				title,
				.Invisible,
				.Small,
				action = .Triangle_Down,
				state = state,
				key = u64(ui.id_mix(id, u64(40 + i))),
			) {
				cal.page, cal.year = .Months, month.year
			}
			ui.close(&c)
		}
		if i == n - 1 {
			after := date_add_months(month, 1)
			st := o.max_date != {} && date_less(o.max_date, after) ? Interaction.Disabled : state
			if icon_button(
				gtx,
				.Chevron_Right,
				"Next month",
				.Invisible,
				.Small,
				no_tooltip = true,
				state = st,
				key = u64(ui.id_mix(id, 5)),
			) {
				calendar_page_by(cal, 1, o)
			}
		} else {
			ui.spacer(gtx, nav)
		}
		ui.close(&line)
		ui.close(&cell)
	}
}

// calendar_page_by moves cal's view n months and brings the cursor along.
@(private)
calendar_page_by :: proc(cal: ^Calendar, n: int, o: Calendar_Options) {
	cal.view = date_add_months(cal.view, n)
	cursor_into_view(cal, o)
}

// Day_Grid is one month grid's inputs.
@(private)
Day_Grid :: struct {
	id:    ops.Area_Id, // the calendar's
	month: Date,
	band:  Day_Band,
	look:  Calendar_Look,
	o:     Calendar_Options,
	state: Interaction,
}

// day_grid is one month: the weekday initials over six week rows of
// day cells, the month's days in their weekday columns and the cells
// before and after it empty. It is a grid named by its month, each week
// a row of it and each day a cell named by its full date, selected,
// disabled and current-date as it is; the weekday initials are column
// headers named by the full weekday. hovered becomes the day under the
// pointer; it reports the day picked.
@(private)
day_grid :: proc(gtx: ^ui.Ctx, cal: ^Calendar, g: Day_Grid, hovered: ^Date) -> (picked: Date) {
	p := ui.widget_open(
		gtx,
		key = u64(ui.id_mix(g.id, u64(0x6d00 + g.month.year * 12 + g.month.month))),
	)
	title := fmt.aprintf(
		"%s %d",
		timefmt.MONTHS[g.month.month - 1],
		g.month.year,
		allocator = gtx.allocator,
	)
	ui.semantics(gtx, &p, {role = .Grid, label = title})
	weekday_row(gtx, &p, g.o.week_start)
	first := week_first(g.month, g.o.week_start)
	for w in 0 ..< CALENDAR_WEEKS {
		row_id := ui.id_mix(p.id, u64(0x500 + w))
		row_rect := ops.Rect {
			0,
			CALENDAR_WEEKDAYS_H + f32(w) * CALENDAR_CELL,
			CALENDAR_GRID_W,
			CALENDAR_CELL,
		}
		ui.part_semantics(gtx, &p, row_id, row_rect, {role = .Row})
		for c in 0 ..< 7 {
			day := date_add_days(first, w * 7 + c)
			if day.month != g.month.month {
				continue
			}
			cell := ops.Rect{f32(c) * CALENDAR_CELL, row_rect.y, CALENDAR_CELL, CALENDAR_CELL}
			if day_cell(gtx, &p, row_id, cal, g, day, cell, hovered) {
				picked = day
			}
		}
	}
	ui.widget_close(gtx, &p, {size = {CALENDAR_GRID_W, CALENDAR_GRID_H}})
	return
}

// weekday_row draws the weekday initials, two letters in caption type
// and --fgColor-muted, as a row of column headers.
@(private)
weekday_row :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, week_start: int) {
	head := ui.id_mix(p.id, 0x4ff)
	ui.part_semantics(gtx, p, head, {0, 0, CALENDAR_GRID_W, CALENDAR_WEEKDAYS_H}, {role = .Row})
	for c in 0 ..< 7 {
		name := timefmt.DAYS[(week_start + c) %% 7]
		t := shape_text(gtx, name[:2], .Caption)
		r := ops.Rect{f32(c) * CALENDAR_CELL, 0, CALENDAR_CELL, CALENDAR_WEEKDAYS_H}
		draw_text(
			gtx,
			t,
			{r.x + (r.w - t.width) / 2, (r.h - t.height) / 2},
			color(.Fg_Color_Muted),
		)
		ui.part_semantics(
			gtx,
			p,
			ui.id_mix(p.id, u64(0x400 + c)),
			r,
			{role = .Column_Header, label = name},
			under = head,
		)
	}
}

// day_cell is one day's cell in g's grid p, under its week's row: it
// reads the cell's input, paints it and declares it. Only the cursor's
// day is a Tab stop. It reports a pick.
@(private)
day_cell :: proc(
	gtx: ^ui.Ctx,
	p: ^ui.Placement,
	row_id: ops.Area_Id,
	cal: ^Calendar,
	g: Day_Grid,
	day: Date,
	cell: ops.Rect,
	hovered: ^Date,
) -> bool {
	id := calendar_cell_id(g.id, day)
	can := date_selectable(g.o, day)
	st := g.state
	switch {
	case !can:
		st = .Disabled
	case g.state != .Live && g.state != .Disabled && day != cal.cursor:
		// A forced state shows on the cursor's day; the rest rest.
		st = .Enabled
	}
	c := control(gtx, id, cell, st)
	if c.hovered && c.st != nil {
		hovered^ = day
	}
	if c.clicked {
		cal.cursor = day
	}
	mark := paint_day(gtx, c, cell, day, g)
	listen(gtx, c.st, id, cell, no_tab = day != cal.cursor)
	label := day_label(day, gtx.allocator)
	ops.tag(gtx.scene, id, label, cell)
	states :=
		design.state_if(mark.selected, {.Selected}) +
		design.state_if(c.disabled, {.Disabled}) +
		design.state_if(day == g.look.today, {.Current_Date})
	ui.part_semantics(
		gtx,
		p,
		id,
		cell,
		{role = .Grid_Cell, label = label, states = states},
		under = row_id,
	)
	return c.clicked
}

// day_label is a day cell's name and tag: Monday, October 5, 2026.
day_label :: proc(d: Date, allocator := context.allocator) -> string {
	return fmt.aprintf(
		"%s, %s %d, %d",
		timefmt.DAYS[weekday(d)],
		timefmt.MONTHS[d.month - 1],
		d.day,
		d.year,
		allocator = allocator,
	)
}

// Day_Mark is how paint_day drew a day: in the selection or not.
@(private)
Day_Mark :: struct {
	selected: bool,
}

// paint_day paints day in cell: the range band behind it (--bgColor-
// accent-muted, from its centre on the band's first day and to it on its
// last), the selection's fill on a picked end, a 1px --borderColor-
// accent-emphasis ring on a proposed end, else the hover and press fill;
// then the day's number, semibold --fgColor-accent for today,
// --fgColor-onEmphasis on the fill, --fgColor-disabled when it cannot be
// picked; then the focus outline.
@(private)
paint_day :: proc(
	gtx: ^ui.Ctx,
	c: Control,
	cell: ops.Rect,
	day: Date,
	g: Day_Grid,
) -> (
	m: Day_Mark,
) {
	b := g.band
	rr := ops.Round_Rect{cell, tok.BORDER_RADIUS_MEDIUM}
	inside := b.lo != {} && !date_less(day, b.lo) && !date_less(b.hi, day)
	end := inside && (day == b.lo || day == b.hi)
	m.selected = inside && day != b.preview
	if inside && b.lo != b.hi {
		paint_band(gtx, cell, day, b, g.o.week_start)
	}
	filled := end && day != b.preview
	switch {
	case filled:
		ops.fill(gtx.scene, rr, color(.Bg_Color_Accent_Emphasis))
	case day == b.preview:
		stroke_inside(gtx, rr, color(.Border_Color_Accent_Emphasis), tok.BORDER_WIDTH_THIN)
	case !c.disabled:
		bg := blend(
			gtx,
			c,
			0,
			color_for(
				{
					.Control_Transparent_Bg_Color_Rest,
					.Control_Transparent_Bg_Color_Hover,
					.Control_Transparent_Bg_Color_Active,
					.Control_Transparent_Bg_Color_Rest,
				},
				c,
			),
		)
		if ui.painted(bg) {
			ops.fill(gtx.scene, rr, bg)
		}
	}
	today := day == g.look.today
	st := style(.Body_Medium)
	fg := tok.Role.Fg_Color_Default
	switch {
	case c.disabled:
		fg = .Fg_Color_Disabled
	case filled:
		fg, st.weight = .Fg_Color_On_Emphasis, tok.BASE_TEXT_WEIGHT_SEMIBOLD
	case today:
		fg, st.weight = .Fg_Color_Accent, tok.BASE_TEXT_WEIGHT_SEMIBOLD
	}
	t := design.shape_style(gtx, fmt.tprintf("%d", day.day), st, font_for(gtx, st.weight))
	draw_text(
		gtx,
		t,
		{cell.x + (cell.w - t.width) / 2, cell.y + (cell.h - t.height) / 2},
		color(fg),
	)
	if filled {
		paint_focus_on_emphasis(gtx, c, rr)
	} else {
		paint_focus_outline(gtx, c, rr)
	}
	return
}

// paint_band paints day's piece of b's band in cell: from the centre on
// its first day, to the centre on its last, else across, with the
// medium radius where a week row starts or ends it.
@(private)
paint_band :: proc(gtx: ^ui.Ctx, cell: ops.Rect, day: Date, b: Day_Band, week_start: int) {
	band := cell
	if day == b.lo {
		band.x, band.w = cell.x + cell.w / 2, cell.w / 2
	} else if day == b.hi {
		band.w = cell.w / 2
	}
	col := (weekday(day) - week_start) %% 7
	r := tok.BORDER_RADIUS_MEDIUM
	k := Corners{}
	if col == 0 && day != b.lo {
		k.tl, k.bl = r, r
	}
	if col == 6 && day != b.hi {
		k.tr, k.br = r, r
	}
	ops.fill(gtx.scene, rounded(gtx, band, k), color(.Bg_Color_Accent_Muted))
}

// calendar_months_page is the months of cal's year to jump to: the year
// between previous and next chevrons, then three columns of month
// buttons, the shown month's a default button and the rest invisible,
// a month wholly outside the bounds disabled. It keeps the days page's
// size, so the overlay holds still. Choosing one shows it.
@(private)
calendar_months_page :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	cal: ^Calendar,
	o: Calendar_Options,
	state: Interaction,
) {
	w := calendar_width(o)
	nav := button_metrics(.Small).height
	sz := ui.sized_open(
		gtx,
		{{w, nav + CALENDAR_HEADER_GAP + CALENDAR_GRID_H}, {w, ui.INF}},
		key = u64(ui.id_mix(id, 50)),
	)
	defer ui.close(&sz)
	col := ui.column_open(
		gtx,
		gap = CALENDAR_HEADER_GAP,
		align = .Fill,
		key = u64(ui.id_mix(id, 51)),
	)
	defer ui.close(&col)
	{
		line := ui.row_open(gtx, align = .Center, key = u64(ui.id_mix(id, 52)))
		defer ui.close(&line)
		prev := o.min_date != {} && o.min_date.year > cal.year - 1 ? Interaction.Disabled : state
		if icon_button(
			gtx,
			.Chevron_Left,
			"Previous year",
			.Invisible,
			.Small,
			no_tooltip = true,
			state = prev,
			key = u64(ui.id_mix(id, 53)),
		) {
			cal.year -= 1
		}
		ui.flexible(gtx, 1)
		{
			c := ui.centered_open(gtx, key = u64(ui.id_mix(id, 54)))
			text(
				gtx,
				fmt.tprintf("%d", cal.year),
				weight = .Semibold,
				key = u64(ui.id_mix(id, 56)),
			)
			ui.close(&c)
		}
		next := o.max_date != {} && o.max_date.year < cal.year + 1 ? Interaction.Disabled : state
		if icon_button(
			gtx,
			.Chevron_Right,
			"Next year",
			.Invisible,
			.Small,
			no_tooltip = true,
			state = next,
			key = u64(ui.id_mix(id, 55)),
		) {
			cal.year += 1
		}
	}
	for r in 0 ..< 4 {
		line := ui.row_open(gtx, gap = CALENDAR_HEADER_GAP, key = u64(ui.id_mix(id, u64(60 + r))))
		for c in 0 ..< 3 {
			m := r * 3 + c + 1
			ui.flexible(gtx, 1)
			if month_button(gtx, id, cal, m, o, state) {
				cal.view = {cal.year, m, 1}
				cursor_into_view(cal, o)
				cal.page, cal.refocus = .Days, true
			}
		}
		ui.close(&line)
	}
}

// month_button is month m of cal's year on the months page, as a block
// button: default for the month shown, invisible for the rest, disabled
// when no day of it can be picked within the bounds.
@(private)
month_button :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	cal: ^Calendar,
	m: int,
	o: Calendar_Options,
	state: Interaction,
) -> bool {
	first := Date{cal.year, m, 1}
	last := Date{cal.year, m, days_in_month(cal.year, m)}
	st := state
	if (o.min_date != {} && date_less(last, o.min_date)) ||
	   (o.max_date != {} && date_less(o.max_date, first)) {
		st = .Disabled
	}
	shown := cal.view.year == cal.year && cal.view.month == m
	label := timefmt.MONTHS[m - 1][:3]
	return button(
		gtx,
		label,
		shown ? .Default : .Invisible,
		.Medium,
		block = true,
		name = timefmt.MONTHS[m - 1],
		state = st,
		key = u64(ui.id_mix(id, u64(0x700 + m))),
	)
}
