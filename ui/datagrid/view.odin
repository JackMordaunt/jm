package datagrid

import "core:mem"
import "core:slice"
import "core:strconv"
import "core:strings"

// View is how the user has arranged a grid and what they asked it to
// show: the columns' order, widths, visibility and pins, the sort, the
// filters and the search. It is the part of a grid a saved view keeps
// (view_encode), and its query (view_query), which a table orders its
// rows by and a remote sends its host. Columns are indexed as the caller
// declared them; order lists every column, hidden or not, in display
// order.
View :: struct {
	order:     [dynamic]int,
	cols:      [dynamic]Column_State,
	sort:      [dynamic]Sort_Key,
	filters:   [dynamic]Filter,
	search:    string,
	allocator: mem.Allocator,
}

// view_init makes v the columns as declared: in their order, each at its
// sizing, hidden and pinned as declared, nothing sorted or filtered.
view_init :: proc(v: ^View, cols: []Column, allocator := context.allocator) {
	v.allocator = allocator
	v.order = make([dynamic]int, allocator)
	v.cols = make([dynamic]Column_State, allocator)
	v.sort = make([dynamic]Sort_Key, allocator)
	v.filters = make([dynamic]Filter, allocator)
	view_reset(v, cols)
}

view_destroy :: proc(v: ^View) {
	view_free_filters(v)
	delete(v.order)
	delete(v.cols)
	delete(v.sort)
	delete(v.filters)
	delete(v.search, v.allocator)
	v^ = {}
}

// view_reset puts v back to the columns as declared.
view_reset :: proc(v: ^View, cols: []Column) {
	clear(&v.order)
	clear(&v.cols)
	clear(&v.sort)
	view_free_filters(v)
	view_set_search(v, "")
	for c, i in cols {
		append(&v.order, i)
		append(&v.cols, Column_State{hidden = c.hidden, pin = c.pin})
	}
}

// view_reset_columns puts the columns back as declared (their order,
// widths, visibility and pins), keeping the sort, filters and search:
// the Reset columns of a column menu.
view_reset_columns :: proc(v: ^View, cols: []Column) {
	clear(&v.order)
	for c, i in cols {
		append(&v.order, i)
		v.cols[i] = Column_State {
			hidden = c.hidden,
			pin    = c.pin,
			auto   = v.cols[i].auto,
		}
	}
}

@(private)
view_free_filters :: proc(v: ^View) {
	for &f in v.filters {
		filter_free(&f, v.allocator)
	}
	clear(&v.filters)
}

@(private)
filter_free :: proc(f: ^Filter, allocator: mem.Allocator) {
	rule_free(f.rule, allocator)
	f^ = {}
}

// rule_free frees what r holds, allocated in allocator.
@(private)
rule_free :: proc(r: Filter_Rule, allocator: mem.Allocator) {
	switch r in r {
	case Set_Filter:
		for s in r.values {
			delete(s, allocator)
		}
		delete(r.values, allocator)
	case Text_Filter:
		delete(r.text, allocator)
	case Range_Filter:
	}
}

// view_copy makes dst the same view as src, in dst's allocator.
view_copy :: proc(dst: ^View, src: ^View) {
	clear(&dst.order)
	append(&dst.order, ..src.order[:])
	clear(&dst.cols)
	append(&dst.cols, ..src.cols[:])
	clear(&dst.sort)
	append(&dst.sort, ..src.sort[:])
	view_free_filters(dst)
	for f in src.filters {
		append(&dst.filters, filter_clone(f, dst.allocator))
	}
	view_set_search(dst, src.search)
}

@(private)
filter_clone :: proc(f: Filter, allocator: mem.Allocator) -> Filter {
	out := f
	switch r in f.rule {
	case Set_Filter:
		out.rule = Set_Filter{clone_strings(r.values, allocator)}
	case Text_Filter:
		out.rule = Text_Filter{strings.clone(r.text, allocator) if r.text != "" else ""}
	case Range_Filter:
	}
	return out
}

// clone_strings is a copy of ss and of each string in it, in allocator.
@(private)
clone_strings :: proc(ss: []string, allocator: mem.Allocator) -> []string {
	out := make([]string, len(ss), allocator)
	for s, i in ss {
		out[i] = strings.clone(s, allocator)
	}
	return out
}

// view_set_search makes the search s.
view_set_search :: proc(v: ^View, s: string) {
	if s == v.search {
		return
	}
	delete(v.search, v.allocator)
	v.search = strings.clone(s, v.allocator) if s != "" else ""
}

// view_sort_cycle is a header click on col: unsorted it sorts ascending,
// ascending it sorts descending, descending it stops sorting by col.
// Without add the rest of the sort goes; with add (Shift) col cycles in
// place and the rest stays, so a sort of several columns is built up.
view_sort_cycle :: proc(v: ^View, col: int, add: bool) {
	at := sort_rank(v, col)
	if !add {
		was := at >= 0 ? v.sort[at] : Sort_Key{col = -1}
		clear(&v.sort)
		switch {
		case was.col < 0:
			append(&v.sort, Sort_Key{col, false})
		case !was.desc:
			append(&v.sort, Sort_Key{col, true})
		}
		return
	}
	switch {
	case at < 0:
		append(&v.sort, Sort_Key{col, false})
	case !v.sort[at].desc:
		v.sort[at].desc = true
	case:
		ordered_remove(&v.sort, at)
	}
}

// sort_rank is where col stands in v's sort, -1 when it is not sorted.
sort_rank :: proc(v: ^View, col: int) -> int {
	for s, i in v.sort {
		if s.col == col {
			return i
		}
	}
	return -1
}

// view_set_rule makes col's filter keep rows by r, which v now owns,
// freeing the rule it had.
@(private)
view_set_rule :: proc(v: ^View, col: int, r: Filter_Rule) {
	f := find_filter(v, col)
	if f == nil {
		append(&v.filters, Filter{col = col})
		f = &v.filters[len(v.filters) - 1]
	}
	rule_free(f.rule, v.allocator)
	f.rule = r
}

// chosen_values is the values f's Set filter keeps, nil for no filter
// or another rule.
chosen_values :: proc(f: ^Filter) -> []string {
	if f == nil {
		return nil
	}
	s, _ := f.rule.(Set_Filter)
	return s.values
}

// find_filter is col's filter, nil when it has none.
find_filter :: proc(v: ^View, col: int) -> ^Filter {
	for &f in v.filters {
		if f.col == col {
			return &f
		}
	}
	return nil
}

// view_filtered reports whether col has a filter that keeps fewer than
// every row: what a header's indicator shows.
view_filtered :: proc(v: ^View, col: int) -> bool {
	f := find_filter(v, col)
	return f != nil && filter_active(f^)
}

// view_filters_active reports whether any filter keeps fewer than every
// row: when a "Clear filters" shows.
view_filters_active :: proc(v: ^View) -> bool {
	for f in v.filters {
		if filter_active(f) {
			return true
		}
	}
	return false
}

// view_set_values makes col's Set filter keep values, copied and sorted
// with duplicates dropped; none clears it.
view_set_values :: proc(v: ^View, col: int, values: []string) {
	out := clone_strings(values, v.allocator)
	slice.sort(out)
	n := 0
	for s, i in out {
		if i > 0 && s == out[n - 1] {
			delete(s, v.allocator)
			continue
		}
		out[n] = s
		n += 1
	}
	view_set_rule(v, col, Set_Filter{out[:n]})
}

// view_toggle_value adds value to col's Set filter or takes it out.
view_toggle_value :: proc(v: ^View, col: int, value: string) {
	old := chosen_values(find_filter(v, col))
	at, found := slice.binary_search(old, value)
	out := make([]string, len(old) - 1 if found else len(old) + 1, v.allocator)
	copy(out, old[:at])
	if found {
		copy(out[at:], old[at + 1:])
		delete(old[at], v.allocator)
	} else {
		out[at] = strings.clone(value, v.allocator)
		copy(out[at + 1:], old[at:])
	}
	if len(old) > 0 {
		// out took the old strings over: only the old slice goes.
		delete(old, v.allocator)
		find_filter(v, col).rule = Set_Filter{out}
		return
	}
	view_set_rule(v, col, Set_Filter{out})
}

// view_set_text makes col's Text filter keep the rows containing text.
view_set_text :: proc(v: ^View, col: int, text: string) {
	if f := find_filter(v, col); f != nil {
		if t, ok := f.rule.(Text_Filter); ok && t.text == text {
			return
		}
	}
	view_set_rule(v, col, Text_Filter{strings.clone(text, v.allocator) if text != "" else ""})
}

// view_set_range makes col's Range filter keep values from lo to hi, a
// nil bound left open.
view_set_range :: proc(v: ^View, col: int, lo, hi: Maybe(f64)) {
	view_set_rule(v, col, Range_Filter{lo, hi})
}


// view_clear_filter clears col's filter, freeing what it held: the
// column's "Clear" in a filter popover.
view_clear_filter :: proc(v: ^View, col: int) {
	for &f, i in v.filters {
		if f.col == col {
			filter_free(&f, v.allocator)
			ordered_remove(&v.filters, i)
			return
		}
	}
}

// view_clear_filters clears every filter and the search: "Clear filters".
view_clear_filters :: proc(v: ^View) {
	view_free_filters(v)
	view_set_search(v, "")
}

// view_query is v as order_build and match_hash read it, the visible
// columns gathered into visible.
view_query :: proc(v: ^View, cols: []Column, visible: ^[dynamic]int) -> Query {
	clear(visible)
	for c in v.order {
		if !v.cols[c].hidden {
			append(visible, c)
		}
	}
	return {
		cols = cols,
		sort = v.sort[:],
		filters = v.filters[:],
		search = v.search,
		visible = visible[:],
	}
}

// VIEW_MAGIC heads a view's text, with its version.
VIEW_MAGIC :: "datagrid-view 1"

// view_encode writes v, named name, as text, one line per fact, columns
// named by their id:
//
//	datagrid-view 1
//	name "Overdue in Norway"
//	column "serial" width 120 pin left
//	column "model" hidden
//	sort "facility" asc
//	filter "facility" set "Norway" "Paraguay"
//	filter "hashrate" range 10 -
//	filter "worker" text "sazsub_"
//	search "s21"
//
// A column line lists every column in display order; a width of 0 (not
// dragged) is left out. Strings are quoted with \" \\ \n \r \t and \xHH
// escapes for the other control bytes, so any value round-trips.
view_encode :: proc(b: ^strings.Builder, v: ^View, cols: []Column, name: string) {
	strings.write_string(b, VIEW_MAGIC)
	strings.write_string(b, "\nname ")
	write_quoted(b, name)
	strings.write_byte(b, '\n')
	for c in v.order {
		encode_column(b, cols[c].id, v.cols[c])
	}
	for s in v.sort {
		strings.write_string(b, "sort ")
		write_quoted(b, cols[s.col].id)
		strings.write_string(b, s.desc ? " desc\n" : " asc\n")
	}
	for f in v.filters {
		if filter_active(f) {
			encode_filter(b, cols[f.col].id, f)
		}
	}
	if v.search != "" {
		strings.write_string(b, "search ")
		write_quoted(b, v.search)
		strings.write_byte(b, '\n')
	}
}

@(private)
encode_column :: proc(b: ^strings.Builder, id: string, s: Column_State) {
	strings.write_string(b, "column ")
	write_quoted(b, id)
	if s.width > 0 {
		strings.write_string(b, " width ")
		write_number(b, f64(s.width))
	}
	if s.hidden {
		strings.write_string(b, " hidden")
	}
	switch s.pin {
	case .Left:
		strings.write_string(b, " pin left")
	case .Right:
		strings.write_string(b, " pin right")
	case .None:
	}
	strings.write_byte(b, '\n')
}

@(private)
encode_filter :: proc(b: ^strings.Builder, id: string, f: Filter) {
	strings.write_string(b, "filter ")
	write_quoted(b, id)
	switch r in f.rule {
	case Set_Filter:
		strings.write_string(b, " set")
		for s in r.values {
			strings.write_byte(b, ' ')
			write_quoted(b, s)
		}
	case Text_Filter:
		strings.write_string(b, " text ")
		write_quoted(b, r.text)
	case Range_Filter:
		strings.write_string(b, " range ")
		write_bound(b, r.lo)
		strings.write_byte(b, ' ')
		write_bound(b, r.hi)
	}
	strings.write_byte(b, '\n')
}

@(private)
write_bound :: proc(b: ^strings.Builder, bound: Maybe(f64)) {
	if v, ok := bound.?; ok {
		write_number(b, v)
	} else {
		strings.write_byte(b, '-')
	}
}

@(private)
write_number :: proc(b: ^strings.Builder, v: f64) {
	buf: [64]u8
	strings.write_string(b, strconv.write_float(buf[:], v, 'g', -1, 64))
}

// write_quoted writes s in double quotes, escaped as view_encode says.
write_quoted :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for i in 0 ..< len(s) {
		write_escaped(b, s[i])
	}
	strings.write_byte(b, '"')
}

// write_escaped writes one byte of a quoted string: a quote, a backslash,
// a newline, a carriage return or a tab by its escape, another control
// byte as \xHH, the rest as it is.
@(private)
write_escaped :: proc(b: ^strings.Builder, c: u8) {
	hex := "0123456789abcdef"
	switch c {
	case '"':
		strings.write_string(b, `\"`)
	case '\\':
		strings.write_string(b, `\\`)
	case '\n':
		strings.write_string(b, `\n`)
	case '\r':
		strings.write_string(b, `\r`)
	case '\t':
		strings.write_string(b, `\t`)
	case 0x00 ..< 0x20, 0x7f:
		strings.write_string(b, `\x`)
		strings.write_byte(b, hex[c >> 4])
		strings.write_byte(b, hex[c & 15])
	case:
		strings.write_byte(b, c)
	}
}

// view_decode reads text that view_encode wrote into v, against cols as
// they are now, and returns the view's name in allocator. It tolerates a
// view from another build: a column that no longer exists is dropped
// from the order, the sort and the filters; a column the view does not
// name keeps its declared state and goes after the named ones, in
// declared order; a line it cannot read is skipped. ok is false only for
// text that is not a view at all.
view_decode :: proc(
	v: ^View,
	cols: []Column,
	text: string,
	allocator := context.allocator,
) -> (
	name: string,
	ok: bool,
) {
	rest := text
	first, _ := strings.split_lines_iterator(&rest)
	if strings.trim_right(first, "\r") != VIEW_MAGIC {
		return "", false
	}
	view_reset(v, cols)
	clear(&v.order)
	named := make([]bool, len(cols), context.temp_allocator)
	for line in strings.split_lines_iterator(&rest) {
		toks := tokens(line, context.temp_allocator)
		if len(toks) == 0 {
			continue
		}
		if toks[0] == "name" && len(toks) > 1 {
			delete(name, allocator)
			name = strings.clone(toks[1], allocator)
			continue
		}
		decode_line(v, cols, toks, named)
	}
	for c in 0 ..< len(cols) {
		if !named[c] {
			append(&v.order, c)
		}
	}
	return name, true
}

// decode_line applies one tokenised line but name to v.
@(private)
decode_line :: proc(v: ^View, cols: []Column, toks: []string, named: []bool) {
	if len(toks) < 2 {
		return
	}
	if toks[0] == "search" {
		view_set_search(v, toks[1])
		return
	}
	c := column_index(cols, toks[1])
	if c < 0 {
		return
	}
	switch toks[0] {
	case "column":
		decode_column_line(v, cols, c, toks[2:], named)
	case "sort":
		decode_sort(v, c, toks[2:])
	case "filter":
		decode_filter(v, c, toks[2:])
	}

}

// decode_sort adds column c to the sort in the direction toks give, the
// first time a line names it.
@(private)
decode_sort :: proc(v: ^View, c: int, toks: []string) {
	if sort_rank(v, c) < 0 && len(toks) > 0 {
		append(&v.sort, Sort_Key{c, toks[0] == "desc"})
	}
}

// decode_column_line places column c next in the order with the state
// toks give it, the first time a line names it.
@(private)
decode_column_line :: proc(v: ^View, cols: []Column, c: int, toks: []string, named: []bool) {
	if named[c] {
		return
	}
	named[c] = true
	append(&v.order, c)
	v.cols[c] = decode_column(cols[c], toks)
}

// column_index is the column named id, -1 for none.
column_index :: proc(cols: []Column, id: string) -> int {
	for c, i in cols {
		if c.id == id {
			return i
		}
	}
	return -1
}

@(private)
decode_column :: proc(c: Column, toks: []string) -> (s: Column_State) {
	for i := 0; i < len(toks); i += 1 {
		value := toks[i + 1] if i + 1 < len(toks) else ""
		switch toks[i] {
		case "hidden":
			s.hidden = true
		case "width":
			s.width = decode_width(c, value)
			i += 1
		case "pin":
			s.pin = .Left if value == "left" else .Right if value == "right" else .None
			i += 1
		}
	}
	return
}

// decode_width is a width a view wrote, within c's bounds; 0 for one it
// cannot read.
@(private)
decode_width :: proc(c: Column, value: string) -> f32 {
	w, ok := strconv.parse_f64(value)
	if !ok || !(w > 0) || w >= f64(INF) {
		return 0
	}
	return clamp_width(c, f32(w))
}

@(private)
decode_filter :: proc(v: ^View, c: int, toks: []string) {
	if len(toks) == 0 || find_filter(v, c) != nil {
		return
	}
	switch toks[0] {
	case "set":
		view_set_values(v, c, toks[1:])
	case "text":
		if len(toks) > 1 {
			view_set_text(v, c, toks[1])
		}
	case "range":
		if len(toks) > 2 {
			view_set_range(v, c, decode_bound(toks[1]), decode_bound(toks[2]))
		}
	}
}

// decode_bound is a range bound a view wrote, nil for an open one.
@(private)
decode_bound :: proc(tok: string) -> Maybe(f64) {
	if v, ok := strconv.parse_f64(tok); ok {
		return v
	}
	return nil
}

// tokens splits line into words and quoted strings, the quotes taken off

// and the escapes undone. A quoted string left open runs to the line's
// end.
tokens :: proc(line: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	i := 0
	for i < len(line) {
		switch line[i] {
		case ' ', '\t', '\r':
			i += 1
		case '"':
			s, next := unquote(line, i + 1, allocator)
			append(&out, s)
			i = next
		case:
			j := i
			for j < len(line) && line[j] != ' ' && line[j] != '\t' && line[j] != '\r' {
				j += 1
			}
			append(&out, line[i:j])
			i = j
		}
	}
	return out[:]
}

// unquote reads a quoted string's body from line[i:] up to its closing
// quote, and returns it and where reading stopped.
@(private)
unquote :: proc(line: string, i: int, allocator: mem.Allocator) -> (string, int) {
	b := strings.builder_make(allocator)
	i := i
	for i < len(line) {
		c := line[i]
		switch {
		case c == '"':
			return strings.to_string(b), i + 1
		case c != '\\' || i + 1 >= len(line):
			strings.write_byte(&b, c)
			i += 1
		case:
			i = unescape(&b, line, i + 1)
		}
	}
	return strings.to_string(b), i
}

// unescape writes the byte the escape at line[i], after its backslash,
// stands for, and returns where reading goes on.
@(private)
unescape :: proc(b: ^strings.Builder, line: string, i: int) -> int {
	e := line[i]
	switch e {
	case 'n':
		strings.write_byte(b, '\n')
	case 'r':
		strings.write_byte(b, '\r')
	case 't':
		strings.write_byte(b, '\t')
	case 'x':
		if i + 3 > len(line) {
			return i + 1
		}
		if h, ok := strconv.parse_u64_of_base(line[i + 1:i + 3], 16); ok {
			strings.write_byte(b, u8(h))
		}
		return i + 3
	case:
		strings.write_byte(b, e)
	}
	return i + 1
}
