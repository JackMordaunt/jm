package datagrid

import "core:slice"
import "core:time"

// A client grid's order: the rows its query keeps, sorted and grouped. A
// query change on rows that stay the same is built a slice at a time, so
// a sort, a filter or a search keystroke over 100,000 rows costs a frame
// no more than ORDER_BUDGET; the grid draws the order it had, stale,
// until the new one is whole. An order_build does the whole job at once.

// ORDER_BUDGET is how long one frame spends building an order.
ORDER_BUDGET :: 4 * time.Millisecond

// ORDER_CHUNK is how many rows a build step takes between looks at the
// clock.
@(private)
ORDER_CHUNK :: 512

// Group is a run of rows sharing the group column's text: where its text
// lies in Order.group_text (group_name reads it), how many rows, and
// where its header sits in Order.items.
Group :: struct {
	lo, hi: int,
	count:  int,
	item:   int,
}

// group_name is group g's text.
group_name :: proc(o: ^Order, g: Group) -> string {
	return string(o.group_text[g.lo:g.hi])
}

// Order is a client grid's rows as its query shows them: rows, the
// matching rows' indices in order, and items, what the grid draws, which
// is rows with a group header before each run when grouped (an item < 0
// is header -item-1), and a collapsed group's rows left out. The rest is
// a build's scratch, kept for its capacity.
Order :: struct {
	rows:       [dynamic]int,
	items:      [dynamic]int,
	groups:     [dynamic]Group,
	group_text: [dynamic]u8, // every group's text, end to end: a source's text may be the frame's
	key_nums:   [dynamic][dynamic]f64, // per sort key, each row's value
	key_ok:     [dynamic][dynamic]bool,
	key_bytes:  [dynamic][dynamic]u8, // per sort key, each row's text end to end
	key_spans:  [dynamic][dynamic][2]u32, // where each row's text lies in key_bytes
	pos, tmp:   [dynamic]i32, // the merge sort's two buffers of positions
}

order_destroy :: proc(o: ^Order) {
	delete(o.rows)
	delete(o.items)
	delete(o.groups)
	delete(o.group_text)
	for ki in 0 ..< len(o.key_nums) {
		delete(o.key_nums[ki])
		delete(o.key_ok[ki])
		delete(o.key_bytes[ki])
		delete(o.key_spans[ki])
	}
	delete(o.key_nums)
	delete(o.key_ok)
	delete(o.key_bytes)
	delete(o.key_spans)
	delete(o.pos)
	delete(o.tmp)
	o^ = {}
}

// Order_Job is an order's build in progress: the step it is at and where
// in it. A job is restarted (order_start) whenever what it builds for
// changes; the query, rows and collapsed groups each step is given must
// be the ones it started with.
Order_Job :: struct {
	phase: Order_Phase,
	at:    int, // the next row, position or item the phase takes
	key:   int, // the sort key Keys is reading
	width: int, // the merge sort's run width
	lo:    int, // where the pair being merged starts
	i, j:  int, // the pair's next positions, while merging one
	shut:  bool, // the group Items is in is collapsed
}

Order_Phase :: enum u8 {
	Filter, // keep the rows the filters and the search keep
	Keys, // read each sort key's cells
	Sort, // merge sort the kept rows' positions
	Items, // lay out the items, group headers included
	Done,
}

// order_build fills o with the rows of src that q matches, sorted by q's
// sort (stably: rows that tie keep their source order), grouped by q's
// group column with the groups in collapsed shut. It reads each sorted
// cell once.
order_build :: proc(o: ^Order, src: Source, q: Query, collapsed: map[string]bool = nil) {
	job: Order_Job
	order_start(&job, o)
	order_step(&job, o, src, q, collapsed, {})
}

// order_start readies job to build o from the beginning.
order_start :: proc(job: ^Order_Job, o: ^Order) {
	job^ = {}
	clear(&o.rows)
}

// order_step carries job on building o until it is done, true, or the
// clock passes deadline (the zero Tick: never), false.
order_step :: proc(
	job: ^Order_Job,
	o: ^Order,
	src: Source,
	q: Query,
	collapsed: map[string]bool,
	deadline: time.Tick,
) -> bool {
	keys := sort_keys(q)
	for job.phase != .Done {
		finished: bool
		switch job.phase {
		case .Filter:
			finished = filter_step(job, o, src, q, deadline)
		case .Keys:
			finished = len(keys) == 0 || keys_step(job, o, src, q.cols, keys, deadline)
		case .Sort:
			finished = len(keys) == 0 || sort_step(job, o, sorting(o, q.cols, keys), deadline)
		case .Items:
			finished = items_step(job, o, src, q.group, collapsed, deadline)
		case .Done:
		}
		if !finished {
			return false
		}
		job.phase = Order_Phase(int(job.phase) + 1)
		job.at = 0
	}
	return true
}

// past reports whether the clock has passed deadline, the zero Tick never.
@(private)
past :: proc(deadline: time.Tick) -> bool {
	return deadline != {} && time.tick_diff(deadline, time.tick_now()) > 0
}

// filter_step keeps the rows q matches, from job.at on.
@(private)
filter_step :: proc(
	job: ^Order_Job,
	o: ^Order,
	src: Source,
	q: Query,
	deadline: time.Tick,
) -> bool {
	sets := filter_sets(q.filters)
	n := max(src.rows, 0)
	for job.at < n {
		end := min(job.at + ORDER_CHUNK, n)
		for r in job.at ..< end {
			if row_matches(src, q, sets, r) {
				append(&o.rows, r)
			}
		}
		job.at = end
		if job.at < n && past(deadline) {
			return false
		}
	}
	return true
}

// sort_keys is the keys q's rows sort by: the group column first, in the
// direction the sort gives it, then the sort's other keys.
@(private)
sort_keys :: proc(q: Query) -> []Sort_Key {
	keys := make([dynamic]Sort_Key, 0, len(q.sort) + 1, context.temp_allocator)
	if q.group >= 0 {
		group := Sort_Key{q.group, false}
		for s in q.sort {
			group.desc = s.desc if s.col == q.group else group.desc
		}
		append(&keys, group)
	}
	for s in q.sort {
		if s.col != q.group {
			append(&keys, s)
		}
	}
	return keys[:]
}

// keys_step reads each sort key's cells for the kept rows into o's key
// arrays, a text copied so it outlives the frame its source made it in.
@(private)
keys_step :: proc(
	job: ^Order_Job,
	o: ^Order,
	src: Source,
	cols: []Column,
	keys: []Sort_Key,
	deadline: time.Tick,
) -> bool {
	for len(o.key_nums) < len(keys) {
		append(&o.key_nums, [dynamic]f64{})
		append(&o.key_ok, [dynamic]bool{})
		append(&o.key_bytes, [dynamic]u8{})
		append(&o.key_spans, [dynamic][2]u32{})
	}
	n := len(o.rows)
	for job.key < len(keys) {
		ki, col := job.key, keys[job.key].col
		kind := cols[col].kind
		if job.at == 0 {
			key_reset(o, ki, kind, n)
		}
		for job.at < n {
			end := min(job.at + ORDER_CHUNK, n)
			key_fill(o, src, kind, col, ki, job.at, end)
			job.at = end
			if job.at < n && past(deadline) {
				return false
			}
		}
		job.key += 1
		job.at = 0
		if job.key < len(keys) && past(deadline) {
			return false
		}
	}
	return true
}

// key_reset readies key ki's arrays for n rows of a column of kind.
@(private)
key_reset :: proc(o: ^Order, ki: int, kind: Value_Kind, n: int) {
	if kind == .Text {
		clear(&o.key_bytes[ki])
		clear(&o.key_spans[ki])
		return
	}
	resize(&o.key_nums[ki], n)
	resize(&o.key_ok[ki], n)
}

// key_fill reads key ki's column for the kept rows from lo to hi.
@(private)
key_fill :: proc(o: ^Order, src: Source, kind: Value_Kind, col, ki, lo, hi: int) {
	if kind != .Text {
		for i in lo ..< hi {
			o.key_nums[ki][i], o.key_ok[ki][i] = source_value(src, kind, o.rows[i], col)
		}
		return
	}
	bytes := &o.key_bytes[ki]
	for i in lo ..< hi {
		start := u32(len(bytes))
		append(bytes, source_text(src, o.rows[i], col))
		append(&o.key_spans[ki], [2]u32{start, u32(len(bytes))})
	}
}

// Sorting is what the sort's comparison reads: the keys and, per key,
// the kept rows' values or texts by position.
@(private)
Sorting :: struct {
	keys:  []Sort_Key,
	nums:  [][dynamic]f64,
	ok:    [][dynamic]bool,
	bytes: [][dynamic]u8,
	spans: [][dynamic][2]u32,
	text:  []bool, // per key: compare text, not numbers
}

// sorting is o's key arrays as the comparison reads them.
@(private)
sorting :: proc(o: ^Order, cols: []Column, keys: []Sort_Key) -> Sorting {
	s := Sorting {
		keys  = keys,
		nums  = o.key_nums[:len(keys)],
		ok    = o.key_ok[:len(keys)],
		bytes = o.key_bytes[:len(keys)],
		spans = o.key_spans[:len(keys)],
		text  = make([]bool, len(keys), context.temp_allocator),
	}
	for k, ki in keys {
		s.text[ki] = cols[k.col].kind == .Text
	}
	return s
}

// sort_step merge sorts the kept rows' positions bottom up, a pair of
// runs at a time and within one when the clock runs out, then puts the
// rows in that order. Merging keeps ties in their order, so the sort is
// stable.
@(private)
sort_step :: proc(job: ^Order_Job, o: ^Order, s: Sorting, deadline: time.Tick) -> bool {
	n := len(o.rows)
	if job.width == 0 {
		resize(&o.pos, n)
		resize(&o.tmp, n)
		for i in 0 ..< n {
			o.pos[i] = i32(i)
		}
		job.width, job.lo, job.i, job.j = 1, 0, -1, -1
	}
	s := s
	for job.width < n {
		for job.lo < n {
			if !merge_pair(job, o, &s, deadline) {
				return false
			}
			job.lo += 2 * job.width
		}
		o.pos, o.tmp = o.tmp, o.pos
		job.width *= 2
		job.lo = 0
	}
	sorted := make([]int, n, context.temp_allocator)
	for p, i in o.pos[:n] {
		sorted[i] = o.rows[p]
	}
	copy(o.rows[:], sorted)
	return true
}

// merge_pair merges the runs at job.lo, of job.width each, from o.pos
// into o.tmp, picking up where it stopped; false when the clock ran out
// first.
@(private)
merge_pair :: proc(job: ^Order_Job, o: ^Order, s: ^Sorting, deadline: time.Tick) -> bool {
	n := len(o.pos)
	mid, hi := min(job.lo + job.width, n), min(job.lo + 2 * job.width, n)
	if job.i < 0 {
		job.i, job.j = job.lo, mid
	}
	from, into := o.pos[:], o.tmp[:]
	for k := job.i + job.j - mid; k < hi; k += 1 {
		take_right :=
			job.i >= mid || (job.j < hi && compare_positions(from[job.j], from[job.i], s) == .Less)
		if take_right {
			into[k] = from[job.j]
			job.j += 1
		} else {
			into[k] = from[job.i]
			job.i += 1
		}
		if k % ORDER_CHUNK == ORDER_CHUNK - 1 && k + 1 < hi && past(deadline) {
			return false
		}
	}
	job.i, job.j = -1, -1
	return true
}

// compare_positions orders two positions by every key in turn, a value
// that is not one (an empty cell) after every value whichever way the
// key runs, and by position to break a full tie.
@(private)
compare_positions :: proc(a, b: i32, s: ^Sorting) -> slice.Ordering {
	for k, ki in s.keys {
		c, blank := compare_key(s, ki, a, b)
		if c == 0 {
			continue
		}
		if k.desc && !blank {
			c = -c
		}
		return .Less if c < 0 else .Greater
	}
	switch {
	case a < b:
		return .Less
	case a > b:
		return .Greater
	}
	return .Equal
}

// compare_key orders positions a and b by key ki, and reports whether
// just one of them is blank, which a descending key does not flip.
@(private)
compare_key :: proc(s: ^Sorting, ki: int, a, b: i32) -> (c: int, blank: bool) {
	if s.text[ki] {
		sa, sb := s.spans[ki][a], s.spans[ki][b]
		ta, tb := string(s.bytes[ki][sa[0]:sa[1]]), string(s.bytes[ki][sb[0]:sb[1]])
		return compare_natural(ta, tb), (ta == "") != (tb == "")
	}
	na, nb := s.nums[ki][a], s.nums[ki][b]
	c = compare_numbers(na, s.ok[ki][a], nb, s.ok[ki][b])
	return c, (s.ok[ki][a] && na == na) != (s.ok[ki][b] && nb == nb)
}

// compare_numbers orders two values, one that is not a value (ok false,
// or NaN) last.
@(private)
compare_numbers :: proc(a: f64, ok_a: bool, b: f64, ok_b: bool) -> int {
	has_a := ok_a && a == a
	has_b := ok_b && b == b
	if has_a != has_b {
		return -1 if has_a else 1
	}
	if !has_a || a == b {
		return 0
	}
	return -1 if a < b else 1
}

// items_step lays out what the grid draws from o.rows, from job.at on:
// the rows, or with a group column a header before each run of equal
// text and the rows of a group in collapsed left out.
@(private)
items_step :: proc(
	job: ^Order_Job,
	o: ^Order,
	src: Source,
	group: int,
	collapsed: map[string]bool,
	deadline: time.Tick,
) -> bool {
	if job.at == 0 {
		clear(&o.items)
		clear(&o.groups)
		clear(&o.group_text)
	}
	if group < 0 {
		append(&o.items, ..o.rows[:])
		return true
	}
	n := len(o.rows)
	for job.at < n {
		end := min(job.at + ORDER_CHUNK, n)
		for i in job.at ..< end {
			item_add(job, o, source_text(src, o.rows[i], group), o.rows[i], collapsed)
		}
		job.at = end
		if job.at < n && past(deadline) {
			return false
		}
	}
	return true
}

// item_add lays out row r, whose group text is t: a header first when t
// starts a group, then the row unless its group is shut.
@(private)
item_add :: proc(job: ^Order_Job, o: ^Order, t: string, r: int, collapsed: map[string]bool) {
	if len(o.groups) == 0 || t != group_name(o, o.groups[len(o.groups) - 1]) {
		lo := len(o.group_text)
		append(&o.group_text, t)
		append(&o.groups, Group{lo = lo, hi = len(o.group_text), item = len(o.items)})
		append(&o.items, -len(o.groups))
		job.shut = collapsed[t]
	}
	o.groups[len(o.groups) - 1].count += 1
	if !job.shut {
		append(&o.items, r)
	}
}
