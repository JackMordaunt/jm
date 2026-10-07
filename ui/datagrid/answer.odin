package datagrid

import "core:mem"
import "core:slice"
import "core:strings"

// Memory_Table answers a paged grid's requests from rows held in memory,
// as a server would: the same filters, search and sort a client grid
// applies (order_build), then the page by offset or by keyset cursor. A
// host that has every row but wants the grid to page them uses it, as
// do the kitchen's simulated source and the tests' reference server.
//
// Its search looks in every column a request names, where a client grid
// looks in its visible columns: a server does not know which are shown.
Memory_Table :: struct {
	cols:      []Column,
	rows:      []Page_Row,
	order:     Order,
	built:     u64, // the order hash order was built for, 0 for none
	place:     map[string]int, // a row's key to its place in order, for a cursor
	allocator: mem.Allocator,
}

// memory_table_init readies t over rows, whose cells come in the order of
// cols, as a request's columns name them. t keeps both, not copies.
memory_table_init :: proc(
	t: ^Memory_Table,
	cols: []Column,
	rows: []Page_Row,
	allocator := context.allocator,
) {
	t.cols, t.rows, t.allocator = cols, rows, allocator
	t.order.rows = make([dynamic]int, allocator)
	t.place = make(map[string]int, allocator)
}

memory_table_destroy :: proc(t: ^Memory_Table) {
	order_destroy(&t.order)
	delete(t.place)
	t^ = {}
}

// answer_page is the page q asks for, its rows pointing into t's and its
// slice in allocator, with the exact count of rows that match.
answer_page :: proc(t: ^Memory_Table, q: Page_Query, allocator := context.allocator) -> Page {
	n := memory_order(t, q.sort, q.filters, q.search)
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
		v := memory_cell(t, r, col)
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

// memory_cell is column col of row r, "" past its cells.
@(private)
memory_cell :: proc(t: ^Memory_Table, r, col: int) -> string {
	cells := t.rows[r].cells
	return cells[col] if col < len(cells) else ""
}

// memory_order orders t's rows by a request's sort, filters and search,
// unless they are what it was ordered by last, and returns how many
// match. A sort or filter naming no column of t is left out.
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
	h := order_hash(q) | 1
	if h == t.built {
		return len(t.order.rows)
	}
	src := Source {
		user = t,
		rows = len(t.rows),
		text = proc(user: rawptr, row, col: int) -> string {
			return memory_cell((^Memory_Table)(user), row, col)
		},
	}
	order_build(&t.order, src, q)
	clear(&t.place)
	for r, i in t.order.rows {
		t.place[t.rows[r].key] = i
	}
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
