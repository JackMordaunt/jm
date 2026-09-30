package ui

import "core:mem"
import "jm:ui/ops"

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
// - Paste goes to every area that asked with clipboard_read since the
//   last Paste, then the askers are forgotten (see request.odin).
// - A focus_request moves focus before the queued events are routed.
// - A Press whose top-most target yields (ops.Input_Area.yields, selectable
//   text) goes to the next area under it that wants Press and does not
//   yield, when there is one. If the pointer then drags past YIELD_DRAG
//   device pixels while held, or the press was a double or triple click,
//   the yielding area takes over: the other gets Cancel, the yielder the
//   press (and focus, if it wants keys) and the drag from there.
// - The cursor (router_cursor) is the grabbing area's during a grab, else
//   the top-most area's under the last pointer position, whatever kinds it
//   wants, else Default.
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
	focus:       ops.Area_Id,
	hover:       ops.Area_Id,
	pressed:     ops.Area_Id, // the area holding the pointer grab; 0 is none
	allocator:   mem.Allocator,

	// Last seen hit of focus, hover and pressed, refreshed each route.
	focus_hit:   Hit,
	hover_hit:   Hit,
	pressed_hit: Hit,
	pointer:     ops.Point, // the device position of the last pointer event, for Event.travel
	placed:      [dynamic]Placed, // the popups the last frame placed, for placed_side

	requests:    [dynamic]Request, // asked of the platform, until router_requests_clear
	readers:     [dynamic]ops.Area_Id, // areas awaiting a Paste
	focus_next:  ops.Area_Id, // with focus_asked: focus to grant at the next route
	focus_asked: bool,
	cursor:      ops.Cursor,
	pointed:     bool, // a pointer event has set pointer

	yielder:     Hit, // a yielding area whose press went to the one under it; area 0 when none
	yield_press: Raw_Event, // that press, replayed to the yielder if it takes over
	pressed_at:  ops.Area_Id, // the area the last route's first Press went to, 0 for none
	press_seen:  bool, // the last route routed a Press
}

// YIELD_DRAG is how far, in device pixels, a press on yielding text must
// drag before the text takes it from the clickable area under it.
YIELD_DRAG :: 4

@(private = "file")
HOVER_KINDS :: ops.Event_Kinds{.Move, .Enter, .Leave}

// router_init prepares r; allocator backs the queue, the routed events and
// the copies of Text strings.
router_init :: proc(r: ^Router, allocator := context.allocator) {
	r.allocator = allocator
	r.queue = make([dynamic]Raw_Event, allocator)
	r.events = make([dynamic]Event, allocator)
	r.placed = make([dynamic]Placed, allocator)
	r.requests = make([dynamic]Request, allocator)
	r.readers = make([dynamic]ops.Area_Id, allocator)
}

// router_destroy frees everything r owns.
router_destroy :: proc(r: ^Router) {
	release_text(r)
	for e in r.queue {
		free_strings(r, e)
	}
	router_requests_clear(r)
	delete(r.queue)
	delete(r.events)
	delete(r.placed)
	delete(r.requests)
	delete(r.readers)
	r^ = {}
}

// router_push queues a device event for the next route. Text and Paste
// strings are copied, so the caller's need not outlive the call.
router_push :: proc(r: ^Router, e: Raw_Event) {
	e := e
	if owns_strings(e.kind) {
		e.text = clone_string(e.text, r.allocator)
		e.mime = clone_string(e.mime, r.allocator)
	} else {
		e.text, e.mime = "", ""
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
	clear(&r.placed)
	if f != nil {
		append(&r.placed, ..f.placed[:])
	}
	refresh(f, r.focus, &r.focus_hit)
	refresh(f, r.hover, &r.hover_hit)
	refresh(f, r.pressed, &r.pressed_hit)
	r.press_seen, r.pressed_at = false, 0
	if r.focus_asked {
		r.focus_asked = false
		h: Hit
		if r.focus_next == 0 || refresh(f, r.focus_next, &h) {
			set_focus(r, h)
		}
	}
	for e in r.queue {
		switch e.kind {
		case .Press:
			route_press(r, f, e)
		case .Release:
			route_release(r, f, e)
		case .Move:
			update_hover(r, f, e.pos)
			if r.yielder.area != 0 {
				d := e.pos - r.yield_press.pos
				if d.x * d.x + d.y * d.y > YIELD_DRAG * YIELD_DRAG {
					take_yield(r)
				}
			}
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
				free_strings(r, e)
			}
		case .Paste:
			route_paste(r, e)
		case .Enter, .Leave, .Focus, .Blur, .Cancel:
		// Synthesized by the router; a pushed one is ignored.
		}
		if e.kind == .Press || e.kind == .Release || e.kind == .Move {
			r.pointer = e.pos
			r.pointed = true
		}
	}
	clear(&r.queue)
	r.cursor = resolve_cursor(r, f)
}

// route_paste hands e to every area waiting on a clipboard read, each its
// own copy of the strings, and forgets them all; with none waiting it is
// dropped.
@(private = "file")
route_paste :: proc(r: ^Router, e: Raw_Event) {
	for area in r.readers {
		append(&r.events, Event{kind = .Paste, area = area, text = clone_string(e.text, r.allocator), mime = clone_string(e.mime, r.allocator)})
	}
	clear(&r.readers)
	free_strings(r, e)
}

// resolve_cursor is the pointer's look after this route: see router_cursor.
@(private = "file")
resolve_cursor :: proc(r: ^Router, f: ^Frame) -> ops.Cursor {
	if r.pressed != 0 {
		return r.pressed_hit.cursor
	}
	if !r.pointed || f == nil {
		return .Default
	}
	#reverse for h in f.hits {
		if hit_contains(f, h, r.pointer) {
			return h.cursor
		}
	}
	return .Default
}

// events returns the events routed to area this frame, in arrival order.
// The slice is allocated from gtx.allocator (the frame allocator); Text
// strings in it are valid until the next router_route.
//
// Handling an event can change state that widgets drawn earlier in the
// frame already read, such as a theme, so any area given events asks for
// one more frame to redraw them.
events :: proc(gtx: ^Ctx, area: ops.Area_Id) -> []Event {
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
hit_test :: proc(f: ^Frame, p: ops.Point, kind: ops.Event_Kind) -> (Hit, bool) {
	return hit_test_any(f, p, {kind})
}

// hit_test_any is hit_test for the top-most hit wanting any of kinds.
@(private = "file")
hit_test_any :: proc(f: ^Frame, p: ops.Point, kinds: ops.Event_Kinds) -> (Hit, bool) {
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
hit_contains :: proc(f: ^Frame, h: Hit, p: ops.Point) -> bool {
	if f == nil || !shape_contains_device(f.scene, h.shape, h.transform, p) {
		return false
	}
	c := h.clip
	for c != NO_CLIP {
		if c < 0 || int(c) >= len(f.clips) {
			return false
		}
		clip := f.clips[c]
		if !shape_contains_device(f.scene, clip.shape, clip.transform, p) {
			return false
		}
		c = clip.parent
	}
	return true
}

// shape_contains_device maps device point p into the local space of m and
// tests it against s. A singular transform contains nothing.
@(private = "file")
shape_contains_device :: proc(sc: ^ops.Scene, s: ops.Shape, m: ops.Affine, p: ops.Point) -> bool {
	inv, ok := ops.invert(m)
	if !ok {
		return false
	}
	return shape_contains(sc, s, ops.apply(inv, p))
}

// shape_contains tests local point p against s. Round_Rect cuts its
// corners; Ellipse uses the normalized distance; Path_Ref tests only the
// path's bounding rect in v1, and a nil sc contains nothing for it.
@(private = "file")
shape_contains :: proc(sc: ^ops.Scene, s: ops.Shape, p: ops.Point) -> bool {
	switch v in s {
	case ops.Rect:
		return ops.rect_contains(v, p)
	case ops.Round_Rect:
		r := v.rect
		if !ops.rect_contains(r, p) {
			return false
		}
		rad := min(v.radius, r.w / 2, r.h / 2)
		if rad <= 0 {
			return true
		}
		c := ops.Point{clamp(p.x, r.x + rad, r.x + r.w - rad), clamp(p.y, r.y + rad, r.y + r.h - rad)}
		d := p - c
		return d.x * d.x + d.y * d.y <= rad * rad
	case ops.Ellipse:
		r := v.rect
		if r.w <= 0 || r.h <= 0 {
			return false
		}
		rx, ry := r.w / 2, r.h / 2
		dx := (p.x - (r.x + rx)) / rx
		dy := (p.y - (r.y + ry)) / ry
		return dx * dx + dy * dy <= 1
	case ops.Path_Ref:
		if sc == nil || int(v.id) >= len(sc.paths) {
			return false
		}
		return ops.rect_contains(ops.shape_bounds(sc, v), p)
	}
	return false
}

// local maps device point p into h's local space; zero when singular.
@(private = "file")
to_local :: proc(h: Hit, p: ops.Point) -> ops.Point {
	inv, ok := ops.invert(h.transform)
	if !ok {
		return {}
	}
	return ops.apply(inv, p)
}

// refresh replaces last with area's hit in f when f still has it, and
// reports whether it did; the top-most one wins when an id is recorded
// twice.
@(private = "file")
refresh :: proc(f: ^Frame, area: ops.Area_Id, last: ^Hit) -> bool {
	if f == nil || area == 0 {
		return false
	}
	#reverse for h in f.hits {
		if h.area == area {
			last^ = h
			return true
		}
	}
	return false
}

// deliver appends e for h's area with pos, when h's kinds contain e's kind.
@(private = "file")
deliver :: proc(r: ^Router, h: Hit, e: Raw_Event, pos: ops.Point) -> bool {
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
			mime = e.mime,
			clicks = e.clicks,
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
synth :: proc(r: ^Router, h: Hit, kind: ops.Event_Kind, pos: ops.Point) {
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
	if !r.press_seen {
		r.press_seen = true
		r.pressed_at = h.area if ok else 0
	}
	if !ok {
		set_focus(r, {})
		return
	}
	if h.yields {
		if under, found := hit_under(f, h, e.pos); found {
			r.yielder, r.yield_press = h, e
			r.pressed_at = under.area
			h = under
		}
	}
	r.pressed = h.area
	r.pressed_hit = h
	if h.kinds & {.Key, .Text} != {} {
		set_focus(r, h)
	}
	deliver_pointer(r, h, e)
	if r.yielder.area != 0 && e.clicks >= 2 {
		take_yield(r)
	}
}

// hit_under is the top-most area below h (recorded before it) under
// device point p that wants Press and does not yield itself.
@(private = "file")
hit_under :: proc(f: ^Frame, h: Hit, p: ops.Point) -> (Hit, bool) {
	#reverse for u in f.hits[:min(h.order, len(f.hits))] {
		if .Press in u.kinds && !u.yields && hit_contains(f, u, p) {
			return u, true
		}
	}
	return {}, false
}

// take_yield hands the held press to the yielding area over it: Cancel
// to the area that had it, then the press itself, replayed, to the
// yielder, which becomes the grab (and the focus when it wants keys).
@(private = "file")
take_yield :: proc(r: ^Router) {
	y, press := r.yielder, r.yield_press
	r.yielder = {}
	if r.pressed != 0 {
		append(&r.events, Event{kind = .Cancel, area = r.pressed, pos = to_local(r.pressed_hit, press.pos)})
	}
	r.pressed = y.area
	r.pressed_hit = y
	r.pressed_at = y.area
	if y.kinds & {.Key, .Text} != {} {
		set_focus(r, y)
	}
	deliver_pointer(r, y, press)
}

@(private = "file")
route_release :: proc(r: ^Router, f: ^Frame, e: Raw_Event) {
	r.yielder = {}
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
update_hover :: proc(r: ^Router, f: ^Frame, p: ops.Point) {
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

// release_text frees the Text and Paste strings delivered by the previous
// route.
@(private = "file")
release_text :: proc(r: ^Router) {
	for e in r.events {
		if owns_strings(e.kind) {
			delete(e.text, r.allocator)
			delete(e.mime, r.allocator)
		}
	}
}

// owns_strings reports whether events of kind carry strings the router
// copied and must free.
@(private = "file")
owns_strings :: proc(kind: ops.Event_Kind) -> bool {
	return kind == .Text || kind == .Paste
}

// free_strings frees a queued event's copied strings.
@(private = "file")
free_strings :: proc(r: ^Router, e: Raw_Event) {
	if owns_strings(e.kind) {
		delete(e.text, r.allocator)
		delete(e.mime, r.allocator)
	}
}

@(private)
clone_string :: proc(s: string, allocator: mem.Allocator) -> string {
	b := make([]u8, len(s), allocator)
	copy(b, s)
	return string(b)
}

// click_from_events applies this frame's events for area to st and reports
// a click: a left Release inside area while pressed, or an Enter/Space Key
// while focused — a widget that registers .Key and .Focus/.Blur in its
// input_area (button, icon_button, fab) becomes keyboard-activatable for
// free; one that doesn't (checkbox) sees no Key or Focus/Blur events at
// all, since the router only delivers what an area registered. Exported
// for widgets built outside this package (jm:ui/material's controls).
click_from_events :: proc(gtx: ^Ctx, area: ops.Area_Id, st: ^Widget_State, bounds: ops.Rect) -> bool {
	return activate_from_events(gtx, area, st, bounds).clicked
}

// Activation is what activate_from_events saw for a widget this frame: a
// click, and any left press or keyboard activation with where it landed
// (the pointer, or the widget's centre for a key), for a design system
// that animates outward from the touch point.
Activation :: struct {
	clicked: bool,
	press:   bool,
	at:      ops.Point,
}

// activate_from_events is click_from_events with the press it saw.
activate_from_events :: proc(gtx: ^Ctx, area: ops.Area_Id, st: ^Widget_State, bounds: ops.Rect) -> (a: Activation) {
	for e in events(gtx, area) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
		case .Press:
			if e.button == .Left {
				st.pressed = true
				a.press, a.at = true, e.pos
			}
		case .Release:
			if e.button == .Left {
				if st.pressed && ops.rect_contains(bounds, e.pos) {
					a.clicked = true
				}
				st.pressed = false
			}
		case .Cancel:
			st.pressed = false
		case .Key:
			if e.key == .Enter || e.key == .Space {
				a.clicked = true
				a.press, a.at = true, {bounds.x + bounds.w / 2, bounds.y + bounds.h / 2} // no pointer position for a keyboard activation
			}
		}
	}
	return
}

