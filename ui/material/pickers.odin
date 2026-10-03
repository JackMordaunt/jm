package material

import "core:fmt"
import "jm:ui/ops"
import "core:math"
import "core:strconv"
import "jm:timefmt"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/material/tokens"

// Date and time pickers (m3e-kit components/date-picker.json:
// comp.date-picker-modal, comp.date-input-modal; time-picker.json:
// comp.time-picker, comp.time-input) and the carousel (carousel.json, which
// has no tokens: its keyline strategies are the spec's).

// Date and its arithmetic are jm:ui/design's (design/calendar.odin).
Date :: design.Date
days_in_month :: design.days_in_month
weekday :: design.weekday
date_less :: design.date_less

// Date_Mode is the date picker's display mode (date-picker.json inputs.displayMode).
Date_Mode :: enum u8 {
	Picker, // the calendar grid
	Input, // one numeric text field
}

// Values date-picker.json gives without tokens, cited where they are used.
DATE_NAV_HEIGHT :: f32(56) // layout monthYearHeight, DatePicker.kt:2619
DATE_GRID_PADDING :: f32(12) // layout horizontalPadding, DatePicker.kt:2621
DATE_CELL :: f32(48) // layout touchTarget, DatePicker.kt:2617
DATE_ROWS :: 6 // layout maxCalendarRows, DatePicker.kt:2631
DATE_YEAR_COLUMNS :: 3 // layout yearsInRow, DatePicker.kt:2632
DATE_YEAR_GUTTER :: f32(16) // layout yearsVerticalPadding, DatePicker.kt:2628
DATE_ENTER_OFFSET :: f32(-48) // behaviour enterOffset, DatePicker.kt:1487-1533
// DATE_ACTIONS_HEIGHT is the dialog's Cancel/OK row. The kit leaves it to
// the dialog spec; 56 is what the 568dp container-height leaves under the
// header, month bar, weekdays and six rows.
DATE_ACTIONS_HEIGHT :: f32(56)
// DATE_INPUT_BODY is the input mode's field (10dp above it, DateInput's
// padding), its 56dp box and a line of supporting text.
DATE_INPUT_BODY :: f32(10 + 56 + 4 + 16 + 12)

// date_picker is M3's modal date picker (comp.date-picker-modal), without
// the dialog around it: a 360dp surface-container-high card with 28dp
// corners, a header (supporting text over a headline of the selection,
// and a mode toggle at its bottom end), a divider, a month bar (a year
// menu button, previous and next), the weekday initials and a fixed 6x7
// grid of 48dp cells whose 40dp day circles are filled primary when
// selected and ringed primary for today. view is the month on show (the
// caller's, so it survives frames); today marks the current date. Returns
// true when selected^ (or range_end^) changed.
//
// range_end, when given, makes it a range picker: a click starts a range
// at selected^, the next ends it (range_end^; before the start it starts
// again), and the days between sit on a secondary-container band.
// selectable, when given, disables the dates it rejects. The year menu
// swaps the grid for a scrollable 3-column grid of min_year..max_year.
// input, when given, adds the mode toggle: input mode (comp.date-input-
// modal) is one outlined numeric field, typed as digits with the slashes
// put in (MM/DD/YYYY), validated once complete (behaviour, DateInput.kt:
// 302-345). mode is the caller's mode, or kept internally when nil. The
// mode switch slides and fades the entering content in from -48dp and
// resizes the card on a default-spatial spring. actions, when given, are
// text buttons along the bottom end; action^ is set to the one clicked.
//
// state, when given, is the caller's Date_Picker_State: the mode (when
// mode is nil) and whether the year menu is open and how far it has
// scrolled. Pass it to keep or restore the picker's view across its
// dialog closing and reopening; it is kept internally otherwise.
//
// Departures: no arrow-key focus movement between days (jm:ui has no
// focus traversal); months change without the paging slide; the card
// keeps the picker's 360dp width and colour in input mode, so
// date-input-modal container-width and -color are unused, and both
// container-height tokens act as maxima.
date_picker :: proc(
	gtx: ^ui.Ctx,
	selected: ^Date,
	view: ^Date,
	today: Date,
	range_end: ^Date = nil,
	mode: ^Date_Mode = nil,
	input: ^ui.Text_State = nil,
	selectable: proc(d: Date) -> bool = nil,
	min_year := 1900,
	max_year := 2100,
	actions: []string = nil,
	action: ^int = nil,
	state: ^Date_Picker_State = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	stack: ui.Stack
	if len(actions) > 0 {
		stack = ui.stack_open(gtx, key ~ 0x57ac, loc)
	}
	p := ui.widget_open(gtx, key, loc)
	W :: tok.DATE_PICKER_MODAL_CONTAINER_WIDTH
	if view.month < 1 || view.month > 12 {
		base := selected^ != {} ? selected^ : today
		view^ = {base.year, base.month, 1}
	}
	ds := state if state != nil else ui.widget_data(gtx, p.id, Date_Picker_State)
	m := mode != nil ? mode^ : ds.mode
	if input == nil {
		m = .Picker
	}
	year_open, year_scroll := ds.year_open, ds.year_scroll
	ranged := range_end != nil
	changed := false

	header_h := ranged ? tok.DATE_PICKER_MODAL_RANGE_SELECTION_HEADER_CONTAINER_HEIGHT : tok.DATE_PICKER_MODAL_HEADER_CONTAINER_HEIGHT
	actions_h := len(actions) > 0 ? DATE_ACTIONS_HEIGHT : 8
	target_h := header_h + 1 + actions_h
	if m == .Picker {
		target_h = min(target_h + DATE_NAV_HEIGHT + DATE_CELL + DATE_ROWS * DATE_CELL, tok.DATE_PICKER_MODAL_CONTAINER_HEIGHT)
	} else {
		target_h = min(target_h + DATE_INPUT_BODY, tok.DATE_INPUT_MODAL_CONTAINER_HEIGHT)
	}
	c := Control{st = ui.widget_state(gtx, p.id)}
	h := animate(gtx, c, 0, target_h, .Default_Spatial, 0.1)
	mf := clamp(animate(gtx, c, 1, m == .Input ? 1 : 0, .Default_Effects), 0, 1)
	size := ui.constrain(gtx.constraints, {W, h})
	area := ops.Rect{0, 0, size.x, size.y}
	k := corners(tok.DATE_PICKER_MODAL_CONTAINER_SHAPE, area)
	card := rounded(gtx, area, k)
	paint_elevation(gtx, {area, k.tl}, elevation_level(tok.DATE_PICKER_MODAL_CONTAINER_ELEVATION))
	ops.fill(gtx.scene, card, color(tok.DATE_PICKER_MODAL_CONTAINER_COLOR))
	ops.clip_push(gtx.scene, card) // the resize is a clipped size transform

	// Header: supporting text, headline, mode toggle (layout header padding,
	// DatePicker.kt:2623-2626).
	sup := ranged ? "Select dates" : "Select date"
	draw_style_text(gtx, sup, {24, 16}, tok.DATE_PICKER_MODAL_HEADER_SUPPORTING_TEXT_FONT, color(tok.DATE_PICKER_MODAL_HEADER_SUPPORTING_TEXT_COLOR))
	headline: string
	if ranged {
		headline = fmt.tprintf("%s – %s", date_short(selected^, "Start date"), date_short(range_end^, "End date"))
	} else if selected^ != {} {
		headline = fmt.tprintf("%s, %s", timefmt.DAYS[weekday(selected^)][:3], date_short(selected^, ""))
	} else {
		headline = m == .Input ? "Entered date" : "Selected date"
	}
	ui.semantics(gtx, &p, {role = .Group, label = ui.frame_string(gtx, headline), description = sup})
	hfont := tok.DATE_PICKER_MODAL_HEADER_HEADLINE_FONT
	if ranged {
		hfont = tok.DATE_PICKER_MODAL_RANGE_SELECTION_HEADER_HEADLINE_FONT
	} else if m == .Input {
		hfont = tok.DATE_INPUT_MODAL_HEADER_HEADLINE_FONT
	}
	draw_style_text(gtx, headline, {24, header_h - 12 - hfont.line_height}, hfont, color(tok.DATE_PICKER_MODAL_HEADER_HEADLINE_COLOR))
	if input != nil {
		g := m == .Picker ? Icon.Edit : Icon.Calendar_Today
		ui.part_semantics(gtx, &p, ui.id_mix(p.id, 2), {size.x - 12 - 48, header_h - 12 - 48, 48, 48}, {role = .Button, label = "date mode"})
		if picker_icon_button(gtx, ui.id_mix(p.id, 2), {size.x - 12 - 48, header_h - 12 - 48}, g, "date mode") {
			m = m == .Picker ? .Input : .Picker
			if m == .Input && selected^ != {} {
				ui.text_set(input, fmt.tprintf("%02d%02d%04d", selected.month, selected.day, selected.year))
			}
		}
	}
	ops.fill(gtx.scene, ops.Rect{0, header_h, size.x, 1}, color(.Outline_Variant))
	y0 := header_h + 1

	// The picker's body fades out, and slides in from DATE_ENTER_OFFSET, as
	// mf moves; the input body the other way round.
	if mf < 0.99 {
		ops.transform_push(gtx.scene, ops.translate(0, DATE_ENTER_OFFSET * mf))
		live := m == .Picker
		// Month bar: the year menu button, then previous and next.
		label := ui.frame_string(gtx, fmt.tprintf("%s %d", timefmt.MONTHS[view.month - 1], view.year))
		lt := shape_text(gtx, label, .Label_Large)
		yb := ops.Rect{DATE_GRID_PADDING, y0 + 4, 12 + lt.width + 4 + 18 + 12, 48}
		yid := ui.id_mix(p.id, 3)
		yc := control(gtx, yid, yb, live ? .Live : .Enabled)
		if yc.clicked {
			year_open = !year_open
			// Open a few years before the selection (layout year-grid).
			row := f32((view.year - min_year) / DATE_YEAR_COLUMNS)
			year_scroll = max(row - 2, 0) * (tok.DATE_PICKER_MODAL_SELECTION_YEAR_CONTAINER_HEIGHT + DATE_YEAR_GUTTER)
		}
		fg := fade(color(.On_Surface_Variant), 1 - mf)
		yr := ops.Rect{yb.x, yb.y + 4, yb.w, 40}
		paint_state_layer(gtx, yc, ops.Round_Rect{yr, 20}, color(.On_Surface_Variant))
		draw_text(gtx, lt, {yb.x + 12, yb.y + (48 - lt.height) / 2}, fg)
		// The chevron flips 180 degrees while the year grid is open.
		icon(gtx, year_open ? .Arrow_Drop_Up : .Arrow_Drop_Down, {yb.x + 12 + lt.width + 4, yb.y + 15}, 18, fg)
		paint_focus_ring(gtx, yc, {yr, 20})
		if live {
			listen(gtx, yc, yid, yb)
			ops.tag(gtx.scene, yid, "year menu")
		}
		ui.part_semantics(gtx, &p, yid, yb, {role = .Button, label = label, states = {.Expandable} + (year_open ? {.Expanded} : {})})
		if !year_open {
			prev_r := ops.Rect{size.x - DATE_GRID_PADDING - 96, y0 + 4, 48, 48}
			if picker_icon_button(gtx, ui.id_mix(p.id, 4), {prev_r.x, prev_r.y}, .Chevron_Left, live ? "previous month" : "") {
				view.month -= 1
				if view.month < 1 {
					view.month, view.year = 12, view.year - 1
				}
			}
			ui.part_semantics(gtx, &p, ui.id_mix(p.id, 4), prev_r, {role = .Button, label = "previous month"})
			next_r := ops.Rect{size.x - DATE_GRID_PADDING - 48, y0 + 4, 48, 48}
			if picker_icon_button(gtx, ui.id_mix(p.id, 5), {next_r.x, next_r.y}, .Chevron_Right, live ? "next month" : "") {
				view.month += 1
				if view.month > 12 {
					view.month, view.year = 1, view.year + 1
				}
			}
			ui.part_semantics(gtx, &p, ui.id_mix(p.id, 5), next_r, {role = .Button, label = "next month"})
		}
		gy := y0 + DATE_NAV_HEIGHT
		if year_open {
			year_scroll = year_grid(gtx, p.id, view, today, {0, gy, size.x, DATE_CELL + DATE_ROWS * DATE_CELL}, year_scroll, min_year, max_year, live, 1 - mf, &year_open, &p)
		} else {
			changed = day_grid(gtx, p.id, selected, range_end, view^, today, selectable, min_year, max_year, gy, live, 1 - mf, label, &p)
		}
		ops.transform_pop(gtx.scene)
	}
	if mf > 0.01 && input != nil {
		ops.transform_push(gtx.scene, ops.translate(0, DATE_ENTER_OFFSET * (1 - mf)))
		changed |= date_field(gtx, ui.id_mix(p.id, 6), input, selected, view, selectable, min_year, max_year, {24, y0 + 10, size.x - 48, 56}, m == .Input, mf, &p)
		ops.transform_pop(gtx.scene)
	}
	ops.clip_pop(gtx.scene)

	ds.year_open, ds.year_scroll = year_open, year_scroll
	if mode != nil {
		mode^ = m
	} else {
		ds.mode = m
	}
	ui.widget_close(gtx, &p, {size = size})

	if len(actions) > 0 {
		// Text buttons at the bottom end, in the stack over the card.
		aw: f32
		for a, i in actions {
			aw += shape_text(gtx, a, .Label_Large).width + 24 + (i > 0 ? 8 : 0)
		}
		pad := ui.inset_open(gtx, {max(size.x - 12 - aw, 0), size.y - DATE_ACTIONS_HEIGHT + 8, 0, 0})
		r := ui.row_open(gtx, gap = 8)
		for a, i in actions {
			if button(gtx, a, .Text, key = u64(i)) && action != nil {
				action^ = i
			}
		}
		ui.close(&r)
		ui.close(&pad)
		ui.close(&stack)
	}
	return changed
}

// Date_Picker_State is what a date picker keeps between frames: see
// date_picker's state parameter. The zero value shows the calendar grid
// with the year menu shut.
Date_Picker_State :: struct {
	mode:        Date_Mode, // when the caller keeps no mode
	year_open:   bool, // the year menu is showing in place of the day grid
	year_scroll: f32, // the year menu's scroll offset, in dp
}

// date_short is d as "Sep 28", or none for the zero date.
@(private)
date_short :: proc(d: Date, none: string) -> string {
	if d == {} || d.month < 1 || d.month > 12 {
		return none
	}
	return fmt.tprintf("%s %d", timefmt.MONTHS[d.month - 1][:3], d.day)
}

// day_grid is the weekday row and the 6x7 month grid of view, from y. alpha
// fades it for the mode switch. Returns true when a click changed the
// selection.
@(private)
day_grid :: proc(
	gtx: ^ui.Ctx,
	pid: ops.Area_Id,
	selected, range_end: ^Date,
	view, today: Date,
	selectable: proc(d: Date) -> bool,
	min_year, max_year: int,
	y: f32,
	live: bool,
	alpha: f32,
	month: string, // the month and year as the headline shows it, for the frame
	p: ^ui.Placement, // the picker, which the grid is a part of
) -> bool {
	x0 := DATE_GRID_PADDING
	for d, i in timefmt.DAYS {
		t := shape_style(gtx, d[:1], tok.DATE_PICKER_MODAL_WEEKDAYS_LABEL_TEXT_FONT)
		draw_text(gtx, t, {x0 + f32(i) * DATE_CELL + (DATE_CELL - t.width) / 2, y + (DATE_CELL - t.height) / 2}, fade(color(tok.DATE_PICKER_MODAL_WEEKDAYS_LABEL_TEXT_COLOR), alpha))
	}
	gy := y + DATE_CELL
	first := weekday({view.year, view.month, 1})
	n := days_in_month(view.year, view.month)
	// The month is a grid of the picker, each day a cell of it; the
	// weekday headers above it are not declared.
	grid := ui.id_mix(pid, 9)
	ui.part_semantics(gtx, p, grid, {x0, gy, 7 * DATE_CELL, f32((first + n + 6) / 7) * DATE_CELL}, {role = .Grid, label = month})
	changed := false
	ranged := range_end != nil
	for day in 1 ..= n {
		cell := first + day - 1
		r := ops.Rect{x0 + f32(cell % 7) * DATE_CELL, gy + f32(cell / 7) * DATE_CELL, DATE_CELL, DATE_CELL}
		this := Date{view.year, view.month, day}
		disabled := this.year < min_year || this.year > max_year || (selectable != nil && !selectable(this))
		band := Day_Band.None
		start, end := selected^, ranged ? range_end^ : Date{}
		on := this == start || (ranged && this == end)
		if ranged && start != {} && end != {} && !date_less(this, start) && !date_less(end, this) && start != end {
			switch {
			case this == start:
				band = .Start
			case this == end:
				band = .End
			case:
				band = .Middle
			}
		}
		id := ui.id_mix(pid, u64(100 + day))
		st := live ? (disabled ? Interaction.Disabled : .Live) : (disabled ? .Disabled : .Enabled)
		c := control(gtx, id, r, st)
		if c.clicked {
			switch {
			case !ranged:
				if selected^ != this {
					selected^ = this
					changed = true
				}
			case start == {} || end != {} || date_less(this, start):
				selected^, range_end^ = this, {}
				changed = true
			case:
				range_end^ = this
				changed = true
			}
			on = this == selected^ || (ranged && this == range_end^)
		}
		paint_day(gtx, c, r, day, on, today == this, band, alpha)
		name := fmt.aprintf("%04d-%02d-%02d", this.year, this.month, this.day, allocator = gtx.allocator)
		if live && !disabled {
			listen(gtx, c, id, r)
			ops.tag(gtx.scene, id, name)
		}
		ui.child_semantics(gtx, grid, id, r, {role = .Grid_Cell, label = name, states = states_of(c, on)})
	}
	return changed
}

// Day_Band is where a day sits in a selected range's band.
@(private)
Day_Band :: enum u8 {
	None,
	Start,
	Middle,
	End,
}

// paint_day paints one day cell r (48dp): the range band, the 40dp day
// circle (selected: filled, fading in on a default-effects spring as it
// becomes selected; today: a 1dp outline), the state layer and the label.
@(private)
paint_day :: proc(gtx: ^ui.Ctx, c: Control, r: ops.Rect, day: int, selected, today: bool, band: Day_Band, alpha: f32) {
	DW, DH :: tok.DATE_PICKER_MODAL_DATE_CONTAINER_WIDTH, tok.DATE_PICKER_MODAL_DATE_CONTAINER_HEIGHT
	cx, cy := r.x + r.w / 2, r.y + r.h / 2
	dot := ops.Rect{cx - DW / 2, cy - DH / 2, DW, DH}
	dk := corners(tok.DATE_PICKER_MODAL_DATE_CONTAINER_SHAPE, dot)
	bh := tok.DATE_PICKER_MODAL_RANGE_SELECTION_ACTIVE_INDICATOR_CONTAINER_HEIGHT
	band_c := fade(color(tok.DATE_PICKER_MODAL_RANGE_SELECTION_ACTIVE_INDICATOR_CONTAINER_COLOR), alpha)
	switch band {
	case .None:
	case .Start:
		ops.fill(gtx.scene, ops.Rect{cx, cy - bh / 2, r.w / 2, bh}, band_c)
	case .Middle:
		ops.fill(gtx.scene, ops.Rect{r.x, cy - bh / 2, r.w, bh}, band_c)
	case .End:
		ops.fill(gtx.scene, ops.Rect{r.x, cy - bh / 2, r.w / 2, bh}, band_c)
	}
	sel := selected ? f32(1) : 0
	if c.st != nil {
		sel = clamp(animate(gtx, c, 0, sel, .Default_Effects), 0, 1)
	}
	label := color(tok.DATE_PICKER_MODAL_DATE_UNSELECTED_LABEL_TEXT_COLOR)
	if band == .Middle {
		label = color(tok.DATE_PICKER_MODAL_SELECTION_DATE_IN_RANGE_LABEL_TEXT_COLOR)
	}
	if today && !selected {
		// Today's outline is dropped once the day is also selected.
		stroke_inside(gtx, {dot, dk.tl}, fade(color(tok.DATE_PICKER_MODAL_DATE_TODAY_CONTAINER_OUTLINE_COLOR), alpha), tok.DATE_PICKER_MODAL_DATE_TODAY_CONTAINER_OUTLINE_WIDTH)
		label = color(tok.DATE_PICKER_MODAL_DATE_TODAY_LABEL_TEXT_COLOR)
	}
	if sel > 0 {
		// Disabled, the selected fill keeps its colour at the disabled content opacity.
		a := sel * alpha * (c.disabled ? DISABLED_CONTENT_OPACITY : 1)
		ops.fill(gtx.scene, rounded(gtx, dot, dk), fade(color(tok.DATE_PICKER_MODAL_DATE_SELECTED_CONTAINER_COLOR), a))
	}
	if selected {
		label = color(tok.DATE_PICKER_MODAL_DATE_SELECTED_LABEL_TEXT_COLOR)
	}
	if c.disabled {
		label = disabled_content()
	}
	layer := ops.Rect{cx - tok.DATE_PICKER_MODAL_DATE_STATE_LAYER_WIDTH / 2, cy - tok.DATE_PICKER_MODAL_DATE_STATE_LAYER_HEIGHT / 2, tok.DATE_PICKER_MODAL_DATE_STATE_LAYER_WIDTH, tok.DATE_PICKER_MODAL_DATE_STATE_LAYER_HEIGHT}
	lk := corners(tok.DATE_PICKER_MODAL_DATE_STATE_LAYER_SHAPE, layer)
	paint_state_layer(gtx, c, rounded(gtx, layer, lk), selected ? color(tok.DATE_PICKER_MODAL_DATE_SELECTED_LABEL_TEXT_COLOR) : color(.On_Surface_Variant))
	t := shape_style(gtx, fmt.tprintf("%d", day), tok.DATE_PICKER_MODAL_DATE_LABEL_TEXT_FONT)
	draw_text(gtx, t, {cx - t.width / 2, cy - t.height / 2}, fade(label, alpha))
	paint_focus_ring_corners(gtx, c, dot, dk, inward = true)
}

// date_cell is one date-picker day cell as a widget, for showing its
// states on their own: 48dp, a 40dp circle, filled when selected, ringed
// when today, on the range band when in_range. Returns true when clicked.
date_cell :: proc(
	gtx: ^ui.Ctx,
	day: int,
	selected := false,
	today := false,
	in_range := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	r := ops.Rect{0, 0, DATE_CELL, DATE_CELL}
	c := control(gtx, p.id, r, state)
	paint_day(gtx, c, r, day, selected, today, in_range ? .Middle : .None, 1)
	listen(gtx, c, p.id, r)
	ui.semantics(gtx, &p, {role = .Button, label = fmt.aprintf("%d", day, allocator = gtx.allocator), states = states_of(c, selected)})
	ui.widget_close(gtx, &p, {size = {DATE_CELL, DATE_CELL}})
	return c.clicked
}

// year_grid is the date picker's year menu in r: 3 columns of 72x36 year
// chips, 16dp apart vertically, scrolled by scroll. A click shows that
// year and closes the menu. Returns the new scroll.
@(private)
year_grid :: proc(
	gtx: ^ui.Ctx,
	pid: ops.Area_Id,
	view: ^Date,
	today: Date,
	r: ops.Rect,
	scroll: f32,
	min_year, max_year: int,
	live: bool,
	alpha: f32,
	open: ^bool,
	p: ^ui.Placement, // the picker, which the years are parts of
) -> f32 {
	YW, YH :: tok.DATE_PICKER_MODAL_SELECTION_YEAR_CONTAINER_WIDTH, tok.DATE_PICKER_MODAL_SELECTION_YEAR_CONTAINER_HEIGHT
	pitch := YH + DATE_YEAR_GUTTER
	col_w := (r.w - 2 * DATE_GRID_PADDING) / DATE_YEAR_COLUMNS
	n := max(max_year - min_year + 1, 0)
	rows := (n + DATE_YEAR_COLUMNS - 1) / DATE_YEAR_COLUMNS
	sid := ui.id_mix(pid, 7)
	sc := scroll
	if live {
		for e in ui.events(gtx, sid) {
			if e.kind == .Scroll {
				sc += e.scroll.y
			}
		}
	}
	content := f32(rows) * pitch + DATE_YEAR_GUTTER
	sc = clamp(sc, 0, max(content - r.h, 0))
	bar_id := ui.id_mix(pid, 8)
	if live {
		sc = ui.scroll_bar_handle(gtx, bar_id, .Vertical, {r.w, r.h}, content, sc)
		ops.input_area(gtx.scene, sid, r, {.Scroll})
	}
	ops.clip_push(gtx.scene, r)
	first := int(sc / pitch)
	last := min(rows, first + int(r.h / pitch) + 2)
	for row in first ..< last {
		for col in 0 ..< DATE_YEAR_COLUMNS {
			y := min_year + row * DATE_YEAR_COLUMNS + col
			if y > max_year {
				break
			}
			cx := r.x + DATE_GRID_PADDING + f32(col) * col_w + col_w / 2
			cy := r.y + DATE_YEAR_GUTTER / 2 + f32(row) * pitch - sc + YH / 2
			chip := ops.Rect{cx - YW / 2, cy - YH / 2, YW, YH}
			k := corners(tok.DATE_PICKER_MODAL_SELECTION_YEAR_STATE_LAYER_SHAPE, chip)
			id := ui.id_mix(pid, u64(1000 + y))
			c := control(gtx, id, chip, live ? .Live : .Enabled)
			if c.clicked {
				view.year = y
				open^ = false
			}
			on := y == view.year
			label := color(tok.DATE_PICKER_MODAL_SELECTION_YEAR_UNSELECTED_LABEL_TEXT_COLOR)
			if on {
				ops.fill(gtx.scene, rounded(gtx, chip, k), fade(color(tok.DATE_PICKER_MODAL_SELECTION_YEAR_SELECTED_CONTAINER_COLOR), alpha))
				label = color(tok.DATE_PICKER_MODAL_SELECTION_YEAR_SELECTED_LABEL_TEXT_COLOR)
			} else if y == today.year {
				// The current year is ringed as today is in the grid.
				stroke_inside(gtx, {chip, k.tl}, color(tok.DATE_PICKER_MODAL_DATE_TODAY_CONTAINER_OUTLINE_COLOR), tok.DATE_PICKER_MODAL_DATE_TODAY_CONTAINER_OUTLINE_WIDTH)
				label = color(tok.DATE_PICKER_MODAL_DATE_TODAY_LABEL_TEXT_COLOR)
			}
			paint_state_layer(gtx, c, rounded(gtx, chip, k), label)
			t := shape_style(gtx, fmt.tprintf("%d", y), tok.DATE_PICKER_MODAL_SELECTION_YEAR_LABEL_TEXT_FONT)
			draw_text(gtx, t, {cx - t.width / 2, cy - t.height / 2}, fade(label, alpha))
			paint_focus_ring_corners(gtx, c, chip, k, inward = true)
			name := fmt.aprintf("year %d", y, allocator = gtx.allocator)
			if live {
				listen(gtx, c, id, chip)
				ops.tag(gtx.scene, id, name)
			}
			ui.part_semantics(gtx, p, id, chip, {role = .Button, label = name, states = states_of(c, on)})
		}
	}
	if live {
		ops.transform_push(gtx.scene, ops.translate(r.x, r.y))
		ui.scroll_bar_paint(gtx, bar_id, .Vertical, {r.w, r.h}, content, sc)
		ops.transform_pop(gtx.scene)
	}
	ops.clip_pop(gtx.scene)
	return sc
}

// date_field is the date picker's input mode in r: an outlined field
// (the outlined text field's tokens) taking digits only, shown with
// slashes as MM/DD/YYYY, with the validation error below once all eight
// digits are in. A valid date becomes the selection. Returns true when it
// changed the selection.
@(private)
date_field :: proc(
	gtx: ^ui.Ctx,
	id: ops.Area_Id,
	s: ^ui.Text_State,
	selected, view: ^Date,
	selectable: proc(d: Date) -> bool,
	min_year, max_year: int,
	r: ops.Rect,
	live: bool,
	alpha: f32,
	p: ^ui.Placement, // the picker, which the field is a part of
) -> bool {
	st := ui.widget_state(gtx, id)
	edited := false
	if live {
		for e in ui.events(gtx, id) {
			#partial switch e.kind {
			case .Focus:
				st.focused = true
			case .Blur:
				st.focused = false
			case .Enter:
				st.hovered = true
			case .Leave:
				st.hovered = false
			case .Text:
				for ch in e.text {
					if ch >= '0' && ch <= '9' && len(s.buf) < 8 {
						append(&s.buf, u8(ch))
						edited = true
					}
				}
			case .Key:
				if e.key == .Backspace && len(s.buf) > 0 {
					pop(&s.buf)
					edited = true
				}
			}
		}
	}
	ui.text_move(s, len(s.buf))
	digits := string(s.buf[:])
	err := ""
	changed := false
	if len(digits) == 8 {
		// Only digits reach the buffer, so these parse.
		year, _ := strconv.parse_int(digits[4:8], 10)
		month, _ := strconv.parse_int(digits[0:2], 10)
		day, _ := strconv.parse_int(digits[2:4], 10)
		d := Date{year, month, day}
		switch {
		case d.month < 1 || d.month > 12 || d.day < 1 || d.day > days_in_month(d.year, d.month):
			err = "Date does not match expected pattern: MM/DD/YYYY"
		case d.year < min_year || d.year > max_year:
			err = fmt.tprintf("Date out of expected year range %d - %d", min_year, max_year)
		case selectable != nil && !selectable(d):
			err = "Date not allowed"
		case edited && selected^ != d:
			selected^ = d
			view^ = {d.year, d.month, 1}
			changed = true
		}
	}
	focused := st.focused
	// Shown with the slashes the pattern puts between month, day and year.
	shown: [10]u8
	n := 0
	for i in 0 ..< len(digits) {
		if i == 2 || i == 4 {
			shown[n] = '/'
			n += 1
		}
		shown[n] = digits[i]
		n += 1
	}
	outline := color(tok.OUTLINED_TEXT_FIELD_OUTLINE_COLOR)
	ow := tok.OUTLINED_TEXT_FIELD_OUTLINE_WIDTH
	lab := color(tok.OUTLINED_TEXT_FIELD_LABEL_COLOR)
	switch {
	case err != "":
		outline, lab = color(tok.OUTLINED_TEXT_FIELD_ERROR_OUTLINE_COLOR), color(tok.OUTLINED_TEXT_FIELD_ERROR_LABEL_COLOR)
		if focused {
			ow = tok.OUTLINED_TEXT_FIELD_FOCUS_OUTLINE_WIDTH
		}
	case focused:
		outline, ow, lab = color(tok.OUTLINED_TEXT_FIELD_FOCUS_OUTLINE_COLOR), tok.OUTLINED_TEXT_FIELD_FOCUS_OUTLINE_WIDTH, color(tok.OUTLINED_TEXT_FIELD_FOCUS_LABEL_COLOR)
	case st.hovered:
		outline = color(tok.OUTLINED_TEXT_FIELD_HOVER_OUTLINE_COLOR)
	}
	k := corners(tok.OUTLINED_TEXT_FIELD_CONTAINER_SHAPE, r)
	// The label always sits floated in a notch cut from the outline.
	lt := shape_text(gtx, "Date", .Body_Small)
	stroke_inside(gtx, {r, k.tl}, fade(outline, alpha), ow)
	notch := ops.Rect{r.x + 12, r.y - 2, lt.width + 8, 4}
	ops.fill(gtx.scene, notch, color(tok.DATE_PICKER_MODAL_CONTAINER_COLOR))
	draw_text(gtx, lt, {r.x + 16, r.y - lt.height / 2}, fade(lab, alpha))
	body := tok.OUTLINED_TEXT_FIELD_CONTAINER_HEIGHT
	if n > 0 {
		t := shape_text(gtx, string(shown[:n]), .Body_Large)
		draw_text(gtx, t, {r.x + 16, r.y + (body - t.height) / 2}, fade(color(tok.OUTLINED_TEXT_FIELD_INPUT_COLOR), alpha))
		if focused {
			ops.fill(gtx.scene, ops.Rect{r.x + 16 + t.width + 1, r.y + 16, 2, 24}, color(tok.OUTLINED_TEXT_FIELD_CARET_COLOR))
		}
	} else {
		t := shape_text(gtx, "MM/DD/YYYY", .Body_Large)
		draw_text(gtx, t, {r.x + 16, r.y + (body - t.height) / 2}, fade(color(.On_Surface_Variant), alpha))
		if focused {
			ops.fill(gtx.scene, ops.Rect{r.x + 16, r.y + 16, 2, 24}, color(tok.OUTLINED_TEXT_FIELD_CARET_COLOR))
		}
	}
	if err != "" {
		et := shape_text(gtx, err, .Body_Small)
		draw_text(gtx, et, {r.x + 16, r.y + body + 4}, fade(color(tok.OUTLINED_TEXT_FIELD_ERROR_SUPPORTING_COLOR), alpha))
	}
	if live {
		ops.input_area(gtx.scene, id, r, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Text, .Focus, .Blur})
		ops.tag(gtx.scene, id, "date input")
	}
	ui.part_semantics(gtx, p, id, r, {role = .Text_Field, label = "Date", value = ui.frame_string(gtx, string(shown[:n])), description = err != "" ? ui.frame_string(gtx, err) : "MM/DD/YYYY"})
	return changed
}

// picker_icon_button is a standard icon button painted at pos inside a
// picker (48dp target, 40dp state layer, 24dp icon in on-surface-variant).
// name, when set, tags it. Returns true when clicked.
@(private)
picker_icon_button :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, pos: ops.Point, g: Icon, name: string) -> bool {
	area := ops.Rect{pos.x, pos.y, 48, 48}
	c := control(gtx, id, area, name != "" ? .Live : .Enabled)
	S :: tok.SMALL_ICON_BUTTON_CONTAINER_HEIGHT
	layer := ui.circle({pos.x + 24, pos.y + 24}, S / 2)
	col := color(tok.STANDARD_ICON_BUTTON_COLOR)
	paint_state_layer(gtx, c, layer, col)
	I :: tok.SMALL_ICON_BUTTON_ICON_SIZE
	icon(gtx, g, {pos.x + (48 - I) / 2, pos.y + (48 - I) / 2}, I, col)
	paint_focus_ring(gtx, c, {{pos.x + 4, pos.y + 4, S, S}, S / 2})
	if name != "" {
		listen(gtx, c, id, area)
		ops.tag(gtx.scene, id, name)
	}
	return c.clicked
}

// Time is a 24-hour clock time.
Time :: struct {
	hour, minute: int,
}

// Time_Mode is the time picker's mode (time-picker.json inputs.mode).
Time_Mode :: enum u8 {
	Dial,
	Input,
}

// Time_Layout arranges the time picker (time-picker.json inputs.layoutType).
Time_Layout :: enum u8 {
	Vertical, // portrait: selectors above the dial
	Horizontal, // landscape: selectors beside the dial
}

// Values time-picker.json gives without tokens, cited where they are used.
TIME_OUTER_RING :: f32(0.39453) // layout outerRingRatio, TimePicker.kt:4038-4041
TIME_INNER_RING :: f32(0.26953) // layout innerRingRatio
TIME_INNER_THRESHOLD :: f32(74) // layout innerOuterThreshold, TimePicker.kt:4051-4052
TIME_DIAL_GAP :: f32(36) // layout clockDisplayBottomMargin, TimePicker.kt:4042-4045
TIME_BOTTOM :: f32(24) // layout clockFaceBottomMargin
TIME_PADDING :: f32(24) // the dialog's inset, as the headline's
TIME_HEADLINE_GAP :: f32(20) // below the headline, TimePicker.kt's headline padding

// time_picker is M3's time picker (comp.time-picker, comp.time-input),
// without the dialog around it: a surface-container-high card with 28dp
// corners and a "Select time" headline. Dial mode: an hour and a minute
// chip (96x80, display digits; the active one primary-container), a colon,
// the AM/PM segmented toggle and a 256dp clock dial whose primary handle,
// track and centre dot point at the value, the label under the handle
// drawn on-primary. Pressing or dragging on the dial picks the active
// field: a drag tracks whole minutes, a tap snaps to the nearest five
// (behaviour, TimePicker.kt:1899-1930); picking an hour moves on to
// minutes. The handle turns on a default-spatial spring and the rings
// cross-fade on a default-effects one. is_24h drops the period toggle and
// adds an inner ring for 13-23 and 00, picked within TIME_INNER_THRESHOLD
// of the centre. Input mode swaps the dial for two numeric fields (type
// digits, Backspace, Up/Down) over "Hour" and "Minute". editing_minute is
// the caller's (which field is active). state forces the chips' and the
// period toggle's look and takes no input. Returns true when t^ changed.
//
// Departures: the hour-to-minute switch is immediate, not after the
// spec's ~100ms (behaviour autoAdvanceDelay, TimePicker.kt:1920,1922;
// jm:ui has no timers short of request_frame); keyboard focus does not
// walk the dial's numbers. The ring radius follows the ring ratio for
// both labels and handle; the spec's "minus half the handle" (layout,
// TimePicker.kt:1937-1954) would leave the handle off the number it
// selects, whose label the spec colours on-primary.
time_picker :: proc(
	gtx: ^ui.Ctx,
	t: ^Time,
	editing_minute: ^bool,
	is_24h := false,
	mode := Time_Mode.Dial,
	layout := Time_Layout.Vertical,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	old := t^
	live := state == .Live
	input := mode == .Input
	ui.semantics(gtx, &p, {role = .Group, label = input ? "Enter time" : "Select time"})
	CW := is_24h ? tok.TIME_PICKER_TIME_SELECTOR24_H_VERTICAL_CONTAINER_WIDTH : tok.TIME_PICKER_TIME_SELECTOR_CONTAINER_WIDTH
	CH := input ? tok.TIME_INPUT_TIME_FIELD_CONTAINER_HEIGHT : tok.TIME_PICKER_TIME_SELECTOR_CONTAINER_HEIGHT
	if input {
		CW = tok.TIME_INPUT_TIME_FIELD_CONTAINER_WIDTH
	}
	SEP :: f32(24)
	DIAL :: tok.TIME_PICKER_CLOCK_DIAL_CONTAINER_SIZE
	chips_w := 2 * CW + SEP
	period_w := is_24h ? 0 : 12 + tok.TIME_PICKER_PERIOD_SELECTOR_VERTICAL_CONTAINER_WIDTH
	horizontal := layout == .Horizontal && !input
	head := input ? tok.TIME_INPUT_HEADLINE_FONT : tok.TIME_PICKER_HEADLINE_FONT
	top := TIME_PADDING + head.line_height + TIME_HEADLINE_GAP
	w, h: f32
	switch {
	case input:
		w = TIME_PADDING + chips_w + period_w + TIME_PADDING
		h = top + CH + 4 + 16 + TIME_BOTTOM
	case horizontal:
		sel_h := CH + (is_24h ? 0 : 12 + tok.TIME_PICKER_PERIOD_SELECTOR_HORIZONTAL_CONTAINER_HEIGHT)
		w = TIME_PADDING + max(chips_w, is_24h ? 0 : tok.TIME_PICKER_PERIOD_SELECTOR_HORIZONTAL_CONTAINER_WIDTH) + 52 + DIAL + TIME_PADDING
		h = top + max(sel_h, DIAL) + TIME_BOTTOM
	case:
		w = TIME_PADDING + max(chips_w + period_w, DIAL) + TIME_PADDING
		h = top + CH + TIME_DIAL_GAP + DIAL + TIME_BOTTOM
	}
	size := ui.constrain(gtx.constraints, {w, h})
	area := ops.Rect{0, 0, size.x, size.y}
	shape_tok := input ? tok.TIME_INPUT_CONTAINER_SHAPE : tok.TIME_PICKER_CONTAINER_SHAPE
	k := corners(shape_tok, area)
	paint_elevation(gtx, {area, k.tl}, elevation_level(tok.TIME_PICKER_CONTAINER_ELEVATION))
	ops.fill(gtx.scene, rounded(gtx, area, k), color(input ? tok.TIME_INPUT_CONTAINER_COLOR : tok.TIME_PICKER_CONTAINER_COLOR))
	draw_style_text(gtx, input ? "Enter time" : "Select time", {TIME_PADDING, TIME_PADDING}, head, color(input ? tok.TIME_INPUT_HEADLINE_COLOR : tok.TIME_PICKER_HEADLINE_COLOR))

	// The time selector: hour and minute chips (or fields) and the colon.
	h12 := t.hour % 12 == 0 ? 12 : t.hour % 12
	x := TIME_PADDING
	for k in 0 ..< 2 {
		box := ops.Rect{x, top, CW, CH}
		id := ui.id_mix(p.id, u64(10 + k))
		minute := k == 1
		active := editing_minute^ == minute
		if input {
			if time_field(gtx, id, box, t, minute, is_24h, live, state, &p) {
				editing_minute^ = minute
			}
		} else {
			c := control(gtx, id, box, state)
			if c.clicked {
				editing_minute^ = minute
			}
			active = editing_minute^ == minute
			bk := corners(tok.TIME_PICKER_TIME_SELECTOR_CONTAINER_SHAPE, box)
			shape := rounded(gtx, box, bk)
			container := color(active ? tok.TIME_PICKER_TIME_SELECTOR_SELECTED_CONTAINER_COLOR : tok.TIME_PICKER_TIME_SELECTOR_UNSELECTED_CONTAINER_COLOR)
			label := color(active ? tok.TIME_PICKER_TIME_SELECTOR_SELECTED_LABEL_TEXT_COLOR : tok.TIME_PICKER_TIME_SELECTOR_UNSELECTED_LABEL_TEXT_COLOR)
			if c.disabled {
				container, label = disabled_container(), disabled_content()
			}
			ops.fill(gtx.scene, shape, container)
			paint_state_layer(gtx, c, shape, label)
			v := minute ? t.minute : (is_24h ? t.hour : h12)
			digits := shape_style(gtx, fmt.tprintf("%02d", v), tok.TIME_PICKER_TIME_SELECTOR_LABEL_TEXT_FONT)
			draw_text(gtx, digits, {box.x + (CW - digits.width) / 2, box.y + (CH - digits.height) / 2}, label)
			paint_focus_ring_corners(gtx, c, box, bk)
			if live {
				listen(gtx, c, id, box)
				ops.tag(gtx.scene, id, minute ? "minute" : "hour")
			}
			ui.part_semantics(gtx, &p, id, box, {role = .Button, label = minute ? "minute" : "hour", value = fmt.aprintf("%02d", v, allocator = gtx.allocator), states = states_of(c, active)})
		}
		x += CW
		if k == 0 {
			sep_font := input ? tok.TIME_INPUT_TIME_FIELD_SEPARATOR_FONT : tok.TIME_PICKER_TIME_SELECTOR_SEPARATOR_FONT
			colon := shape_style(gtx, ":", sep_font)
			draw_text(gtx, colon, {x + (SEP - colon.width) / 2, top + (CH - colon.height) / 2}, color(input ? tok.TIME_INPUT_TIME_FIELD_SEPARATOR_COLOR : tok.TIME_PICKER_TIME_SELECTOR_SEPARATOR_COLOR))
			x += SEP
		}
	}
	if input {
		for k in 0 ..< 2 {
			lt := shape_style(gtx, k == 0 ? "Hour" : "Minute", tok.TIME_INPUT_TIME_FIELD_SUPPORTING_TEXT_FONT)
			draw_text(gtx, lt, {TIME_PADDING + f32(k) * (CW + SEP), top + CH + 4}, color(tok.TIME_INPUT_TIME_FIELD_SUPPORTING_TEXT_COLOR))
		}
	}

	// The period toggle: one segmented control, beside the chips (below
	// them in the horizontal layout).
	if !is_24h {
		pr: ops.Rect
		if horizontal {
			pr = {TIME_PADDING, top + CH + 12, tok.TIME_PICKER_PERIOD_SELECTOR_HORIZONTAL_CONTAINER_WIDTH, tok.TIME_PICKER_PERIOD_SELECTOR_HORIZONTAL_CONTAINER_HEIGHT}
		} else if input {
			pr = {x + 12, top, tok.TIME_INPUT_PERIOD_SELECTOR_CONTAINER_WIDTH, tok.TIME_INPUT_PERIOD_SELECTOR_CONTAINER_HEIGHT}
		} else {
			pr = {x + 12, top, tok.TIME_PICKER_PERIOD_SELECTOR_VERTICAL_CONTAINER_WIDTH, tok.TIME_PICKER_PERIOD_SELECTOR_VERTICAL_CONTAINER_HEIGHT}
		}
		period_toggle(gtx, p.id, pr, t, horizontal, live, state, &p)
	}

	if !input {
		dc: ops.Point
		if horizontal {
			dc = {size.x - TIME_PADDING - DIAL / 2, top + DIAL / 2}
		} else {
			dc = {size.x / 2, top + CH + TIME_DIAL_GAP + DIAL / 2}
		}
		clock_dial(gtx, p.id, dc, t, editing_minute, is_24h, live)
	}
	ui.widget_close(gtx, &p, {size = size})
	return t^ != old
}

// period_toggle is the AM/PM segmented control in r: two halves split by
// a 1dp divider inside one outline (layout dividerWidth, TimePicker.kt:
// 2770-2911), the current half on tertiary-container. Clicking the other
// half moves the time 12 hours; clicking the current one does nothing.
@(private)
period_toggle :: proc(gtx: ^ui.Ctx, pid: ops.Area_Id, r: ops.Rect, t: ^Time, horizontal, live: bool, state: Interaction, p: ^ui.Placement) {
	k := corners(tok.TIME_PICKER_PERIOD_SELECTOR_CONTAINER_SHAPE, r)
	for half in 0 ..< 2 {
		hr: ops.Rect
		hk: Corners
		if horizontal {
			hr = {r.x + f32(half) * r.w / 2, r.y, r.w / 2, r.h}
			hk = half == 0 ? Corners{k.tl, 0, 0, k.bl} : Corners{0, k.tr, k.br, 0}
		} else {
			hr = {r.x, r.y + f32(half) * r.h / 2, r.w, r.h / 2}
			hk = half == 0 ? Corners{k.tl, k.tr, 0, 0} : Corners{0, 0, k.br, k.bl}
		}
		id := ui.id_mix(pid, u64(20 + half))
		c := control(gtx, id, hr, state)
		pm := t.hour >= 12
		if c.clicked && (half == 1) != pm {
			t.hour = (t.hour + 12) % 24
		}
		on := (half == 1) == (t.hour >= 12)
		shape := rounded(gtx, hr, hk)
		label := color(on ? tok.TIME_PICKER_PERIOD_SELECTOR_SELECTED_LABEL_TEXT_COLOR : tok.TIME_PICKER_PERIOD_SELECTOR_UNSELECTED_LABEL_TEXT_COLOR)
		if on {
			ops.fill(gtx.scene, shape, c.disabled ? disabled_container() : color(tok.TIME_PICKER_PERIOD_SELECTOR_SELECTED_CONTAINER_COLOR))
		}
		if c.disabled {
			label = disabled_content()
		}
		paint_state_layer(gtx, c, shape, label)
		lt := shape_style(gtx, half == 0 ? "AM" : "PM", tok.TIME_PICKER_PERIOD_SELECTOR_LABEL_TEXT_FONT)
		draw_text(gtx, lt, {hr.x + (hr.w - lt.width) / 2, hr.y + (hr.h - lt.height) / 2}, label)
		paint_focus_ring_corners(gtx, c, hr, hk)
		if live {
			listen(gtx, c, id, hr)
			ops.tag(gtx.scene, id, half == 0 ? "AM" : "PM")
		}
		ui.part_semantics(gtx, p, id, hr, {role = .Button, label = half == 0 ? "AM" : "PM", states = states_of(c, on)})
	}
	ow := tok.TIME_PICKER_PERIOD_SELECTOR_OUTLINE_WIDTH
	oc := color(tok.TIME_PICKER_PERIOD_SELECTOR_OUTLINE_COLOR)
	if state == .Disabled {
		oc = disabled_container()
	}
	stroke_inside(gtx, {r, k.tl}, oc, ow)
	if horizontal {
		ops.fill(gtx.scene, ops.Rect{r.x + r.w / 2 - ow / 2, r.y, ow, r.h}, oc)
	} else {
		ops.fill(gtx.scene, ops.Rect{r.x, r.y + r.h / 2 - ow / 2, r.w, ow}, oc)
	}
}

// time_field is one of the input mode's numeric fields in r: digits
// typed shift in from the right (clamped to the field's range),
// Backspace drops the last, Up/Down step with wrap-around. Focused it is
// primary-container with a 2dp primary outline. Returns true when it took
// focus this frame.
@(private)
time_field :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, r: ops.Rect, t: ^Time, minute, is_24h, live: bool, state: Interaction, p: ^ui.Placement) -> bool {
	focused_now := false
	hovered, focused: bool
	if live {
		st := ui.widget_state(gtx, id)
		for e in ui.events(gtx, id) {
			v := minute ? t.minute : t.hour
			hi := minute ? 59 : 23
			#partial switch e.kind {
			case .Enter:
				st.hovered = true
			case .Leave:
				st.hovered = false
			case .Focus:
				st.focused = true
				focused_now = true
			case .Blur:
				st.focused = false
			case .Text:
				for ch in e.text {
					if ch < '0' || ch > '9' {
						continue
					}
					shown := minute || is_24h ? v : (v % 12 == 0 ? 12 : v % 12)
					n := (shown * 10 + int(ch - '0')) % 100
					if n > (minute || is_24h ? hi : 12) {
						n = int(ch - '0')
					}
					if !minute && !is_24h {
						n = n % 12 + (t.hour >= 12 ? 12 : 0)
					}
					v = n
				}
			case .Key:
				#partial switch e.key {
				case .Backspace:
					v = minute || is_24h ? v / 10 : (v % 12) / 10 + (t.hour >= 12 ? 12 : 0)
				case .Up:
					v = (v + 1) % (hi + 1)
				case .Down:
					v = (v + hi) % (hi + 1)
				}
			}
			if minute {
				t.minute = v
			} else {
				t.hour = v
			}
		}
		hovered, focused = st.hovered, st.focused
	} else {
		hovered, focused = state == .Hovered, state == .Focused || state == .Pressed
	}
	k := corners(tok.TIME_INPUT_TIME_FIELD_CONTAINER_SHAPE, r)
	shape := rounded(gtx, r, k)
	container := color(focused ? tok.TIME_INPUT_TIME_FIELD_FOCUS_CONTAINER_COLOR : tok.TIME_INPUT_TIME_FIELD_CONTAINER_COLOR)
	label := color(focused ? tok.TIME_INPUT_TIME_FIELD_FOCUS_LABEL_TEXT_COLOR : (hovered ? tok.TIME_INPUT_TIME_FIELD_HOVER_LABEL_TEXT_COLOR : tok.TIME_INPUT_TIME_FIELD_LABEL_TEXT_COLOR))
	if state == .Disabled {
		container, label = disabled_container(), disabled_content()
	}
	ops.fill(gtx.scene, shape, container)
	if hovered && !focused {
		ops.fill(gtx.scene, shape, ops.with_alpha(label, HOVER_OPACITY))
	}
	if focused {
		ow := tok.TIME_INPUT_TIME_FIELD_FOCUS_OUTLINE_WIDTH
		stroke_inside(gtx, {r, k.tl}, color(tok.TIME_INPUT_TIME_FIELD_FOCUS_OUTLINE_COLOR), ow)
	}
	v := minute ? t.minute : (is_24h ? t.hour : (t.hour % 12 == 0 ? 12 : t.hour % 12))
	digits := shape_style(gtx, fmt.tprintf("%02d", v), tok.TIME_INPUT_TIME_FIELD_LABEL_TEXT_FONT)
	draw_text(gtx, digits, {r.x + (r.w - digits.width) / 2, r.y + (r.h - digits.height) / 2}, label)
	if live {
		ops.input_area(gtx.scene, id, shape, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Text, .Focus, .Blur})
		ops.tag(gtx.scene, id, minute ? "minute" : "hour")
	}
	ui.part_semantics(gtx, p, id, r, {role = .Text_Field, label = minute ? "Minute" : "Hour", value = ui.frame_string(gtx, fmt.tprintf("%02d", v)), states = state == .Disabled ? {.Disabled} : {}})
	return focused_now
}

// clock_dial is the dial centred on dc: its face, the hour or minute
// labels on the ring (and the 24-hour inner ring), and the selector.
@(private)
clock_dial :: proc(gtx: ^ui.Ctx, pid: ops.Area_Id, dc: ops.Point, t: ^Time, editing_minute: ^bool, is_24h, live: bool) {
	DIAL :: tok.TIME_PICKER_CLOCK_DIAL_CONTAINER_SIZE
	face := ui.circle(dc, DIAL / 2)
	ops.fill(gtx.scene, face, color(tok.TIME_PICKER_CLOCK_DIAL_COLOR))
	outer := DIAL * TIME_OUTER_RING
	inner := DIAL * TIME_INNER_RING
	id := ui.id_mix(pid, 30)
	st := ui.widget_state(gtx, id)
	// A press that moves at all is a drag (whole minutes), one that does
	// not a tap (minutes snapped to five).
	grab := ui.drag(gtx, id, slop = 0)
	if live {
		for e in ui.events(gtx, id) {
			#partial switch e.kind {
			case .Press:
				st.pressed = true
			case .Release:
				if st.pressed && !editing_minute^ {
					editing_minute^ = true // an hour picked: on to minutes
				} else if st.pressed && grab.tapped {
					// A tap snaps minutes to the nearest five.
					t.minute = (t.minute + 2) / 5 * 5 % 60
				}
				st.pressed = false
				continue
			}
			if (e.kind == .Press || e.kind == .Move) && st.pressed {
				d := e.pos - dc
				ang := math.atan2(d.x, -d.y) // 0 at 12 o'clock, clockwise
				if ang < 0 {
					ang += 2 * math.PI
				}
				if editing_minute^ {
					t.minute = int(math.round(ang / (2 * math.PI) * 60)) % 60
				} else {
					hh := int(math.round(ang / (2 * math.PI) * 12)) % 12
					switch {
					case is_24h:
						// Inside the threshold is the inner ring: 13-23 and 00.
						in_ring := math.sqrt(d.x * d.x + d.y * d.y) < TIME_INNER_THRESHOLD
						t.hour = in_ring ? (hh == 0 ? 0 : hh + 12) : (hh == 0 ? 12 : hh)
					case:
						t.hour = hh + (t.hour >= 12 ? 12 : 0)
					}
				}
			}
		}
		ops.input_area(gtx.scene, id, face, {.Press, .Release, .Move})
		ops.tag(gtx.scene, id, "clock dial")
	}
	dragging := st.pressed && grab.phase == .Dragging

	// The handle's angle, in turns, springs to the value (default-spatial)
	// the short way round; a drag follows the pointer directly.
	value := editing_minute^ ? f32(t.minute) / 60 : f32(t.hour % 12) / 12
	c := Control{}
	if live {
		c.st = st
	}
	cur := c.st != nil ? c.st.springs[0].value : value
	target := cur + (value - cur) - math.round(value - cur)
	turn: f32
	if dragging && c.st != nil {
		c.st.springs[0] = {value = target, target = target, started = true}
		turn = target
	} else {
		turn = animate(gtx, c, 0, target, .Default_Spatial, 0.001)
	}
	ring_m := clamp(animate(gtx, c, 1, editing_minute^ ? 1 : 0, .Default_Effects), 0, 1)
	on_inner := is_24h && !editing_minute^ && (t.hour == 0 || t.hour > 12)
	R := on_inner ? inner : outer
	a := turn * 2 * math.PI
	hand := dc + R * ops.Point{math.sin(a), -math.cos(a)}
	HS :: tok.TIME_PICKER_CLOCK_DIAL_SELECTOR_HANDLE_CONTAINER_SIZE

	// Labels: hours and minutes cross-fade; the handle covers one, which
	// is drawn again, clipped to the handle, on-primary.
	labels :: proc(gtx: ^ui.Ctx, dc: ops.Point, outer, inner: f32, ring_m: f32, is_24h: bool, col: ops.Color) {
		for i in 0 ..< 12 {
			na := f32(i) / 12 * 2 * math.PI
			dir := ops.Point{math.sin(na), -math.cos(na)}
			if ring_m < 1 {
				at := dc + outer * dir
				lt := shape_style(gtx, fmt.tprintf("%d", i == 0 ? 12 : i), tok.TIME_PICKER_CLOCK_DIAL_LABEL_TEXT_FONT)
				draw_text(gtx, lt, {at.x - lt.width / 2, at.y - lt.height / 2}, fade(col, 1 - ring_m))
				if is_24h {
					at = dc + inner * dir
					it := shape_style(gtx, fmt.tprintf("%02d", i == 0 ? 0 : i + 12), tok.TIME_PICKER_CLOCK_DIAL_LABEL_TEXT_FONT)
					draw_text(gtx, it, {at.x - it.width / 2, at.y - it.height / 2}, fade(col, 1 - ring_m))
				}
			}
			if ring_m > 0 {
				at := dc + outer * dir
				mt := shape_style(gtx, fmt.tprintf("%02d", i * 5), tok.TIME_PICKER_CLOCK_DIAL_LABEL_TEXT_FONT)
				draw_text(gtx, mt, {at.x - mt.width / 2, at.y - mt.height / 2}, fade(col, ring_m))
			}
		}
	}
	labels(gtx, dc, outer, inner, ring_m, is_24h, color(tok.TIME_PICKER_CLOCK_DIAL_UNSELECTED_LABEL_TEXT_COLOR))
	sel := color(tok.TIME_PICKER_CLOCK_DIAL_SELECTOR_TRACK_CONTAINER_COLOR)
	ops.stroke(gtx.scene, ui.line(gtx, dc, hand), sel, {width = tok.TIME_PICKER_CLOCK_DIAL_SELECTOR_TRACK_CONTAINER_WIDTH})
	ops.fill(gtx.scene, ui.circle(dc, tok.TIME_PICKER_CLOCK_DIAL_SELECTOR_CENTER_CONTAINER_SIZE / 2), color(tok.TIME_PICKER_CLOCK_DIAL_SELECTOR_CENTER_CONTAINER_COLOR))
	handle := ui.circle(hand, HS / 2)
	ops.fill(gtx.scene, handle, color(tok.TIME_PICKER_CLOCK_DIAL_SELECTOR_HANDLE_CONTAINER_COLOR))
	ops.clip_push(gtx.scene, handle)
	labels(gtx, dc, outer, inner, ring_m, is_24h, color(tok.TIME_PICKER_CLOCK_DIAL_SELECTED_LABEL_TEXT_COLOR))
	ops.clip_pop(gtx.scene)
}

// Carousel_Item is one carousel tile: a two-colour gradient standing in
// for an image, and a label.
Carousel_Item :: struct {
	label: string,
	a, b:  ops.Color,
}

// Carousel_Strategy is the keyline arrangement (carousel.json inputs.strategy).
Carousel_Strategy :: enum u8 {
	Multi_Browse, // large, medium and small items, sized jointly to fill
	Uncontained, // one width throughout, the last cut off; no snapping
	Hero_Start, // large item(s) and one small peek at the end
	Hero_Center, // a large item between two small ones
	Full_Screen, // one item filling the viewport
}

// Values carousel.json gives without tokens (layout carousel-defaults,
// Carousel.kt:813-824, and the snap spring, states fling-snap).
CAROUSEL_MIN_SMALL :: f32(40)
CAROUSEL_MAX_SMALL :: f32(56)
CAROUSEL_SNAP :: ui.Spring_Params{1, 400} // StiffnessMediumLow, Carousel.kt:739,769
CAROUSEL_SETTLE_DELAY :: f32(0.15) // how long scrolling must rest before a snap; not in the kit

// carousel is M3's carousel, horizontal (carousel.json): items laid out on
// the keylines strategy computes for width, each drawn full-size (its
// large width) and clipped to its current mask, so an item crossing from
// large to small collapses around its centre (parallax) with its label
// fading out. Multi-browse finds the large/medium/small counts that fill
// width best around item_width (small = large/3 in [min_small,
// max_small], medium their midpoint; Keylines.kt:44-97); hero keeps one
// large item and small peeks; uncontained keeps item_width throughout.
// Wheel, trackpad or a drag scrolls it; Left/Right step while focused; a
// snapping strategy settles on the nearest item with the spec's spring
// once wheel scrolling rests. Letting go of a drag snaps at once: a fling
// of CAROUSEL_FLING_VELOCITY or more moves on one item its way, a slower
// release settles on the nearest, never more than one item from where the
// press landed, and the spring starts at the pointer's speed (states
// fling-snap). Uncontained has no snap: a fling glides on and slows
// (ui.Sling) until it stops or meets an end; a press catches it. Items are corner extra-large (the kit has no
// carousel tokens; M3's carousel item shape). Returns the index of an
// item clicked this frame, or -1.
//
// state, when given, is the caller's Carousel_State: the scroll position
// and the grab in progress. Pass it to keep or restore the position, or
// to move the carousel from outside (set position; it snaps from there
// like a scroll); it is kept internally otherwise.
//
// Departures: horizontal only; the hero-center strategy centres the
// focal item on a small leading keyline rather than solving both sides.
carousel :: proc(
	gtx: ^ui.Ctx,
	items: []Carousel_Item,
	width: f32 = 400,
	height: f32 = 200,
	strategy := Carousel_Strategy.Multi_Browse,
	item_width: f32 = 186,
	item_spacing: f32 = 0,
	min_small := CAROUSEL_MIN_SMALL,
	max_small := CAROUSEL_MAX_SMALL,
	state: ^Carousel_State = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	p := ui.widget_open(gtx, key, loc)
	ui.semantics(gtx, &p, {role = .List, label = "carousel"})
	size := ui.constrain(gtx.constraints, {width, height})
	kl := carousel_keylines(strategy, size.x, item_width, item_spacing, min_small, max_small)
	n := len(items)
	max_pos := f32(max(n - kl.focal_count - (kl.lead - 1), 0))
	if strategy == .Uncontained {
		max_pos = max(f32(n) - (size.x + item_spacing) / (kl.large + item_spacing), 0)
	}
	// springs[0] is the position's snap.
	st := ui.widget_state(gtx, p.id)
	cs := state if state != nil else ui.widget_data(gtx, p.id, Carousel_State)
	rest := &ui.widget_data(gtx, p.id, Carousel_Rest).delay
	// A position set from outside since last frame moves like a scroll:
	// internally the snap's value always ends a frame equal to it.
	scrolled := cs.position != st.springs[0].value
	clicked := -1
	pitch := kl.large + item_spacing
	ui.drag_update(&cs.drag, ui.events(gtx, p.id), .Horizontal, CAROUSEL_SLOP)
	if cs.drag.phase != .Idle {
		ui.sling_stop(&cs.glide) // a press catches a glide
	}
	if cs.drag.delta.x != 0 {
		cs.position -= cs.drag.delta.x / pitch
		scrolled = true
	}
	flung := cs.drag.released
	for e in ui.events(gtx, p.id) {
		#partial switch e.kind {
		case .Scroll:
			cs.position += (e.scroll.x + e.scroll.y) / pitch
			scrolled = true
		case .Press:
			st.pressed = true
			cs.from = math.round(cs.position)
		case .Release:
			if st.pressed && cs.drag.tapped {
				clicked = carousel_hit(kl, cs.position, n, e.pos.x, item_spacing)
			}
			st.pressed = false
			scrolled = true
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
		case .Key:
			#partial switch e.key {
			case .Left:
				cs.position = math.round(cs.position) - 1
				scrolled = true
			case .Right:
				cs.position = math.round(cs.position) + 1
				scrolled = true
			}
		}
	}
	if flung && strategy == .Uncontained {
		ui.sling_start(&cs.glide, cs.drag.velocity, gtx.time)
	}
	if glide, gliding := ui.sling_step(&cs.glide, gtx.time); glide.x != 0 || gliding {
		cs.position -= glide.x / pitch
		scrolled = true
		if cs.position <= 0 || cs.position >= max_pos {
			ui.sling_stop(&cs.glide) // it met an end
		} else if gliding {
			ui.request_frame(gtx)
		}
	}
	cs.position = clamp(cs.position, 0, max_pos)
	if (scrolled || st.pressed) && !flung {
		st.springs[0] = {value = cs.position, target = cs.position, started = true}
		rest^ = {to = 1, duration = CAROUSEL_SETTLE_DELAY}
		cs.aimed = false
	} else if strategy != .Uncontained {
		if flung {
			// Let go: snap at once to the item the fling aims at, the
			// spring starting at the pointer's speed.
			cs.aim = carousel_fling_aim(cs.position, cs.from, -cs.drag.velocity.x, max_pos)
			cs.aimed = true
			st.springs[0] = {value = cs.position, velocity = -cs.drag.velocity.x / pitch, target = cs.position, started = true}
			rest^ = {to = 1, duration = CAROUSEL_SETTLE_DELAY, t = CAROUSEL_SETTLE_DELAY}
		}
		// Resting: once the delay runs out, snap to the aimed or nearest item.
		resting := rest.t >= rest.duration
		if !resting {
			ui.tween_update(rest, gtx)
		} else {
			target := cs.aim if cs.aimed else math.round(cs.position)
			cs.position = ui.spring_update(&st.springs[0], gtx, clamp(target, 0, max_pos), CAROUSEL_SNAP, 0.001)
		}
	}
	pos := cs.position
	focused := st.focused
	view := ops.Rect{0, 0, size.x, size.y}
	ops.input_area(gtx.scene, p.id, view, {.Scroll, .Press, .Release, .Move, .Key, .Focus, .Blur})
	ops.tag(gtx.scene, p.id, "carousel")
	ops.clip_push(gtx.scene, view)
	on := color(.On_Primary)
	for i in 0 ..< n {
		r, ok := carousel_item_rect(kl, pos, i, n, item_spacing, size.y)
		if !ok || r.x >= size.x || r.x + r.w <= 0 {
			continue
		}
		it := items[i]
		mk := corners(tok.SYS_SHAPE_CORNER_EXTRA_LARGE, r)
		mask := rounded(gtx, r, mk)
		// The content is the large width, centred on the mask: parallax.
		content := ops.Rect{r.x + r.w / 2 - kl.large / 2, 0, kl.large, size.y}
		ops.clip_push(gtx.scene, mask)
		ops.fill(gtx.scene, content, ops.Linear_Gradient{{content.x, 0}, {content.x + content.w, content.h}, gradient_stops(gtx, it.a, it.b)})
		ops.clip_pop(gtx.scene)
		a := kl.large > kl.small ? clamp((r.w - kl.small) / (kl.large - kl.small), 0, 1) : 1
		if a > 0.3 {
			t := shape_text(gtx, it.label, .Title_Medium)
			ops.clip_push(gtx.scene, mask)
			draw_text(gtx, t, {r.x + 16, r.h - 16 - t.height}, fade(on, (a - 0.3) / 0.7))
			ops.clip_pop(gtx.scene)
		}
		ui.part_semantics(gtx, &p, ui.id_mix(p.id, u64(i)), r, {role = .List_Item, label = it.label})
	}
	ops.clip_pop(gtx.scene)
	if focused {
		paint_focus_ring(gtx, {focused = true}, {view, CORNER_EXTRA_LARGE})
	}
	ui.widget_close(gtx, &p, {size = size})
	return clicked
}

// Carousel_State is what a carousel keeps between frames: see carousel's
// state parameter. The zero value is scrolled to the start, not grabbed.
Carousel_State :: struct {
	// position is the scroll position in items: 0 puts the first item on
	// the first focal keyline, 1 the second, and fractions lie between.
	position: f32,
	drag:     ui.Drag, // a press, a drag once past CAROUSEL_SLOP rather than a click
	from:     f32, // the item the press landed on: a fling leaves it by one item at most
	aim:      f32, // with aimed, the item the last fling settles on
	aimed:    bool,
	glide:    ui.Sling, // uncontained: a fling carrying on after the release
}

// CAROUSEL_SLOP is how far, in dp, a press on a carousel moves sideways
// before it scrolls rather than clicks an item.
CAROUSEL_SLOP :: f32(4)

// CAROUSEL_FLING_VELOCITY is the release speed, in dp/s, at which a fling
// moves on to the next item rather than settling on the nearest: Compose's
// MinFlingVelocityDp (foundation SnapFlingBehavior.kt:432), which the
// carousel's pager snapping uses.
CAROUSEL_FLING_VELOCITY :: f32(400)

// carousel_fling_aim is the item a fling released at pos settles on.
// velocity is the release's, in dp/s toward later items. Fast enough, it
// is the next item that way; slower, the nearest (snapPositionalThreshold
// 0.5, foundation Pager.kt:478). Either way it stays within one item of
// from, the item the press landed on (CarouselDefaults.
// singleAdvanceFlingBehavior's PagerSnapDistance.atMost(1), material3
// Carousel.kt:737-745), and in [0, max_pos]. Line numbers are androidx
// 1358a48e, the commit the m3e-kit pins.
carousel_fling_aim :: proc(pos, from, velocity, max_pos: f32) -> f32 {
	aim := math.round(pos)
	if velocity >= CAROUSEL_FLING_VELOCITY {
		aim = math.floor(pos) + 1
	} else if velocity <= -CAROUSEL_FLING_VELOCITY {
		aim = math.ceil(pos) - 1
	}
	return clamp(aim, max(from - 1, 0), min(from + 1, max_pos))
}

// Carousel_Rest is how long a carousel's scrolling has rested, counting
// up to CAROUSEL_SETTLE_DELAY before the snap starts.
@(private)
Carousel_Rest :: struct {
	delay: ui.Tween,
}

// Carousel_Keylines are one strategy's item sizes along the viewport:
// sizes[i] is the width of the item i places past the focal position
// (negative places leave at the start), clamped at both ends.
@(private)
Carousel_Keylines :: struct {
	sizes:       [16]f32,
	count:       int, // sizes in use
	lead:        int, // how many keylines come before the first focal one
	focal_count: int, // large items
	large:       f32,
	small:       f32,
}

// carousel_keylines arranges width for strategy s.
@(private)
carousel_keylines :: proc(s: Carousel_Strategy, width, preferred, spacing, min_small, max_small: f32) -> (k: Carousel_Keylines) {
	avail := max(width, 1)
	target := clamp(preferred, 1, avail)
	small := clamp(target / 3, min_small, max_small)
	add :: proc(k: ^Carousel_Keylines, v: f32, n: int) {
		for _ in 0 ..< n {
			if k.count < len(k.sizes) {
				k.sizes[k.count] = v
				k.count += 1
			}
		}
	}
	switch s {
	case .Multi_Browse:
		// The lowest-cost counts: large ones as close to the target size as
		// fits once one small (and maybe one medium) take their share.
		best_cost := f32(1e9)
		best_l, best_m: int
		best_large: f32
		for l in 1 ..= max(int(avail / small), 1) {
			for m in 0 ..= 1 {
				// avail = l*L + m*(L+small)/2 + small + spacing*(items-1)
				items := l + m + 1
				room := avail - small - spacing * f32(items - 1) - f32(m) * small / 2
				L := room / (f32(l) + f32(m) / 2)
				if L < small * 1.5 {
					continue
				}
				cost := abs(L - target)
				if cost < best_cost {
					best_cost, best_l, best_m, best_large = cost, l, m, L
				}
			}
		}
		if best_l == 0 {
			best_l, best_large = 1, avail
		}
		k.large, k.small, k.focal_count = best_large, small, best_l
		add(&k, small, 1) // the leaving keyline
		k.lead = 1
		add(&k, best_large, best_l)
		add(&k, (best_large + small) / 2, best_m)
		add(&k, small, 1)
	case .Hero_Start, .Hero_Center:
		// Hero collapses to full screen without room for its smalls and a
		// large at least 1.25 times them (layout hero-collapse-to-full-screen).
		smalls := s == .Hero_Center ? 2 : 1
		if avail < f32(smalls) * min_small + min_small * 1.25 {
			k.large, k.small, k.focal_count = avail, avail, 1
			add(&k, avail, 3)
			k.lead = 1
			break
		}
		L := avail - f32(smalls) * (small + spacing)
		k.large, k.small, k.focal_count = L, small, 1
		add(&k, small, 1)
		k.lead = 1
		if s == .Hero_Center {
			// The leading small peek sits in view, before the focal item.
			add(&k, small, 1)
			k.lead = 2
		}
		add(&k, L, 1)
		add(&k, small, 1)
	case .Full_Screen:
		k.large, k.small, k.focal_count = avail, avail, 1
		add(&k, avail, 3)
		k.lead = 1
	case .Uncontained:
		k.large, k.small, k.focal_count = target, target, 1
		add(&k, target, 1)
		k.lead = 1
		add(&k, target, len(k.sizes) - 1)
	}
	return
}

// carousel_size is the width of the item at fractional keyline slot s
// (0 = the first focal keyline), interpolated between keylines.
@(private)
carousel_size :: proc(k: Carousel_Keylines, s: f32) -> f32 {
	x := s + f32(k.lead)
	if x <= 0 {
		return k.sizes[0]
	}
	if x >= f32(k.count - 1) {
		return k.sizes[k.count - 1]
	}
	i := int(x)
	f := x - f32(i)
	return k.sizes[i] + (k.sizes[i + 1] - k.sizes[i]) * f
}

// carousel_item_rect is item i's mask at scroll position pos: items are
// laid end to end from the one leaving at the start, which slides out
// past x = 0 as it shrinks to the leaving keyline.
@(private)
carousel_item_rect :: proc(k: Carousel_Keylines, pos: f32, i, n: int, spacing, h: f32) -> (ops.Rect, bool) {
	first := int(math.floor(pos))
	frac := pos - f32(first)
	// Keylines between the leaving one and the focal one hold items too
	// (hero-center's leading peek): item first sits on the first of them,
	// at 0, and the focal item is lead-1 places on.
	if i < first {
		return {}, false
	}
	skip := f32(k.lead - 1)
	x := -frac * (k.sizes[0] + spacing)
	for j in first ..< i {
		x += carousel_size(k, f32(j) - pos - skip) + spacing
	}
	w := carousel_size(k, f32(i) - pos - skip)
	return {x, 0, w, h}, true
}

// carousel_hit is the index of the item under x at pos, or -1.
@(private)
carousel_hit :: proc(k: Carousel_Keylines, pos: f32, n: int, x, spacing: f32) -> int {
	for i in 0 ..< n {
		r, ok := carousel_item_rect(k, pos, i, n, spacing, 1)
		if ok && x >= r.x && x < r.x + r.w {
			return i
		}
	}
	return -1
}

@(private)
gradient_stops :: proc(gtx: ^ui.Ctx, a, b: ops.Color) -> []ops.Gradient_Stop {
	stops := make([]ops.Gradient_Stop, 2, gtx.allocator)
	stops[0] = {0, a}
	stops[1] = {1, b}
	return stops
}
