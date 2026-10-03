package ui

import "core:fmt"
import "jm:ui/ops"

// Focus_Map is what Debug_Flag.Focus draws of a frame, in device space:
// every focus scope as the box round its areas, the stops Tab visits in
// their order, and the focused area.
Focus_Map :: struct {
	scopes: []Focus_Map_Scope,
	stops:  []ops.Rect, // Tab's stops, in the order it visits them
	focus:  ops.Rect, // the focused area, empty when none is drawn
}

// Focus_Map_Scope is one focus scope's box: round every area recorded in
// it, nested scopes' included, grown by its height so a scope holding
// others draws outside them.
Focus_Map_Scope :: struct {
	node:   Focus_Scope_Node,
	rect:   ops.Rect,
	name:   string, // what names the scope's id: a semantic label, else a tag; "" when nothing does
	height: int, // the levels of scope nested inside it
	active: bool, // the trap that holds focus
}

// FOCUS_SCOPE_FILL is a scope's fill: faint, so nested scopes darken as
// they stack. FOCUS_SCOPE_STROKE outlines each scope and FOCUS_COLOR the
// focused area.
FOCUS_SCOPE_FILL :: ops.Color{60, 120, 255, 34}
FOCUS_SCOPE_STROKE :: ops.Color{60, 120, 255, 150}
FOCUS_COLOR :: ops.Color{255, 196, 0, 255}

// FOCUS_SCOPE_GROW is how far, in device-independent pixels, a scope's
// box grows past its areas for each level nested inside it.
FOCUS_SCOPE_GROW :: f32(4)

// focus_map is f's focus scopes, Tab stops and focus as r routes them,
// built on allocator; scale is the display density. Areas clipped out of
// sight are left out of the boxes.
focus_map :: proc(f: ^Frame, r: ^Router, scale: f32, allocator := context.allocator) -> (m: Focus_Map) {
	scopes := make([]Focus_Map_Scope, len(f.scopes), allocator)
	trap := active_trap(f)
	for s, i in f.scopes {
		scopes[i] = {node = s, active = Scope_Ref(i + 1) == trap}
		scopes[i].name = id_name(f, s.id)
		k := 0
		for at := s.parent; at > 0; at = f.scopes[at - 1].parent {
			k += 1
			scopes[at - 1].height = max(scopes[at - 1].height, k)
		}
	}
	for h in f.hits {
		if h.observes {
			continue
		}
		box := visible_rect(f, h)
		if box.w <= 0 || box.h <= 0 {
			continue
		}
		for at := h.scope; at > 0; at = f.scopes[at - 1].parent {
			scopes[at - 1].rect = union_rect(scopes[at - 1].rect, box)
		}
		if h.area == r.focus && r.focus != 0 {
			m.focus = box
		}
	}
	for &s in scopes {
		if s.rect.w > 0 {
			g := FOCUS_SCOPE_GROW * scale * f32(s.height + 1)
			s.rect = {s.rect.x - g, s.rect.y - g, s.rect.w + 2 * g, s.rect.h + 2 * g}
		}
	}
	n := router_tab_stops(r, f)
	stops := make([]ops.Rect, n, allocator)
	for i in 0 ..< n {
		stops[i] = visible_rect(f, r.stops[i])
	}
	return {scopes, stops, m.focus}
}

// id_name is what names id in f: the label of its semantics, else its
// tag, else "".
@(private = "file")
id_name :: proc(f: ^Frame, id: ops.Area_Id) -> string {
	for n in f.nodes {
		if n.id == id && n.semantics.label != "" {
			return n.semantics.label
		}
	}
	for tg in f.tags {
		if tg.id == id {
			return tg.name
		}
	}
	return ""
}

// visible_rect is h's device bounds inside the clips it sits in.
@(private = "file")
visible_rect :: proc(f: ^Frame, h: Hit) -> ops.Rect {
	box := ops.transform_rect(h.transform, ops.shape_bounds(f.scene, h.shape))
	return ops.rect_intersect(box, clip_chain_bounds(f, h.clip))
}

// union_rect is the smallest rect holding a and b; an empty a is none.
@(private = "file")
union_rect :: proc(a, b: ops.Rect) -> ops.Rect {
	if a.w <= 0 || a.h <= 0 {
		return b
	}
	x0, y0 := min(a.x, b.x), min(a.y, b.y)
	x1, y1 := max(a.x + a.w, b.x + b.w), max(a.y + a.h, b.y + b.h)
	return {x0, y0, x1 - x0, y1 - y0}
}

// paint_focus_map draws m over the frame, above the app: each scope a
// translucent box labelled above its top edge with its kind and name, the active trap's
// outline heavier, each Tab stop numbered in Tab's order, and the focused
// area ringed.
paint_focus_map :: proc(gtx: ^Ctx, m: Focus_Map, scale: f32) {
	o := gtx.scene
	mc := ops.macro_open(o)
	size := 10 * scale
	for s in m.scopes {
		if s.rect.w <= 0 {
			continue
		}
		radius := 4 * scale
		ops.fill(o, ops.Round_Rect{s.rect, radius}, FOCUS_SCOPE_FILL)
		ops.stroke(o, ops.Round_Rect{s.rect, radius}, FOCUS_SCOPE_STROKE, {width = (s.active ? 2 : 1) * scale})
		paint_focus_label(gtx, scope_label(s), {s.rect.x, s.rect.y - size * 1.4}, size, FOCUS_SCOPE_STROKE)
	}
	if m.focus.w > 0 {
		ops.fill(o, m.focus, ops.Color{FOCUS_COLOR.r, FOCUS_COLOR.g, FOCUS_COLOR.b, 60})
		ops.stroke(o, m.focus, FOCUS_COLOR, {width = 2 * scale})
	}
	for r, i in m.stops {
		if r.w > 0 && r.h > 0 {
			paint_focus_label(gtx, fmt.tprint(i + 1), {r.x + r.w, r.y}, size, ops.Color{30, 30, 40, 230})
		}
	}
	ops.macro_close(o, mc)
	ops.defer_call(o, mc)
}

// scope_label names a scope by what it does, and by its tag when an
// area of its id has one, else its id.
@(private = "file")
scope_label :: proc(m: Focus_Map_Scope) -> string {
	s := m.node
	name := m.name != "" ? m.name : fmt.tprintf("%06x", u64(s.id) >> 40) // the id's top 24 bits tell scopes apart
	kind := s.trap ? "trap" : "scope"
	switch s.rove {
	case .Horizontal:
		kind = s.wrap ? "rove across, wrap" : "rove across"
	case .Vertical:
		kind = s.wrap ? "rove down, wrap" : "rove down"
	case .Both:
		kind = s.wrap ? "rove both, wrap" : "rove both"
	case .None:
	}
	if s.trap && s.rove != .None {
		return fmt.tprintf("trap, %s: %s", kind, name)
	}
	return fmt.tprintf("%s: %s", kind, name)
}

// paint_focus_label draws text on a pill of bg whose top-left corner is at.
@(private = "file")
paint_focus_label :: proc(gtx: ^Ctx, text: string, at: ops.Point, size: f32, bg: ops.Color) {
	run := shape(gtx.shaper, gtx.font, size, text, gtx.allocator)
	pad := size * 0.35
	pill := ops.Rect{at.x, at.y, run.advance + 2 * pad, size * 1.4}
	ops.fill(gtx.scene, ops.Round_Rect{pill, pill.h / 2}, bg)
	ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), {at.x + pad, at.y + size * 1.05}, ops.Color{255, 255, 255, 255})
}

// is_group_role reports whether role names a group that is one Tab stop,
// its items reached by arrow keys: a tab list, radio group, toolbar,
// tree, menu or listbox (WAI-ARIA Authoring Practices, Developing a
// Keyboard Interface, "Keyboard Navigation Inside Components").
@(private = "file")
is_group_role :: proc(role: ops.Role) -> bool {
	#partial switch role {
	case .Tab_List, .Radio_Group, .Toolbar, .Tree, .Menu, .List_Box:
		return true
	}
	return false
}

// group_stop_report lists, a line each, the groups in f holding more than
// one of the stops Tab visits as r routes it: a group being its items'
// nearest ancestor of a group role (is_group_role) in f's semantics. A
// kit's group widget that forgets its roving focus scope shows up here;
// it is what the kitchens' tests assert is empty. groups is how many
// groups held a stop at all: what was checked.
group_stop_report :: proc(f: ^Frame, r: ^Router, allocator := context.allocator) -> (lines: []string, groups_seen: int) {
	n := router_tab_stops(r, f)
	groups := make([dynamic]ops.Area_Id, context.temp_allocator)
	names := make([dynamic][dynamic]string, context.temp_allocator)
	for i in 0 ..< n {
		g := group_of(f, r.stops[i].area)
		if g == 0 {
			continue
		}
		at := -1
		for x, k in groups {
			if x == g {
				at = k
			}
		}
		if at < 0 {
			append(&groups, g)
			append(&names, make([dynamic]string, context.temp_allocator))
			at = len(groups) - 1
		}
		append(&names[at], tag_of(f, r.stops[i].area))
	}
	out := make([dynamic]string, allocator)
	for g, k in groups {
		if len(names[k]) < 2 {
			continue
		}
		node := node_of(f, g)
		append(&out, fmt.aprintf("%v %q: %d stops %v", node.semantics.role, node.semantics.label, len(names[k]), names[k][:], allocator = allocator))
	}
	return out[:], len(groups)
}

// node_of is f's semantic node with id, zero when it has none.
@(private = "file")
node_of :: proc(f: ^Frame, id: ops.Area_Id) -> Semantic_Node {
	for n in f.nodes {
		if n.id == id {
			return n
		}
	}
	return {}
}

// group_of is the nearest semantic ancestor of area, area's own node
// excluded, with a group role; 0 when there is none.
@(private = "file")
group_of :: proc(f: ^Frame, area: ops.Area_Id) -> ops.Area_Id {
	at := node_of(f, area).parent
	for depth := 0; at != 0 && depth < 64; depth += 1 {
		n := node_of(f, at)
		if is_group_role(n.semantics.role) {
			return at
		}
		at = n.parent
	}
	return 0
}

// tag_of is the tag naming area in f, or its id when it has none.
@(private = "file")
tag_of :: proc(f: ^Frame, area: ops.Area_Id) -> string {
	for t in f.tags {
		if t.id == area {
			return t.name
		}
	}
	return fmt.tprintf("%x", u64(area))
}
