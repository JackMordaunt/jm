package ui

import "core:math"
import "jm:ui/ops"
import "core:testing"

@(private = "file")
add_hit :: proc(
	f: ^Frame,
	area: ops.Area_Id,
	shape: ops.Shape,
	kinds: ops.Event_Kinds,
	m := ops.IDENTITY,
	clip := NO_CLIP,
) {
	append(&f.hits, Hit{area, kinds, shape, m, clip, len(f.hits), 0, .Default, false})
}

// route pushes evs, routes them against f and returns the routed events.
@(private = "file")
route :: proc(r: ^Router, f: ^Frame, evs: ..Raw_Event) -> []Event {
	for e in evs {
		router_push(r, e)
	}
	router_route(r, f)
	return r.events[:]
}

@(private = "file")
expect_event :: proc(
	t: ^testing.T,
	got: Event,
	kind: ops.Event_Kind,
	area: ops.Area_Id,
	pos: ops.Point = {},
	loc := #caller_location,
) {
	testing.expect_value(t, got.kind, kind, loc = loc)
	testing.expect_value(t, got.area, area, loc = loc)
	testing.expect_value(t, got.pos, pos, loc = loc)
}

@(test)
input_hit_test_picks_top_most :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	add_hit(&f, 1, ops.Rect{0, 0, 100, 100}, {.Press})
	add_hit(&f, 2, ops.Rect{50, 50, 100, 100}, {.Press})

	h, ok := hit_test(&f, {75, 75}, .Press)
	testing.expect(t, ok)
	testing.expect_value(t, h.area, 2)
	h, ok = hit_test(&f, {25, 25}, .Press)
	testing.expect(t, ok)
	testing.expect_value(t, h.area, 1)
	_, ok = hit_test(&f, {200, 10}, .Press)
	testing.expect(t, !ok)
}

@(test)
input_hit_test_rotated_rect :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	r := ops.Rect{0, 0, 100, 100}
	m := ops.mul(ops.rotate(math.PI / 4), ops.translate(200, 200))
	add_hit(&f, 1, r, {.Press}, m)

	_, ok := hit_test(&f, ops.apply(m, {50, 50}), .Press)
	testing.expect(t, ok, "center of the rotated rect")
	// The rect is a diamond on screen: its bounding box corners are outside.
	b := ops.transform_rect(m, r)
	corner := ops.Point{b.x + 2, b.y + 2}
	testing.expect(t, ops.rect_contains(b, corner))
	_, ok = hit_test(&f, corner, .Press)
	testing.expect(t, !ok, "bounding box corner of the rotated rect")
}

@(test)
input_hit_test_respects_clip :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	append(&f.clips, Clip{parent = NO_CLIP, shape = ops.Rect{0, 0, 200, 50}, transform = ops.IDENTITY})
	append(&f.clips, Clip{parent = 0, shape = ops.Rect{0, 0, 50, 200}, transform = ops.translate(10, 0)})
	add_hit(&f, 1, ops.Rect{0, 0, 100, 100}, {.Press}, ops.IDENTITY, 1)

	_, ok := hit_test(&f, {30, 25}, .Press)
	testing.expect(t, ok, "inside both clips")
	_, ok = hit_test(&f, {80, 25}, .Press)
	testing.expect(t, !ok, "outside the inner clip")
	_, ok = hit_test(&f, {30, 75}, .Press)
	testing.expect(t, !ok, "outside the outer clip")
	_, ok = hit_test(&f, {5, 25}, .Press)
	testing.expect(t, !ok, "left of the translated inner clip")
}

@(test)
input_hit_test_shapes :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	add_hit(&f, 1, ops.Round_Rect{{0, 0, 100, 100}, 20}, {.Press})
	add_hit(&f, 2, ops.Ellipse{{200, 0, 100, 50}}, {.Press})

	_, ok := hit_test(&f, {1, 1}, .Press)
	testing.expect(t, !ok, "rounded-off corner")
	_, ok = hit_test(&f, {1, 50}, .Press)
	testing.expect(t, ok, "straight edge")
	_, ok = hit_test(&f, {250, 25}, .Press)
	testing.expect(t, ok, "ellipse center")
	_, ok = hit_test(&f, {202, 2}, .Press)
	testing.expect(t, !ok, "ellipse bounds corner")
}

@(test)
input_hit_test_filters_kinds :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	add_hit(&f, 1, ops.Rect{0, 0, 100, 100}, {.Press})
	add_hit(&f, 2, ops.Rect{0, 0, 100, 100}, {.Move})

	h, ok := hit_test(&f, {10, 10}, .Press)
	testing.expect(t, ok)
	testing.expect_value(t, h.area, 1)
	h, ok = hit_test(&f, {10, 10}, .Move)
	testing.expect(t, ok)
	testing.expect_value(t, h.area, 2)
	_, ok = hit_test(&f, {10, 10}, .Scroll)
	testing.expect(t, !ok)
}

@(test)
input_router_travel_is_local_and_ignores_where_the_area_moved :: proc(t: ^testing.T) {
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	// The area is drawn at 2x, then moves 40px right between frames: travel
	// is the pointer's own movement in local units either way.
	a: Frame
	frame_init(&a)
	defer frame_destroy(&a)
	add_hit(&a, 1, ops.Rect{0, 0, 100, 100}, {.Press, .Release, .Move}, ops.mul(ops.scale(2, 2), ops.translate(10, 0)))
	evs := route(&r, &a, {kind = .Press, pos = {20, 20}}, {kind = .Move, pos = {30, 20}})
	if !testing.expect_value(t, len(evs), 2) {
		return
	}
	testing.expect_value(t, evs[1].travel, ops.Point{5, 0})
	b: Frame
	frame_init(&b)
	defer frame_destroy(&b)
	add_hit(&b, 1, ops.Rect{0, 0, 100, 100}, {.Press, .Release, .Move}, ops.mul(ops.scale(2, 2), ops.translate(50, 0)))
	evs = route(&r, &b, {kind = .Move, pos = {36, 20}})
	if !testing.expect_value(t, len(evs), 1) {
		return
	}
	testing.expect_value(t, evs[0].travel, ops.Point{3, 0})
}

@(test)
input_router_grabs_until_release :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	add_hit(&f, 1, ops.Rect{0, 0, 100, 100}, {.Press, .Release, .Move}, ops.translate(10, 10))

	evs := route(
		&r,
		&f,
		{kind = .Press, pos = {20, 20}},
		{kind = .Move, pos = {500, 500}},
		{kind = .Release, pos = {500, 500}},
	)
	if !testing.expect_value(t, len(evs), 3) {
		return
	}
	expect_event(t, evs[0], .Press, 1, {10, 10})
	expect_event(t, evs[1], .Move, 1, {490, 490})
	expect_event(t, evs[2], .Release, 1, {490, 490})
	testing.expect_value(t, r.pressed, 0)

	// With the grab gone, a Move far away reaches nobody.
	evs = route(&r, &f, {kind = .Move, pos = {500, 500}})
	testing.expect_value(t, len(evs), 0)
}

@(test)
input_router_hover_sequence :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	k := ops.Event_Kinds{.Enter, .Leave, .Move}
	add_hit(&f, 1, ops.Rect{0, 0, 50, 50}, k)
	add_hit(&f, 2, ops.Rect{100, 0, 50, 50}, k)

	evs := route(
		&r,
		&f,
		{kind = .Move, pos = {10, 10}},
		{kind = .Move, pos = {20, 20}},
		{kind = .Move, pos = {110, 10}},
		{kind = .Move, pos = {300, 300}},
	)
	want := [?]struct {
		kind: ops.Event_Kind,
		area: ops.Area_Id,
	}{{.Enter, 1}, {.Move, 1}, {.Move, 1}, {.Leave, 1}, {.Enter, 2}, {.Move, 2}, {.Leave, 2}}
	if !testing.expect_value(t, len(evs), len(want)) {
		return
	}
	for w, i in want {
		testing.expectf(
			t,
			evs[i].kind == w.kind && evs[i].area == w.area,
			"event %d: got %v on %d, want %v on %d",
			i,
			evs[i].kind,
			evs[i].area,
			w.kind,
			w.area,
		)
	}
	testing.expect_value(t, r.hover, 0)
}

@(test)
input_router_focus :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	add_hit(&f, 1, ops.Rect{0, 0, 100, 20}, {.Press, .Release, .Key, .Text, .Focus, .Blur})
	add_hit(&f, 2, ops.Rect{0, 50, 100, 20}, {.Press, .Release})

	evs := route(&r, &f, {kind = .Press, pos = {5, 5}}, {kind = .Release, pos = {5, 5}})
	testing.expect_value(t, r.focus, 1)
	if testing.expect_value(t, len(evs), 3) {
		expect_event(t, evs[0], .Focus, 1)
		expect_event(t, evs[1], .Press, 1, {5, 5})
		expect_event(t, evs[2], .Release, 1, {5, 5})
	}

	evs = route(&r, &f, {kind = .Key, key = .Enter}, {kind = .Text, text = "hé"})
	if testing.expect_value(t, len(evs), 2) {
		expect_event(t, evs[0], .Key, 1)
		testing.expect_value(t, evs[0].key, Key.Enter)
		expect_event(t, evs[1], .Text, 1)
		testing.expect_value(t, evs[1].text, "hé")
	}

	// A button that does not take keys leaves focus alone.
	evs = route(&r, &f, {kind = .Press, pos = {5, 55}}, {kind = .Release, pos = {5, 55}})
	testing.expect_value(t, r.focus, 1)
	testing.expect_value(t, len(evs), 2)

	// Empty space blurs; keys are then dropped.
	evs = route(
		&r,
		&f,
		{kind = .Press, pos = {500, 500}},
		{kind = .Release, pos = {500, 500}},
		{kind = .Text, text = "x"},
	)
	testing.expect_value(t, r.focus, 0)
	if testing.expect_value(t, len(evs), 1) {
		expect_event(t, evs[0], .Blur, 1)
	}
}

@(test)
input_router_scroll_passes_through :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	add_hit(&f, 1, ops.Rect{0, 0, 100, 100}, {.Scroll})
	add_hit(&f, 2, ops.Rect{0, 0, 50, 50}, {.Press})

	evs := route(&r, &f, {kind = .Scroll, pos = {10, 10}, scroll = {0, 3}})
	if testing.expect_value(t, len(evs), 1) {
		expect_event(t, evs[0], .Scroll, 1, {10, 10})
		testing.expect_value(t, evs[0].scroll, [2]f32{0, 3})
	}
}

@(test)
input_router_nil_frame :: proc(t: ^testing.T) {
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	evs := route(&r, nil, {kind = .Press, pos = {1, 1}}, {kind = .Text, text = "dropped"})
	testing.expect_value(t, len(evs), 0)
}
