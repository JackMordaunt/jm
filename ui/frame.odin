package ui

// Frame is the flattened form of Ops: every draw carries its own device
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
	shape:     Shape,
	transform: Affine,
}

Draw_Cmd :: union {
	Fill,
	Stroke,
	Glyphs,
	Image,
}

Draw :: struct {
	transform: Affine,
	clip:      Clip_Id,
	cmd:       Draw_Cmd,
}

Hit :: struct {
	area:      Area_Id,
	kinds:     Event_Kinds,
	shape:     Shape,
	transform: Affine,
	clip:      Clip_Id,
	order:     int, // recording order; later areas are on top
	layer:     i32, // 0 for the frame, higher for each overlay drawn over it (Defer)
}

// Layout_Box is a Debug_Box placed on the frame: its rect in device space.
Layout_Box :: struct {
	id:        Area_Id,
	rect:      Rect,
	min, max:  Size,
	depth:     i32,
	file:      string,
	line:      i32,
	procedure: string,
	clip:      Clip_Id,
	layer:     i32, // 0 for the frame, higher for each overlay drawn over it (Defer)
}

Frame :: struct {
	draws: [dynamic]Draw,
	clips: [dynamic]Clip,
	hits:  [dynamic]Hit,
	tags:  [dynamic]Tag,
	boxes: [dynamic]Layout_Box, // under Debug_Flag.Inspect, every widget's layout
	ops:   ^Ops, // resources: paths, runs, fonts, images
}

frame_init :: proc(f: ^Frame, allocator := context.allocator) {
	f.draws = make([dynamic]Draw, allocator)
	f.clips = make([dynamic]Clip, allocator)
	f.hits = make([dynamic]Hit, allocator)
	f.tags = make([dynamic]Tag, allocator)
	f.boxes = make([dynamic]Layout_Box, allocator)
}

frame_reset :: proc(f: ^Frame) {
	clear(&f.draws)
	clear(&f.clips)
	clear(&f.hits)
	clear(&f.tags)
	clear(&f.boxes)
	f.ops = nil
}

frame_destroy :: proc(f: ^Frame) {
	delete(f.draws)
	delete(f.clips)
	delete(f.hits)
	delete(f.tags)
	delete(f.boxes)
	f^ = {}
}
