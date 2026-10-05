package ui

import "core:testing"

import "jm:ui/ops"

// Two nested guards each get back the handle they held, innermost first,
// and the next frame starts with nothing held.
@(test)
test_guard_handles_nest :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	outer := guard_hold(&h.gtx, int)
	outer^ = 1
	inner := guard_hold(&h.gtx, f32)
	inner^ = 2
	testing.expect_value(t, guard_take(&h.gtx, f32)^, f32(2))
	testing.expect_value(t, guard_take(&h.gtx, int)^, 1)
	harness_frame(&h)
	testing.expect_value(t, len(h.layout.held), 0)
}

// A guard called as a statement closes at the end of the enclosing block,
// so a proc may open its container on its first line.
@(test)
test_a_guard_called_as_a_statement_closes_with_its_block :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	Row_Of_Two :: proc(t: ^testing.T, gtx: ^Ctx) {
		row(gtx, gap = 4)
		label(gtx, "a")
		label(gtx, "b")
		testing.expect_value(t, depth(gtx.layout), 1)
	}
	Row_Of_Two(t, &h.gtx)
	testing.expect_value(t, depth(&h.layout), 0)
	{
		column(&h.gtx)
		scope(&h.gtx, 7)
		testing.expect_value(t, depth(&h.layout), 1)
		testing.expect(t, h.layout.scope != 0)
	}
	testing.expect_value(t, depth(&h.layout), 0)
	testing.expect_value(t, h.layout.scope, 0)
}

// The grid, overlay and scope guards open what their pairs open and put
// everything back at the end of the block.
@(test)
test_grid_overlay_and_scope_guards_nest :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	l := &h.layout
	if column(gtx) {
		if grid(gtx, {{}, {grow = 1}}, column_gap = 4) {
			testing.expect(t, innermost(l).kind == .Grid)
			label(gtx, "a")
			label(gtx, "b")
		}
		testing.expect(t, innermost(l).kind == .Flex)
		if overlay(gtx, {10, 10}) {
			// An overlay lays out from a fresh root.
			testing.expect_value(t, depth(l), 0)
			label(gtx, "over")
		}
		testing.expect_value(t, depth(l), 1)
		if scope(gtx, "row") {
			testing.expect(t, l.scope != 0)
		}
		testing.expect_value(t, l.scope, 0)
	}
	testing.expect_value(t, depth(l), 0)
	harness_frame(&h)
	testing.expect_value(t, len(h.layout.held), 0)
}

// The scope guard mixes the same value scope_open does for every kind of
// value scope_open takes, so ids, and retain, agree across the two forms.
@(test)
test_scope_guard_mixes_what_scope_open_mixes :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	gtx := &h.gtx
	Page :: enum u8 {
		Home,
		Settings,
	}
	Key :: distinct u64
	state: int
	opened :: proc(gtx: ^Ctx, v: $T) -> ops.Area_Id {
		s := scope_open(gtx, v)
		defer scope_close(&s)
		return gtx.layout.scope
	}
	guarded :: proc(gtx: ^Ctx, v: any) -> ops.Area_Id {
		scope(gtx, v)
		return gtx.layout.scope
	}
	testing.expect_value(t, guarded(gtx, i64(-3)), opened(gtx, i64(-3)))
	testing.expect_value(t, guarded(gtx, u8(200)), opened(gtx, u8(200)))
	testing.expect_value(t, guarded(gtx, Key(1 << 40)), opened(gtx, Key(1 << 40)))
	testing.expect_value(t, guarded(gtx, Page.Settings), opened(gtx, Page.Settings))
	testing.expect_value(t, guarded(gtx, "row 4"), opened(gtx, "row 4"))
	testing.expect_value(t, guarded(gtx, &state), opened(gtx, &state))
	testing.expect(t, guarded(gtx, "a") != guarded(gtx, "b"))
	testing.expect_value(t, h.layout.scope, 0)
}

// A guarded grid places its cells exactly where the explicit pair does.
@(test)
test_grid_guard_and_pair_place_cells_the_same :: proc(t: ^testing.T) {
	Draw :: proc(gtx: ^Ctx, guarded: bool) {
		if guarded {
			if grid(gtx, {{}, {grow = 1}}, column_gap = 8, row_gap = 4) {
				label(gtx, "a")
				label(gtx, "bb")
				label(gtx, "ccc")
				label(gtx, "d")
			}
		} else {
			g := grid_open(gtx, {{}, {grow = 1}}, column_gap = 8, row_gap = 4)
			defer close(&g)
			label(gtx, "a")
			label(gtx, "bb")
			label(gtx, "ccc")
			label(gtx, "d")
		}
	}
	Placed :: proc(h: ^Harness) -> []ops.Tag {
		frame: Frame
		frame_init(&frame, context.temp_allocator)
		flatten(&h.scene, &frame)
		return frame.tags[:]
	}
	a, b: Harness
	harness_init(&a)
	harness_init(&b)
	defer harness_destroy(&a)
	defer harness_destroy(&b)
	Draw(&a.gtx, true)
	Draw(&b.gtx, false)
	ta, tb := Placed(&a), Placed(&b)
	testing.expect_value(t, len(ta), 4)
	testing.expect_value(t, len(tb), 4)
	for ii in 0 ..< min(len(ta), len(tb)) {
		testing.expect_value(t, ta[ii].name, tb[ii].name)
		testing.expect_value(t, ta[ii].bounds, tb[ii].bounds)
	}
	// "ccc" starts row 2 in column 0, below "a": the grid placed it.
	testing.expect(t, len(ta) == 4 && ta[2].bounds.x == ta[0].bounds.x && ta[2].bounds.y > ta[0].bounds.y)
}
