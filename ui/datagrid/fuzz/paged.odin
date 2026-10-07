package datagrid_fuzz

import "core:encoding/cbor"
import "core:fmt"
import "core:slice"

import harness "jm:fuzz"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/ops"

// A paged grid through ui.Probe, its host answering from a Memory_Table:
// the user scrolls, sorts, filters, searches and clicks rows, and the host
// answers what it was asked in any order, as an error, as a refresh, late
// after the need went, or never. The same table, asked for one row of the
// current query, is the reference every shown row is held to.

@(private)
PAGED_COLUMNS := []datagrid.Column {
	{id = "key", title = "Key", row_header = true},
	{id = "model", title = "Model", filter = .Set},
	{id = "site", title = "Site", filter = .Set},
	{id = "hash", title = "Hash", kind = .Number},
}

// Paged_Case is one case's grid, its rows and its host.
@(private)
Paged_Case :: struct {
	g:       datagrid.Grid,
	skin:    datagrid.Skin,
	paging:  datagrid.Paging,
	rows:    []datagrid.Page_Row,
	table:   datagrid.Memory_Table,
	pending: [dynamic]Pending,
	clicked: datagrid.Row_Key,
	click:   bool, // a row was clicked, and nothing since changed the selection
}

// Pending is a page the host was asked for and has not answered; live is
// false once the grid needs it no more, when a host would cancel it.
@(private)
Pending :: struct {
	key:  ui.Need_Key,
	q:    datagrid.Page_Query,
	live: bool,
}

@(private)
paged_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	c := (^Paged_Case)(user)
	datagrid.grid(gtx, &c.g, PAGED_COLUMNS, {paged = &c.paging}, &c.skin, "Rows")
}

// paged draws a table and a grid's paging over it, then a run of ops, and
// after each frame holds the grid to the reference.
paged :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	c := new(Paged_Case)
	paged_case_init(c, src)
	defer datagrid.grid_destroy(&c.g)
	defer datagrid.memory_table_destroy(&c.table)
	p: ui.Probe
	ui.probe_init(&p, paged_view, c, {400, f32(harness.integer_in(src, 60, 500))})
	defer ui.probe_destroy(&p)
	host_sync(c, &p)
	for step in 0 ..< harness.integer_in(src, 0, 40) {
		op := harness.integer_in(src, 0, 8)
		apply_op(c, &p, op, src)
		ui.probe_frame(&p)
		host_sync(c, &p)
		if detail, ok := paged_holds(c, &p); !ok {
			return fmt.tprintf(
					"step %d op %d, %d rows, %v: %s",
					step,
					op,
					len(c.rows),
					c.paging,
					detail,
				),
				false
		}
	}
	return "", true
}

@(private)
paged_case_init :: proc(c: ^Paged_Case, src: ^harness.Source) {
	n := harness.integer_in(src, 0, 300)
	c.rows = make([]datagrid.Page_Row, n)
	sites := []string{"Norway", "Paraguay", "Wisconsin"}
	for &r, i in c.rows {
		r.key = fmt.aprintf("k%04d", i)
		cells := make([]string, 4)
		cells[0] = r.key
		cells[1] = fmt.aprintf("M%d", (i * 7) % 5)
		cells[2] = sites[(i * 5) % 3]
		cells[3] = fmt.aprint((i * 37) % 101)
		r.cells = cells
	}
	datagrid.memory_table_init(&c.table, PAGED_COLUMNS, c.rows)
	c.paging = {
		source     = "rows",
		page_size  = harness.integer_in(src, 1, 30),
		margin     = harness.integer_in(src, 0, 3),
		capacity   = harness.integer_in(src, 1, 10),
		keep_stale = harness.boolean(src),
	}
	if harness.boolean(src) {
		c.paging.estimate = harness.integer_in(src, 1, 400)
	}
	datagrid.grid_init(&c.g, PAGED_COLUMNS, &c.paging)
	c.skin.style = datagrid.DEFAULT_STYLE
	c.pending = make([dynamic]Pending)
}

// apply_op does what the user or the host does between two frames.
@(private)
apply_op :: proc(c: ^Paged_Case, p: ^ui.Probe, op: int, src: ^harness.Source) {
	v := &c.g.view
	switch op {
	case 0:
		c.g.scroll.y = f32(harness.integer_in(src, 0, len(c.rows) * 33 + 100))
	case 1:
		datagrid.view_sort_cycle(v, harness.integer_in(src, 0, 4), harness.boolean(src))
	case 2:
		filter_sites(v, src)
	case 3:
		datagrid.view_set_search(v, harness.choice(src, []string{"", "1", "k00", "Nor", "M2"}))
	case 4:
		for _ in 0 ..< harness.integer_in(src, 1, 5) {
			host_answer(c, p, src)
		}
	case 5:
		click_row(c, p, src)
	}
}

// filter_sites sets a drawn Set filter on the model or the site column to
// a drawn few of the sites, none clearing it.
@(private)
filter_sites :: proc(v: ^datagrid.View, src: ^harness.Source) {
	values := make([dynamic]string)
	for s in ([]string{"Norway", "Paraguay", "Wisconsin"}) {
		if harness.boolean(src) {
			append(&values, s)
		}
	}
	datagrid.view_set_values(v, harness.choice(src, []int{1, 2}), values[:])
}

// host_sync starts what the grid needs that the host was not asked for,
// and marks what it needs no more.
@(private)
host_sync :: proc(c: ^Paged_Case, p: ^ui.Probe) {
	needs := ui.probe_needs(p)
	for &w in c.pending {
		w.live = false
		for n in needs {
			w.live ||= n.key == w.key
		}
	}
	outer: for n in needs {
		q, ok := ui.need_as(n, datagrid.Page_Query, context.allocator)
		if !ok {
			continue
		}
		for w in c.pending {
			if w.key == n.key {
				continue outer
			}
		}
		append(&c.pending, Pending{n.key, q, true})
	}
}

// deliver gives the grid pg under w's need, with status.
@(private)
deliver :: proc(p: ^ui.Probe, w: Pending, pg: datagrid.Page, status := ui.Status.Ready) {
	bytes, err := cbor.marshal_into_bytes(pg)
	assert(err == nil, "a page always encodes")
	ui.probe_deliver_raw(p, w.key, bytes, status)
}

// host_answer answers one page it was asked for, in a drawn way: the
// page, an error, the page as a refresh, or nothing, the request dropped
// as cancelled. One the grid needs no more is answered late or dropped.
@(private)
host_answer :: proc(c: ^Paged_Case, p: ^ui.Probe, src: ^harness.Source) {
	if len(c.pending) == 0 {
		return
	}
	i := harness.integer_in(src, 0, len(c.pending))
	w := c.pending[i]
	ordered_remove(&c.pending, i)
	switch harness.integer_in(src, 0, 5) {
	case 0:
		deliver(p, w, datagrid.Page{error = "failed"})
	case 1:
		deliver(p, w, datagrid.answer_page(&c.table, w.q), .Stale)
	case 2:
		if !w.live {
			return // cancelled: a host drops a need that went
		}
		fallthrough
	case:
		deliver(p, w, datagrid.answer_page(&c.table, w.q))
	}
}

// click_row clicks a drawn row the grid shows, when it shows any.
@(private)
click_row :: proc(c: ^Paged_Case, p: ^ui.Probe, src: ^harness.Source) {
	g := &c.g
	shown := make([dynamic]int)
	for i in g.geo.first ..< g.geo.last {
		it := datagrid.item_at(g, {paged = &c.paging}, i)
		top := f32(datagrid.heights_top(&g.heights, i)) - g.scroll.y
		if (it.state == .Ready || it.state == .Stale) && top >= 0 && top + 20 < g.geo.body.h {
			append(&shown, i)
		}
	}
	if len(shown) == 0 {
		return
	}
	i := shown[harness.integer_in(src, 0, len(shown))]
	it := datagrid.item_at(g, {paged = &c.paging}, i)
	y := g.geo.body.y + f32(datagrid.heights_top(&g.heights, i)) - g.scroll.y + 10
	ui.probe_click_at(p, ops.Point{10, y})
	c.clicked, c.click = it.key, true
	host_sync(c, p)
}

// current_query is the request for the grid's view as it stands, without
// its rows: what the reference is asked.
@(private)
current_query :: proc(c: ^Paged_Case) -> datagrid.Page_Query {
	v := &c.g.view
	q := datagrid.Page_Query {
		search = v.search,
	}
	sort := make([dynamic]datagrid.Query_Sort)
	for k in v.sort {
		append(&sort, datagrid.Query_Sort{PAGED_COLUMNS[k.col].id, k.desc})
	}
	filters := make([dynamic]datagrid.Query_Filter)
	for f in v.filters {
		if datagrid.filter_active(f) {
			append(&filters, datagrid.Query_Filter{PAGED_COLUMNS[f.col].id, f.rule})
		}
	}
	q.sort, q.filters = sort[:], filters[:]
	return q
}

// paged_holds checks a frame: the rows shown, the cache and the need set,
// the selection and the end.
@(private)
paged_holds :: proc(c: ^Paged_Case, p: ^ui.Probe) -> (string, bool) {
	g := &c.g
	want := current_query(c)
	want.limit = 1
	if detail, ok := rows_hold(c, want); !ok {
		return detail, false
	}
	// The window the frame wanted, before what arrived in it moved the
	// count: the cache may hold it until the next frame's window.
	lo, hi := g.pages.wanted[0], g.pages.wanted[1]
	if len(g.pages.entries) > max(g.pages.capacity, hi - lo) {
		return fmt.tprintf("%d pages cached, capacity %d", len(g.pages.entries), g.pages.capacity),
			false
	}
	if detail, ok := needs_hold(c, p, want, lo, hi); !ok {
		return detail, false
	}
	if detail, ok := selection_holds(c); !ok {
		return detail, false
	}
	total := datagrid.answer_page(&c.table, want).total
	ok := !g.pages.end || g.pages.count == total
	return fmt.tprintf("an end at %d, %d rows match", g.pages.count, total), ok
}

// selection_holds checks that a clicked row is the selection, alone and
// keyed by its own key string.
@(private)
selection_holds :: proc(c: ^Paged_Case) -> (string, bool) {
	sel := &c.g.sel
	if !c.click {
		return "", true
	}
	name, held := sel.keys[c.clicked]
	ok := held && len(sel.keys) == 1 && !sel.all && datagrid.row_key(name) == c.clicked
	return fmt.tprintf("clicked %v, selection %v", c.clicked, sel.keys), ok
}

// rows_hold holds every row in view to the reference's row at its place
// under the current query; a stand-in from another query must be kept on
// purpose.
@(private)
rows_hold :: proc(c: ^Paged_Case, want: datagrid.Page_Query) -> (string, bool) {
	g := &c.g
	for i in g.geo.first ..< g.geo.last {
		row, st, page := datagrid.pages_row(&g.pages, i)
		if st != .Ready && st != .Stale {
			continue
		}
		if !shown_row_holds(c, want, i, row.key, st, page.query) {
			return fmt.tprintf("row %d shows %q as %v of query %d", i, row.key, st, page.query),
				false
		}
	}
	return "", true
}

// shown_row_holds reports whether row i may show key, from query: the
// current query's row there, or another's only as a stand-in kept on
// purpose.
@(private)
shown_row_holds :: proc(
	c: ^Paged_Case,
	want: datagrid.Page_Query,
	i: int,
	key: string,
	st: datagrid.Row_State,
	query: u64,
) -> bool {
	if query != c.g.pages.query {
		return st == .Stale && c.paging.keep_stale
	}
	return row_is(c, want, i, key)
}

// row_is reports whether row i of the query want asks for is keyed key.
@(private)
row_is :: proc(c: ^Paged_Case, want: datagrid.Page_Query, i: int, key: string) -> bool {
	q := want
	q.offset = i
	ref := datagrid.answer_page(&c.table, q)
	return len(ref.rows) == 1 && ref.rows[0].key == key
}

// needs_hold checks the pages the frame needed: each under the current
// query, each in the window [lo, hi) the view wants, no more than it.
@(private)
needs_hold :: proc(
	c: ^Paged_Case,
	p: ^ui.Probe,
	want: datagrid.Page_Query,
	lo, hi: int,
) -> (
	string,
	bool,
) {
	n := 0
	for need in ui.probe_needs(p) {
		q, ok := ui.need_as(need, datagrid.Page_Query, context.allocator)
		if !ok {
			continue
		}
		n += 1
		index := q.offset / c.paging.page_size
		if index < lo || index >= hi {
			return fmt.tprintf("page %d needed outside pages %d to %d", index, lo, hi), false
		}
		if !same_query(q, want) {
			return fmt.tprintf("a page needed under %v, the view is %v", q, want), false
		}
	}
	if n > hi - lo {
		return fmt.tprintf("%d pages needed for a window of %d", n, hi - lo), false
	}
	return "", true
}

// same_query reports whether a and b ask for the same rows in the same
// order, whatever page.
@(private)
same_query :: proc(a, b: datagrid.Page_Query) -> bool {
	if a.search != b.search || !slice.equal(a.sort, b.sort) || len(a.filters) != len(b.filters) {
		return false
	}
	for f, i in a.filters {
		g := b.filters[i]
		fs, f_set := f.rule.(datagrid.Set_Filter)
		gs, g_set := g.rule.(datagrid.Set_Filter)
		if f.column != g.column || !f_set || !g_set || !slice.equal(fs.values, gs.values) {
			return false
		}

	}
	return true
}
