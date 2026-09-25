/*
Package ui is an immediate-mode user interface whose frame is data. A ui proc
records scene ops (transforms, clips, fills, glyph runs, input areas, tags)
into an Ops buffer; flatten turns that into a device-space draw list and a hit
list; a renderer executes the draw list and a router hit-tests the hit list.
Every stage is a plain array with a text dump, so a frame can be asserted on,
serialized, or driven by a probe without a window.

	ui :: proc(gtx: ^ui.Ctx, m: ^Model) {
		col := ui.column(gtx, gap = 8); defer ui.end(&col)
		ui.label(gtx, "Name")
		ui.text_field(gtx, &m.name)
		if ui.button(gtx, "Save") { save(m) }
	}

Frame flow: ops_reset -> ui(gtx) -> flatten(ops, frame) -> router_commit(frame.hits)
-> render(frame). Input arrives one frame late by design: events are routed
against the previous frame's hit list, as in Gio.

Coordinates: y grows downwards, units are device pixels. Affine follows the
Blend2D matrix layout: x' = a*x + c*y + e, y' = b*x + d*y + f.

Memory: Ops holds only per-frame data and is reset each frame; slices inside
ops (paths, glyph runs, tag names) are expected to live in the frame
allocator. Nothing in this package is thread-safe; one Ctx per thread.

Subpackages: ui/blend2d is the raster binding, ui/render executes a Frame on
it and provides the Shaper, ui/sdl opens a window. The core package has no
foreign dependencies so `odin check` and tests need nothing built.
*/
package ui

import "core:mem"

// Ctx is the per-frame layout context every widget takes first. Widgets
// record into ops, size themselves inside constraints, read theme for
// defaults, shape text through shaper and read their events from router.
Ctx :: struct {
	ops:         ^Ops,
	constraints: Constraints,
	theme:       ^Theme,
	shaper:      Shaper,
	router:      ^Router,
	frame:       u64,
	dt:          f32,
	allocator:   mem.Allocator,
}

// Constraints flow down: a widget must return a size within [min, max].
Constraints :: struct {
	min, max: Size,
}

// Dims flow up: the size a widget took, and its text baseline from the top
// (0 when it has none) so siblings can align on it.
Dims :: struct {
	size:     Size,
	baseline: f32,
}

// exact makes constraints that admit only one size.
exact :: proc(s: Size) -> Constraints {
	return {min = s, max = s}
}

// loose makes constraints from zero up to s.
loose :: proc(s: Size) -> Constraints {
	return {min = {}, max = s}
}

// constrain clamps s into c.
constrain :: proc(c: Constraints, s: Size) -> Size {
	return {
		clamp(s.x, c.min.x, c.max.x),
		clamp(s.y, c.min.y, c.max.y),
	}
}
