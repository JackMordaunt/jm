package datagrid

import "core:fmt"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// A paged grid through ui.Probe, against a Memory_Table as its server:
// skeletons, then rows; the need set as the view moves; a new query key on
// a sort; stand-ins kept while a new query loads; a failed page and its
// retry; selecting all loaded or all matching; a streamed export.

@(private = "file")
Pager :: struct {
	g:      Grid,
	skin:   Skin,
	paging: Paging,
	rows:   []Page_Row,
	cells:  [][4]string,
	table:  Memory_Table,
	ev:     Events,
	fail:   bool, // answer every page with an error
	seen:   ops.Color, // what a test's cell slot saw
}

@(private = "file")
PAGED_COLS := []Column {
	{id = "serial", title = "Serial", row_header = true},
	{id = "model", title = "Model", filter = .Set},
	{id = "site", title = "Site", filter = .Set},
	{id = "hash", title = "Hash", kind = .Number, align = .End},
}

@(private = "file")
pager_make :: proc(n: int, paging: Paging) -> ^Pager {
	m := new(Pager)
	m.paging = paging
	m.cells = make([][4]string, n)
	m.rows = make([]Page_Row, n)
	sites := []string{"Norway", "Paraguay", "Wisconsin"}
	for i in 0 ..< n {
		m.cells[i] = {
			fmt.aprintf("SN-%05d", i),
			fmt.aprintf("M%d", i % 4),
			sites[i % 3],
			fmt.aprintf("%d", (i * 37) % 100),
		}
		m.rows[i] = {
			key   = m.cells[i][0],
			cells = m.cells[i][:],
		}
	}
	memory_table_init(&m.table, PAGED_COLS, m.rows)
	grid_init(&m.g, PAGED_COLS, &m.paging)
	m.skin.style = DEFAULT_STYLE
	return m
}

@(private = "file")
pager_free :: proc(m: ^Pager) {
	grid_destroy(&m.g)
	memory_table_destroy(&m.table)
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
pager_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Pager)(user)
	m.ev = grid(gtx, &m.g, PAGED_COLS, Source{paged = &m.paging}, &m.skin, "Rigs")
}

// serve answers every page the last frame needed, then runs a frame.
@(private = "file")
serve :: proc(p: ^ui.Probe, m: ^Pager) {
	for n in ui.probe_needs(p) {
		q, ok := ui.need_as(n, Page_Query)
		if !ok {
			continue
		}
		pg := answer_page(&m.table, q, context.temp_allocator)
		if m.fail {
			pg = {
				error = "timed out",
			}
		}
		ui.probe_deliver(p, q, pg)
	}
	ui.probe_frame(p)
}

// page_needs counts the pages the last frame needed, and the first and
// last offsets among them.
@(private = "file")
page_needs :: proc(p: ^ui.Probe) -> (n, lo, hi: int) {
	lo = max(int)
	hi = -1
	for need in ui.probe_needs(p) {
		if q, ok := ui.need_as(need, Page_Query); ok {
			n += 1
			lo, hi = min(lo, q.offset), max(hi, q.offset)
		}
	}
	return
}

@(test)
test_a_paged_grid_shows_skeletons_then_rows_and_finds_its_end :: proc(t: ^testing.T) {
	m := pager_make(95, {source = "rigs", page_size = 10, margin = 1})
	defer pager_free(m)
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	n, lo, _ := page_needs(&p)
	testing.expect_value(t, [2]int{n, lo}, [2]int{1, 0}) // one page can be all there is
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `row "" row 2 busy`), said)
	testing.expect(t, !ui.probe_tagged(&p, "SN-00000"), "a skeleton, not a row")
	for _ in 0 ..< 12 {
		serve(&p, m)
	}
	testing.expect(t, ui.probe_tagged(&p, "SN-00000"))
	// 12 rows in view and 2 of overscan are pages 0 and 1, and 1 of margin.
	n, lo, _ = page_needs(&p)
	testing.expect_value(t, [2]int{n, lo}, [2]int{3, 0})
	testing.expect_value(t, m.g.geo.items, 95) // the server said
	testing.expect_value(t, m.g.pages.kind, Count_Kind.Exact)
	m.g.scroll.y = 1e6
	ui.probe_frame(&p)
	// The pages left behind are needed no more: their host cancels them.
	dropped_first := false
	for d in ui.probe_dropped(&p) {
		if q, ok := ui.need_as(d, Page_Query); ok && q.offset == 0 {
			dropped_first = true
		}
	}
	testing.expect(t, dropped_first, "the first page is dropped")
	for _ in 0 ..< 4 {
		serve(&p, m)
	}
	testing.expect_value(t, m.g.geo.items, 95)
	testing.expect(t, ui.probe_tagged(&p, "SN-00094"), "the last row")
	n, lo, _ = page_needs(&p)
	testing.expect(t, n <= 4 && lo >= 70, fmt.tprint(n, lo))
	testing.expect(t, len(m.g.pages.entries) <= m.g.pages.capacity)
}

@(test)
test_a_sort_is_a_new_query_its_pages_asked_with_the_sort :: proc(t: ^testing.T) {
	m := pager_make(60, {source = "rigs", page_size = 20})
	defer pager_free(m)
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	for _ in 0 ..< 4 {
		serve(&p, m)
	}
	before := m.g.pages.query
	testing.expect(t, ui.probe_click(&p, "Hash"))
	testing.expect(t, m.g.pages.query != before, "the sort changed the query key")
	sorted := false
	for need in ui.probe_needs(&p) {
		if q, ok := ui.need_as(need, Page_Query); ok {
			sorted = len(q.sort) == 1 && q.sort[0] == Query_Sort{"hash", false}
		}
	}
	testing.expect(t, sorted, "the page asks with the sort")
	testing.expect(t, !ui.probe_tagged(&p, "SN-00000"), "the old rows went")
	serve(&p, m)
	serve(&p, m)
	// The rows come in the order the server sorted them.
	for i in 0 ..< 3 {
		it := item_at(&m.g, Source{paged = &m.paging}, i)
		want := m.rows[m.table.order.rows[i]].key
		testing.expect(t, it.page_row != nil && it.name == want, fmt.tprint(i, it.name, want))
	}
}

@(test)
test_kept_stand_ins_show_dimmed_until_the_new_query_arrives :: proc(t: ^testing.T) {
	m := pager_make(60, {source = "rigs", page_size = 20, keep_stale = true})
	defer pager_free(m)
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	for _ in 0 ..< 4 {
		serve(&p, m)
	}
	// The cell slot sees the colour row 1's text is drawn in.
	m.skin.cell = proc(gtx: ^ui.Ctx, c: ^Cell, user: rawptr) -> bool {
		if c.text == "SN-00001" {
			(^Pager)(user).seen = c.fg
		}
		return false
	}
	m.skin.user = m
	ui.probe_frame(&p)
	testing.expect_value(t, m.seen.a, 255)
	view_set_values(&m.g.view, 2, {"Norway"})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "SN-00001"), "an old row stands in")
	_, st, _ := pages_row(&m.g.pages, 1)
	testing.expect_value(t, st, Row_State.Stale)
	testing.expect_value(t, m.seen.a, 127) // dimmed by half
	serve(&p, m)
	serve(&p, m)
	testing.expect(t, !ui.probe_tagged(&p, "SN-00001"), "a Paraguay rig, filtered out")
	_, st, _ = pages_row(&m.g.pages, 1)
	testing.expect_value(t, st, Row_State.Ready)
	testing.expect_value(t, m.g.geo.items, 20)
}

@(test)
test_a_failed_page_shows_its_error_and_retries_on_a_click :: proc(t: ^testing.T) {
	m := pager_make(30, {source = "rigs", page_size = 50})
	defer pager_free(m)
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	m.fail = true
	serve(&p, m)
	serve(&p, m)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `row "timed out"`), said)
	m.fail = false
	ui.probe_click_at(&p, {100, 60})
	attempt := -1
	for need in ui.probe_needs(&p) {
		if q, ok := ui.need_as(need, Page_Query); ok {
			attempt = q.attempt
		}
	}
	testing.expect_value(t, attempt, 1)
	serve(&p, m)
	serve(&p, m)
	testing.expect(t, ui.probe_tagged(&p, "SN-00000"))
}

// failed_slots counts the skin's calls for failed rows in a frame.
@(private = "file")
failed_slots: int

// A skin that draws a failed page's rows itself gets a slot for each row:
// a page of many failed rows once claimed one id for all of them.
@(test)
test_a_skin_draws_every_row_of_a_failed_page :: proc(t: ^testing.T) {
	m := pager_make(30, {source = "rigs", page_size = 50})
	defer pager_free(m)
	m.skin.failed = proc(gtx: ^ui.Ctx, size: ops.Size, err: string, user: rawptr) -> bool {
		failed_slots += 1
		p := ui.widget_open(gtx)
		ops.tag(gtx.scene, p.id, "failed slot")
		ui.widget_close(gtx, &p, {size = size})
		return true
	}
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	m.fail = true
	serve(&p, m)
	serve(&p, m)
	_, st, _ := pages_row(&m.g.pages, 3)
	testing.expect_value(t, st, Row_State.Failed)
	failed_slots = 0
	ui.probe_frame(&p)
	// Every row in view is failed, each drawn once by the skin.
	testing.expect_value(t, failed_slots, m.g.geo.last - m.g.geo.first)
	testing.expect(t, failed_slots > 1)
}

@(test)
test_select_all_loaded_names_rows_and_all_matching_names_the_query :: proc(t: ^testing.T) {
	m := pager_make(500, {source = "rigs", page_size = 20, margin = 1})
	defer pager_free(m)
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	for _ in 0 ..< 6 {
		serve(&p, m)
	}
	select_loaded(&m.g, Source{paged = &m.paging})
	testing.expect(t, !m.g.sel.all)
	testing.expect_value(t, len(m.g.sel.keys), 40) // pages 0 and 1
	testing.expect_value(t, m.g.sel.keys[row_key("SN-00032")], "SN-00032")
	ui.probe_click(&p, "SN-00001")
	ui.probe_key(&p, .A, {ui.SHORTCUT})
	testing.expect(t, m.g.sel.all, "all matching, loaded or not")
	testing.expect(t, selected(&m.g.sel, row_key("SN-00499")))
	view_set_values(&m.g.view, 2, {"Norway"})
	ui.probe_frame(&p)
	// The rows it named are not the rows that match now: it keeps the
	// loaded ones it covered, explicitly.
	testing.expect(t, !m.g.sel.all)
	testing.expect(t, selected(&m.g.sel, row_key("SN-00001")))
	testing.expect(t, !selected(&m.g.sel, row_key("SN-00499")))
}

@(test)
test_a_paged_export_streams_every_page_with_progress_and_stops :: proc(t: ^testing.T) {
	m := pager_make(2500, {source = "rigs", page_size = 50})
	defer pager_free(m)
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	serve(&p, m)
	export_start(&m.g, PAGED_COLS, Source{paged = &m.paging})
	serve(&p, m)
	serve(&p, m)
	w, total := export_progress(&m.g)
	testing.expect_value(t, w, EXPORT_PAGE)
	testing.expect_value(t, total, 2500)
	for _ in 0 ..< 4 {
		serve(&p, m)
	}
	testing.expect(t, m.g.export.done)
	text := strings.to_string(m.g.export.text)
	testing.expect_value(t, strings.count(text, "\r\n"), 2501)
	testing.expect(t, strings.has_suffix(text, "SN-02499,M3,Norway,63\r\n"), text[len(text) - 40:])
	export_start(&m.g, PAGED_COLS, Source{paged = &m.paging})
	serve(&p, m)
	export_cancel(&m.g)
	serve(&p, m)
	testing.expect(t, !m.g.export.active)
	for need in ui.probe_needs(&p) {
		q, ok := ui.need_as(need, Page_Query)
		testing.expect(t, !ok || q.limit != EXPORT_PAGE, "a stopped export needs no page")
	}
}

@(test)
test_a_memory_table_pages_by_offset_and_by_cursor_alike :: proc(t: ^testing.T) {
	m := pager_make(100, {page_size = 10})
	defer pager_free(m)
	q := Page_Query {
		columns = {"serial", "model", "site", "hash"},
		sort    = {{"hash", true}},
		filters = {{column = "site", kind = .Set, values = {"Norway", "Wisconsin"}}},
		offset  = 10,
		limit   = 10,
	}
	by_offset := answer_page(&m.table, q, context.temp_allocator)
	testing.expect_value(t, by_offset.total, 67) // a third are Paraguay
	q.offset = 0
	first := answer_page(&m.table, q, context.temp_allocator)
	q.after = {
		key = first.rows[9].key,
	}
	q.offset = 999 // a cursor wins over the offset
	by_cursor := answer_page(&m.table, q, context.temp_allocator)
	testing.expect_value(t, len(by_cursor.rows), 10)
	for r, i in by_cursor.rows {
		testing.expect_value(t, r.key, by_offset.rows[i].key)
	}
	vq := Values_Query {
		column  = "model",
		filters = {{column = "site", kind = .Set, values = {"Norway"}}},
		like    = "m",
		limit   = 3,
	}
	v := answer_values(&m.table, vq, context.temp_allocator)
	testing.expect_value(t, len(v.values), 3)
	// Norway is every third row: models M0 and M3 come 9 times, M1 and M2 8.
	testing.expect_value(t, v.values[0], Value_Count{"M0", 9})
	testing.expect_value(t, v.values[2].count, 8)
}

// A paged grid's steady frame, its pages in and nothing changing,
// allocates nothing either: no heap, no temp, the need plumbing
// included.
@(test)
test_a_steady_paged_frame_allocates_nothing :: proc(t: ^testing.T) {
	spy := Spy {
		inner = context.allocator,
	}
	spy_t := Spy {
		inner = context.temp_allocator,
	}
	context.allocator = {spy_proc, &spy}
	context.temp_allocator = {spy_proc, &spy_t}
	m := pager_make(5000, {source = "rigs", page_size = 50})
	defer pager_free(m)
	view_sort_cycle(&m.g.view, 3, false)
	view_set_values(&m.g.view, 2, {"Norway"})
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	for _ in 0 ..< 6 {
		serve(&p, m)
	}
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	spy.armed, spy_t.armed = true, true
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	spy.armed, spy_t.armed = false, false
	expect_no_allocations(t, &spy, &spy_t)
	testing.expect(t, ui.probe_tagged(&p, "SN-00000"), "the rows are in")
}

// The count says nothing of a query until a page of it lands: before the
// first answer it is only room for a page of skeletons, and after a new
// sort it is the last query's.
@(test)
test_the_count_is_known_only_once_a_page_of_the_query_lands :: proc(t: ^testing.T) {
	m := pager_make(30, {source = "rigs", page_size = 10, keep_stale = true})
	defer pager_free(m)
	p: ui.Probe
	ui.probe_init(&p, pager_view, m, {600, 400})
	defer ui.probe_destroy(&p)
	testing.expect(t, !pages_known(&m.g.pages), "known before any page")
	testing.expect(t, pages_loading(&m.g.pages))
	for _ in 0 ..< 6 {
		serve(&p, m) // a full page reaches for the next until the end shows
	}
	testing.expect(t, pages_known(&m.g.pages))
	testing.expect(t, !pages_loading(&m.g.pages))
	append(&m.g.view.sort, Sort_Key{col = 0, desc = true})
	ui.probe_frame(&p)
	testing.expect(t, !pages_known(&m.g.pages), "the last query's count stood for the new one")
	serve(&p, m)
	serve(&p, m)
	testing.expect(t, pages_known(&m.g.pages))
	est: Pages
	pages_init(&est, {page_size = 10, estimate = 500})
	defer pages_destroy(&est)
	testing.expect(t, pages_known(&est), "a caller's estimate is known")
}
