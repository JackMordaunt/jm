package datagrid

import "core:fmt"
import "jm:ui"

// The frame's side of a paged grid: the pages near the view are asked of
// the caller's fetch, and what arrives under them goes into the cache. A
// page scrolled far away is asked for no more, so a fetch that asks by
// need has its host cancel the request; a page that comes back into view
// is asked for again.

// page_query is the request shared by every page of the current view,
// without the rows: the columns, the sort, the filters and the search,
// in the frame's allocator.
page_query :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column) -> Page_Query {
	q := Page_Query {
		columns = make([]string, len(cols), gtx.allocator),
		sort    = make([]Query_Sort, len(g.view.sort), gtx.allocator),
		search  = g.view.search,
	}
	for c, i in cols {
		q.columns[i] = c.id
	}
	for s, i in g.view.sort {
		q.sort[i] = {cols[s.col].id, s.desc}
	}
	q.filters = query_filters(gtx, g, cols, -1)
	return q
}

// query_filters is the view's active filters as a request carries them,
// leaving out column except's (-1 leaves none out).
query_filters :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, except: int) -> []Query_Filter {
	out := make([dynamic]Query_Filter, 0, len(g.view.filters), gtx.allocator)
	for f in g.view.filters {
		if !filter_active(f) || f.col == except {
			continue
		}
		append(&out, Query_Filter{cols[f.col].id, f.rule})

	}
	return out[:]
}

// sort_columns is the view's sort columns, in the sort's order: what a
// keyset cursor carries the values of.
@(private)
sort_columns :: proc(gtx: ^ui.Ctx, g: ^Grid) -> []int {
	out := make([]int, len(g.view.sort), gtx.allocator)
	for s, i in g.view.sort {
		out[i] = s.col
	}
	return out
}

// want_pages asks fetch for the pages near the view, takes in those that
// arrived, and evicts what the cache cannot keep. It reports whether the
// count moved.
@(private)
want_pages :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, r: ^Remote_Rows) -> bool {
	p := &r.pages
	lo, hi := pages_window(p, g.geo.first, g.geo.last)
	pages_want(p, lo, hi, sort_columns(gtx, g))
	q := page_query(gtx, g, cols)
	for i in lo ..< hi {
		if r.fetch == nil {
			break
		}
		e := pages_find(p, p.query, i)
		q.offset, q.limit = i * p.page_size, p.page_size
		q.after, q.attempt = e.after, e.attempt
		pg, st, version := r.fetch(r.user, gtx, q)
		if pg != nil && (st == .Ready || st == .Stale) {
			pages_arrive(p, p.query, i, pg, version, st == .Stale)
		}
	}
	pages_evict(p, lo, hi)
	return max(p.count, 0) != g.geo.items
}

// export_page asks for the export's next page and writes it when it
// arrives: in order, a page at a time, each after the last, so a keyset
// source gets the cursor every time. A short page is the end; an error
// stops the export with it.
@(private)
export_page :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, r: ^Remote_Rows, ev: ^Events) {
	x := &g.export
	if r.fetch == nil {
		return
	}
	q := page_query(gtx, g, cols)
	q.offset, q.limit, q.after, q.attempt = x.next, x.limit, x.after, x.attempt
	pg, st, _ := r.fetch(r.user, gtx, q)
	switch {
	case pg == nil || st != .Ready:
		return
	case pg.error != "":
		x.error = clone_to(pg.error, x.text.buf.allocator)
		x.done = true
	case:
		export_rows_of(gtx, x, cols, pg.rows)
		x.next += len(pg.rows)
		x.done = len(pg.rows) < x.limit
		if !x.done {
			export_keep_cursor(x, pg.rows[len(pg.rows) - 1], sort_columns(gtx, g))
		}
	}
	ev.exported = x.done
}

// export_rows_of writes a page's rows to x, the export's columns of each.
@(private)
export_rows_of :: proc(gtx: ^ui.Ctx, x: ^Export, cols: []Column, rows: []Page_Row) {
	fields := make([dynamic]string, 0, len(x.cols), gtx.allocator)
	for r in rows {
		clear(&fields)
		for c in x.cols {
			switch {
			case cols[c].row_number:
				append(&fields, fmt.aprint(x.written + 1, allocator = gtx.allocator))
			case c < len(r.cells):
				append(&fields, r.cells[c])
			case:
				append(&fields, "")
			}
		}
		write_record(&x.text, CSV, fields[:])
		x.written += 1
	}
}

// export_keep_cursor keeps the last row written as the next page's cursor.
@(private)
export_keep_cursor :: proc(x: ^Export, r: Page_Row, sort_cols: []int) {
	clear(&x.keep)
	append(&x.keep, r.key)
	spans := make([dynamic][2]int, 0, len(sort_cols), context.temp_allocator)
	for c in sort_cols {
		lo := len(x.keep)
		if c < len(r.cells) {
			append(&x.keep, r.cells[c])
		}
		append(&spans, [2]int{lo, len(x.keep)})
	}
	alloc := x.text.buf.allocator
	delete(x.after.values, alloc)
	x.after.key = string(x.keep[:len(r.key)])
	x.after.values = make([]string, len(spans), alloc)
	for s, i in spans {
		x.after.values[i] = string(x.keep[s[0]:s[1]])
	}
}

// values_query is the request for column col's distinct values under
// the other filters and the search, like a filter text, at most limit,
// which a Set filter asks a remote's fetch_values for, as the grid
// cannot count rows it does not hold.
@(private)
values_query :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	col: int,
	like: string,
	limit := 200,
) -> Values_Query {
	return {
		column = cols[col].id,
		filters = query_filters(gtx, g, cols, col),
		search = g.view.search,
		like = like,
		limit = limit,
	}
}
