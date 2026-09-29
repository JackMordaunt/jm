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

// Widget_State is what every widget keeps between frames, keyed by its
// id: whether it is being pointed at, pressed or focused, and four spring
// slots for whatever it animates. Anything one widget alone needs — a
// container's layout memo, a text field's caret scroll, a design
// system's ripple — is its own type in widget_data, not a field here.
Widget_State :: struct {
	seen:    u64,
	hovered: bool,
	pressed: bool,
	focused: bool,
	springs: [4]Spring, // a component's own animated properties, one slot each, numbered by the component
	root:    Area_Id, // the root scope it was last seen under, for retain
}

// Flex_Memo is a flex container's totals from the frame before, so a
// weighted child on the next frame is offered its share of what the
// rigid children leave.
@(private)
Flex_Memo :: struct {
	rigid, weights: f32,
	count:          int,
}

// Scroll_Offset is a scroll container's offset into its content.
@(private)
Scroll_Offset :: struct {
	x, y: f32,
}

// Scroll_Bar_Memo is a scroll bar's own memory: the seconds since the
// last activity, and the offset it last drew at.
@(private)
Scroll_Bar_Memo :: struct {
	idle, offset: f32,
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
	wrap:     bool, // wrap: children break into lines, line_gap apart
	line_gap: f32,
}

Layout :: struct {
	stack:     [dynamic]Container,
	children:  [dynamic]Child,
	state:     map[Area_Id]^Widget_State, // each on the heap, so a pointer lasts until its widget is dropped
	data:      map[Data_Key]Data_Entry, // widget_data's typed values
	retained:  map[Area_Id]u64, // root scope -> the last frame retain kept it
	scope:     Area_Id, // mixed into widget ids; scope and list set it
	scope_root: Area_Id, // the outermost open scope, which state records as its root
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
	loc:      runtime.Source_Code_Location, // the call that made the widget, for Debug_Box
}

// layout_init prepares l; its storage lives in allocator.
layout_init :: proc(l: ^Layout, allocator := context.allocator) {
	l.allocator = allocator
	l.stack = make([dynamic]Container, allocator)
	l.children = make([dynamic]Child, allocator)
	l.state = make(map[Area_Id]^Widget_State, allocator)
	l.data = make(map[Data_Key]Data_Entry, allocator)
	l.retained = make(map[Area_Id]u64, allocator)
}

// layout_destroy frees l's storage.
layout_destroy :: proc(l: ^Layout) {
	delete(l.stack)
	delete(l.children)
	for _, v in l.state {
		free(v, l.allocator)
	}
	delete(l.state)
	for _, e in l.data {
		mem.free(e.ptr, l.allocator)
	}
	delete(l.data)
	delete(l.retained)
	l^ = {}
}

// layout_reset starts a frame: it checks every container and scope was
// ended and drops the state of widgets not seen in the frame before,
// unless a retained scope holds it (see retain).
layout_reset :: proc(l: ^Layout) {
	assert(len(l.stack) == 0, "ui: a container was not ended")
	assert(l.scope == 0, "ui: a scope was not ended")
	clear(&l.stack)
	clear(&l.children)
	l.scope, l.scope_root = 0, 0
	l.frame += 1
	stale := make([dynamic]Area_Id, context.temp_allocator)
	for k, v in l.state {
		if !kept(l, v.seen, v.root) {
			append(&stale, k)
		}
	}
	for k in stale {
		free(l.state[k], l.allocator)
		delete_key(&l.state, k)
	}
	stale_data := make([dynamic]Data_Key, context.temp_allocator)
	for k, e in l.data {
		if !kept(l, e.seen, e.root) {
			append(&stale_data, k)
		}
	}
	for k in stale_data {
		mem.free(l.data[k].ptr, l.allocator)
		delete_key(&l.data, k)
	}
	for k, f in l.retained {
		if f + 1 < l.frame {
			delete_key(&l.retained, k)
		}
	}
}

// widget_state returns the retained state for id. The pointer stays valid
// until the widget is dropped, a frame after it was last asked for (or
// later, under a retained scope); without a layout it lasts the frame.
widget_state :: proc(gtx: ^Ctx, area: Area_Id) -> ^Widget_State {
	l := gtx.layout
	if l == nil {
		return new(Widget_State, gtx.allocator)
	}
	v, ok := l.state[area]
	if !ok {
		v = new(Widget_State, l.allocator)
		l.state[area] = v
	}
	v.seen, v.root = l.frame, l.scope_root
	return v
}

// widget_begin opens a widget: it derives the widget's id from key and loc,
// sets gtx.constraints to what the innermost container offers, and places
// the widget (a pushed translate, or a macro the container places later).
widget_begin :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Placement {
	p := Placement {
		loc    = loc,
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

// BOUNDS_COLOR outlines widgets under Debug_Flag.Bounds: magenta, a colour
// no theme uses, translucent so nested boxes read as nesting.
BOUNDS_COLOR :: Color{255, 0, 255, 140}

// widget_end closes a widget opened by widget_begin: it clamps dims into the
// constraints the widget was given, restores gtx.constraints and reports the
// size to the container. Returns the clamped dims.
widget_end :: proc(gtx: ^Ctx, p: ^Placement, dims: Dims) -> Dims {
	d := dims
	d.size = constrain(p.given, d.size)
	if .Bounds in gtx.debug {
		// In the widget's own space, before its transform or macro closes.
		stroke(gtx.ops, Rect{0, 0, d.size.x, d.size.y}, BOUNDS_COLOR, {width = 1})
	}
	if .Inspect in gtx.debug {
		depth := gtx.layout != nil ? i32(len(gtx.layout.stack)) : 0
		append(
			&gtx.ops.ops,
			Debug_Box{p.id, d.size, p.given.min, p.given.max, depth, p.loc.file_path, p.loc.line, p.loc.procedure},
		)
	}
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
	end_overlay,
	end_scope,
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

// wrap lays children left to right, gap apart, starting a new line, line_gap
// below, whenever the next child would pass the width it is offered: the
// row of chips, buttons or cards that must reflow, not scroll, when the
// window narrows. Each child is offered the full width and measures at its
// natural size; align places a child across its line (Start, Center or
// End; Fill acts as Start). A line_gap below 0 means gap. Weights do not
// apply: a flexible child is laid out at its natural size.
wrap :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	line_gap: f32 = -1,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
) -> Flex {
	f := flex_open(gtx, .Horizontal, gap, align, key, loc)
	if f.index >= 0 {
		c := &gtx.layout.stack[f.index]
		c.wrap = true
		c.deferred = true
		c.line_gap = line_gap < 0 ? gap : line_gap
	}
	return f
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
	if c.wrap {
		return {max = axis_vec(c.axis, main_max, INF)}
	}
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
		memo := (^Flex_Memo)(data_slot(l, Data_Key{c.place.id, Flex_Memo}, size_of(Flex_Memo), align_of(Flex_Memo)))
		rigid = max(rigid, memo.rigid)
		weights = max(weights, memo.weights)
		count = max(count, memo.count)
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
	if c.wrap {
		end_wrap(f)
		return
	}
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
	memo := widget_data(gtx, c.place.id, Flex_Memo)
	memo.rigid = c.rigid
	memo.weights = c.weights
	memo.count = c.count
	done := container_pop(gtx, f.index)
	widget_end(gtx, &done.place, {size, baseline})
	f.index = -1
}

// end_wrap places a wrap's children in lines and reports its size: the
// widest line by the lines' total height.
@(private)
end_wrap :: proc(f: ^Flex) {
	gtx := f.gtx
	l := gtx.layout
	c := &l.stack[f.index]
	kids := l.children[c.first:]
	limit := is_finite(c.cs.max.x) ? c.cs.max.x : INF
	// Two passes over the lines: measure one, then place it, so a child
	// can be aligned across its line's height.
	width, y, baseline: f32
	start := 0
	for start < len(kids) {
		end := start
		w, h: f32
		for end < len(kids) {
			kw := kids[end].size.x
			next := end > start ? w + c.gap + kw : kw
			if end > start && next > limit {
				break
			}
			w = next
			h = max(h, kids[end].size.y)
			end += 1
		}
		x: f32
		for k in kids[start:end] {
			off: f32
			#partial switch c.align {
			case .Center:
				off = (h - k.size.y) / 2
			case .End:
				off = h - k.size.y
			}
			push_transform(gtx.ops, translate(x, y + off))
			call(gtx.ops, k.macro)
			pop_transform(gtx.ops)
			if baseline == 0 && k.baseline > 0 {
				baseline = k.baseline + y + off
			}
			x += k.size.x + c.gap
		}
		width = max(width, w)
		y += h
		start = end
		if start < len(kids) {
			y += c.line_gap
		}
	}
	size := constrain(c.cs, {width, y})
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

// Overlay is an open overlay; see overlay.
Overlay :: struct {
	gtx:    ^Ctx,
	macro:  Macro_Id,
	stack:  [dynamic]Container, // the enclosing containers, set aside
	saved:  Constraints,
	scope:  Area_Id,
	root:   bool,
	pushed: bool, // at was non-zero: a translate to pop
	active: bool,
	// discard, set before end, drops the layer: recorded, never drawn or
	// hit — for a menu closed by a click in its own frame, whose scrim
	// would otherwise take the next click (input routes against the last
	// frame's hits).
	discard: bool,
}

// overlay records the widgets up to end into a layer drawn after the rest
// of the frame, on top of it (see Defer): at `at` from the enclosing
// container's origin — wrap an anchor widget and the overlay in a stack to
// place it against that widget — or from the window's top-left when root. They lay out from a fresh root
// under cs — they are not children of the container around the call, and
// take no space in it. A menu, tooltip or dialog is one of these.
overlay :: proc(gtx: ^Ctx, at: Point = {}, cs := Constraints{max = {INF, INF}}, root := false) -> Overlay {
	o := Overlay {
		gtx    = gtx,
		saved  = gtx.constraints,
		root   = root,
		active = true,
	}
	o.macro = macro_begin(gtx.ops)
	if at != {} {
		push_transform(gtx.ops, translate_to(at))
		o.pushed = true
	}
	if l := gtx.layout; l != nil {
		o.stack = l.stack
		o.scope = l.scope
		l.stack = make([dynamic]Container, gtx.allocator)
	}
	gtx.constraints = cs
	return o
}

// end_overlay closes the layer and schedules it.
end_overlay :: proc(o: ^Overlay) {
	if !o.active {
		return
	}
	o.active = false
	gtx := o.gtx
	if l := gtx.layout; l != nil {
		assert(len(l.stack) == 0, "ui: a container inside an overlay was not ended")
		l.stack = o.stack
		l.scope = o.scope
	}
	gtx.constraints = o.saved
	if o.pushed {
		pop_transform(gtx.ops)
	}
	macro_end(gtx.ops, o.macro)
	if !o.discard {
		defer_call(gtx.ops, o.macro, o.root)
	}
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
//
// min_width lays the content out at least that wide, however narrow the
// box: content that cannot reflow narrower then scrolls sideways, by a
// horizontal wheel or Shift and the vertical one, instead of being cut off.
scroll_box :: proc(gtx: ^Ctx, key: u64 = 0, min_width: f32 = 0, loc := #caller_location) -> Scroll_Box {
	i, c := overlay_open(gtx, .Scroll, key, loc)
	if c != nil {
		c.inner = {min = {max(c.cs.min.x, min_width), 0}, max = {max(c.cs.max.x, min_width), INF}}
		c.body = macro_begin(gtx.ops)
	}
	return {gtx, i}
}

// end_scroll_box applies scroll events, then clips and offsets the body.
end_scroll_box :: proc(s: ^Scroll_Box) {
	overlay_close(s.gtx, &s.index)
}

// Scroll bar metrics, in dp. The bar is an overlay scroller, modelled on
// macOS's: hidden until the content scrolls or the pointer reaches its
// edge, thin while it shows, wider while hovered or dragged, and gone again
// SCROLL_BAR_LINGER seconds after the last of those. The m3e-kit has no
// scroll bar spec or tokens, nor does jm:ui's theme; the expanded bar is Compose
// Multiplatform's desktop default (defaultScrollbarStyle in foundation's
// Scrollbar.skiko.kt, JetBrains compose-multiplatform-core jb-main, read
// 2026-09-28): 8dp thick, 4dp corners, a 16dp minimum thumb, 50% alpha.
SCROLL_BAR_THICKNESS :: f32(8) // expanded, and the width of the hit area
SCROLL_BAR_THIN :: f32(4) // shown but not hovered
SCROLL_BAR_MIN_THUMB :: f32(16)
SCROLL_BAR_INSET :: f32(2) // from the box's edge, so the thumb does not touch it
SCROLL_BAR_THIN_ALPHA :: f32(0.35)
SCROLL_BAR_HOVER_ALPHA :: f32(0.50)
SCROLL_BAR_LINGER :: f32(1) // seconds a bar stays after the last activity

// SCROLL_BAR_FADE moves the bar in and out, and between thin and
// expanded: a critically damped spring, never overshooting a colour.
@(private)
SCROLL_BAR_FADE :: Spring_Params{1, 1600}

// Scroll_Bar is one bar's layout along its box's edge, in the box's space.
@(private)
Scroll_Bar :: struct {
	view, range: f32, // the box's length on the axis, and how far it scrolls
	track:       Rect,
	thumb_len:   f32,
	travel:      f32, // how far the thumb moves along the track
}

// scroll_bar_layout is the bar for axis over a box of size whose content is
// content long on that axis; ok is false when nothing overflows. both
// shortens the bars so the two do not cross in the corner; ends, when
// larger than the usual inset, is how far the track stops short of each
// end: a rounded box's corner radius, so the bar runs only along its
// straight edge and ends where the corner's curve begins.
@(private)
scroll_bar_layout :: proc(axis: Axis, size: Size, content: f32, both: bool, ends: f32 = 0) -> (b: Scroll_Bar, ok: bool) {
	b.view = main_of(axis, size)
	if content <= b.view {
		return
	}
	start := max(SCROLL_BAR_INSET, ends)
	track_len := b.view - 2 * start
	if both {
		track_len -= SCROLL_BAR_THICKNESS + SCROLL_BAR_INSET
	}
	b.thumb_len = clamp(track_len * b.view / content, SCROLL_BAR_MIN_THUMB, track_len)
	b.range = content - b.view
	b.travel = max(track_len - b.thumb_len, 1)
	edge := cross_of(axis, size) - SCROLL_BAR_THICKNESS - SCROLL_BAR_INSET
	b.track = axis == .Vertical ? Rect{edge, start, SCROLL_BAR_THICKNESS, track_len} : Rect{start, edge, track_len, SCROLL_BAR_THICKNESS}
	return b, true
}

// scroll_bar_handle applies this frame's events on the bar for axis to
// offset and returns the result: dragging the thumb scrolls in proportion,
// a press on the track either side of it moves a page. scroll_box draws its
// own bars; a widget that scrolls content it paints itself (a list drawn
// row by row) calls this before painting at the offset, then
// scroll_bar_paint after, both in its box's space and with an id of its
// own. size is the box, content the content's length on axis; a rounded
// box passes its corner radius as ends, to both.
scroll_bar_handle :: proc(gtx: ^Ctx, id: Area_Id, axis: Axis, size: Size, content, offset: f32, both := false, ends: f32 = 0) -> f32 {
	b, ok := scroll_bar_layout(axis, size, content, both, ends)
	if !ok {
		return offset
	}
	off := offset
	st := widget_state(gtx, id)
	for e in events(gtx, id) {
		along := main_of(axis, e.pos) - main_of(axis, Point{b.track.x, b.track.y})
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Press:
			at := b.travel * off / b.range
			switch {
			case along < at:
				off -= b.view
			case along > at + b.thumb_len:
				off += b.view
			case:
				st.pressed = true
			}
		case .Move:
			if st.pressed {
				off += main_of(axis, e.travel) * b.range / b.travel
			}
		case .Release:
			st.pressed = false
		}
	}
	return clamp(off, 0, b.range)
}

// scroll_bar_paint draws the bar for axis at offset and lays its input
// area over the track, on top of what came before. The bar shows while
// the content is scrolling or the pointer is on it, and fades
// SCROLL_BAR_LINGER seconds after; its input area stays, so reaching the
// edge brings it back. With Debug_Flag.Reveal it always shows. The thumb
// is the theme's foreground.
scroll_bar_paint :: proc(gtx: ^Ctx, id: Area_Id, axis: Axis, size: Size, content, offset: f32, both := false, ends: f32 = 0) {
	b, ok := scroll_bar_layout(axis, size, content, both, ends)
	if !ok {
		return
	}
	// The bar's own widget state: springs 0 and 1 are the expand and the
	// fade; its memo holds the idle time and the offset it last drew at.
	// A bar starts idle, so it stays hidden until something happens.
	st := widget_state(gtx, id)
	m := widget_data(gtx, id, Scroll_Bar_Memo)
	held := st.hovered || st.pressed
	switch {
	case !st.springs[1].started:
		m.idle = SCROLL_BAR_LINGER
	case held || offset != m.offset:
		m.idle = 0
	case:
		m.idle += gtx.dt
	}
	m.offset = offset
	shown := m.idle < SCROLL_BAR_LINGER || revealing(gtx)
	if shown && !held {
		request_frame(gtx, SCROLL_BAR_LINGER - m.idle)
	}
	vis := spring_update(&st.springs[1], gtx, shown ? 1 : 0, SCROLL_BAR_FADE)
	grow := spring_update(&st.springs[0], gtx, held ? 1 : 0, SCROLL_BAR_FADE)
	input_area(gtx.ops, id, b.track, {.Press, .Release, .Move, .Enter, .Leave})
	alpha := (SCROLL_BAR_THIN_ALPHA + (SCROLL_BAR_HOVER_ALPHA - SCROLL_BAR_THIN_ALPHA) * grow) * vis
	if alpha < 0.01 {
		return
	}
	// The thumb hugs the box's outer edge and grows inward.
	thick := SCROLL_BAR_THIN + (SCROLL_BAR_THICKNESS - SCROLL_BAR_THIN) * grow
	at := b.travel * offset / b.range
	thumb := b.track
	if axis == .Vertical {
		thumb = {b.track.x + b.track.w - thick, b.track.y + at, thick, b.thumb_len}
	} else {
		thumb = {b.track.x + at, b.track.y + b.track.h - thick, b.thumb_len, thick}
	}
	fill(gtx.ops, Round_Rect{thumb, thick / 2}, with_alpha(gtx.theme.fg, alpha))
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
		sc := widget_data(gtx, c.place.id, Scroll_Offset)
		for e in events(gtx, c.place.id) {
			if e.kind != .Scroll {
				continue
			}
			if .Shift in e.mods && e.scroll.x == 0 {
				sc.x += e.scroll.y * SCROLL_STEP
			} else {
				sc.y += e.scroll.y * SCROLL_STEP
				sc.x += e.scroll.x * SCROLL_STEP
			}
		}
		sc.y = clamp(sc.y, 0, max(content.y - size.y, 0))
		sc.x = clamp(sc.x, 0, max(content.x - size.x, 0))
		// The bars take their input before the body is placed, so a drag
		// moves the content this frame. Each bar has its own data slot;
		// the slots live on the heap, so sc stays valid while they are made.
		both := content.y > size.y && content.x > size.x
		sc.y = scroll_bar_handle(gtx, id_mix(c.place.id, 1), .Vertical, size, content.y, sc.y, both)
		sc.x = scroll_bar_handle(gtx, id_mix(c.place.id, 2), .Horizontal, size, content.x, sc.x, both)
		view := Rect{0, 0, size.x, size.y}
		input_area(o, c.place.id, view, {.Scroll})
		push_clip(o, view)
		push_transform(o, translate(-sc.x, -sc.y))
		call(o, c.body)
		pop_transform(o)
		scroll_bar_paint(gtx, id_mix(c.place.id, 1), .Vertical, size, content.y, sc.y, both)
		scroll_bar_paint(gtx, id_mix(c.place.id, 2), .Horizontal, size, content.x, sc.x, both)
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
