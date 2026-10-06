package datagrid

import "core:encoding/csv"
import "core:slice"
import "core:strings"
import "core:testing"

// Column widths and placement, row heights, the selection and delimited
// text on worked examples.

@(test)
test_widths_grow_to_fill_and_shrink_to_fit :: proc(t: ^testing.T) {
	tracks := []Track{{base = 100, min = 40, grow = 1}, {base = 50, min = 40, rigid = true}, {base = 100, min = 40, max = 120, grow = 1}}
	out: [3]f32
	solve_widths(tracks, 400, .Scroll, out[:])
	// 150 left over: 75 each, but the third caps at 120, so the first takes
	// the 55 it could not.
	testing.expect_value(t, out, [3]f32{230, 50, 120})
	solve_widths(tracks, 200, .Scroll, out[:])
	testing.expect_value(t, out, [3]f32{100, 50, 100}) // too wide: scroll
	solve_widths(tracks, 200, .Shrink, out[:])
	testing.expect_value(t, out, [3]f32{75, 50, 75}) // the rigid one keeps its 50
	solve_widths(tracks, 100, .Shrink, out[:])
	testing.expect_value(t, out, [3]f32{40, 50, 40}) // no further than min
}

@(test)
test_place_columns_pins_left_and_right_and_virtualises_the_middle :: proc(t: ^testing.T) {
	cols := []Column{{id = "a", sizing = .Fixed, width = 100}, {id = "b", sizing = .Fixed, width = 100}, {id = "c", sizing = .Fixed, width = 100}, {id = "d", sizing = .Fixed, width = 100}}
	states := []Column_State{{pin = .Right}, {}, {pin = .Left}, {}}
	order := []int{0, 1, 2, 3}
	p: Placement
	defer placement_destroy(&p)
	place_columns(&p, cols, states, order, 250, .Scroll)
	got := make([dynamic]int, context.temp_allocator)
	for pl in p.places {
		append(&got, pl.col)
	}
	testing.expect(t, slice.equal(got[:], []int{2, 1, 3, 0}))
	testing.expect_value(t, p.left_w, 100)
	testing.expect_value(t, p.mid_w, 200)
	testing.expect_value(t, p.right_w, 100)
	lo, hi := mid_visible(&p, 120, 50) // only the second middle column shows
	testing.expect_value(t, lo, 2)
	testing.expect_value(t, hi, 3)
	lo, hi = mid_visible(&p, 90, 50) // the edge between them
	testing.expect_value(t, lo, 1)
	testing.expect_value(t, hi, 3)
	free_all(context.temp_allocator)
}

@(test)
test_move_column_puts_it_before_the_target :: proc(t: ^testing.T) {
	order := []int{0, 1, 2, 3}
	move_column(order, 0, 3)
	testing.expect(t, slice.equal(order, []int{1, 2, 0, 3}))
	move_column(order, 3, 0)
	testing.expect(t, slice.equal(order, []int{3, 1, 2, 0}))
	move_column(order, 1, 4)
	testing.expect(t, slice.equal(order, []int{3, 2, 0, 1}))
}

@(test)
test_heights_find_rows_and_tops_both_ways :: proc(t: ^testing.T) {
	h: Heights
	defer heights_destroy(&h)
	heights_build(&h, 5, proc(_: rawptr, i: int) -> f64 {return f64(10 * (i + 1))}, nil)
	testing.expect_value(t, heights_top(&h, 0), 0)
	testing.expect_value(t, heights_top(&h, 3), 60)
	testing.expect_value(t, heights_total(&h), 150)
	testing.expect_value(t, heights_at(&h, 0), 0)
	testing.expect_value(t, heights_at(&h, 9.9), 0)
	testing.expect_value(t, heights_at(&h, 10), 1)
	testing.expect_value(t, heights_at(&h, 59), 2)
	testing.expect_value(t, heights_at(&h, 1000), 4)
	heights_set(&h, 0, 100)
	testing.expect_value(t, heights_top(&h, 1), 100)
	testing.expect_value(t, heights_at(&h, 99), 0)
	heights_set_uniform(&h, 1000, 33)
	testing.expect_value(t, heights_top(&h, 10), 330)
	testing.expect_value(t, heights_at(&h, 331), 10)
}

@(test)
test_selection_ranges_replace_the_last_range_and_settle_on_a_new_filter :: proc(t: ^testing.T) {
	s: Selection
	selection_init(&s)
	defer selection_destroy(&s)
	selection_only(&s, 1, "")
	selection_toggle(&s, 5, "") // anchor moves to 5, base {1, 5}
	selection_range(&s, {5, 6, 7}, nil)
	testing.expect_value(t, selection_count(&s, 10), 4)
	selection_range(&s, {5, 4}, nil) // the range shrinks back; 1 stays
	testing.expect(t, selected(&s, 1) && selected(&s, 4) && selected(&s, 5))
	testing.expect(t, !selected(&s, 6) && !selected(&s, 7))

	selection_all(&s, 77)
	set_selected(&s, 3, "", false)
	testing.expect(t, selected(&s, 9) && !selected(&s, 3))
	testing.expect_value(t, selection_count(&s, 10), 9)
	selection_settle(&s, 77, {1, 2, 3}, nil) // the same match: nothing to do
	testing.expect(t, s.all)
	selection_settle(&s, 78, {1, 2, 3}, nil)
	testing.expect(t, !s.all)
	testing.expect(t, selected(&s, 1) && selected(&s, 2) && !selected(&s, 3) && !selected(&s, 9))
}

@(test)
test_csv_and_tsv_read_back_through_core_csv :: proc(t: ^testing.T) {
	fields := []string{"plain", "a,b", `say "hi"`, "two\nlines", "tab\there", "", "=SUM(A1)", "-5"}
	b := strings.builder_make(context.temp_allocator)
	write_record(&b, TSV, fields)
	r: csv.Reader
	r.comma = '\t'
	r.multiline_fields = true
	csv.reader_init_with_string(&r, strings.to_string(b), context.temp_allocator)
	defer csv.reader_destroy(&r)
	got, err := csv.read(&r, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect(t, slice.equal(got, fields), "tsv keeps every field as typed")

	strings.builder_reset(&b)
	write_record(&b, CSV, fields)
	r2: csv.Reader
	r2.multiline_fields = true
	csv.reader_init_with_string(&r2, strings.to_string(b), context.temp_allocator)
	defer csv.reader_destroy(&r2)
	got, err = csv.read(&r2, context.temp_allocator)
	testing.expect(t, err == nil)
	testing.expect_value(t, got[6], "'=SUM(A1)") // a formula is defused
	testing.expect_value(t, got[7], "'-5")
	testing.expect(t, slice.equal(got[:6], fields[:6]))
	free_all(context.temp_allocator)
}

