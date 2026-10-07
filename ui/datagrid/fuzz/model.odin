package datagrid_fuzz

import "core:fmt"
import "core:slice"
import "core:strconv"
import "core:strings"

import harness "jm:fuzz"
import "jm:ui/datagrid"

// The pure model's properties: each draws its input, runs the grid's own
// code on it, and holds the result to a reference written the plain way
// or to the bounds the code promises.

// EPSILON is how far a width or a height may drift from exact through
// the solver's and the index's arithmetic, per pixel of the whole.
EPSILON :: 1e-3

// widths draws tracks, a width and a Fit, solves, and checks every track
// keeps its bounds and that the whole fills or fits as the Fit says.
widths :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	tracks := draw_tracks(src)
	avail := f32(harness.integer_in(src, -10, 3000))
	fit := datagrid.Fit.Shrink if harness.boolean(src) else .Scroll
	out := make([]f32, len(tracks))
	datagrid.solve_widths(tracks, avail, fit, out)
	total: f32
	for t, i in tracks {
		if detail, ok := track_holds(t, out[i], fit); !ok {
			return fmt.tprintf("track %d %v: %s", i, t, detail), false
		}
		total += out[i]
	}
	want := widths_want(tracks, avail, fit)
	ok := abs(total - want) <= EPSILON * max(want, 1) + 0.01
	return fmt.tprintf(
			"%d tracks in %v (%v): %v, want %v in all",
			len(tracks),
			avail,
			fit,
			out,
			want,
		),
		ok
}

// draw_tracks draws up to eight tracks, each at least its min and at
// most its max.
@(private)
draw_tracks :: proc(src: ^harness.Source) -> []datagrid.Track {
	tracks := make([]datagrid.Track, harness.integer_in(src, 0, 9))
	for &t in tracks {
		t.min = f32(harness.integer_in(src, 0, 120))
		t.base = t.min + f32(harness.integer_in(src, 0, 400))
		if harness.boolean(src) {
			t.max = t.base + f32(harness.integer_in(src, 0, 200))
		}
		t.grow = f32(harness.integer_in(src, 0, 4))
		t.rigid = harness.integer_in(src, 0, 4) == 0
	}
	return tracks
}

// widths_want is what tracks should come to in avail under fit: their
// bases, grown to avail as far as the growing ones can go, or with Shrink
// shrunk to it as far as the ones not rigid can give.
@(private)
widths_want :: proc(tracks: []datagrid.Track, avail: f32, fit: datagrid.Fit) -> f32 {
	base, room, give: f32
	for t in tracks {
		base += t.base
		room += track_room(t)
		give += 0 if t.rigid else t.base - t.min
	}
	switch {
	case avail <= 0:
	case base < avail:
		return min(avail, base + room)
	case base > avail && fit == .Shrink:
		return max(avail, base - give)
	}
	return base
}

// track_room is how far t can grow: none unless it grows, else to its
// max, without one as far as anything asks.
@(private)
track_room :: proc(t: datagrid.Track) -> f32 {
	if t.grow <= 0 || t.rigid {
		return 0
	}
	return (t.max - t.base) if t.max > 0 else 1e9
}

// track_holds checks one track's width w: within its bounds, then grown
// or shrunk only as its kind allows.
@(private)
track_holds :: proc(t: datagrid.Track, w: f32, fit: datagrid.Fit) -> (string, bool) {
	slack := EPSILON * max(t.base, 1)
	switch {
	case !(w >= 0) || w >= datagrid.INF:
		return fmt.tprintf("width %v", w), false
	case w < t.min - slack:
		return fmt.tprintf("%v under its min", w), false
	case t.rigid && w != t.base:
		return fmt.tprintf("rigid, but %v", w), false
	}
	return track_moved(t, w, fit, slack)
}

// track_moved checks a track that moved from its base: grown only if it
// grows and only to its max, shrunk only to fit.
@(private)
track_moved :: proc(t: datagrid.Track, w: f32, fit: datagrid.Fit, slack: f32) -> (string, bool) {
	grew, shrank := w > t.base + slack, w < t.base - slack
	switch {
	case grew && t.grow <= 0:
		return fmt.tprintf("grew to %v", w), false
	case grew && t.max > 0 && w > t.max + slack:
		return fmt.tprintf("%v past its max", w), false
	case shrank && fit != .Shrink:
		return fmt.tprintf("shrank to %v without Shrink", w), false
	}
	return "", true
}

// heights draws row heights, indexes them, and checks every top against a
// prefix sum, the row found at drawn ys, a changed height and the uniform
// form.
heights :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	n := harness.integer_in(src, 0, 200)
	hs := make([]f64, n)
	for &v in hs {
		v = f64(harness.integer_in(src, 0, 90))
	}
	h: datagrid.Heights
	defer datagrid.heights_destroy(&h)
	height_of :: proc(user: rawptr, i: int) -> f64 {
		return (^[]f64)(user)[i]
	}
	datagrid.heights_build(&h, n, height_of, &hs)
	for k := 0; k < 4; k += 1 {
		if detail, ok := tops_hold(&h, hs, src); !ok {
			return detail, false
		}
		if n == 0 {
			break
		}
		i := harness.integer_in(src, 0, n)
		hs[i] = f64(harness.integer_in(src, 0, 300))
		datagrid.heights_set(&h, i, hs[i])
	}
	u := f64(harness.integer_in(src, 1, 60))
	datagrid.heights_set_uniform(&h, n, u)
	for i in 0 ..= n {
		if datagrid.heights_top(&h, i) != f64(i) * u {
			return fmt.tprintf("uniform %v: top of %d", u, i), false
		}
	}
	return "", true
}

// tops_hold checks h against the heights hs, each at least 1: every top
// against a prefix sum, every height, the total, and the row found at
// drawn ys.
@(private)
tops_hold :: proc(h: ^datagrid.Heights, hs: []f64, src: ^harness.Source) -> (string, bool) {
	sum: f64
	for v, i in hs {
		if top := datagrid.heights_top(h, i); abs(top - sum) > 1e-6 * max(sum, 1) {
			return fmt.tprintf("top of %d is %v, want %v", i, top, sum), false
		}
		if got := datagrid.heights_of(h, i); got != max(v, 1) {
			return fmt.tprintf("height of %d is %v, want %v", i, got, v), false
		}
		sum += max(v, 1)
	}
	if datagrid.heights_total(h) != sum {
		return fmt.tprintf("total %v, want %v", datagrid.heights_total(h), sum), false
	}
	return rows_found(h, len(hs), sum, src)
}

// rows_found checks the row heights_at finds at drawn ys within sum,
// the height of h's n rows: the one whose span holds y.
@(private)
rows_found :: proc(
	h: ^datagrid.Heights,
	n: int,
	sum: f64,
	src: ^harness.Source,
) -> (
	string,
	bool,
) {
	for _ in 0 ..< (8 if n > 0 else 0) {
		y := f64(harness.integer_in(src, 0, max(int(sum), 1)))
		i := datagrid.heights_at(h, y)
		top, next := datagrid.heights_top(h, i), datagrid.heights_top(h, i + 1)
		if top > y || y >= next {
			return fmt.tprintf("y %v found row %d, %v to %v", y, i, top, next), false
		}
	}
	return "", true
}

// KEYS is the universe a selection case selects from.
@(private)
KEYS :: 12

// Selection_Model is what a Selection means, written as sets: explicit,
// set is what is selected; all, set is what is taken out of every row.
@(private)
Selection_Model :: struct {
	all, base_all: bool,
	set, base:     [KEYS]bool,
	anchored:      bool,
	match:         u64,
}

// selection draws ops on a Selection and on its model and checks after
// each that every key reads the same, the count agrees, and every kept
// name is its key's.
selection :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	s: datagrid.Selection
	datagrid.selection_init(&s)
	defer datagrid.selection_destroy(&s)
	m: Selection_Model
	ops := harness.integer_in(src, 0, 30)
	for step in 0 ..< ops {
		op := harness.integer_in(src, 0, 7)
		selection_op(&s, &m, op, src)
		if detail, ok := selection_agrees(&s, &m); !ok {
			return fmt.tprintf("after op %d (%d): %s", step, op, detail), false
		}
	}
	return "", true
}

@(private)
name_of :: proc(k: int) -> string {
	return fmt.tprintf("r%d", k)
}

// selection_op applies op to s and its model alike.
@(private)
selection_op :: proc(s: ^datagrid.Selection, m: ^Selection_Model, op: int, src: ^harness.Source) {
	k := harness.integer_in(src, 0, KEYS)
	key := datagrid.Row_Key(k + 1)
	switch op {
	case 0:
		datagrid.selection_only(s, key, name_of(k))
		m^ = {
			match = m.match,
		}
		m.set[k] = true
		model_anchor(m)
	case 1:
		datagrid.selection_toggle(s, key, name_of(k))
		m.set[k] = !m.set[k]
		model_anchor(m)
	case 2:
		datagrid.selection_anchor(s, key)
		model_anchor(m)
	case 3:
		selection_range_op(s, m, src)
	case 4:
		match := u64(harness.integer_in(src, 1, 4))
		datagrid.selection_all(s, match)
		m^ = {
			all   = true,
			match = match,
		}
	case 5:
		datagrid.selection_clear(s)
		m^ = {
			match = m.match,
		}
	case 6:
		selection_settle_op(s, m, src)
	}
}

@(private)
model_anchor :: proc(m: ^Selection_Model) {
	m.base, m.base_all, m.anchored = m.set, m.all, true
}

// selection_range_op draws the keys of a Shift range and applies it.
@(private)
selection_range_op :: proc(s: ^datagrid.Selection, m: ^Selection_Model, src: ^harness.Source) {
	n := harness.integer_in(src, 0, 5)
	keys := make([]datagrid.Row_Key, n)
	names := make([]string, n)
	ks := make([]int, n)
	for i in 0 ..< n {
		ks[i] = harness.integer_in(src, 0, KEYS)
		keys[i], names[i] = datagrid.Row_Key(ks[i] + 1), name_of(ks[i])
	}
	datagrid.selection_range(s, keys, names)
	if !m.anchored && n > 0 {
		model_anchor(m)
	}
	m.set, m.all = m.base, m.base_all
	for k in ks {
		m.set[k] = !m.all
	}
}

// selection_settle_op draws a new match and the rows loaded under it.
@(private)
selection_settle_op :: proc(s: ^datagrid.Selection, m: ^Selection_Model, src: ^harness.Source) {
	match := u64(harness.integer_in(src, 1, 4))
	loaded := make([dynamic]datagrid.Row_Key)
	names := make([dynamic]string)
	ks := make([dynamic]int)
	for k in 0 ..< KEYS {
		if harness.boolean(src) {
			append(&loaded, datagrid.Row_Key(k + 1))
			append(&names, name_of(k))
			append(&ks, k)
		}
	}
	datagrid.selection_settle(s, match, loaded[:], names[:])
	if !m.all || m.match == match {
		return
	}
	out: [KEYS]bool
	for k in ks {
		out[k] = !m.set[k]
	}
	m.set, m.all, m.base, m.anchored = out, false, {}, false
}

// selection_agrees compares s with its model, key by key.
@(private)
selection_agrees :: proc(s: ^datagrid.Selection, m: ^Selection_Model) -> (string, bool) {
	count := 0
	for k in 0 ..< KEYS {
		want := m.set[k] != m.all
		if datagrid.selected(s, datagrid.Row_Key(k + 1)) != want {
			return fmt.tprintf("key %d selected is %v", k, !want), false
		}
		count += int(want)
	}
	if got := datagrid.selection_count(s, KEYS); got != count {
		return fmt.tprintf("count %d, want %d", got, count), false
	}
	for key, name in s.keys {
		if name != name_of(int(key) - 1) {
			return fmt.tprintf("key %d keeps the name %q", key, name), false
		}
	}
	return "", true
}

// PIECES are the bits a query case's text is made of: digits that sort
// by value, letters that fold, blanks, and a rune past ASCII.
@(private)
PIECES := []string{"", "a", "A", "b", "10", "9", "x2", "x10", " ", "é"}

// SITES are a set column's values, the blank among them.
@(private)
SITES := []string{"Norway", "Paraguay", "Wisconsin", ""}

// QUERY_COLS are a query case's columns: text, a number, a date, a site.
@(private)
QUERY_COLS := []datagrid.Column {
	{id = "name"},
	{id = "hash", kind = .Number},
	{id = "made", kind = .Date},
	{id = "site"},
}

@(private)
Rows :: struct {
	cells: [][4]string,
}

@(private)
rows_source :: proc(r: ^Rows) -> datagrid.Source {
	text :: proc(user: rawptr, row, col: int) -> string {
		return (^Rows)(user).cells[row][col]
	}
	return {user = r, rows = len(r.cells), text = text}
}

// draw_rows draws up to 40 rows of the query columns.
@(private)
draw_rows :: proc(src: ^harness.Source) -> Rows {
	n := harness.integer_in(src, 0, 40)
	r := Rows{make([][4]string, n)}
	for &c in r.cells {
		c[0] = harness.text(src, PIECES, 3)
		switch harness.integer_in(src, 0, 4) {
		case 0:
			c[1] = ""
		case 1:
			c[1] = "n/a"
		case:
			c[1] = fmt.aprint(harness.integer_in(src, -50, 50))
		}
		day := harness.integer_in(src, 0, 30)
		c[2] = fmt.aprintf("2026-01-%02d", day) if day > 0 else ""
		c[3] = harness.choice(src, SITES)
	}
	return r
}

// draw_filter draws one filter on a drawn column.
@(private)
draw_filter :: proc(src: ^harness.Source) -> datagrid.Filter {
	f: datagrid.Filter
	switch harness.integer_in(src, 0, 4) {
	case 0:
		values := make([dynamic]string)
		for s in SITES {
			if harness.boolean(src) {
				append(&values, s)
			}
		}
		f = {3, datagrid.Set_Filter{values[:]}}
	case 1:
		f = {harness.choice(src, []int{0, 3}), datagrid.Text_Filter{harness.text(src, PIECES, 2)}}
	case 2:
		lo := draw_bound(src, f64(harness.integer_in(src, -60, 60)))
		hi := draw_bound(src, f64(harness.integer_in(src, -60, 60)))
		f = {1, datagrid.Range_Filter{lo, hi}}
	case:
		lo, _ := datagrid.parse_date(fmt.tprintf("2026-01-%02d", harness.integer_in(src, 1, 30)))
		hi, _ := datagrid.parse_date(fmt.tprintf("2026-01-%02d", harness.integer_in(src, 1, 30)))
		f = {2, datagrid.Range_Filter{draw_bound(src, lo), draw_bound(src, hi)}}
	}
	return f
}

// draw_bound is v as a range bound, or an open one.
@(private)
draw_bound :: proc(src: ^harness.Source, v: f64) -> Maybe(f64) {
	if harness.boolean(src) {
		return v
	}
	return nil
}

// query draws rows and a query, builds the order, and holds it to the rows
// filtered and stably sorted the plain way; then checks that the filters
// compose as an intersection.
query :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	rows := draw_rows(src)
	filters := make([]datagrid.Filter, harness.integer_in(src, 0, 4))
	for &f in filters {
		f = draw_filter(src)
	}
	sort := make([]datagrid.Sort_Key, harness.integer_in(src, 0, 4))
	for &k in sort {
		k = {harness.integer_in(src, 0, 4), harness.boolean(src)}
	}
	q := datagrid.Query {
		cols    = QUERY_COLS,
		sort    = sort,
		filters = filters,
		search  = harness.text(src, PIECES, 2),
		visible = []int{0, 1, 2, 3},
	}
	o: datagrid.Order
	defer datagrid.order_destroy(&o)
	datagrid.order_build(&o, rows_source(&rows), q)
	want := reference_order(&rows, q)
	if !equal_ints(o.rows[:], want) {
		return fmt.tprintf("rows %v\nquery %v\ngot %v\nwant %v", rows.cells, q, o.rows[:], want),
			false
	}
	return filters_compose(&rows, q, o.rows[:])
}

// reference_order is q's rows the plain way: every row tested against
// every filter and the search, then sorted by insertion, which is stable.
@(private)
reference_order :: proc(rows: ^Rows, q: datagrid.Query) -> []int {
	out := make([dynamic]int)
	for r in 0 ..< len(rows.cells) {
		if reference_keeps(rows, q, r) {
			append(&out, r)
		}
	}
	for i in 1 ..< len(out) {
		for j := i; j > 0 && reference_less(rows, q.sort, out[j], out[j - 1]); j -= 1 {
			out[j], out[j - 1] = out[j - 1], out[j]
		}
	}
	return out[:]
}

@(private)
reference_keeps :: proc(rows: ^Rows, q: datagrid.Query, r: int) -> bool {
	for f in q.filters {
		if !reference_filter(rows.cells[r][f.col], QUERY_COLS[f.col].kind, f) {
			return false
		}
	}
	if q.search == "" {
		return true
	}
	for c in rows.cells[r] {
		if strings.contains(strings.to_lower(c), strings.to_lower(q.search)) {
			return true
		}
	}
	return false
}

@(private)
reference_filter :: proc(cell: string, kind: datagrid.Value_Kind, f: datagrid.Filter) -> bool {
	switch r in f.rule {
	case datagrid.Set_Filter:
		return len(r.values) == 0 || slice.contains(r.values, cell)
	case datagrid.Text_Filter:
		return strings.contains(strings.to_lower(cell), strings.to_lower(r.text))
	case datagrid.Range_Filter:
		return reference_range(cell, kind, r)
	}
	return true
}

// reference_range reports whether r keeps cell: any cell when neither
// bound is set, else one whose value lies within them.
@(private)
reference_range :: proc(
	cell: string,
	kind: datagrid.Value_Kind,
	r: datagrid.Range_Filter,
) -> bool {
	lo, has_lo := r.lo.?
	hi, has_hi := r.hi.?
	if !has_lo && !has_hi {
		return true
	}
	v, ok := reference_value(cell, kind)
	return ok && (!has_lo || v >= lo) && (!has_hi || v <= hi)
}

@(private)
reference_value :: proc(cell: string, kind: datagrid.Value_Kind) -> (f64, bool) {
	if kind == .Date {
		return datagrid.parse_date(cell)
	}
	return strconv.parse_f64(cell)
}

// reference_less orders two rows by sort, a blank or a value that is not
// one after the rest whichever way a key runs.
@(private)
reference_less :: proc(rows: ^Rows, sort: []datagrid.Sort_Key, a, b: int) -> bool {
	for k in sort {
		ca, cb := rows.cells[a][k.col], rows.cells[b][k.col]
		c, blank_first := reference_compare(ca, cb, QUERY_COLS[k.col].kind)
		if blank_first != 0 {
			return blank_first < 0
		}
		if c != 0 {
			return (c < 0) != k.desc
		}
	}
	return false
}

// reference_compare orders two cells of a column of kind; blank_first is
// -1 when only b is blank or not a value, which puts a first whichever
// way the sort runs, 1 when only a is, else 0.
@(private)
reference_compare :: proc(ca, cb: string, kind: datagrid.Value_Kind) -> (c, blank_first: int) {
	if kind == .Text {
		if (ca == "") != (cb == "") {
			return 0, 1 if ca == "" else -1
		}
		return datagrid.compare_natural(ca, cb), 0
	}
	va, oa := reference_value(ca, kind)
	vb, ob := reference_value(cb, kind)
	if oa != ob {
		return 0, -1 if oa else 1
	}
	return reference_order_values(va, vb, oa), 0
}

// reference_order_values orders two values, or none when they are not.
@(private)
reference_order_values :: proc(va, vb: f64, ok: bool) -> int {
	if !ok || va == vb {
		return 0
	}
	return -1 if va < vb else 1
}

@(private)
equal_ints :: proc(a, b: []int) -> bool {
	if len(a) != len(b) {
		return false
	}
	for v, i in a {
		if b[i] != v {
			return false
		}
	}
	return true
}

// filters_compose checks that q's rows are those its first filter keeps
// that the rest keep too.
@(private)
filters_compose :: proc(rows: ^Rows, q: datagrid.Query, got: []int) -> (string, bool) {
	if len(q.filters) < 2 {
		return "", true
	}
	first, rest := q, q
	first.filters, first.sort = q.filters[:1], nil
	rest.filters, rest.sort, rest.search = q.filters[1:], nil, ""
	o: datagrid.Order
	defer datagrid.order_destroy(&o)
	datagrid.order_build(&o, rows_source(rows), first)
	both := make([dynamic]int)
	for r in o.rows {
		if reference_keeps(rows, rest, r) {
			append(&both, r)
		}
	}
	in_got := make(map[int]bool)
	for r in got {
		in_got[r] = true
	}
	ok := len(both) == len(got)
	for r in both {
		ok = ok && in_got[r]
	}
	return fmt.tprintf("one filter then the rest kept %v, all at once %v", both[:], got), ok
}

// FIELD_PIECES are what a delimited field is made of: every byte that
// needs quoting, the formula leaders, and plain text.
@(private)
FIELD_PIECES := []string {
	"",
	"a",
	",",
	`"`,
	"\n",
	"\t",
	"=1+1",
	"-",
	"@x",
	"+",
	" ",
	"é",
	"x y",
	"\r\n",
	"\r",
}

// delimited draws a record, writes it as CSV and as TSV, and reads each
// back with read_quoted, an RFC 4180 reader: a defused formula comes back
// with its apostrophe, every other field as it was.
//
// Not through core:encoding/csv: with multiline_fields, its line scan
// takes a delimiter inside quotes for the end of a field, so the closing
// quote after it opens another and the record runs to EOF. "\"a,\"" and
// "\",\"" read as nothing; a tab-delimited "\"\t\"" too (reader.odin's
// read_line). The unit test that reads a record back through it avoids
// those fields.
delimited :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	n := harness.integer_in(src, 1, 7)
	fields := make([]string, n)
	for &f in fields {
		f = harness.text(src, FIELD_PIECES, 3)
	}
	for format in ([]datagrid.Delimited{datagrid.CSV, datagrid.TSV}) {
		b := strings.builder_make()
		datagrid.write_record(&b, format, fields)
		text := strings.to_string(b)
		got, ok := read_quoted(text, format.delim, format.eol)
		if !ok || len(got) != n {
			return fmt.tprintf("%q read back as %q", text, got), false
		}
		for f, i in fields {
			if want := written(format, f); got[i] != want {
				return fmt.tprintf("field %d %q read back as %q from %q", i, f, got[i], text),
					false
			}
		}
	}
	return "", true
}

// written is field f as format should write it: a formula defused with an
// apostrophe, every other field as it is.
@(private)
written :: proc(format: datagrid.Delimited, f: string) -> string {
	if format.defuse && len(f) > 0 && strings.index_byte(datagrid.FORMULA_LEADERS, f[0]) >= 0 {
		return strings.concatenate({"'", f})
	}
	return f
}

// read_quoted reads one record of fields split by delim and ended by eol,
// as RFC 4180 has it: a field in double quotes holds anything, a doubled
// quote one quote; any other holds no quote, carriage return or newline.
@(private)
read_quoted :: proc(text: string, delim: u8, eol: string) -> ([]string, bool) {
	out := make([dynamic]string)
	i := 0
	for {
		field, next, ok := read_field(text, i, delim, eol)
		if !ok {
			return out[:], false
		}
		append(&out, field)
		i = next
		switch {
		case i < len(text) && text[i] == delim:
			i += 1
		case strings.has_prefix(text[i:], eol):
			return out[:], i + len(eol) == len(text)
		case:
			return out[:], false
		}
	}
}

// read_field reads the field at text[i], quoted or not, and returns it
// and where it ends; ok is false for a field RFC 4180 does not allow.
@(private)
read_field :: proc(
	text: string,
	i: int,
	delim: u8,
	eol: string,
) -> (
	field: string,
	next: int,
	ok: bool,
) {
	if i < len(text) && text[i] == '"' {
		return read_quoted_field(text, i + 1)
	}
	j := i
	for j < len(text) && text[j] != delim && !strings.has_prefix(text[j:], eol) {
		if strings.index_byte("\"\r\n", text[j]) >= 0 {
			return "", j, false // RFC 4180 quotes a field holding one
		}
		j += 1
	}
	return text[i:j], j, true
}

// read_quoted_field reads a quoted field's body from text[i], a doubled
// quote one quote, to its closing quote; ok is false if it never closes.
@(private)
read_quoted_field :: proc(text: string, i: int) -> (field: string, next: int, ok: bool) {
	b := strings.builder_make()
	j := i
	for j < len(text) {
		if text[j] != '"' {
			strings.write_byte(&b, text[j])
			j += 1
			continue
		}
		if j + 1 >= len(text) || text[j + 1] != '"' {
			return strings.to_string(b), j + 1, true
		}
		strings.write_byte(&b, '"')
		j += 2
	}
	return "", j, false
}

// VIEW_TEXT is what a view's strings are made of: every byte its quoting
// escapes, and plain text.
@(private)
VIEW_TEXT := []string{"", "a", " ", `"`, `\`, "\n", "\r", "\t", "\x00", "\x7f", "é", "x y", "-"}

// views draws columns and a view of them, writes it, and reads it back:
// against the same columns it is the same view; against columns changed
// since, every column stands in the order once and what names a dropped
// column is gone; and text that is no view reads as none.
views :: proc(_: Nothing, src: ^harness.Source) -> (string, bool) {
	cols := draw_columns(src, 0)
	v: datagrid.View
	datagrid.view_init(&v, cols)
	draw_view(&v, cols, src)
	name := harness.text(src, VIEW_TEXT, 3)
	b := strings.builder_make()
	datagrid.view_encode(&b, &v, cols, name)
	text := strings.to_string(b)
	back: datagrid.View
	datagrid.view_init(&back, cols)
	got, ok := datagrid.view_decode(&back, cols, text)
	if !ok || got != name {
		return fmt.tprintf("%q read back as name %q (%v)", text, got, ok), false
	}
	if detail, same := views_equal(&v, &back); !same {
		return fmt.tprintf("%s, from %q", detail, text), false
	}
	changed := draw_columns(src, len(cols))
	datagrid.view_decode(&back, changed, text)
	if detail, whole := view_holds(&back, changed); !whole {
		return fmt.tprintf("against changed columns: %s, from %q", detail, text), false
	}
	pieces := []string{"datagrid-view 1\n", "column ", `"c1"`, " width ", "x", "\n", "sort "}
	garbage := harness.text(src, pieces, 12)
	if _, read := datagrid.view_decode(&back, cols, garbage); read {
		if detail, whole := view_holds(&back, cols); !whole {
			return fmt.tprintf("from %q: %s", garbage, detail), false
		}
	}
	return "", true
}

// draw_columns draws up to six columns named c<from>, c<from+1> and on,
// with some of c0 to c5 among them when from is past them, shuffled.
@(private)
draw_columns :: proc(src: ^harness.Source, from: int) -> []datagrid.Column {
	n := harness.integer_in(src, 1, 7)
	out := make([]datagrid.Column, n)
	for &c, i in out {
		id := from + i
		if from > 0 && harness.boolean(src) {
			id = harness.integer_in(src, 0, from)
		}
		c.id = fmt.aprintf("c%d", id)
		c.min_width = f32(harness.integer_in(src, 0, 80))
	}
	for i := n - 1; i > 0; i -= 1 {
		j := harness.integer_in(src, 0, i + 1)
		out[i], out[j] = out[j], out[i]
	}
	return out
}

// draw_view arranges v: columns moved, sized, hidden and pinned; a sort; a
// filter of each kind; a search.
@(private)
draw_view :: proc(v: ^datagrid.View, cols: []datagrid.Column, src: ^harness.Source) {
	n := len(cols)
	for _ in 0 ..< harness.integer_in(src, 0, 4) {
		datagrid.move_column(
			v.order[:],
			harness.integer_in(src, 0, n),
			harness.integer_in(src, 0, n + 1),
		)
	}
	for &s, i in v.cols {
		if harness.boolean(src) {
			s.width = datagrid.clamp_width(cols[i], f32(harness.integer_in(src, 1, 600)) + 0.25)
		}
		s.hidden = harness.integer_in(src, 0, 4) == 0
		s.pin = harness.choice(src, []datagrid.Pin{.None, .Left, .Right})
	}
	for _ in 0 ..< harness.integer_in(src, 0, 3) {
		datagrid.view_sort_cycle(v, harness.integer_in(src, 0, n), harness.boolean(src))
	}
	values := make([dynamic]string)
	for _ in 0 ..< harness.integer_in(src, 0, 4) {
		append(&values, harness.text(src, VIEW_TEXT, 3))
	}
	datagrid.view_set_values(v, harness.integer_in(src, 0, n), values[:])
	datagrid.view_set_text(v, harness.integer_in(src, 0, n), harness.text(src, VIEW_TEXT, 3))
	lo, hi :=
		f64(harness.integer_in(src, -1000, 1000)) / 8, f64(harness.integer_in(src, -1000, 1000))
	col := harness.integer_in(src, 0, n)
	datagrid.view_set_range(v, col, draw_bound(src, lo), draw_bound(src, hi))
	datagrid.view_set_search(v, harness.text(src, VIEW_TEXT, 3))
}

// views_equal compares what a view keeps: order, widths, visibility, pins,
// sort, active filters and search.
@(private)
views_equal :: proc(a, b: ^datagrid.View) -> (string, bool) {
	if !equal_ints(a.order[:], b.order[:]) {
		return fmt.tprintf("order %v read back as %v", a.order[:], b.order[:]), false
	}
	for s, i in a.cols {
		if !same_state(s, b.cols[i]) {
			return fmt.tprintf("column %d %v read back as %v", i, s, b.cols[i]), false
		}
	}
	if !slice.equal(a.sort[:], b.sort[:]) {
		return fmt.tprintf("sort %v read back as %v", a.sort[:], b.sort[:]), false
	}
	if detail, same := active_filters_equal(a, b); !same {
		return detail, false
	}
	return fmt.tprintf("search %q read back as %q", a.search, b.search), a.search == b.search
}

// same_state reports whether two columns' states agree in what a view
// keeps: width, visibility and pin.
@(private)
same_state :: proc(a, b: datagrid.Column_State) -> bool {
	return a.width == b.width && a.hidden == b.hidden && a.pin == b.pin
}

// active_filters_equal compares a's active filters with b's, which keeps
// only those.
@(private)
active_filters_equal :: proc(a, b: ^datagrid.View) -> (string, bool) {
	active := make([dynamic]datagrid.Filter)
	for f in a.filters {
		if datagrid.filter_active(f) {
			append(&active, f)
		}
	}
	if len(active) != len(b.filters) {
		return fmt.tprintf("filters %v read back as %v", active[:], b.filters[:]), false
	}
	for f, i in active {
		if !filters_equal(f, b.filters[i]) {
			return fmt.tprintf("filter %v read back as %v", f, b.filters[i]), false
		}
	}
	return "", true
}

// filters_equal compares what a filter of its kind keeps: a Set's values,
// a Text's text, a Range's bounds.
@(private)
filters_equal :: proc(a, b: datagrid.Filter) -> bool {
	if a.col != b.col || datagrid.rule_kind(a.rule) != datagrid.rule_kind(b.rule) {
		return false
	}
	switch r in a.rule {
	case datagrid.Set_Filter:
		return slice.equal(r.values, b.rule.(datagrid.Set_Filter).values)
	case datagrid.Text_Filter:
		return r.text == b.rule.(datagrid.Text_Filter).text
	case datagrid.Range_Filter:
		s := b.rule.(datagrid.Range_Filter)
		return bound_equal(r.lo, s.lo) && bound_equal(r.hi, s.hi)
	}
	return true
}

// bound_equal reports whether two bounds are both open, or both set to
// one value.
@(private)
bound_equal :: proc(a, b: Maybe(f64)) -> bool {
	x, has_a := a.?
	y, has_b := b.?
	return has_a == has_b && (!has_a || x == y)
}


// view_holds checks v stands on cols: the order holds every column once,
// and the sort and filters name columns there are.
@(private)
view_holds :: proc(v: ^datagrid.View, cols: []datagrid.Column) -> (string, bool) {
	n := len(cols)
	if len(v.order) != n || len(v.cols) != n || !is_permutation(v.order[:]) {
		return fmt.tprintf("order %v and %d states for %d columns", v.order[:], len(v.cols), n),
			false
	}
	for k in v.sort {
		if !column_in(k.col, n) {
			return fmt.tprintf("sort %v", v.sort[:]), false
		}
	}
	for f in v.filters {
		if !column_in(f.col, n) {
			return fmt.tprintf("filter on column %d", f.col), false
		}
	}
	return "", true
}

// column_in reports whether c is one of n columns.
@(private)
column_in :: proc(c, n: int) -> bool {
	return c >= 0 && c < n
}

// is_permutation reports whether order holds 0 to len(order) - 1, each
// once.
@(private)
is_permutation :: proc(order: []int) -> bool {
	seen := make([]bool, len(order))
	for c in order {
		if c < 0 || c >= len(order) || seen[c] {
			return false
		}
		seen[c] = true
	}
	return true
}
