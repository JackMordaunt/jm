package datagrid

import "core:fmt"
import "core:mem"
import "core:slice"
import "core:strings"
import "core:testing"
import "core:time"

// The query (natural order, dates, filters, sorts, groups), saved views
// and the page cache on worked examples.

@(private = "file")
Table :: struct {
	rows: [][]string,
}

@(private = "file")
table_source :: proc(t: ^Table) -> Source {
	text :: proc(user: rawptr, row, col: int) -> string {
		return (^Table)(user).rows[row][col]
	}
	return {user = t, rows = len(t.rows), text = text}
}

@(private = "file")
COLS := []Column {
	{id = "name", title = "Name"},
	{id = "site", title = "Site", filter = .Set},
	{id = "hash", title = "Hashrate", kind = .Number, filter = .Range},
	{id = "made", title = "Created", kind = .Date},
}

@(private = "file")
ROWS := [][]string {
	{"rig10", "Norway", "200", "2026-01-05"},
	{"rig2", "Paraguay", "95.5", "2025-12-31"},
	{"Rig1", "Norway", "", "2026-03-01T10:00:00Z"},
	{"rig3", "Ethiopia", "1,250", "bad"},
	{"rig2", "Norway", "95.5", "2026-01-05"},
}

@(test)
test_compare_natural_reads_digit_runs_by_value_and_letters_without_case :: proc(t: ^testing.T) {
	testing.expect(t, compare_natural("rig2", "rig10") < 0)
	testing.expect(t, compare_natural("Rig1", "rig2") < 0)
	testing.expect(t, compare_natural("a", "") < 0) // blanks last
	testing.expect(t, compare_natural("item007", "item7") != 0) // total: leading zeros differ by bytes
	testing.expect_value(t, compare_natural("same", "same"), 0)
	testing.expect(t, compare_natural("ABC", "abc") != 0)
	testing.expect_value(t, compare_natural("ABC", "abc"), -compare_natural("abc", "ABC"))
	testing.expect(
		t,
		compare_natural("x99999999999999999999999", "x100000000000000000000000") < 0,
	) // past u64
}

@(test)
test_parse_date_reads_iso_dates_with_and_without_a_time :: proc(t: ^testing.T) {
	d, ok := parse_date("1970-01-02")
	testing.expect(t, ok)
	testing.expect_value(t, d, 86400)
	d, ok = parse_date("2026-03-01T10:00:30Z")
	testing.expect(t, ok)
	testing.expect_value(t, d, 1772359230)
	_, ok = parse_date("2026-13-01")
	testing.expect(t, !ok)
	n, nok := parse_value(.Number, "1,250.5 TH/s")
	testing.expect(t, nok)
	testing.expect_value(t, n, 1250.5)
}

@(test)
test_order_filters_searches_sorts_and_groups :: proc(t: ^testing.T) {
	tb := Table{ROWS}
	src := table_source(&tb)
	v: View
	view_init(&v, COLS, context.temp_allocator)
	visible := make([dynamic]int, context.temp_allocator)
	o: Order
	defer order_destroy(&o)

	view_sort_cycle(&v, 0, false)
	order_build(&o, src, view_query(&v, COLS, &visible))
	// Rig1 rig2 rig2 rig3 rig10, the ties stable.
	testing.expect(t, slice.equal(o.rows[:], []int{2, 1, 4, 3, 0}))

	view_sort_cycle(&v, 2, false) // by hashrate: the blank one last
	order_build(&o, src, view_query(&v, COLS, &visible))
	testing.expect(t, slice.equal(o.rows[:], []int{1, 4, 0, 3, 2}))
	view_sort_cycle(&v, 2, false)
	order_build(&o, src, view_query(&v, COLS, &visible))
	testing.expect(
		t,
		slice.equal(o.rows[:], []int{3, 0, 1, 4, 2}),
		"descending, blanks still last",
	)

	view_set_values(&v, 1, {"Norway", "Paraguay", "Norway"})
	testing.expect_value(t, len(find_filter(&v, 1).rule.(Set_Filter).values), 2)
	view_set_range(&v, 2, 90, 150)
	order_build(&o, src, view_query(&v, COLS, &visible))
	testing.expect(t, slice.equal(o.rows[:], []int{1, 4}))
	view_set_search(&v, "PARA")
	order_build(&o, src, view_query(&v, COLS, &visible))
	testing.expect(t, slice.equal(o.rows[:], []int{1}))
	free_all(context.temp_allocator)
}

@(test)
test_distinct_values_count_under_the_other_filters :: proc(t: ^testing.T) {
	tb := Table{ROWS}
	src := table_source(&tb)
	v: View
	view_init(&v, COLS, context.temp_allocator)
	visible := make([dynamic]int, context.temp_allocator)
	view_set_values(&v, 1, {"Norway"}) // its own filter does not narrow its values
	view_set_range(&v, 2, 100, nil)
	vals := distinct_values(src, view_query(&v, COLS, &visible), 1, context.temp_allocator)
	testing.expect_value(t, len(vals), 2)
	testing.expect_value(t, vals[0], Value_Count{"Ethiopia", 1})
	testing.expect_value(t, vals[1], Value_Count{"Norway", 1})
	free_all(context.temp_allocator)
}

@(test)
test_sort_cycles_and_shift_builds_a_multi_sort :: proc(t: ^testing.T) {
	v: View
	view_init(&v, COLS, context.temp_allocator)
	view_sort_cycle(&v, 0, false)
	testing.expect(t, slice.equal(v.sort[:], []Sort_Key{{0, false}}))
	view_sort_cycle(&v, 1, true)
	view_sort_cycle(&v, 1, true)
	testing.expect(t, slice.equal(v.sort[:], []Sort_Key{{0, false}, {1, true}}))
	view_sort_cycle(&v, 1, true)
	testing.expect(t, slice.equal(v.sort[:], []Sort_Key{{0, false}}))
	view_sort_cycle(&v, 2, false) // a plain click replaces
	testing.expect(t, slice.equal(v.sort[:], []Sort_Key{{2, false}}))
	view_sort_cycle(&v, 2, false)
	view_sort_cycle(&v, 2, false)
	testing.expect_value(t, len(v.sort), 0)
	free_all(context.temp_allocator)
}

@(test)
test_a_view_round_trips_and_survives_a_dropped_column :: proc(t: ^testing.T) {
	v: View
	view_init(&v, COLS, context.temp_allocator)
	move_column(v.order[:], 3, 0)
	v.cols[0].width = 180
	v.cols[1].hidden = true
	v.cols[2].pin = .Left
	view_sort_cycle(&v, 2, false)
	view_sort_cycle(&v, 0, true)
	view_set_values(&v, 1, {"Norway", "say \"hi\"\n"})
	view_set_range(&v, 2, 10.5, nil)
	view_set_search(&v, "rig\t2")
	b := strings.builder_make(context.temp_allocator)
	view_encode(&b, &v, COLS, "Ops \"view\"")

	w: View
	view_init(&w, COLS, context.temp_allocator)
	name, ok := view_decode(&w, COLS, strings.to_string(b), context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, name, "Ops \"view\"")
	testing.expect(t, slice.equal(w.order[:], v.order[:]))
	testing.expect(t, slice.equal(w.cols[:], v.cols[:]))
	testing.expect(t, slice.equal(w.sort[:], v.sort[:]))
	testing.expect(
		t,
		slice.equal(
			find_filter(&w, 1).rule.(Set_Filter).values,
			find_filter(&v, 1).rule.(Set_Filter).values,
		),
	)
	hash := find_filter(&w, 2).rule.(Range_Filter)
	testing.expect_value(t, hash.lo.? or_else -1, 10.5)
	testing.expect(t, hash.hi == nil)

	testing.expect_value(t, w.search, "rig\t2")

	// The next build dropped "site" and added "owner".
	drift := []Column{COLS[0], {id = "owner", title = "Owner", hidden = true}, COLS[2], COLS[3]}
	d: View
	view_init(&d, drift, context.temp_allocator)
	_, ok = view_decode(&d, drift, strings.to_string(b), context.temp_allocator)
	testing.expect(t, ok)
	testing.expect(t, slice.equal(d.order[:], []int{3, 0, 2, 1}), "the new column goes last")
	testing.expect(t, d.cols[1].hidden, "and keeps its declared state")
	testing.expect_value(t, len(d.filters), 1) // site's filter went with it
	testing.expect_value(t, d.cols[0].width, 180)

	_, ok = view_decode(
		&d,
		drift,
		"datagrid-view 1\nname \"old\"\ngroup \"serial\"\n",
		context.temp_allocator,
	)
	testing.expect(t, ok, "a group line a grid wrote before grouping went is passed over")

	_, ok = view_decode(&d, drift, "not a view")
	testing.expect(t, !ok)
	free_all(context.temp_allocator)
}

@(private = "file")
page_of :: proc(index, size, total: int, query: u64) -> Page {
	rows := make([dynamic]Page_Row, context.temp_allocator)
	for i in index * size ..< min((index + 1) * size, total) {
		cells := make([]string, 1, context.temp_allocator)
		cells[0] = strings.clone(itoa(i), context.temp_allocator)
		append(&rows, Page_Row{key = cells[0], cells = cells})
	}
	return {rows = rows[:]}
}

@(private = "file")
itoa :: proc(i: int) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_int(&b, i)
	return strings.to_string(b)
}

@(test)
test_pages_grow_an_unknown_count_until_a_short_page :: proc(t: ^testing.T) {
	p: Pages
	pages_init(&p, {page_size = 10, margin = 1, capacity = 4})
	defer pages_destroy(&p)
	pages_query(&p, 1)
	lo, hi := pages_window(&p, 0, 5)
	// One page of skeleton is all there can be yet.
	testing.expect_value(t, [2]int{lo, hi}, [2]int{0, 1})
	pages_want(&p, lo, hi, nil)
	_, st, _ := pages_row(&p, 3)
	testing.expect_value(t, st, Row_State.Loading)
	pg := page_of(0, 10, 25, 1)
	testing.expect(t, pages_arrive(&p, 1, 0, &pg, 1))
	testing.expect_value(t, p.count, 20) // a page past the full one
	testing.expect_value(t, p.kind, Count_Kind.Unknown)
	row, st2, _ := pages_row(&p, 3)
	testing.expect_value(t, st2, Row_State.Ready)
	testing.expect_value(t, row.key, "3")
	other := page_of(0, 10, 25, 2)
	testing.expect(t, !pages_arrive(&p, 2, 0, &other, 1), "another query's page is refused")

	lo, hi = pages_window(&p, 10, 15)
	testing.expect_value(t, [2]int{lo, hi}, [2]int{0, 2})
	pages_want(&p, lo, hi, {0})
	testing.expect_value(t, pages_find(&p, 1, 1).after.key, "9") // keyset: the row before
	pg1 := page_of(1, 10, 25, 1)
	pages_arrive(&p, 1, 1, &pg1, 1)
	pg2 := page_of(2, 10, 25, 1)
	pages_arrive(&p, 1, 2, &pg2, 1)
	testing.expect_value(t, p.count, 25)
	testing.expect_value(t, p.kind, Count_Kind.Exact)
	_, st3, _ := pages_row(&p, 25)
	testing.expect_value(t, st3, Row_State.Missing)
	free_all(context.temp_allocator)
}

@(test)
test_pages_keep_stale_stand_ins_until_the_new_query_arrives :: proc(t: ^testing.T) {
	p: Pages
	pages_init(&p, {page_size = 10, keep_stale = true, capacity = 2})
	defer pages_destroy(&p)
	pages_query(&p, 1)
	pages_want(&p, 0, 1, nil)
	pg := page_of(0, 10, 100, 1)
	pages_arrive(&p, 1, 0, &pg, 1)
	pages_query(&p, 2)
	row, st, _ := pages_row(&p, 4)
	testing.expect_value(t, st, Row_State.Stale)
	testing.expect_value(t, row.key, "4")
	pages_want(&p, 0, 1, nil)
	pg2 := page_of(0, 10, 100, 2)
	pages_arrive(&p, 2, 0, &pg2, 1)
	pages_evict(&p, 0, 1)
	testing.expect_value(t, len(p.entries), 1) // the stand-in goes once its page has come
	_, st2, _ := pages_row(&p, 4)
	testing.expect_value(t, st2, Row_State.Ready)
	// Eviction keeps the window and drops the farthest.
	for i in 1 ..< 6 {
		pages_want(&p, i, i + 1, nil)
	}
	pages_evict(&p, 5, 6)
	testing.expect_value(t, len(p.entries), 2)
	testing.expect(t, pages_find(&p, 2, 5) != nil && pages_find(&p, 2, 4) != nil)
	free_all(context.temp_allocator)
}

@(test)
test_an_empty_page_bounds_the_count_and_ends_it_after_a_full_one :: proc(t: ^testing.T) {
	p: Pages
	pages_init(&p, {page_size = 10, estimate = 100})
	defer pages_destroy(&p)
	pages_query(&p, 1)
	// 25 rows: page 6 is past them, empty, and says only that.
	empty := page_of(6, 10, 25, 1)
	testing.expect_value(t, len(empty.rows), 0)
	pages_arrive(&p, 1, 6, &empty, 1)
	testing.expect_value(t, p.count, 60)
	testing.expect(t, !p.end, "the rows end at 60 or before, not at 60")
	full := page_of(1, 10, 25, 1)
	pages_arrive(&p, 1, 1, &full, 1)
	testing.expect_value(t, p.count, 60) // an estimate, held to the bound
	short := page_of(2, 10, 25, 1)
	pages_arrive(&p, 1, 2, &short, 2)
	testing.expect_value(t, [2]int{p.count, int(p.end)}, [2]int{25, 1})
	// An empty page right after a full one ends the rows exactly there.
	pages_query(&p, 2)
	f0 := page_of(0, 10, 10, 2)
	e1 := page_of(1, 10, 10, 2)
	pages_arrive(&p, 2, 1, &e1, 3)
	pages_arrive(&p, 2, 0, &f0, 4)
	testing.expect_value(t, [2]int{p.count, int(p.end)}, [2]int{10, 1})
	free_all(context.temp_allocator)
}

// Fresh is a source whose every text is made anew in the temp allocator,
// as a source that formats its cells is: a build over several frames
// must keep its own copies.
@(private = "file")
Fresh :: struct {
	n: int,
}

@(private = "file")
fresh_source :: proc(f: ^Fresh) -> Source {
	text :: proc(user: rawptr, row, col: int) -> string {
		switch col {
		case 0:
			return fmt.tprintf("rig%d", (row * 7919) % 1000)
		case 1:
			return SITE_NAMES[row % len(SITE_NAMES)]
		case 2:
			return fmt.tprintf("%d", (row * 37) % 500)
		}
		return fmt.tprintf("2026-0%d-1%d", 1 + row % 9, row % 10)
	}
	return {user = f, rows = f.n, text = text}
}

@(private = "file")
SITE_NAMES := []string{"Norway", "Paraguay", "Ethiopia", "Wisconsin"}

@(test)
test_an_order_built_a_chunk_at_a_time_is_the_order_built_at_once :: proc(t: ^testing.T) {
	f := Fresh{5000}
	src := fresh_source(&f)
	v: View
	view_init(&v, COLS) // not the temp allocator, which each step frees
	defer view_destroy(&v)
	view_sort_cycle(&v, 0, false)
	view_sort_cycle(&v, 2, true)
	view_sort_cycle(&v, 2, true) // descending
	view_set_values(&v, 1, {"Norway", "Ethiopia", "Wisconsin"})
	view_set_range(&v, 2, 20, nil)
	visible: [dynamic]int
	defer delete(visible)
	q := view_query(&v, COLS, &visible)
	whole: Order
	defer order_destroy(&whole)
	order_build(&whole, src, q)
	sliced: Order
	defer order_destroy(&sliced)
	job: Order_Job
	order_start(&job, &sliced)
	steps := 1
	// A deadline long gone: each step does one chunk, the least it may.
	for !order_step(&job, &sliced, src, q, time.Tick{1}) {
		free_all(context.temp_allocator) // the frame's texts go, as a frame's do
		steps += 1
	}
	testing.expect(t, steps > 20, "the build took many steps")
	testing.expect(t, len(whole.rows) > 1000)
	testing.expect(t, slice.equal(whole.rows[:], sliced.rows[:]))
}

@(test)
test_values_hash_moves_with_the_other_filters_only :: proc(t: ^testing.T) {
	v: View
	view_init(&v, COLS, context.temp_allocator)
	visible := make([dynamic]int, context.temp_allocator)
	before := values_hash(view_query(&v, COLS, &visible), 1)
	view_set_values(&v, 1, {"Norway"}) // the column's own choice
	view_set_search(&v, "rig") // the counts leave the search out
	testing.expect_value(t, values_hash(view_query(&v, COLS, &visible), 1), before)
	view_set_range(&v, 2, 100, nil)
	testing.expect(t, values_hash(view_query(&v, COLS, &visible), 1) != before)
}

@(test)
test_a_filter_that_changes_kind_hashes_as_its_new_kind_alone :: proc(t: ^testing.T) {
	visible := make([dynamic]int, context.temp_allocator)
	clean: View
	view_init(&clean, COLS, context.temp_allocator)
	view_set_text(&clean, 0, "rig")
	changed: View
	view_init(&changed, COLS, context.temp_allocator)
	view_set_values(&changed, 0, {"rig2"})
	view_set_range(&changed, 0, 1, 9)
	view_set_text(&changed, 0, "rig")
	testing.expect_value(
		t,
		match_hash(view_query(&changed, COLS, &visible)),
		match_hash(view_query(&clean, COLS, &visible)),
	)
	before := match_hash(view_query(&clean, COLS, &visible))
	view_set_text(&clean, 0, "rig2")
	testing.expect(t, match_hash(view_query(&clean, COLS, &visible)) != before)
}

@(test)
test_toggling_values_keeps_a_sorted_set_and_frees_what_it_drops :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	v: View
	view_init(&v, COLS, mem.tracking_allocator(&track))
	view_set_text(&v, 1, "way")
	view_toggle_value(&v, 1, "Paraguay")
	view_toggle_value(&v, 1, "Norway")
	view_toggle_value(&v, 1, "Wisconsin")
	view_toggle_value(&v, 1, "Paraguay")
	values := find_filter(&v, 1).rule.(Set_Filter).values
	testing.expect(t, slice.equal(values, []string{"Norway", "Wisconsin"}), fmt.tprint(values))
	view_set_values(&v, 1, values) // its own values, cloned before the old go
	values = find_filter(&v, 1).rule.(Set_Filter).values
	testing.expect(t, slice.equal(values, []string{"Norway", "Wisconsin"}), fmt.tprint(values))
	view_destroy(&v)
	testing.expect_value(t, len(track.allocation_map), 0)
	testing.expect_value(t, len(track.bad_free_array), 0)
}
