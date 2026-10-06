package datagrid

import "core:slice"
import "core:strconv"
import "core:strings"
import "jm:ui"

// The query: which rows show, in what order. A client grid applies it to
// the rows in memory (order_build); a paged grid sends it to its source
// in every page request, and the rows come back already matched and
// ordered. Both hash it the same way, so a change to the filters, the
// search or the sort is a new query in either.

// Sort_Key is one level of a sort: the column and its direction. A sort
// is a list of them, the first deciding and each later one breaking the
// ties left.
Sort_Key :: struct {
	col:  int,
	desc: bool,
}

// Filter is one column's filter. Set keeps the rows whose text is one of
// values, kept sorted; Text the rows whose text contains text, without
// case; Range the rows whose value is at least lo (when has_lo) and at
// most hi (when has_hi). A filter with nothing chosen keeps every row.
Filter :: struct {
	col:            int,
	kind:           Filter_Kind,
	values:         [dynamic]string,
	text:           string,
	lo, hi:         f64,
	has_lo, has_hi: bool,
}

// filter_active reports whether f keeps fewer than every row.
filter_active :: proc(f: Filter) -> bool {
	switch f.kind {
	case .Set:
		return len(f.values) > 0
	case .Text:
		return f.text != ""
	case .Range:
		return f.has_lo || f.has_hi
	case .None:
	}
	return false
}

// Source is where a grid's rows come from. A client source has every row
// in memory: rows of them, text giving column col of row as shown (a
// field of the row, or a string in context.temp_allocator: the grid reads
// it within the frame, and jm:ui's frame loops free that allocator only
// after the frame), key naming each (nil: the row's index), value a
// number or a date's Unix seconds for sorting and range filters (nil:
// parsed from the text), height a row's own height for a grid whose rows
// differ (nil: the density's). Bump version when the rows change, so the
// order is built again.
//
// A paged source sets paged: then rows, text, key and value are unused,
// and the grid asks for pages of rows by need (see paged.odin).
Source :: struct {
	user:    rawptr,
	rows:    int,
	text:    proc(user: rawptr, row, col: int) -> string,
	key:     proc(user: rawptr, row: int) -> Row_Key,
	value:   proc(user: rawptr, row, col: int) -> (f64, bool),
	height:  proc(user: rawptr, row: int) -> f32,
	version: u64,
	paged:   ^Paging,
}

// source_text is column col of row, "" without a text proc.
source_text :: proc(src: Source, row, col: int) -> string {
	return src.text(src.user, row, col) if src.text != nil else ""
}

// source_key is row's key: its index when the source names none, which
// keeps a selection only while the rows stay where they are.
source_key :: proc(src: Source, row: int) -> Row_Key {
	return src.key(src.user, row) if src.key != nil else Row_Key(row)
}

// source_value is column col of row as a number, for a column of kind:
// the source's value, else its text parsed as a number or an ISO 8601
// date. ok is false for a value that is not one.
source_value :: proc(src: Source, kind: Value_Kind, row, col: int) -> (f64, bool) {
	if src.value != nil {
		return src.value(src.user, row, col)
	}
	return parse_value(kind, source_text(src, row, col))
}

// parse_value reads s as kind: a number for Number, Unix seconds for a
// Date (an ISO 8601 date, with or without a time), nothing for Text.
parse_value :: proc(kind: Value_Kind, s: string) -> (f64, bool) {
	switch kind {
	case .Number:
		return strconv.parse_f64(trim_number(s))
	case .Date:
		return parse_date(s)
	case .Text:
	}
	return 0, false
}

// trim_number drops the spaces, thousands separators and a trailing
// percent sign or unit that a shown number may carry: "1,234.5 TH/s".
@(private)
trim_number :: proc(s: string) -> string {
	lo := 0
	for lo < len(s) && s[lo] == ' ' {
		lo += 1
	}
	hi := lo
	for hi < len(s) && (is_digit(s[hi]) || strings.index_byte(".-+,eE", s[hi]) >= 0) {
		hi += 1
	}
	t := s[lo:hi]
	if !has_byte(t, ',') {
		return t
	}
	buf := make([]u8, len(t), context.temp_allocator)
	n := 0
	for i in 0 ..< len(t) {
		if t[i] != ',' {
			buf[n] = t[i]
			n += 1
		}
	}
	return string(buf[:n])
}

@(private)
has_byte :: proc(s: string, b: u8) -> bool {
	for i in 0 ..< len(s) {
		if s[i] == b {
			return true
		}
	}
	return false
}

@(private)
is_digit :: proc(c: u8) -> bool {
	return c >= '0' && c <= '9'
}

// parse_date reads an ISO 8601 date, YYYY-MM-DD, with an optional time
// after a T or a space (HH:MM or HH:MM:SS, fractions and a zone ignored),
// as Unix seconds in UTC.
parse_date :: proc(s: string) -> (f64, bool) {
	if len(s) < 10 || s[4] != '-' || s[7] != '-' {
		return 0, false
	}
	y, ok_y := digits(s[0:4])
	m, ok_m := digits(s[5:7])
	d, ok_d := digits(s[8:10])
	if !ok_y || !ok_m || !ok_d || m < 1 || m > 12 || d < 1 || d > 31 {
		return 0, false
	}
	secs := f64(days_from_civil(y, m, d)) * 86400
	if len(s) >= 16 && (s[10] == 'T' || s[10] == ' ') && s[13] == ':' {
		hh, ok_h := digits(s[11:13])
		mm, ok_mm := digits(s[14:16])
		if ok_h && ok_mm {
			secs += f64(hh * 3600 + mm * 60)
		}
		if len(s) >= 19 && s[16] == ':' {
			if ss, ok_s := digits(s[17:19]); ok_s {
				secs += f64(ss)
			}
		}
	}
	return secs, true
}

@(private)
digits :: proc(s: string) -> (n: int, ok: bool) {
	for i in 0 ..< len(s) {
		if !is_digit(s[i]) {
			return 0, false
		}
		n = n * 10 + int(s[i] - '0')
	}
	return n, len(s) > 0
}

// days_from_civil is the days from 1970-01-01 to y-m-d in the proleptic
// Gregorian calendar (Howard Hinnant's algorithm).
@(private)
days_from_civil :: proc(y, m, d: int) -> int {
	yy := y - (m <= 2 ? 1 : 0)
	era := (yy >= 0 ? yy : yy - 399) / 400
	yoe := yy - era * 400
	mp := (m + 9) % 12
	doy := (153 * mp + 2) / 5 + d - 1
	doe := yoe * 365 + yoe / 4 - yoe / 100 + doy
	return era * 146097 + doe - 719468
}

// contains_fold reports whether hay contains needle, ASCII letters
// compared without case and other bytes exactly, with no allocation: the
// search runs over every visible cell of every row.
contains_fold :: proc(hay, needle: string) -> bool {
	if len(needle) == 0 {
		return true
	}
	if len(needle) > len(hay) {
		return false
	}
	first := fold(needle[0])
	outer: for i in 0 ..= len(hay) - len(needle) {
		if fold(hay[i]) != first {
			continue
		}
		for j in 1 ..< len(needle) {
			if fold(hay[i + j]) != fold(needle[j]) {
				continue outer
			}
		}
		return true
	}
	return false
}

@(private)
fold :: #force_inline proc(c: u8) -> u8 {
	return c + 32 if c >= 'A' && c <= 'Z' else c
}

// compare_natural orders two strings as people read them: digit runs by
// their value, letters without case, then by bytes to break a tie, and
// the empty string after everything else. 0 only for equal strings.
compare_natural :: proc(a, b: string) -> int {
	switch {
	case a == b:
		return 0
	case a == "":
		return 1
	case b == "":
		return -1
	}
	i, j := 0, 0
	for i < len(a) && j < len(b) {
		if is_digit(a[i]) && is_digit(b[j]) {
			c, ei, ej := compare_digit_runs(a, b, i, j)
			if c != 0 {
				return c
			}
			i, j = ei, ej
			continue
		}
		ca, cb := fold(a[i]), fold(b[j])
		if ca != cb {
			return ca < cb ? -1 : 1
		}
		i += 1
		j += 1
	}
	switch {
	case len(a) - i < len(b) - j:
		return -1
	case len(a) - i > len(b) - j:
		return 1
	}
	// Equal but for case: bytes decide, so the order is total.
	return a < b ? -1 : 1
}

// compare_digit_runs compares the digit runs starting at a[i] and b[j]
// by value, however long, and returns where each ends.
@(private)
compare_digit_runs :: proc(a, b: string, i, j: int) -> (c, ei, ej: int) {
	si, sj := i, j
	for si < len(a) - 1 && a[si] == '0' && is_digit(a[si + 1]) {
		si += 1
	}
	for sj < len(b) - 1 && b[sj] == '0' && is_digit(b[sj + 1]) {
		sj += 1
	}
	ei, ej = si, sj
	for ei < len(a) && is_digit(a[ei]) {
		ei += 1
	}
	for ej < len(b) && is_digit(b[ej]) {
		ej += 1
	}
	switch {
	case ei - si != ej - sj:
		c = ei - si < ej - sj ? -1 : 1
	case a[si:ei] != b[sj:ej]:
		c = a[si:ei] < b[sj:ej] ? -1 : 1
	}
	return
}

// Query is a grid's query as order_build reads it: the columns, the
// sort, the filters, the search text, the visible columns the search
// looks in, and the column rows are grouped by (-1 for none).
Query :: struct {
	cols:    []Column,
	sort:    []Sort_Key,
	filters: []Filter,
	search:  string,
	visible: []int,
	group:   int,
}

// fnv_str folds s into h, ended by a byte no UTF-8 text holds, so two
// strings hashed in turn cannot run together.
@(private)
fnv_str :: proc(h: u64, s: string) -> u64 {
	return ui.fnv_bytes(ui.fnv_bytes(h, transmute([]u8)s), {0xff})
}

// row_key is a paged row's key: the hash of its string key.
row_key :: proc(s: string) -> Row_Key {
	return Row_Key(ui.fnv_bytes(ui.FNV_OFFSET, transmute([]u8)s))
}

// match_hash names which rows q matches: its filters and its search,
// columns named by id so a hash outlives a reordering.
match_hash :: proc(q: Query) -> u64 {
	h := fnv_str(ui.FNV_OFFSET, q.search)
	for f in q.filters {
		if !filter_active(f) {
			continue
		}
		h = fnv_str(h, q.cols[f.col].id)
		h = ui.fnv_u64(h, u64(f.kind))
		for v in f.values {
			h = fnv_str(h, v)
		}
		h = fnv_str(h, f.text)
		h = ui.fnv_u64(h, transmute(u64)(f.has_lo ? f.lo : 0))
		h = ui.fnv_u64(h, transmute(u64)(f.has_hi ? f.hi : 0))
		h = ui.fnv_u64(h, u64(f.has_lo) | u64(f.has_hi) << 1)
	}
	return h
}

// order_hash names the rows q matches in the order it puts them.
order_hash :: proc(q: Query) -> u64 {
	h := ui.fnv_u64(match_hash(q), 0x5047)
	for s in q.sort {
		h = fnv_str(h, q.cols[s.col].id)
		h = ui.fnv_u64(h, u64(s.desc))
	}
	if q.group >= 0 {
		h = fnv_str(ui.fnv_u64(h, 0x6772), q.cols[q.group].id)
	}
	return h
}

// row_matches reports whether row passes every filter of q and its
// search; sets holds each Set filter's values as a lookup, by filter.
row_matches :: proc(src: Source, q: Query, sets: []map[string]bool, row: int) -> bool {
	for f, i in q.filters {
		if filter_active(f) && !filter_keeps(src, q.cols[f.col], f, sets[i], row) {
			return false
		}
	}
	if q.search == "" {
		return true
	}
	for c in q.visible {
		if contains_fold(source_text(src, row, c), q.search) {
			return true
		}
	}
	return false
}

// filter_keeps reports whether f keeps row.
@(private)
filter_keeps :: proc(src: Source, col: Column, f: Filter, set: map[string]bool, row: int) -> bool {
	switch f.kind {
	case .Set:
		return source_text(src, row, f.col) in set
	case .Text:
		return contains_fold(source_text(src, row, f.col), f.text)
	case .Range:
		v, ok := source_value(src, col.kind, row, f.col)
		if !ok {
			return false
		}
		return (!f.has_lo || v >= f.lo) && (!f.has_hi || v <= f.hi)
	case .None:
	}
	return true
}

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
// is header -item-1), and a collapsed group's rows left out. built names
// the query, data version and row count it was built for, so the grid
// rebuilds it only when one changes.
Order :: struct {
	rows:       [dynamic]int,
	items:      [dynamic]int,
	groups:     [dynamic]Group,
	group_text: [dynamic]u8, // every group's text, end to end: a source's text may be the frame's
	built:      u64,
	nums:       [dynamic]f64, // sort scratch: one column's values
	texts:      [dynamic]string, // sort scratch: one column's text
	key_nums:   [dynamic][dynamic]f64,
	key_texts:  [dynamic][dynamic]string,
	key_ok:     [dynamic][dynamic]bool,
}

order_destroy :: proc(o: ^Order) {
	delete(o.rows)
	delete(o.items)
	delete(o.groups)
	delete(o.group_text)
	delete(o.nums)
	delete(o.texts)
	for a in o.key_nums {
		delete(a)
	}
	for a in o.key_texts {
		delete(a)
	}
	for a in o.key_ok {
		delete(a)
	}
	delete(o.key_nums)
	delete(o.key_texts)
	delete(o.key_ok)
	o^ = {}
}

// order_build fills o with the rows of src that q matches, sorted by q's
// sort (stably: rows that tie keep their source order), grouped by q's
// group column with the groups in collapsed shut. It reads each sorted
// cell once.
order_build :: proc(o: ^Order, src: Source, q: Query, collapsed: map[string]bool = nil) {
	clear(&o.rows)
	sets := make([]map[string]bool, len(q.filters), context.temp_allocator)
	for f, i in q.filters {
		if f.kind == .Set && len(f.values) > 0 {
			sets[i] = make(map[string]bool, len(f.values), context.temp_allocator)
			for v in f.values {
				sets[i][v] = true
			}
		}
	}
	for r in 0 ..< max(src.rows, 0) {
		if row_matches(src, q, sets, r) {
			append(&o.rows, r)
		}
	}
	keys := make([dynamic]Sort_Key, 0, len(q.sort) + 1, context.temp_allocator)
	if q.group >= 0 {
		desc := false
		for s in q.sort {
			if s.col == q.group {
				desc = s.desc
			}
		}
		append(&keys, Sort_Key{q.group, desc})
	}
	for s in q.sort {
		if s.col != q.group {
			append(&keys, s)
		}
	}
	if len(keys) > 0 {
		sort_rows(o, src, q.cols, keys[:])
	}
	build_items(o, src, q.group, collapsed)
}

// Sorting is what sort_rows's comparison reads.
@(private)
Sorting :: struct {
	keys:  []Sort_Key,
	nums:  [][dynamic]f64,
	texts: [][dynamic]string,
	ok:    [][dynamic]bool,
	text:  []bool, // per key: compare text, not numbers
}

// sort_rows sorts o.rows by keys, reading each key column's cells into
// arrays first so the comparisons touch no callback.
@(private)
sort_rows :: proc(o: ^Order, src: Source, cols: []Column, keys: []Sort_Key) {
	n := len(o.rows)
	for len(o.key_nums) < len(keys) {
		append(&o.key_nums, [dynamic]f64{})
		append(&o.key_texts, [dynamic]string{})
		append(&o.key_ok, [dynamic]bool{})
	}
	s := Sorting {
		keys  = keys,
		nums  = o.key_nums[:len(keys)],
		texts = o.key_texts[:len(keys)],
		ok    = o.key_ok[:len(keys)],
		text  = make([]bool, len(keys), context.temp_allocator),
	}
	for k, ki in keys {
		s.text[ki] = cols[k.col].kind == .Text
		fill_key(&s, src, cols[k.col].kind, k.col, ki, o.rows[:])
	}
	// Sort positions, not rows, so each key's arrays index directly.
	pos := make([]i32, n, context.temp_allocator)
	for i in 0 ..< n {
		pos[i] = i32(i)
	}
	slice.sort_by_cmp_with_data(pos, compare_positions, &s)
	sorted := make([]int, n, context.temp_allocator)
	for p, i in pos {
		sorted[i] = o.rows[p]
	}
	copy(o.rows[:], sorted)
}

// fill_key reads key ki's column for every row into s's arrays.
@(private)
fill_key :: proc(s: ^Sorting, src: Source, kind: Value_Kind, col, ki: int, rows: []int) {
	n := len(rows)
	if s.text[ki] {
		resize(&s.texts[ki], n)
		for r, i in rows {
			s.texts[ki][i] = source_text(src, r, col)
		}
		return
	}
	resize(&s.nums[ki], n)
	resize(&s.ok[ki], n)
	for r, i in rows {
		s.nums[ki][i], s.ok[ki][i] = source_value(src, kind, r, col)
	}
}

// compare_positions orders two positions by every key in turn, a value
// that is not one (an empty cell) after every value whichever way the
// key runs, and by position to break a full tie, which keeps the sort
// stable.
@(private)
compare_positions :: proc(a, b: i32, user: rawptr) -> slice.Ordering {
	s := (^Sorting)(user)
	for k, ki in s.keys {
		c, blank := 0, false
		if s.text[ki] {
			ta, tb := s.texts[ki][a], s.texts[ki][b]
			c, blank = compare_natural(ta, tb), (ta == "") != (tb == "")
		} else {
			na, nb := s.nums[ki][a], s.nums[ki][b]
			c = compare_numbers(na, s.ok[ki][a], nb, s.ok[ki][b])
			blank = (s.ok[ki][a] && na == na) != (s.ok[ki][b] && nb == nb)
		}
		if c != 0 {
			if k.desc && !blank {
				c = -c
			}
			return c < 0 ? .Less : .Greater
		}
	}
	switch {
	case a < b:
		return .Less
	case a > b:
		return .Greater
	}
	return .Equal
}

// compare_numbers orders two values, one that is not a value (ok false,
// or NaN) last.
@(private)
compare_numbers :: proc(a: f64, ok_a: bool, b: f64, ok_b: bool) -> int {
	has_a := ok_a && a == a
	has_b := ok_b && b == b
	switch {
	case !has_a && !has_b:
		return 0
	case !has_a:
		return 1
	case !has_b:
		return -1
	case a < b:
		return -1
	case a > b:
		return 1
	}
	return 0
}

// build_items lays out what the grid draws from o.rows: the rows, or
// with a group column a header before each run of equal text and the
// rows of a group in collapsed left out.
@(private)
build_items :: proc(o: ^Order, src: Source, group: int, collapsed: map[string]bool) {
	clear(&o.items)
	clear(&o.groups)
	clear(&o.group_text)
	if group < 0 {
		append(&o.items, ..o.rows[:])
		return
	}
	shut := false
	for r, i in o.rows {
		t := source_text(src, r, group)
		if i == 0 || t != group_name(o, o.groups[len(o.groups) - 1]) {
			lo := len(o.group_text)
			append(&o.group_text, t)
			append(&o.groups, Group{lo = lo, hi = len(o.group_text), item = len(o.items)})
			append(&o.items, -len(o.groups))
			shut = collapsed[t]
		}
		o.groups[len(o.groups) - 1].count += 1
		if !shut {
			append(&o.items, r)
		}
	}
}

// Value_Count is one distinct value of a column and how many rows hold
// it: what a Set filter offers.
Value_Count :: struct {
	value: string,
	count: int,
}

// distinct_values is column col's distinct texts among the rows of src
// that pass every filter of q but col's own, with their counts, sorted
// naturally: what the column's Set filter offers to choose from, so the
// counts say what choosing one would show.
distinct_values :: proc(
	src: Source,
	q: Query,
	col: int,
	allocator := context.allocator,
) -> []Value_Count {
	others := make([dynamic]Filter, 0, len(q.filters), context.temp_allocator)
	for f in q.filters {
		if f.col != col {
			append(&others, f)
		}
	}
	rest := q
	rest.filters = others[:]
	rest.search = ""
	sets := make([]map[string]bool, len(others), context.temp_allocator)
	for f, i in others {
		if f.kind == .Set {
			sets[i] = make(map[string]bool, len(f.values), context.temp_allocator)
			for v in f.values {
				sets[i][v] = true
			}
		}
	}
	counts := make(map[string]int, 64, context.temp_allocator)
	for r in 0 ..< max(src.rows, 0) {
		if row_matches(src, rest, sets, r) {
			counts[source_text(src, r, col)] += 1
		}
	}
	out := make([]Value_Count, len(counts), allocator)
	i := 0
	for v, n in counts {
		out[i] = {strings.clone(v, allocator), n}
		i += 1
	}
	slice.sort_by(out, proc(a, b: Value_Count) -> bool {
		return compare_natural(a.value, b.value) < 0
	})
	return out
}
