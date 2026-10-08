package datagrid

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
		e := pages_find(p, p.query, i)
		q.offset, q.limit = i * p.page_size, p.page_size
		q.after, q.attempt = e.after, e.attempt
		pg, st, version := remote_rows_fetch(r, gtx, q)
		if pg != nil && (st == .Ready || st == .Stale) {
			pages_arrive(p, p.query, i, pg, version, st == .Stale)
		}
	}
	pages_evict(p, lo, hi)
	return max(p.count, 0) != g.geo.items
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
