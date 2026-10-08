package datagrid

import "jm:ui"

// Rows is where a grid's rows come from, the grid's to ask one question
// of either: the rows its query keeps, at places 0 to the count. A
// Memory_Table holds every row and answers this frame, ordering them on
// the grid's budget; a Remote_Rows asks the caller's fetch procs for
// pages of them and answers as they arrive, frames later. The grid
// reads both through the procs here, so what differs between them is
// when an answer comes, not what it is.
//
// The caller keeps each for the grid's life and passes it every frame;
// nil is no rows.
Rows :: union {
	^Memory_Table,
	^Remote_Rows,
}

// Remote_Rows is a grid's window on rows a source holds: the page cache,
// which keeps a bounded number of the pages near the view (paged.odin),
// and the caller's procs that ask its source for a page and for a
// column's values, with the user pointer they are called with.
Remote_Rows :: struct {
	pages:        Pages,
	fetch:        Fetch_Page,
	fetch_values: Fetch_Values,
	user:         rawptr,
}

// Fetch_Page asks the caller's source for page q, every frame the page is
// wanted, and returns what the source has sent so far as
// ui.need_versioned does: the page, nil unless status is Ready or Stale,
// valid for the frame; and a version that moves with each delivery. The
// caller names q to its source in its own terms, a need of its own type
// (a distinct Page_Query will do), so no contract with a host is the
// grid's. A frame that does not ask for a page lets it go.
Fetch_Page :: #type proc(
	user: rawptr,
	gtx: ^ui.Ctx,
	q: Page_Query,
) -> (
	page: ^Page,
	status: ui.Status,
	version: u64,
)

// Fetch_Values asks the caller's source for a column's values for its Set
// filter, as Fetch_Page asks for a page.
Fetch_Values :: #type proc(
	user: rawptr,
	gtx: ^ui.Ctx,
	q: Values_Query,
) -> (
	values: ^Values,
	status: ui.Status,
	version: u64,
)

// remote_rows_init readies r to ask fetch for pages as paging says, and
// values (nil for none) for a Set filter's values, each called with user.
remote_rows_init :: proc(
	r: ^Remote_Rows,
	paging: Paging,
	fetch: Fetch_Page,
	values: Fetch_Values,
	user: rawptr,
	allocator := context.allocator,
) {
	pages_init(&r.pages, paging, allocator)
	r.fetch, r.fetch_values, r.user = fetch, values, user
}

remote_rows_destroy :: proc(r: ^Remote_Rows) {
	pages_destroy(&r.pages)
	r^ = {}
}

// rows_count is how many places src has, how sure it is of that, and
// whether the count says anything yet: a remote's is only room for a
// page of skeletons until a page of the query arrives (or its estimate
// stands), and a caller must not show it as the rows' number.
rows_count :: proc(src: Rows) -> (n: int, kind: Count_Kind, known: bool) {
	switch r in src {
	case ^Memory_Table:
		return len(r.order.rows), .Exact, true
	case ^Remote_Rows:
		return max(r.pages.count, 0), r.pages.kind, pages_known(&r.pages)
	}
	return 0, .Exact, true
}

// rows_loading reports whether rows src will show are on their way: a
// table's host still fetching them, a remote's page in view not yet in.
rows_loading :: proc(src: Rows) -> bool {
	switch r in src {
	case ^Memory_Table:
		return r.loading
	case ^Remote_Rows:
		return pages_loading(&r.pages)
	}
	return false
}

// rows_values is column col's distinct values for its Set filter, under
// the view's other filters and its search, and a version that moves when
// they change: values is nil while version is since, so a caller that
// keeps them copies each change once. A table counts them now, every
// value in natural order; a remote asks its fetch_values (Values_Query),
// whose source gives the most common first, at most 200, and loading
// says they are on their way or being refreshed; a remote without one
// has none.
rows_values :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Rows,
	col: int,
	since: u64,
) -> (
	values: []Value_Count,
	version: u64,
	loading: bool,
) {
	switch r in src {
	case ^Memory_Table:
		q := view_query(&g.view, cols, &g.visible)
		version = values_hash(q, col) ~ u64(len(r.rows)) ~ r.version << 32 | 1
		if version != since {
			values = distinct_values(r.rows, q, col, gtx.allocator)
		}
		return
	case ^Remote_Rows:
		if r.fetch_values == nil {
			return nil, since, false
		}
		q := values_query(gtx, g, cols, col, "")
		v, st, delivered := r.fetch_values(r.user, gtx, q)
		if v == nil || (st != .Ready && st != .Stale) {
			return nil, since, true
		}
		if delivered != since {
			values = v.values
		}
		return values, delivered, st == .Stale
	}
	return nil, since, false
}

// rows_retry asks again for the places from lo to hi whose page failed;
// only a remote's can.
@(private)
rows_retry :: proc(src: Rows, lo, hi: int) {
	if r, ok := src.(^Remote_Rows); ok {
		size := r.pages.page_size
		pages_retry(&r.pages, lo / size, hi / size + 1)
	}
}

// rows_held gathers the keys and key strings of the rows src holds in
// the current order, into keys and names: every row a table keeps, the
// rows a remote has loaded of the current query (current_only) or of any
// query it still caches.
@(private)
rows_held :: proc(
	src: Rows,
	keys: ^[dynamic]Row_Key,
	names: ^[dynamic]string,
	current_only: bool,
) {
	switch r in src {
	case ^Memory_Table:
		for row in r.order.rows {
			append(keys, row_key(r.rows[row].key))
			append(names, r.rows[row].key)
		}
	case ^Remote_Rows:
		for e in r.pages.entries {
			if current_only && (e.query != r.pages.query || e.state != .Ready) {
				continue
			}
			for pr in e.rows {
				append(keys, row_key(pr.key))
				append(names, pr.key)
			}
		}
	}
}

// rows_building reports whether a table is still building its next
// order, drawing the last one stale meanwhile.
@(private)
rows_building :: proc(src: Rows) -> bool {
	t, ok := src.(^Memory_Table)
	return ok && t.target != 0
}

// memory_table_item fills it with what stands at place i of t's order: a row, or
// a skeleton past them while t is loading.
@(private)
memory_table_item :: proc(t: ^Memory_Table, i: int, it: ^Item) {
	if i >= len(t.order.rows) {
		it.state = .Loading
		return
	}
	r := t.order.rows[i]
	pr := &t.rows[r]
	it.row, it.page_row, it.key, it.name = r, pr, row_key(pr.key), pr.key
	it.state = .Stale if t.target != 0 else .Ready
}
