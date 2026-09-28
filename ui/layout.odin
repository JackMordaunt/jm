package ui

import "base:runtime"
import "core:math"
import "core:mem"

// Layout. Constraints flow down and Dims flow up in a single pass, as in Gio,
// but containers wrap the widgets called between their begin and end without
// the author naming each child:
//
//	col := column(gtx, gap = 8); defer end(&col)
//	label(gtx, "Name")
//	if button(gtx, "Save") { save(m) }
//
// Layout is the stack of open containers, reached through gtx.layout. Every
// widget brackets itself with widget_begin / widget_end: begin asks the
// innermost container for the child's constraints and position, end reports
// the child's Dims back so the container advances. A container is itself a
// child of the container around it.
//
// Placement is direct when the container knows the child's position before
// the child runs (a Start or Fill aligned flex, inset, stack): begin pushes a
// translate, end pops it. Otherwise the child is recorded into a macro and
// the container emits translate + call + pop once it knows where the child
// goes. That costs one macro per child, and is what Center and End alignment
// and fill_space need. box, clip_box and centered record their whole body
// into one macro so they can paint, clip or offset it once its size is known.
//
// Layout also holds the state widgets keep across frames (hover, press,
// focus, a text field's scroll, a flex's last measurements), in a map keyed
// by Area_Id, because Ctx lives for one frame. Call layout_reset at the top
// of each frame: it drops the state of widgets that were not laid out in the
// previous frame.
//
// If gtx.layout is nil, widgets place themselves at the origin under
// gtx.constraints, containers do nothing, list draws nothing, and retained
// state lasts one frame.

// INF is an unbounded constraint.
INF :: math.INF_F32

Axis :: enum u8 {
	Horizontal,
	Vertical,
}

// Align places children on a flex's cross axis. Start is single pass;
// Center and End record each child into a macro; Fill gives each child
// tight cross constraints (the flex's cross max), so it stays single pass,
// and degrades to Start when the cross axis is unbounded.
Align :: enum u8 {
	Start,
	Center,
	End,
	Fill,
}

// Widget_State is what a widget keeps between frames, keyed by its id.
Widget_State :: struct {
	seen:          u64,
	hovered:       bool,
	pressed:       bool,
	focused:       bool,
	scroll:        f32, // text field: horizontal scroll to keep the caret visible
	flex_valid:    bool, // flex: the fields below hold last frame's totals
	flex_rigid:    f32,
	flex_weight:   f32,
	flex_count:    int,
	ripple:        Tween, // button family: ink-ripple progress since the last Press; ripple.t < ripple.duration means still animating
	ripple_origin: Point, // where that Press landed, local to the widget
}

@(private)
Container_Kind :: enum u8 {
	Flex,
	Stack,
	Inset,
	Box,
	Clip,
	Center,
	List,
	Scroll,
}

@(private)
Child :: struct {
	size:     Size,
	baseline: f32,
	weight:   f32,
	macro:    Macro_Id,
	deferred: bool, // recorded into macro; placed at the flex's end
	slot:     bool, // fill_space: no content, size resolved at end
}

@(private)
Container :: struct {
	kind:     Container_Kind,
	place:    Placement, // how this container sits in its parent
	cs:       Constraints, // the container's own constraints
	inner:    Constraints, // overlay kinds: what each child gets
	offset:   Point, // overlay kinds: where each child goes
	pad:      Padding,
	style:    Box_Style,
	body:     Macro_Id,
	extent:   Size, // overlay: max child size; flex: max cross in .y
	baseline: f32,
	// Flex only.
	axis:     Axis,
	align:    Align,
	gap:      f32,
	deferred: bool,
	cursor:   f32, // main-axis end of the last child
	count:    int,
	first:    int, // first Child in Layout.children
	rigid:    f32, // main size of unweighted children so far
	weights:  f32, // weights so far, slots included
	next:     f32, // weight for the next child, set by flexible
}

Layout :: struct {
	stack:     [dynamic]Container,
	children:  [dynamic]Child,
	state:     map[Area_Id]Widget_State,
	scope:     Area_Id, // mixed into widget ids; list sets it per item
	frame:     u64,
	allocator: mem.Allocator,
}

// Placement is a widget's bracket: widget_begin fills it, widget_end
// consumes it. id is the widget's Area_Id.
Placement :: struct {
	id:       Area_Id,
	parent:   int, // container index, -1 at the root
	saved:    Constraints,
	given:    Constraints,
	pushed:   bool,
	deferred: bool,
	macro:    Macro_Id,
	weight:   f32,
}

// layout_init prepares l; its storage lives in allocator.
layout_init :: proc(l: ^Layout, allocator := context.allocator) {
	l.allocator = allocator
	l.stack = make([dynamic]Container, allocator)
	l.children = make([dynamic]Child, allocator)
	l.state = make(map[Area_Id]Widget_State, allocator)
}

// layout_destroy frees l's storage.
layout_destroy :: proc(l: ^Layout) {
	delete(l.stack)
	delete(l.children)
	delete(l.state)
	l^ = {}
}

// layout_reset starts a frame: it checks every container was ended and
// drops the state of widgets not seen in the frame before.
layout_reset :: proc(l: ^Layout) {
	assert(len(l.stack) == 0, "ui: a container was not ended")
	clear(&l.stack)
	clear(&l.children)
	l.scope = 0
	l.frame += 1
	stale := make([dynamic]Area_Id, context.temp_allocator)
	for k, v in l.state {
		if v.seen + 1 < l.frame {
			append(&stale, k)
		}
	}
	for k in stale {
		delete_key(&l.state, k)
	}
}

// widget_state returns the retained state for id. The pointer is valid until
// the next widget_state call; without a layout it lasts the frame.
widget_state :: proc(gtx: ^Ctx, area: Area_Id) -> ^Widget_State {
	l := gtx.layout
	if l == nil {
		return new(Widget_State, gtx.allocator)
	}
	_, v, _, _ := map_entry(&l.state, area)
	v.seen = l.frame
	return v
}

// widget_begin opens a widget: it derives the widget's id from key and loc,
// sets gtx.constraints to what the innermost container offers, and places
// the widget (a pushed translate, or a macro the container places later).
widget_begin :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Placement {
	p := Placement {
		id     = id(key, loc),
		parent = -1,
		saved  = gtx.constraints,
		given  = gtx.constraints,
	}
	l := gtx.layout
	if l == nil {
		return p
	}
	if l.scope != 0 {
		p.id = id_mix(l.scope, u64(p.id))
	}
	if len(l.stack) == 0 {
		return p
	}
	p.parent = len(l.stack) - 1
	c := &l.stack[p.parent]
	switch c.kind {
	case .Flex:
		p.weight = c.next
		c.next = 0
		gtx.constraints = flex_child_constraints(l, c, p.weight)
		if c.deferred {
			p.deferred = true
			p.macro = macro_begin(gtx.ops)
		} else {
			at := c.count > 0 ? c.cursor + c.gap : 0
			push_transform(gtx.ops, translate_to(axis_vec(c.axis, at, 0)))
			p.pushed = true
		}
	case .Stack, .Inset, .Box, .Clip, .Center, .List, .Scroll:
		gtx.constraints = c.inner
		if c.offset != {} {
			push_transform(gtx.ops, translate_to(c.offset))
			p.pushed = true
		}
	}
	p.given = gtx.constraints
	return p
}

// widget_end closes a widget opened by widget_begin: it clamps dims into the
// constraints the widget was given, restores gtx.constraints and reports the
// size to the container. Returns the clamped dims.
widget_end :: proc(gtx: ^Ctx, p: ^Placement, dims: Dims) -> Dims {
	d := dims
	d.size = constrain(p.given, d.size)
	if p.pushed {
		pop_transform(gtx.ops)
	}
	if p.deferred {
		macro_end(gtx.ops, p.macro)
	}
	gtx.constraints = p.saved
	l := gtx.layout
	if l == nil || p.parent < 0 {
		return d
	}
	assert(p.parent == len(l.stack) - 1, "ui: widget ended inside a container it began outside")
	c := &l.stack[p.parent]
	switch c.kind {
	case .Flex:
		flex_add(
			l,
			c,
			{
				size = d.size,
				baseline = d.baseline,
				weight = p.weight,
				macro = p.macro,
				deferred = p.deferred,
			},
		)
	case .Stack, .Inset, .Box, .Clip, .Center, .List, .Scroll:
		c.extent = {max(c.extent.x, d.size.x), max(c.extent.y, d.size.y)}
		if c.baseline == 0 && d.baseline > 0 {
			c.baseline = d.baseline + c.offset.y
		}
	}
	return d
}

@(private)
translate_to :: proc(p: Point) -> Affine {
	return translate(p.x, p.y)
}

@(private)
main_of :: proc(a: Axis, v: [2]f32) -> f32 {
	return a == .Horizontal ? v.x : v.y
}

@(private)
cross_of :: proc(a: Axis, v: [2]f32) -> f32 {
	return a == .Horizontal ? v.y : v.x
}

@(private)
axis_vec :: proc(a: Axis, main, cross: f32) -> [2]f32 {
	return a == .Horizontal ? {main, cross} : {cross, main}
}

@(private)
is_finite :: proc(v: f32) -> bool {
	return v < INF
}

@(private)
shrink :: proc(cs: Constraints, p: Padding) -> Constraints {
	d := Size{p.left + p.right, p.top + p.bottom}
	return {
		min = {max(cs.min.x - d.x, 0), max(cs.min.y - d.y, 0)},
		max = {max(cs.max.x - d.x, 0), max(cs.max.y - d.y, 0)},
	}
}

// Containers.

Flex :: struct {
	gtx:   ^Ctx,
	index: int,
}

Stack :: struct {
	gtx:   ^Ctx,
	index: int,
}

Inset :: struct {
	gtx:   ^Ctx,
	index: int,
}

Box :: struct {
	gtx:   ^Ctx,
	index: int,
}

Clip_Box :: struct {
	gtx:   ^Ctx,
	index: int,
}

Centered :: struct {
	gtx:   ^Ctx,
	index: int,
}

Scroll_Box :: struct {
	gtx:   ^Ctx,
	index: int,
}

// end closes any container; `defer end(&c)` right after opening it.
end :: proc {
	end_flex,
	end_stack,
	end_inset,
	end_box,
	end_clip_box,
	end_centered,
	end_scroll_box,
}

// container_open places the container as a child of its parent and pushes
// it. Returns its stack index, or -1 without a layout.
@(private)
container_open :: proc(
	gtx: ^Ctx,
	kind: Container_Kind,
	key: u64,
	loc: runtime.Source_Code_Location,
) -> int {
	p := widget_begin(gtx, key, loc)
	return container_push(gtx, kind, p)
}

@(private)
container_push :: proc(gtx: ^Ctx, kind: Container_Kind, p: Placement) -> int {
	l := gtx.layout
	if l == nil {
		return -1
	}
	append(
		&l.stack,
		Container {
			kind = kind,
			place = p,
			cs = gtx.constraints,
			inner = gtx.constraints,
			first = len(l.children),
		},
	)
	return len(l.stack) - 1
}

// container_pop removes the container at index, which must be innermost,
// and the child records it owned.
@(private)
container_pop :: proc(gtx: ^Ctx, index: int) -> Container {
	l := gtx.layout
	assert(index == len(l.stack) - 1, "ui: containers ended out of order")
	c := pop(&l.stack)
	resize(&l.children, c.first)
	return c
}

// column lays children top to bottom, gap apart. See Align for the cost of
// each alignment; a flexible child or fill_space makes it measure first.
column :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
) -> Flex {
	return flex_open(gtx, .Vertical, gap, align, key, loc)
}

// row lays children left to right, gap apart.
row :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
) -> Flex {
	return flex_open(gtx, .Horizontal, gap, align, key, loc)
}

@(private)
flex_open :: proc(
	gtx: ^Ctx,
	axis: Axis,
	gap: f32,
	align: Align,
	key: u64,
	loc: runtime.Source_Code_Location,
) -> Flex {
	i := container_open(gtx, .Flex, key, loc)
	if i >= 0 {
		c := &gtx.layout.stack[i]
		c.axis = axis
		c.gap = gap
		c.align = align
		c.deferred = align == .Center || align == .End
	}
	return {gtx, i}
}

// flexible marks the next child of the innermost row or column as weighted:
// it is given a tight main-axis share, weight / total weight, of the space
// the unweighted children leave. A child is laid out when it is called, so
// its share is computed from the previous frame's totals when the flex has
// been seen before; the first frame is exact only when every weighted child
// comes after every unweighted one. Outside a flex it does nothing.
flexible :: proc(gtx: ^Ctx, weight: f32) {
	l := gtx.layout
	if l == nil || len(l.stack) == 0 {
		return
	}
	c := &l.stack[len(l.stack) - 1]
	if c.kind == .Flex {
		c.next = weight
	}
}

@(private)
flex_child_constraints :: proc(l: ^Layout, c: ^Container, weight: f32) -> Constraints {
	main_max := main_of(c.axis, c.cs.max)
	cross_max := cross_of(c.axis, c.cs.max)
	// An unweighted child is offered what the unweighted children before it
	// left, as in Gio, so it measures at its natural size even when a
	// weighted child took too much on a first frame.
	used := c.rigid + c.gap * f32(c.count)
	lo: f32 = 0
	hi := max(main_max - used, 0)
	cross_min: f32 = 0
	if c.align == .Fill && is_finite(cross_max) {
		cross_min = cross_max
	}
	if weight > 0 && is_finite(main_max) {
		rigid := c.rigid
		weights := c.weights + weight
		count := c.count + 1
		if memo, ok := l.state[c.place.id]; ok && memo.flex_valid {
			rigid = max(rigid, memo.flex_rigid)
			weights = max(weights, memo.flex_weight)
			count = max(count, memo.flex_count)
		}
		free := max(main_max - rigid - c.gap * f32(count - 1), 0)
		lo = free * weight / weights
		hi = lo
	}
	return {min = axis_vec(c.axis, lo, cross_min), max = axis_vec(c.axis, hi, cross_max)}
}

@(private)
flex_add :: proc(l: ^Layout, c: ^Container, k: Child) {
	m := main_of(c.axis, k.size)
	at := c.count > 0 ? c.cursor + c.gap : 0
	c.cursor = at + m
	c.count += 1
	c.weights += k.weight
	if k.weight == 0 && !k.slot {
		c.rigid += m
	}
	c.extent.y = max(c.extent.y, cross_of(c.axis, k.size))
	append(&l.children, k)
}

// end_flex places any deferred children and reports the flex's size: main
// is the children plus gaps (fill_space takes what is left of the main
// max), cross is the widest child, or the cross max under Fill.
end_flex :: proc(f: ^Flex) {
	gtx := f.gtx
	if f.index < 0 {
		return
	}
	l := gtx.layout
	c := &l.stack[f.index]
	kids := l.children[c.first:]
	gaps := c.gap * f32(max(len(kids) - 1, 0))
	fixed, slot_weight: f32
	for k in kids {
		if k.slot {
			slot_weight += k.weight
		} else {
			fixed += main_of(c.axis, k.size)
		}
	}
	total := fixed + gaps
	if slot_weight > 0 {
		main_max := main_of(c.axis, c.cs.max)
		limit := is_finite(main_max) ? main_max : main_of(c.axis, c.cs.min)
		free := max(limit - total, 0)
		for &k in kids {
			if k.slot {
				k.size = axis_vec(c.axis, free * k.weight / slot_weight, 0)
			}
		}
		total += free
	}
	cross := c.extent.y
	cross_max := cross_of(c.axis, c.cs.max)
	if c.align == .Fill && is_finite(cross_max) {
		cross = cross_max
	}
	size := constrain(c.cs, axis_vec(c.axis, total, cross))
	cross = cross_of(c.axis, size)
	at, baseline: f32
	for k, i in kids {
		if i > 0 {
			at += c.gap
		}
		off: f32
		#partial switch c.align {
		case .Center:
			off = (cross - cross_of(c.axis, k.size)) / 2
		case .End:
			off = cross - cross_of(c.axis, k.size)
		}
		pos := axis_vec(c.axis, at, off)
		if k.deferred {
			push_transform(gtx.ops, translate_to(pos))
			call(gtx.ops, k.macro)
			pop_transform(gtx.ops)
		}
		if baseline == 0 && k.baseline > 0 {
			baseline = k.baseline + pos.y
		}
		at += main_of(c.axis, k.size)
	}
	memo := widget_state(gtx, c.place.id)
	memo.flex_valid = true
	memo.flex_rigid = c.rigid
	memo.flex_weight = c.weights
	memo.flex_count = c.count
	done := container_pop(gtx, f.index)
	widget_end(gtx, &done.place, {size, baseline})
	f.index = -1
}

// spacer takes size along the innermost flex's main axis (a square outside
// a flex).
spacer :: proc(gtx: ^Ctx, size: f32, loc := #caller_location) -> Dims {
	axis, in_flex := parent_axis(gtx)
	p := widget_begin(gtx, 0, loc)
	s := Size{size, size}
	if in_flex {
		s = axis_vec(axis, size, 0)
	}
	return widget_end(gtx, &p, {size = s})
}

// fill_space takes the main-axis space the innermost flex has left, shared
// by weight with any other fill_space. It is resolved when the flex ends, so
// the flex records every later child into a macro. Outside a flex it takes
// the minimum constraints.
fill_space :: proc(gtx: ^Ctx, weight: f32 = 1, loc := #caller_location) {
	l := gtx.layout
	if l != nil && len(l.stack) > 0 {
		c := &l.stack[len(l.stack) - 1]
		if c.kind == .Flex {
			c.deferred = true
			flex_add(l, c, {weight = max(weight, 1e-6), slot = true})
			return
		}
	}
	p := widget_begin(gtx, 0, loc)
	widget_end(gtx, &p, {size = gtx.constraints.min})
}

// parent_axis reports the innermost container's main axis if it is a flex.
@(private)
parent_axis :: proc(gtx: ^Ctx) -> (Axis, bool) {
	l := gtx.layout
	if l == nil || len(l.stack) == 0 {
		return .Vertical, false
	}
	c := &l.stack[len(l.stack) - 1]
	return c.axis, c.kind == .Flex
}

@(private)
overlay_open :: proc(
	gtx: ^Ctx,
	kind: Container_Kind,
	key: u64,
	loc: runtime.Source_Code_Location,
) -> (
	int,
	^Container,
) {
	i := container_open(gtx, kind, key, loc)
	if i < 0 {
		return i, nil
	}
	return i, &gtx.layout.stack[i]
}

// stack overlays its children at the origin with loose constraints; its
// size is the largest child.
stack :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Stack {
	i, c := overlay_open(gtx, .Stack, key, loc)
	if c != nil {
		c.inner = loose(c.cs.max)
	}
	return {gtx, i}
}

// end_stack reports the stack's size.
end_stack :: proc(s: ^Stack) {
	overlay_close(s.gtx, &s.index)
}

// inset pads its children: constraints shrink by the padding, children are
// offset by (left, top), and the size is the content plus the padding.
inset :: proc(gtx: ^Ctx, padding: Padding, key: u64 = 0, loc := #caller_location) -> Inset {
	i, c := overlay_open(gtx, .Inset, key, loc)
	if c != nil {
		c.pad = padding
		c.inner = shrink(c.cs, padding)
		c.offset = {padding.left, padding.top}
	}
	return {gtx, i}
}

// end_inset reports the inset's size.
end_inset :: proc(s: ^Inset) {
	overlay_close(s.gtx, &s.index)
}

// box is a panel: it pads its children like inset and paints a round-rect
// background and outline under them. The body is recorded into a macro
// because the background's size is known only at end.
box :: proc(gtx: ^Ctx, style := Box_Style{}, key: u64 = 0, loc := #caller_location) -> Box {
	i, c := overlay_open(gtx, .Box, key, loc)
	if c != nil {
		c.style = resolve_box(gtx.theme, style)
		c.pad = c.style.padding
		c.inner = shrink(c.cs, c.pad)
		c.offset = {c.pad.left, c.pad.top}
		c.body = macro_begin(gtx.ops)
	}
	return {gtx, i}
}

// end_box paints the background, then runs the body over it.
end_box :: proc(s: ^Box) {
	overlay_close(s.gtx, &s.index)
}

// clip_box clips its children to its final size (a macro, since the size
// is known only at end). Children get the box's own constraints.
clip_box :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Clip_Box {
	i, c := overlay_open(gtx, .Clip, key, loc)
	if c != nil {
		c.body = macro_begin(gtx.ops)
	}
	return {gtx, i}
}

// end_clip_box emits the clip around the body.
end_clip_box :: proc(s: ^Clip_Box) {
	overlay_close(s.gtx, &s.index)
}

// centered centers its content in the space it is offered: it takes the
// max constraint on every bounded axis and the content's size on an
// unbounded one. Children get loose constraints; the body is a macro.
centered :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Centered {
	i, c := overlay_open(gtx, .Center, key, loc)
	if c != nil {
		c.inner = loose(c.cs.max)
		c.body = macro_begin(gtx.ops)
	}
	return {gtx, i}
}

// end_centered offsets the body to the center.
end_centered :: proc(s: ^Centered) {
	overlay_close(s.gtx, &s.index)
}

// SCROLL_STEP is the pixels scroll_box moves per unit of Event.scroll:
// ui/sdl (sdl.odin's MOUSE_WHEEL case) forwards SDL's wheel.y, which is
// typically 1.0 per notch on a discrete wheel and fractional on a
// touchpad, not pixels — though list's doc treats it as pixels.
SCROLL_STEP :: f32(48)

// scroll_box is a vertical viewport over content of any height: children
// get the box's width constraints and an unbounded height, and the box
// takes the height it is offered (the content's, when unbounded). Scroll
// events move the content, clamped to its overflow; the offset is kept in
// the box's own widget state, so a distinct key gives a fresh offset. The
// body is a macro, as in clip_box.
scroll_box :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Scroll_Box {
	i, c := overlay_open(gtx, .Scroll, key, loc)
	if c != nil {
		c.inner = {min = {c.cs.min.x, 0}, max = {c.cs.max.x, INF}}
		c.body = macro_begin(gtx.ops)
	}
	return {gtx, i}
}

// end_scroll_box applies scroll events, then clips and offsets the body.
end_scroll_box :: proc(s: ^Scroll_Box) {
	overlay_close(s.gtx, &s.index)
}

@(private)
overlay_close :: proc(gtx: ^Ctx, index: ^int) {
	if index^ < 0 {
		return
	}
	c := container_pop(gtx, index^)
	index^ = -1
	o := gtx.ops
	content := c.extent
	pads := Size{c.pad.left + c.pad.right, c.pad.top + c.pad.bottom}
	size: Size
	baseline := c.baseline
	#partial switch c.kind {
	case .Stack:
		size = constrain(c.cs, content)
	case .Inset:
		size = constrain(c.cs, content + pads)
	case .Box:
		macro_end(o, c.body)
		size = constrain(c.cs, content + pads)
		rr := Round_Rect{{0, 0, size.x, size.y}, c.style.radius}
		if c.style.paint != nil {
			c.style.paint(gtx, c.place.id, size, c.style.user)
		} else if painted(c.style.fill) {
			fill(o, rr, c.style.fill)
		}
		if c.style.paint == nil && c.style.stroke > 0 && painted(c.style.outline) {
			h := c.style.stroke / 2
			edge := Round_Rect {
				{h, h, size.x - c.style.stroke, size.y - c.style.stroke},
				max(c.style.radius - h, 0),
			}
			stroke(o, edge, c.style.outline, {width = c.style.stroke})
		}
		call(o, c.body)
	case .Clip:
		macro_end(o, c.body)
		size = constrain(c.cs, content)
		push_clip(o, Rect{0, 0, size.x, size.y})
		call(o, c.body)
		pop_clip(o)
	case .Scroll:
		macro_end(o, c.body)
		size = constrain(c.cs, {content.x, is_finite(c.cs.max.y) ? c.cs.max.y : content.y})
		st := widget_state(gtx, c.place.id)
		for e in events(gtx, c.place.id) {
			if e.kind == .Scroll {
				st.scroll += e.scroll.y * SCROLL_STEP
			}
		}
		st.scroll = clamp(st.scroll, 0, max(content.y - size.y, 0))
		view := Rect{0, 0, size.x, size.y}
		input_area(o, c.place.id, view, {.Scroll})
		push_clip(o, view)
		push_transform(o, translate(0, -st.scroll))
		call(o, c.body)
		pop_transform(o)
		pop_clip(o)
		baseline = 0
	case .Center:
		macro_end(o, c.body)
		want := Size {
			is_finite(c.cs.max.x) ? c.cs.max.x : content.x,
			is_finite(c.cs.max.y) ? c.cs.max.y : content.y,
		}
		size = constrain(c.cs, want)
		off := (size - content) / 2
		push_transform(o, translate_to(off))
		call(o, c.body)
		pop_transform(o)
		if baseline > 0 {
			baseline += off.y
		}
	}
	widget_end(gtx, &c.place, {size, baseline})
}
