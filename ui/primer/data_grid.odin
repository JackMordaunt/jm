package primer

import "core:fmt"
import "core:strings"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/datagrid/export"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// DataTable on jm:ui/datagrid: the grid's model, virtualisation, keys and
// selection, dressed in Primer's DataTable look (data-table.json,
// Table.module.css) and given the admin dashboard's toolbar in Primer's
// components: a search field, saved views in an ActionMenu, a Clear
// filters button, and a Columns menu that exports, copies and arranges
// the columns; each filterable column's header holds a filter button
// opening a SelectPanel of the column's values with their counts, or for
// a Text or Range filter a panel of fields (data_grid_filters.odin).
//
//	g: primer.Data_Grid
//	primer.data_grid_init(&g, COLUMNS)
//	datagrid.memory_table_init(&table, COLUMNS, datagrid.rows_of(cells, 0))
//	ev := primer.data_grid(gtx, &g, COLUMNS, &table, "Rigs")
//	if ev.activated { open_rig(ev.row.key) }
//
// A caller draws its own cells (a Label, a Button that takes its own
// presses) by setting g.skin.cell and g.skin.cell_user once: the grid
// refills the rest of its skin every frame and leaves those alone.

// Data_Grid is a Primer data grid's state, the caller's to keep for the
// grid's life: the core grid (whose view a saved view is made of), the
// toolbar's search field, the open filter panel and menus, the saved
// views, the export running, and the CSV of the last one.
Data_Grid :: struct {
	grid:         datagrid.Grid,
	skin:         datagrid.Skin,
	search:       ui.Text_State,
	filter:       Filter_Panel,
	views_open:   bool,
	delete_open:  bool,
	columns_open: bool,
	naming:       bool,
	name:         ui.Text_State,
	views:        [dynamic]Saved_View,
	applied:      int, // the saved view last applied, -1 for none
	applied_view: u64, // the view's query when it was, to notice a change
	export:       export.Export,
	csv:          strings.Builder, // the last finished export
	notice:       string, // what the toolbar says last happened: "Copied 3 rows"
	cols:         []datagrid.Column, // this frame's, for the slots
	rows:         datagrid.Rows, // this frame's
	today:        Date, // what a date filter's presets count from; zero for date_today
}

// Saved_View is a named arrangement of the grid, as datagrid.view_encode
// wrote it: text that reads back against a later build's columns.
Saved_View :: struct {
	name: string,
	text: string,
}

// Filter_Panel is the column filter panel: which column's is open, its
// filter field, and the values it lists, as the panel draws them; or a
// Text or Range panel's fields.
@(private)
Filter_Panel :: struct {
	open:     bool,
	col:      int,
	seen:     bool, // the panel was drawn this frame
	text:     ui.Text_State, // a Set panel's filter field, a Text panel's Contains
	lo, hi:   ui.Text_State, // a number Range panel's Min and Max
	lo_err:   string, // what is wrong with Min, empty when nothing
	hi_err:   string,
	dates:    Date_Range, // a date Range panel's range
	values:   [dynamic]datagrid.Value_Count, // the column's values, every one
	built:    u64, // the query values was counted under, 0 for none
	shown:    [dynamic]int, // the values the filter text keeps, at most FILTER_SHOWN
	items:    [dynamic]Select_Panel_Item,
	selected: [dynamic]bool,
}

// FILTER_SHOWN is the most values a filter panel lists at once: the panel
// lays out every item, and a column of serial numbers has thousands.
FILTER_SHOWN :: 300

// data_grid_init readies g for columns.
data_grid_init :: proc(g: ^Data_Grid, columns: []datagrid.Column) {
	datagrid.grid_init(&g.grid, columns)
	g.filter.col = -1
	g.applied = -1
	g.views = make([dynamic]Saved_View)
	g.csv = strings.builder_make()
}

data_grid_destroy :: proc(g: ^Data_Grid) {
	datagrid.grid_destroy(&g.grid)
	delete(g.search.buf)
	delete(g.name.buf)
	f := &g.filter
	delete(f.text.buf)
	delete(f.lo.buf)
	delete(f.hi.buf)
	values_free(&f.values)
	delete(f.values)
	delete(f.shown)
	delete(f.items)
	delete(f.selected)
	for v in g.views {
		delete(v.name)
		delete(v.text)
	}
	delete(g.views)
	export.destroy(&g.export)
	strings.builder_destroy(&g.csv)
	delete(g.notice)
	g^ = {}
}

@(private)
values_free :: proc(values: ^[dynamic]datagrid.Value_Count) {
	for v in values {
		delete(v.value)
	}
	clear(values)
}

// data_grid is a Primer data grid of columns over the rows rows holds or
// asks for (datagrid.Rows), label naming
// it, filling the room it is offered: the toolbar (unless toolbar is
// false) over the grid. It returns what the grid did; a finished export's
// CSV is in g.csv.
data_grid :: proc(
	gtx: ^ui.Ctx,
	g: ^Data_Grid,
	columns: []datagrid.Column,
	rows: datagrid.Rows,
	label := "",
	toolbar := true,
	key: u64 = 0,
	loc := #caller_location,
) -> (
	ev: datagrid.Events,
) {
	g.cols, g.rows = columns, rows
	grid_skin(gtx, g)
	col := ui.column_open(gtx, gap = tok.BASE_SIZE_8, align = .Fill, key = key, loc = loc)
	defer ui.close(&col)
	if toolbar {
		grid_toolbar(gtx, g, label)
	}
	g.filter.seen = false
	ui.flexible(gtx, 1)
	ev = datagrid.grid(gtx, &g.grid, columns, rows, &g.skin, label)
	switch {
	case ev.filter_asked >= 0:
		filter_open(g, ev.filter_asked)
	case g.filter.open && !g.filter.seen:
		g.filter.open = false // its column scrolled away
	}
	exported := export.step(&g.export, gtx, columns, rows)
	grid_notices(g, ev, exported)
	return
}

// grid_notices keeps the CSV of an export that finished this frame and
// says in the toolbar what an export or a copy did.
@(private)
grid_notices :: proc(g: ^Data_Grid, ev: datagrid.Events, exported: bool) {
	if exported && g.export.error == "" {
		strings.builder_reset(&g.csv)
		strings.write_string(&g.csv, export.text(&g.export))
		w, _ := export.progress(&g.export)
		set_notice(g, fmt.tprintf("Exported %d rows", w))
	}
	if ev.copied > 0 {
		set_notice(g, fmt.tprintf("Copied %d cells", ev.copied))
	}
}

@(private)
set_notice :: proc(g: ^Data_Grid, s: string) {
	delete(g.notice)
	g.notice = strings.clone(s)
}

// grid_skin fills g's skin from the tokens for this frame: Primer's
// table type, the density's cell padding, and the theme's colours.
@(private)
grid_skin :: proc(gtx: ^ui.Ctx, g: ^Data_Grid) {
	s := &g.skin
	s.style = grid_style(gtx, g.grid.density)
	s.user = g
	s.header = grid_header
	s.empty = grid_empty
	s.failed = grid_failed
}

// grid_style is the grid's look at density d: 12px text on 20px lines,
// the header semibold --fgColor-muted on --bgColor-muted, every row ruled
// in --borderColor-default, a hovered row --control-transparent-bgColor-
// hover, a selected one --bgColor-accent-muted, rows the density's
// padding tall (Table.module.css:73-102).
grid_style :: proc(gtx: ^ui.Ctx, d: datagrid.Density) -> (st: datagrid.Style) {
	block, inline := cell_padding(d)
	line := TABLE_TEXT.line_height
	st.font = font_for(gtx, tok.BASE_TEXT_WEIGHT_NORMAL)
	st.header_font = font_for(gtx, tok.BASE_TEXT_WEIGHT_SEMIBOLD)
	st.text_size = TABLE_TEXT.size
	for density in datagrid.Density {
		b, _ := cell_padding(density)
		st.row_height[density] = line + 2 * b + tok.BORDER_WIDTH_THIN
	}
	st.header_height = line + 2 * block + 2 * tok.BORDER_WIDTH_THIN
	st.pad = inline
	st.header_extra = 2 * BUTTON_ICON + 2 * tok.BASE_SIZE_4
	st.radius = TABLE_RADIUS
	st.bg = color(.Bg_Color_Default)
	st.fg = color(.Fg_Color_Default)
	st.muted = color(.Fg_Color_Muted)
	st.header_bg = color(.Bg_Color_Muted)
	st.header_fg = color(.Fg_Color_Muted)
	st.border = color(.Border_Color_Default)
	st.rule = color(.Border_Color_Default)
	st.hover = color(.Control_Transparent_Bg_Color_Hover)
	st.selected = color(.Bg_Color_Accent_Muted)
	st.cursor = color(.Focus_Outline_Color)
	st.focus = color(.Focus_Outline_Color)
	st.skeleton = color(.Skeleton_Loader_Bg_Color)
	st.error_fg = color(.Fg_Color_Danger)
	st.pin_shadow = ops.with_alpha(color(.Border_Color_Default), 0.6)
	st.handle = color(.Border_Color_Accent_Emphasis)
	st.active = color(.Fg_Color_Accent)
	return
}

// cell_padding is a density's block and inline cell padding: 4/8px
// condensed, 8/12px normal, 12/16px spacious (Table.module.css:88-102).
@(private)
cell_padding :: proc(d: datagrid.Density) -> (block, inline: f32) {
	switch d {
	case .Condensed:
		return 4, 8
	case .Spacious:
		return 12, 16
	case .Normal:
	}
	return 8, 12
}

// TABLE_RADIUS is the table's outer corner radius, 0.375rem
// (Table.module.css:71): a literal in the CSS, which the token of the
// same size stands for.
TABLE_RADIUS :: tok.BORDER_RADIUS_MEDIUM

// TABLE_TEXT is the table's text: 12px on 20px lines
// (Table.module.css:73-80); a header or row header is semibold.
TABLE_TEXT :: tok.Type_Style {
	weight      = tok.BASE_TEXT_WEIGHT_NORMAL,
	size        = 12,
	line_height = 20,
}

// SORT_ICON_GAP is the gap between a header's text and its icons, 0.5rem
// (Table.module.css:268-270).
SORT_ICON_GAP :: tok.BASE_SIZE_8

// grid_header is the header slot: the title, semibold, in
// --fgColor-default while the column is sorted and --fgColor-muted
// otherwise, cut with an ellipsis to fit; the sort's octicon and its rank
// in a sort of several; and for a filterable column a filter button,
// counting the values chosen while it filters, opening the column's
// filter panel. The parts are placed from the right edge, measured, so
// the first frame lays them out as every later one does.
@(private)
grid_header :: proc(gtx: ^ui.Ctx, h: ^datagrid.Header, user: rawptr) {
	g := (^Data_Grid)(user)
	_, inline := cell_padding(g.grid.density)
	right := h.size.x - tok.BASE_SIZE_4
	if h.column.filter != .None {
		rec := ui.record_open(gtx, ui.loose(h.size), key = 1)
		filter_button(gtx, g, h)
		m, d := ui.record_close(&rec)
		right -= d.size.x
		ops.transform_push(gtx.scene, ops.translate(right, (h.size.y - d.size.y) / 2))
		ops.call(gtx.scene, m)
		ops.transform_pop(gtx.scene)
		right -= tok.BASE_SIZE_4
	}
	ink := color(.Fg_Color_Default if h.rank >= 0 else .Fg_Color_Muted)
	if h.rank >= 0 {
		right -= header_sort_mark(gtx, g, h, right, ink) + SORT_ICON_GAP
	}
	right = max(right, inline + tok.BASE_SIZE_4)
	box := ops.Rect{inline, 0, right - inline, h.size.y}
	font := font_for(gtx, tok.BASE_TEXT_WEIGHT_SEMIBOLD)
	datagrid.draw_text_line(
		gtx,
		&g.grid,
		font,
		TABLE_TEXT.size,
		h.column.title,
		box,
		h.column.align,
		ink,
	)
}

// header_sort_mark draws a sorted header's octicon, and its rank when the
// sort has several keys, ending at right; it returns their width.
@(private)
header_sort_mark :: proc(
	gtx: ^ui.Ctx,
	g: ^Data_Grid,
	h: ^datagrid.Header,
	right: f32,
	ink: ops.Color,
) -> f32 {
	w := BUTTON_ICON
	t: Text
	if len(g.grid.view.sort) > 1 {
		rank := fmt.aprintf("%d", h.rank + 1, allocator = gtx.allocator)
		t = shape_text(gtx, rank, .Caption)
		w += t.width + 1
	}
	y := (h.size.y - BUTTON_ICON) / 2
	icon(gtx, .Sort_Desc if h.desc else .Sort_Asc, {right - w, y}, BUTTON_ICON, ink)
	if t.width > 0 {
		draw_text(gtx, t, {right - t.width, (h.size.y - t.height) / 2}, ink)
	}
	return w
}

// filter_button is a header's filter button and, while open, its panel
// hanging from it. A Set filter's button counts the values chosen; a Text
// or Range filter's shows a dot on its icon while it filters.
@(private)
filter_button :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, h: ^datagrid.Header) {
	f := datagrid.find_filter(&g.grid.view, h.col)
	chosen := len(datagrid.chosen_values(f))
	dot := Unread_Dot.None
	if f != nil && datagrid.rule_kind(f.rule) != .Set && datagrid.filter_active(f^) {
		dot = .Leading
	}
	s := ui.stack_open(gtx, key = h.key)
	defer ui.close(&s)
	name := fmt.aprintf("Filter %s", h.column.title, allocator = gtx.allocator)
	variant := Button_Variant.Invisible
	// Not a Tab stop: the grid is one, and Alt+Down on a header opens
	// its panel from the keyboard.
	if chosen > 0 {
		count := fmt.aprintf("%d", chosen, allocator = gtx.allocator)
		if button(
			gtx,
			"",
			variant,
			.Small,
			leading = .Filter,
			count = count,
			name = name,
			tab_stop = false,
			key = 1,
		) {
			filter_toggle(g, h.col)
		}
	} else if icon_button(
		gtx,
		.Filter,
		name,
		variant,
		.Small,
		dot = dot,
		no_tooltip = true,
		tab_stop = false,
		key = 1,
	) {
		filter_toggle(g, h.col)
	}
	anchor := ui.last_widget(gtx)
	if g.filter.open && g.filter.col == h.col {
		g.filter.seen = true
		if h.column.filter == .Set {
			filter_panel(gtx, g, h.col, anchor)
		} else {
			range_panel(gtx, g, h.col, anchor)
		}
	}
}

@(private)
filter_toggle :: proc(g: ^Data_Grid, col: int) {
	if g.filter.open && g.filter.col == col {
		g.filter.open = false
		return
	}
	filter_open(g, col)
}

// filter_open opens column col's filter panel: a Set panel's field
// empty, a Text or Range panel's fields holding the filter as it stands.
@(private)
filter_open :: proc(g: ^Data_Grid, col: int) {
	if col < 0 || col >= len(g.cols) || g.cols[col].filter == .None {
		return
	}
	g.filter.open, g.filter.col, g.filter.built = true, col, 0
	panel_seed(g, col)
}

// filter_panel is column col's SelectPanel: its values with their counts
// under the other filters, the chosen ones checked, a Select all over
// those the field keeps; a change applies at once.
@(private)
filter_panel :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, col: int, anchor: ui.Last_Widget) {
	f := &g.filter
	loading := filter_values(gtx, g, col)
	filter_items(g, col)
	total := filter_matches(g)
	subtitle := ""
	if total > len(f.shown) {
		subtitle = fmt.aprintf(
			"Showing %d of %d values; type to narrow",
			len(f.shown),
			total,
			allocator = gtx.allocator,
		)
	}
	r := select_panel(
		gtx,
		&f.open,
		anchor,
		&f.text,
		f.items[:],
		f.selected[:],
		multiple = true,
		title = fmt.aprintf("Filter by %s", g.cols[col].title, allocator = gtx.allocator),
		subtitle = subtitle,
		placeholder = "Filter values",
		loading = loading,
		select_all = true,
		key = u64(ui.id_mix(ops.Area_Id(col), 0xf17e)),
	)
	if r.changed {
		filter_apply(g, col)
	}
}

// filter_values fills the panel's values for column col when the other
// filters or the rows changed since: counted from a table's rows, needed
// from a remote's host. It reports whether they are still on their way.
@(private)
filter_values :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, col: int) -> (loading: bool) {
	f := &g.filter
	values, version, on_way := datagrid.rows_values(gtx, &g.grid, g.cols, g.rows, col, f.built)
	if version != f.built {
		keep_values(f, values)
		f.built = version
	}
	return on_way
}

// keep_values makes the panel's values copies of values.
@(private)
keep_values :: proc(f: ^Filter_Panel, values: []datagrid.Value_Count) {
	values_free(&f.values)
	for x in values {
		append(&f.values, datagrid.Value_Count{strings.clone(x.value), x.count})
	}
}

// filter_matches is how many of the panel's values its field keeps.
@(private)
filter_matches :: proc(g: ^Data_Grid) -> int {
	like := ui.text_string(&g.filter.text)
	n := 0
	for v in g.filter.values {
		if datagrid.contains_fold(v.value, like) {
			n += 1
		}
	}
	return n
}

// filter_items lists the values the field keeps, up to FILTER_SHOWN, as
// panel items, each checked when the column's filter keeps it.
@(private)
filter_items :: proc(g: ^Data_Grid, col: int) {
	f := &g.filter
	like := ui.text_string(&f.text)
	cur := datagrid.find_filter(&g.grid.view, col)
	clear(&f.shown)
	clear(&f.items)
	clear(&f.selected)
	for v, i in f.values {
		if len(f.shown) >= FILTER_SHOWN {
			break
		}
		if !datagrid.contains_fold(v.value, like) {
			continue
		}
		append(&f.shown, i)
		text := v.value if v.value != "" else "(blank)"
		count := design.thousands(v.count)
		append(&f.items, Select_Panel_Item{text = text, description = count, group = -1})
		append(&f.selected, has_value(datagrid.chosen_values(cur), v.value))
	}
}

@(private)
has_value :: proc(values: []string, v: string) -> bool {
	for x in values {
		if x == v {
			return true
		}
	}
	return false
}

// filter_apply makes column col's filter what the panel's checks say: the
// values shown as checked, and those the field hides as they were.
@(private)
filter_apply :: proc(g: ^Data_Grid, col: int) {
	f := &g.filter
	keep := make([dynamic]string, context.temp_allocator)
	shown := make(map[string]bool, len(f.shown), context.temp_allocator)
	for i, k in f.shown {
		v := f.values[i].value
		shown[v] = true
		if f.selected[k] {
			append(&keep, v)
		}
	}
	for v in datagrid.chosen_values(datagrid.find_filter(&g.grid.view, col)) {
		if !shown[v] {
			append(&keep, v)
		}
	}
	datagrid.view_set_values(&g.grid.view, col, keep[:])
	g.applied = -1
}

// grid_empty is the empty slot: a grid with no rows says so in the
// middle, and when filters hid them, how to see them again.
@(private)
grid_empty :: proc(gtx: ^ui.Ctx, size: ops.Size, user: rawptr) {
	g := (^Data_Grid)(user)
	filtered := datagrid.view_filters_active(&g.grid.view)
	in_ := ui.inset_open(gtx, {tok.BASE_SIZE_16, tok.BASE_SIZE_32, tok.BASE_SIZE_16, 0})
	defer ui.close(&in_)
	c := ui.column_open(gtx, gap = tok.BASE_SIZE_4, align = .Center)
	defer ui.close(&c)
	title := "No rows match these filters" if filtered else "No rows"
	layout_text(gtx, title, style(.Body_Medium), color(.Fg_Color_Default), .Text)
	if filtered {
		layout_text(
			gtx,
			"Clear filters to see every row.",
			style(.Body_Small),
			color(.Fg_Color_Muted),
			.Text,
		)
	}
}

// grid_failed is the failed slot: an alert octicon and the error in
// --fgColor-danger, and that a click or Enter tries again.
@(private)
grid_failed :: proc(gtx: ^ui.Ctx, size: ops.Size, err: string, user: rawptr) -> bool {
	g := (^Data_Grid)(user)
	_, inline := cell_padding(g.grid.density)
	in_ := ui.inset_open(gtx, {inline, 0, inline, 0})
	defer ui.close(&in_)
	r := ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center)
	defer ui.close(&r)
	ink := color(.Fg_Color_Danger)
	p := ui.widget_open(gtx)
	icon(gtx, .Alert, {0, 0}, BUTTON_ICON, ink)
	ui.widget_close(gtx, &p, {size = {BUTTON_ICON, size.y}})
	msg := fmt.aprintf("Couldn't load these rows: %s", err, allocator = gtx.allocator)
	layout_text(gtx, msg, TABLE_TEXT, ink, .Text, tagged = false)
	layout_text(
		gtx,
		"Click or press Enter to retry",
		TABLE_TEXT,
		color(.Fg_Color_Muted),
		.Text,
		tagged = false,
	)
	return true
}

// grid_toolbar is the bar over the grid: at the start the search field,
// how many rows match and are selected, and what last happened; at the
// end, while an export runs, its progress and Cancel, Clear filters while
// a filter is on, and the Views and Columns menus. Naming a view to save
// puts its name field and Save and Cancel in the menus' place.
@(private)
grid_toolbar :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, label: string) {
	bar := ui.row_open(gtx, align = .Center, justify = .Space_Between)
	defer ui.close(&bar)
	{
		start := ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center)
		defer ui.close(&start)
		toolbar_search(gtx, g, label)
		datagrid.grid_sync(&g.grid, g.cols, g.rows, &g.skin)
		toolbar_counts(gtx, g)
	}
	end := ui.row_open(gtx, gap = tok.BASE_SIZE_8, align = .Center)
	defer ui.close(&end)
	if export.running(&g.export) {
		w, total := export.progress(&g.export)
		of := fmt.tprintf(" of %s", design.thousands(total)) if total >= 0 else ""
		progress := fmt.aprintf(
			"Exporting %s%s rows",
			design.thousands(w),
			of,
			allocator = gtx.allocator,
		)
		layout_text(gtx, progress, style(.Body_Small), color(.Fg_Color_Muted), .Status)
		if button(gtx, "Cancel", .Invisible, .Small, key = 1) {
			export.cancel(&g.export)
		}
	}
	if g.naming {
		toolbar_naming(gtx, g)
		return
	}
	if datagrid.view_filters_active(&g.grid.view) {
		if button(gtx, "Clear filters", .Default, .Small, leading = .Filter_Remove, key = 2) {
			datagrid.view_clear_filters(&g.grid.view)
			ui.text_set(&g.search, "")
			g.applied = -1
			g.filter.open = false
		}
	}
	views_menu(gtx, g)
	columns_menu(gtx, g)
}


// toolbar_search is the search field: what it holds is the grid's search,
// and a search set elsewhere (a view applied) shows in it.
@(private)
toolbar_search :: proc(gtx: ^ui.Ctx, g: ^Data_Grid, label: string) {
	if ui.text_string(&g.search) != g.grid.view.search {
		ui.text_set(&g.search, g.grid.view.search)
	}
	name := fmt.aprintf("Search %s", label if label != "" else "rows", allocator = gtx.allocator)
	e := text_input(
		gtx,
		&g.search,
		"Search…",
		.Small,
		leading = .Search,
		width = 240,
		name = name,
		key = 3,
	)
	if e.changed {
		datagrid.view_set_search(&g.grid.view, ui.text_string(&g.search))
		g.applied = -1
	}
}

// toolbar_counts says how many rows match, about how many while a
// remote's count is an estimate, Loading… before a remote query has any
// answer, and how many are selected; then the notice.
@(private)
toolbar_counts :: proc(gtx: ^ui.Ctx, g: ^Data_Grid) {
	n, kind, known := datagrid.rows_count(g.rows)
	if !known {
		// No page of this query yet: no number to give. Say it is coming,
		// or nothing when the first page failed (its rows say why).
		if datagrid.rows_loading(g.rows) {
			layout_text(
				gtx,
				"Loading…",
				style(.Body_Small),
				color(.Fg_Color_Muted),
				.Status,
				key = 4,
			)
		}
		return
	}
	about := kind != .Exact
	text := fmt.aprintf(
		"%s%s %s",
		"about " if about else "",
		design.thousands(n),
		"row" if n == 1 else "rows",
		allocator = gtx.allocator,
	)
	if !datagrid.selection_empty(&g.grid.sel) {
		picked := datagrid.selection_count(&g.grid.sel, n)
		text = fmt.aprintf(
			"%s · %s selected",
			text,
			design.thousands(picked),
			allocator = gtx.allocator,
		)
	}
	layout_text(gtx, text, style(.Body_Small), color(.Fg_Color_Muted), .Status, key = 4)
	if g.notice != "" {
		layout_text(gtx, g.notice, style(.Body_Small), color(.Fg_Color_Success), .Status, key = 5)
	}
}

// toolbar_naming is the field a saved view's name is typed in, with Save
// (Update when it names a view there is) and Cancel.
@(private)
toolbar_naming :: proc(gtx: ^ui.Ctx, g: ^Data_Grid) {
	e := text_input(gtx, &g.name, "View name", .Small, width = 200, name = "View name", key = 6)
	name := strings.trim_space(ui.text_string(&g.name))
	verb := "Update" if view_index(g, name) >= 0 else "Save"
	state := Interaction.Disabled if name == "" else .Live
	if (button(gtx, verb, .Primary, .Small, state = state, key = 7) || e.submitted) && name != "" {
		data_grid_save_view(g, name)
		g.naming = false
	}
	if button(gtx, "Cancel", .Invisible, .Small, key = 8) {
		g.naming = false
	}
}

// views_menu is the Views menu: the saved views, the last applied one
// checked, each applying itself; Save current view…; and a submenu that
// deletes one.
@(private)
views_menu :: proc(gtx: ^ui.Ctx, g: ^Data_Grid) {
	label := "Views"
	if g.applied >= 0 {
		label = fmt.aprintf("Views · %s", g.views[g.applied].name, allocator = gtx.allocator)
	}
	action_menu_button(gtx, label, &g.views_open, .Bookmark, size = .Small, key = 9)
	m := action_menu_open(gtx, &g.views_open, ui.last_widget(gtx), .Single, align = .End, key = 10)
	for v, i in g.views {
		if action_menu_item(&m, v.name, selected = i == g.applied) {
			data_grid_apply_view(g, i)
		}
	}
	if len(g.views) == 0 {
		action_menu_item(&m, "No saved views yet", state = .Disabled)
	}
	action_menu_divider(&m)
	if action_menu_item(&m, "Save current view…", leading = .Plus) {
		g.naming = true
		ui.text_set(&g.name, g.views[g.applied].name if g.applied >= 0 else "")
	}
	if len(g.views) > 0 {
		views_menu_delete(g, &m)
	}
	action_menu_close(&m)
}

// views_menu_delete is the Views menu's Delete view and its submenu of the
// saved views.
@(private)
views_menu_delete :: proc(g: ^Data_Grid, m: ^Action_Menu) {
	action_menu_item(m, "Delete view", leading = .Trash, submenu = &g.delete_open)
	sub := action_menu_submenu_open(m, &g.delete_open, key = 11)
	defer action_menu_close(&sub)
	for v, i in g.views {
		if action_menu_item(&sub, v.name, variant = .Danger) {
			data_grid_delete_view(g, i)
		}
	}
}

// columns_menu is the Columns menu, its button counting the columns shown
// while some are hidden: Download CSV and Copy CSV of the view; which
// columns show; which are pinned to the left; the density; and Reset
// columns.
@(private)
columns_menu :: proc(gtx: ^ui.Ctx, g: ^Data_Grid) {
	shown, hideable := 0, 0
	for c, i in g.cols {
		if !c.no_hide {
			hideable += 1
			shown += int(!g.grid.view.cols[i].hidden)
		}
	}
	count := ""
	if shown < hideable {
		count = fmt.aprintf("%d/%d", shown, hideable, allocator = gtx.allocator)
	}
	if button(
		gtx,
		"Columns",
		.Default,
		.Small,
		leading = .Columns,
		action = .Triangle_Down,
		count = count,
		expanded = g.columns_open,
		key = 12,
	) {
		g.columns_open = !g.columns_open
	}
	m := action_menu_open(gtx, &g.columns_open, ui.last_widget(gtx), align = .End, key = 13)
	if action_menu_item(&m, "Download CSV", leading = .Download) {
		export.start(&g.export, gtx, &g.grid, g.cols, g.rows)
	}
	if action_menu_item(&m, "Copy CSV", leading = .Copy) {
		copy_csv(gtx, g)
	}
	columns_menu_arrange(g, &m)
	action_menu_close(&m)
}

// columns_menu_arrange is the Columns menu's groups that arrange the
// grid: shown columns, pinned columns, density, reset.
@(private)
columns_menu_arrange :: proc(g: ^Data_Grid, m: ^Action_Menu) {
	v := &g.grid.view
	action_menu_group_open(m, "Show", selection = .Multiple)
	for c, i in g.cols {
		if !c.no_hide &&
		   action_menu_item(m, c.title, selected = !v.cols[i].hidden, keep_open = true) {
			v.cols[i].hidden = !v.cols[i].hidden
		}
	}
	action_menu_group_close(m)
	columns_menu_pins(g, m, .Left, "Pin to the left")
	columns_menu_pins(g, m, .Right, "Pin to the right")
	action_menu_group_open(m, "Density", selection = .Single)
	for name, d in DENSITY_NAMES {
		if action_menu_item(m, name, selected = g.grid.density == d) {
			g.grid.density = d
		}
	}
	action_menu_group_close(m)
	action_menu_divider(m)
	if action_menu_item(m, "Reset columns", leading = .Sync) {
		datagrid.view_reset_columns(v, g.cols)
	}
}

// columns_menu_pins is the Columns menu's group that pins shown columns
// to side or unpins them: one for the left, one for the right.
@(private)
columns_menu_pins :: proc(g: ^Data_Grid, m: ^Action_Menu, side: datagrid.Pin, heading: string) {
	v := &g.grid.view
	action_menu_group_open(m, heading, selection = .Multiple)
	defer action_menu_group_close(m)
	for c, i in g.cols {
		on := v.cols[i].pin == side
		if !v.cols[i].hidden && action_menu_item(m, c.title, selected = on, keep_open = true) {
			v.cols[i].pin = .None if on else side
		}
	}
}

// DENSITY_NAMES are the densities as the Columns menu names them.
DENSITY_NAMES :: [datagrid.Density]string {
	.Condensed = "Condensed",
	.Normal    = "Normal",
	.Spacious  = "Spacious",
}

// copy_csv puts a table's view on the clipboard as CSV. A remote's rows
// are not in hand: its CSV is downloaded, streamed by pages.
@(private)
copy_csv :: proc(gtx: ^ui.Ctx, g: ^Data_Grid) {
	x: export.Export
	defer export.destroy(&x)
	if !export.write_all(&x, gtx, &g.grid, g.cols, g.rows) {
		set_notice(g, "A paged table's CSV streams: Download CSV, then copy it")
		return
	}
	ui.clipboard_write(gtx, export.text(&x))
	w, _ := export.progress(&x)
	set_notice(g, fmt.tprintf("Copied %d rows as CSV", w))
}

// view_index is the saved view named name, -1 for none.
@(private)
view_index :: proc(g: ^Data_Grid, name: string) -> int {
	for v, i in g.views {
		if v.name == name {
			return i
		}
	}
	return -1
}

// data_grid_save_view saves the grid's view as name, replacing a saved
// view of that name, the views kept in name order, and marks it applied.
data_grid_save_view :: proc(g: ^Data_Grid, name: string) {
	b := strings.builder_make(context.temp_allocator)
	datagrid.view_encode(&b, &g.grid.view, g.cols, name)
	data_grid_load_view(g, name, strings.to_string(b))
	g.applied = view_index(g, name)
	set_notice(g, fmt.tprintf("Saved view %q", name))
}

// data_grid_load_view adds a view saved before, as text view_encode
// wrote, under name, replacing one of that name: what a caller that
// persists g.views reads back.
data_grid_load_view :: proc(g: ^Data_Grid, name, text: string) {
	if i := view_index(g, name); i >= 0 {
		delete(g.views[i].text)
		g.views[i].text = strings.clone(text)
		return
	}
	at := len(g.views)
	for v, i in g.views {
		if datagrid.compare_natural(name, v.name) < 0 {
			at = i
			break
		}
	}
	inject_at(&g.views, at, Saved_View{strings.clone(name), strings.clone(text)})
	if g.applied >= at {
		g.applied += 1
	}
}

// data_grid_apply_view makes saved view i the grid's view, read against
// the columns the grid has now.
data_grid_apply_view :: proc(g: ^Data_Grid, i: int) {
	if i < 0 || i >= len(g.views) {
		return
	}
	datagrid.view_decode(&g.grid.view, g.cols, g.views[i].text, context.temp_allocator)
	g.applied = i
}

// data_grid_delete_view forgets saved view i.
data_grid_delete_view :: proc(g: ^Data_Grid, i: int) {
	if i < 0 || i >= len(g.views) {
		return
	}
	delete(g.views[i].name)
	delete(g.views[i].text)
	ordered_remove(&g.views, i)
	switch {
	case g.applied == i:
		g.applied = -1
	case g.applied > i:
		g.applied -= 1
	}
}
