package ui

import "core:mem/virtual"
import "core:testing"
import "jm:ui/ops"

@(test)
test_window_drag_flattens_in_device_pixels :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	sc: ops.Scene
	ops.init(&sc)
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)

	ops.transform_push(&sc, ops.scale(2, 2))
	ops.window_drag(&sc, {10, 0, 40, 16})
	ops.transform_pop(&sc)
	flatten(&sc, &f)
	testing.expect_value(t, len(f.drags), 1)
	if len(f.drags) == 1 {
		testing.expect_value(t, f.drags[0], ops.Rect{20, 0, 80, 32})
	}

	ops.reset(&sc)
	m := ops.macro_open(&sc)
	ops.window_drag(&sc, {0, 0, 10, 10})
	ops.macro_close(&sc, m)
	ops.transform_push(&sc, ops.translate(5, 7))
	ops.call(&sc, m)
	ops.transform_pop(&sc)
	flatten(&sc, &f)
	testing.expect_value(t, len(f.drags), 1)
	if len(f.drags) == 1 {
		testing.expect_value(t, f.drags[0], ops.Rect{5, 7, 10, 10})
	}

	ops.reset(&sc)
	ops.window_drag(&sc, {})
	ops.window_drag(&sc, {0, 0, 0, 4})
	ops.window_drag(&sc, {1, 2, -3, 4})
	testing.expect_value(t, len(sc.ops), 0)

	gtx := Ctx{scene = &sc}
	window_drag(&gtx, {1, 2, 3, 4})
	empty: Ctx
	window_drag(&empty, {1, 2, 3, 4})
	testing.expect_value(t, len(sc.ops), 1)

	bytes := ops.encode(&sc)
	dst: ops.Scene
	ops.init(&dst)
	testing.expect(t, ops.decode(bytes, &dst))
	testing.expect_value(t, ops.dump(&dst), ops.dump(&sc))
}
