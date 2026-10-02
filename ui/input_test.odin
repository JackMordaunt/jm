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
	observes := false,
) {
	append(&f.hits, Hit{area = area, kinds = kinds, shape = shape, transform = m, clip = clip, order = len(f.hits), observes = observes})
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

@(test)
test_an_observer_hears_enter_and_leave_under_what_is_on_top :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	// A wrapping observer (1) under a button (2), and a second button (3)
	// beside them, outside the observer.
	add_hit(&f, 1, ops.Rect{0, 0, 50, 50}, {.Enter, .Leave}, observes = true)
	add_hit(&f, 2, ops.Rect{0, 0, 50, 50}, {.Press, .Release, .Enter, .Leave})
	add_hit(&f, 3, ops.Rect{60, 0, 50, 50}, {.Press, .Release, .Enter, .Leave})
	f.hits[1].cursor = .Pointer
	add_hit(&f, 4, ops.Rect{0, 0, 50, 50}, {.Enter, .Leave}, observes = true) // on top, with a cursor of its own
	f.hits[3].cursor = .Text

	evs := route(&r, &f, {kind = .Move, pos = {10, 10}})
	testing.expect_value(t, len(evs), 3)
	if len(evs) == 3 {
		expect_event(t, evs[0], .Enter, 1, {10, 10})
		expect_event(t, evs[1], .Enter, 4, {10, 10})
		expect_event(t, evs[2], .Enter, 2, {10, 10})
	}
	testing.expect_value(t, r.hover, ops.Area_Id(2)) // observers take no hover
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Pointer) // nor the cursor

	// A press goes to the button; the observer hears nothing more.
	evs = route(&r, &f, {kind = .Press, pos = {12, 10}, button = .Left}, {kind = .Release, pos = {12, 10}, button = .Left})
	for e in evs {
		testing.expect(t, e.area == 2, "only the button takes the press and release")
	}

	evs = route(&r, &f, {kind = .Move, pos = {70, 10}})
	testing.expect_value(t, len(evs), 4)
	if len(evs) == 4 {
		testing.expect_value(t, evs[0].kind, ops.Event_Kind.Leave)
		testing.expect_value(t, evs[1].kind, ops.Event_Kind.Leave)
		testing.expect_value(t, evs[0].area + evs[1].area, ops.Area_Id(1 + 4)) // both observers, in either order
		expect_event(t, evs[2], .Leave, 2, {70, 10})
		expect_event(t, evs[3], .Enter, 3, {70, 10}) // the rect is placed by its shape, not a transform
	}
	testing.expect_value(t, len(r.observed), 0)
}

@(private = "file")
Focus_Model :: struct {
	dialog, menu: bool, // a trapping dialog over the page, and a trapping menu raised inside it
	keep:         bool, // b keeps Tab
	first:        bool, // ask for the dialog's first area this frame
	presses:      int, // presses a heard
}

// focus_view is three page buttons a, b, c in a row, b and c in a plain
// scope; a dialog below them with d1 and d2 in a trap and a popup p1
// raised in it; and a menu with m1 in a trap of its own raised from
// inside the dialog.
@(private = "file")
focus_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Focus_Model)(user)
	focusable :: proc(gtx: ^Ctx, id: ops.Area_Id, name: string, x: f32) {
		ops.input_area(gtx.scene, id, ops.Rect{x, 0, 40, 20}, {.Press, .Release, .Key, .Focus, .Blur})
		ops.tag(gtx.scene, id, name)
	}
	for e in events(gtx, 1) {
		if e.kind == .Press {
			m.presses += 1
		}
	}
	focusable(gtx, 1, "a", 0)
	focus_scope_open(gtx, 70) // a plain scope, named for focus_first
	focusable(gtx, 2, "b", 50)
	focusable(gtx, 3, "c", 100)
	focus_scope_close(gtx)
	ops.input_area(gtx.scene, 4, ops.Rect{150, 0, 40, 20}, {.Press, .Release}) // clickable, never focused
	if m.keep {
		key_interest(gtx, 2, .Tab)
	}
	if m.first {
		focus_first(gtx, m.dialog ? 50 : 70)
		m.first = false
	}
	if !m.dialog {
		return
	}
	d := overlay_open(gtx, {0, 100})
	focus_scope_open(gtx, 50, trap = true)
	focusable(gtx, 10, "d1", 0)
	if m.menu {
		menu := popup_open(gtx, {0, 0, 40, 20}, 60)
		focus_scope_open(gtx, 60, trap = true)
		focusable(gtx, 20, "m1", 0)
		focus_scope_close(gtx)
		popup_close(&menu, {40, 20})
	}
	// A popup with no trap of its own stays in the dialog's.
	tip := popup_open(gtx, {0, 0, 40, 20}, 61, .After)
	focusable(gtx, 12, "p1", 0)
	popup_close(&tip, {40, 20})
	// Recorded after the menu's scope closed: the dialog's again.
	focusable(gtx, 11, "d2", 50)
	focus_scope_close(gtx)
	focusable(gtx, 13, "x", 100) // in the dialog's layer, outside its trap
	overlay_close(&d)
}

@(test)
test_tab_walks_focusable_areas_in_order_and_wraps :: proc(t: ^testing.T) {
	m: Focus_Model
	p: Probe
	probe_init(&p, focus_view, &m, {300, 300})
	defer probe_destroy(&p)
	want :: proc(t: ^testing.T, p: ^Probe, area: ops.Area_Id, loc := #caller_location) {
		testing.expect_value(t, p.router.focus, area, loc = loc)
	}
	probe_key(&p, .Tab)
	want(t, &p, 1) // from nothing, the first
	probe_key(&p, .Tab)
	probe_key(&p, .Tab)
	want(t, &p, 3) // the clickable area that wants no keys is no stop
	probe_key(&p, .Tab)
	want(t, &p, 1)
	probe_key(&p, .Tab, {.Shift})
	want(t, &p, 3)
	probe_key(&p, .Tab, {.Ctrl})
	want(t, &p, 3) // another modifier is not Tab traversal
	testing.expect(t, focus_visible(&Ctx{router = &p.router}))
	// An area that keeps Tab is not left by it.
	m.keep = true
	testing.expect(t, probe_click(&p, "b"))
	probe_key(&p, .Tab)
	want(t, &p, 2)
	probe_key(&p, .Tab, {.Shift})
	want(t, &p, 1) // it kept Tab, not Shift+Tab
}

@(test)
test_a_trap_keeps_focus_in_and_a_newer_trap_suspends_it :: proc(t: ^testing.T) {
	m: Focus_Model
	p: Probe
	probe_init(&p, focus_view, &m, {300, 300})
	defer probe_destroy(&p)
	testing.expect(t, probe_click(&p, "c"))
	m.dialog = true
	probe_frame(&p)
	testing.expect_value(t, p.router.focus, ops.Area_Id(3)) // the trap moves nothing by itself
	probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, ops.Area_Id(10))
	probe_key(&p, .Tab)
	probe_key(&p, .Tab)
	probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, ops.Area_Id(10)) // d1, d2, the popup's p1, and round inside
	probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, p.router.focus, ops.Area_Id(12))
	// A press on the page cannot take focus out, but still lands.
	testing.expect(t, probe_click(&p, "a"))
	testing.expect_value(t, p.router.focus, ops.Area_Id(12))
	testing.expect_value(t, m.presses, 1)
	// A press on nothing leaves it too.
	probe_move(&p, 280, 280)
	router_push(&p.router, {kind = .Press, pos = {280, 280}, button = .Left})
	probe_frame(&p)
	router_push(&p.router, {kind = .Release, pos = {280, 280}, button = .Left})
	probe_frame(&p)
	testing.expect_value(t, p.router.focus, ops.Area_Id(12))
	// The menu's trap, newer, holds Tab until it closes.
	m.menu = true
	probe_frame(&p)
	probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, ops.Area_Id(20))
	probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, ops.Area_Id(20))
	m.menu = false
	probe_frame(&p)
	probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, ops.Area_Id(10))
	// Gone, the dialog lets focus go anywhere again.
	m.dialog = false
	probe_frame(&p)
	testing.expect(t, probe_click(&p, "b"))
	testing.expect_value(t, p.router.focus, ops.Area_Id(2))
}

@(test)
test_focus_first_focuses_the_first_area_in_a_scope :: proc(t: ^testing.T) {
	m := Focus_Model{dialog = true}
	p: Probe
	probe_init(&p, focus_view, &m, {300, 300})
	defer probe_destroy(&p)
	testing.expect_value(t, focused(&Ctx{router = &p.router}), ops.Area_Id(0))
	m.first = true
	probe_frame(&p) // asks
	probe_frame(&p) // routed
	testing.expect_value(t, focused(&Ctx{router = &p.router}), ops.Area_Id(10))
	// With no trap, the first area of a plain scope, not of the frame.
	m.dialog = false
	m.first = true
	probe_frame(&p)
	probe_frame(&p)
	testing.expect_value(t, focused(&Ctx{router = &p.router}), ops.Area_Id(2))
}

@(test)
test_outside_presses_walk_the_popups_from_the_top_until_one_holds_the_press :: proc(t: ^testing.T) {
	f: Frame
	frame_init(&f)
	defer frame_destroy(&f)
	r: Router
	router_init(&r)
	defer router_destroy(&r)
	// The page's button (1); a menu (10) opened from it, which counts the
	// button as inside; a submenu (20) opened from the menu, on top.
	add_hit(&f, 1, ops.Rect{0, 0, 40, 20}, {.Press, .Release})
	add_hit(&f, 10, ops.Rect{0, 0, 40, 20}, {.Outside}, observes = true)
	add_hit(&f, 10, ops.Rect{0, 24, 100, 100}, {.Outside}, observes = true)
	add_hit(&f, 11, ops.Rect{0, 24, 100, 30}, {.Press, .Release})
	add_hit(&f, 20, ops.Rect{104, 24, 100, 100}, {.Outside}, observes = true)

	// A press inside the submenu closes nothing.
	evs := route(&r, &f, {kind = .Press, pos = {150, 50}, button = .Left})
	for e in evs {
		testing.expect(t, e.kind != .Outside, "a press in the top popup is outside nothing")
	}
	route(&r, &f, {kind = .Release, pos = {150, 50}, button = .Left})
	// A press on the menu's item: the submenu above is pressed outside, the
	// walk stops at the menu, and the item still takes the press.
	evs = route(&r, &f, {kind = .Press, pos = {10, 30}, button = .Left})
	testing.expect_value(t, len(evs), 2)
	if len(evs) == 2 {
		expect_event(t, evs[0], .Outside, 20, {10, 30})
		expect_event(t, evs[1], .Press, 11, {10, 30})
	}
	route(&r, &f, {kind = .Release, pos = {10, 30}, button = .Left})
	// A press on the page button is inside the menu (its anchor), so only
	// the submenu hears it; the button takes it.
	evs = route(&r, &f, {kind = .Press, pos = {5, 5}, button = .Right})
	testing.expect_value(t, len(evs), 2)
	if len(evs) == 2 {
		expect_event(t, evs[0], .Outside, 20, {5, 5})
		testing.expect_value(t, evs[0].button, Button.Right) // the popup decides which buttons dismiss
		expect_event(t, evs[1], .Press, 1, {5, 5})
	}
	route(&r, &f, {kind = .Release, pos = {5, 5}, button = .Right})
	// A press outside everything reaches every popup, top first, once each.
	evs = route(&r, &f, {kind = .Press, pos = {300, 300}, button = .Left})
	testing.expect_value(t, len(evs), 2)
	if len(evs) == 2 {
		expect_event(t, evs[0], .Outside, 20, {300, 300})
		expect_event(t, evs[1], .Outside, 10, {300, 300})
	}
	// An area that wants only Outside takes neither hover nor the cursor.
	f.hits[0].cursor = .Pointer
	route(&r, &f, {kind = .Release, pos = {300, 300}, button = .Left}, {kind = .Move, pos = {5, 5}})
	testing.expect_value(t, r.hover, ops.Area_Id(0)) // the button wants no hover kinds
	testing.expect_value(t, router_cursor(&r), ops.Cursor.Pointer)
}
