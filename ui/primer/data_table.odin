package primer

import "base:runtime"
import "core:fmt"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Table.Container's heading and Table.Pagination: the parts of Primer's
// DataTable around the table itself, which is data_grid.

// Data_Table_Heading is an open table heading.
Data_Table_Heading :: struct {
	gtx:      ^ui.Ctx,
	col, row: ui.Flex,
	subtitle: string,
	divider:  bool,
}

// data_table_heading_open opens Table.Container's heading: the title
// (body-medium semibold, 20px line) with the caller's actions end-aligned
// 8px apart beside it, up to data_table_heading_close, then the subtitle
// (body-small) and an optional divider, 16px above and 8px below; a table
// after it sits 8px below (Table.module.css:2-66).
data_table_heading_open :: proc(gtx: ^ui.Ctx, title: string, subtitle := "", divider := false, key: u64 = 0, loc := #caller_location) -> (h: Data_Table_Heading) {
	h.gtx, h.subtitle, h.divider = gtx, subtitle, divider
	h.col = ui.column_open(gtx, align = .Fill, key = key, loc = loc)
	h.row = ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = 20}
	layout_text(gtx, title, st, color(.Fg_Color_Default), .Heading)
	ui.fill_space(gtx)
	return
}

// data_table_heading_close ends the heading.
data_table_heading_close :: proc(h: ^Data_Table_Heading) {
	gtx := h.gtx
	ui.close(&h.row)
	if h.subtitle != "" {
		st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_SMALL, line_height = tok.TEXT_BODY_SIZE_SMALL * tok.TEXT_TITLE_LINE_HEIGHT_SMALL}
		layout_text(gtx, h.subtitle, st, color(.Fg_Color_Default), .Text)
	}
	if h.divider {
		ui.spacer(gtx, tok.BASE_SIZE_16)
		rule(gtx)
	}
	ui.spacer(gtx, tok.BASE_SIZE_8)
	ui.close(&h.col)
}

// data_table_heading is data_table_heading_open as a guard: `if
// primer.data_table_heading(gtx, "Repositories") { … }` closes it at the end
// of the if, or of the block when called as a statement.
@(deferred_in = data_table_heading_guard_close)
data_table_heading :: proc(
	gtx: ^ui.Ctx,
	title: string,
	subtitle := "",
	divider := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	ui.guard_hold(gtx, Data_Table_Heading)^ = data_table_heading_open(gtx, title, subtitle, divider, key, loc)
	return true
}

@(private = "file")
data_table_heading_guard_close :: proc(
	gtx: ^ui.Ctx,
	title: string,
	subtitle: string,
	divider: bool,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	h := ui.guard_take(gtx, Data_Table_Heading)
	data_table_heading_close(h)
}

// rule is a 1px --borderColor-default line across the width offered.
@(private)
rule :: proc(gtx: ^ui.Ctx, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	w := ui.is_finite(gtx.constraints.max.x) ? gtx.constraints.max.x : 0
	ops.fill(gtx.scene, ops.Rect{0, 0, w, tok.BORDER_WIDTH_THIN}, color(.Border_Color_Default))
	ui.semantics(gtx, &p, {role = .Separator})
	ui.widget_close(gtx, &p, {size = {w, tok.BORDER_WIDTH_THIN}})
}

// PAGE_STEP_MIN is a page button's minimum side, 2rem
// (DataTable/Pagination.module.css:134-141).
PAGE_STEP_MIN :: tok.BASE_SIZE_32

// data_table_pagination is Table.Pagination: a footer bar continuing a
// table built with footer = true (no top rule, medium bottom corners,
// 8px by 16px padding), the range "start‒end of total" in small muted
// text at the start, and at the end Previous, the page numbers (first and
// last, two either side of the current, ellipses between) and Next. The
// current page is --fgColor-onEmphasis on --bgColor-accent-emphasis;
// Previous on the first page and Next on the last are muted, without
// their chevron, and do nothing. show_pages, when not given, hides the
// numbers below 768px. page is the caller's zero-based index; it returns
// true on the frame page changes, when the caller shows that slice.
//
// The range is a status node, jm:ui's live region, as the web's is
// (DataTable/Pagination.tsx:181-199).
//
// Departures: Previous and Next at the ends are disabled rather than
// aria-disabled and focusable (DataTable/Pagination.tsx:113-168), as
// jm:ui has no focusable disabled state.
data_table_pagination :: proc(
	gtx: ^ui.Ctx,
	label: string,
	page: ^int,
	total: int,
	page_size := 25,
	show_pages: Maybe(bool) = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	size := max(page_size, 1)
	pages := max((total + size - 1) / size, 1)
	page^ = clamp(page^, 0, pages - 1)
	before := page^
	bar := ui.box_open(gtx, {paint = paint_pagination_bar, padding = {16, 8, 16, 8}}, key, loc)
	defer ui.close(&bar)
	ui.container_semantics(gtx, {role = .Navigation, label = ui.frame_string(gtx, label)})
	r := ui.row_open(gtx, gap = tok.BASE_SIZE_16, align = .Center)
	defer ui.close(&r)
	first := total == 0 ? 0 : page^ * size + 1
	last := min((page^ + 1) * size, total)
	small := style(.Body_Small)
	layout_text(gtx, fmt.aprintf("%d‒%d of %d", first, last, total, allocator = gtx.allocator), small, color(.Fg_Color_Muted), .Status)
	ui.fill_space(gtx)
	steps := ui.row_open(gtx, gap = 0, align = .Center)
	defer ui.close(&steps)
	if page_step(gtx, "Previous", "Previous page", page^ > 0, false, .Chevron_Left, 1) {
		page^ -= 1
	}
	if show_pages.? or_else viewport_range(gtx) != .Narrow {
		ui.spacer(gtx, tok.BASE_SIZE_16)
		for n in page_numbers(page^, pages, gtx.allocator) {
			if n < 0 {
				ellipsis_step(gtx, u64(1000 - n))
				continue
			}
			name := fmt.aprintf("%d", n + 1, allocator = gtx.allocator)
			said := fmt.aprintf("Page %d", n + 1, allocator = gtx.allocator)
			if page_step(gtx, name, said, true, n == page^, .None, u64(100 + n)) {
				page^ = n
			}
		}
		ui.spacer(gtx, tok.BASE_SIZE_16)
	}
	if page_step(gtx, "Next", "Next page", page^ < pages - 1, false, .Chevron_Right, 2) {
		page^ += 1
	}
	return page^ != before
}

// page_numbers is the pages to show around current of count: the first
// and last, two either side of current, and -1, -2 for the gaps
// (DataTable/Pagination.tsx:53-99).
page_numbers :: proc(current, count: int, allocator := context.allocator) -> []int {
	out := make([dynamic]int, allocator)
	gap := -1
	prev := -1
	for n in 0 ..< count {
		if n == 0 || n == count - 1 || abs(n - current) <= 2 {
			if prev >= 0 && n - prev > 1 {
				append(&out, gap)
				gap -= 1
			}
			append(&out, n)
			prev = n
		}
	}
	return out[:]
}

@(private)
paint_pagination_bar :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, size: ops.Size, user: rawptr) {
	r := tok.BORDER_RADIUS_MEDIUM
	b := tok.BORDER_WIDTH_THIN
	edge := color(.Border_Color_Default)
	ops.clip_push(gtx.scene, ops.Rect{0, 0, size.x, size.y})
	defer ops.clip_pop(gtx.scene)
	// A rounded box pulled up past the top: no top rule, rounded bottom.
	box := ops.Round_Rect{{0, -r, size.x, size.y + r}, r}
	ops.fill(gtx.scene, box, color(.Bg_Color_Default))
	stroke_inside(gtx, box, edge, b)
}

// page_step is one pagination step: a page number at least 32px square,
// 8px by 6px padding, or Previous or Next with its chevron; current and
// enabled set its look.
@(private)
page_step :: proc(gtx: ^ui.Ctx, text, said: string, enabled, current: bool, chevron: Icon, key: u64, loc := #caller_location) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_MEDIUM, line_height = 20}
	t := design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	show_chevron := chevron != .None && enabled
	pad_x: f32 = chevron != .None ? 8 : 6
	w := t.width + 2 * pad_x + (show_chevron ? BUTTON_ICON + 4 : 0)
	sz := ui.constrain_min(gtx.constraints, {max(w, PAGE_STEP_MIN), max(20 + 16, PAGE_STEP_MIN)})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, enabled ? .Live : .Disabled)
	rr := ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}
	ink: ops.Color
	switch {
	case current:
		ops.fill(gtx.scene, rr, color(.Bg_Color_Accent_Emphasis))
		ink = color(.Fg_Color_On_Emphasis)
	case !enabled:
		ink = color(.Fg_Color_Muted)
	case:
		if c.state == .Hovered || c.state == .Pressed || c.focus_visible {
			ops.fill(gtx.scene, rr, color(.Control_Transparent_Bg_Color_Hover))
		}
		ink = color(chevron != .None ? .Fg_Color_Accent : .Fg_Color_Default)
	}
	x := (sz.x - w) / 2 + pad_x
	if show_chevron && chevron == .Chevron_Left {
		icon(gtx, chevron, {x, (sz.y - BUTTON_ICON) / 2}, BUTTON_ICON, ink)
		x += BUTTON_ICON + 4
	}
	draw_text(gtx, t, {x, (sz.y - t.height) / 2}, ink)
	if show_chevron && chevron == .Chevron_Right {
		icon(gtx, chevron, {x + t.width + 4, (sz.y - BUTTON_ICON) / 2}, BUTTON_ICON, ink)
	}
	if current {
		paint_focus_on_emphasis(gtx, c, rr)
	} else {
		paint_focus_outline(gtx, c, rr)
	}
	listen(gtx, c.st, p.id, area)
	tag := ui.frame_string(gtx, said)
	ops.tag(gtx.scene, p.id, tag, area)
	ui.semantics(gtx, &p, {role = .Button, label = tag, states = design.state_if(!enabled, {.Disabled}) + design.state_if(current, {.Selected})})
	ui.widget_close(gtx, &p, {sz, (sz.y - t.height) / 2 + baseline_of(t)})
	return c.clicked && enabled && !current
}

// ellipsis_step is a truncation step: a 32px square ellipsis.
@(private)
ellipsis_step :: proc(gtx: ^ui.Ctx, key: u64, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	st := style(.Body_Medium)
	t := design.shape_style(gtx, "…", st, font_for(gtx, st.weight))
	draw_text(gtx, t, {(PAGE_STEP_MIN - t.width) / 2, (PAGE_STEP_MIN - t.height) / 2}, color(.Fg_Color_Muted))
	ui.widget_close(gtx, &p, {size = {PAGE_STEP_MIN, PAGE_STEP_MIN}})
}
