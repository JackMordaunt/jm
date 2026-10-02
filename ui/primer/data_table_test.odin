package primer

import "core:slice"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of DataTable and its pagination through ui.Probe by tags.

@(private = "file")
Table_Model :: struct {
	sort:      Table_Sort,
	sorts:     int,
	padding:   Cell_Padding,
	loading:   bool,
	empty:     bool,
	page:      int,
	pages:     int,
}

@(private = "file")
NAMES := [?]string{"Ada", "Grace Hopper", "Linus"}
@(private = "file")
ROLES := [?]string{"Engineer", "Admiral", "Kernel"}

@(private = "file")
table_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Table_Model)(user)
	col := ui.column_open(gtx, align = .Fill)
	defer ui.close(&col)
	columns := []Column{{header = "Name", width = .Auto, row_header = true, sortable = true}, {header = "Role", sortable = true}, {header = "Count", align = .End, width = .Auto}}
	t, sorted := data_table_open(gtx, columns, &m.sort, m.padding, loading = m.loading, skeleton_rows = 3, footer = true, label = "People")
	if sorted {
		m.sorts += 1
	}
	if !m.loading && !m.empty {
		for n, i in NAMES {
			data_table_cell(gtx, t, n)
			data_table_cell(gtx, t, ROLES[i])
			data_table_cell(gtx, t, i == 0 ? "1" : "100")
		}
	}
	data_table_close(t)
	if data_table_pagination(gtx, "People pages", &m.page, 200, 10) {
		m.pages += 1
	}
}

@(private = "file")
text_width :: proc(p: ^ui.Probe, s: string, st: tok.Type_Style) -> f32 {
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	return design.shape_style(&gtx, s, st, font_for(&gtx, st.weight)).width
}

@(test)
test_data_table_sizes_columns_from_their_widest_cell :: proc(t: ^testing.T) {
	m := Table_Model{sort = {-1, .Ascending}}
	p: ui.Probe
	ui.probe_init(&p, table_view, &m, {700, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	semi := TABLE_TEXT
	semi.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	// Column 0 is auto: its widest cell, the row-header "Grace Hopper",
	// plus 16px at the edge and 12px inside.
	name_w := max(text_width(&p, "Grace Hopper", semi), text_width(&p, "Name", semi) + SORT_ICON_GAP + BUTTON_ICON)
	role := ui.probe_bounds(&p, "Role")
	engineer := ui.probe_bounds(&p, "Engineer")
	testing.expect(t, abs(role.x - (16 + name_w + 12 + 12)) < 0.01)
	testing.expect_value(t, engineer.x, role.x) // every cell in a column shares its x
	// The end-aligned auto column ends 16px from the table's edge.
	hundred := ui.probe_bounds(&p, "100")
	one := ui.probe_bounds(&p, "1")
	testing.expect(t, abs(hundred.x + hundred.w - (700 - 16)) < 0.01)
	testing.expect(t, abs(one.x + one.w - (700 - 16)) < 0.01)
	// Normal density: the header row is its 1px top rule, 8px, a 20px
	// line, 8px and its 1px bottom rule; the first body text sits 8px in.
	ada := ui.probe_bounds(&p, "Ada")
	testing.expect_value(t, ada.y, 38 + 8)
	testing.expect_value(t, ada.x, TABLE_EDGE_PADDING)
	testing.expect_value(t, ui.probe_bounds(&p, "Linus").y, 38 + 2 * 37 + 8)
}

@(test)
test_data_table_condensed_and_spacious_pad_their_cells :: proc(t: ^testing.T) {
	for c in ([?]struct {
			padding:       Cell_Padding,
			block, inline: f32,
		}{{.Condensed, 4, 8}, {.Spacious, 12, 16}}) {
		m := Table_Model{sort = {-1, .Ascending}, padding = c.padding}
		p: ui.Probe
		ui.probe_init(&p, table_view, &m, {700, 600}, allocator = context.temp_allocator)
		header := 1 + 2 * c.block + 20 + 1
		testing.expect_value(t, ui.probe_bounds(&p, "Ada").y, header + c.block)
		testing.expect_value(t, ui.probe_bounds(&p, "Ada").x, TABLE_EDGE_PADDING) // 16px whatever the density
		ui.probe_destroy(&p)
	}
	free_all(context.temp_allocator)
}

@(test)
test_a_sortable_header_sorts_ascending_then_flips :: proc(t: ^testing.T) {
	m := Table_Model{sort = {-1, .Ascending}}
	p: ui.Probe
	ui.probe_init(&p, table_view, &m, {700, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Role"))
	testing.expect_value(t, m.sort, Table_Sort{1, .Ascending})
	testing.expect_value(t, m.sorts, 1)
	ui.probe_key(&p, .Enter) // keyboard activation flips it
	testing.expect_value(t, m.sort, Table_Sort{1, .Descending})
	testing.expect(t, ui.probe_click(&p, "Name"))
	testing.expect_value(t, m.sort, Table_Sort{0, .Ascending})
	testing.expect(t, ui.probe_click(&p, "Count")) // not sortable: its text is no button
	testing.expect_value(t, m.sorts, 3)
	// The sorted header shows its icon in --fgColor-default.
	ui.probe_frame(&p)
	testing.expect(t, icon_drawn(&p, .Sort_Asc, color(.Fg_Color_Default)))
}

@(private = "file")
icon_drawn :: proc(p: ^ui.Probe, i: Icon, c: ops.Color) -> bool {
	path, _ := icon_path(i, BUTTON_ICON)
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if pr, is_path := f.shape.(ops.Path_Ref); is_path {
				got := p.scene.paths[pr.id]
				col, solid := f.paint.(ops.Color)
				if solid && col == c && slice.equal(got.verbs, path.verbs) {
					return true
				}
			}
		}
	}
	return false
}

@(test)
test_an_empty_table_is_its_header_and_a_loading_one_draws_skeleton_bars :: proc(t: ^testing.T) {
	m := Table_Model{sort = {-1, .Ascending}, empty = true}
	p: ui.Probe
	ui.probe_init(&p, table_view, &m, {700, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// The pagination bar starts right under the 38px header row.
	testing.expect_value(t, ui.probe_bounds(&p, "Previous page").y, 38 + 8)

	m.empty, m.loading = false, true
	ui.probe_frame(&p)
	bars := 0
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if c, solid := f.paint.(ops.Color); solid && c == color(.Skeleton_Loader_Bg_Color) {
				bars += 1
			}
		}
	}
	testing.expect_value(t, bars, 3 * 3) // three items in each of three columns
	testing.expect_value(t, ui.probe_bounds(&p, "Ada"), ops.Rect{})
}

// A hovered body row fills with the transparent control hover, whatever
// control in it the pointer is over.
@(test)
test_a_hovered_row_lights :: proc(t: ^testing.T) {
	m := Table_Model{sort = {-1, .Ascending}}
	p: ui.Probe
	ui.probe_init(&p, table_view, &m, {700, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	lit :: proc(p: ^ui.Probe) -> int {
		n := 0
		for op in p.scene.ops {
			if f, ok := op.(ops.Fill); ok {
				if c, solid := f.paint.(ops.Color); solid && c == color(.Control_Transparent_Bg_Color_Hover) {
					n += 1
				}
			}
		}
		return n
	}
	base := lit(&p)
	c, _ := ui.probe_center(&p, "Engineer")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_frame(&p)
	testing.expect_value(t, lit(&p), base + 1)
}

// A table wider than its box keeps its columns and scrolls sideways.
@(test)
test_a_wide_table_scrolls_rather_than_squeezes :: proc(t: ^testing.T) {
	m := Table_Model{sort = {-1, .Ascending}}
	p: ui.Probe
	ui.probe_init(&p, table_view, &m, {200, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	hundred := ui.probe_bounds(&p, "100")
	testing.expect(t, hundred.x > 200)
	c, _ := ui.probe_center(&p, "Ada")
	ui.router_push(&p.router, {kind = .Scroll, pos = c, scroll = {1e6, 0}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	moved := ui.probe_bounds(&p, "100")
	testing.expect(t, abs(moved.x + moved.w - (200 - 16)) < 0.01) // scrolled to its end
}

@(test)
test_compare_alphanumeric_orders_digit_runs_by_value :: proc(t: ^testing.T) {
	testing.expect_value(t, compare_alphanumeric("item2", "item10"), -1)
	testing.expect_value(t, compare_alphanumeric("item10", "item2"), 1)
	testing.expect_value(t, compare_alphanumeric("b", "a"), 1)
	testing.expect_value(t, compare_alphanumeric("same", "same"), 0) // the web says -1
	testing.expect_value(t, compare_alphanumeric("", "a"), 1) // blanks last
	testing.expect_value(t, compare_alphanumeric("a", ""), -1)
	testing.expect_value(t, compare_alphanumeric("v1", "v1.2"), -1)
}

@(test)
test_pagination_shows_ends_and_two_either_side :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	got := page_numbers(9, 20, context.temp_allocator)
	testing.expect(t, slice.equal(got, []int{0, -1, 7, 8, 9, 10, 11, -2, 19}))
	got = page_numbers(0, 3, context.temp_allocator)
	testing.expect(t, slice.equal(got, []int{0, 1, 2}))

	m := Table_Model{sort = {-1, .Ascending}}
	p: ui.Probe
	ui.probe_init(&p, table_view, &m, {900, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_click(&p, "Previous page") // disabled on the first page
	testing.expect_value(t, m.page, 0)
	testing.expect(t, ui.probe_click(&p, "Next page"))
	testing.expect_value(t, m.page, 1)
	testing.expect(t, ui.probe_click(&p, "Page 20"))
	testing.expect_value(t, m.page, 19)
	ui.probe_click(&p, "Next page") // disabled on the last
	testing.expect_value(t, m.page, 19)
	testing.expect_value(t, m.pages, 2)
	testing.expect(t, ui.probe_tagged(&p, "Page 1"))
	testing.expect(t, !ui.probe_tagged(&p, "Page 10")) // truncated
}


@(test)
test_a_group_shows_its_count_and_speaks_row_or_rows :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		columns := []Column{{header = "Name"}}
		sort := Table_Sort{-1, .Ascending}
		tb, _ := data_table_open(gtx, columns, &sort, .Normal, label = "Groups")
		data_table_group(gtx, tb, "Solo", 1)
		data_table_cell(gtx, tb, "Ada")
		data_table_group(gtx, tb, "Pair", 2)
		data_table_cell(gtx, tb, "Grace")
		data_table_cell(gtx, tb, "Linus")
		data_table_close(tb)
	}
	p: ui.Probe
	ui.probe_init(&p, view, nil, {400, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "\"1 row\""), "one row is singular: %s", said)
	testing.expectf(t, strings.contains(said, "\"2 rows\""), "two are plural: %s", said)
	testing.expect(t, ui.probe_tagged(&p, "1"), "the count shows as a bare number")
	testing.expect(t, !ui.probe_tagged(&p, "1 rows"))
}
