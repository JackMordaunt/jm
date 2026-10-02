package primer

import "base:runtime"
import "core:fmt"
import "core:strconv"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Cell_Padding is a data table's density: block and inline cell padding
// of 4/8px (condensed), 8/12px (normal) or 12/16px (spacious)
// (Table.module.css:88-102).
Cell_Padding :: enum u8 {
	Normal,
	Condensed,
	Spacious,
}

@(private)
cell_padding :: proc(p: Cell_Padding) -> (block, inline: f32) {
	switch p {
	case .Condensed:
		return 4, 8
	case .Spacious:
		return 12, 16
	case .Normal:
	}
	return 8, 12
}

// TABLE_EDGE_PADDING is the first cell's start and the last cell's end
// padding in every density, so text lines up with the container's edge
// (Table.module.css:171-179).
TABLE_EDGE_PADDING :: tok.BASE_SIZE_16

// TABLE_RADIUS is the table's outer corner radius, 0.375rem
// (Table.module.css:71): a literal in the CSS, equal to --borderRadius-medium.
TABLE_RADIUS :: tok.BORDER_RADIUS_MEDIUM

// TABLE_TEXT is the table's text: 12px on 20px lines (Table.module.css:
// 73-80); a header or row header is semibold.
TABLE_TEXT :: tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = 12, line_height = 20}

// SORT_ICON_GAP is the gap between a sortable header's text and its icon,
// 0.5rem (Table.module.css:268-270).
SORT_ICON_GAP :: tok.BASE_SIZE_8

// Column_Width is how a column is sized (useTable.ts:387-433): Grow, the
// default, is minmax(max-content, 1fr), never narrower than its widest
// cell; Grow_Collapse is minmax(0, 1fr), shrinking below its content;
// Auto is its widest cell and takes no free width; Fixed is Column.px.
Column_Width :: enum u8 {
	Grow,
	Grow_Collapse,
	Auto,
	Fixed,
}

// Column_Align places a column's cells and header at its start or end.
Column_Align :: enum u8 {
	Start,
	End,
}

// Column is one data table column: its header text, alignment, sizing
// (min_width and max_width replace the computed bounds; 0 is none),
// whether it is a row header (semibold) and whether it sorts.
Column :: struct {
	header:               string,
	align:                Column_Align,
	width:                Column_Width,
	px:                   f32,
	min_width, max_width: f32,
	row_header:           bool,
	sortable:             bool,
}

// Sort_Direction is a sorted column's order.
Sort_Direction :: enum u8 {
	Ascending,
	Descending,
}

// Table_Sort is a table's sort: the sorted column, -1 for none, and its
// direction. The caller owns it and orders its rows by it.
Table_Sort :: struct {
	column:    int,
	direction: Sort_Direction,
}

// Table_Row_Kind is what a grid row of the table holds, for the paint.
@(private)
Table_Row_Kind :: enum u8 {
	Header,
	Body,
	Group,
	Skeleton,
}

// Data_Table is an open data table.
Data_Table :: struct {
	gtx:           ^ui.Ctx,
	id:            ops.Area_Id,
	columns:       []Column,
	padding:       Cell_Padding,
	rec:           ui.Recording,
	grid:          ui.Grid,
	key:           u64,
	loc:           runtime.Source_Code_Location,
	width:         f32,
	cell:          int, // cells laid out in the current row
	rows:          [dynamic]Table_Row_Kind,
	skeleton_rows: int,
	footer:        bool,
	open:          ui.Inset,
	label:         string,
}

// data_table_open opens Primer's DataTable (data-table.json,
// Table.module.css, DataTable/Table.tsx): a grid of columns on
// --bgColor-default in 12px text on 20px lines, each column sized from
// its widest cell (Column_Width), cells padded by density with 16px at
// the row's outer edges, every cell ruled below and the rows ruled at
// their outer sides in --borderColor-default, the header row semibold
// --fgColor-muted on --bgColor-muted with a top rule and 6px top corners.
// A sortable header is a button: activating it sorts ascending, again
// flips the direction; the sorted header turns --fgColor-default and
// shows its direction's icon, an unsorted one previews the ascending icon
// while hovered or focused. A hovered body row fills with
// --control-transparent-bgColor-hover. It returns true on the frame sort
// changed, when the caller reorders its rows (compare_alphanumeric helps).
// Add rows with data_table_cell (or data_table_cell_open/close for any
// content), a group heading with data_table_group, then data_table_close.
// loading shows skeleton_rows placeholder lines under the real header
// instead of rows. With no rows the header sits over an empty body: the
// caller shows a Blankslate below it. A table wider than its box
// scrolls sideways. footer squares the bottom corners for a pagination
// bar (data_table_pagination) below.
//
// Departures: rows are the caller's to order; the table keeps no data,
// so client-side and external sorting are the same, and a group keeps
// its place as the caller lays it out. The header's hover is its sort
// button's, which fills the header's content. Skeleton bars are drawn
// here in --skeletonLoader-bgColor without the shimmer, as SkeletonText
// is another component (and its 14px metrics are kept, so loading rows
// are taller, data-table.json gotcha). jm:ui has no column or row header
// roles: cells are cells and a header is its sort button or text.
data_table_open :: proc(
	gtx: ^ui.Ctx,
	columns: []Column,
	sort: ^Table_Sort = nil,
	cell_padding := Cell_Padding.Normal,
	loading := false,
	skeleton_rows := 10,
	footer := false,
	label := "",
	key: u64 = 0,
	loc := #caller_location,
) -> (t: ^Data_Table, sorted: bool) {
	// On the frame allocator: the grid's paint reads it at close.
	t = new(Data_Table, gtx.allocator)
	t.gtx, t.columns, t.padding, t.key, t.loc = gtx, columns, cell_padding, key, loc
	t.footer, t.label = footer, label
	t.id = ui.claim_id(gtx, key, loc)
	t.rows = make([dynamic]Table_Row_Kind, gtx.allocator)
	cs := ui.offer(gtx)
	t.width = ui.is_finite(cs.max.x) ? cs.max.x : 0
	tracks := make([]ui.Track, len(columns), gtx.allocator)
	for c, i in columns {
		tracks[i] = column_track(c)
	}
	t.rec = ui.record_open(gtx, {min = {t.width, 0}, max = {ui.INF, ui.INF}}, u64(ui.id_mix(t.id, 1)), loc)
	t.grid = ui.grid_open(gtx, tracks, align = .Center, paint = paint_table, user = t)
	ui.container_semantics(gtx, {role = .Table, label = ui.frame_string(gtx, label)})
	append(&t.rows, Table_Row_Kind.Header)
	for c, i in columns {
		if header_cell(gtx, t, c, i, sort) {
			sorted = true
		}
	}
	if loading {
		append(&t.rows, Table_Row_Kind.Skeleton)
		t.skeleton_rows = max(skeleton_rows, 1)
		for _, i in columns {
			skeleton_cell(gtx, t, i)
		}
	}
	return
}

// column_track is c's grid track.
@(private)
column_track :: proc(c: Column) -> ui.Track {
	tr := ui.Track {
		min   = c.min_width,
		max   = c.max_width,
		align = c.align == .End ? .End : .Start,
	}
	switch c.width {
	case .Grow:
		tr.grow = 1
	case .Grow_Collapse:
		tr.grow, tr.collapse = 1, true
	case .Auto:
	case .Fixed:
		tr.width = c.px
	}
	return tr
}

// cell_insets is the box of column i's cells around their content: the
// density's padding, 16px at the row's outer edges, and the 1px rule
// every cell has below it (a header cell above it too), which the paint
// draws in that space.
@(private)
cell_insets :: proc(t: ^Data_Table, i: int, header := false) -> ui.Padding {
	block, inline := cell_padding(t.padding)
	b := tok.BORDER_WIDTH_THIN
	p := ui.Padding{inline, block + (header ? b : 0), inline, block + b}
	if i == 0 {
		p.left = TABLE_EDGE_PADDING
	}
	if i == len(t.columns) - 1 {
		p.right = TABLE_EDGE_PADDING
	}
	return p
}

// header_cell is column i's header: its text, or for a sortable column a
// button of text and sort icon that toggles sort. It returns true when it
// changed sort.
@(private)
header_cell :: proc(gtx: ^ui.Ctx, t: ^Data_Table, c: Column, i: int, sort: ^Table_Sort) -> bool {
	in_ := ui.inset_open(gtx, cell_insets(t, i, header = true), key = u64(i))
	defer ui.close(&in_)
	st := TABLE_TEXT
	st.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	sorted_here := sort != nil && sort.column == i
	ink := color(sorted_here ? .Fg_Color_Default : .Fg_Color_Muted)
	if !c.sortable || sort == nil {
		layout_text(gtx, c.header, st, ink, .Text, key = u64(i))
		return false
	}
	p := ui.widget_open(gtx, u64(i))
	text := design.shape_style(gtx, c.header, st, font_for(gtx, st.weight))
	sz := ui.constrain_min(gtx.constraints, {text.width + SORT_ICON_GAP + BUTTON_ICON, max(text.height, BUTTON_ICON)})
	area := ops.Rect{0, 0, sz.x, sz.y}
	ctl := control(gtx, p.id, area, .Live)
	changed := false
	if ctl.clicked {
		if sorted_here {
			sort.direction = sort.direction == .Ascending ? .Descending : .Ascending
		} else {
			sort^ = {i, .Ascending}
		}
		sorted_here, changed = true, true
		ink = color(.Fg_Color_Default)
	}
	tx, ix: f32 = 0, text.width + SORT_ICON_GAP
	if c.align == .End {
		tx, ix = BUTTON_ICON + SORT_ICON_GAP, 0
	}
	draw_text(gtx, text, {tx, (sz.y - text.height) / 2}, ink)
	ic := Icon.None
	switch {
	case sorted_here:
		ic = sort.direction == .Ascending ? .Sort_Asc : .Sort_Desc
	case ctl.hovered || ctl.focused:
		ic = .Sort_Asc
	}
	if ic != .None {
		icon(gtx, ic, {ix, (sz.y - BUTTON_ICON) / 2}, BUTTON_ICON, ink)
	}
	paint_focus_outline(gtx, ctl, {area, tok.BORDER_RADIUS_SMALL})
	listen(gtx, ctl.st, p.id, area)
	said := ui.frame_string(gtx, c.header)
	ops.tag(gtx.scene, p.id, said)
	next := "Sort ascending"
	if sorted_here && sort.direction == .Ascending {
		next = "Sort descending"
	}
	ui.semantics(gtx, &p, {role = .Button, label = said, description = next})
	ui.widget_close(gtx, &p, {sz, (sz.y - text.height) / 2 + baseline_of(text)})
	return changed
}

// data_table_cell is the next cell: text in the column's alignment,
// semibold in a row-header column. Cells fill each row left to right.
data_table_cell :: proc(gtx: ^ui.Ctx, t: ^Data_Table, text: string) {
	data_table_cell_open(gtx, t)
	defer data_table_cell_close(t)
	c := t.columns[t.cell]
	st := TABLE_TEXT
	if c.row_header {
		st.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	}
	layout_text(gtx, text, st, color(.Fg_Color_Default), .Cell)
}

// data_table_cell_open starts the next cell for any content, padded as a
// cell, up to data_table_cell_close.
data_table_cell_open :: proc(gtx: ^ui.Ctx, t: ^Data_Table, loc := #caller_location) {
	if t.cell == 0 {
		append(&t.rows, Table_Row_Kind.Body)
	}
	t.open = ui.inset_open(gtx, cell_insets(t, t.cell), key = u64(len(t.rows) * 1024 + t.cell), loc = loc)
}

// data_table_cell_close ends the cell and moves to the next column.
data_table_cell_close :: proc(t: ^Data_Table) {
	ui.close(&t.open)
	t.cell = (t.cell + 1) % len(t.columns)
}

// data_table_group is a group heading: a row across every column on
// --bgColor-muted, its label semibold --fgColor-default then its row
// count in --fgColor-muted, 8px apart on a shared baseline
// (Table.module.css:291-319).
data_table_group :: proc(gtx: ^ui.Ctx, t: ^Data_Table, label: string, count: int, loc := #caller_location) {
	assert(t.cell == 0, "primer: a table group must start a row")
	append(&t.rows, Table_Row_Kind.Group)
	ui.grid_span(gtx)
	block, inline := cell_padding(t.padding)
	in_ := ui.inset_open(gtx, {TABLE_EDGE_PADDING, block, inline, block + tok.BORDER_WIDTH_THIN}, key = u64(len(t.rows)), loc = loc)
	defer ui.close(&in_)
	r := ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Baseline)
	defer ui.close(&r)
	st := TABLE_TEXT
	st.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	layout_text(gtx, label, st, color(.Fg_Color_Default), .Text)
	layout_text(gtx, fmt.aprintf("%d rows", count, allocator = gtx.allocator), TABLE_TEXT, color(.Fg_Color_Muted), .Text)
}

// SKELETON_WIDTHS are the skeleton bars' widths, cycling down a cell
// (Table.module.css:239-258).
@(rodata)
SKELETON_WIDTHS := [5]f32{0.85, 0.675, 0.8, 0.6, 0.75}

// skeleton_item_height is one skeleton item: a SkeletonText line, body
// medium (14px) tall with half its line's leading either side, padded as
// a cell, ruled below (SkeletonText.module.css:1-13).
@(private)
skeleton_item_height :: proc(t: ^Data_Table) -> f32 {
	block, _ := cell_padding(t.padding)
	return tok.TEXT_BODY_SIZE_MEDIUM * tok.TEXT_BODY_LINE_HEIGHT_MEDIUM + 2 * block + tok.BORDER_WIDTH_THIN
}

// skeleton_cell reserves a loading cell's height; the paint draws its
// bars, which are a share of the column's width.
@(private)
skeleton_cell :: proc(gtx: ^ui.Ctx, t: ^Data_Table, i: int) {
	p := ui.widget_open(gtx, u64(i))
	ui.semantics(gtx, &p, {role = .Cell, label = "Loading"})
	ui.widget_close(gtx, &p, {size = {0, f32(t.skeleton_rows) * skeleton_item_height(t)}})
}

// data_table_close closes the table: it scrolls it sideways when it is
// wider than its box.
data_table_close :: proc(t: ^Data_Table) {
	gtx := t.gtx
	ui.close(&t.grid)
	m, d := ui.record_close(&t.rec)
	if t.width <= 0 || d.size.x <= t.width + 0.5 {
		place_recording(gtx, m, d.size, {}, u64(ui.id_mix(t.id, 2)), t.loc)
		return
	}
	box := ui.sized_open(gtx, {min = {t.width, d.size.y}, max = {t.width, d.size.y}}, u64(ui.id_mix(t.id, 3)), t.loc)
	defer ui.close(&box)
	sb := ui.scroll_box_open(gtx, key = u64(ui.id_mix(t.id, 4)), wide = true)
	defer ui.close(&sb)
	place_recording(gtx, m, d.size, {})
}

// paint_table paints under the cells: the header's fill, hovered rows,
// skeleton bars, the group headers' fill and every rule, with the outer
// corners rounded.
@(private)
paint_table :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, g: ui.Grid_Lines, user: rawptr) {
	t := (^Data_Table)(user)
	w := g.size.x
	b := tok.BORDER_WIDTH_THIN
	last := len(g.row_h) - 1
	bottom_radius := t.footer ? 0 : TABLE_RADIUS
	ops.clip_push(gtx.scene, ops.Round_Rect{{0, 0, w, g.size.y}, TABLE_RADIUS})
	defer ops.clip_pop(gtx.scene)
	ops.fill(gtx.scene, ops.Rect{0, 0, w, g.size.y}, color(.Bg_Color_Default))
	if bottom_radius == 0 && last >= 0 {
		// Square the bottom corners for a footer: the clip rounds all four.
		ops.fill(gtx.scene, ops.Rect{0, g.size.y - TABLE_RADIUS, w, TABLE_RADIUS}, color(.Bg_Color_Default))
	}
	rule := color(.Border_Color_Default)
	for kind, r in t.rows {
		if r > last {
			break
		}
		row := ops.Rect{0, g.row_y[r], w, g.row_h[r]}
		switch kind {
		case .Header, .Group:
			ops.fill(gtx.scene, row, color(.Bg_Color_Muted))
		case .Body:
			if table_row_hovered(gtx, ui.id_mix(id, u64(r) + 1), row) {
				ops.fill(gtx.scene, row, color(.Control_Transparent_Bg_Color_Hover))
			}
		case .Skeleton:
			paint_skeleton(gtx, t, g, row)
		}
		ops.fill(gtx.scene, ops.Rect{0, row.y + row.h - b, w, b}, rule)
	}
	ops.fill(gtx.scene, ops.Rect{0, 0, w, b}, rule)
	stroke_inside(gtx, {{0, 0, w, g.size.y}, TABLE_RADIUS}, rule, b)
}

// table_row_hovered watches a body row with an observer area, so the row
// lights under its own controls too, and reports whether the pointer is
// over it.
@(private)
table_row_hovered :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, row: ops.Rect) -> bool {
	st := ui.widget_state(gtx, id)
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		}
	}
	ops.observer_area(gtx.scene, id, row)
	return st.hovered
}

// paint_skeleton draws the loading row's bars: per column, skeleton_rows
// items each holding a bar of the cycling width, ruled between.
@(private)
paint_skeleton :: proc(gtx: ^ui.Ctx, t: ^Data_Table, g: ui.Grid_Lines, row: ops.Rect) {
	block, _ := cell_padding(t.padding)
	item := skeleton_item_height(t)
	bar := tok.TEXT_BODY_SIZE_MEDIUM
	lead := (tok.TEXT_BODY_SIZE_MEDIUM * tok.TEXT_BODY_LINE_HEIGHT_MEDIUM - bar) / 2
	fill := color(.Skeleton_Loader_Bg_Color)
	for x, c in g.col_x {
		pad := cell_insets(t, c)
		inner := g.col_w[c] - pad.left - pad.right
		for k in 0 ..< t.skeleton_rows {
			y := row.y + f32(k) * item
			ops.fill(gtx.scene, ops.Round_Rect{{x + pad.left, y + block + lead, inner * SKELETON_WIDTHS[k % 5], bar}, tok.BORDER_RADIUS_SMALL}, fill)
			if k < t.skeleton_rows - 1 {
				ops.fill(gtx.scene, ops.Rect{x, y + item - tok.BORDER_WIDTH_THIN, g.col_w[c], tok.BORDER_WIDTH_THIN}, color(.Border_Color_Default))
			}
		}
	}
}

// compare_alphanumeric orders two strings as DataTable's alphanumeric
// sort does, digit runs by value and the rest by text, blank strings
// last (sorting.ts:34-135). Equal strings compare 0; the web returns -1,
// which data-table.json records as an upstream bug.
compare_alphanumeric :: proc(a, b: string) -> int {
	switch {
	case a == b:
		return 0
	case a == "":
		return 1
	case b == "":
		return -1
	}
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		da, db := is_digit(a[i]), is_digit(b[j])
		if da && db {
			ei, ej := digit_run(a, i), digit_run(b, j)
			na, _ := strconv.parse_u64(a[i:ei])
			nb, _ := strconv.parse_u64(b[j:ej])
			if na != nb {
				return na < nb ? -1 : 1
			}
			i, j = ei, ej
			continue
		}
		if a[i] != b[j] {
			return a[i] < b[j] ? -1 : 1
		}
		i += 1
		j += 1
	}
	switch {
	case len(a) - i < len(b) - j:
		return -1
	case len(a) - i > len(b) - j:
		return 1
	}
	return 0
}

@(private)
is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

@(private)
digit_run :: proc(s: string, from: int) -> int {
	e := from
	for e < len(s) && is_digit(s[e]) {
		e += 1
	}
	return e
}

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
