package primer

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// A data grid's Text and Range filter panels, which hang from a header's
// filter button as the Set filter's SelectPanel does: a Contains field
// for a Text column; Min and Max fields for a Number column's Range; a
// date range picker with presets for a Date column's. Each applies as it
// is edited and has a Clear that drops the column's filter.

// FILTER_PANEL_W is a Text or Range panel's width: the SelectPanel's
// small overlay (tok.OVERLAY_WIDTH_SMALL).
@(private)
FILTER_PANEL_W :: tok.OVERLAY_WIDTH_SMALL

// FILTER_PANEL_PAD is a Text or Range panel's inset, the overlay's
// normal padding.
@(private)
FILTER_PANEL_PAD :: tok.OVERLAY_PADDING_NORMAL

// Error texts a Range panel's number fields show.
@(private)
ERR_NOT_A_NUMBER :: "Enter a number"
@(private)
ERR_MAX_BELOW_MIN :: "Max is less than min"

// SECONDS_PER_DAY turns a date's day count into the Unix seconds a Date
// column's values are.
@(private)
SECONDS_PER_DAY :: 86400

// panel_seed fills column col's panel from the column's filter as it
// stands, as the panel opens.
@(private)
panel_seed :: proc(g: ^Data_Grid, col: int) {
	f := &g.filter
	cur := datagrid.find_filter(&g.grid.view, col)
	ui.text_set(&f.text, cur.text if cur != nil && cur.kind == .Text else "")
	ui.text_set(&f.lo, bound_text(cur, true))
	ui.text_set(&f.hi, bound_text(cur, false))
	f.lo_err, f.hi_err = "", ""
	f.dates = {}
	if cur != nil && cur.kind == .Range && cur.has_lo && cur.has_hi {
		f.dates = {day_of(cur.lo), day_of(cur.hi)}
	}
}

// bound_text is a Range filter's low or high bound as a field shows it,
// empty when it is open.
@(private)
bound_text :: proc(cur: ^datagrid.Filter, low: bool) -> string {
	if cur == nil || cur.kind != .Range {
		return ""
	}
	has, v := cur.has_lo, cur.lo
	if !low {
		has, v = cur.has_hi, cur.hi
	}
	return fmt.tprintf("%v", v) if has else ""
}

// day_of is the date Unix seconds fall on.
@(private)
day_of :: proc(seconds: f64) -> Date {
	return date_from_days(int(math.floor(seconds / SECONDS_PER_DAY)))
}

// range_panel is the open panel of column col, a Text or a Range one,
// hanging from anchor: an anchored dialog titled for the column.
@(private)
range_panel :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, col: int, anchor: ui.Last_Widget) {
	f := &g.filter
	title := fmt.aprintf("Filter by %s", g.cols[col].title, allocator = gtx.allocator)
	key := u64(ui.id_mix(ops.Area_Id(col), 0xf17f))
	a := anchored_overlay_open(gtx, &f.open, anchor, role = .Dialog, name = title, key = key)
	if a.visible {
		sz := ui.sized_open(gtx, {{FILTER_PANEL_W, 0}, {FILTER_PANEL_W, ui.INF}}, key = 1)
		in_ := ui.inset_open(gtx, ui.pad_all(FILTER_PANEL_PAD), key = 2)
		c := ui.column_open(gtx, gap = tok.STACK_GAP_NORMAL, align = .Fill, key = 3)
		layout_text(gtx, title, style(.Body_Medium), color(.Fg_Color_Default), .Text)
		switch {
		case g.cols[col].filter == .Text:
			text_fields(gtx, g, col)
		case g.cols[col].kind == .Date:
			date_fields(gtx, g, col)
		case:
			number_fields(gtx, g, col)
		}
		if button(gtx, "Clear", .Default, .Small, block = true, key = 4) {
			panel_clear(g, col)
		}
		ui.close(&c)
		ui.close(&in_)
		ui.close(&sz)
	}
	anchored_overlay_close(&a)
}

// panel_clear drops column col's filter and empties its panel.
@(private)
panel_clear :: proc(g: ^Data_Grid, col: int) {
	datagrid.view_clear_filter(&g.grid.view, col)
	g.applied = -1
	panel_seed(g, col)
}

// text_fields is a Text panel's Contains field: the column keeps the
// rows whose text holds what it says, without case, as it is typed.
@(private)
text_fields :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, col: int) {
	f := &g.filter
	fc := form_control_open(gtx, "Contains", key = 5)
	e := text_input(gtx, &f.text, "Text to find", .Small, leading = .Search, block = true, key = 6)
	form_control_close(gtx, &fc)
	if e.changed {
		datagrid.view_set_text(&g.grid.view, col, ui.text_string(&f.text))
		g.applied = -1
	}
}

// number_fields are a number Range panel's Min and Max fields, side by
// side, either empty for an open bound. An edit applies once both read
// as numbers and Min is not over Max; until then the field at fault says
// why and the filter stays as it was.
@(private)
number_fields :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, col: int) {
	f := &g.filter
	half := (FILTER_PANEL_W - 2 * FILTER_PANEL_PAD - tok.STACK_GAP_CONDENSED) / 2
	row := ui.row_open(gtx, gap = tok.STACK_GAP_CONDENSED, align = .Start, key = 7)
	lo := bound_field(gtx, &f.lo, "Min", f.lo_err, half, 8)
	hi := bound_field(gtx, &f.hi, "Max", f.hi_err, half, 10)
	ui.close(&row)
	if !lo && !hi {
		return
	}
	lo_err, hi_err := range_apply(g, col)
	if lo_err != f.lo_err || hi_err != f.hi_err {
		f.lo_err, f.hi_err = lo_err, hi_err
		ui.request_frame(gtx)
	}
}

// bound_field is one of a Range panel's number fields, labelled label,
// in a form_control saying err when it has one. It reports an edit.
@(private)
bound_field :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	label, err: string,
	width: f32,
	key: u64,
) -> bool {
	fc := form_control_open(gtx, label, validation = err, key = key)
	defer form_control_close(gtx, &fc)
	status := Validation_Status.Error if err != "" else .None
	e := text_input(gtx, s, "Any", .Small, validation = status, width = width, key = key + 1)
	return e.changed
}

// range_apply makes column col's Range filter what the panel's Min and
// Max say, both empty clearing it, when they make a range; it returns
// what is wrong with each when they do not.
@(private)
range_apply :: proc(g: ^Data_Grid, col: int) -> (lo_err, hi_err: string) {
	f := &g.filter
	lo, has_lo, lo_ok := parse_bound(ui.text_string(&f.lo))
	hi, has_hi, hi_ok := parse_bound(ui.text_string(&f.hi))
	if !lo_ok {
		lo_err = ERR_NOT_A_NUMBER
	}
	if !hi_ok {
		hi_err = ERR_NOT_A_NUMBER
	}
	if lo_ok && hi_ok && has_lo && has_hi && lo > hi {
		hi_err = ERR_MAX_BELOW_MIN
	}
	if lo_err != "" || hi_err != "" {
		return
	}
	if has_lo || has_hi {
		datagrid.view_set_range(&g.grid.view, col, lo, has_lo, hi, has_hi)
	} else {
		datagrid.view_clear_filter(&g.grid.view, col)
	}
	g.applied = -1
	return
}

// parse_bound reads a number field: empty is an open bound; otherwise a
// finite number, thousands separators allowed, or not ok.
@(private)
parse_bound :: proc(s: string) -> (v: f64, has, ok: bool) {
	t := strings.trim_space(s)
	if t == "" {
		return 0, false, true
	}
	t, _ = strings.remove_all(t, ",", context.temp_allocator)
	n, parsed := strconv.parse_f64(t)
	if !parsed || math.is_nan(n) || math.is_inf(n) {
		return 0, false, false
	}
	return n, true, true
}

// date_fields is a Date Range panel's date range picker, with the
// standard presets as of the grid's today: the column keeps the rows
// dated from the first day's start to the last day's end.
@(private)
date_fields :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, col: int) {
	f := &g.filter
	today := g.today if g.today != {} else date_today()
	presets := standard_presets(today)
	changed := date_range_picker(
		gtx,
		&f.dates,
		today,
		presets[:],
		name = "Dates",
		reserve = false,
		size = .Small,
		key = 12,
	)
	if !changed {
		return
	}
	if f.dates.start == {} {
		datagrid.view_clear_filter(&g.grid.view, col)
	} else {
		lo := f64(date_days(f.dates.start)) * SECONDS_PER_DAY
		hi := f64(date_days(f.dates.end) + 1) * SECONDS_PER_DAY - 1
		datagrid.view_set_range(&g.grid.view, col, lo, true, hi, true)
	}
	g.applied = -1
}
