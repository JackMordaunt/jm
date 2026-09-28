package ui

import "core:math"
import "core:mem/virtual"
import "core:testing"

@(private = "file")
near :: proc(p, q: Point) -> bool {
	return abs(p.x - q.x) < 1e-4 && abs(p.y - q.y) < 1e-4
}

@(test)
test_flatten_transforms_compose_child_first :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	ops: Ops
	ops_init(&ops)
	f: Frame
	frame_init(&f)

	push_transform(&ops, translate(10, 20))
	push_transform(&ops, rotate(math.PI / 2))
	fill(&ops, Rect{0, 0, 1, 1}, Color{255, 0, 0, 255})
	pop_transform(&ops)
	fill(&ops, Rect{0, 0, 1, 1}, Color{0, 255, 0, 255})
	pop_transform(&ops)
	fill(&ops, Rect{0, 0, 1, 1}, Color{0, 0, 255, 255})
	flatten(&ops, &f)

	testing.expect_value(t, len(f.draws), 3)
	testing.expect(t, f.ops == &ops)
	// Rotate first, then translate: local (1,0) turns to (0,1) and moves by (10,20).
	rot := f.draws[0].transform
	testing.expect(t, near(apply(rot, {0, 0}), {10, 20}))
	testing.expect(t, near(apply(rot, {1, 0}), {10, 21}))
	testing.expect(t, near(apply(rot, {0, 1}), {9, 20}))
	testing.expect_value(t, f.draws[1].transform, translate(10, 20))
	testing.expect_value(t, f.draws[2].transform, IDENTITY)
	for d in f.draws {
		testing.expect_value(t, d.clip, NO_CLIP)
	}
}

@(test)
test_flatten_clip_chain :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	ops: Ops
	ops_init(&ops)
	f: Frame
	frame_init(&f)
	red := Color{255, 0, 0, 255}

	push_clip(&ops, Rect{0, 0, 100, 100}) // clip 0
	push_transform(&ops, translate(5, 5))
	push_clip(&ops, Round_Rect{{0, 0, 50, 50}, 4}) // clip 1, under the translate
	fill(&ops, Rect{0, 0, 1, 1}, red)
	pop_clip(&ops)
	pop_transform(&ops)
	push_clip(&ops, Ellipse{{0, 0, 20, 20}}) // clip 2, sibling of 1
	fill(&ops, Rect{0, 0, 1, 1}, red)
	pop_clip(&ops)
	fill(&ops, Rect{0, 0, 1, 1}, red)
	pop_clip(&ops)
	push_clip(&ops, Rect{0, 0, 10, 10}) // clip 3, a new root
	fill(&ops, Rect{0, 0, 1, 1}, red)
	pop_clip(&ops)
	fill(&ops, Rect{0, 0, 1, 1}, red)
	flatten(&ops, &f)

	testing.expect_value(t, len(f.clips), 4)
	testing.expect_value(t, f.clips[0].parent, NO_CLIP)
	testing.expect_value(t, f.clips[1].parent, Clip_Id(0))
	testing.expect_value(t, f.clips[2].parent, Clip_Id(0))
	testing.expect_value(t, f.clips[3].parent, NO_CLIP)
	testing.expect_value(t, f.clips[0].transform, IDENTITY)
	testing.expect_value(t, f.clips[1].transform, translate(5, 5))
	testing.expect_value(t, f.clips[2].transform, IDENTITY)
	_, is_rrect := f.clips[1].shape.(Round_Rect)
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
	ops: Ops
	ops_init(&ops)
	f: Frame
	frame_init(&f)

	// inner is recorded inside outer's body: skipped there, called from it.
	outer := macro_begin(&ops)
	fill(&ops, Rect{0, 0, 10, 10}, Color{1, 1, 1, 255})
	inner := macro_begin(&ops)
	fill(&ops, Rect{0, 0, 2, 2}, Color{2, 2, 2, 255})
	macro_end(&ops, inner)
	push_transform(&ops, translate(1, 1))
	call(&ops, inner)
	pop_transform(&ops)
	macro_end(&ops, outer)

	push_clip(&ops, Rect{0, 0, 500, 500})
	push_transform(&ops, translate(100, 0))
	call(&ops, outer)
	pop_transform(&ops)
	pop_clip(&ops)
	push_transform(&ops, translate(0, 200))
	call(&ops, outer)
	pop_transform(&ops)
	flatten(&ops, &f)

	// Nothing inline; two calls of outer, each drawing its fill and inner's.
	testing.expect_value(t, len(f.draws), 4)
	testing.expect_value(t, f.draws[0].transform, translate(100, 0))
	testing.expect_value(t, f.draws[0].clip, Clip_Id(0))
	testing.expect_value(t, f.draws[1].transform, translate(101, 1))
	testing.expect_value(t, f.draws[1].clip, Clip_Id(0))
	testing.expect_value(t, f.draws[2].transform, translate(0, 200))
	testing.expect_value(t, f.draws[2].clip, NO_CLIP)
	testing.expect_value(t, f.draws[3].transform, translate(1, 201))
	testing.expect(t, near(apply(f.draws[3].transform, {2, 2}), {3, 203}))
	fill_color :: proc(d: Draw) -> Color {
		return d.cmd.(Fill).paint.(Color)
	}
	testing.expect_value(t, fill_color(f.draws[0]).r, 1)
	testing.expect_value(t, fill_color(f.draws[1]).r, 2)
}

@(test)
test_flatten_hits_and_tags :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	ops: Ops
	ops_init(&ops)
	f: Frame
	frame_init(&f)

	m := macro_begin(&ops)
	input_area(&ops, 30, Rect{0, 0, 5, 5}, {.Press})
	macro_end(&ops, m)
	input_area(&ops, 10, Rect{0, 0, 100, 20}, {.Press, .Release})
	tag(&ops, 10, "Save")
	push_transform(&ops, translate(0, 30))
	push_clip(&ops, Rect{0, 0, 100, 20})
	input_area(&ops, 20, Ellipse{{0, 0, 100, 20}}, {.Move})
	tag(&ops, 20, "Cancel")
	call(&ops, m)
	pop_clip(&ops)
	pop_transform(&ops)
	flatten(&ops, &f)

	testing.expect_value(t, len(f.hits), 3)
	areas := [?]Area_Id{10, 20, 30}
	for h, i in f.hits {
		testing.expect_value(t, h.order, i)
		testing.expect_value(t, h.area, areas[i])
	}
	testing.expect_value(t, f.hits[0].clip, NO_CLIP)
	testing.expect_value(t, f.hits[1].clip, Clip_Id(0))
	testing.expect_value(t, f.hits[1].transform, translate(0, 30))
	testing.expect_value(t, f.hits[1].kinds, Event_Kinds{.Move})
	testing.expect_value(t, f.hits[2].transform, translate(0, 30))
	testing.expect_value(t, len(f.tags), 2)
	testing.expect_value(t, f.tags[0].name, "Save")
	testing.expect_value(t, f.tags[1].id, Area_Id(20))

	// A second flatten resets the frame rather than appending.
	flatten(&ops, &f)
	testing.expect_value(t, len(f.hits), 3)
	testing.expect_value(t, len(f.tags), 2)
}

@(test)
test_flatten_defer_runs_last_under_its_transform_unclipped :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	ops: Ops
	ops_init(&ops)
	f: Frame
	frame_init(&f)

	RED :: Color{255, 0, 0, 255}
	GREEN :: Color{0, 255, 0, 255}
	BLUE :: Color{0, 0, 255, 255}
	push_clip(&ops, Rect{0, 0, 5, 5})
	push_transform(&ops, translate(10, 20))
	menu := macro_begin(&ops)
	fill(&ops, Rect{0, 0, 1, 1}, RED)
	input_area(&ops, 7, Rect{0, 0, 1, 1}, {.Press})
	inner := macro_begin(&ops)
	fill(&ops, Rect{0, 0, 1, 1}, BLUE)
	macro_end(&ops, inner)
	push_transform(&ops, translate(1, 1))
	defer_call(&ops, inner) // a defer from inside a deferred macro
	pop_transform(&ops)
	macro_end(&ops, menu)
	defer_call(&ops, menu)
	pop_transform(&ops)
	pop_clip(&ops)
	fill(&ops, Rect{0, 0, 1, 1}, GREEN) // recorded after the defer, drawn before it
	input_area(&ops, 8, Rect{0, 0, 1, 1}, {.Press})
	flatten(&ops, &f)

	testing.expect_value(t, len(f.draws), 3)
	testing.expect_value(t, f.draws[0].cmd.(Fill).paint.(Color), GREEN)
	testing.expect_value(t, f.draws[1].cmd.(Fill).paint.(Color), RED)
	testing.expect_value(t, f.draws[2].cmd.(Fill).paint.(Color), BLUE)
	testing.expect_value(t, f.draws[1].transform, translate(10, 20))
	testing.expect_value(t, f.draws[2].transform, translate(11, 21))
	testing.expect_value(t, f.draws[1].clip, NO_CLIP) // escapes the clip it was met under
	// The deferred hit is after (above) the one recorded later inline.
	testing.expect_value(t, f.hits[0].area, Area_Id(8))
	testing.expect_value(t, f.hits[1].area, Area_Id(7))
}
