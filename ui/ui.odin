/*
Package ui is an immediate-mode user interface whose frame is data. A ui proc
records scene sc (transforms, clips, fills, glyph runs, input areas, tags)
into an ops.Scene buffer; flatten turns that into a device-space draw list and a hit
list; a renderer executes the draw list and a router hit-tests the hit list.
Every stage is a plain array with a text dump, so a frame can be asserted on,
serialized, or driven by a probe without a window.

	ui :: proc(gtx: ^ui.Ctx, m: ^Model) {
		col := ui.column_open(gtx, gap = 8); defer ui.close(&col)
		ui.label(gtx, "Name")
		base.label(gtx, m.name)
		if m3.button(gtx, "Save") { save(m) } // a design system's widget, on the same gtx
	}

Frame flow: router_route(router, previous frame) -> ops_reset -> ui(gtx) ->
flatten(sc, frame) -> render(frame). Input arrives one frame late by design:
events are routed against the previous frame's hit list, as in Gio.

Coordinates: y grows downwards, units are device pixels. ops.Affine follows the
Blend2D matrix layout: x' = a*x + c*y + e, y' = b*x + d*y + f.

Memory: ops.Scene holds only per-frame data and is reset each frame; slices inside
sc (paths, glyph runs, tag names) are expected to live in the frame
allocator. Nothing in this package is thread-safe; one Ctx per thread.

Subpackages: ui/blend2d is the raster binding, ui/render executes a Frame on
it and provides the Shaper, and shaper/render.snapshot a ui proc to a PNG
without a window. ui/sdl opens a window (sdl.run) or, for the host half of a
hot-reload split, spawns and re-spawns a subprocess in place of a local ui
proc (sdl.run_host); ui/child is that subprocess's own runtime loop; ui/ipc
is the framing and process handling underneath the two of them. The core
package has no foreign dependencies so `odin check` and tests need nothing
built.

Checking a change headlessly, cheapest first: `-dump` (see examples/
ui-kitchen, examples/hot-architecture) prints the scene as text — free of
vision tokens, and enough for most bugs (wrong position, wrong color as a
hex value, a missing widget). Reach for `-png` only once the question is
actually about pixels — blending, clipping, antialiasing — and even then,
render.diff_files (or the tools/img-diff command line over it) turns two
PNGs into a list of changed rects as text, so confirming an edit changed
what it should not need opening either image: only diff_files's own
`highlight` output, if anything, is worth a look. A headless example that
never opens a window builds faster and simpler importing only ui/child (as
examples/hot-counter and examples/hot-architecture's child binaries do) than
one that also imports ui/sdl for a window fallback (as ui-kitchen and
hotreload-diagram do) — real but, on programs this size, modest, so it is
a default for new headless-first work, not a reason to split an existing
example.
*/
package ui

import "core:mem"
import "jm:ui/ops"

// Ui_Proc builds one frame: it records into gtx.scene and reads events from
// gtx.router. user is passed through from whatever ran it (ui/sdl's App,
// ui/child's App) untouched.
Ui_Proc :: proc(gtx: ^Ctx, user: rawptr)

// Ctx is the per-frame layout context every widget takes first. Widgets
// record into the scene, size themselves inside constraints, take the
// toolkit's font from font, shape text through shaper and read their events from router.
// A host runs a frame for every input event, and one more after it, which
// events asks for; anything else that changes with time asks for its next
// frame with request_frame.
Ctx :: struct {
	scene:         ^ops.Scene,
	constraints: Constraints,
	font:        ops.Font_Id, // the toolkit's own face: text hit-testing, the debug chrome, and what a base label falls back to
	shaper:      Shaper,
	router:      ^Router,
	layout:      ^Layout,
	viewport:    ops.Size, // the window's size, in the units constraints use: what a layout keyed on the window rather than its own box (a CSS media query) reads from inside any container
	frame:       u64,
	dt:          f32, // seconds since the previous frame
	time:        f64, // seconds of frame time since the app began: the sum of every frame's dt, so a looping animation read from it is deterministic in a probe
	allocator:   mem.Allocator,
	wants_frame: bool, // request_frame was called this frame
	frame_after: f32, // then: the fewest seconds any caller asked to wait
	debug:       Debug_Flags, // inspection switches; see Debug_Flag
	restored:    []byte, // what the last child persisted, on the first frame after a hot-reload respawn; see restored
	persist:     []byte, // what persist asked the host to keep this frame
	// reduce_motion is the platform's reduce-motion setting
	// (reduce_motion_preferred), which the host sets each frame: a
	// decorative loop (a shimmer, a pulse) stands still while it is
	// true, and motion that shows progress, such as a spinner, keeps going.
	reduce_motion: bool,
}

// request_frame asks the host for another frame within after seconds; 0,
// the default, is the next display refresh. An animation asks every frame
// it moves. Of several requests in one frame the soonest wins; a frame with
// none waits for input.
request_frame :: proc(gtx: ^Ctx, after: f32 = 0) {
	a := max(after, 0)
	if !gtx.wants_frame || a < gtx.frame_after {
		gtx.frame_after = a
	}
	gtx.wants_frame = true
}

// Constraints flow down: a widget must return a size within [min, max].
Constraints :: struct {
	min, max: ops.Size,
}

// Dims flow up: the size a widget took, and its text baseline from the top
// (0 when it has none) so siblings can align on it.
Dims :: struct {
	size:     ops.Size,
	baseline: f32,
}

// exact makes constraints that admit only one size.
exact :: proc(s: ops.Size) -> Constraints {
	return {min = s, max = s}
}

// loose makes constraints from zero up to s.
loose :: proc(s: ops.Size) -> Constraints {
	return {min = {}, max = s}
}

// constrain clamps s into c.
constrain :: proc(c: Constraints, s: ops.Size) -> ops.Size {
	return {
		clamp(s.x, c.min.x, c.max.x),
		clamp(s.y, c.min.y, c.max.y),
	}
}

// constrain_min is constrain, except the result never goes below natural in
// either axis, even when c.max is smaller — a widget's own content (its
// label, its icon) sets a hard floor a too-small container cannot squeeze
// it past. The button family uses this instead of constrain so a
// pathologically small parent clips or overflows the button rather than
// shrinking its box below what its own text needs to stay legible.
constrain_min :: proc(c: Constraints, natural: ops.Size) -> ops.Size {
	s := constrain(c, natural)
	return {max(s.x, natural.x), max(s.y, natural.y)}
}
