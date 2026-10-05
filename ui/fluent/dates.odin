package fluent

import "core:fmt"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// The dates: calendar, date picker and time picker on the fluent-kit's
// calendar.json, date-picker.json and time-picker.json (the compat
// packages react-calendar-compat, react-datepicker-compat and
// react-timepicker-compat at the kit's commit). Every dimension is a
// constant in their styles files, cited as file:lines where used; every
// colour is an alias token chosen per state through State_Roles and
// color_for.
//
// Departures: the calendar picks single days (dateRangeType day); week,
// work-week and month ranges, week numbers and the month picker as an
// overlay are not built. Keyboard arrows move a cursor day the outline
// follows while any day has focus, as jm:ui moves focus only by Tab.
// The navigation slide moves the whole grid, with no transition week
// fading out beside it. The date picker opens when its input takes
// focus or Enter is pressed, and the calendar's Escape closes it; an
// ArrowDown in the input and a click on the icon alone are not seen, as
// input keeps its own events. Its default format is "Mon Sep 28 2026"
// and typed text parses as M/D/YYYY or YYYY-MM-DD, not the platform's
// Date.parse. The time picker is input plus its own option list rather
// than the combobox, which had not landed when this was written; once
// it has, the picker could compose it. High contrast is what the theme
// binds, not the styles' forced-colours rules.
//
// Time and the formats here are this package's own; Date and the
// calendar arithmetic are design's, which primer's pickers share.

// Date and its arithmetic are jm:ui/design's (design/calendar.odin).
Date :: design.Date
days_in_month :: design.days_in_month
weekday :: design.weekday
date_less :: design.date_less
date_add_days :: design.date_add_days
date_add_months :: design.date_add_months

// Time is a time of day.
Time :: struct {
	hour, minute, second: int,
}

MONTH_NAMES := [12]string{"January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"}
MONTH_SHORT := [12]string{"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}
WEEKDAY_SHORT := [7]string{"Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"}
WEEKDAY_LETTERS := [7]string{"S", "M", "T", "W", "T", "F", "S"}

// format_date is d as the platform's Date string reads: "Mon Sep 28 2026".
format_date :: proc(d: Date, allocator := context.allocator) -> string {
	return fmt.aprintf("%s %s %d %d", WEEKDAY_SHORT[weekday(d)], MONTH_SHORT[d.month - 1], d.day, d.year, allocator = allocator)
}

// parse_date reads M/D/YYYY or YYYY-MM-DD, with any whitespace around
// it, into a valid Date.
parse_date :: proc(s: string) -> (d: Date, ok: bool) {
	t := strings.trim_space(s)
	sep := strings.contains(t, "/") ? "/" : "-"
	parts := strings.split(t, sep, context.temp_allocator)
	if len(parts) != 3 {
		return
	}
	n: [3]int
	for p, i in parts {
		v, pok := strconv.parse_int(strings.trim_space(p), 10)
		if !pok {
			return
		}
		n[i] = v
	}
	if sep == "/" {
		d = {n[2], n[0], n[1]}
	} else {
		d = {n[0], n[1], n[2]}
	}
	ok = d.year >= 1 && d.month >= 1 && d.month <= 12 && d.day >= 1 && d.day <= days_in_month(d.year, d.month)
	return
}

// Calendar dimensions (useCalendarDayGridStyles.styles.ts,
// useCalendarDayStyles.styles.ts, useCalendarPickerStyles.styles.ts,
// useCalendarStyles.styles.ts: calendar.json layout and hard-coded note).
CALENDAR_WIDTH :: f32(220) // one picker: 12px padding around 196px of content
CALENDAR_PAD :: f32(12)
CALENDAR_CONTENT :: f32(196)
CALENDAR_HEADER_H :: f32(28)
CALENDAR_NAV :: f32(28) // a navigation button's square
CALENDAR_CELL :: f32(28) // a day cell, 2px around its 24px button
CALENDAR_DAY_BUTTON :: f32(24)
CALENDAR_GRID_TOP :: f32(4)
CALENDAR_GRID_BOTTOM :: f32(10)
CALENDAR_TODAY :: f32(20) // today's disc
CALENDAR_MARK :: f32(4) // a marked day's dot, 1px above the cell's bottom
CALENDAR_ITEM :: f32(40) // a month or year button
CALENDAR_ITEM_COL_GAP :: f32(12)
CALENDAR_ITEM_ROW_GAP :: f32(16)
CALENDAR_GO_TODAY_H :: f32(30)
CALENDAR_GO_TODAY_TOP :: f32(3)
CALENDAR_GO_TODAY_RIGHT :: f32(16)
CALENDAR_SLIDE :: f32(20) // the grid's travel on navigation (calendarMotions.tsx:41-43,81-85)
CALENDAR_YEARS :: 12 // years per page (CalendarYear.tsx CELL_COUNT)

// Month_Picker is where the month and year pickers sit: beside the day
// grid (440px wide, the default), or not at all.
Month_Picker :: enum u8 {
	Beside,
	None,
}

// Calendar_Result is what a calendar frame reported.
Calendar_Result :: struct {
	picked:    bool, // a day was chosen this frame; selected^ holds it
	dismissed: bool, // Escape on a day
}

// Calendar_Page is which picker a column shows.
@(private = "file")
Calendar_Page :: enum u8 {
	Months,
	Years,
}

// Calendar_Data is a calendar's own state between frames: the cursor
// day the arrow keys move, the month picker column's page and year
// range, and the navigation slide.
@(private = "file")
Calendar_Data :: struct {
	cursor:     Date,
	page:       Calendar_Page,
	year_base:  int, // the year picker's first year, 0 until set
	slide:      ui.Tween,
	slide_dir:  f32, // -1 up (earlier), 1 down (later)
	seen_view:  Date,
	pick_slide: ui.Tween,
	pick_dir:   f32,
}

// Nav_Roles are the header and navigation buttons' backgrounds and
// text: brand-inverted fills with the brand-on-light foregrounds, a
// pairing the calendar alone uses (calendar.json gotcha).
@(private = "file")
NAV_BG :: State_Roles{.Transparent_Background, .Brand_Background_Inverted_Hover, .Brand_Background_Inverted_Pressed, .Transparent_Background}
@(private = "file")
NAV_FG3 :: State_Roles{.Neutral_Foreground3, .Brand_Foreground_On_Light_Hover, .Brand_Foreground_On_Light_Pressed, .Neutral_Foreground_Disabled}
@(private = "file")
NAV_FG1 :: State_Roles{.Neutral_Foreground1, .Brand_Foreground_On_Light_Hover, .Brand_Foreground_On_Light_Pressed, .Neutral_Foreground_Disabled}
@(private = "file")
ITEM_FG :: State_Roles{.Neutral_Foreground3, .Neutral_Foreground1_Static, .Neutral_Foreground1_Static, .Neutral_Foreground_Disabled}
@(private = "file")
DAY_FG :: State_Roles{.Neutral_Foreground1, .Neutral_Foreground1, .Neutral_Foreground1, .Neutral_Foreground_Disabled}

// calendar is the month grid with its header, the month and year
// pickers beside it, and the go-to-today button (calendar.json). view
// is the month shown and moves with the navigation; selected is the
// chosen day, the zero Date for none; today draws its disc; marked
// days carry the dot. A day outside [min, max] takes no pointer.
calendar :: proc(
	gtx: ^ui.Ctx,
	selected: ^Date,
	view: ^Date,
	today: Date,
	marked: []Date = nil,
	month_picker := Month_Picker.Beside,
	go_today := true,
	min_date := Date{},
	max_date := Date{},
	highlight_current_month := false,
	highlight_selected_month := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Calendar_Result) {
	p := ui.widget_open(gtx, key, loc)
	if view.year == 0 {
		view^ = selected.year != 0 ? selected^ : today
	}
	view.day = 1
	d := ui.widget_data(gtx, p.id, Calendar_Data)
	live := state == .Live
	if d.cursor.year == 0 {
		d.cursor = selected.year != 0 ? selected^ : today
	}
	if d.seen_view.year == 0 {
		d.seen_view = view^
	}
	beside := month_picker == .Beside
	// A forced state paints one control in it, the cursor day, and the
	// rest at rest, so a gallery shows what the state looks like on a
	// day rather than a grid of it; disabled disables them all.
	btn_state := state == .Live || state == .Disabled ? state : Interaction.Enabled
	w := beside ? 2 * CALENDAR_WIDTH : CALENDAR_WIDTH

	// Day picker header: the month-and-year button (not clickable, as
	// the month picker is never an overlay here) and the navigation
	// buttons, whose click moves view before the grid lays out.
	x0, y0 := CALENDAR_PAD, CALENDAR_PAD
	header_title := fmt.tprintf("%s %d", MONTH_NAMES[view.month - 1], view.year)
	ui.semantics(gtx, &p, {role = .Group, label = ui.frame_string(gtx, header_title)})
	header_button(gtx, &p, 1, {x0, y0, CALENDAR_CONTENT - 2 * CALENDAR_NAV, CALENDAR_HEADER_H}, header_title, false, btn_state)
	if nav_button(gtx, &p, 2, {x0 + CALENDAR_CONTENT - 2 * CALENDAR_NAV, y0, CALENDAR_NAV, CALENDAR_NAV}, .Arrow_Up, NAV_FG3, "Previous month", btn_state) {
		view^ = date_add_months(view^, -1)
	}
	if nav_button(gtx, &p, 3, {x0 + CALENDAR_CONTENT - CALENDAR_NAV, y0, CALENDAR_NAV, CALENDAR_NAV}, .Arrow_Down, NAV_FG3, "Next month", btn_state) {
		view^ = date_add_months(view^, 1)
	}
	if view^ != d.seen_view {
		// A change slides the grid in from the direction it came
		// (calendar.json behaviour grid-motion).
		d.slide_dir = date_less(d.seen_view, view^) ? 1 : -1
		d.slide = {to = 1, duration = tok.DURATION_SLOWER / 1000}
		d.seen_view = view^
	}
	slide := live ? (1 - bezier_ease(tok.CURVE_DECELERATE_MAX, ui.tween_update(&d.slide, gtx))) * CALENDAR_SLIDE * d.slide_dir : 0
	weeks := week_count(view^)
	grid_h := CALENDAR_GRID_TOP + f32(weeks + 1) * CALENDAR_CELL + CALENDAR_GRID_BOTTOM
	col_h := 2 * CALENDAR_PAD + CALENDAR_HEADER_H + grid_h
	picker_h := 2 * CALENDAR_PAD + CALENDAR_HEADER_H + CALENDAR_GRID_TOP + 3 * CALENDAR_ITEM + 2 * CALENDAR_ITEM_ROW_GAP
	h := max(col_h, beside ? picker_h : 0)
	if go_today {
		h += CALENDAR_GO_TODAY_TOP + CALENDAR_GO_TODAY_H
	}
	sz := ui.constrain(gtx.constraints, {w, h})

	gy := y0 + CALENDAR_HEADER_H + CALENDAR_GRID_TOP
	// Weekday labels, then the weeks: the grid's first day is the Sunday
	// on or before the 1st (firstDayOfWeek sunday).
	for i in 0 ..< 7 {
		cx := x0 + f32(i) * CALENDAR_CELL
		t := shape_style(gtx, WEEKDAY_LETTERS[i], control_style(.Small, tok.FONT_WEIGHT_REGULAR))
		draw_text(gtx, t, {cx + (CALENDAR_CELL - t.width) / 2, gy + (CALENDAR_CELL - t.height) / 2}, color(.Neutral_Foreground1))
	}
	grid := ops.Rect{x0, gy + CALENDAR_CELL, CALENDAR_CONTENT, f32(weeks) * CALENDAR_CELL}
	// The weeks are a grid named as the header reads, and each day a
	// cell of it; the calendar stays a group, as the pickers beside the
	// grid and the go-to-today button are its parts too.
	grid_id := ui.id_mix(p.id, 99)
	ui.part_semantics(gtx, &p, grid_id, grid, {role = .Grid, label = ui.frame_string(gtx, header_title)})
	ops.clip_push(gtx.scene, grid)
	first := date_add_days(view^, -weekday(view^))
	focused_any := false
	key_pick := false
	for wk in 0 ..< weeks {
		for wd in 0 ..< 7 {
			day := date_add_days(first, wk * 7 + wd)
			cell := ops.Rect{grid.x + f32(wd) * CALENDAR_CELL, grid.y + f32(wk) * CALENDAR_CELL + slide, CALENDAR_CELL, CALENDAR_CELL}
			id := ui.id_mix(p.id, u64(100 + wk * 7 + wd))
			out_of_bounds := (min_date.year != 0 && date_less(day, min_date)) || (max_date.year != 0 && date_less(max_date, day))
			st := state
			if state != .Live && state != .Disabled && day != d.cursor {
				st = .Enabled
			}
			if out_of_bounds {
				st = .Disabled
			}
			c := control(gtx, id, cell, st)
			if c.st != nil {
				for e in ui.events(gtx, id) {
					if e.kind != .Key {
						continue
					}
					#partial switch e.key {
					case .Left:
						d.cursor = date_add_days(d.cursor, -1)
					case .Right:
						d.cursor = date_add_days(d.cursor, 1)
					case .Up:
						d.cursor = date_add_days(d.cursor, -7)
					case .Down:
						d.cursor = date_add_days(d.cursor, 7)
					case .Home:
						d.cursor = date_add_days(d.cursor, -weekday(d.cursor))
					case .End:
						d.cursor = date_add_days(d.cursor, 6 - weekday(d.cursor))
					case .Page_Up:
						d.cursor = date_add_months(d.cursor, -1)
					case .Page_Down:
						d.cursor = date_add_months(d.cursor, 1)
					case .Enter, .Space:
						key_pick = true // the activation below picks the cursor, not this cell
					case .Escape:
						r.dismissed = true
					}
				}
				if c.focused {
					focused_any = true
				}
			}
			if c.clicked {
				if !key_pick {
					d.cursor = day
				}
				selected^ = d.cursor
				r.picked = true
			}
			paint_day(gtx, c, cell, day, view^, today, selected^, marked, out_of_bounds)
			listen(gtx, c.st, id, cell)
			said := fmt.aprintf("%d %s %d", day.day, MONTH_SHORT[day.month - 1], day.year, allocator = gtx.allocator)
			ops.tag(gtx.scene, id, said)
			ui.part_semantics(gtx, &p, id, cell, {role = .Grid_Cell, label = said, states = design.state_if(day == selected^, {.Selected}) + design.state_if(c.disabled, {.Disabled})}, under = grid_id)
		}
	}
	ops.clip_pop(gtx.scene)
	if live && (d.cursor.month != view.month || d.cursor.year != view.year) && focused_any {
		// The cursor left the shown month by keyboard: follow it.
		view^ = {d.cursor.year, d.cursor.month, 1}
		ui.request_frame(gtx)
	}
	if focused_any && ui.focus_visible(gtx) {
		off := week_of(first, d.cursor)
		if off >= 0 && off < weeks * 7 {
			cell := ops.Rect{grid.x + f32(off % 7) * CALENDAR_CELL, grid.y + f32(off / 7) * CALENDAR_CELL + slide, CALENDAR_CELL, CALENDAR_CELL}
			fc: Control
			fc.focus_visible = true
			paint_focus_outline(gtx, fc, {cell, tok.BORDER_RADIUS_MEDIUM})
		}
	}

	// Month and year pickers beside the day grid, over a 1px divider.
	if beside {
		ops.fill(gtx.scene, ops.Rect{CALENDAR_WIDTH - 1, 0, 1, col_h}, color(.Neutral_Stroke2))
		px := CALENDAR_WIDTH + CALENDAR_PAD
		if d.year_base == 0 || view.year < d.year_base || view.year >= d.year_base + CALENDAR_YEARS {
			d.year_base = view.year - (view.year % CALENDAR_YEARS)
		}
		title := d.page == .Months ? fmt.tprintf("%d", view.year) : fmt.tprintf("%d - %d", d.year_base, d.year_base + CALENDAR_YEARS - 1)
		if header_button(gtx, &p, 4, {px, y0, CALENDAR_CONTENT - 2 * CALENDAR_NAV, CALENDAR_HEADER_H}, title, true, btn_state) {
			d.page = d.page == .Months ? .Years : .Months
		}
		step := d.page == .Months ? 1 : CALENDAR_YEARS
		if nav_button(gtx, &p, 5, {px + CALENDAR_CONTENT - 2 * CALENDAR_NAV, y0, CALENDAR_NAV, CALENDAR_NAV}, .Arrow_Up, NAV_FG1, "Previous year", btn_state) {
			if d.page == .Months {
				view^ = date_add_months(view^, -12)
			} else {
				d.year_base -= step
			}
		}
		if nav_button(gtx, &p, 6, {px + CALENDAR_CONTENT - CALENDAR_NAV, y0, CALENDAR_NAV, CALENDAR_NAV}, .Arrow_Down, NAV_FG1, "Next year", btn_state) {
			if d.page == .Months {
				view^ = date_add_months(view^, 12)
			} else {
				d.year_base += step
			}
		}
		for i in 0 ..< 12 {
			ix := px + f32(i % 4) * (CALENDAR_ITEM + CALENDAR_ITEM_COL_GAP)
			iy := y0 + CALENDAR_HEADER_H + CALENDAR_GRID_TOP + f32(i / 4) * (CALENDAR_ITEM + CALENDAR_ITEM_ROW_GAP)
			item := ops.Rect{ix, iy, CALENDAR_ITEM, CALENDAR_ITEM}
			label: string
			current, chosen: bool
			if d.page == .Months {
				label = MONTH_SHORT[i]
				current = highlight_current_month && today.year == view.year && today.month == i + 1
				chosen = highlight_selected_month && selected.year == view.year && selected.month == i + 1
			} else {
				label = fmt.tprintf("%d", d.year_base + i)
				current = highlight_current_month && today.year == d.year_base + i
				chosen = highlight_selected_month && selected.year == d.year_base + i
			}
			if picker_item(gtx, &p, u64(200 + i), item, label, current, chosen, btn_state) {
				if d.page == .Months {
					view^ = {view.year, i + 1, 1}
				} else {
					view^ = {d.year_base + i, view.month, 1}
					d.page = .Months
				}
			}
		}
	}

	if go_today {
		t := shape_style(gtx, "Go to today", control_style(.Small, tok.FONT_WEIGHT_REGULAR))
		bw := t.width + 2 * tok.SPACING_HORIZONTAL_XS
		by := (beside ? max(col_h, picker_h) : col_h) + CALENDAR_GO_TODAY_TOP
		br := ops.Rect{sz.x - CALENDAR_GO_TODAY_RIGHT - bw, by, bw, CALENDAR_GO_TODAY_H}
		id := ui.id_mix(p.id, 7)
		c := control(gtx, id, br, btn_state)
		if c.clicked {
			view^ = {today.year, today.month, 1}
			d.cursor = today
		}
		fg := color_for(State_Roles{.Neutral_Foreground1, .Brand_Foreground1, .Brand_Foreground2, .Neutral_Foreground_Disabled}, c)
		draw_text(gtx, t, {br.x + tok.SPACING_HORIZONTAL_XS, br.y + (br.h - t.height) / 2}, fg)
		paint_focus_outline(gtx, c, {br, tok.BORDER_RADIUS_MEDIUM})
		listen(gtx, c.st, id, br)
		ops.tag(gtx.scene, id, "Go to today")
		ui.part_semantics(gtx, &p, id, br, {role = .Button, label = "Go to today", states = design.state_if(c.disabled, {.Disabled})})
	}
	if view^ != d.seen_view {
		// The month picker or go-to-today moved view after the grid laid
		// out: the next frame lays out the new month, and may be a
		// different height.
		ui.request_frame(gtx)
	}
	ui.widget_close(gtx, &p, {size = sz})
	return
}

// week_count is the rows a month needs from the Sunday on or before its
// first day: 4 to 6 (calendar.json layout grid).
@(private = "file")
week_count :: proc(view: Date) -> int {
	first := Date{view.year, view.month, 1}
	lead := weekday(first)
	return (lead + days_in_month(view.year, view.month) + 6) / 7
}

// week_of is the cell index of day counted from the grid's first day, or
// negative when before it.
@(private = "file")
week_of :: proc(first, day: Date) -> int {
	n := 0
	d := first
	for n < 42 {
		if d == day {
			return n
		}
		if date_less(day, d) {
			return -1
		}
		d = date_add_days(d, 1)
		n += 1
	}
	return -1
}

// header_button is the month-and-year button, or a picker's current
// item button: semibold base300 text padded 0 4px 0 10px on a 28px
// line, clickable only where a picker can open from it
// (useCalendarDayStyles.styles.ts, useCalendarPickerStyles.styles.ts).
@(private = "file")
header_button :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, key: u64, r: ops.Rect, text: string, clickable: bool, state: Interaction) -> bool {
	id := ui.id_mix(p.id, key)
	c: Control
	if clickable {
		c = control(gtx, id, r, state)
	}
	t := shape_style(gtx, text, control_style(.Medium, tok.FONT_WEIGHT_SEMIBOLD))
	if clickable {
		bg := color_for(NAV_BG, c)
		if ui.painted(bg) {
			ops.fill(gtx.scene, ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}, bg)
		}
	}
	fg := clickable ? color_for(NAV_FG1, c) : color(state == .Disabled ? .Neutral_Foreground_Disabled : .Neutral_Foreground1)
	ops.clip_push(gtx.scene, r)
	draw_text(gtx, t, {r.x + 10, r.y + (r.h - t.height) / 2}, fg)
	ops.clip_pop(gtx.scene)
	said := ui.frame_string(gtx, text)
	if clickable {
		paint_focus_outline(gtx, c, {r, tok.BORDER_RADIUS_MEDIUM})
		listen(gtx, c.st, id, r)
		ops.tag(gtx.scene, id, said)
		ui.part_semantics(gtx, p, id, r, {role = .Button, label = said, states = design.state_if(c.disabled, {.Disabled})})
	} else {
		ui.part_semantics(gtx, p, id, r, {role = .Heading, label = said})
	}
	return c.clicked
}

// nav_button is a 28px navigation button: transparent, the icon in fg's
// roles, brand-inverted fills on hover and press
// (useCalendarDayStyles.styles.ts, useCalendarPickerStyles.styles.ts).
@(private = "file")
nav_button :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, key: u64, r: ops.Rect, ic: Icon, fg: State_Roles, name: string, state: Interaction) -> bool {
	id := ui.id_mix(p.id, key)
	c := control(gtx, id, r, state)
	bg := color_for(NAV_BG, c)
	if ui.painted(bg) {
		ops.fill(gtx.scene, ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}, bg)
	}
	icon(gtx, ic, {r.x + (r.w - 16) / 2, r.y + (r.h - 16) / 2}, 16, color_for(fg, c))
	paint_focus_outline(gtx, c, {r, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, id, r)
	ops.tag(gtx.scene, id, name)
	ui.part_semantics(gtx, p, id, r, {role = .Button, label = name, states = design.state_if(c.disabled, {.Disabled})})
	return c.clicked
}

// picker_item is a 40px month or year button (useCalendarPickerStyles.
// styles.ts): Foreground3 base200 text, hover and press in the inverted
// brand fills with Foreground1_Static text, the current or selected one
// highlighted when asked.
@(private = "file")
picker_item :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, key: u64, r: ops.Rect, text: string, current, chosen: bool, state: Interaction) -> bool {
	id := ui.id_mix(p.id, key)
	c := control(gtx, id, r, state)
	bg := color_for(State_Roles{.Transparent_Background, .Brand_Background_Inverted_Hover, .Brand_Background_Inverted_Pressed, .Transparent_Background}, c)
	fg := color_for(ITEM_FG, c)
	weight := tok.FONT_WEIGHT_REGULAR
	if current {
		bg, fg, weight = color(.Brand_Background), color(.Neutral_Foreground_On_Brand), tok.FONT_WEIGHT_SEMIBOLD
	} else if chosen {
		bg = color(c.pressed ? .Brand_Background_Inverted_Pressed : .Brand_Background_Inverted_Selected)
		fg, weight = color(.Neutral_Foreground1_Static), tok.FONT_WEIGHT_SEMIBOLD
	}
	if ui.painted(bg) {
		ops.fill(gtx.scene, ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}, bg)
	}
	t := shape_style(gtx, text, control_style(.Small, weight))
	draw_text(gtx, t, {r.x + (r.w - t.width) / 2, r.y + (r.h - t.height) / 2}, fg)
	paint_focus_outline(gtx, c, {r, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, id, r)
	said := ui.frame_string(gtx, text)
	ops.tag(gtx.scene, id, said)
	ui.part_semantics(gtx, p, id, r, {role = .Button, label = said, states = design.state_if(current || chosen, {.Selected}) + design.state_if(c.disabled, {.Disabled})})
	return c.clicked
}

// paint_day paints one day cell: the 24px button's hover and press
// fills, a single selected day's tint and Brand_Stroke1 border, today's
// 20px disc, the number in the month's or the outside-month colour, and
// the marked-day dot (useCalendarDayGridStyles.styles.ts, calendar.json
// states).
@(private = "file")
paint_day :: proc(gtx: ^ui.Ctx, c: Control, cell: ops.Rect, day, view, today, selected: Date, marked: []Date, out_of_bounds: bool) {
	btn := ops.Rect{cell.x + 2, cell.y + 2, CALENDAR_DAY_BUTTON, CALENDAR_DAY_BUTTON}
	rr := ops.Round_Rect{btn, tok.BORDER_RADIUS_MEDIUM}
	is_selected := day == selected
	is_today := day == today
	outside := day.month != view.month
	bg := color_for(State_Roles{.Transparent_Background, .Brand_Background_Inverted_Hover, .Brand_Background_Inverted_Pressed, .Transparent_Background}, c)
	fg := color_for(DAY_FG, c)
	if outside && !c.disabled {
		fg = color(.Neutral_Foreground4)
	}
	if is_selected {
		bg = color(.Brand_Background_Inverted_Selected)
		fg = color(.Neutral_Foreground1_Static)
	}
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	if is_selected {
		stroke_inside(gtx, rr, color(.Brand_Stroke1), tok.STROKE_WIDTH_THIN)
	}
	weight := tok.FONT_WEIGHT_REGULAR
	if is_today {
		disc := ops.Rect{cell.x + (cell.w - CALENDAR_TODAY) / 2, cell.y + (cell.h - CALENDAR_TODAY) / 2, CALENDAR_TODAY, CALENDAR_TODAY}
		ops.fill(gtx.scene, ops.Ellipse{disc}, color(.Brand_Background))
		fg = color(.Neutral_Foreground_On_Brand)
		weight = tok.FONT_WEIGHT_SEMIBOLD
	}
	if out_of_bounds {
		fg = color(.Neutral_Foreground_Disabled)
	}
	t := shape_style(gtx, fmt.tprintf("%d", day.day), control_style(.Small, weight))
	draw_text(gtx, t, {cell.x + (cell.w - t.width) / 2, cell.y + (cell.h - t.height) / 2}, fg)
	for m in marked {
		if m == day {
			dot := color(is_today ? .Neutral_Foreground_On_Brand : .Brand_Foreground2)
			ops.fill(gtx.scene, ops.Ellipse{{cell.x + (cell.w - CALENDAR_MARK) / 2, cell.y + cell.h - 1 - CALENDAR_MARK, CALENDAR_MARK, CALENDAR_MARK}}, dot)
			break
		}
	}
}

// Date picker.

// Date_Picker_Appearance is the Input appearance the picker shows:
// outline, underline (underlined) or filled-lighter (borderless).
Date_Picker_Appearance :: enum u8 {
	Outline,
	Underline,
	Filled_Lighter,
}

// Date_Validation is what committing typed text reported.
Date_Validation :: enum u8 {
	Ok,
	Invalid_Input,
	Out_Of_Bounds,
	Required_Input,
}

@(private = "file")
Date_Picker_Data :: struct {
	view:        Date,
	was_focused: bool,
	was_open:    bool,
}

// DATE_POPUP_GAP is the surface's offset below the input (the positioning
// hook's below-start default; date-picker.json layout position).
DATE_POPUP_GAP :: f32(4)

// date_picker is an input with the Calendar icon and the calendar in a
// popup below it (date-picker.json). selected is the value, the zero
// Date for none; s is the input's text, which the picker writes on a
// pick. It opens when the input takes focus or Enter is pressed, and
// closes on a pick, Escape in the calendar or a press outside. With
// allow_text_input the text is parsed on Enter, on losing focus and
// on close, and validation says what it found. Returns true on the
// frame a day is picked.
date_picker :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	selected: ^Date,
	open: ^bool,
	today: Date,
	placeholder := "Select a date",
	appearance := Date_Picker_Appearance.Outline,
	size := Size.Medium,
	allow_text_input := false,
	required := false,
	min_date := Date{},
	max_date := Date{},
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (picked: bool, validation: Date_Validation) {
	// The inner widgets' keys derive from id, as a stack is no scope:
	// two pickers keyed apart must not share an input.
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Date_Picker_Data)
	st := ui.stack_open(gtx, u64(ui.id_mix(id, 5)), loc)
	defer ui.close(&st)
	ia: Input_Appearance
	switch appearance {
	case .Outline:
		ia = .Outline
	case .Underline:
		ia = .Underline
	case .Filled_Lighter:
		ia = .Filled_Lighter
	}
	r := input(gtx, s, placeholder, ia, size, after = .Calendar, width = width, name = name != "" ? name : placeholder, state = state, key = u64(ui.id_mix(id, 1)))
	if state == .Live {
		if r.focused && !d.was_focused {
			open^ = true // focus opens it (date-picker.json behaviour open)
		}
		if r.submitted {
			if allow_text_input {
				validation = commit_date_text(s, selected, required, min_date, max_date)
			}
			open^ = true
		}
		if !r.focused && d.was_focused && allow_text_input && !open^ {
			validation = commit_date_text(s, selected, required, min_date, max_date)
		}
		d.was_focused = r.focused
	}
	if !open^ || state == .Disabled {
		d.was_open = false
		return
	}
	if !d.was_open {
		d.was_open = true
		d.view = selected.year != 0 ? selected^ : today
		d.view.day = 1
	}
	heights := CONTROL_HEIGHT
	input_h := heights[size] // the input's height, as input lays it out
	scrim_id := ui.id_mix(id, 0xffff)
	for e in ui.events(gtx, scrim_id) {
		if e.kind == .Press {
			open^ = false
		}
	}
	// Escape reaches the picker's id by key_interest below whether or not
	// a day holds focus; a focused day reports it as dismissed too.
	for e in ui.events(gtx, id) {
		if e.kind == .Key && e.key == .Escape {
			open^ = false
		}
	}
	// Below the input, flipped above or shifted along it to stay in the
	// window (ui.popup_open).
	ov := ui.popup_open(gtx, {0, 0, 0, input_h}, id, .Below, .Start, DATE_POPUP_GAP)
	ui.key_interest(gtx, id, .Escape)
	ops.input_area(gtx.scene, scrim_id, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	mp := new(Menu_Paint, gtx.allocator)
	mp^ = {id = id, alpha = 1}
	box := ui.box_open(gtx, {padding = ui.pad_all(tok.STROKE_WIDTH_THIN), paint = paint_menu, user = mp}, key = u64(ui.id_mix(id, 2)))
	cr := calendar(gtx, selected, &d.view, today, min_date = min_date, max_date = max_date, state = state, key = u64(ui.id_mix(id, 3)))
	ui.close(&box)
	if cr.picked {
		ui.text_set(s, format_date(selected^, context.temp_allocator))
		picked = true
		validation = .Ok
		open^ = false
	}
	if cr.dismissed {
		open^ = false
	}
	if !open^ {
		if allow_text_input && !picked {
			validation = commit_date_text(s, selected, required, min_date, max_date)
		}
		ov.discard = true
	}
	ui.popup_close(&ov, mp.size)
	return
}

// commit_date_text parses the input's text into selected, reporting
// what it found (date-picker.json behaviour text-input).
@(private = "file")
commit_date_text :: proc(s: ^ui.Text_State, selected: ^Date, required: bool, min_date, max_date: Date) -> Date_Validation {
	text := strings.trim_space(ui.text_string(s))
	if text == "" {
		selected^ = {}
		return required ? .Required_Input : .Ok
	}
	d, ok := parse_date(text)
	if !ok {
		return .Invalid_Input
	}
	if (min_date.year != 0 && date_less(d, min_date)) || (max_date.year != 0 && date_less(max_date, d)) {
		return .Out_Of_Bounds
	}
	selected^ = d
	return .Ok
}

// Time picker.

// Time_Error is what submitting freeform text reported.
Time_Error :: enum u8 {
	None,
	Invalid_Input,
	Out_Of_Bounds,
	Required_Input,
}

// TIME_LIST_MAX_H is the listbox's cap: 416px, twelve items, or 80% of
// the window (time-picker.json layout listbox).
TIME_LIST_MAX_H :: f32(416)

// time_options are the times from start_hour stepping by increment
// minutes while before end_hour, which is exclusive and wraps to the
// next day when not after start_hour (timeMath.ts getDateStartAnchor,
// getDateEndAnchor, getTimesBetween). An increment of 0 or less yields
// none.
time_options :: proc(start_hour := 0, end_hour := 24, increment := 30, allocator := context.allocator) -> []Time {
	if increment <= 0 {
		return nil
	}
	end := end_hour * 60
	if start_hour > end_hour || end_hour == 24 {
		end = (end_hour == 24 ? 0 : end_hour) * 60 + 24 * 60
	}
	out := make([dynamic]Time, allocator)
	for m := start_hour * 60; m < end; m += increment {
		mm := m % (24 * 60)
		append(&out, Time{mm / 60, mm % 60, 0})
	}
	return out[:]
}

// format_time is t as "h:mm AM" in a 12-hour cycle or "HH:mm" in a
// 24-hour one, with ":ss" when seconds (timeMath.ts formatDateToTimeString).
format_time :: proc(t: Time, hour12 := true, seconds := false, allocator := context.allocator) -> string {
	if hour12 {
		h := t.hour % 12
		if h == 0 {
			h = 12
		}
		mer := t.hour < 12 ? "AM" : "PM"
		if seconds {
			return fmt.aprintf("%d:%02d:%02d %s", h, t.minute, t.second, mer, allocator = allocator)
		}
		return fmt.aprintf("%d:%02d %s", h, t.minute, mer, allocator = allocator)
	}
	if seconds {
		return fmt.aprintf("%02d:%02d:%02d", t.hour, t.minute, t.second, allocator = allocator)
	}
	return fmt.aprintf("%02d:%02d", t.hour, t.minute, allocator = allocator)
}

// parse_time reads h:mm or hh:mm, with :ss when seconds, and a trailing
// AM or PM in a 12-hour cycle where hours run 0 to 12; in a 24-hour
// cycle hours run 0 to 24 and no meridiem is accepted
// (timeMath.ts getDateFromTimeString and its four patterns).
parse_time :: proc(s: string, hour12 := true, seconds := false) -> (t: Time, ok: bool) {
	str := strings.trim_space(s)
	mer := ""
	if hour12 {
		if len(str) < 3 {
			return
		}
		mer = strings.to_lower(str[len(str) - 2:], context.temp_allocator)
		if mer != "am" && mer != "pm" {
			return
		}
		str = strings.trim_space(str[:len(str) - 2])
	}
	parts := strings.split(str, ":", context.temp_allocator)
	if len(parts) != (seconds ? 3 : 2) {
		return
	}
	n: [3]int
	for p, i in parts {
		if len(p) == 0 || len(p) > 2 || (i > 0 && len(p) != 2) {
			return
		}
		v, pok := strconv.parse_int(p, 10)
		if !pok {
			return
		}
		n[i] = v
	}
	if n[1] > 59 || n[2] > 59 || n[0] > (hour12 ? 12 : 24) {
		return
	}
	t = {n[0], n[1], n[2]}
	if hour12 {
		if mer == "pm" && t.hour != 12 {
			t.hour += 12
		} else if mer == "am" && t.hour == 12 {
			t.hour = 0
		}
	}
	t.hour %= 24
	return t, true
}

@(private = "file")
Time_Picker_Data :: struct {
	was_focused: bool,
	was_open:    bool,
	submitted:   [32]u8, // the text submitted last, so only a change resubmits
	sub_len:     int,
}

@(private = "file")
submitted_text :: proc(d: ^Time_Picker_Data) -> string {
	return string(d.submitted[:d.sub_len])
}

@(private = "file")
remember_submitted :: proc(d: ^Time_Picker_Data, text: string) {
	d.sub_len = copy(d.submitted[:], text)
}

// time_picker is an input with the Chevron_Down icon and a list of the
// times time_options gives (time-picker.json). selected is the value
// and valid whether one is held; s is the input's text, which a pick
// writes. It opens when the input takes focus or Enter is pressed and
// closes on a pick or a press outside. In freeform, Enter or losing
// focus submits the text when it changed: parsed into selected, or
// reported as an error. Returns true on the frame the value changes.
time_picker :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	selected: ^Time,
	valid: ^bool,
	open: ^bool,
	start_hour := 0,
	end_hour := 24,
	increment := 30,
	hour12 := true,
	seconds := false,
	freeform := false,
	required := false,
	placeholder := "Select a time",
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	window_h: f32 = 0,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (changed: bool, err: Time_Error) {
	id := ui.claim_id(gtx, key, loc)
	d := ui.widget_data(gtx, id, Time_Picker_Data)
	st := ui.stack_open(gtx, u64(ui.id_mix(id, 5)), loc)
	defer ui.close(&st)
	r := input(gtx, s, placeholder, appearance, size, after = .Chevron_Down, width = width, name = name != "" ? name : placeholder, state = state, key = u64(ui.id_mix(id, 1)))
	if state == .Live {
		if r.focused && !d.was_focused {
			open^ = true
		}
		if r.submitted {
			if freeform {
				changed, err = submit_time_text(s, d, selected, valid, hour12, seconds, required, start_hour, end_hour)
				open^ = false
			} else {
				open^ = !open^
			}
		}
		if !r.focused && d.was_focused && freeform && !open^ {
			changed, err = submit_time_text(s, d, selected, valid, hour12, seconds, required, start_hour, end_hour)
		}
		d.was_focused = r.focused
	}
	if !open^ || state == .Disabled {
		d.was_open = false
		return
	}
	d.was_open = true
	heights := CONTROL_HEIGHT
	input_h := heights[size] // the input's height, as input lays it out
	scrim_id := ui.id_mix(id, 0xffff)
	for e in ui.events(gtx, scrim_id) {
		if e.kind == .Press {
			open^ = false
		}
	}
	max_h := TIME_LIST_MAX_H
	if window_h > 0 {
		max_h = min(max_h, window_h * 0.8)
	}
	ov := ui.popup_open(gtx, {0, 0, 0, input_h}, id, .Below, .Start, DATE_POPUP_GAP, {max = {ui.INF, max_h}})
	ops.input_area(gtx.scene, scrim_id, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	mp := new(Menu_Paint, gtx.allocator)
	mp^ = {id = id, alpha = 1}
	box := ui.box_open(gtx, {padding = ui.pad_all(tok.SPACING_HORIZONTAL_XS + tok.STROKE_WIDTH_THIN), paint = paint_menu, user = mp}, key = u64(ui.id_mix(id, 2)))
	sb := ui.scroll_box_open(gtx, key = u64(ui.id_mix(id, 3)), min_width = max(160, (width > 0 ? width : 200) - 2 * (tok.SPACING_HORIZONTAL_XS + tok.STROKE_WIDTH_THIN)))
	col := ui.column_open(gtx, gap = tok.SPACING_HORIZONTAL_XXS, align = .Fill, key = u64(ui.id_mix(id, 4)))
	ui.container_semantics(gtx, {role = .List_Box})
	opts := time_options(start_hour, end_hour, increment, gtx.allocator)
	for t, i in opts {
		label := format_time(t, hour12, seconds, gtx.allocator)
		if time_option(gtx, label, valid^ && t == selected^, state, u64(ui.id_mix(id, u64(10 + i)))) {
			selected^ = t
			valid^ = true
			changed = true
			ui.text_set(s, label)
			remember_submitted(d, label)
			open^ = false
		}
	}
	ui.close(&col)
	ui.close(&sb)
	ui.close(&box)
	if !open^ {
		ov.discard = true
	}
	ui.popup_close(&ov, mp.size)
	return
}

// submit_time_text parses the input's text into selected when it is not
// what was submitted last (time-picker.json behaviour freeform-submit).
@(private = "file")
submit_time_text :: proc(s: ^ui.Text_State, d: ^Time_Picker_Data, selected: ^Time, valid: ^bool, hour12, seconds, required: bool, start_hour, end_hour: int) -> (changed: bool, err: Time_Error) {
	text := strings.trim_space(ui.text_string(s))
	if text == submitted_text(d) {
		return
	}
	remember_submitted(d, text)
	if text == "" {
		valid^ = false
		return true, required ? .Required_Input : .None
	}
	t, ok := parse_time(text, hour12, seconds)
	if !ok {
		return true, .Invalid_Input
	}
	// Out of bounds: before the start hour on a range that does not wrap,
	// or past the end (timeMath.ts getDateFromTimeString's anchors).
	mins := t.hour * 60 + t.minute
	start := start_hour * 60
	end := end_hour * 60
	wraps := start_hour > end_hour || end_hour == 24
	if !wraps && (mins < start || mins >= end) {
		return true, .Out_Of_Bounds
	}
	if wraps && mins < start && mins >= (end_hour == 24 ? 0 : end_hour) * 60 {
		return true, .Out_Of_Bounds
	}
	selected^ = t
	valid^ = true
	return true, .None
}

// time_option is one row of the list: a combobox option (combobox.json
// option-box): base300 text padded SNudge vertically and S horizontally,
// Neutral_Background1 hover and pressed roles, the check icon while
// selected.
@(private = "file")
time_option :: proc(gtx: ^ui.Ctx, label: string, selected: bool, state: Interaction, key: u64) -> bool {
	p := ui.widget_open(gtx, key)
	t := shape_style(gtx, label, control_style(.Medium, tok.FONT_WEIGHT_REGULAR))
	h := t.height + 2 * tok.SPACING_VERTICAL_SNUDGE
	sz := ui.constrain_min(gtx.constraints, {t.width + 2 * tok.SPACING_HORIZONTAL_S + 16 + tok.SPACING_HORIZONTAL_XS, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	bg := color_for(State_Roles{.Transparent_Background, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Transparent_Background}, c)
	fg := color_for(State_Roles{.Neutral_Foreground1, .Neutral_Foreground1_Hover, .Neutral_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	if ui.painted(bg) {
		ops.fill(gtx.scene, ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}, bg)
	}
	x := tok.SPACING_HORIZONTAL_S
	if selected {
		icon(gtx, .Checkmark, {x - tok.SPACING_HORIZONTAL_XXS, (sz.y - 16) / 2}, 16, fg)
	}
	x += 16 + tok.SPACING_HORIZONTAL_XS
	draw_text(gtx, t, {x, (sz.y - t.height) / 2}, fg)
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	ui.semantics(gtx, &p, {role = .Option, label = label, states = design.state_if(selected, {.Selected}) + design.state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked
}
