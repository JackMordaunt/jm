package ui


import "jm:ui/ops"

// Frame is the flattened form of an ops.Scene: every draw carries its own device
// transform and a clip reference, so an executor never nests. Hits are the
// input areas in the same terms. Both are produced by flatten (flatten.odin)
// and consumed by ui/render and the router.

Clip_Id :: distinct i32

NO_CLIP :: Clip_Id(-1)

// Clip is one node of the clip tree: this shape under this device
// transform, intersected with parent. Executors resolve a chain to a device
// rect when every node is a Rect under an axis-aligned transform, and fall
// back to a mask layer otherwise.
Clip :: struct {
	parent:    Clip_Id,
	shape:     ops.Shape,
	transform: ops.Affine,
}

Draw_Cmd :: union {
	ops.Fill,
	ops.Stroke,
	ops.Glyphs,
	ops.Image,
	ops.Shadow,
}

Draw :: struct {
	transform: ops.Affine,
	clip:      Clip_Id,
	cmd:       Draw_Cmd,
}

Hit :: struct {
	area:      ops.Area_Id,
	kinds:     ops.Event_Kinds,
	shape:     ops.Shape,
	transform: ops.Affine,
	clip:      Clip_Id,
	order:     int, // recording order; later areas are on top
	layer:     i32, // 0 for the frame, higher for each overlay drawn over it (Defer)
	cursor:    ops.Cursor, // the pointer's look over it
	yields:    bool, // see ops.Input_Area
	observes:  bool, // see ops.Input_Area
}

// Placed is a popup flatten placed (see ops.Placement): its key, the
// side it opened on, which is the asked side unless flatten flipped it,
// and how far it was shifted along its edge to stay in the window, in
// the anchor's own coordinates.
Placed :: struct {
	key:   ops.Area_Id,
	side:  ops.Side,
	shift: ops.Point,
}

// Layout_Box is a Debug_Box placed on the frame: its rect in device space.
Layout_Box :: struct {
	id:        ops.Area_Id,
	rect:      ops.Rect,
	min, max:  ops.Size,
	depth:     i32,
	file:      string,
	line:      i32,
	procedure: string,
	kind:      string, // the widget proc that made it: button, column
	clip:      Clip_Id,
	layer:     i32, // 0 for the frame, higher for each overlay drawn over it (Defer)
}

// Semantic_Node is a Semantic op placed on the frame: its rect in device
// space, and its parent by id (0 at the top), from which semantics_report
// rebuilds the tree.
Semantic_Node :: struct {
	id:        ops.Area_Id,
	parent:    ops.Area_Id,
	semantics: ops.Semantics,
	rect:      ops.Rect,
	layer:     i32,
	clip:      Clip_Id,
}

Frame :: struct {
	draws: [dynamic]Draw,
	clips: [dynamic]Clip,
	hits:  [dynamic]Hit,
	tags:  [dynamic]ops.Tag,
	nodes: [dynamic]Semantic_Node, // every Semantic, in close order
	keys:  [dynamic]ops.Key_Interest, // every Key_Interest, for the router
	boxes: [dynamic]Layout_Box, // under Debug_Flag.Inspect, every widget's layout
	placed: [dynamic]Placed, // every popup flatten placed, and the side it chose
	scene:   ^ops.Scene, // resources: paths, runs, fonts, images //review:ignore odin-destroy-incomplete borrowed: flatten points it at the caller's scene
	stacks:  Flatten_Stacks, // flatten's scratch, not part of the result
}

// Flatten_Stacks are flatten's working stacks. They live on the Frame so
// a steady frame reuses their capacity instead of allocating: flatten
// touches no allocator once the frame's arrays have grown to fit.
@(private)
Flatten_Stacks :: struct {
	transforms: [dynamic]ops.Affine, // the transforms pushed so far, innermost last
	clips:      [dynamic]Clip_Id, // likewise the clips
	deferred:   [dynamic]Deferred, // the Defers met, run after everything else
	held:       [dynamic]Covering, // covering Defers met, waiting for their Cover_End
}

// Covering is a Defer waiting for the end of the container it covers.
@(private)
Covering :: struct {
	covers:   ops.Area_Id,
	deferred: Deferred,
}

// Deferred is a Defer met during flatten: its macro and the transform to
// run it under once everything else is flattened.
@(private)
Deferred :: struct {
	id:        ops.Macro_Id,
	transform: ops.Affine,
}

frame_init :: proc(f: ^Frame, allocator := context.allocator) {
	f.draws = make([dynamic]Draw, allocator)
	f.clips = make([dynamic]Clip, allocator)
	f.hits = make([dynamic]Hit, allocator)
	f.tags = make([dynamic]ops.Tag, allocator)
	f.nodes = make([dynamic]Semantic_Node, allocator)
	f.keys = make([dynamic]ops.Key_Interest, allocator)
	f.boxes = make([dynamic]Layout_Box, allocator)
	f.placed = make([dynamic]Placed, allocator)
	f.stacks.transforms = make([dynamic]ops.Affine, allocator)
	f.stacks.clips = make([dynamic]Clip_Id, allocator)
	f.stacks.deferred = make([dynamic]Deferred, allocator)
	f.stacks.held = make([dynamic]Covering, allocator)
}

frame_reset :: proc(f: ^Frame) {
	clear(&f.draws)
	clear(&f.clips)
	clear(&f.hits)
	clear(&f.tags)
	clear(&f.nodes)
	clear(&f.keys)
	clear(&f.boxes)
	clear(&f.placed)
	clear(&f.stacks.transforms)
	clear(&f.stacks.clips)
	clear(&f.stacks.deferred)
	clear(&f.stacks.held)
	f.scene = nil
}

frame_destroy :: proc(f: ^Frame) {
	delete(f.draws)
	delete(f.clips)
	delete(f.hits)
	delete(f.tags)
	delete(f.nodes)
	delete(f.keys)
	delete(f.boxes)
	delete(f.placed)
	delete(f.stacks.transforms)
	delete(f.stacks.clips)
	delete(f.stacks.deferred)
	delete(f.stacks.held)
	f^ = {}
}
