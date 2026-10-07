package primer

import "core:testing"

import "jm:ui"
import "jm:ui/datagrid"

@(private = "file")
COUNT_COLS := []datagrid.Column{{id = "serial", title = "Serial"}}

@(private = "file")
Count_Model :: struct {
	g:      Data_Grid,
	remote: datagrid.Remote_Rows,
}

@(private = "file")
count_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Count_Model)(user)
	data_grid(gtx, &m.g, COUNT_COLS, &m.remote, "Rigs")
}

// A paged grid says Loading… until its first page lands, never the room
// it keeps for a page of skeletons as if it were the rows' number.
@(test)
test_a_paged_grid_counts_only_what_arrived :: proc(t: ^testing.T) {
	m: Count_Model
	datagrid.remote_rows_init(&m.remote, {source = "rigs", page_size = 50})
	defer datagrid.remote_rows_destroy(&m.remote)
	data_grid_init(&m.g, COUNT_COLS)
	defer data_grid_destroy(&m.g)
	p: ui.Probe
	ui.probe_init(&p, count_view, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Loading…"))
	testing.expect(t, !ui.probe_tagged(&p, "about 50 rows"))
	for n in ui.probe_needs(&p) {
		if q, ok := ui.need_as(n, datagrid.Page_Query); ok {
			rows := []datagrid.Page_Row {
				{key = "a", cells = {"SN-1"}},
				{key = "b", cells = {"SN-2"}},
			}
			ui.probe_deliver(&p, q, datagrid.Page{rows = rows, total = 2, total_kind = .Exact})
		}
	}
	ui.probe_advance(&p, 2, 1.0 / 60)
	testing.expect(t, ui.probe_tagged(&p, "2 rows"))
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
}
