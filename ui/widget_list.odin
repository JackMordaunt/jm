package ui

import "core:math"
import "jm:ui/ops"

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
// so items need no keys. Scroll events move the offset SCROLL_STEP pixels
// per unit, as scroll_box does (positive scrolls down), clamped to [0,
// content - viewport], and a scroll bar on the right drags and pages it.
// The viewport is the content height clamped to the constraints. Needs
// gtx.layout; without one it draws nothing.
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

	o := gtx.scene
	l.scope = id_mix(p.id, 0)
	first_item := ops.macro_open(o)
	needs_mark := needs_count(gtx)
	item(gtx, 0, user)
	ops.macro_close(o, first_item)
	measured := container_at(l, idx).extent
	row := max(measured.y, 1)
	if !is_finite(cs.max.x) {
		width = measured.x
	}

	content := row * f32(count)
	view := clamp(content, cs.min.y, cs.max.y)
	for e in events(gtx, p.id) {
		if e.kind == .Scroll {
			s.offset += e.scroll.y * SCROLL_STEP
		}
	}
	s.offset = clamp(s.offset, 0, max(content - view, 0))
	size := constrain(cs, {width, view})
	// The bar takes its input before the rows are placed, so a drag moves
	// them this frame; it is painted after them, so it sits on top.
	s.offset = scroll_bar_handle(gtx, id_mix(p.id, 1), .Vertical, size, content, s.offset)

	ops.input_area(o, p.id, ops.Rect{0, 0, size.x, size.y}, {.Scroll})
	ops.clip_push(o, ops.Rect{0, 0, size.x, size.y})
	lo := int(s.offset / row)
	hi := min(count, int(math.ceil((s.offset + size.y) / row)))
	if lo > 0 {
		// Row 0 was laid out to be measured, not shown: what it needed
		// is not needed (see need.odin), or a scrolled list would keep
		// its first row's data live.
		needs_rewind(gtx, needs_mark)
	}
	for i in lo ..< hi {
		ops.transform_push(o, ops.translate(0, f32(i) * row - s.offset))
		if i == 0 {
			ops.call(o, first_item)
		} else {
			l.scope = id_mix(p.id, u64(i))
			item(gtx, i, user)
		}
		ops.transform_pop(o)
	}
	// The bar is painted inside the clip, as scroll_box paints its own:
	// render's damage takes a draw inside a clip as the clip's content
	// and scrolls the region with the bar's tiles repainted after, where
	// a changed draw over the region from outside stops it scrolling
	// (render.test_compose_list_widget_scrolls).
	scroll_bar_paint(gtx, id_mix(p.id, 1), .Vertical, size, content, s.offset)
	ops.clip_pop(o)

	l.scope = saved
	container_pop(gtx, idx)
	return widget_close(gtx, &p, {size = size})
}
