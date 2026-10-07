package fluent

import "core:slice"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/ops"

// Behaviour of the data display components, driven through ui.Probe.

@(private = "file")
Data_Model :: struct {
	sort:      Sort_Direction,
	sorts:     int,
	rows:      [3]bool,
	row_hits:  int,
	single:    int,
	multi:     [3]bool,
	dismissed: int,
	primary:   int,
	removed:   int,
	group:     bool,
}

@(private = "file")
COLUMNS := [?]f32{160, 0}

@(private = "file")
NAMES := [?]string{"Katri Ahokas", "Elvia Atkins", "Cameron Evans", "Wanda Howard", "Mona Kane", "Allan Munger", "Erik Nason"}

@(private = "file")
data_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Data_Model)(user)
	col := ui.column_open(gtx, gap = 12)
	defer ui.close(&col)
	if table(gtx, COLUMNS[:]) {
		t := current_table()
		if table_header(gtx, t) {
			if table_header_cell(gtx, current_row(), "Name", &m.sort) {
				m.sorts += 1
			}
			table_header_cell(gtx, current_row(), "Modified")
		}
		ROWS := [3]string{"Report", "Plan", "Notes"}
		for name, i in ROWS {
			clicked: bool
			if table_row(gtx, t, &m.rows[i], &clicked, name = name, key = u64(i)) {
				table_cell_layout(gtx, current_row(), name, "Doc", {icon = .Document})
				table_cell(gtx, current_row(), "Today")
			}
			if clicked {
				m.row_hits += 1
			}
		}
	}
	if list(gtx, .Single, &m.single) {
		l := current_list()
		list_item(gtx, l, "Alpha")
		list_item(gtx, l, "Beta", key = 1)
	}
	lm := list_open(gtx, .Multi)
	for label, i in ([3]string{"Red", "Green", "Blue"}) {
		list_item(gtx, &lm, label, &m.multi[i], key = u64(i))
	}
	list_close(&lm)
	if tag(gtx, "Removable", dismissible = true) {
		m.dismissed += 1
	}
	tag(gtx, "Static", .Outline, key = 1)
	if c, d := interaction_tag(gtx, "Pick", .Brand); c {
		m.primary += 1
	} else if d {
		m.removed += 1
	}
	avatar_group(gtx, NAMES[:], max_inline = 3, open = &m.group)
	skeleton_item(gtx, 20, .Rectangle, width = 120)
	text_preset(gtx, "Heading", .Title3, {0, 0, 0, 255})
}

@(test)
test_table_sorts_and_selects_rows :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Name"))
	testing.expect_value(t, m.sort, Sort_Direction.Ascending)
	testing.expect(t, ui.probe_click(&p, "Name"))
	testing.expect_value(t, m.sort, Sort_Direction.Descending)
	testing.expect_value(t, m.sorts, 2)
	// "Modified" has no sort: it registers no input area.
	testing.expect(t, !ui.probe_click(&p, "Modified"))

	// A row is 44px at medium; the header's sortable cell at least 32.
	header := ui.probe_bounds(&p, "Name")
	testing.expect_value(t, header.h, 44)
	testing.expect_value(t, header.w, 160)
	// A row is tagged by its name on its own input area.
	testing.expect(t, ui.probe_click(&p, "Plan"))
	testing.expect(t, m.rows[1])
	testing.expect(t, !m.rows[0])
	testing.expect_value(t, m.row_hits, 1)
	testing.expect(t, ui.probe_click(&p, "Plan"))
	testing.expect(t, !m.rows[1])
}

@(test)
test_list_selects_one_or_many :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Beta"))
	testing.expect_value(t, m.single, 1)
	testing.expect(t, ui.probe_click(&p, "Alpha"))
	testing.expect_value(t, m.single, 0)
	testing.expect(t, ui.probe_click(&p, "Green"))
	testing.expect(t, ui.probe_click(&p, "Blue"))
	testing.expect(t, !m.multi[0] && m.multi[1] && m.multi[2])
	testing.expect(t, ui.probe_click(&p, "Green"))
	testing.expect(t, !m.multi[1])
	testing.expect_value(t, ui.probe_bounds(&p, "Alpha").h, LIST_ITEM_HEIGHT)
}

@(test)
test_tags_dismiss_and_act :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Removable"))
	testing.expect_value(t, m.dismissed, 1)
	// Focused by the click, Delete dismisses it too.
	ui.probe_key(&p, .Delete)
	testing.expect_value(t, m.dismissed, 2)
	// A static tag takes no input.
	testing.expect(t, !ui.probe_click(&p, "Static"))
	// A medium tag is 32px tall.
	testing.expect_value(t, ui.probe_bounds(&p, "Removable").h, 32)
	// An interaction tag's halves act apart.
	testing.expect(t, ui.probe_click(&p, "Pick"))
	testing.expect_value(t, m.primary, 1)
	testing.expect(t, ui.probe_click(&p, "dismiss"))
	testing.expect_value(t, m.removed, 1)
	testing.expect_value(t, m.primary, 1)
}

@(test)
test_avatar_group_overflows_past_its_max :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Seven names, three inline: the button counts the other four.
	b := ui.probe_bounds(&p, "+4")
	testing.expect_value(t, b.w, 32)
	testing.expect_value(t, b.h, 32)
	testing.expect(t, !slice.contains(ui.probe_names(&p), "Mona Kane"))
	testing.expect(t, ui.probe_click(&p, "+4"))
	testing.expect(t, m.group)
	// Open, the popover lists the overflow by name.
	testing.expect(t, slice.contains(ui.probe_names(&p), "Mona Kane"))
	testing.expect(t, !slice.contains(ui.probe_names(&p), "Katri Ahokas"))
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.group)
}

@(test)
test_skeleton_and_text_size_and_animate :: proc(t: ^testing.T) {
	m: Data_Model
	p: ui.Probe
	ui.probe_init(&p, data_view, &m, {600, 1200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	names := ui.probe_names(&p)
	testing.expect(t, slice.contains(names, "skeleton"))
	testing.expect(t, slice.contains(names, "Heading"))
	// The skeleton's wave never settles.
	testing.expect(t, p.wants_frame)
	testing.expect_value(t, text_style(.S300, .Regular), style(.Body1))
	testing.expect_value(t, text_style(.S500, .Semibold), style(.Subtitle1))
	testing.expect_value(t, tag_group_gap(.Small), f32(6))
}

@(private = "file")
Hug_Model :: struct {
	in_row, in_column: ui.Dims,
	wrapped:           ui.Dims,
	short:             f32, // "Short" shaped on one line
}

@(private = "file")
hug_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Hug_Model)(user)
	m.short = shape_style(gtx, "Short", text_style(.S300, .Regular)).width
	col := ui.column_open(gtx, align = .Fill)
	defer ui.close(&col)
	if ui.row(gtx) {
		m.in_row = text(gtx, "Short", {0, 0, 0, 255}, block = true)
	}
	m.in_column = text(gtx, "Filled", {0, 0, 0, 255}, block = true)
	if ui.row(gtx) {
		m.wrapped = text(gtx, "long enough to wrap onto more than one line", {0, 0, 0, 255}, block = true, key = 1)
	}
}

@(test)
test_block_text_hugs_in_a_row_and_fills_a_fill_column :: proc(t: ^testing.T) {
	m: Hug_Model
	p: ui.Probe
	ui.probe_init(&p, hug_view, &m, {200, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	short := m.short
	testing.expect(t, m.in_row.size.x > 0)
	testing.expect_value(t, m.in_row.size.x, short)
	testing.expect_value(t, m.in_column.size.x, 200)
	// Wrapped, it is its widest line, no wider than the row offered.
	testing.expect(t, m.wrapped.size.y > text_style(.S300, .Regular).line_height)
	testing.expect(t, m.wrapped.size.x <= 200)
	testing.expect(t, m.wrapped.size.x > short)
}

@(test)
test_truncated_text_fits_its_box_and_copies_whole :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx)
		defer ui.close(&col)
		text(gtx, "a sentence far too long for its box", color(.Neutral_Foreground1), block = true, width = 80, wrap_lines = false, truncate = true)
	}
	p: ui.Probe
	ui.probe_init(&p, view, nil, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	b := ui.probe_bounds(&p, "a sentence far too long for its box")
	testing.expect_value(t, b.w, 80)
	// What is drawn is a short run and the ellipsis, not the sentence.
	drawn := 0
	for r in ui.probe_current(&p).scene.runs {
		drawn += len(r.glyphs)
	}
	testing.expect(t, drawn > 1 && drawn < 15, "the line is cut")
	y := b.y + b.h / 2
	ui.router_push(&p.router, {kind = .Press, pos = {b.x + 1, y}, clicks = 1})
	ui.router_push(&p.router, {kind = .Move, pos = {b.x + b.w - 1, y}})
	ui.router_push(&p.router, {kind = .Release, pos = {b.x + b.w - 1, y}, clicks = 1})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect_value(t, ui.label_selection(&ctx), "a sentence far too long for its box")
}

// A right press on a row asks for its context menu, at a point in the
// row's own coordinates; a left press does not.
@(test)
test_table_row_reports_a_context_press :: proc(t: ^testing.T) {
	Rows :: struct {
		asked: bool,
		at:    ops.Point,
	}
	r: Rows
	p: ui.Probe
	ui.probe_init(&p, proc(gtx: ^ui.Ctx, user: rawptr) {
			r := (^Rows)(user)
			tbl := table_open(gtx, {0, 100})
			defer table_close(&tbl)
			ui.spacer(gtx, 40) // the row is not at the table's origin
			row := table_row_open(gtx, &tbl, name = "row", context_clicked = &r.asked, context_at = &r.at)
			table_cell(gtx, &row, "notes.txt")
			table_cell(gtx, &row, "1 KB")
			table_row_close(&row)
		}, &r, {600, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "row"))
	testing.expect(t, !r.asked, "a left click is no context press")
	// It holds on the frame of the press, as double_clicked does.
	b := ui.probe_bounds(&p, "row")
	c, _ := ui.probe_center(&p, "row")
	ui.router_push(&p.router, {kind = .Press, pos = c, button = .Right})
	ui.probe_frame(&p)
	testing.expect(t, r.asked, "a right press is")
	ui.router_push(&p.router, {kind = .Release, pos = c, button = .Right})
	ui.probe_frame(&p)
	testing.expect(t, !r.asked, "and only on its frame")
	testing.expect(t, abs(r.at.x - b.w / 2) < 1 && abs(r.at.y - b.h / 2) < 1, "at the press, in the row's own coordinates")
}

@(private = "file")
Grid_Model :: struct {
	g:     datagrid.Grid,
	keyed: []datagrid.Page_Row,
	table: datagrid.Memory_Table,
}

@(private = "file")
GRID_COLUMNS := []datagrid.Column{{id = "name", title = "Name"}, {id = "size", title = "Size", kind = .Number}}

@(private = "file")
GRID_ROWS := [][2]string{{"notes.txt", "3"}, {"plan.md", "12"}, {"budget.xlsx", "7"}}

@(private = "file")
grid_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Grid_Model)(user)
	skin := data_grid_skin(gtx, &m.g)
	datagrid.grid(gtx, &m.g, GRID_COLUMNS, &m.table, &skin, "Files")
}

// The data grid's skin: Table's 44px rows ruled in Stroke 2, and a sorted
// header's arrow in Foreground 1.
@(test)
test_a_data_grid_wears_the_table_s_look :: proc(t: ^testing.T) {
	m: Grid_Model
	m.keyed = datagrid.rows_of(GRID_ROWS, 0)
	defer delete(m.keyed)
	datagrid.memory_table_init(&m.table, GRID_COLUMNS, m.keyed)
	defer datagrid.memory_table_destroy(&m.table)
	datagrid.grid_init(&m.g, GRID_COLUMNS)
	defer datagrid.grid_destroy(&m.g)
	p: ui.Probe
	ui.probe_init(&p, grid_view, &m, {400, 300})
	defer ui.probe_destroy(&p)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `row 3 at 0,88 400x44`), said)
	testing.expect_value(t, datagrid.item_at(&m.g, &m.table, 1).row, 1)
	testing.expect(t, ui.probe_click(&p, "Size"))
	// 3, 7, 12: budget.xlsx's 7 moves up to second.
	testing.expect_value(t, datagrid.item_at(&m.g, &m.table, 1).row, 2)
	arrows := 0
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if c, solid := f.paint.(ops.Color); solid && c == color(.Neutral_Foreground1) {
				if _, is_path := f.shape.(ops.Path_Ref); is_path {
					arrows += 1
				}
			}
		}
	}
	testing.expect(t, arrows > 0, "the sort's arrow")
	free_all(context.temp_allocator)
}
