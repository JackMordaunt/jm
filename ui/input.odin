package ui

import "core:mem"
import "jm:ui/ops"

// Input routing. A platform (ui/shell, the probe) pushes device events with
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
// - Observers (ops.Input_Area.observes) sit outside all of that: every
//   observer under the pointer is sent Enter as the pointer arrives and
//   Leave as it goes, whatever is on top of it, and no other event. Hover,
//   presses and the cursor never land on one.
// - A Press whose target wants Key or Text takes focus (Blur to the old,
//   Focus to the new). A Press on no area clears focus. A Press on an area
//   that wants neither leaves focus where it is, so clicking a toolbar
//   button does not blur the text field it acts on.
// - Tab moves focus to the next area that wants Key or Text and is not
//   no_tab (ops.Input_Area), in frame order, Shift+Tab to the previous, wrapping at the ends; from no focus
//   Tab goes to the first. The focused area hears the Tab first. An area
//   that keeps Tab (a Key_Interest of its own for it) is not left by it.
// - Focus scopes (ops.Focus_Scope) group areas for focus. While the frame
//   has a trapping scope, the last one met is the trap: Tab cycles only
//   the areas inside it, and a press cannot move focus out of it (a press
//   outside leaves focus where it is). When a trap is gone, focus it
//   still held goes back to where it was when the trap came. focus_first
//   focuses the first area inside a named scope.
// - A roving scope (ops.Focus_Scope.rove) is one Tab stop: its outermost
//   roving scope stands for every area inside, entered at the focused
//   one, else the scope's entry, else the member that last held focus,
//   else the first. An unmodified arrow of its axis, Home or End moves
//   focus among the members of the focused area's nearest roving scope,
//   after the focused area has heard the key, unless that area shows the
//   text cursor (a field to edit) or holds a Key_Interest for the key.
// - Key and Text go to the focused area, else they are dropped. A Key
//   also goes to every area with a Key_Interest it matches (ui.key_interest),
//   focused or not, once per area, after the focused area has had it: a
//   dialog's Escape, an app's shortcuts. A focused area's claiming
//   interest that matches keeps the key from all of them. The match is Gio v0.10.2's
//   keyFilterMatch (io/input/key.go) for a key.Filter with no Focus. Of
//   the topmost interests a key matches only the last in the frame, the
//   top-most layer's, gets it.
// - Overlays stack in frame order, the last drawn on top. That order is
//   the dismissal stack: Escape through topmost interests, and presses
//   through Outside. Before a Press is routed, the areas that ask for
//   Outside are walked from the top-most down: each that does not contain
//   the press in any of its shapes is sent Outside, and the walk stops at
//   the first that does. The Press then routes as below.
// - Paste goes to every area that asked with clipboard_read since the
//   last Paste, then the askers are forgotten (see request.odin).
// - A focus_request moves focus before the queued events are routed; a
//   pushed Focus naming an area (an assistive technology's request through
//   the platform) moves it in turn with the other events.
// - Focus is visible (focus_visible) from a Key until the next Press, as
//   the web's :focus-visible: a click focuses without showing a ring, a
//   key shows it on whatever holds focus.
// - A yielding area (ops.Input_Area.yields, selectable text) is never
//   hovered and gets no Move while nothing is pressed: hover and free
//   moves go to what lies under it, so a card keeps its hover over its
//   own text. It still gets Move while it holds the grab.
// - A Press whose top-most target yields goes to the next area under it
//   that wants Press and does not yield, when there is one. If the
//   pointer then drags past YIELD_DRAG device pixels while held, or the
//   press was a double or triple click, the yielding area takes over: the
//   other gets Cancel, the yielder the press (and focus, if it wants keys)
//   and the drag from there.
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
	needs:       [dynamic]Need, // the shapes asked for, until router_needs_clear; see need.odin
	need_text:   mem.Dynamic_Arena, // their kinds and queries (need_text)
	need_text_ready: bool,
	commands:    [dynamic]Command, // asked of the application, until router_commands_clear
	readers:     [dynamic]ops.Area_Id, // areas awaiting a Paste
	focus_next:  ops.Area_Id, // with focus_asked: focus to grant at the next route
	focus_asked: bool,
	focus_into:  ops.Area_Id, // with into_asked: the scope whose first area to focus at the next route
	into_asked:  bool,
	stops:       [dynamic]Hit, // scratch for Tab: the focusable areas in order
	roved:       [dynamic]Scope_Memory, // each roving scope's member that last held focus
	traps:       [dynamic]Scope_Memory, // each trap the last route saw: focus to give back, and the area it held
	cursor:      ops.Cursor,
	pointed:     bool, // a pointer event has set pointer

	yielder:     Hit, // a yielding area whose press went to the one under it; area 0 when none
	yield_press: Raw_Event, // that press, replayed to the yielder if it takes over
	pressed_at:  ops.Area_Id, // the area the last route's first Press went to, 0 for none
	press_seen:  bool, // the last route routed a Press
	keyboard:    bool, // a Key came after the last Press: focus is visible
	observed:    [dynamic]Hit, // the observers the pointer is over, each sent its Enter
}

// Scope_Memory is what the router keeps of a focus scope between routes:
// for a roving scope, area is the member that last held focus; for a
// trap, area is where focus was when it came and held the area inside it
// that had focus at the end of the last route.
@(private)
Scope_Memory :: struct {
	scope: ops.Area_Id,
	area:  ops.Area_Id,
	held:  ops.Area_Id,
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
	r.needs = make([dynamic]Need, allocator)
	r.commands = make([dynamic]Command, allocator)
	r.readers = make([dynamic]ops.Area_Id, allocator)
	r.observed = make([dynamic]Hit, allocator)
	r.stops = make([dynamic]Hit, allocator)
	r.roved = make([dynamic]Scope_Memory, allocator)
	r.traps = make([dynamic]Scope_Memory, allocator)
}

// router_destroy frees everything r owns.
router_destroy :: proc(r: ^Router) {
	release_text(r)
	for e in r.queue {
		free_strings(r, e)
	}
	router_requests_clear(r)
	router_needs_clear(r)
	if r.need_text_ready {
		mem.dynamic_arena_destroy(&r.need_text)
	}
	router_commands_clear(r)
	delete(r.queue)
	delete(r.events)
	delete(r.placed)
	delete(r.requests)
	delete(r.needs)
	delete(r.commands)
	delete(r.readers)
	delete(r.observed)
	delete(r.stops)
	delete(r.roved)
	delete(r.traps)
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
	// Before this route's requests: a trap that appears remembers where
	// focus was before the request that takes focus into it, and a
	// request made as one closes wins over the trap giving focus back.
	if f != nil {
		track_traps(r, f)
	}
	if r.focus_asked {
		r.focus_asked = false
		h: Hit
		if r.focus_next == 0 || refresh(f, r.focus_next, &h) {
			set_focus(r, h)
		}
	}
	if r.into_asked {
		r.into_asked = false
		if f != nil && focus_stops(r, f, r.focus_into) > 0 {
			set_focus(r, r.stops[0])
		}
	}
	for e in r.queue {
		switch e.kind {
		case .Press:
			r.keyboard = false
			route_outside(r, f, e)
			route_press(r, f, e)
		case .Release:
			route_release(r, f, e)
		case .Move:
			update_hover(r, f, e.pos)
			if r.yielder.area != 0 {
				d := e.pos - r.yield_press.pos
				if d.x * d.x + d.y * d.y > YIELD_DRAG * YIELD_DRAG {
					take_yield(r, f)
				}
			}
			if r.pressed != 0 {
				deliver_pointer(r, r.pressed_hit, e)
			} else if h, ok := hit_test_any(f, e.pos, {.Move}, past_yields = true); ok {
				deliver_pointer(r, h, e)
			}
		case .Scroll:
			if h, ok := hit_test(f, e.pos, .Scroll); ok {
				deliver_pointer(r, h, e)
			}
		case .Key, .Text:
			if e.kind == .Key {
				r.keyboard = true
			}
			focused := r.focus != 0 && deliver(r, r.focus_hit, e, {})
			if e.kind == .Key && f != nil {
				route_key_interest(r, f, e, r.focus if focused else 0)
				if e.key == .Tab && e.mods - {.Shift} == {} && !keeps_key(f, r.focus, .Tab, e.mods) {
					route_tab(r, f, .Shift in e.mods)
				} else if e.mods == {} && is_rove_key(e.key) && r.focus != 0 && !keeps_key(f, r.focus, e.key, e.mods) {
					route_rove(r, f, e.key)
				}
			} else if !focused {
				free_strings(r, e)
			}
		case .Paste:
			route_paste(r, e)
		case .Focus:
			// Pushed by a platform for an assistive technology's request:
			// focus the area, shown as keyboard focus, when the frame has it.
			h: Hit
			if e.area != 0 && f != nil && refresh(f, e.area, &h) {
				set_focus(r, h)
				r.keyboard = true
			}
		case .Enter, .Leave, .Blur, .Cancel, .Outside:
		// Synthesized by the router; a pushed one is ignored.
		}
		if e.kind == .Press || e.kind == .Release || e.kind == .Move {
			r.pointer = e.pos
			r.pointed = true
		}
	}
	clear(&r.queue)
	r.cursor = resolve_cursor(r, f)
	if f != nil {
		remember_focus(r, f)
	}
}

// route_key_interest sends Key e to every area whose Key_Interest in f
// matches it, except had, which has it already, and once per area.
@(private = "file")
route_key_interest :: proc(r: ^Router, f: ^Frame, e: Raw_Event, had: ops.Area_Id) {
	if claims_key(f, had, e.key, e.mods) {
		return
	}
	first := len(r.events)
	top := -1 // the last topmost interest that matches: the only one of them to get the key
	for k, i in f.keys {
		if k.topmost && key_interest_matches(k, e.key, e.mods) {
			top = i
		}
	}
	for k, i in f.keys {
		if k.claim ||
		   k.area == had ||
		   !key_interest_matches(k, e.key, e.mods) ||
		   (k.topmost && i != top) {
			continue
		}
		again := false
		for d in r.events[first:] {
			if d.area == k.area {
				again = true
			}
		}
		if !again {
			append(&r.events, Event{kind = .Key, area = k.area, key = e.key, mods = e.mods})
		}
	}
}

// route_outside walks the areas that ask for Outside from the top-most
// down, sending Outside to each that does not contain press e's point in
// any of its shapes, until one does; see Event_Kind.Outside.
@(private = "file")
route_outside :: proc(r: ^Router, f: ^Frame, e: Raw_Event) {
	if f == nil {
		return
	}
	first := len(r.events)
	walk: #reverse for h in f.hits {
		if .Outside not_in h.kinds {
			continue
		}
		for d in r.events[first:] {
			if d.area == h.area {
				continue walk
			}
		}
		for o in f.hits {
			if o.area == h.area && .Outside in o.kinds && hit_contains(f, o, e.pos) {
				return
			}
		}
		append(&r.events, Event{kind = .Outside, area = h.area, pos = to_local(h, e.pos), button = e.button})
	}
}

// key_interest_matches reports whether k asks for key with mods: the key
// (any, for None), every required modifier, and no modifier outside the
// required and optional ones.
key_interest_matches :: proc(k: ops.Key_Interest, key: Key, mods: Mods) -> bool {
	if k.key != .None && k.key != key {
		return false
	}
	return mods >= k.mods && (mods - k.mods - k.optional) == {}
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
		if !h.observes && hit_contains(f, h, r.pointer) {
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
// With past_yields, a yielding area (selectable text) is passed over: it
// takes neither hover nor a free Move from what lies under it.
@(private = "file")
hit_test_any :: proc(f: ^Frame, p: ops.Point, kinds: ops.Event_Kinds, past_yields := false) -> (Hit, bool) {
	if f == nil {
		return {}, false
	}
	#reverse for h in f.hits {
		if past_yields && h.yields {
			continue
		}
		if h.kinds & kinds != {} && !h.observes && hit_contains(f, h, p) {
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
		if active_trap(f) == 0 {
			set_focus(r, {})
		}
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
	if h.kinds & {.Key, .Text} != {} && may_focus(f, h) {
		set_focus(r, h)
	}
	deliver_pointer(r, h, e)
	if r.yielder.area != 0 && e.clicks >= 2 {
		take_yield(r, f)
	}
}

// hit_under is the top-most area below h (recorded before it) under
// device point p that wants Press and does not yield itself.
@(private = "file")
hit_under :: proc(f: ^Frame, h: Hit, p: ops.Point) -> (Hit, bool) {
	#reverse for u in f.hits[:min(h.order, len(f.hits))] {
		if .Press in u.kinds && !u.yields && !u.observes && hit_contains(f, u, p) {
			return u, true
		}
	}
	return {}, false
}

// take_yield hands the held press to the yielding area over it: Cancel
// to the area that had it, then the press itself, replayed, to the
// yielder, which becomes the grab (and the focus when it wants keys).
@(private = "file")
take_yield :: proc(r: ^Router, f: ^Frame) {
	y, press := r.yielder, r.yield_press
	r.yielder = {}
	if r.pressed != 0 {
		append(&r.events, Event{kind = .Cancel, area = r.pressed, pos = to_local(r.pressed_hit, press.pos)})
	}
	r.pressed = y.area
	r.pressed_hit = y
	r.pressed_at = y.area
	if y.kinds & {.Key, .Text} != {} && may_focus(f, y) {
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
	update_observers(r, f, p)
	h: Hit
	ok: bool
	if r.pressed != 0 {
		h = r.pressed_hit
		ok = h.kinds & HOVER_KINDS != {} && hit_contains(f, h, p)
	} else {
		h, ok = hit_test_any(f, p, HOVER_KINDS, past_yields = true)
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

// update_observers sends Leave to each observer the pointer, now at p,
// has left, and Enter to each it has come over.
@(private = "file")
update_observers :: proc(r: ^Router, f: ^Frame, p: ops.Point) {
	i := 0
	for i < len(r.observed) {
		o := r.observed[i]
		now: Hit
		if refresh(f, o.area, &now) && hit_contains(f, now, p) {
			r.observed[i] = now
			i += 1
			continue
		}
		synth(r, o, .Leave, to_local(o, p))
		unordered_remove(&r.observed, i)
	}
	if f == nil {
		return
	}
	outer: for h in f.hits {
		if !h.observes || !hit_contains(f, h, p) {
			continue
		}
		for o in r.observed {
			if o.area == h.area {
				continue outer
			}
		}
		append(&r.observed, h)
		synth(r, h, .Enter, to_local(h, p))
	}
}

// active_trap is the trapping focus scope that holds focus in f: the
// last one met, 0 when f has none.
@(private)
active_trap :: proc(f: ^Frame) -> Scope_Ref {
	if f == nil {
		return 0
	}
	#reverse for s, i in f.scopes {
		if s.trap {
			return Scope_Ref(i + 1)
		}
	}
	return 0
}

// in_scope reports whether scope s is within, or nested in it; with id
// set, whether it is or is nested in any scope named id instead.
@(private = "file")
in_scope :: proc(f: ^Frame, s: Scope_Ref, within: Scope_Ref, id: ops.Area_Id = 0) -> bool {
	for at := s; at > 0 && int(at) <= len(f.scopes); at = f.scopes[at - 1].parent {
		if (id == 0 && at == within) || (id != 0 && f.scopes[at - 1].id == id) {
			return true
		}
	}
	return false
}

// may_focus reports whether a press may focus h: always, unless a trap
// holds focus and h lies outside it.
@(private = "file")
may_focus :: proc(f: ^Frame, h: Hit) -> bool {
	trap := active_trap(f)
	return trap == 0 || in_scope(f, h.scope, trap)
}

// focus_stops fills r.stops with the areas of f Tab visits, in frame
// order, once each: those that want Key or Text, inside the active trap
// when there is one and inside a scope named within when within is set.
// A roving scope's areas give one stop, its entry (roving_entry), where
// its first area stands. It returns how many there are.
@(private = "file")
focus_stops :: proc(r: ^Router, f: ^Frame, within: ops.Area_Id = 0) -> int {
	clear(&r.stops)
	trap := active_trap(f)
	outer: for i in 0 ..< len(f.hits) {
		h := tab_hit(f, i)
		if !tab_reachable(f, h, trap, within) {
			continue
		}
		if g := outer_roving(f, h.scope); g != 0 {
			for s in r.stops {
				if outer_roving(f, s.scope) == g {
					continue outer
				}
			}
			h = roving_entry(r, f, g, trap, within)
		}
		for s in r.stops {
			if s.area == h.area {
				continue outer
			}
		}
		append(&r.stops, h)
	}
	return len(r.stops)
}

// router_tab_stops is the stops Tab visits in f as r routes it, in order:
// r.stops, valid until r next routes or is asked again.
@(private)
router_tab_stops :: proc(r: ^Router, f: ^Frame) -> int {
	return focus_stops(r, f)
}

// tab_hit is f's i-th hit in reading order (Frame.tab_order), or in
// recording order for a frame built without flatten.
@(private = "file")
tab_hit :: proc(f: ^Frame, i: int) -> Hit {
	if len(f.tab_order) == len(f.hits) {
		return f.hits[f.tab_order[i]]
	}
	h := f.hits[i]
	h.tab = i32(i)
	return h
}

// tab_place is h's place in reading order, as tab_hit numbers them.
@(private = "file")
tab_place :: proc(f: ^Frame, h: Hit) -> i32 {
	return h.tab if len(f.tab_order) == len(f.hits) else i32(h.order)
}

// tab_reachable reports whether h is an area focus may move to by key:
// it wants Key or Text and is no no_tab area, and lies inside trap and
// inside a scope named within, each when set.
@(private = "file")
tab_reachable :: proc(f: ^Frame, h: Hit, trap: Scope_Ref, within: ops.Area_Id) -> bool {
	if h.observes || h.no_tab || h.kinds & {.Key, .Text} == {} {
		return false
	}
	return (trap == 0 || in_scope(f, h.scope, trap)) && (within == 0 || in_scope(f, h.scope, 0, within))
}

// outer_roving is the outermost roving scope s lies in, s included, up
// to the nearest trap; 0 for none. Tab treats everything inside it as one
// stop. A trap is a world of its own: a menu raised from a toolbar's
// button is no part of the toolbar's stop.
@(private = "file")
outer_roving :: proc(f: ^Frame, s: Scope_Ref) -> (g: Scope_Ref) {
	for at := s; at > 0 && int(at) <= len(f.scopes); at = f.scopes[at - 1].parent {
		if f.scopes[at - 1].rove != .None {
			g = at
		}
		if f.scopes[at - 1].trap {
			break
		}
	}
	return
}

// nearest_roving is the innermost roving scope s lies in, s included, up
// to the nearest trap; 0 for none. Its arrows move among the areas it is
// nearest to.
@(private = "file")
nearest_roving :: proc(f: ^Frame, s: Scope_Ref) -> Scope_Ref {
	for at := s; at > 0 && int(at) <= len(f.scopes); at = f.scopes[at - 1].parent {
		if f.scopes[at - 1].rove != .None {
			return at
		}
		if f.scopes[at - 1].trap {
			return 0
		}
	}
	return 0
}

// roving_entry is the area Tab enters roving scope g at: the focused
// area when it is inside, else the scope's entry (the selected tab, the
// checked radio), else the area that last held focus there, else its
// first reachable area.
@(private = "file")
roving_entry :: proc(r: ^Router, f: ^Frame, g: Scope_Ref, trap: Scope_Ref, within: ops.Area_Id) -> Hit {
	node := f.scopes[g - 1]
	last := memory_of(r.roved[:], node.id).area
	first, remembered, entry: Hit
	for i in 0 ..< len(f.hits) {
		h := tab_hit(f, i)
		if !tab_reachable(f, h, trap, within) || !in_scope(f, h.scope, g) {
			continue
		}
		switch {
		case h.area == r.focus:
			return h
		case first.area == 0:
			first = h
		}
		if h.area == last && remembered.area == 0 {
			remembered = h
		}
		if h.area == node.entry && entry.area == 0 {
			entry = h
		}
	}
	switch {
	case entry.area != 0:
		return entry
	case remembered.area != 0:
		return remembered
	}
	return first
}

// keeps_key reports whether the focused area holds a Key_Interest for
// key with mods: it uses the key itself, so the key does not move focus
// off it.
@(private = "file")
keeps_key :: proc(f: ^Frame, focus: ops.Area_Id, key: Key, mods: Mods) -> bool {
	if focus == 0 {
		return false
	}
	for k in f.keys {
		if k.area == focus && k.key == key && key_interest_matches(k, key, mods) {
			return true
		}
	}
	return false
}

// claims_key reports whether the focused area holds a claiming
// Key_Interest matching key with mods, keeping it from every other.
@(private = "file")
claims_key :: proc(f: ^Frame, focus: ops.Area_Id, key: Key, mods: Mods) -> bool {
	if focus == 0 {
		return false
	}
	for k in f.keys {
		if k.area == focus && k.claim && key_interest_matches(k, key, mods) {
			return true
		}
	}
	return false
}

// is_rove_key reports whether key can move focus inside a roving scope.
@(private = "file")
is_rove_key :: proc(key: Key) -> bool {
	#partial switch key {
	case .Left, .Right, .Up, .Down, .Home, .End:
		return true
	}
	return false
}

// rove_axis_takes reports whether a roving scope of axis moves on key:
// Home and End on every axis, each arrow on its own.
@(private = "file")
rove_axis_takes :: proc(axis: ops.Rove, key: Key) -> bool {
	#partial switch key {
	case .Home, .End:
		return axis != .None
	case .Left, .Right:
		return axis == .Horizontal || axis == .Both
	case .Up, .Down:
		return axis == .Vertical || axis == .Both
	}
	return false
}

// route_rove moves focus by key among the members of the focused area's
// nearest roving scope, when its axis takes the key and the focused area
// is no text to edit: one showing the text cursor keeps its arrows, where
// a list row that takes Text only for type-ahead does not.
@(private = "file")
route_rove :: proc(r: ^Router, f: ^Frame, key: Key) {
	h: Hit
	if !refresh(f, r.focus, &h) || h.cursor == .Text {
		return
	}
	g := nearest_roving(f, h.scope)
	if g == 0 || !rove_axis_takes(f.scopes[g - 1].rove, key) {
		return
	}
	clear(&r.stops)
	at := -1
	outer: for i in 0 ..< len(f.hits) {
		m := tab_hit(f, i)
		if !tab_reachable(f, m, 0, 0) || nearest_roving(f, m.scope) != g {
			continue
		}
		for s in r.stops {
			if s.area == m.area {
				continue outer
			}
		}
		if m.area == r.focus {
			at = len(r.stops)
		}
		append(&r.stops, m)
	}
	n := len(r.stops)
	if at < 0 || n == 0 {
		return
	}
	next := at
	#partial switch key {
	case .Home:
		next = 0
	case .End:
		next = n - 1
	case .Left, .Up:
		next = at > 0 ? at - 1 : (f.scopes[g - 1].wrap ? n - 1 : 0)
	case .Right, .Down:
		next = at < n - 1 ? at + 1 : (f.scopes[g - 1].wrap ? 0 : n - 1)
	}
	set_focus(r, r.stops[next], key)
}

// memory_of is mem's entry for scope, zero when it has none.
@(private = "file")
memory_of :: proc(mem: []Scope_Memory, scope: ops.Area_Id) -> Scope_Memory {
	for m in mem {
		if m.scope == scope {
			return m
		}
	}
	return {}
}

// scope_named is f's scope named id, 0 when f has none.
@(private = "file")
scope_named :: proc(f: ^Frame, id: ops.Area_Id) -> Scope_Ref {
	for s, i in f.scopes {
		if s.id == id {
			return Scope_Ref(i + 1)
		}
	}
	return 0
}

// traps reports whether f has a trapping scope named id.
@(private = "file")
traps :: proc(f: ^Frame, id: ops.Area_Id) -> bool {
	for s in f.scopes {
		if s.id == id && s.trap {
			return true
		}
	}
	return false
}

// track_traps gives focus back from the traps the last route saw that f
// no longer has, or has but no longer trapping (a menu playing out its
// close), when the trap still held it, and starts remembering where focus
// was for the traps f is the first frame to have.
@(private = "file")
track_traps :: proc(r: ^Router, f: ^Frame) {
	for i := len(r.traps) - 1; i >= 0; i -= 1 {
		m := r.traps[i]
		if traps(f, m.scope) {
			continue
		}
		ordered_remove(&r.traps, i)
		back: Hit
		if m.held != 0 && r.focus == m.held && refresh(f, m.area, &back) {
			set_focus(r, back)
		}
	}
	for s in f.scopes {
		if s.trap && memory_of(r.traps[:], s.id).scope == 0 {
			append(&r.traps, Scope_Memory{scope = s.id, area = r.focus})
		}
	}
}

// remember_focus keeps, once a route is done, which member of each
// roving scope around the focused area holds focus, and which area each
// trap holds, and forgets the scopes f no longer has.
@(private = "file")
remember_focus :: proc(r: ^Router, f: ^Frame) {
	for i := len(r.roved) - 1; i >= 0; i -= 1 {
		if scope_named(f, r.roved[i].scope) == 0 {
			unordered_remove(&r.roved, i)
		}
	}
	h: Hit
	focused := refresh(f, r.focus, &h)
	for &m in r.traps {
		m.held = 0
		if focused && in_scope(f, h.scope, 0, m.scope) {
			m.held = r.focus
		}
	}
	if !focused {
		return
	}
	scopes: for at := h.scope; at > 0 && int(at) <= len(f.scopes); at = f.scopes[at - 1].parent {
		s := f.scopes[at - 1]
		if s.rove == .None {
			continue
		}
		for &m in r.roved {
			if m.scope == s.id {
				m.area = r.focus
				continue scopes
			}
		}
		append(&r.roved, Scope_Memory{scope = s.id, area = r.focus})
	}
}

// route_tab moves focus to the next of f's focus stops after the focused
// area, or the previous when back, wrapping at the ends.
@(private = "file")
route_tab :: proc(r: ^Router, f: ^Frame, back: bool) {
	n := focus_stops(r, f)
	if n == 0 {
		return
	}
	at := -1
	for s, i in r.stops {
		if s.area == r.focus {
			at = i
		}
	}
	h: Hit
	if at < 0 && refresh(f, r.focus, &h) {
		at = tab_step_origin(r.stops[:], tab_place(f, h), back)
	}
	next: int
	switch {
	case at < 0:
		next = back ? n - 1 : 0
	case back:
		next = (at + n - 1) % n
	case:
		next = (at + 1) % n
	}
	set_focus(r, r.stops[next], .Tab, back ? {.Shift} : {})
}

// tab_step_origin places focus that is no stop itself (a no_tab area) among
// stops, by reading order (Hit.tab): the index Tab steps on from, the last stop
// before order, or for Shift+Tab the first after it; -1 when it lies
// past the end Tab is heading for, so Tab wraps.
@(private = "file")
tab_step_origin :: proc(stops: []Hit, place: i32, back: bool) -> int {
	if back {
		for s, i in stops {
			if s.tab > place {
				return i
			}
		}
		return -1
	}
	at := -1
	for s, i in stops {
		if s.tab < place {
			at = i
		}
	}
	return at
}

// set_focus moves focus to h (a zero Hit clears it), sending Blur and
// Focus. by is the key that moved it, with its mods: Tab, or a roving
// scope's arrow, Home or End; None for a press or a request. The Focus
// carries it, so a radio can check the one the arrows reach but not the
// one Tab enters at.
@(private = "file")
set_focus :: proc(r: ^Router, h: Hit, by := Key.None, mods := Mods{}) {
	if h.area == r.focus {
		return
	}
	if r.focus != 0 {
		synth(r, r.focus_hit, .Blur, {})
	}
	r.focus = h.area
	r.focus_hit = h
	if h.area != 0 {
		deliver(r, h, Raw_Event{kind = .Focus, key = by, mods = mods}, {})
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
	clicks:  u8, // the press's count: 2 for a double click, as the platform counts them
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
				a.press, a.at, a.clicks = true, e.pos, e.clicks
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

