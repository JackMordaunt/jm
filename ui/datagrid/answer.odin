package datagrid

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:time"
import "jm:ui"

// Memory_Table is rows held in memory, ordered by a query: the rows a
// grid shows when it has every one (Rows), or a server's answers to a
// paged grid's requests (answer_page, answer_values), as the kitchen's
// simulated source and the tests' reference server use it.
//
// t borrows cols and rows, which must stay as they are until
// memory_table_changed says they moved: an order a grid builds a slice a
// frame reads the rows' strings across frames. Every row needs a key,
// unique in the table: a grid keeps its selection, and a server its
// keyset cursor, by it. One table orders rows for one grid; two grids
// over the same rows each take a table over them.
//
// heights, when set, is each row's own height, by row; loading says more
// rows are on their way, as when a host fetches every row before showing
// any, and a grid draws a view of skeleton rows after the rows it has.
//
// A grid's search looks in its visible columns; a server's in every
// column a request names, as a server does not know which are shown.
Memory_Table :: struct {
	cols:      []Column,
	rows:      []Page_Row,
	heights:   []f32,
	loading:   bool,
	version:   u64, // moved by memory_table_changed
	order:     Order,
	built:     u64, // what order was built for, 0 for nothing
	place:     map[string]int, // a row's key to its place in order, for a cursor
	placed:    u64, // what place was made for
	next:      Order, // the next order, built a slice a frame while order is shown
	job:       Order_Job,
	target:    u64, // what next is for, 0 when nothing is building
	data:      u64, // the rows order was built from: their version, count and loading
	allocator: mem.Allocator,
}

// memory_table_init readies t over rows, whose cells come in the order of
// cols, as a grid's columns and a request's columns name them. t keeps
// both, not copies.
memory_table_init :: proc(
	t: ^Memory_Table,
	cols: []Column,
	rows: []Page_Row,
	allocator := context.allocator,
) {
	t.cols, t.rows, t.allocator = cols, rows, allocator
	t.order.rows = make([dynamic]int, allocator)
	t.next.rows = make([dynamic]int, allocator)
	t.place = make(map[string]int, allocator)
	check_keys(rows)
}

// rows_of is cells as a table's rows, each keyed by its text in column
// key: the rows' cells are slices of cells, which must outlive them; the
// slice of rows is in allocator.
rows_of :: proc(cells: [][$N]string, key: int, allocator := context.allocator) -> []Page_Row {
	out := make([]Page_Row, len(cells), allocator)
	for &c, i in cells {
		out[i] = {c[key], c[:]}
	}
	return out
}

memory_table_destroy :: proc(t: ^Memory_Table) {
	order_destroy(&t.order)
	order_destroy(&t.next)
	delete(t.place)
	t^ = {}
}

// memory_table_view is t's rows, the places of its current view in
// order (indices into rows), and the version of the rows, which
// memory_table_changed moves. order is t's own: a new order replaces it.
memory_table_view :: proc(t: ^Memory_Table) -> (rows: []Page_Row, order: []int, version: u64) {
	return t.rows, t.order.rows[:], t.version
}

// memory_table_changed takes rows as t's rows, the same slice changed in
// place or another: the order is built again, at once, and a grid over t
// measures its columns again.
memory_table_changed :: proc(t: ^Memory_Table, rows: []Page_Row) {
	t.rows = rows
	t.version += 1
	check_keys(rows)
}

// check_keys fails on a row without a key, and in a debug build on two
// rows with one key, which would select or page as one row.
@(private)
check_keys :: proc(rows: []Page_Row) {
	for r, i in rows {
		fmt.assertf(r.key != "", "Memory_Table: row %d has no key; give every row a unique key", i)
	}
	when ODIN_DEBUG {
		seen := make(map[string]int, len(rows), context.temp_allocator)
		for r, i in rows {
			at, dup := seen[r.key]
			fmt.assertf(!dup, "Memory_Table: rows %d and %d share the key %q", at, i, r.key)
			seen[r.key] = i
		}
	}
}

// memory_table_step brings t's order to q, a grid's query: at once the first
// time and when the rows changed, else a slice of it until deadline (the
// zero Tick: no limit). done reports whether order is q's; swapped
// whether it became so in this call.
@(private)
memory_table_step :: proc(
	t: ^Memory_Table,
	q: Query,
	deadline: time.Tick,
) -> (
	done, swapped: bool,
) {
	data := ui.fnv_u64(ui.fnv_u64(t.version, u64(len(t.rows))), u64(t.loading))
	key := ui.fnv_u64(ui.fnv_u64(order_hash(q), visible_hash(q.visible)), data) | 1
	if key == t.built {
		t.target = 0 // back to the order shown: what was building is not wanted
		return true, false
	}
	if t.built == 0 || data != t.data {
		t.target, t.data = 0, data
		order_build(&t.order, t.rows, q)
	} else {
		if t.target != key {
			t.target = key
			order_start(&t.job, &t.next)
		}
		if !order_step(&t.job, &t.next, t.rows, q, deadline) {
			return false, false
		}
		t.order, t.next = t.next, t.order
		t.target = 0
	}
	t.built = key
	return true, true
}

// visible_hash names the columns a search looks in.
@(private)
visible_hash :: proc(visible: []int) -> u64 {
	h := ui.FNV_OFFSET
	for c in visible {
		h = ui.fnv_u64(h, u64(c))
	}
	return h
}

// answer_page is the page q asks for, its rows pointing into t's and its
// slice in allocator, with the exact count of rows that match.
answer_page :: proc(t: ^Memory_Table, q: Page_Query, allocator := context.allocator) -> Page {
	n := memory_order(t, q.sort, q.filters, q.search)
	if t.placed != t.built {
		clear(&t.place)
		for r, i in t.order.rows {
			t.place[t.rows[r].key] = i
		}
		t.placed = t.built
	}
	start := max(q.offset, 0)
	if q.after.key != "" {
		if at, ok := t.place[q.after.key]; ok {
			start = at + 1
		}
	}
	start = min(start, n)
	end := min(start + max(q.limit, 0), n)
	out := make([]Page_Row, end - start, allocator)
	for r, i in t.order.rows[start:end] {
		out[i] = t.rows[r]
	}
	return {rows = out, total = n, total_kind = .Exact}
}

// answer_values is the distinct values q asks for, counted under the other
// filters and the search and kept to those containing q.like, the most
// common first, at most q.limit of them; in allocator.
answer_values :: proc(
	t: ^Memory_Table,
	q: Values_Query,
	allocator := context.allocator,
) -> Values {
	col := column_index(t.cols, q.column)
	if col < 0 {
		return {error = "no such column"}
	}
	memory_order(t, nil, q.filters, q.search)
	counts := make(map[string]int, 64, context.temp_allocator)
	for r in t.order.rows {
		v := row_text(t.rows, r, col)
		if contains_fold(v, q.like) {
			counts[v] += 1
		}
	}
	all := make([dynamic]Value_Count, 0, len(counts), context.temp_allocator)
	for v, c in counts {
		append(&all, Value_Count{v, c})
	}
	slice.sort_by(all[:], proc(a, b: Value_Count) -> bool {
		if a.count != b.count {
			return a.count > b.count
		}
		return compare_natural(a.value, b.value) < 0
	})
	keep := len(all) if q.limit <= 0 else min(q.limit, len(all))
	out := make([]Value_Count, keep, allocator)
	for v, i in all[:keep] {
		out[i] = {strings.clone(v.value, allocator), v.count}
	}
	return {values = out}
}

// memory_order orders t's rows by a request's sort, filters and search,
// at once, unless they are what it was ordered by last, and returns how
// many match. A sort or filter naming no column of t is left out.
@(private)
memory_order :: proc(
	t: ^Memory_Table,
	sort: []Query_Sort,
	filters: []Query_Filter,
	search: string,
) -> int {
	all := make([]int, len(t.cols), context.temp_allocator)
	for _, i in t.cols {
		all[i] = i
	}
	q := Query {
		cols    = t.cols,
		sort    = memory_sort(t, sort),
		filters = memory_filters(t, filters),
		search  = search,
		visible = all,
	}
	h := ui.fnv_u64(order_hash(q), t.version) | 1
	if h == t.built {
		return len(t.order.rows)
	}
	order_build(&t.order, t.rows, q)
	t.target = 0
	t.built = h
	return len(t.order.rows)
}

@(private)
memory_sort :: proc(t: ^Memory_Table, sort: []Query_Sort) -> []Sort_Key {
	out := make([dynamic]Sort_Key, 0, len(sort), context.temp_allocator)
	for s in sort {
		if c := column_index(t.cols, s.column); c >= 0 {
			append(&out, Sort_Key{c, s.desc})
		}
	}
	return out[:]
}

@(private)
memory_filters :: proc(t: ^Memory_Table, filters: []Query_Filter) -> []Filter {
	out := make([dynamic]Filter, 0, len(filters), context.temp_allocator)
	for f in filters {
		c := column_index(t.cols, f.column)
		if c < 0 {
			continue
		}
		rule := f.rule
		if s, is_set := rule.(Set_Filter); is_set {
			sorted := slice.clone(s.values, context.temp_allocator)
			slice.sort(sorted)
			rule = Set_Filter{sorted}
		}
		append(&out, Filter{c, rule})
	}
	return out[:]
}
