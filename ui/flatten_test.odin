package ui

import "core:math"
import "core:mem"
import "jm:ui/ops"
import "core:mem/virtual"
import "core:testing"

@(private = "file")
near :: proc(p, q: ops.Point) -> bool {
	return abs(p.x - q.x) < 1e-4 && abs(p.y - q.y) < 1e-4
}

@(test)
test_flatten_transforms_compose_child_first :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	f: Frame
	frame_init(&f)

	ops.transform_push(&sc, ops.translate(10, 20))
	ops.transform_push(&sc, ops.rotate(math.PI / 2))
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, ops.Color{255, 0, 0, 255})
	ops.transform_pop(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, ops.Color{0, 255, 0, 255})
	ops.transform_pop(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, ops.Color{0, 0, 255, 255})
	flatten(&sc, &f)

	testing.expect_value(t, len(f.draws), 3)
	testing.expect(t, f.scene == &sc)
	// Rotate first, then translate: local (1,0) turns to (0,1) and moves by (10,20).
	rot := f.draws[0].transform
	testing.expect(t, near(ops.apply(rot, {0, 0}), {10, 20}))
	testing.expect(t, near(ops.apply(rot, {1, 0}), {10, 21}))
	testing.expect(t, near(ops.apply(rot, {0, 1}), {9, 20}))
	testing.expect_value(t, f.draws[1].transform, ops.translate(10, 20))
	testing.expect_value(t, f.draws[2].transform, ops.IDENTITY)
	for d in f.draws {
		testing.expect_value(t, d.clip, NO_CLIP)
	}
}

@(test)
test_flatten_clip_chain :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	f: Frame
	frame_init(&f)
	red := ops.Color{255, 0, 0, 255}

	ops.clip_push(&sc, ops.Rect{0, 0, 100, 100}) // clip 0
	ops.transform_push(&sc, ops.translate(5, 5))
	ops.clip_push(&sc, ops.Round_Rect{{0, 0, 50, 50}, 4}) // clip 1, under the translate
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, red)
	ops.clip_pop(&sc)
	ops.transform_pop(&sc)
	ops.clip_push(&sc, ops.Ellipse{{0, 0, 20, 20}}) // clip 2, sibling of 1
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, red)
	ops.clip_pop(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, red)
	ops.clip_pop(&sc)
	ops.clip_push(&sc, ops.Rect{0, 0, 10, 10}) // clip 3, a new root
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, red)
	ops.clip_pop(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, red)
	flatten(&sc, &f)

	testing.expect_value(t, len(f.clips), 4)
	testing.expect_value(t, f.clips[0].parent, NO_CLIP)
	testing.expect_value(t, f.clips[1].parent, Clip_Id(0))
	testing.expect_value(t, f.clips[2].parent, Clip_Id(0))
	testing.expect_value(t, f.clips[3].parent, NO_CLIP)
	testing.expect_value(t, f.clips[0].transform, ops.IDENTITY)
	testing.expect_value(t, f.clips[1].transform, ops.translate(5, 5))
	testing.expect_value(t, f.clips[2].transform, ops.IDENTITY)
	_, is_rrect := f.clips[1].shape.(ops.Round_Rect)
	testing.expect(t, is_rrect)

	want := [?]Clip_Id{1, 2, 0, 3, NO_CLIP}
	testing.expect_value(t, len(f.draws), len(want))
	for d, i in f.draws {
		testing.expectf(t, d.clip == want[i], "draw %d clip %d, want %d", i, d.clip, want[i])
	}
}

@(test)
test_flatten_macro_runs_at_each_call :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	f: Frame
	frame_init(&f)

	// inner is recorded inside outer's body: skipped there, called from it.
	outer := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 10, 10}, ops.Color{1, 1, 1, 255})
	inner := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 2, 2}, ops.Color{2, 2, 2, 255})
	ops.macro_close(&sc, inner)
	ops.transform_push(&sc, ops.translate(1, 1))
	ops.call(&sc, inner)
	ops.transform_pop(&sc)
	ops.macro_close(&sc, outer)

	ops.clip_push(&sc, ops.Rect{0, 0, 500, 500})
	ops.transform_push(&sc, ops.translate(100, 0))
	ops.call(&sc, outer)
	ops.transform_pop(&sc)
	ops.clip_pop(&sc)
	ops.transform_push(&sc, ops.translate(0, 200))
	ops.call(&sc, outer)
	ops.transform_pop(&sc)
	flatten(&sc, &f)

	// Nothing inline; two calls of outer, each drawing its fill and inner's.
	testing.expect_value(t, len(f.draws), 4)
	testing.expect_value(t, f.draws[0].transform, ops.translate(100, 0))
	testing.expect_value(t, f.draws[0].clip, Clip_Id(0))
	testing.expect_value(t, f.draws[1].transform, ops.translate(101, 1))
	testing.expect_value(t, f.draws[1].clip, Clip_Id(0))
	testing.expect_value(t, f.draws[2].transform, ops.translate(0, 200))
	testing.expect_value(t, f.draws[2].clip, NO_CLIP)
	testing.expect_value(t, f.draws[3].transform, ops.translate(1, 201))
	testing.expect(t, near(ops.apply(f.draws[3].transform, {2, 2}), {3, 203}))
	fill_color :: proc(d: Draw) -> ops.Color {
		return d.cmd.(ops.Fill).paint.(ops.Color)
	}
	testing.expect_value(t, fill_color(f.draws[0]).r, 1)
	testing.expect_value(t, fill_color(f.draws[1]).r, 2)
}

@(test)
test_flatten_hits_and_tags :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	f: Frame
	frame_init(&f)

	m := ops.macro_open(&sc)
	ops.input_area(&sc, 30, ops.Rect{0, 0, 5, 5}, {.Press})
	ops.macro_close(&sc, m)
	ops.input_area(&sc, 10, ops.Rect{0, 0, 100, 20}, {.Press, .Release})
	ops.tag(&sc, 10, "Save")
	ops.transform_push(&sc, ops.translate(0, 30))
	ops.clip_push(&sc, ops.Rect{0, 0, 100, 20})
	ops.input_area(&sc, 20, ops.Ellipse{{0, 0, 100, 20}}, {.Move})
	ops.tag(&sc, 20, "Cancel")
	ops.call(&sc, m)
	ops.clip_pop(&sc)
	ops.transform_pop(&sc)
	flatten(&sc, &f)

	testing.expect_value(t, len(f.hits), 3)
	areas := [?]ops.Area_Id{10, 20, 30}
	for h, i in f.hits {
		testing.expect_value(t, h.order, i)
		testing.expect_value(t, h.area, areas[i])
	}
	testing.expect_value(t, f.hits[0].clip, NO_CLIP)
	testing.expect_value(t, f.hits[1].clip, Clip_Id(0))
	testing.expect_value(t, f.hits[1].transform, ops.translate(0, 30))
	testing.expect_value(t, f.hits[1].kinds, ops.Event_Kinds{.Move})
	testing.expect_value(t, f.hits[2].transform, ops.translate(0, 30))
	testing.expect_value(t, len(f.tags), 2)
	testing.expect_value(t, f.tags[0].name, "Save")
	testing.expect_value(t, f.tags[1].id, ops.Area_Id(20))

	// A second flatten resets the frame rather than appending.
	flatten(&sc, &f)
	testing.expect_value(t, len(f.hits), 3)
	testing.expect_value(t, len(f.tags), 2)
}

@(test)
test_flatten_defer_runs_last_under_its_transform_unclipped :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	sc: ops.Scene
	ops.init(&sc)
	f: Frame
	frame_init(&f)

	RED :: ops.Color{255, 0, 0, 255}
	GREEN :: ops.Color{0, 255, 0, 255}
	BLUE :: ops.Color{0, 0, 255, 255}
	ops.clip_push(&sc, ops.Rect{0, 0, 5, 5})
	ops.transform_push(&sc, ops.translate(10, 20))
	menu := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, RED)
	ops.input_area(&sc, 7, ops.Rect{0, 0, 1, 1}, {.Press})
	inner := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, BLUE)
	ops.macro_close(&sc, inner)
	ops.transform_push(&sc, ops.translate(1, 1))
	ops.defer_call(&sc, inner) // a defer from inside a deferred macro
	ops.transform_pop(&sc)
	ops.macro_close(&sc, menu)
	ops.defer_call(&sc, menu)
	ops.transform_pop(&sc)
	ops.clip_pop(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, GREEN) // recorded after the defer, drawn before it
	ops.input_area(&sc, 8, ops.Rect{0, 0, 1, 1}, {.Press})
	flatten(&sc, &f)

	testing.expect_value(t, len(f.draws), 3)
	testing.expect_value(t, f.draws[0].cmd.(ops.Fill).paint.(ops.Color), GREEN)
	testing.expect_value(t, f.draws[1].cmd.(ops.Fill).paint.(ops.Color), RED)
	testing.expect_value(t, f.draws[2].cmd.(ops.Fill).paint.(ops.Color), BLUE)
	testing.expect_value(t, f.draws[1].transform, ops.translate(10, 20))
	testing.expect_value(t, f.draws[2].transform, ops.translate(11, 21))
	testing.expect_value(t, f.draws[1].clip, NO_CLIP) // escapes the clip it was met under
	// The deferred hit is after (above) the one recorded later inline.
	testing.expect_value(t, f.hits[0].area, ops.Area_Id(8))
	testing.expect_value(t, f.hits[1].area, ops.Area_Id(7))
}

@(test)
test_flatten_reuses_its_stacks_once_grown :: proc(t: ^testing.T) {
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)

	menu := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 5, 5}, ops.Color{0, 0, 255, 255})
	ops.macro_close(&sc, menu)
	ops.transform_push(&sc, ops.translate(10, 20))
	ops.clip_push(&sc, ops.Rect{0, 0, 50, 50})
	ops.transform_push(&sc, ops.translate(1, 1))
	ops.fill(&sc, ops.Rect{0, 0, 1, 1}, ops.Color{255, 0, 0, 255})
	ops.defer_call(&sc, menu)
	ops.transform_pop(&sc)
	ops.clip_pop(&sc)
	ops.transform_pop(&sc)
	flatten(&sc, &f) // grows the frame's arrays and stacks

	// Flattened again, the same scene needs no new memory from anywhere.
	context.allocator = mem.panic_allocator()
	flatten(&sc, &f)
	testing.expect_value(t, len(f.draws), 2)
	testing.expect_value(t, f.draws[1].transform, ops.translate(11, 21)) // the deferred menu, under the push it met
}

@(test)
test_top_defer_runs_after_a_window_cover :: proc(t: ^testing.T) {
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	// A top layer recorded first, a window cover second: the cover's
	// draw still lands under the top layer's.
	top := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 10, 10}, ops.Color{1, 1, 1, 255})
	ops.macro_close(&sc, top)
	ops.defer_call(&sc, top, root = true, top = true)
	cover := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 20, 20}, ops.Color{2, 2, 2, 255})
	ops.macro_close(&sc, cover)
	ops.defer_call(&sc, cover, root = true, cover = true)
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	flatten(&sc, &f, {0, 0, 100, 100})
	testing.expect_value(t, len(f.draws), 2)
	under := f.draws[0].cmd.(ops.Fill).paint.(ops.Color)
	over := f.draws[1].cmd.(ops.Fill).paint.(ops.Color)
	testing.expect_value(t, under.r, u8(2))
	testing.expect_value(t, over.r, u8(1))
}

// A root Defer escapes every transform met on the way to it but keeps the
// host's density scale: on a 2x display a dialog laid out at the window's
// logical size covers the whole window, not its top-left quarter.
@(test)
test_root_defer_runs_under_the_root_transform :: proc(t: ^testing.T) {
	sc: ops.Scene
	ops.init(&sc)
	defer ops.destroy(&sc)
	ops.transform_push(&sc, ops.scale(2, 2))
	ops.transform_push(&sc, ops.translate(10, 20))
	dialog := ops.macro_open(&sc)
	ops.fill(&sc, ops.Rect{0, 0, 360, 300}, ops.Color{1, 1, 1, 255})
	ops.macro_close(&sc, dialog)
	ops.defer_call(&sc, dialog, root = true)
	ops.transform_pop(&sc)
	ops.transform_pop(&sc)
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	flatten(&sc, &f, {0, 0, 720, 600}, ops.scale(2, 2))
	testing.expect_value(t, len(f.draws), 1)
	testing.expect_value(t, f.draws[0].transform, ops.scale(2, 2))
}
