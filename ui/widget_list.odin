package ui

import "core:math"

// List_State is a list's scroll offset in pixels, owned by the caller.
List_State :: struct {
	offset: f32,
}

// List_Item lays out item i; user is list's user pointer.
List_Item :: proc(gtx: ^Ctx, i: int, user: rawptr)

// list is a clipped, virtualised vertical viewport over count items. It
// measures item 0 to get the row height and assumes every row is that tall;
// then it lays out only the rows that intersect the viewport, each under
// translate(0, i*row - offset). Items get the list's width as a tight
// minimum, so rows span it. Each item's widgets get ids scoped to (list, i),
// so items need no keys. Scroll events add scroll.y pixels to the offset
// (positive scrolls down), clamped to [0, content - viewport]. The viewport
// is the content height clamped to the constraints. Needs gtx.layout; without
// one it draws nothing.
list :: proc(
	gtx: ^Ctx,
	s: ^List_State,
	count: int,
	item: List_Item,
	user: rawptr = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> Dims {
	p := widget_open(gtx, key, loc)
	l := gtx.layout
	if l == nil || count <= 0 {
		return widget_close(gtx, &p, {size = gtx.constraints.min})
	}
	cs := gtx.constraints
	width := is_finite(cs.max.x) ? cs.max.x : 0
	idx := container_push(gtx, {kind = .List, inner = {min = {width, 0}, max = {cs.max.x, INF}}}, p)
	saved := l.scope

	o := gtx.ops
	l.scope = id_mix(p.id, 0)
	first_item := macro_open(o)
	item(gtx, 0, user)
	macro_close(o, first_item)
	measured := container_at(l, idx).extent
	row := max(measured.y, 1)
	if !is_finite(cs.max.x) {
		width = measured.x
	}

	content := row * f32(count)
	view := clamp(content, cs.min.y, cs.max.y)
	for e in events(gtx, p.id) {
		if e.kind == .Scroll {
			s.offset += e.scroll.y
		}
	}
	s.offset = clamp(s.offset, 0, max(content - view, 0))
	size := constrain(cs, {width, view})

	input_area(o, p.id, Rect{0, 0, size.x, size.y}, {.Scroll})
	clip_push(o, Rect{0, 0, size.x, size.y})
	lo := int(s.offset / row)
	hi := min(count, int(math.ceil((s.offset + size.y) / row)))
	for i in lo ..< hi {
		transform_push(o, translate(0, f32(i) * row - s.offset))
		if i == 0 {
			call(o, first_item)
		} else {
			l.scope = id_mix(p.id, u64(i))
			item(gtx, i, user)
		}
		transform_pop(o)
	}
	clip_pop(o)

	l.scope = saved
	container_pop(gtx, idx)
	return widget_close(gtx, &p, {size = size})
}
