package primer

import "core:testing"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/ops"

// The Primer data grid's Text and Range filter panels through ui.Probe:
// a Contains field, Min and Max fields with their validation, and a date
// range picker's preset, each with its header's dot and its Clear.

@(private = "file")
Crew :: struct {
	g:     Data_Grid,
	rows:  [][3]string,
	keyed: []datagrid.Page_Row,
	table: datagrid.Memory_Table,
}

@(private = "file")
CREW_COLS := []datagrid.Column {
	{id = "name", title = "Name", row_header = true, filter = .Text},
	{id = "count", title = "Count", kind = .Number, align = .End, filter = .Range},
	{id = "joined", title = "Joined", kind = .Date, filter = .Range},
}

@(private = "file")
CREW := [][3]string {
	{"Ada", "1", "2026-10-01"},
	{"Grace Hopper", "1,200", "2026-08-15"},
	{"Linus", "7", "2026-10-06 18:30"},
}

@(private = "file")
crew_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Crew)(user)
	data_grid(gtx, &m.g, CREW_COLS, &m.table, "Crew")
}

@(private = "file")
crew_open :: proc(p: ^ui.Probe) -> ^Crew {
	m := new(Crew, context.temp_allocator)
	m.rows = CREW
	m.keyed = datagrid.rows_of(m.rows, 0)
	datagrid.memory_table_init(&m.table, CREW_COLS, m.keyed)
	data_grid_init(&m.g, CREW_COLS)
	m.g.today = {2026, 10, 6}
	ui.probe_init(p, crew_view, m, ops.Size{900, 600}, allocator = context.temp_allocator)
	return m
}

@(private = "file")
crew_close :: proc(p: ^ui.Probe, m: ^Crew) {
	ui.probe_destroy(p)
	data_grid_destroy(&m.g)
	datagrid.memory_table_destroy(&m.table)
	delete(m.keyed)
	free_all(context.temp_allocator)
}

// shows reports which of the crew's rows the grid draws, by name.
@(private = "file")
shows :: proc(p: ^ui.Probe) -> (ada, grace, linus: bool) {
	return ui.probe_tagged(
		p,
		"Ada",
	), ui.probe_tagged(p, "Grace Hopper"), ui.probe_tagged(p, "Linus")
}

// dot_drawn reports whether a header's filter button wears its dot: an
// ellipse in --fgColor-accent.
@(private = "file")
dot_drawn :: proc(p: ^ui.Probe) -> bool {
	for d in ui.probe_current(p).draws {
		fill, is_fill := d.cmd.(ops.Fill)
		if !is_fill {
			continue
		}
		_, round := fill.shape.(ops.Ellipse)
		ink, solid := fill.paint.(ops.Color)
		if round && solid && ink == color(.Fg_Color_Accent) {
			return true
		}
	}
	return false
}

@(test)
test_a_text_filter_keeps_the_rows_containing_its_text :: proc(t: ^testing.T) {
	p: ui.Probe
	m := crew_open(&p)
	defer crew_close(&p, m)
	testing.expect(t, ui.probe_click(&p, "Filter Name"))
	testing.expect(t, m.g.filter.open)
	testing.expect(t, ui.probe_tagged(&p, "Contains"))
	testing.expect(t, !dot_drawn(&p), "no dot before it filters")
	ui.probe_type(&p, "LI") // the field has focus; case does not matter
	ui.probe_frame(&p)
	ada, grace, linus := shows(&p)
	testing.expect(t, !ada && !grace && linus)
	testing.expect(t, dot_drawn(&p), "the header says the column filters")
	testing.expect(t, ui.probe_click(&p, "Clear"))
	ui.probe_frame(&p)
	ada, grace, linus = shows(&p)
	testing.expect(t, ada && grace && linus)
	testing.expect(t, !datagrid.view_filters_active(&m.g.grid.view))
}

@(test)
test_a_number_range_checks_its_fields_and_keeps_the_rows_between :: proc(t: ^testing.T) {
	p: ui.Probe
	m := crew_open(&p)
	defer crew_close(&p, m)
	testing.expect(t, ui.probe_click(&p, "Filter Count"))
	testing.expect(t, ui.probe_click(&p, "Min"))
	ui.probe_type(&p, "5")
	ui.probe_frame(&p)
	ada, grace, linus := shows(&p)
	testing.expect(t, !ada && grace && linus, "Min alone leaves the top open")
	testing.expect(t, dot_drawn(&p))

	testing.expect(t, ui.probe_click(&p, "Max"))
	ui.probe_type(&p, "lots")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Enter a number"))
	_, grace, _ = shows(&p)
	testing.expect(t, grace, "a field that is no number leaves the filter as it was")

	ui.probe_key(&p, .A, {.Ctrl})
	ui.probe_key(&p, .A, {.Super})
	ui.probe_type(&p, "1,000") // thousands separators read
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Enter a number"))
	ada, grace, linus = shows(&p)
	testing.expect(t, !ada && !grace && linus, "1,200 is over the top")

	testing.expect(t, ui.probe_click(&p, "Min"))
	ui.probe_key(&p, .A, {.Ctrl})
	ui.probe_key(&p, .A, {.Super})
	ui.probe_type(&p, "2000")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Max is less than min"))
	f := datagrid.find_filter(&m.g.grid.view, 1)
	rule := f.rule if f != nil else nil
	r, _ := rule.(datagrid.Range_Filter)
	lo, hi := r.lo.? or_else -1, r.hi.? or_else -1
	testing.expect(t, lo == 5 && hi == 1000, "the last good range stands")

	testing.expect(t, ui.probe_click(&p, "Clear"))
	ui.probe_frame(&p)
	testing.expect(t, !datagrid.view_filtered(&m.g.grid.view, 1))
	testing.expect_value(t, ui.text_string(&m.g.filter.lo), "")
	testing.expect(t, !ui.probe_tagged(&p, "Max is less than min"))
	testing.expect(t, !dot_drawn(&p))
}

@(test)
test_a_date_range_preset_keeps_the_rows_dated_in_it :: proc(t: ^testing.T) {
	p: ui.Probe
	m := crew_open(&p)
	defer crew_close(&p, m)
	testing.expect(t, ui.probe_click(&p, "Filter Joined"))
	testing.expect(t, ui.probe_click(&p, "Choose dates..."))
	testing.expect(t, ui.probe_click(&p, "Last 7 days"))
	ui.probe_frame(&p)
	ada, grace, linus := shows(&p)
	testing.expect(t, ada && !grace && linus, "Sep 30 to the end of Oct 6, both days whole")
	f := datagrid.find_filter(&m.g.grid.view, 2)
	rule := f.rule if f != nil else nil
	r, _ := rule.(datagrid.Range_Filter)
	testing.expect(t, r.lo != nil && r.hi != nil)

	testing.expect(t, ui.probe_click(&p, "Clear filters"), "the toolbar clears a range too")
	ui.probe_frame(&p)
	ada, grace, linus = shows(&p)
	testing.expect(t, ada && grace && linus)
	testing.expect(t, !m.g.filter.open, "Clear filters closes the panel")
}

@(test)
test_a_range_panel_opens_holding_the_filter_as_it_stands :: proc(t: ^testing.T) {
	p: ui.Probe
	m := crew_open(&p)
	defer crew_close(&p, m)
	datagrid.view_set_range(&m.g.grid.view, 1, 2, nil)
	datagrid.view_set_range(&m.g.grid.view, 2, 1759276800, 1759795199)
	testing.expect(t, ui.probe_click(&p, "Filter Count"))
	testing.expect_value(t, ui.text_string(&m.g.filter.lo), "2")
	testing.expect_value(t, ui.text_string(&m.g.filter.hi), "")
	ui.probe_key(&p, .Escape)
	testing.expect(t, ui.probe_click(&p, "Filter Joined"))
	testing.expect_value(t, m.g.filter.dates, Date_Range{{2025, 10, 1}, {2025, 10, 6}})
}
