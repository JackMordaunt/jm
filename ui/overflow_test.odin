package ui

import "core:strings"
import "core:testing"

@(test)
test_frame_overflow_reports_draws_cut_at_the_sides :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		fill(gtx.ops, Rect{10, 10, 50, 20}, Color{1, 0, 0, 255}) // inside
		fill(gtx.ops, Rect{80, 40, 40, 20}, Color{2, 0, 0, 255}) // 20 past the right
		push_clip(gtx.ops, Rect{0, 70, 50, 20})
		fill(gtx.ops, Rect{30, 70, 40, 20}, Color{3, 0, 0, 255}) // 20 past its clip
		fill(gtx.ops, Rect{60, 70, 40, 20}, Color{4, 0, 0, 255}) // wholly outside: tucked away, not cut
		pop_clip(gtx.ops)
	}
	p: Probe
	probe_init(&p, view, nil, {100, 100}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	list := frame_overflow(probe_current(&p), p.size, context.temp_allocator)
	if !testing.expect_value(t, len(list), 2) {
		return
	}
	testing.expect_value(t, list[0].bounds, Rect{80, 40, 40, 20})
	testing.expect_value(t, list[1].visible.x + list[1].visible.w, f32(50))
	report := overflow_report(probe_current(&p), p.size, context.temp_allocator)
	testing.expect(t, strings.contains(report, "20 past the right"))
}
