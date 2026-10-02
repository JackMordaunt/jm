package ui

import "base:runtime"

// Guards: every container opener as a self-closing form.
//
//	if ui.column(gtx, gap = 8) {
//		ui.label(gtx, "Name")
//		if ui.row(gtx, gap = 4) {
//			ui.label(gtx, "Save")
//		}
//	}
//
// The opener returns true and Odin's deferred_in calls its closer at the
// end of the if, with the same arguments, so nothing is left open and
// nothing has to be paired by hand. The closer closes the innermost
// container, which is the one this call opened: a guard's scope is the
// scope of its call, so opens and closes nest as the blocks do. It
// asserts the kind, so a guard that finds another kind on top fails
// loudly rather than closing the wrong container.
//
// The explicit pair, column_open and close, is for a body that spans
// procs or needs the handle.

@(deferred_in = column_guard_close)
column :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
	justify := Justify.Start,
) -> bool {
	column_open(gtx, gap, align, key, loc, justify)
	return true
}

@(deferred_in = row_guard_close)
row :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
	justify := Justify.Start,
) -> bool {
	row_open(gtx, gap, align, key, loc, justify)
	return true
}

@(deferred_in = wrap_guard_close)
wrap :: proc(
	gtx: ^Ctx,
	gap: f32 = 0,
	line_gap: f32 = -1,
	align: Align = .Start,
	key: u64 = 0,
	loc := #caller_location,
	justify := Justify.Start,
) -> bool {
	wrap_open(gtx, gap, line_gap, align, key, loc, justify)
	return true
}

@(deferred_in = stack_guard_close)
stack :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	stack_open(gtx, key, loc)
	return true
}

@(deferred_in = inset_guard_close)
inset :: proc(gtx: ^Ctx, padding: Padding, key: u64 = 0, loc := #caller_location) -> bool {
	inset_open(gtx, padding, key, loc)
	return true
}

@(deferred_in = sized_guard_close)
sized :: proc(gtx: ^Ctx, limits: Size_Limits, key: u64 = 0, loc := #caller_location) -> bool {
	sized_open(gtx, limits, key, loc)
	return true
}

@(deferred_in = box_guard_close)
box :: proc(gtx: ^Ctx, style := Box_Style{}, key: u64 = 0, loc := #caller_location) -> bool {
	box_open(gtx, style, key, loc)
	return true
}

@(deferred_in = clip_box_guard_close)
clip_box :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	clip_box_open(gtx, key, loc)
	return true
}

@(deferred_in = centered_guard_close)
centered :: proc(gtx: ^Ctx, key: u64 = 0, loc := #caller_location) -> bool {
	centered_open(gtx, key, loc)
	return true
}

@(deferred_in = scroll_box_guard_close)
scroll_box :: proc(gtx: ^Ctx, key: u64 = 0, min_width: f32 = 0, offset: ^Scroll_Offset = nil, loc := #caller_location, wide := false) -> bool {
	scroll_box_open(gtx, key, min_width, offset, loc, wide)
	return true
}

// The closers take the guard's arguments, as deferred_in hands them over,
// and use only gtx.

@(private = "file")
column_guard_close :: proc(
	gtx: ^Ctx,
	gap: f32,
	align: Align,
	key: u64,
	loc: runtime.Source_Code_Location,
	justify: Justify,
) {
	innermost_close(gtx, .Flex)
}

@(private = "file")
row_guard_close :: proc(
	gtx: ^Ctx,
	gap: f32,
	align: Align,
	key: u64,
	loc: runtime.Source_Code_Location,
	justify: Justify,
) {
	innermost_close(gtx, .Flex)
}

@(private = "file")
wrap_guard_close :: proc(
	gtx: ^Ctx,
	gap: f32,
	line_gap: f32,
	align: Align,
	key: u64,
	loc: runtime.Source_Code_Location,
	justify: Justify,
) {
	innermost_close(gtx, .Flex)
}

@(private = "file")
sized_guard_close :: proc(gtx: ^Ctx, limits: Size_Limits, key: u64, loc: runtime.Source_Code_Location) {
	innermost_close(gtx, .Inset)
}

@(private = "file")
stack_guard_close :: proc(gtx: ^Ctx, key: u64, loc: runtime.Source_Code_Location) {
	innermost_close(gtx, .Stack)
}

@(private = "file")
inset_guard_close :: proc(
	gtx: ^Ctx,
	padding: Padding,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	innermost_close(gtx, .Inset)
}

@(private = "file")
box_guard_close :: proc(gtx: ^Ctx, style: Box_Style, key: u64, loc: runtime.Source_Code_Location) {
	innermost_close(gtx, .Box)
}

@(private = "file")
clip_box_guard_close :: proc(gtx: ^Ctx, key: u64, loc: runtime.Source_Code_Location) {
	innermost_close(gtx, .Clip)
}

@(private = "file")
centered_guard_close :: proc(gtx: ^Ctx, key: u64, loc: runtime.Source_Code_Location) {
	innermost_close(gtx, .Center)
}

@(private = "file")
scroll_box_guard_close :: proc(
	gtx: ^Ctx,
	key: u64,
	min_width: f32,
	offset: ^Scroll_Offset,
	loc: runtime.Source_Code_Location,
	wide: bool,
) {
	innermost_close(gtx, .Scroll)
}

// innermost_close closes the innermost container, which must be of kind:
// what a guard opened is what is on top when its scope ends. Without a
// layout the open pushed nothing, so there is nothing to close. A design
// system's guards (material.card) close through it too.
innermost_close :: proc(gtx: ^Ctx, kind: Container_Kind) {
	l := gtx.layout
	if l == nil {
		return
	}
	c := innermost(l)
	assert(c != nil && c.kind == kind, "ui: a guard's scope ended with another container on top")
	i := depth(l) - 1
	if kind == .Flex {
		f := Flex{gtx, i}
		flex_close(&f)
	} else {
		container_close(gtx, &i)
	}
}

// guard_hold gives a design system's guard somewhere to keep its handle
// until its closer runs: deferred_in hands the closer only the opener's
// arguments, so the opener fills the slot this returns and the closer takes
// it back with guard_take. Holds nest as the guards do. The slot lives in
// the frame allocator; without a layout nothing is kept and guard_take
// returns a zero handle.
guard_hold :: proc(gtx: ^Ctx, $T: typeid) -> ^T {
	h := new(T, gtx.allocator)
	if l := gtx.layout; l != nil {
		append(&l.held, Held{T, h})
	}
	return h
}

// guard_take is the handle the innermost guard_hold kept, which must be a T:
// a guard that finds another guard's handle fails loudly rather than
// closing the wrong thing.
guard_take :: proc(gtx: ^Ctx, $T: typeid) -> ^T {
	l := gtx.layout
	if l == nil {
		return new(T, gtx.allocator)
	}
	assert(len(l.held) > 0, "ui: a guard closed with no handle held")
	h := pop(&l.held)
	assert(h.type == T, "ui: a guard's scope ended with another guard's handle on top")
	return (^T)(h.ptr)
}

// Held is one guard handle kept between guard_hold and guard_take.
@(private)
Held :: struct {
	type: typeid,
	ptr:  rawptr,
}
