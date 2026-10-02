package ui

import "core:testing"
import "jm:ui/ops"
import "jm:ui/testutil"

@(test)
test_resolve_tracks_sizes_from_content_then_shares_the_rest :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Auto keeps its content; two growers share 300 - 50 = 250 equally.
	w := resolve_tracks({{}, {grow = 1}, {grow = 1}}, {50, 20, 30}, 300, context.temp_allocator)
	testing.expect_value(t, w[0], 50)
	testing.expect_value(t, w[1], 125)
	testing.expect_value(t, w[2], 125)
	// A grower wider than its share keeps its content and the other
	// takes what is left (CSS's "find the size of an fr").
	w = resolve_tracks({{grow = 1}, {grow = 1}}, {250, 10}, 300, context.temp_allocator)
	testing.expect_value(t, w[0], 250)
	testing.expect_value(t, w[1], 50)
	// Shares follow grow; a fixed width is exact whatever its content.
	w = resolve_tracks({{width = 40}, {grow = 1}, {grow = 3}}, {90, 0, 0}, 240, context.temp_allocator)
	testing.expect_value(t, w[0], 40)
	testing.expect_value(t, w[1], 50)
	testing.expect_value(t, w[2], 150)
	// With no room, a collapsing grower shrinks to its min; a plain one
	// keeps its content, so the grid overflows rather than squeezes.
	w = resolve_tracks({{grow = 1, collapse = true, min = 8}, {grow = 1}}, {100, 100}, 120, context.temp_allocator)
	testing.expect_value(t, w[0], 20)
	testing.expect_value(t, w[1], 100)
	w = resolve_tracks({{grow = 1, collapse = true, min = 8}, {grow = 1}}, {100, 100}, 90, context.temp_allocator)
	testing.expect_value(t, w[0], 8)
	testing.expect_value(t, w[1], 100)
	// max caps both the content and the share; min floors them.
	w = resolve_tracks({{max = 30}, {grow = 1, max = 60}, {min = 70}}, {80, 0, 10}, 400, context.temp_allocator)
	testing.expect_value(t, w[0], 30)
	testing.expect_value(t, w[1], 60)
	testing.expect_value(t, w[2], 70)
	// Unbounded: nothing to share, every track at its base.
	w = resolve_tracks({{grow = 1}, {}}, {12, 34}, INF, context.temp_allocator)
	testing.expect_value(t, w[0], 12)
	testing.expect_value(t, w[1], 34)
}

@(private = "file")
Painted :: struct {
	lines: Grid_Lines,
	calls: int,
}

@(private = "file")
record_lines :: proc(gtx: ^Ctx, id: ops.Area_Id, lines: Grid_Lines, user: rawptr) {
	p := (^Painted)(user)
	p.lines = lines
	p.calls += 1
	ops.fill(gtx.scene, ops.Rect{0, 0, lines.size.x, lines.size.y}, ops.Color{1, 2, 3, 255})
}

@(private = "file")
tag_bounds :: proc(h: ^Harness) -> map[string]ops.Rect {
	frame: Frame
	frame_init(&frame, context.temp_allocator)
	flatten(&h.scene, &frame)
	at := make(map[string]ops.Rect, context.temp_allocator)
	for tg in frame.tags {
		at[tg.name] = tg.bounds
	}
	return at
}

// Every cell in a column shares the column's width, set by its widest
// cell; the growing column takes the rest; rows are their tallest cell.
@(test)
test_grid_sizes_columns_from_their_widest_cell_across_rows :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {400, 300})
	defer harness_destroy(&h)
	gtx := &h.gtx
	painted: Painted
	{
		col := column_open(gtx); defer close(&col)
		g := grid_open(gtx, {{}, {grow = 1}, {align = .End}}, column_gap = 8, row_gap = 4, paint = record_lines, user = &painted)
		defer close(&g)
		label(gtx, "a")
		label(gtx, "b")
		label(gtx, "c1")
		label(gtx, "dddd") // widens column 0 for row 1 too
		label(gtx, "e")
		label(gtx, "f")
	}
	at := tag_bounds(&h)
	testing.expect_value(t, painted.calls, 1)
	l := painted.lines
	testing.expect(t, testutil.near(l.col_w[0], 4 * W))
	testing.expect(t, testutil.near(l.col_w[2], 2 * W))
	testing.expect(t, testutil.near(l.col_w[1], 400 - 16 - 6 * W))
	testing.expect_value(t, l.size, ops.Size{400, 14 + 4 + 14})
	testing.expect_value(t, l.row_y[1], 18)
	b, has_b := at["b"]
	e, has_e := at["e"]
	f, has_f := at["f"]
	testing.expect(t, has_b && has_e && has_f)
	testing.expect(t, testutil.near(b.x, 4 * W + 8)) // after the widest cell of column 0, row 2's
	testing.expect(t, testutil.near(e.x, b.x))
	testing.expect_value(t, e.y, 18)
	testing.expect(t, testutil.near(f.x, 400 - W)) // end-aligned: "f" is narrower than "c1"
	// The paint ran under the cells: its fill is drawn before any glyphs.
	frame: Frame
	frame_init(&frame, context.temp_allocator)
	flatten(&h.scene, &frame)
	fill, glyphs := -1, -1
	for d, i in frame.draws {
		_, is_fill := d.cmd.(ops.Fill)
		_, is_glyphs := d.cmd.(ops.Glyphs)
		if is_fill && fill < 0 {
			fill = i
		}
		if is_glyphs && glyphs < 0 {
			glyphs = i
		}
	}
	testing.expect(t, fill >= 0 && glyphs >= 0 && fill < glyphs)
}

// grid_span gives a child a row of its own, wherever the row before
// stopped, and it is offered the grid's whole width.
@(test)
test_grid_span_takes_a_row_of_its_own :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {300, 300})
	defer harness_destroy(&h)
	gtx := &h.gtx
	painted: Painted
	offered: f32
	{
		col := column_open(gtx); defer close(&col)
		g := grid_open(gtx, {{}, {}}, paint = record_lines, user = &painted)
		defer close(&g)
		label(gtx, "a")
		grid_span(gtx)
		{
			r := row_open(gtx); defer close(&r)
			offered = gtx.constraints.max.x
			label(gtx, "group")
		}
		label(gtx, "b")
		label(gtx, "c")
	}
	l := painted.lines
	testing.expect_value(t, len(l.row_h), 3)
	testing.expect_value(t, l.spans[1], true)
	testing.expect_value(t, l.spans[2], false)
	testing.expect_value(t, offered, 300)
	at := tag_bounds(&h)
	testing.expect_value(t, at["group"].y, 14)
	testing.expect_value(t, at["b"].y, 28)
	testing.expect(t, testutil.near(at["c"].x, at["b"].x + W))
}

// A cell wider than a collapsed column is clipped to it.
@(test)
test_grid_clips_a_cell_wider_than_its_collapsed_column :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {100, 100})
	defer harness_destroy(&h)
	gtx := &h.gtx
	{
		col := column_open(gtx); defer close(&col)
		g := grid_open(gtx, {{grow = 1, collapse = true}, {grow = 1}})
		defer close(&g)
		label(gtx, "aaaaaaaaaa") // 10W = 84
		label(gtx, "bbbbbbb") // 7W = 58.8: column 1 keeps it, column 0 gets the rest
	}
	clip := index_of(&h.scene, ops.Push_Clip)
	testing.expect(t, clip >= 0)
	r := h.scene.ops[clip].(ops.Push_Clip).shape.(ops.Rect)
	testing.expect(t, testutil.near(r.w, 100 - 7 * W))
}
