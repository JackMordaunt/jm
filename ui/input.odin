package ui

import "core:mem"

// Input routing. A platform (ui/sdl, the probe) pushes device events with
// router_push; once per frame, before the ui proc runs, router_route
// hit-tests them against the previous frame and turns them into per-area
// events that widgets read with events(gtx, area). Input is therefore one
// frame late, as in Gio.
//
// Rules, applied to each queued event in arrival order:
//
// - Pointer events (Press, Release, Move, Scroll) go to the top-most hit
//   whose kinds contain the event kind, whose shape contains the point and
//   whose clip chain admits it. Kinds are a filter, not an occluder: an
//   area on top that does not want Scroll lets Scroll through to the one
//   below.
// - A Press grabs its target. Until the Release, Press, Move and Release go
//   to the grabbing area wherever the pointer is, with pos in that area's
//   local space. Release ends the grab.
// - Hover is the top-most hit under the pointer that wants any of Move,
//   Enter or Leave. Move, Press and Release (after the grab ends) update
//   it; a change sends Leave to the old area and Enter to the new. While a
//   grab is held only the grabbing area can be hovered, so a drag does not
//   light up what it crosses; hover is recomputed at the Release point.
//   A Move that leaves every area sets hover to 0 and is delivered nowhere.
// - A Press whose target wants Key or Text takes focus (Blur to the old,
//   Focus to the new). A Press on no area clears focus. A Press on an area
//   that wants neither leaves focus where it is, so clicking a toolbar
//   button does not blur the text field it acts on.
// - Key and Text go to the focused area, else they are dropped.
// - Every delivery honours the target's kinds: an area that did not ask
//   for Enter, Focus or Release never receives one.
//
// Positions: pointer events and Enter/Leave carry pos in the target's local
// space (the hit's transform inverted); Key, Text, Focus and Blur carry a
// zero pos.
//
// The frame given to router_route is read only during that call; the router
// keeps no pointer into it. It remembers the last seen Hit of the hovered,
// pressed and focused areas, so an area missing from a frame can still be
// sent its Leave, Release or Blur.

// Router turns device events into per-area events by hit-testing against
// the previous frame's hits. Widgets read their events during layout.
Router :: struct {
	queue:       [dynamic]Raw_Event, // device events since the last route
	events:      [dynamic]Event, // this frame's routed events
	focus:       Area_Id,
	hover:       Area_Id,
	pressed:     Area_Id, // the area holding the pointer grab; 0 is none
	allocator:   mem.Allocator,

	// Last seen hit of focus, hover and pressed, refreshed each route.
	focus_hit:   Hit,
	hover_hit:   Hit,
	pressed_hit: Hit,
	pointer:     Point, // the device position of the last pointer event, for Event.travel
}

@(private = "file")
HOVER_KINDS :: Event_Kinds{.Move, .Enter, .Leave}

// router_init prepares r; allocator backs the queue, the routed events and
// the copies of Text strings.
router_init :: proc(r: ^Router, allocator := context.allocator) {
	r.allocator = allocator
	r.queue = make([dynamic]Raw_Event, allocator)
	r.events = make([dynamic]Event, allocator)
}

// router_destroy frees everything r owns.
router_destroy :: proc(r: ^Router) {
	release_text(r)
	for e in r.queue {
		if e.kind == .Text {
			delete(e.text, r.allocator)
		}
	}
	delete(r.queue)
	delete(r.events)
	r^ = {}
}

// router_push queues a device event for the next route. Text is copied, so
// the caller's string need not outlive the call.
router_push :: proc(r: ^Router, e: Raw_Event) {
	e := e
	if e.kind == .Text {
		e.text = clone_string(e.text, r.allocator)
	}
	append(&r.queue, e)
}

// router_route hit-tests the queued device events against f (the previous
// frame) and fills r.events for the frame about to be laid out. Call it once
// per frame before the ui proc. f may be nil on the first frame; it is read
// only during this call.
router_route :: proc(r: ^Router, f: ^Frame) {
	release_text(r)
	clear(&r.events)
	refresh(f, r.focus, &r.focus_hit)
	refresh(f, r.hover, &r.hover_hit)
	refresh(f, r.pressed, &r.pressed_hit)
	for e in r.queue {
		switch e.kind {
		case .Press:
			route_press(r, f, e)
		case .Release:
			route_release(r, f, e)
		case .Move:
			update_hover(r, f, e.pos)
			if r.pressed != 0 {
				deliver_pointer(r, r.pressed_hit, e)
			} else if h, ok := hit_test(f, e.pos, .Move); ok {
				deliver_pointer(r, h, e)
			}
		case .Scroll:
			if h, ok := hit_test(f, e.pos, .Scroll); ok {
				deliver_pointer(r, h, e)
			}
		case .Key, .Text:
			if r.focus == 0 || !deliver(r, r.focus_hit, e, {}) {
				if e.kind == .Text {
					delete(e.text, r.allocator)
				}
			}
		case .Enter, .Leave, .Focus, .Blur:
		// Synthesized by the router; a pushed one is ignored.
		}
		if e.kind == .Press || e.kind == .Release || e.kind == .Move {
			r.pointer = e.pos
		}
	}
	clear(&r.queue)
}

// events returns the events routed to area this frame, in arrival order.
// The slice is allocated from gtx.allocator (the frame allocator); Text
// strings in it are valid until the next router_route.
//
// Handling an event can change state that widgets drawn earlier in the
// frame already read, such as a theme, so any area given events asks for
// one more frame to redraw them.
events :: proc(gtx: ^Ctx, area: Area_Id) -> []Event {
	if gtx.router == nil {
		return nil
	}
	out := make([dynamic]Event, gtx.allocator)
	for e in gtx.router.events {
		if e.area == area {
			append(&out, e)
		}
	}
	if len(out) > 0 {
		request_frame(gtx)
	}
	return out[:]
}

// hit_test returns the top-most hit in f under device point p whose kinds
// contain kind, or false when there is none. f may be nil.
hit_test :: proc(f: ^Frame, p: Point, kind: Event_Kind) -> (Hit, bool) {
	return hit_test_any(f, p, {kind})
}

// hit_test_any is hit_test for the top-most hit wanting any of kinds.
@(private = "file")
hit_test_any :: proc(f: ^Frame, p: Point, kinds: Event_Kinds) -> (Hit, bool) {
	if f == nil {
		return {}, false
	}
	#reverse for h in f.hits {
		if h.kinds & kinds != {} && hit_contains(f, h, p) {
			return h, true
		}
	}
	return {}, false
}

// hit_contains reports whether device point p lies in h's shape and inside
// every clip on h's chain.
@(private)
hit_contains :: proc(f: ^Frame, h: Hit, p: Point) -> bool {
	if f == nil || !shape_contains_device(f.ops, h.shape, h.transform, p) {
		return false
	}
	c := h.clip
	for c != NO_CLIP {
		if c < 0 || int(c) >= len(f.clips) {
			return false
		}
		clip := f.clips[c]
		if !shape_contains_device(f.ops, clip.shape, clip.transform, p) {
			return false
		}
		c = clip.parent
	}
	return true
}

// shape_contains_device maps device point p into the local space of m and
// tests it against s. A singular transform contains nothing.
@(private = "file")
shape_contains_device :: proc(ops: ^Ops, s: Shape, m: Affine, p: Point) -> bool {
	inv, ok := invert(m)
	if !ok {
		return false
	}
	return shape_contains(ops, s, apply(inv, p))
}

// shape_contains tests local point p against s. Round_Rect cuts its
// corners; Ellipse uses the normalized distance; Path_Ref tests only the
// path's bounding rect in v1, and a nil ops contains nothing for it.
@(private = "file")
shape_contains :: proc(ops: ^Ops, s: Shape, p: Point) -> bool {
	switch v in s {
	case Rect:
		return rect_contains(v, p)
	case Round_Rect:
		r := v.rect
		if !rect_contains(r, p) {
			return false
		}
		rad := min(v.radius, r.w / 2, r.h / 2)
		if rad <= 0 {
			return true
		}
		c := Point{clamp(p.x, r.x + rad, r.x + r.w - rad), clamp(p.y, r.y + rad, r.y + r.h - rad)}
		d := p - c
		return d.x * d.x + d.y * d.y <= rad * rad
	case Ellipse:
		r := v.rect
		if r.w <= 0 || r.h <= 0 {
			return false
		}
		rx, ry := r.w / 2, r.h / 2
		dx := (p.x - (r.x + rx)) / rx
		dy := (p.y - (r.y + ry)) / ry
		return dx * dx + dy * dy <= 1
	case Path_Ref:
		if ops == nil || int(v.id) >= len(ops.paths) {
			return false
		}
		return rect_contains(shape_bounds(ops, v), p)
	}
	return false
}

// local maps device point p into h's local space; zero when singular.
@(private = "file")
to_local :: proc(h: Hit, p: Point) -> Point {
	inv, ok := invert(h.transform)
	if !ok {
		return {}
	}
	return apply(inv, p)
}

// refresh replaces last with area's hit in f when f still has it; the
// top-most one wins when an id is recorded twice.
@(private = "file")
refresh :: proc(f: ^Frame, area: Area_Id, last: ^Hit) {
	if f == nil || area == 0 {
		return
	}
	#reverse for h in f.hits {
		if h.area == area {
			last^ = h
			return
		}
	}
}

// deliver appends e for h's area with pos, when h's kinds contain e's kind.
@(private = "file")
deliver :: proc(r: ^Router, h: Hit, e: Raw_Event, pos: Point) -> bool {
	if e.kind not_in h.kinds {
		return false
	}
	append(
		&r.events,
		Event {
			kind = e.kind,
			area = h.area,
			pos = pos,
			button = e.button,
			scroll = e.scroll,
			key = e.key,
			mods = e.mods,
			text = e.text,
		},
	)
	return true
}

// deliver_pointer delivers e to h with pos mapped into h's local space,
// and its travel since the last pointer event mapped the same way.
@(private = "file")
deliver_pointer :: proc(r: ^Router, h: Hit, e: Raw_Event) {
	pos := to_local(h, e.pos)
	if deliver(r, h, e, pos) {
		r.events[len(r.events) - 1].travel = pos - to_local(h, r.pointer)
	}
}

// synth delivers a router-made event of kind to h.
@(private = "file")
synth :: proc(r: ^Router, h: Hit, kind: Event_Kind, pos: Point) {
	deliver(r, h, Raw_Event{kind = kind}, pos)
}

@(private = "file")
route_press :: proc(r: ^Router, f: ^Frame, e: Raw_Event) {
	if r.pressed != 0 {
		// Another button while grabbed stays with the grab.
		deliver_pointer(r, r.pressed_hit, e)
		return
	}
	update_hover(r, f, e.pos)
	h, ok := hit_test(f, e.pos, .Press)
	if !ok {
		set_focus(r, {})
		return
	}
	r.pressed = h.area
	r.pressed_hit = h
	if h.kinds & {.Key, .Text} != {} {
		set_focus(r, h)
	}
	deliver_pointer(r, h, e)
}

@(private = "file")
route_release :: proc(r: ^Router, f: ^Frame, e: Raw_Event) {
	if r.pressed != 0 {
		deliver_pointer(r, r.pressed_hit, e)
		r.pressed = 0
		r.pressed_hit = {}
	} else if h, ok := hit_test(f, e.pos, .Release); ok {
		deliver_pointer(r, h, e)
	}
	update_hover(r, f, e.pos)
}

// update_hover moves hover to the area under p, sending Leave and Enter.
@(private = "file")
update_hover :: proc(r: ^Router, f: ^Frame, p: Point) {
	h: Hit
	ok: bool
	if r.pressed != 0 {
		h = r.pressed_hit
		ok = h.kinds & HOVER_KINDS != {} && hit_contains(f, h, p)
	} else {
		h, ok = hit_test_any(f, p, HOVER_KINDS)
	}
	next := h.area if ok else 0
	if next == r.hover {
		return
	}
	if r.hover != 0 {
		synth(r, r.hover_hit, .Leave, to_local(r.hover_hit, p))
	}
	r.hover = next
	r.hover_hit = h if ok else {}
	if ok {
		synth(r, h, .Enter, to_local(h, p))
	}
}

// set_focus moves focus to h (a zero Hit clears it), sending Blur and Focus.
@(private = "file")
set_focus :: proc(r: ^Router, h: Hit) {
	if h.area == r.focus {
		return
	}
	if r.focus != 0 {
		synth(r, r.focus_hit, .Blur, {})
	}
	r.focus = h.area
	r.focus_hit = h
	if h.area != 0 {
		synth(r, h, .Focus, {})
	}
}

// release_text frees the Text strings delivered by the previous route.
@(private = "file")
release_text :: proc(r: ^Router) {
	for e in r.events {
		if e.kind == .Text {
			delete(e.text, r.allocator)
		}
	}
}

@(private = "file")
clone_string :: proc(s: string, allocator: mem.Allocator) -> string {
	b := make([]u8, len(s), allocator)
	copy(b, s)
	return string(b)
}
