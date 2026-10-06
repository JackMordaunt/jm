package datagrid_fuzz

import "core:fmt"

import harness "jm:fuzz"
import "jm:ui/datagrid"

// The page cache alone: queries change, windows move, and pages arrive
// for this query and old ones, short, empty, failed and refreshed, in
// any order, from a server whose rows never change.

// Server is a page cache case's server: how many rows each query has.
@(private)
Server :: struct {
	totals: [4]int, // by query, 1 to 3
	size:   int,
}

// server_key is row i of query q's key: what the cache must show there.
@(private)
server_key :: proc(q: u64, i: int) -> string {
	return fmt.tprintf("q%dr%d", q, i)
}

// server_page is page index of query q as the server answers it, a
// drawn count beside it.
@(private)
server_page :: proc(s: ^Server, q: u64, index: int, src: ^harness.Source) -> datagrid.Page {
	total := s.totals[q]
	lo := min(index * s.size, total)
	hi := min(lo + s.size, total)
	rows := make([]datagrid.Page_Row, hi - lo)
	for &r, k in rows {
		r.key = server_key(q, lo + k)
		r.cells = make([]string, 1)
		r.cells[0] = r.key
	}
	pg := datagrid.Page {
		rows = rows,
	}
	switch harness.integer_in(src, 0, 4) {
	case 0:
		pg.total, pg.total_kind = total, .Exact
	case 1:
		pg.total = max(total + harness.integer_in(src, -s.size, 2 * s.size), 0)
		pg.total_kind = .Estimated
	case 2:
		pg = {
			error = "failed",
		}
	}
	return pg
}

// pages draws a cache's settings and a run of ops, and after each checks
// that every row the cache shows is the server's for its query, that only
// a stand-in shows another query's, that the cache keeps within its
// capacity and the window, and that a found end is where the rows end.
pages :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	cfg := datagrid.Paging {
		page_size  = harness.integer_in(src, 1, 9),
		margin     = harness.integer_in(src, 0, 3),
		capacity   = harness.integer_in(src, 1, 7),
		keep_stale = harness.boolean(src),
	}
	if harness.boolean(src) {
		cfg.estimate = harness.integer_in(src, 1, 80)
	}
	s := Server {
		size = cfg.page_size,
	}
	for q in 1 ..= 3 {
		s.totals[q] = harness.integer_in(src, 0, 60)
	}
	p: datagrid.Pages
	datagrid.pages_init(&p, cfg)
	defer datagrid.pages_destroy(&p)
	datagrid.pages_query(&p, 1)
	version: u64
	for step in 0 ..< harness.integer_in(src, 0, 40) {
		op := harness.integer_in(src, 0, 4)
		detail, ok := apply_pages_op(&p, &s, op, &version, src)
		if ok {
			detail, ok = pages_agree(&p, &s, cfg)
		}
		if !ok {
			return fmt.tprintf("step %d op %d %v, totals %v: %s", step, op, cfg, s.totals, detail),
				false
		}
	}
	return "", true
}

// apply_pages_op applies one drawn op and checks what the op itself promises.
@(private)
apply_pages_op :: proc(
	p: ^datagrid.Pages,
	s: ^Server,
	op: int,
	version: ^u64,
	src: ^harness.Source,
) -> (
	string,
	bool,
) {
	switch op {
	case 0:
		datagrid.pages_query(p, u64(harness.integer_in(src, 1, 4)))
	case 1:
		return want_window(p, s, src)
	case 2:
		return arrive_page(p, s, version, src)
	case:
		lo := harness.integer_in(src, 0, 8)
		datagrid.pages_retry(p, lo, lo + harness.integer_in(src, 0, 4))
	}
	return "", true
}

// want_window wants and evicts for a drawn view and checks the window
// is the view's pages and the margin, and the cache within its bound.
@(private)
want_window :: proc(p: ^datagrid.Pages, s: ^Server, src: ^harness.Source) -> (string, bool) {
	first := harness.integer_in(src, 0, max(p.count, 1) + 10)
	last := first + harness.integer_in(src, 0, 20)
	lo, hi := datagrid.pages_window(p, first, last)
	datagrid.pages_want(p, lo, hi, nil)
	datagrid.pages_evict(p, lo, hi)
	bound := (max(last - 1, first) / s.size - first / s.size + 1) + 2 * p.margin
	if hi - lo > bound || hi - lo < 1 {
		return fmt.tprintf("rows %d to %d want pages %d to %d", first, last, lo, hi), false
	}
	if len(p.entries) > max(p.capacity, hi - lo) {
		return fmt.tprintf("%d pages cached past %d", len(p.entries), p.capacity), false
	}
	return "", true
}

// arrive_page delivers a drawn page, mostly of the current query, and
// checks the cache takes it exactly when it is.
@(private)
arrive_page :: proc(
	p: ^datagrid.Pages,
	s: ^Server,
	version: ^u64,
	src: ^harness.Source,
) -> (
	string,
	bool,
) {
	q := p.query
	if harness.integer_in(src, 0, 4) == 0 {
		q = u64(harness.integer_in(src, 1, 4))
	}
	index := pick_index(p, src)
	version^ += 1
	pg := server_page(s, q, index, src)
	took := datagrid.pages_arrive(p, q, index, &pg, version^, harness.boolean(src))
	return fmt.tprintf("page %d of query %d taken: %v", index, q, took), took == (q == p.query)
}

// pick_index is a page a case delivers: one the cache waits for, mostly.
@(private)
pick_index :: proc(p: ^datagrid.Pages, src: ^harness.Source) -> int {
	if len(p.entries) > 0 && harness.integer_in(src, 0, 4) != 0 {
		return p.entries[harness.integer_in(src, 0, len(p.entries))].index
	}
	return harness.integer_in(src, 0, 10)
}

// pages_agree checks every row the cache would show, and its count.
@(private)
pages_agree :: proc(p: ^datagrid.Pages, s: ^Server, cfg: datagrid.Paging) -> (string, bool) {
	if p.count < 0 {
		return fmt.tprintf("count %d", p.count), false
	}
	total := s.totals[p.query]
	if p.end && p.count != total {
		return fmt.tprintf("an end at %d, the rows end at %d", p.count, total), false
	}
	for i in 0 ..< min(p.count, 200) {
		if detail, ok := row_agrees(p, cfg, i); !ok {
			return detail, false
		}
	}
	return "", true
}

// row_agrees checks the row the cache shows at i: a Ready one the
// server's for the current query, a Stale one the server's for its own
// query, which is another only while stand-ins are kept.
@(private)
row_agrees :: proc(p: ^datagrid.Pages, cfg: datagrid.Paging, i: int) -> (string, bool) {
	row, st, pg := datagrid.pages_row(p, i)
	#partial switch st {
	case .Ready:
		if pg.query != p.query || row.key != server_key(p.query, i) {
			return fmt.tprintf("row %d Ready as %q of query %d", i, row.key, pg.query), false
		}
	case .Stale:
		if pg.query != p.query && !cfg.keep_stale {
			return fmt.tprintf("row %d stands in from query %d", i, pg.query), false
		}
		if row.key != server_key(pg.query, i) {
			return fmt.tprintf("row %d Stale as %q of query %d", i, row.key, pg.query), false
		}
	}
	return "", true
}
