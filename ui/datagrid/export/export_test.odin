package export

import "core:fmt"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/datagrid"

// An export through ui.Probe over a grid of rigs, a table's and a
// remote's: the view as CSV a chunk or a page at a time with progress,
// all of it at once, and the view it began on kept when the grid's
// changes under it.

@(private = "file")
COLS := []datagrid.Column {
	{id = "serial", title = "Serial", row_header = true},
	{id = "model", title = "Model", filter = .Set},
	{id = "site", title = "Site", filter = .Set},
	{id = "hash", title = "Hash", kind = .Number, align = .End},
}

@(private = "file")
SITES := []string{"Norway", "Paraguay", "Wisconsin"}

// Rigs is a grid over n rigs, as a table or, remote, served from one: a
// rig's serial is SN- and its index, its site every third the same, its
// hash (index * 37) % 100.
@(private = "file")
Rigs :: struct {
	g:        datagrid.Grid,
	skin:     datagrid.Skin,
	cells:    [][4]string,
	rows:     []datagrid.Page_Row,
	table:    datagrid.Memory_Table,
	remote:   datagrid.Remote_Rows,
	src:      datagrid.Rows,
	x:        Export,
	begin:    bool, // start an export in the next frame, as a menu does
	at_once:  bool, // or write it all at once, as Copy CSV does
	wrote:    bool, // what all reported
	hold:     bool, // skip the export's steps, as a slow frame would
	finished: int, // frames step reported the end on
}

@(private = "file")
rigs_make :: proc(n: int, remote: bool) -> ^Rigs {
	m := new(Rigs)
	m.cells = make([][4]string, n)
	m.rows = make([]datagrid.Page_Row, n)
	for ii in 0 ..< n {
		m.cells[ii] = {
			fmt.aprintf("SN-%05d", ii),
			fmt.aprintf("M%d", ii % 4),
			SITES[ii % 3],
			fmt.aprintf("%d", (ii * 37) % 100),
		}
		m.rows[ii] = {m.cells[ii][0], m.cells[ii][:]}
	}
	datagrid.memory_table_init(&m.table, COLS, m.rows)
	m.src = &m.table
	if remote {
		datagrid.remote_rows_init(&m.remote, {page_size = 50}, fetch_page, nil, nil)
		m.src = &m.remote
	}
	datagrid.grid_init(&m.g, COLS)
	m.skin.style = datagrid.DEFAULT_STYLE
	return m
}

@(private = "file")
rigs_free :: proc(m: ^Rigs) {
	destroy(&m.x)
	datagrid.grid_destroy(&m.g)
	datagrid.remote_rows_destroy(&m.remote)
	datagrid.memory_table_destroy(&m.table)
	for c in m.cells {
		delete(c[0])
		delete(c[1])
		delete(c[3])
	}
	delete(m.cells)
	delete(m.rows)
	free(m)
}

@(private = "file")
rigs_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Rigs)(user)
	switch {
	case m.begin:
		start(&m.x, gtx, &m.g, COLS, m.src)
	case m.at_once:
		m.wrote = write_all(&m.x, gtx, &m.g, COLS, m.src)
	}
	m.begin, m.at_once = false, false
	datagrid.grid(gtx, &m.g, COLS, m.src, &m.skin, "Rigs")
	if !m.hold && step(&m.x, gtx, COLS, m.src) {
		m.finished += 1
	}
}

// Test_Page is the tests' own need for a page.
@(private = "file")
Test_Page :: distinct datagrid.Page_Query

@(private = "file")
fetch_page :: proc(
	_: rawptr,
	gtx: ^ui.Ctx,
	q: datagrid.Page_Query,
) -> (
	^datagrid.Page,
	ui.Status,
	u64,
) {
	return ui.need_versioned(gtx, Test_Page(q), datagrid.Page)
}

// serve answers every page the last frame needed from the rigs' table,
// then runs a frame.
@(private = "file")
serve :: proc(p: ^ui.Probe, m: ^Rigs) {
	for n in ui.probe_needs(p) {
		if q, ok := ui.need_as(n, Test_Page); ok {
			pg := datagrid.answer_page(&m.table, datagrid.Page_Query(q), context.temp_allocator)
			ui.probe_deliver(p, q, pg)
		}
	}
	ui.probe_frame(p)
}

// count_export_pages counts the pages of PAGE rows the last frame
// needed, and reports whether any was under a sort.
@(private = "file")
count_export_pages :: proc(p: ^ui.Probe) -> (n: int, sorted: bool) {
	for need in ui.probe_needs(p) {
		if q, ok := ui.need_as(need, Test_Page); ok && q.limit == PAGE {
			n += 1
			sorted ||= len(q.sort) > 0
		}
	}
	return
}

@(test)
test_a_table_export_writes_the_view_a_chunk_a_frame :: proc(t: ^testing.T) {
	m := rigs_make(90_000, false)
	defer rigs_free(m)
	datagrid.view_set_values(&m.g.view, 2, {"Norway"})
	m.g.view.cols[1].hidden = true
	p: ui.Probe
	ui.probe_init(&p, rigs_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	m.begin = true
	ui.probe_frame(&p)
	w, total := progress(&m.x)
	testing.expect_value(t, w, CHUNK)
	testing.expect_value(t, total, 30_000)
	testing.expect(t, running(&m.x))
	ui.probe_frame(&p)
	testing.expect(t, !running(&m.x))
	testing.expect_value(t, m.finished, 1)
	got := text(&m.x)
	testing.expect(
		t,
		strings.has_prefix(got, "Serial,Site,Hash\r\nSN-00000,Norway,0\r\nSN-00003,Norway,11\r\n"),
		got[:60],
	)
	testing.expect_value(t, strings.count(got, "\r\n"), 30_001)
}

@(test)
test_all_writes_a_table_view_at_once_in_column_order :: proc(t: ^testing.T) {
	m := rigs_make(50_000, false)
	defer rigs_free(m)
	datagrid.view_set_values(&m.g.view, 2, {"Paraguay"})
	m.g.view.cols[1].hidden = true
	datagrid.move_column(m.g.view.order[:], 3, 0)
	p: ui.Probe
	ui.probe_init(&p, rigs_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p) // the grid lays its columns out
	m.at_once = true
	ui.probe_frame(&p)
	testing.expect(t, m.wrote)
	got := text(&m.x)
	testing.expect(
		t,
		strings.has_prefix(got, "Hash,Serial,Site\r\n37,SN-00001,Paraguay\r\n"),
		got[:50],
	)
	testing.expect_value(t, strings.count(got, "\r\n"), 16_668) // the titles and a third of the rows
}

// A sort changed while a table's export runs reorders the grid, not the
// file: the export writes the order it began on.
@(test)
test_a_table_export_keeps_the_order_it_began_on :: proc(t: ^testing.T) {
	m := rigs_make(45_000, false)
	defer rigs_free(m)
	p: ui.Probe
	ui.probe_init(&p, rigs_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p)
	m.begin = true
	ui.probe_frame(&p)
	datagrid.view_sort_cycle(&m.g.view, 0, false) // Serial ascending
	datagrid.view_sort_cycle(&m.g.view, 0, false) // and descending
	m.hold = true
	ui.probe_frame(&p)
	for frames := 0; m.table.target != 0 && frames < 1000; frames += 1 {
		ui.probe_frame(&p) // the grid builds the new order a slice a frame
	}
	testing.expect_value(t, m.table.target, 0)
	m.hold = false
	for frames := 0; running(&m.x) && frames < 100; frames += 1 {
		ui.probe_frame(&p)
	}
	testing.expect(t, m.x.error == "", m.x.error)
	got := text(&m.x)
	testing.expect(t, strings.has_prefix(got, "Serial,Model,Site,Hash\r\nSN-00000,"), got[:40])
	testing.expect(t, strings.has_suffix(got, "SN-44999,M3,Wisconsin,63\r\n"), got[len(got) - 30:])
	testing.expect_value(t, strings.count(got, "\r\n"), 45_001)
}

// Rows changed under a table's export stop it: its order points into
// the rows it began on.
@(test)
test_a_table_export_stops_when_its_rows_change :: proc(t: ^testing.T) {
	m := rigs_make(45_000, false)
	defer rigs_free(m)
	p: ui.Probe
	ui.probe_init(&p, rigs_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p)
	m.begin = true
	ui.probe_frame(&p)
	datagrid.memory_table_changed(&m.table, m.rows[:100])
	ui.probe_frame(&p)
	testing.expect(t, !running(&m.x))
	testing.expect_value(t, m.x.error, "the rows changed while they were exported")
	testing.expect_value(t, m.finished, 1)
}

@(test)
test_a_remote_export_streams_every_page_with_progress_and_stops :: proc(t: ^testing.T) {
	m := rigs_make(2500, true)
	defer rigs_free(m)
	p: ui.Probe
	ui.probe_init(&p, rigs_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	serve(&p, m)
	m.begin = true
	serve(&p, m)
	serve(&p, m)
	w, total := progress(&m.x)
	testing.expect_value(t, w, PAGE)
	testing.expect_value(t, total, 2500)
	for _ in 0 ..< 4 {
		serve(&p, m)
	}
	testing.expect(t, !running(&m.x))
	testing.expect_value(t, m.finished, 1)
	got := text(&m.x)
	testing.expect_value(t, strings.count(got, "\r\n"), 2501)
	testing.expect(t, strings.has_suffix(got, "SN-02499,M3,Norway,63\r\n"), got[len(got) - 40:])
	m.begin = true
	ui.probe_frame(&p)
	testing.expect(t, running(&m.x), "a second export runs")
	n, _ := count_export_pages(&p)
	testing.expect_value(t, n, 1)
	cancel(&m.x)
	serve(&p, m)
	n, _ = count_export_pages(&p)
	testing.expect_value(t, n, 0)
}

// A sort changed while a remote's export runs sorts the grid's pages,
// not the export's: it asks for the query it began on to the end.
@(test)
test_a_remote_export_keeps_the_query_it_began_on :: proc(t: ^testing.T) {
	m := rigs_make(2500, true)
	defer rigs_free(m)
	p: ui.Probe
	ui.probe_init(&p, rigs_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	serve(&p, m)
	m.begin = true
	serve(&p, m)
	datagrid.view_sort_cycle(&m.g.view, 3, false)
	for frames := 0; running(&m.x) && frames < 20; frames += 1 {
		serve(&p, m)
		_, sorted := count_export_pages(&p)
		testing.expect(t, !sorted, "an export page asked under the new sort")
	}
	testing.expect(t, !running(&m.x))
	got := text(&m.x)
	testing.expect_value(t, strings.count(got, "\r\n"), 2501)
	testing.expect(t, strings.has_suffix(got, "SN-02499,M3,Norway,63\r\n"), got[len(got) - 40:])
}
