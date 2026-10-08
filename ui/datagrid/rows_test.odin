package datagrid

import "core:testing"
import "jm:ui"

// Rows: a table refuses rows it cannot key, and a Set filter's values
// come the same way from a table, counted now, and from a remote, asked
// for and delivered.

@(private = "file")
VALUE_COLS := []Column {
	{id = "serial", title = "Serial"},
	{id = "site", title = "Site", filter = .Set},
}

@(private = "file")
VALUE_CELLS := [][2]string{{"SN-1", "Norway"}, {"SN-2", "Paraguay"}, {"SN-3", "Norway"}}

@(test)
test_a_table_row_without_a_key_fails_at_once :: proc(t: ^testing.T) {
	testing.expect_assert_message(t, "Memory_Table: row 1 has no key; give every row a unique key")
	rows := []Page_Row{{"a", nil}, {"", nil}}
	tb: Memory_Table
	memory_table_init(&tb, VALUE_COLS, rows)
}

@(private = "file")
Values_Model :: struct {
	g:       Grid,
	src:     Rows,
	since:   u64,
	values:  []Value_Count,
	version: u64,
	loading: bool,
}

@(private = "file")
values_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Values_Model)(user)
	m.values, m.version, m.loading = rows_values(gtx, &m.g, VALUE_COLS, m.src, 1, m.since)
}

@(test)
test_a_table_counts_its_values_now_and_says_when_they_change :: proc(t: ^testing.T) {
	rows := rows_of(VALUE_CELLS, 0)
	defer delete(rows)
	tb: Memory_Table
	memory_table_init(&tb, VALUE_COLS, rows)
	defer memory_table_destroy(&tb)
	m := Values_Model {
		src = &tb,
	}
	grid_init(&m.g, VALUE_COLS)
	defer grid_destroy(&m.g)
	p: ui.Probe
	ui.probe_init(&p, values_view, &m, {400, 300})
	defer ui.probe_destroy(&p)

	testing.expect(t, !m.loading)
	testing.expect_value(t, len(m.values), 2)
	testing.expect_value(t, m.values[0], Value_Count{"Norway", 2})
	m.since = m.version
	ui.probe_frame(&p)
	testing.expect(t, m.values == nil, "unchanged since: nothing to copy again")
	testing.expect_value(t, m.version, m.since)
	view_set_search(&m.g.view, "SN-3") // the counts leave the search out
	ui.probe_frame(&p)
	testing.expect(t, m.values == nil)
	view_set_text(&m.g.view, 0, "SN-1") // another column's filter narrows them
	ui.probe_frame(&p)
	testing.expect(t, m.version != m.since)
	testing.expect_value(t, len(m.values), 1)
}

@(test)
test_a_remote_asks_for_its_values_and_keeps_each_delivery_once :: proc(t: ^testing.T) {
	r: Remote_Rows
	remote_rows_init(&r, {page_size = 10}, test_fetch_page, test_fetch_values, nil)
	defer remote_rows_destroy(&r)
	m := Values_Model {
		src = &r,
	}
	grid_init(&m.g, VALUE_COLS)
	defer grid_destroy(&m.g)
	p: ui.Probe
	ui.probe_init(&p, values_view, &m, {400, 300})
	defer ui.probe_destroy(&p)

	testing.expect(t, m.loading, "on their way")
	testing.expect(t, m.values == nil)
	asked := false
	for n in ui.probe_needs(&p) {
		if q, ok := ui.need_as(n, Test_Values); ok {
			asked = q.column == "site"
			values := []Value_Count{{"Norway", 2}, {"Paraguay", 1}}
			ui.probe_deliver(&p, q, Values{values = values})
		}
	}
	testing.expect(t, asked, "a Test_Values for the site column")
	ui.probe_frame(&p)
	testing.expect(t, !m.loading)
	testing.expect_value(t, len(m.values), 2)
	testing.expect_value(t, m.values[0], Value_Count{"Norway", 2})
	testing.expect_value(t, m.values[1], Value_Count{"Paraguay", 1})
	m.since = m.version
	ui.probe_frame(&p)
	testing.expect(t, m.values == nil, "the same delivery: nothing to copy again")
}
