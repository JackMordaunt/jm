package datagrid

import "core:mem"

// A paged grid holds a window of a table too big to load: it asks for
// pages of rows near the view by need, keeps a bounded cache of what
// arrived, and draws a skeleton where a row has not.
//
// The page request (Page_Query) carries the whole query, so it works for
// both ways a server pages. An offset server reads offset and limit. A
// keyset server reads after as well: the key and sort values of the row
// before the page, when the grid has that row (it does for every page
// but one it jumped to); without it a keyset server falls back to the
// offset. after is fixed when the page is first asked for, so the need's
// key does not change under the host when the page before arrives.
//
// The pure half is here: which pages to want (pages_window), what to do
// with one that arrives (pages_arrive), what to evict (pages_evict) and
// what a row shows (pages_row). The grid's frame turns the wanted pages
// into needs and their answers into arrivals.

// Paging is a paged source's settings. source names the table to the
// host, which may serve several. A page is page_size rows; margin pages
// either side of those in view are wanted too, so a scroll finds them
// loaded; at most capacity pages are cached, the farthest from the view
// evicted first. On a new query (a sort, a filter, the search) the old
// pages go, or with keep_stale stay drawn, dimmed, until the new ones
// arrive. estimate is a row count to show before the first page says.
Paging :: struct {
	source:     string,
	page_size:  int,
	margin:     int,
	capacity:   int,
	keep_stale: bool,
	estimate:   int,
}

// Count_Kind is how much the grid knows of the row count. Unknown grows
// as pages arrive, one page of skeleton past the last full one, until a
// short page shows where the rows end; Estimated is a count the source
// guessed, as PostgREST's estimated count is (its reference on
// pagination and count, section "Estimated Count", read 2026-10-05);
// Exact is the count.
Count_Kind :: enum u8 {
	Unknown,
	Estimated,
	Exact,
}

// Query_Sort and Query_Filter are a sort key and a filter as a page
// request carries them: columns by id.
Query_Sort :: struct {
	column: string,
	desc:   bool,
}

Query_Filter :: struct {
	column:         string,
	kind:           Filter_Kind,
	values:         []string,
	text:           string,
	lo, hi:         f64,
	has_lo, has_hi: bool,
}

// Cursor is the row before a page, for a keyset server: its key, and its
// text in each sort column, in the sort's order. An empty key is no
// cursor.
Cursor :: struct {
	key:    string,
	values: []string,
}

// Page_Query is a page request, the need a paged grid records for each
// page it wants: the source, every column's id in declared order (the
// order a page's cells come in), the query, which rows (offset and
// limit), the keyset cursor when the grid has it, and attempt, which a
// retry bumps so a failed page is asked for afresh.
Page_Query :: struct {
	source:  string,
	columns: []string,
	sort:    []Query_Sort,
	filters: []Query_Filter,
	search:  string,
	offset:  int,
	limit:   int,
	after:   Cursor,
	attempt: int,
}

// Page_Row is one row of a page: its key, unique in the table, and its
// cells' text, one per column in Page_Query.columns' order.
Page_Row :: struct {
	key:   string,
	cells: []string,
}

// Page answers a Page_Query: up to limit rows, fewer only at the table's
// end; the row count when the host knows it (total_kind); or error when
// the page could not be had, which the grid shows on its rows with a
// retry.
Page :: struct {
	rows:       []Page_Row,
	total:      int,
	total_kind: Count_Kind,
	error:      string,
}

// Values_Query asks for a column's distinct values among the rows that
// pass the other filters and the search, for its Set filter, matching
// like: Values answers it, the most common first or as the host likes,
// at most limit of them.
Values_Query :: struct {
	source:  string,
	column:  string,
	filters: []Query_Filter,
	search:  string,
	like:    string,
	limit:   int,
}

Values :: struct {
	values: []Value_Count,
	error:  string,
}

// Row_State is what a paged row shows: nothing yet (Missing, before it is
// asked for, or past the end), a skeleton while its page loads, the row
// (Ready), the row dimmed while it is refreshed or stands in for a new
// query's (Stale), or its page's error (Failed).
Row_State :: enum u8 {
	Missing,
	Loading,
	Ready,
	Stale,
	Failed,
}

// Page_State is a cached page's.
Page_State :: enum u8 {
	Loading,
	Ready,
	Failed,
}

// Cached_Page is a page the grid holds: under which query, which page,
// its state, its rows and what they point into, the cursor it was asked
// with, its attempt, its error, the delivery it was copied from and the
// tick it was last wanted. stale says it is being refreshed.
Cached_Page :: struct {
	query:      u64,
	index:      int,
	state:      Page_State,
	stale:      bool,
	rows:       []Page_Row,
	cells:      []string,
	text:       []u8,
	after:      Cursor,
	after_text: []u8,
	attempt:    int,
	error:      string,
	version:    u64,
	wanted:     u64,
}

// Pages is a paged grid's cache: the current query's hash, the row
// count and how much is known of it, whether a short page fixed the end,
// the pages, and the tick that ages them.
Pages :: struct {
	using config: Paging,
	query:        u64,
	count:        int,
	kind:         Count_Kind,
	end:          bool,
	entries:      [dynamic]Cached_Page,
	tick:         u64,
	wanted:       [2]int, // the pages last wanted, [lo, hi)
	allocator:    mem.Allocator,
}

// pages_init readies p for config, its zero settings taken as defaults:
// pages of 100, two either side, 32 cached.
pages_init :: proc(p: ^Pages, config: Paging, allocator := context.allocator) {
	p.config = config
	p.page_size = config.page_size > 0 ? config.page_size : 100
	p.margin = config.margin > 0 ? config.margin : 2
	p.capacity = config.capacity > 0 ? config.capacity : 32
	p.allocator = allocator
	p.entries = make([dynamic]Cached_Page, allocator)
	reset_count(p)
}

pages_destroy :: proc(p: ^Pages) {
	for &e in p.entries {
		page_free(p, &e)
	}
	delete(p.entries)
	p^ = {}
}

@(private)
reset_count :: proc(p: ^Pages) {
	p.end = false
	if p.estimate > 0 {
		p.count, p.kind = p.estimate, .Estimated
	} else {
		p.count, p.kind = p.page_size, .Unknown
	}
}

@(private)
page_free :: proc(p: ^Pages, e: ^Cached_Page) {
	delete(e.rows, p.allocator)
	delete(e.cells, p.allocator)
	delete(e.text, p.allocator)
	delete(e.after.values, p.allocator)
	delete(e.after_text, p.allocator)
	delete(e.error, p.allocator)
	e^ = {}
}

// pages_query makes query the current one and reports whether it is
// new. A new query drops the cached pages, or with keep_stale keeps them
// to stand in, dimmed, until the new query's arrive; either way the count
// starts over.
pages_query :: proc(p: ^Pages, query: u64) -> bool {
	if query == p.query {
		return false
	}
	p.query = query
	if !p.keep_stale {
		for &e in p.entries {
			page_free(p, &e)
		}
		clear(&p.entries)
		reset_count(p)
		return true
	}
	// The old count stands in too: the new query's is likely close.
	p.end = false
	if p.kind == .Exact {
		p.kind = .Estimated
	}
	return true
}

// pages_known reports whether the count says anything of the current
// query: a page of it has arrived, or the caller's estimate stands. Until
// then the count is only room for a page of skeletons (or the last
// query's), and a caller must not show it as the rows' number.
pages_known :: proc(p: ^Pages) -> bool {
	for e in p.entries {
		if page_held(p, e) {
			return true
		}
	}
	return p.estimate > 0 && p.kind == .Estimated && p.count == p.estimate
}

// pages_loading reports whether a page of the current query in the
// window is still on its way.
pages_loading :: proc(p: ^Pages) -> bool {
	for i in p.wanted[0] ..< p.wanted[1] {
		if e := pages_find(p, p.query, i); e == nil || e.state == .Loading {
			return true
		}
	}
	return false
}

// pages_find is page index of query, nil when it is not cached.
pages_find :: proc(p: ^Pages, query: u64, index: int) -> ^Cached_Page {
	for &e in p.entries {
		if e.query == query && e.index == index {
			return &e
		}
	}
	return nil
}

// pages_limit is one past the last page there can be.
pages_limit :: proc(p: ^Pages) -> int {
	return (max(p.count, 0) + p.page_size - 1) / p.page_size
}

// pages_window is the pages to want, [lo, hi), for rows first to last
// (exclusive) in view: their pages and margin more either side, none
// past the last page there can be, and always at least one page so an
// empty table is still asked about.
pages_window :: proc(p: ^Pages, first, last: int) -> (lo, hi: int) {
	size := p.page_size
	view_lo := max(first, 0) / size
	view_hi := max(last - 1, first, 0) / size
	limit := max(pages_limit(p), 1)
	lo = clamp(view_lo - p.margin, 0, limit - 1)
	hi = clamp(view_hi + p.margin + 1, lo + 1, limit)
	return
}

// pages_want marks pages [lo, hi) of the current query wanted at a new
// tick, making a Loading entry for each not cached, with the cursor of
// the row before it when that row is held.
pages_want :: proc(p: ^Pages, lo, hi: int, sort_cols: []int) {
	p.tick += 1
	p.wanted = {lo, hi}
	for i in lo ..< hi {
		e := pages_find(p, p.query, i)
		if e == nil {
			append(&p.entries, Cached_Page{query = p.query, index = i, state = .Loading})
			e = &p.entries[len(p.entries) - 1]
			e.after, e.after_text = cursor_before(p, i, sort_cols)
		}
		e.wanted = p.tick
	}
}

// cursor_before is the last row of page index-1 as a cursor, copied,
// when that page is held and ready.
@(private)
cursor_before :: proc(p: ^Pages, index: int, sort_cols: []int) -> (c: Cursor, text: []u8) {
	if index == 0 {
		return
	}
	prev := pages_find(p, p.query, index - 1)
	if prev == nil || prev.state != .Ready || len(prev.rows) == 0 {
		return
	}
	return cursor_of(prev.rows[len(prev.rows) - 1], sort_cols, p.allocator)
}

// cursor_of is row r as a cursor: its key and its text in each sort
// column, copied into one block, text, in allocator.
@(private)
cursor_of :: proc(
	r: Page_Row,
	sort_cols: []int,
	allocator: mem.Allocator,
) -> (
	c: Cursor,
	text: []u8,
) {
	n := len(r.key)
	for col in sort_cols {
		n += len(r.cells[col]) if col < len(r.cells) else 0
	}
	text = make([]u8, n, allocator)
	c.values = make([]string, len(sort_cols), allocator)
	at := copy(text, r.key)
	c.key = string(text[:at])
	for col, i in sort_cols {
		if col < len(r.cells) {
			k := copy(text[at:], r.cells[col])
			c.values[i] = string(text[at:at + k])
			at += k
		}
	}
	return
}

// pages_arrive takes page index of query as delivered (version names the
// delivery, so the same one is not copied twice) and reports whether it
// was taken: a page for another query never is. refreshing marks it
// stale: the host has it but is getting it again. It copies the rows, so
// the delivery may go, and moves the count.
pages_arrive :: proc(
	p: ^Pages,
	query: u64,
	index: int,
	pg: ^Page,
	version: u64,
	refreshing := false,
) -> bool {
	if query != p.query || index < 0 {
		return false
	}
	e := pages_find(p, query, index)
	if e == nil {
		append(&p.entries, Cached_Page{query = query, index = index})
		e = &p.entries[len(p.entries) - 1]
	}
	e.stale = refreshing
	if e.version == version && e.state != .Loading {
		return true
	}
	e.version = version
	delete(e.error, p.allocator)
	e.error = ""
	if pg.error != "" {
		e.state = .Failed
		e.error = clone_to(pg.error, p.allocator)
		return true
	}
	copy_rows(p, e, pg.rows)
	e.state = .Ready
	update_count(p, index, len(pg.rows), pg.total, pg.total_kind)
	return true
}

// clone_to copies s into allocator.
@(private)
clone_to :: proc(s: string, allocator: mem.Allocator) -> string {
	out := make([]u8, len(s), allocator)
	copy(out, s)
	return string(out)
}

// copy_rows replaces e's rows with a copy of rows: three allocations,
// the rows, their cells and one block of text.
@(private)
copy_rows :: proc(p: ^Pages, e: ^Cached_Page, rows: []Page_Row) {
	delete(e.rows, p.allocator)
	delete(e.cells, p.allocator)
	delete(e.text, p.allocator)
	bytes, cells := 0, 0
	for r in rows {
		bytes += len(r.key)
		cells += len(r.cells)
		for c in r.cells {
			bytes += len(c)
		}
	}
	e.rows = make([]Page_Row, len(rows), p.allocator)
	e.cells = make([]string, cells, p.allocator)
	e.text = make([]u8, bytes, p.allocator)
	at, ci := 0, 0
	keep :: proc(text: []u8, at: ^int, s: string) -> string {
		n := copy(text[at^:], s)
		out := string(text[at^:at^ + n])
		at^ += n
		return out
	}
	for r, i in rows {
		e.rows[i].key = keep(e.text, &at, r.key)
		e.rows[i].cells = e.cells[ci:ci + len(r.cells)]
		for c in r.cells {
			e.cells[ci] = keep(e.text, &at, c)
			ci += 1
		}
	}
}

// update_count moves the count for page index arriving with n rows and
// the host's total of kind. A full page believes an exact total, keeps
// an estimate unless the rows outrun it, and with no total runs the
// count one page past it; then the pages held say where the rows end
// (settle_end).
@(private)
update_count :: proc(p: ^Pages, index, n, total: int, kind: Count_Kind) {
	size := p.page_size
	extent := index * size + n
	if n == size && !p.end {
		switch kind {
		case .Exact:
			p.count, p.kind = max(total, extent), .Exact
		case .Estimated:
			p.count, p.kind = max(total, extent), .Estimated
		case .Unknown:
			if p.kind == .Unknown {
				p.count = max(p.count, extent + size)
			} else {
				p.count = max(p.count, extent)
			}
		}
	}
	settle_end(p)
}

// settle_end finds where the rows end from the current query's pages
// held. A short page past the last full one ends them exactly, as does
// an empty one right after it or first of all; an empty one further on
// says only that they end at or before it. A full page past a found end
// says the rows grew, and the end is looked for again.
@(private)
settle_end :: proc(p: ^Pages) {
	size := p.page_size
	last_full := last_full_page(p)
	if p.end && (last_full + 1) * size > p.count {
		p.end = false
	}
	for e in p.entries {
		if !page_held(p, e) || len(e.rows) >= size || e.index < last_full {
			continue
		}
		extent := e.index * size + len(e.rows)
		if ends_rows(e, last_full) {
			p.count, p.kind, p.end = extent, .Exact, true
			return
		}
		p.count = min(p.count, extent)
	}
}

// ends_rows reports whether e, a short page past the last full one, ends
// the rows where it does: it holds rows, or it is empty right after the
// last full page or first of all.
@(private)
ends_rows :: proc(e: Cached_Page, last_full: int) -> bool {
	return len(e.rows) > 0 || e.index == last_full + 1
}

// last_full_page is the index of the last full page of the current query
// held, -1 for none.
@(private)
last_full_page :: proc(p: ^Pages) -> int {
	last := -1
	for e in p.entries {
		if page_held(p, e) && len(e.rows) == p.page_size {
			last = max(last, e.index)
		}
	}
	return last
}

// page_held reports whether e is a page of the current query that has
// arrived.
@(private)
page_held :: proc(p: ^Pages, e: Cached_Page) -> bool {
	return e.query == p.query && e.state == .Ready
}

// pages_evict keeps at most capacity pages, never fewer than the window
// [lo, hi) of the current query: it drops a stand-in page whose own page
// has arrived, then the cached page farthest from the window, a stand-in
// before any current page.
pages_evict :: proc(p: ^Pages, lo, hi: int) {
	drop_replaced(p)
	keep := max(p.capacity, hi - lo)
	for len(p.entries) > keep {
		worst, far := -1, -1
		for e, i in p.entries {
			if d := distance(p, e, lo, hi); d > far {
				worst, far = i, d
			}
		}
		if far <= 0 {
			return
		}
		page_drop(p, worst)
	}
}

// drop_replaced drops every stand-in whose own page has arrived or
// failed.
@(private)
drop_replaced :: proc(p: ^Pages) {
	for i := len(p.entries) - 1; i >= 0; i -= 1 {
		e := &p.entries[i]
		if e.query == p.query {
			continue
		}
		if own := pages_find(p, p.query, e.index); own != nil && own.state != .Loading {
			page_drop(p, i)
		}
	}
}

// distance is how far e lies outside [lo, hi): 0 inside, and a stand-in
// for another query farther than any page of this one.
@(private)
distance :: proc(p: ^Pages, e: Cached_Page, lo, hi: int) -> int {
	if e.query != p.query {
		return max(int) / 2 - e.index
	}
	switch {
	case e.index < lo:
		return lo - e.index
	case e.index >= hi:
		return e.index - hi + 1
	}
	return 0
}

@(private)
page_drop :: proc(p: ^Pages, i: int) {
	page_free(p, &p.entries[i])
	unordered_remove(&p.entries, i)
}

// pages_row is row i of the current query and what it shows: the row,
// Ready or Stale while refreshed; a stand-in from the last query, Stale;
// the page's error, Failed; Loading for a page asked for; Missing for one
// not asked for or past the rows it holds. The row and page pointers are
// valid until the cache next changes.
pages_row :: proc(p: ^Pages, i: int) -> (row: ^Page_Row, state: Row_State, page: ^Cached_Page) {
	if i < 0 {
		return nil, .Missing, nil
	}
	index := i / p.page_size
	k := i - index * p.page_size
	e := pages_find(p, p.query, index)
	if e != nil && e.state != .Loading {
		return held_row(e, k)
	}
	if p.keep_stale {
		if old := stand_in(p, index, k); old != nil {
			return &old.rows[k], .Stale, old
		}
	}
	return nil, .Loading if e != nil else .Missing, e
}

// held_row is row k of page e, which has arrived or failed.
@(private)
held_row :: proc(e: ^Cached_Page, k: int) -> (^Page_Row, Row_State, ^Cached_Page) {
	switch {
	case e.state == .Failed:
		return nil, .Failed, e
	case k >= len(e.rows):
		return nil, .Missing, e
	}
	return &e.rows[k], .Stale if e.stale else .Ready, e
}

// stand_in is a page of another query that holds row k of page index, to
// stand in until the current query's arrives; nil when none does.
@(private)
stand_in :: proc(p: ^Pages, index, k: int) -> ^Cached_Page {
	for &old in p.entries {
		if old.query != p.query && old.index == index && old.state == .Ready && k < len(old.rows) {
			return &old
		}
	}
	return nil
}

// pages_retry asks again for every failed page in [lo, hi): a new
// attempt is a new request.
pages_retry :: proc(p: ^Pages, lo, hi: int) {
	for &e in p.entries {
		if e.query == p.query && e.state == .Failed && e.index >= lo && e.index < hi {
			e.state = .Loading
			e.attempt += 1
		}
	}
}
