package ui

import "base:runtime"
import "jm:ui/ops"
import "core:math"
import "core:mem"
import "core:strings"

// Layout. Constraints flow down and Dims flow up in a single pass, as in Gio,
// but containers wrap the widgets called between their open and close without
// the author naming each child:
//
//	col := column_open(gtx, gap = 8); defer close(&col)
//	label(gtx, "Name")
//	if button(gtx, "Save") { save(m) }
//
// Layout is the stack of open containers, reached through gtx.layout. Every
// widget brackets itself with widget_open / widget_close: begin asks the
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
// and degrades to Start when the cross axis is unbounded. Baseline lines
// up the first baselines of a row's children (or of a wrap's line),
// recording each like Center; a child that reports none aligns its bottom
// edge, as CSS synthesises one. The row is as tall as the deepest ascent
// plus the deepest descent. A column has no baselines across it, so
// Baseline there acts as Start.
Align :: enum u8 {
	Start,
	Center,
	End,
	Fill,
	Baseline,
}

// Justify places a flex's children along its main axis when they leave
// space over, as CSS's justify-content: Start packs them at the start,
// Center and End move the pack, Space_Between shares the space over
// between the children (one child stays at the start), and Space_Evenly
// shares it equally before, between and after them. A justified flex
// takes the whole of a bounded main axis and records each child into a
// macro, as Center alignment does; on an unbounded main axis, or beside a
// fill_space, nothing is over and every value packs at the start. In a
// wrap each line is justified on its own.
Justify :: enum u8 {
	Start,
	Center,
	End,
	Space_Between,
	Space_Evenly,
}

// justify_offsets is where the first of n children starts and the space
// added to each gap, for free main-axis space over.
@(private)
justify_offsets :: proc(j: Justify, free: f32, n: int) -> (lead, between: f32) {
	if free <= 0 || n == 0 {
		return
	}
	switch j {
	case .Start:
	case .Center:
		lead = free / 2
	case .End:
		lead = free
	case .Space_Between:
		if n > 1 {
			between = free / f32(n - 1)
		}
	case .Space_Evenly:
		between = free / f32(n + 1)
		lead = between
	}
	return
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
	root:    ops.Area_Id, // the root scope it was last seen under, for retain
}

// Flex_Memo is a flex container's totals from the frame before, so a
// weighted child on the next frame is offered its share of what the
// rigid children leave.
@(private)
Flex_Memo :: struct {
	rigid, weights: f32,
	count:          int,
}

// Scroll_Offset is a scroll box's offset into its content, in pixels
// from the content's top-left. The box keeps its own unless the caller
// passes one to scroll_box_open: then the app owns the position, can
// read and set it, and can persist it (persist_struct).
Scroll_Offset :: struct {
	x, y: f32,
}

// Scroll_Bar_Memo is a scroll bar's own memory: the seconds since the
// last activity, and the offset it last drew at.
@(private)
Scroll_Bar_Memo :: struct {
	idle, offset: f32,
}

// Container_Kind is what a container lays its children out as. It is
// public for the guards a design system builds (ui/guards.odin).
Container_Kind :: enum u8 {
	Flex,
	Stack,
	Inset,
	Box,
	Clip,
	Center,
	List,
	Scroll,
	Grid,
}

@(private)
Child :: struct {
	size:     ops.Size,
	baseline: f32,
	weight:   f32,
	macro:    ops.Macro_Id,
	deferred: bool, // recorded into macro; placed at the flex's end
	slot:     bool, // fill_space: no content, size resolved at end
	span:     bool, // grid_span: a grid row of its own
}

@(private)
Container :: struct {
	kind:     Container_Kind,
	place:    Placement, // how this container sits in its parent
	cs:       Constraints, // the container's own constraints
	inner:    Constraints, // overlay kinds: what each child gets
	offset:   ops.Point, // overlay kinds: where each child goes
	pad:      Padding,
	style:    Box_Style,
	body:     ops.Macro_Id,
	covered:  bool, // an overlay covers it: its end is a Cover_End
	extent:   ops.Size, // overlay: max child size; flex: max cross in .y
	baseline: f32,
	// Flex only.
	axis:     Axis,
	align:    Align,
	justify:  Justify,
	gap:      f32,
	deferred: bool,
	cursor:   f32, // main-axis end of the last child
	count:    int,
	first:    int, // first Child in Layout.children
	rigid:    f32, // main size of unweighted children so far
	weights:  f32, // weights so far, slots included
	next:     f32, // weight for the next child, set by flexible
	wrap:     bool, // wrap: children break into lines, line_gap apart
	natural:  bool, // overflow_row: children are offered an unbounded main axis
	line_gap: f32,
	scroll:   ^Scroll_Offset, // scroll: the caller's offset, else the box's own widget_data
	// Grid only; gap is between columns, line_gap between rows.
	tracks:     []Track,
	column:     int, // the next cell's column
	span_next:  bool, // grid_span was called for the next child
	grid_paint: Grid_Paint, // called with style.user
	fit:      bool, // scroll: take the content's height up to the height offered
	drag_scroll: bool, // scroll: a drag on the box moves its content, and a fast release slings it
}

Layout :: struct {
	stack:     [dynamic]Container,
	children:  [dynamic]Child,
	state:     map[ops.Area_Id]^Widget_State, // each on the heap, so a pointer lasts until its widget is dropped
	data:      map[Data_Key]Data_Entry, // widget_data's typed values
	shapes:    map[Need_Key]Shape_Entry, // what the host delivered for the frame's needs; see need.odin
	retained:  map[ops.Area_Id]u64, // root scope -> the last frame retain kept it
	held:      [dynamic]Held, // guard handles between guard_hold and guard_take
	claims:    map[Claim_Key]u64, // this frame's unkeyed claims per call site and parent
	claimed:   map[ops.Area_Id]runtime.Source_Code_Location, // this frame's ids and who claimed them
	root_parent: ops.Area_Id, // what a widget with no container open claims under: 0, or an overlay's opener
	root_semantic: ops.Area_Id, // the semantic parent of a node with none open: 0, or a recording's enclosing node
	scope:     ops.Area_Id, // mixed into widget ids; scope and list set it
	scope_root: ops.Area_Id, // the outermost open scope, which state records as its root
	frame:     u64,
	allocator: mem.Allocator,
	selection: Label_Selection, // the app's one selection in read-only text; see selectable.odin
	persisted: [dynamic]u8, // what persist_struct last sent, to send only changes
	persisted_once: bool,
	last:      Last_Widget, // the widget closed most recently; see last_widget
	reveals:   [dynamic]Reveal, // this frame's scroll_into_view requests
}

// Last_Widget is a widget just closed: its id and the size it took.
Last_Widget :: struct {
	id:   ops.Area_Id,
	size: ops.Size,
}

// last_widget is the widget closed most recently: called right after a
// widget proc returns, that widget's id and size. A popup anchored to a
// control it did not draw (a menu's button) reads it to listen to the
// control's keys and to place itself against it, both in a ui.stack.
last_widget :: proc(gtx: ^Ctx) -> Last_Widget {
	if gtx.layout == nil {
		return {}
	}
	return gtx.layout.last
}

// Placement is a widget's bracket: widget_open fills it, widget_close
// consumes it. id is the widget's Area_Id.
Placement :: struct {
	id:       ops.Area_Id,
	parent:   int, // container index, -1 at the root
	saved:    Constraints,
	given:    Constraints,
	pushed:   bool,
	deferred: bool,
	macro:    ops.Macro_Id,
	weight:   f32,
	loc:      runtime.Source_Code_Location, // the call that made the widget, for Debug_Box
	kind:     string, // the widget proc that made it, for Debug_Box: button, column
	semantics: ops.Semantics, // what semantics set; emitted at widget_close
	semantic:  bool,
	parts:     bool, // part_semantics declared a part under this widget
}

// layout_init prepares l; its storage lives in allocator.
layout_init :: proc(l: ^Layout, allocator := context.allocator) {
	l.allocator = allocator
	l.stack = make([dynamic]Container, allocator)
	l.children = make([dynamic]Child, allocator)
	l.held = make([dynamic]Held, allocator)
	l.claims = make(map[Claim_Key]u64, allocator)
	l.claimed = make(map[ops.Area_Id]runtime.Source_Code_Location, allocator)
	l.state = make(map[ops.Area_Id]^Widget_State, allocator)
	l.shapes = make(map[Need_Key]Shape_Entry, allocator)
	l.data = make(map[Data_Key]Data_Entry, allocator)
	l.retained = make(map[ops.Area_Id]u64, allocator)
	l.persisted = make([dynamic]u8, allocator)
	l.reveals = make([dynamic]Reveal, allocator)
}

// layout_destroy frees l's storage.
layout_destroy :: proc(l: ^Layout) {
	delete(l.stack)
	delete(l.children)
	delete(l.held)
	delete(l.claims)
	delete(l.claimed)
	for _, v in l.state {
		free(v, l.allocator)
	}
	delete(l.state)
	for _, e in l.data {
		mem.free(e.ptr, l.allocator)
	}
	delete(l.data)
	for _, &e in l.shapes {
		shape_entry_free(l, &e)
	}
	delete(l.shapes)
	delete(l.retained)
	delete(l.persisted)
	delete(l.reveals)
	text_destroy(&l.selection.state)
	l^ = {}
}

// layout_reset starts a frame: it checks every container and scope was
// ended and drops the state of widgets not seen in the frame before,
// unless a retained scope holds it (see retain).
layout_reset :: proc(l: ^Layout) {
	assert(len(l.stack) == 0, "ui: a container was not ended")
	assert(l.scope == 0, "ui: a scope was not ended")
	assert(len(l.held) == 0, "ui: a guard's handle was held and never taken")
	clear(&l.stack)
	clear(&l.children)
	clear(&l.claims)
	clear(&l.claimed)
	clear(&l.reveals)
	l.scope, l.scope_root, l.root_parent, l.root_semantic = 0, 0, 0, 0
	l.frame += 1
	stale := make([dynamic]ops.Area_Id, context.temp_allocator)
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
	shapes_reset(l)
}

// widget_state returns the retained state for id. The pointer stays valid
// until the widget is dropped, a frame after it was last asked for (or
// later, under a retained scope); without a layout it lasts the frame.
widget_state :: proc(gtx: ^Ctx, area: ops.Area_Id) -> ^Widget_State {
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

// self is where widget_open itself was called from. That is inside the
// widget proc, so its procedure names the widget: a button's is button,
// a column's is column_open, trimmed to column. A private helper that
// opens on an opener's behalf passes its own self through, as flex_open
// does, so the name stays the opener's.
// widget_open opens a widget: it claims the widget's id (see claim_id),
// sets gtx.constraints to what the innermost container offers, and places
// the widget (a pushed translate, or a macro the container places later).
widget_open :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location, self := #caller_location) -> Placement {
	p := Placement {
		loc    = loc,
		kind   = strings.trim_suffix(self.procedure, "_open"),
		id     = claim(gtx.layout, key, loc),
		parent = -1,
		saved  = gtx.constraints,
		given  = gtx.constraints,
	}
	l := gtx.layout
	if l == nil {
		return p
	}
	c := innermost(l)
	if c == nil {
		return p
	}
	p.parent = depth(l) - 1
	switch c.kind {
	case .Flex:
		p.weight = c.next
		c.next = 0
		gtx.constraints = flex_child_constraints(l, c, p.weight)
		if c.deferred {
			p.deferred = true
			p.macro = ops.macro_open(gtx.scene)
		} else {
			at := c.count > 0 ? c.cursor + c.gap : 0
			ops.transform_push(gtx.scene, translate_to(axis_vec(c.axis, at, 0)))
			p.pushed = true
		}
	case .Grid:
		gtx.constraints = grid_child_constraints(c)
		p.deferred = true
		p.macro = ops.macro_open(gtx.scene)
	case .Stack, .Inset, .Box, .Clip, .Center, .List, .Scroll:
		gtx.constraints = c.inner
		if c.offset != {} {
			ops.transform_push(gtx.scene, translate_to(c.offset))
			p.pushed = true
		}
	}
	p.given = gtx.constraints
	return p
}

// offer is the constraints the innermost container would give the widget
// made next, without making it: what a component that records its parts
// (record_open) before it opens its own widget lays them out against. At
// the root, or without a layout, it is gtx.constraints.
offer :: proc(gtx: ^Ctx) -> Constraints {
	l := gtx.layout
	c := innermost(l)
	if c == nil {
		return gtx.constraints
	}
	switch c.kind {
	case .Flex:
		return flex_child_constraints(l, c, c.next)
	case .Grid:
		return grid_child_constraints(c)
	case .Stack, .Inset, .Box, .Clip, .Center, .List, .Scroll:
	}
	return c.inner
}

// BOUNDS_COLOR outlines widgets under Debug_Flag.Bounds: magenta, a colour
// no theme uses, translucent so nested boxes read as nesting.
BOUNDS_COLOR :: ops.Color{255, 0, 255, 140}

// widget_close closes a widget opened by widget_open: it clamps dims into the
// constraints the widget was given, restores gtx.constraints and reports the
// size to the container. Returns the clamped dims.
widget_close :: proc(gtx: ^Ctx, p: ^Placement, dims: Dims) -> Dims {
	d := dims
	d.size = constrain(p.given, d.size)
	if .Bounds in gtx.debug {
		// In the widget's own space, before its transform or macro closes.
		ops.stroke(gtx.scene, ops.Rect{0, 0, d.size.x, d.size.y}, BOUNDS_COLOR, {width = 1})
	}
	if .Inspect in gtx.debug {
		depth := i32(depth(gtx.layout))
		append(
			&gtx.scene.ops,
			ops.Debug_Box{p.id, d.size, p.given.min, p.given.max, depth, p.loc.file_path, p.loc.line, p.loc.procedure, p.kind},
		)
	}
	if p.semantic {
		ops.semantic(gtx.scene, p.id, semantic_parent(gtx.layout, p.parent), p.semantics, {0, 0, d.size.x, d.size.y})
	} else if p.parts {
		// Its parts named it as their parent: it is a group of them, so
		// the order of the declarations does not matter.
		ops.semantic(gtx.scene, p.id, semantic_parent(gtx.layout, p.parent), {role = .Group}, {0, 0, d.size.x, d.size.y})
	}
	if p.pushed {
		ops.transform_pop(gtx.scene)
	}
	if p.deferred {
		ops.macro_close(gtx.scene, p.macro)
	}
	gtx.constraints = p.saved
	l := gtx.layout
	if l != nil {
		l.last = {p.id, d.size}
	}
	if l == nil || p.parent < 0 {
		return d
	}
	assert(p.parent == depth(l) - 1, "ui: widget ended inside a container it began outside")
	c := container_at(l, p.parent)
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
	case .Grid:
		grid_add(l, c, {size = d.size, baseline = d.baseline, macro = p.macro, deferred = true})
	case .Stack, .Inset, .Box, .Clip, .Center, .List, .Scroll:
		c.extent = {max(c.extent.x, d.size.x), max(c.extent.y, d.size.y)}
		if c.baseline == 0 && d.baseline > 0 {
			c.baseline = d.baseline + c.offset.y
		}
	}
	return d
}

@(private)
translate_to :: proc(p: ops.Point) -> ops.Affine {
	return ops.translate(p.x, p.y)
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

is_finite :: proc(v: f32) -> bool {
	return v < INF
}

@(private)
shrink :: proc(cs: Constraints, p: Padding) -> Constraints {
	d := ops.Size{p.left + p.right, p.top + p.bottom}
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

// close closes any container, overlay or scope from its handle: `defer
// close(&c)` right after opening it. Each container's guard (column,
// stack, box, …) closes itself instead; see guards.odin.
close :: proc {
	flex_close,
	stack_close,
	inset_close,
	box_close,
	clip_box_close,
	centered_close,
	scroll_box_close,
	grid_close,
	overlay_close,
	scope_close,
}

// PAINT_AFTER_CHILDREN are the kinds whose own paint (a background, a
// clip, a centring offset, a scroll) needs the children's size first, so
// container_push records their children into a body macro that the end
// proc calls after painting.
@(private)
PAINT_AFTER_CHILDREN :: bit_set[Container_Kind]{.Box, .Clip, .Center, .Scroll}

// container_push makes c the innermost container, for the widget placed
// as p. An opener says what c is — its kind and how it lays out, complete
// in one literal — and the layout adds what only it knows: the placement,
// the constraints the parent offered, where its children start and, for a
// PAINT_AFTER_CHILDREN kind, the body macro. Every opener is widget_open then this,
// in that order: the offered constraints exist only after widget_open,
// and so must the macro. Without a layout nothing is pushed and the index
// is -1, which every end proc accepts.
@(private)
container_push :: proc(gtx: ^Ctx, c: Container, p: Placement) -> int {
	l := gtx.layout
	if l == nil {
		return -1
	}
	c := c
	c.place = p
	c.cs = gtx.constraints
	c.first = len(l.children)
	if c.kind in PAINT_AFTER_CHILDREN {
		c.body = ops.macro_open(gtx.scene)
	}
	append(&l.stack, c)
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

// The layout's stack is the containers open right now, innermost last,
// and children every child placed in them, each container's run starting
// at its first. Nothing else in the package indexes them: these are the
// ways in, each named for what the access means.

// depth is how many containers are open; 0 at the root or without a layout.
@(private)
depth :: proc(l: ^Layout) -> int {
	return l == nil ? 0 : len(l.stack)
}

// container_at is the open container that a handle's index (a Flex,
// Stack or Placement.parent) names.
@(private)
container_at :: proc(l: ^Layout, index: int) -> ^Container {
	return &l.stack[index]
}

// innermost is the container a widget made now is placed in, or nil at
// the root or without a layout.
@(private)
innermost :: proc(l: ^Layout) -> ^Container {
	if l == nil || len(l.stack) == 0 {
		return nil
	}
	return &l.stack[len(l.stack) - 1]
}

// container_id is the id of the innermost open container, 0 at the root:
// what a component built as a container (sized_open, say) names its
// parts' semantic nodes under, or takes keyboard focus with, so the node
// a reader sees and the area that holds focus are one.
container_id :: proc(gtx: ^Ctx) -> ops.Area_Id {
	c := innermost(gtx.layout)
	return c.place.id if c != nil else 0
}

// children_of is every child placed in c so far, in order.
@(private)
children_of :: proc(l: ^Layout, c: ^Container) -> []Child {
	return l.children[c.first:]
}

// containers_detach gives l an empty container stack, so what is laid out
// next is at the root whatever was open, and returns the stack it had;
// containers_attach puts that back once the detached run is ended.
@(private)
containers_detach :: proc(l: ^Layout, allocator: mem.Allocator) -> [dynamic]Container {
	saved := l.stack
	l.stack = make([dynamic]Container, allocator)
	return saved
}

@(private)
containers_attach :: proc(l: ^Layout, saved: [dynamic]Container) {
	assert(len(l.stack) == 0, "ui: a container inside an overlay was not ended")
	l.stack = saved
}

// column lays children top to bottom, gap apart, placed along it by
// justify. See Align for the cost of each alignment; a flexible child or
// fill_space makes it measure first.
column_open :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
	justify := Justify.Start,
) -> Flex {
	return flex_open(gtx, .Vertical, gap, align, justify, key, loc)
}

// row lays children left to right, gap apart, placed along it by justify.
row_open :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
	justify := Justify.Start,
) -> Flex {
	return flex_open(gtx, .Horizontal, gap, align, justify, key, loc)
}

// flex_open is column_open and row_open: a flex along axis, deferred when
// its alignment or justification needs the total before any child can be
// placed.
@(private)
flex_open :: proc(gtx: ^Ctx, axis: Axis, gap: f32, align: Align, justify: Justify, key: u64, loc: runtime.Source_Code_Location, self := #caller_location) -> Flex {
	p := widget_open(gtx, key, loc, self)
	c := Container {
		kind     = .Flex,
		axis     = axis,
		gap      = gap,
		align    = align,
		justify  = justify,
		deferred = align == .Center || align == .End || (align == .Baseline && axis == .Horizontal) || justify != .Start,
	}
	return {gtx, container_push(gtx, c, p)}
}

// wrap lays children left to right, gap apart, starting a new line, line_gap
// below, whenever the next child would pass the width it is offered: the
// row of chips, buttons or cards that must reflow, not scroll, when the
// window narrows. Each child is offered the full width and measures at its
// natural size; align places a child across its line (Start, Center,
// End or Baseline; Fill acts as Start). A line_gap below 0 means gap. Weights do not
// apply: a flexible child is laid out at its natural size. justify places
// each line's children along it.
wrap_open :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	line_gap: f32 = -1,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
	justify := Justify.Start,
) -> Flex {
	p := widget_open(gtx, key, loc)
	c := Container {
		kind     = .Flex,
		axis     = .Horizontal,
		gap      = gap,
		align    = align,
		justify  = justify,
		wrap     = true,
		deferred = true, // every child is placed once the lines are known
		line_gap = line_gap < 0 ? gap : line_gap,
	}
	return {gtx, container_push(gtx, c, p)}
}

// flexible marks the next child of the innermost row or column as weighted:
// it is given a tight main-axis share, weight / total weight, of the space
// the unweighted children leave. A child is laid out when it is called, so
// its share is computed from the previous frame's totals when the flex has
// been seen before; the first frame is exact only when every weighted child
// comes after every unweighted one. Outside a flex it does nothing.
flexible :: proc(gtx: ^Ctx, weight: f32) {
	if c := innermost(gtx.layout); c != nil && c.kind == .Flex {
		c.next = weight
	}
}

// overflow_row_open is a row for a run that may not fit, a toolbar's or
// a label group's: each child is measured at its natural width (offered
// an unbounded width, as a wrap does), recorded and placed only at close,
// so the caller can decide which to show (flex_fit, flex_truncate) once
// it knows them all, and then add what stands for the rest. Children it
// keeps past its width overflow it, as in any row.
overflow_row_open :: proc(gtx: ^Ctx, gap: f32 = 0, align: Align = .Start, key: u64 = 0, loc := #caller_location) -> Flex {
	p := widget_open(gtx, key, loc)
	c := Container {
		kind     = .Flex,
		axis     = .Horizontal,
		gap      = gap,
		align    = align,
		deferred = true,
		natural  = true,
	}
	return {gtx, container_push(gtx, c, p)}
}

// flex_fit keeps the longest run of f's children so far, from the first,
// that fits its width: every child when they all fit, else as many as
// leave room after them, gap apart, for reserve, the width of what the
// caller adds next (a "+N" button), dropping the rest by flex_truncate.
// It returns how many it dropped; an unbounded row drops none. f is an
// overflow_row, so each child was measured at its natural width.
flex_fit :: proc(f: ^Flex, reserve: f32 = 0) -> (dropped: int) {
	c := flex_container(f)
	if c == nil {
		return 0
	}
	kids := children_of(f.gtx.layout, c)
	limit := main_of(c.axis, c.cs.max)
	if !is_finite(limit) || c.cursor <= limit {
		return 0
	}
	room := limit - reserve - c.gap
	keep, end := 0, f32(0)
	for k, i in kids {
		next := (i > 0 ? end + c.gap : 0) + main_of(c.axis, k.size)
		if next > room {
			break
		}
		end = next
		keep += 1
	}
	flex_truncate(f, keep)
	return len(kids) - keep
}

// flex_truncate drops f's children from the nth on: they take no space,
// and nothing they recorded (paint, input areas, tags, semantics) runs,
// since each was recorded into a macro that is now never called. A child
// added after this follows the nth. f must be deferred (a Center, End or
// Baseline row, a column so aligned, or a wrap) and innermost: a child
// placed directly was drawn as it closed and cannot be taken back. An
// overflow_row is both.
flex_truncate :: proc(f: ^Flex, n: int) {
	c := flex_container(f)
	if c == nil {
		return
	}
	l := f.gtx.layout
	kids := children_of(l, c)
	if n >= len(kids) {
		return
	}
	kept := make([]Child, max(n, 0), f.gtx.allocator)
	copy(kept, kids)
	c.cursor, c.count, c.weights, c.rigid, c.extent.y = 0, 0, 0, 0, 0
	resize(&l.children, c.first)
	for k in kept {
		flex_add(l, c, k)
	}
}

// flex_count is how many children f holds so far: those it measured,
// less any that flex_fit or flex_truncate dropped. 0 once f is closed.
flex_count :: proc(f: ^Flex) -> int {
	l := f.gtx.layout
	if l == nil || f.index < 0 {
		return 0
	}
	return container_at(l, f.index).count
}

// flex_extent is where f's children so far end along its main axis,
// from its start, gaps included: where the next child goes, less a gap.
// 0 once f is closed.
flex_extent :: proc(f: ^Flex) -> f32 {
	l := f.gtx.layout
	if l == nil || f.index < 0 {
		return 0
	}
	return container_at(l, f.index).cursor
}

// flex_container is f's container when f is the innermost, deferred flex, as
// flex_fit and flex_truncate need; nil without a layout.
@(private = "file")
flex_container :: proc(f: ^Flex) -> ^Container {
	l := f.gtx.layout
	if l == nil || f.index < 0 {
		return nil
	}
	assert(f.index == depth(l) - 1, "ui: flex_fit or flex_truncate on a flex that is not innermost")
	c := container_at(l, f.index)
	assert(c.kind == .Flex && c.deferred, "ui: flex_fit or flex_truncate on a flex that places children directly")
	return c
}

@(private)
flex_child_constraints :: proc(l: ^Layout, c: ^Container, weight: f32) -> Constraints {
	main_max := main_of(c.axis, c.cs.max)
	cross_max := cross_of(c.axis, c.cs.max)
	if c.wrap {
		return {max = axis_vec(c.axis, main_max, INF)}
	}
	if c.natural {
		return {max = axis_vec(c.axis, INF, cross_max)}
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

// flex_close places any deferred children and reports the flex's size: main
// is the children plus gaps (fill_space takes what is left of the main
// max), cross is the widest child, or the cross max under Fill.
flex_close :: proc(f: ^Flex) {
	gtx := f.gtx
	if f.index < 0 {
		return
	}
	l := gtx.layout
	c := container_at(l, f.index)
	if c.wrap {
		wrap_close(f)
		return
	}
	kids := children_of(l, c)
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
	ascent: f32
	if c.align == .Baseline && c.axis == .Horizontal {
		descent: f32
		ascent, descent = baseline_extent(kids)
		cross = max(cross, ascent + descent)
	}
	main := total
	main_max := main_of(c.axis, c.cs.max)
	if c.justify != .Start && is_finite(main_max) {
		main = max(main, main_max)
	}
	size := constrain(c.cs, axis_vec(c.axis, main, cross))
	cross = cross_of(c.axis, size)
	at, between := justify_offsets(c.justify, main_of(c.axis, size) - total, len(kids))
	baseline: f32
	for k, i in kids {
		if i > 0 {
			at += c.gap + between
		}
		off: f32
		#partial switch c.align {
		case .Center:
			off = (cross - cross_of(c.axis, k.size)) / 2
		case .End:
			off = cross - cross_of(c.axis, k.size)
		case .Baseline:
			if c.axis == .Horizontal {
				off = ascent - child_baseline(k)
			}
		}
		pos := axis_vec(c.axis, at, off)
		if k.deferred {
			ops.transform_push(gtx.scene, translate_to(pos))
			ops.call(gtx.scene, k.macro)
			ops.transform_pop(gtx.scene)
		}
		if baseline == 0 && k.baseline > 0 {
			baseline = k.baseline + pos.y
		}
		at += main_of(c.axis, k.size)
	}
	memo := widget_data(gtx, c.place.id, Flex_Memo)
	if c.weights > 0 && (memo.rigid != c.rigid || memo.weights != c.weights || memo.count != c.count) {
		// A weighted child took its share from totals that were not this
		// frame's: a first frame, or one whose unweighted children
		// changed. The next frame lays it out exactly, so ask for one
		// rather than leave the stale layout up until input comes.
		request_frame(gtx)
	}
	memo.rigid = c.rigid
	memo.weights = c.weights
	memo.count = c.count
	done := container_pop(gtx, f.index)
	cover_close(gtx, &done)
	widget_close(gtx, &done.place, {size, baseline})
	f.index = -1
}

// wrap_close places a wrap's children in lines and reports its size: the
// widest line by the lines' total height.
@(private)
wrap_close :: proc(f: ^Flex) {
	gtx := f.gtx
	l := gtx.layout
	c := container_at(l, f.index)
	kids := children_of(l, c)
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
		ascent: f32
		if c.align == .Baseline {
			descent: f32
			ascent, descent = baseline_extent(kids[start:end])
			h = max(h, ascent + descent)
		}
		x, between := justify_offsets(c.justify, limit - w if is_finite(limit) else 0, end - start)
		for k in kids[start:end] {
			off: f32
			#partial switch c.align {
			case .Center:
				off = (h - k.size.y) / 2
			case .End:
				off = h - k.size.y
			case .Baseline:
				off = ascent - child_baseline(k)
			}
			ops.transform_push(gtx.scene, ops.translate(x, y + off))
			ops.call(gtx.scene, k.macro)
			ops.transform_pop(gtx.scene)
			if baseline == 0 && k.baseline > 0 {
				baseline = k.baseline + y + off
			}
			x += k.size.x + c.gap + between
		}
		width = max(width, w)
		if c.justify != .Start && is_finite(limit) {
			width = limit
		}
		y += h
		start = end
		if start < len(kids) {
			y += c.line_gap
		}
	}
	size := constrain(c.cs, {width, y})
	done := container_pop(gtx, f.index)
	cover_close(gtx, &done)
	widget_close(gtx, &done.place, {size, baseline})
	f.index = -1
}

// child_baseline is k's first baseline from its top, or its bottom edge
// when it reports none, as CSS synthesises a baseline for a box without
// text.
@(private = "file")
child_baseline :: proc(k: Child) -> f32 {
	return k.baseline > 0 ? k.baseline : k.size.y
}

// baseline_extent is how far kids reach above and below their shared
// baseline: the deepest ascent and the deepest descent.
@(private = "file")
baseline_extent :: proc(kids: []Child) -> (ascent, descent: f32) {
	for k in kids {
		b := child_baseline(k)
		ascent = max(ascent, b)
		descent = max(descent, k.size.y - b)
	}
	return
}

// spacer takes size along the innermost flex's main axis (a square outside
// a flex).
spacer :: proc(gtx: ^Ctx, size: f32, loc := #caller_location) -> Dims {
	axis, in_flex := parent_axis(gtx)
	p := widget_open(gtx, 0, loc)
	s := ops.Size{size, size}
	if in_flex {
		s = axis_vec(axis, size, 0)
	}
	return widget_close(gtx, &p, {size = s})
}

// fill_space takes the main-axis space the innermost flex has left, shared
// by weight with any other fill_space. It is resolved when the flex ends, so
// the flex records every later child into a macro. Outside a flex it takes
// the minimum constraints.
fill_space :: proc(gtx: ^Ctx, weight: f32 = 1, loc := #caller_location) {
	l := gtx.layout
	if c := innermost(l); c != nil && c.kind == .Flex {
		c.deferred = true
		flex_add(l, c, {weight = max(weight, 1e-6), slot = true})
		return
	}
	p := widget_open(gtx, 0, loc)
	widget_close(gtx, &p, {size = gtx.constraints.min})
}

// parent_axis reports the innermost container's main axis if it is a flex.
parent_axis :: proc(gtx: ^Ctx) -> (Axis, bool) {
	c := innermost(gtx.layout)
	if c == nil {
		return .Vertical, false
	}
	return c.axis, c.kind == .Flex
}

// stack overlays its children at the origin with loose constraints; its
// size is the largest child.
stack_open :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Stack {
	p := widget_open(gtx, key, loc)
	return {gtx, container_push(gtx, {kind = .Stack, inner = loose(gtx.constraints.max)}, p)}
}

// stack_close reports the stack's size.
stack_close :: proc(s: ^Stack) {
	container_close(s.gtx, &s.index)
}

// inset pads its children: constraints shrink by the padding, children are
// offset by (left, top), and the size is the content plus the padding.
inset_open :: proc(gtx: ^Ctx, padding: Padding, key: u64 = 0, loc := #caller_location) -> Inset {
	p := widget_open(gtx, key, loc)
	c := Container {
		kind   = .Inset,
		pad    = padding,
		inner  = shrink(gtx.constraints, padding),
		offset = {padding.left, padding.top},
	}
	return {gtx, container_push(gtx, c, p)}
}

// Size_Limits bound a sized box: min and max per axis. A zero max leaves
// that axis uncapped; min equal to max fixes it.
Size_Limits :: struct {
	min, max: ops.Size,
}

// sized bounds its children and itself by limits within what it is
// offered: children get the narrowed constraints, and the box is its
// content's size clamped into them, so a min holds even around a small
// body. The offered constraints win a conflict (a max below the offered
// min, a min above the offered max), and a min wins over a max, as in
// CSS. It paints nothing; put a box inside it for a surface.
sized_open :: proc(gtx: ^Ctx, limits: Size_Limits, key: u64 = 0, loc := #caller_location) -> Inset {
	p := widget_open(gtx, key, loc)
	cs := limit(gtx.constraints, limits)
	i := container_push(gtx, {kind = .Inset, inner = cs}, p)
	if i >= 0 {
		gtx.layout.stack[i].cs = cs
	}
	return {gtx, i}
}

// limit narrows cs by limits (see sized_open).
@(private = "file")
limit :: proc(cs: Constraints, limits: Size_Limits) -> Constraints {
	out: Constraints
	for a in 0 ..< 2 {
		lo := clamp(limits.min[a], cs.min[a], cs.max[a])
		hi := cs.max[a]
		if limits.max[a] > 0 {
			hi = max(clamp(limits.max[a], cs.min[a], cs.max[a]), lo)
		}
		out.min[a], out.max[a] = lo, hi
	}
	return out
}

// inset_close reports the inset's size.
inset_close :: proc(s: ^Inset) {
	container_close(s.gtx, &s.index)
}

// box is a panel: it pads its children like inset and paints a round-rect
// background and outline under them, each only when its style says so; a
// design system's panel (base.panel) fills the style from its theme. The body is recorded into a macro
// because the background's size is known only at end.
box_open :: proc(gtx: ^Ctx, style := Box_Style{}, key: u64 = 0, loc := #caller_location) -> Box {
	p := widget_open(gtx, key, loc)
	st := style
	c := Container {
		kind   = .Box,
		style  = st,
		pad    = st.padding,
		inner  = shrink(gtx.constraints, st.padding),
		offset = {st.padding.left, st.padding.top},
	}
	return {gtx, container_push(gtx, c, p)}
}

// box_close paints the background, then runs the body over it.
box_close :: proc(s: ^Box) {
	container_close(s.gtx, &s.index)
}

// clip_box clips its children to its final size (a macro, since the size
// is known only at end). Children get the box's own constraints.
clip_box_open :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Clip_Box {
	p := widget_open(gtx, key, loc)
	return {gtx, container_push(gtx, {kind = .Clip, inner = gtx.constraints}, p)}
}

// clip_box_close emits the clip around the body.
clip_box_close :: proc(s: ^Clip_Box) {
	container_close(s.gtx, &s.index)
}

// centered centers its content in the space it is offered: it takes the
// max constraint on every bounded axis and the content's size on an
// unbounded one. Children get loose constraints; the body is a macro.
centered_open :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> Centered {
	p := widget_open(gtx, key, loc)
	return {gtx, container_push(gtx, {kind = .Center, inner = loose(gtx.constraints.max)}, p)}
}

// centered_close offsets the body to the center.
centered_close :: proc(s: ^Centered) {
	container_close(s.gtx, &s.index)
}

// Overlay is an open overlay; see overlay.
Overlay :: struct {
	place:  ops.Placement, // set for a popup: flatten decides where it lands
	gtx:    ^Ctx,
	macro:  ops.Macro_Id,
	stack:  [dynamic]Container, // the enclosing containers, set aside
	saved:  Constraints,
	scope:  ops.Area_Id,
	parent: ops.Area_Id, // the layout's root_parent, set aside
	semantic: ops.Area_Id, // the layout's root_semantic, set aside: a layer's nodes start at the root
	root:   bool,
	cover:  bool, // stacks over the enclosing container's later children too
	top:    bool, // runs after every other layer, window covers included
	pushed: bool, // at was non-zero: a translate to pop
	active: bool,
	// discard, set before end, drops the layer: recorded, never drawn or
	// hit — for a menu closed by a click in its own frame, whose scrim
	// would otherwise take the next click (input routes against the last
	// frame's hits).
	discard: bool,
	node:      ops.Area_Id, // overlay_semantics' node for the layer, 0 for none
	semantics: ops.Semantics,
	node_rect: ops.Rect, // its box when the overlay is no popup; a popup's is its size
}

// overlay records the widgets up to end into a layer drawn after the rest
// of the frame, on top of it (see Defer): at `at` from the enclosing
// container's origin — wrap an anchor widget and the overlay in a stack to
// place it against that widget — or from the window's top-left when root. They lay out from a fresh root
// under cs — they are not children of the container around the call, and
// take no space in it. A menu, tooltip or dialog is one of these.
//
// An overlay stacks over what was recorded before it, so a popup raised
// later — by a sibling after it — lands on top. One with cover stacks over
// the whole of its enclosing container instead: everything recorded in it,
// before or after, and every overlay that raises, sit under it, while an
// overlay raised from inside it still sits above. That is a modal: a
// dialog, a modal sheet or drawer and its scrim. At the root it covers the
// window. A top overlay runs after every other, window covers included:
// the debug tray, which must stay usable over a modal. Nothing else
// decides the order: no overlay knows of another.
overlay_open :: proc(gtx: ^Ctx, at: ops.Point = {}, cs := Constraints{max = {INF, INF}}, root := false, cover := false, top := false) -> Overlay {
	o := Overlay {
		gtx    = gtx,
		saved  = gtx.constraints,
		root   = root,
		cover  = cover,
		top    = top,
		active = true,
	}
	o.macro = ops.macro_open(gtx.scene)
	if at != {} {
		ops.transform_push(gtx.scene, translate_to(at))
		o.pushed = true
	}
	if l := gtx.layout; l != nil {
		o.parent, o.semantic = l.root_parent, l.root_semantic
		if c := innermost(l); c != nil {
			l.root_parent = c.place.id
		}
		l.root_semantic = 0
		o.stack = containers_detach(l, gtx.allocator)
		o.scope = l.scope
	}
	gtx.constraints = cs
	return o
}

// overlay_close closes the layer and schedules it.
overlay_close :: proc(o: ^Overlay) {
	if !o.active {
		return
	}
	o.active = false
	gtx := o.gtx
	covers: ops.Area_Id
	if l := gtx.layout; l != nil {
		containers_attach(l, o.stack)
		l.scope = o.scope
		l.root_parent, l.root_semantic = o.parent, o.semantic
		if c := innermost(l); o.cover && c != nil {
			c.covered = true
			covers = c.place.id
		}
	}
	gtx.constraints = o.saved
	if o.node != 0 {
		// Inside the macro, so it lands on the layer; a popup knows its
		// size by now, a plain overlay has no box of its own.
		ops.semantic(gtx.scene, o.node, 0, o.semantics, {0, 0, o.place.size.x, o.place.size.y} if o.place.set else o.node_rect)
	}
	if o.pushed {
		ops.transform_pop(gtx.scene)
	}
	ops.macro_close(gtx.scene, o.macro)
	if o.discard {
		return
	}
	if o.place.set {
		ops.defer_place(gtx.scene, o.macro, o.place, o.cover, covers)
	} else {
		ops.defer_call(gtx.scene, o.macro, o.root, o.cover, covers, o.top)
	}
}

// popup_open is overlay_open for a popup attached to an anchor: a menu,
// listbox, tooltip or popover. anchor is the widget it opens from, in the
// coordinates current at the call; the popup is laid out from its own
// origin under cs, and popup_close, given the size it came to, has
// flatten place it on side of anchor, gap away, aligned by align, flipped
// to the opposite side and shifted as needed to stay inside the window
// (see ops.Placement). key names the popup for placed_side; a widget
// passes its own id.
popup_open :: proc(
	gtx: ^Ctx,
	anchor: ops.Rect,
	key: ops.Area_Id,
	side := ops.Side.Below,
	align := ops.Side_Align.Start,
	gap: f32 = 0,
	cs := Constraints{max = {INF, INF}},
) -> Overlay {
	return popup_place(gtx, {key = key, anchor = anchor, side = side, align = align, gap = gap}, cs)
}

// popup_place is popup_open for any placement: inside the anchor, nudged
// along the edge, with orders of sides and alignments to fall back on
// (see ops.Placement). place.size is popup_close's to set.
popup_place :: proc(gtx: ^Ctx, place: ops.Placement, cs := Constraints{max = {INF, INF}}) -> Overlay {
	o := overlay_open(gtx, cs = cs)
	if l := gtx.layout; l != nil {
		l.root_parent = place.key
	}
	o.place = place
	o.place.set = true
	return o
}

// popup_close closes a popup opened by popup_open, whose content came to
// size, and schedules it to be placed.
popup_close :: proc(o: ^Overlay, size: ops.Size) {
	o.place.size = size
	overlay_close(o)
}

// Recording is a run of widgets laid out apart from the containers
// around it; see record_open.
Recording :: struct {
	gtx:      ^Ctx,
	macro:    ops.Macro_Id,
	stack:    [dynamic]Container, // the enclosing containers, set aside
	saved:    Constraints,
	scope:    ops.Area_Id,
	parent:   ops.Area_Id, // the layout's root_parent, set aside
	semantic: ops.Area_Id, // the layout's root_semantic, set aside
	index:    int, // the run's own container, -1 without a layout
	active:   bool,
}

// record_open lays the widgets up to record_close out under cs, apart
// from the containers open around it, into a macro that the caller
// places once it knows the run's size: measure first, then decide where.
// The run takes no space in the enclosing container and draws nothing
// until the caller calls its macro (ops.call) under the transform and
// clip it chooses; call it once, as its input areas are hit wherever it
// is drawn. Its ids are claimed under the innermost container and its
// semantic nodes sit under the enclosing node, as if it were laid out in
// place. A component that sizes one part from another records each part
// first: slots placed in an order other than their calls, a title that
// wraps beside actions measured before it.
record_open :: proc(gtx: ^Ctx, cs: Constraints, key: u64 = 0, loc := #caller_location) -> Recording {
	r := Recording {
		gtx    = gtx,
		saved  = gtx.constraints,
		index  = -1,
		active = true,
	}
	r.macro = ops.macro_open(gtx.scene)
	if l := gtx.layout; l != nil {
		r.parent, r.semantic, r.scope = l.root_parent, l.root_semantic, l.scope
		if c := innermost(l); c != nil {
			l.root_parent = c.place.id
		}
		l.root_semantic = semantic_parent(l, depth(l) - 1)
		r.stack = containers_detach(l, gtx.allocator)
	}
	gtx.constraints = cs
	p := widget_open(gtx, key, loc)
	r.index = container_push(gtx, {kind = .Inset, inner = cs}, p)
	return r
}

// record_close ends the run record_open began and returns its macro and
// the size and baseline it came to, within the constraints it was given.
record_close :: proc(r: ^Recording) -> (ops.Macro_Id, Dims) {
	if !r.active {
		return r.macro, {}
	}
	r.active = false
	gtx := r.gtx
	d: Dims
	if r.index >= 0 {
		c := container_pop(gtx, r.index)
		cover_close(gtx, &c)
		d = widget_close(gtx, &c.place, {constrain(c.cs, c.extent), c.baseline})
	}
	if l := gtx.layout; l != nil {
		containers_attach(l, r.stack)
		l.root_parent, l.root_semantic, l.scope = r.parent, r.semantic, r.scope
	}
	gtx.constraints = r.saved
	ops.macro_close(gtx.scene, r.macro)
	return r.macro, d
}

// placed_side is the side the popup keyed key opened on last frame, or
// side when it was not shown: what a popup that draws toward its anchor
// (an arrow, a slide) reads to follow a flip. A popup's first frame
// takes side; flatten places it right regardless.
placed_side :: proc(gtx: ^Ctx, key: ops.Area_Id, side: ops.Side) -> ops.Side {
	s, _ := placed(gtx, key, side)
	return s
}

// placed is placed_side and the shift flatten applied along the edge to
// keep the popup in the window, in the anchor's coordinates: an arrow
// meant to point at the anchor's centre moves by -shift within the popup.
// Zero shift when it was not shown last frame.
placed :: proc(gtx: ^Ctx, key: ops.Area_Id, side: ops.Side) -> (ops.Side, ops.Point) {
	if p, ok := last_placed(gtx, key); ok {
		return p.side, p.shift
	}
	return side, {}
}

// last_placed is where flatten put the popup keyed key last frame: its
// side, alignment and shift; false when it was not shown.
last_placed :: proc(gtx: ^Ctx, key: ops.Area_Id) -> (Placed, bool) {
	if gtx.router == nil {
		return {}, false
	}
	for p in gtx.router.placed {
		if p.key == key {
			return p, true
		}
	}
	return {}, false
}

// SCROLL_THUMB_COLOR is the bar's thumb: a mid grey that reads on light and
// dark alike, faded by the bar's own alpha, so the chrome needs no theme.
SCROLL_THUMB_COLOR :: ops.Color{128, 128, 128, 255}

// SCROLL_STEP is the points scroll_box and list move per unit of
// Event.scroll: a wheel's notch is 1.0. A precise device's delta, a
// trackpad's on macOS, arrives as the fraction of a step its points come
// to (ui/shell, scroll_darwin.odin), so the content moves exactly as far
// as the fingers.
SCROLL_STEP :: f32(48)

// scroll_by_drag moves offset by area's drag and sling and returns it
// clamped to [0, limit]: the content follows the pointer, and a release
// with speed glides on until it slows below a pixel a second or meets an
// edge. A press stops a glide. The area must ask for Press, Move and
// Release; an axis with no room to scroll is locked out of the drag.
@(private)
scroll_by_drag :: proc(gtx: ^Ctx, area: ops.Area_Id, offset, limit: ops.Point) -> ops.Point {
	axis := Drag_Axis.Both
	if limit.x <= 0 {
		axis = .Vertical
	} else if limit.y <= 0 {
		axis = .Horizontal
	}
	d := drag(gtx, area, axis)
	s := widget_data(gtx, area, Sling)
	if d.phase != .Idle {
		sling_stop(s)
	}
	if d.released {
		sling_start(s, -d.velocity, gtx.time)
	}
	travel, moving := sling_step(s, gtx.time)
	off := offset - d.delta + travel
	held := ops.Point{clamp(off.x, 0, max(limit.x, 0)), clamp(off.y, 0, max(limit.y, 0))}
	if held != off {
		sling_stop(s)
		moving = false
	}
	if moving {
		request_frame(gtx)
	}
	return held
}

// scroll_box is a vertical viewport over content of any height: children
// get the box's width constraints and an unbounded height, and the box
// takes the height it is offered (the content's, when unbounded). Scroll
// events move the content, clamped to its overflow; the offset is kept in
// the box's own widget state, so a distinct key gives a fresh offset, or
// in offset when the caller passes one (see Scroll_Offset). The body is a
// macro, as in clip_box.
//
// min_width lays the content out at least that wide, however narrow the
// box: content that cannot reflow narrower then scrolls sideways, by a
// horizontal wheel or Shift and the vertical one, instead of being cut off.
// wide offers the content any width from the box's own up, so content
// that sizes itself (a table whose columns fit their cells) is laid out at
// its own width and scrolls sideways when wider than the box.
//
// A box takes wheel events only while its content overflows it, so one
// with nothing to scroll lets the wheel through to the box around it.
//
// With fit the box takes its content's height, up to the height offered
// and at least the least it is offered, and scrolls only beyond that: a
// popup's CSS max-height with overflow auto.
//
// With drag_scroll a left-button drag on the box moves the content with
// the pointer, and a fast release slings it on (ui.drag, ui.Sling), as a
// touch screen scrolls. It is off by default, since on a desktop a drag
// selects text or moves a handle. The box's own area lies under its
// children, so a drag starts only where no child takes the press.
scroll_box_open :: proc(gtx: ^Ctx, key: u64 = 0, min_width: f32 = 0, offset: ^Scroll_Offset = nil, loc := #caller_location, wide := false, fit := false, drag_scroll := false) -> Scroll_Box {
	p := widget_open(gtx, key, loc)
	cs := gtx.constraints
	inner := Constraints{min = {max(cs.min.x, min_width), 0}, max = {max(cs.max.x, min_width), INF}}
	if wide {
		inner.min.x = max(inner.min.x, is_finite(cs.max.x) ? cs.max.x : 0)
		inner.max.x = INF
	}
	c := Container {
		kind   = .Scroll,
		inner  = inner,
		scroll = offset,
		fit    = fit,
		drag_scroll = drag_scroll,
	}
	return {gtx, container_push(gtx, c, p)}
}

// Reveal is a scroll_into_view request: at is how many ops the scene held
// when it was made, which places it in the recording, and rect is in the
// space current there.
@(private)
Reveal :: struct {
	at:   int,
	rect: ops.Rect,
}

// scroll_into_view asks every scroll box the caller is drawn inside to
// scroll by the least amount that shows rect, in the space current at the
// call (a widget's own, inside its bracket): a focused row in a tree, a
// tab in a scrolling strip. Each box closing after the call over content
// that holds it moves that frame; a box closed before it, or the caller
// inside an overlay, is not moved. rect larger than a box shows its
// top-left. Ask on the frame the thing should come into view, not every
// frame, or the box can no longer be scrolled away from it.
scroll_into_view :: proc(gtx: ^Ctx, rect: ops.Rect) {
	if l := gtx.layout; l != nil && gtx.scene != nil {
		append(&l.reveals, Reveal{len(gtx.scene.ops), rect})
	}
}

// find_reveal is the first of this frame's reveals recorded in macro
// body, in body's space: its ops are walked as flatten runs them,
// following calls, skipping macro bodies inline and overlays.
@(private = "file")
find_reveal :: proc(gtx: ^Ctx, body: ops.Macro_Id) -> (ops.Rect, bool) {
	l := gtx.layout
	if l == nil || len(l.reveals) == 0 {
		return {}, false
	}
	m := gtx.scene.macros[body]
	return find_reveal_in(gtx.scene, l.reveals[:], m.first, m.last, ops.IDENTITY, 0)
}

@(private = "file")
find_reveal_in :: proc(sc: ^ops.Scene, reveals: []Reveal, lo, hi: int, t: ops.Affine, depth: int) -> (ops.Rect, bool) {
	stack := make([dynamic]ops.Affine, context.temp_allocator)
	t := t
	i := lo
	for i < hi {
		for r in reveals {
			if r.at == i {
				return ops.transform_rect(t, r.rect), true
			}
		}
		#partial switch op in sc.ops[i] {
		case ops.Push_Transform:
			append(&stack, t)
			t = ops.mul(op.m, t)
		case ops.Push_Sticky:
			append(&stack, t)
		case ops.Pop_Transform:
			if len(stack) > 0 {
				t = pop(&stack)
			}
		case ops.Macro_Begin:
			last := sc.macros[op.id].last
			i = hi if last < 0 else max(i, min(last, hi))
		case ops.Call:
			m := sc.macros[op.id]
			if m.last >= 0 && depth < MAX_CALL_DEPTH {
				if r, ok := find_reveal_in(sc, reveals, m.first, m.last, t, depth + 1); ok {
					return r, true
				}
			}
		}
		i += 1
	}
	for r in reveals {
		if r.at == hi {
			return ops.transform_rect(t, r.rect), true
		}
	}
	return {}, false
}

// nearest_offset is the scroll offset nearest at that shows [lo, lo+len)
// in a view view long: unchanged when it shows already, else the start or
// end brought to the view's edge, the start when it is longer than the
// view.
@(private = "file")
nearest_offset :: proc(at, view, lo, length: f32) -> f32 {
	switch {
	case lo < at || length > view:
		return lo
	case lo + length > at + view:
		return lo + length - view
	}
	return at
}

// scroll_box_close applies scroll events, then clips and offsets the body.
scroll_box_close :: proc(s: ^Scroll_Box) {
	container_close(s.gtx, &s.index)
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
	track:       ops.Rect,
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
scroll_bar_layout :: proc(axis: Axis, size: ops.Size, content: f32, both: bool, ends: f32 = 0) -> (b: Scroll_Bar, ok: bool) {
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
	b.track = axis == .Vertical ? ops.Rect{edge, start, SCROLL_BAR_THICKNESS, track_len} : ops.Rect{start, edge, track_len, SCROLL_BAR_THICKNESS}
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
scroll_bar_handle :: proc(gtx: ^Ctx, id: ops.Area_Id, axis: Axis, size: ops.Size, content, offset: f32, both := false, ends: f32 = 0) -> f32 {
	b, ok := scroll_bar_layout(axis, size, content, both, ends)
	if !ok {
		return offset
	}
	off := offset
	st := widget_state(gtx, id)
	// The thumb follows the drag from its first pixel; a press on the
	// track pages instead and drags nothing.
	d := drag(gtx, id, .Vertical if axis == .Vertical else .Horizontal, slop = 0)
	on_thumb := st.pressed
	for e in events(gtx, id) {
		along := main_of(axis, e.pos) - main_of(axis, ops.Point{b.track.x, b.track.y})
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
				st.pressed, on_thumb = true, true
			}
		case .Release, .Cancel:
			st.pressed = false
		}
	}
	if on_thumb {
		off += main_of(axis, d.delta) * b.range / b.travel
	}
	return clamp(off, 0, b.range)
}

// scroll_bar_paint draws the bar for axis at offset and lays its input
// area over the track, on top of what came before. The bar shows while
// the content is scrolling or the pointer is on it, and fades
// SCROLL_BAR_LINGER seconds after; its input area stays, so reaching the
// edge brings it back. With Debug_Flag.Reveal it always shows. The thumb
// is the theme's foreground.
scroll_bar_paint :: proc(gtx: ^Ctx, id: ops.Area_Id, axis: Axis, size: ops.Size, content, offset: f32, both := false, ends: f32 = 0) {
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
	ops.input_area(gtx.scene, id, b.track, {.Press, .Release, .Move, .Enter, .Leave})
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
	ops.fill(gtx.scene, ops.Round_Rect{thumb, thick / 2}, ops.with_alpha(SCROLL_THUMB_COLOR, alpha))
}

@(private)
container_close :: proc(gtx: ^Ctx, index: ^int) {
	if index^ < 0 {
		return
	}
	c := container_pop(gtx, index^)
	index^ = -1
	o := gtx.scene
	content := c.extent
	pads := ops.Size{c.pad.left + c.pad.right, c.pad.top + c.pad.bottom}
	size: ops.Size
	baseline := c.baseline
	#partial switch c.kind {
	case .Stack:
		size = constrain(c.cs, content)
	case .Inset:
		size = constrain(c.cs, content + pads)
	case .Box:
		ops.macro_close(o, c.body)
		size = constrain(c.cs, content + pads)
		rr := ops.Round_Rect{{0, 0, size.x, size.y}, c.style.radius}
		if c.style.paint != nil {
			c.style.paint(gtx, c.place.id, size, c.style.user)
		} else if painted(c.style.fill) {
			ops.fill(o, rr, c.style.fill)
		}
		if c.style.paint == nil && c.style.stroke > 0 && painted(c.style.outline) {
			h := c.style.stroke / 2
			edge := ops.Round_Rect {
				{h, h, size.x - c.style.stroke, size.y - c.style.stroke},
				max(c.style.radius - h, 0),
			}
			ops.stroke(o, edge, c.style.outline, {width = c.style.stroke})
		}
		ops.call(o, c.body)
	case .Clip:
		ops.macro_close(o, c.body)
		size = constrain(c.cs, content)
		ops.clip_push(o, ops.Rect{0, 0, size.x, size.y})
		ops.call(o, c.body)
		ops.clip_pop(o)
	case .Scroll:
		ops.macro_close(o, c.body)
		tall := content.y
		if is_finite(c.cs.max.y) && !c.fit {
			tall = c.cs.max.y
		}
		size = constrain(c.cs, {content.x, tall})
		sc := c.scroll != nil ? c.scroll : widget_data(gtx, c.place.id, Scroll_Offset)
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
		if c.drag_scroll {
			at := scroll_by_drag(gtx, c.place.id, {sc.x, sc.y}, content - size)
			sc.x, sc.y = at.x, at.y
		}
		if r, ok := find_reveal(gtx, c.body); ok {
			sc.y = nearest_offset(sc.y, size.y, r.y, r.h)
			sc.x = nearest_offset(sc.x, size.x, r.x, r.w)
		}
		sc.y = clamp(sc.y, 0, max(content.y - size.y, 0))
		sc.x = clamp(sc.x, 0, max(content.x - size.x, 0))
		// The bars take their input before the body is placed, so a drag
		// moves the content this frame. Each bar has its own data slot;
		// the slots live on the heap, so sc stays valid while they are made.
		both := content.y > size.y && content.x > size.x
		sc.y = scroll_bar_handle(gtx, id_mix(c.place.id, 1), .Vertical, size, content.y, sc.y, both)
		sc.x = scroll_bar_handle(gtx, id_mix(c.place.id, 2), .Horizontal, size, content.x, sc.x, both)
		view := ops.Rect{0, 0, size.x, size.y}
		if content.y > size.y || content.x > size.x {
			kinds := ops.Event_Kinds{.Scroll}
			if c.drag_scroll {
				kinds += {.Press, .Move, .Release}
			}
			ops.input_area(o, c.place.id, view, kinds)
		}
		ops.clip_push(o, view)
		ops.transform_push(o, ops.translate(-sc.x, -sc.y))
		ops.call(o, c.body)
		ops.transform_pop(o)
		scroll_bar_paint(gtx, id_mix(c.place.id, 1), .Vertical, size, content.y, sc.y, both)
		scroll_bar_paint(gtx, id_mix(c.place.id, 2), .Horizontal, size, content.x, sc.x, both)
		ops.clip_pop(o)
		baseline = 0
	case .Center:
		ops.macro_close(o, c.body)
		want := ops.Size {
			is_finite(c.cs.max.x) ? c.cs.max.x : content.x,
			is_finite(c.cs.max.y) ? c.cs.max.y : content.y,
		}
		size = constrain(c.cs, want)
		off := (size - content) / 2
		ops.transform_push(o, translate_to(off))
		ops.call(o, c.body)
		ops.transform_pop(o)
		if baseline > 0 {
			baseline += off.y
		}
	}
	cover_close(gtx, &c)
	widget_close(gtx, &c.place, {size, baseline})
}

// cover_close ends what a covering overlay covers, once the container's
// children are all recorded: see overlay_open's cover.
@(private)
cover_close :: proc(gtx: ^Ctx, c: ^Container) {
	if c.covered {
		ops.cover_end(gtx.scene, c.place.id)
	}
}
