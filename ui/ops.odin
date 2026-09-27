package ui

import "core:mem"

// Scene ops. A ui proc records these; flatten consumes them. Push/Pop pairs
// nest; Macro_Begin..Macro_End brackets ops that are skipped inline and run
// only where a Call names them, under the transform and clip current at the
// Call. That is how a parent measures a child before placing it.

Push_Transform :: struct {
	m: Affine,
}

Pop_Transform :: struct {
}

Push_Clip :: struct {
	shape: Shape,
}

Pop_Clip :: struct {
}

Macro_Begin :: struct {
	id: Macro_Id,
}

Macro_End :: struct {
	id: Macro_Id,
}

Call :: struct {
	id: Macro_Id,
}

Fill :: struct {
	shape: Shape,
	paint: Paint,
}

Stroke :: struct {
	shape: Shape,
	paint: Paint,
	style: Stroke_Style,
}

Glyphs :: struct {
	run:    Run_Id,
	origin: Point, // baseline origin
	color:  Color,
}

Image :: struct {
	id:  Image_Id,
	dst: Rect,
	src: Rect, // in image pixels; zero rect means the whole image
}

// Input_Area registers a hit region under the current transform and clip.
// Widgets choose their own Area_Id; a stable id across frames is what lets
// the router track hover, press and focus.
Input_Area :: struct {
	id:    Area_Id,
	shape: Shape,
	kinds: Event_Kinds,
}

// Tag names an area for the dump and the probe: probe.find("Save").
Tag :: struct {
	id:   Area_Id,
	name: string,
}

Op :: union {
	Push_Transform,
	Pop_Transform,
	Push_Clip,
	Pop_Clip,
	Macro_Begin,
	Macro_End,
	Call,
	Fill,
	Stroke,
	Glyphs,
	Image,
	Input_Area,
	Tag,
}

// Macro records the op index range [first, last) of a macro's body,
// excluding its Macro_Begin and Macro_End ops.
Macro :: struct {
	first, last: int,
}

Font_Ref :: struct {
	id:   Font_Id,
	path: string,
}

Image_Ref :: struct {
	id:   Image_Id,
	path: string,
}

// Ops is one frame of scene ops plus the resources they reference. It is
// the wire format: encode(ops) is everything a remote renderer needs, given
// it can open the font and image paths.
Ops :: struct {
	ops:       [dynamic]Op,
	paths:     [dynamic]Path,
	runs:      [dynamic]Glyph_Run,
	macros:    [dynamic]Macro,
	fonts:     [dynamic]Font_Ref,
	images:    [dynamic]Image_Ref,
	allocator: mem.Allocator,
}

ops_init :: proc(o: ^Ops, allocator := context.allocator) {
	o.allocator = allocator
	o.ops = make([dynamic]Op, allocator)
	o.paths = make([dynamic]Path, allocator)
	o.runs = make([dynamic]Glyph_Run, allocator)
	o.macros = make([dynamic]Macro, allocator)
	o.fonts = make([dynamic]Font_Ref, allocator)
	o.images = make([dynamic]Image_Ref, allocator)
}

// ops_reset empties the frame but keeps fonts and images: those are
// registered once and referenced by id every frame.
ops_reset :: proc(o: ^Ops) {
	clear(&o.ops)
	clear(&o.paths)
	clear(&o.runs)
	clear(&o.macros)
}

ops_destroy :: proc(o: ^Ops) {
	delete(o.ops)
	delete(o.paths)
	delete(o.runs)
	delete(o.macros)
	delete(o.fonts)
	delete(o.images)
	o^ = {}
}

// Recorders. Each appends one op; the widget layer builds on these.

push_transform :: proc(o: ^Ops, m: Affine) {
	append(&o.ops, Push_Transform{m})
}

pop_transform :: proc(o: ^Ops) {
	append(&o.ops, Pop_Transform{})
}

push_clip :: proc(o: ^Ops, shape: Shape) {
	append(&o.ops, Push_Clip{shape})
}

pop_clip :: proc(o: ^Ops) {
	append(&o.ops, Pop_Clip{})
}

fill :: proc(o: ^Ops, shape: Shape, paint: Paint) {
	append(&o.ops, Fill{shape, paint})
}

stroke :: proc(o: ^Ops, shape: Shape, paint: Paint, style: Stroke_Style) {
	append(&o.ops, Stroke{shape, paint, style})
}

glyphs :: proc(o: ^Ops, run: Run_Id, origin: Point, color: Color) {
	append(&o.ops, Glyphs{run, origin, color})
}

image :: proc(o: ^Ops, id: Image_Id, dst: Rect, src: Rect = {}) {
	append(&o.ops, Image{id, dst, src})
}

input_area :: proc(o: ^Ops, id: Area_Id, shape: Shape, kinds: Event_Kinds) {
	append(&o.ops, Input_Area{id, shape, kinds})
}

tag :: proc(o: ^Ops, id: Area_Id, name: string) {
	append(&o.ops, Tag{id, name})
}

// macro_begin opens a macro; ops recorded until macro_end are not run
// inline. Returns the id to macro_end and call.
macro_begin :: proc(o: ^Ops) -> Macro_Id {
	id := Macro_Id(len(o.macros))
	append(&o.macros, Macro{first = len(o.ops) + 1, last = -1})
	append(&o.ops, Macro_Begin{id})
	return id
}

macro_end :: proc(o: ^Ops, id: Macro_Id) {
	o.macros[id].last = len(o.ops)
	append(&o.ops, Macro_End{id})
}

call :: proc(o: ^Ops, id: Macro_Id) {
	append(&o.ops, Call{id})
}

// Resources.

// add_path records p as given: it does not copy verbs or points, so they
// must outlive the frame (gtx.allocator, never a bare composite literal —
// see Path). add_run and add_image/add_font follow the same rule for their
// own slices.
add_path :: proc(o: ^Ops, p: Path) -> Path_Id {
	append(&o.paths, p)
	return Path_Id(len(o.paths) - 1)
}

add_run :: proc(o: ^Ops, r: Glyph_Run) -> Run_Id {
	append(&o.runs, r)
	return Run_Id(len(o.runs) - 1)
}

// add_font registers a font file once; ids are stable for the life of Ops.
add_font :: proc(o: ^Ops, path: string) -> Font_Id {
	for f in o.fonts {
		if f.path == path {
			return f.id
		}
	}
	id := Font_Id(len(o.fonts))
	append(&o.fonts, Font_Ref{id, path})
	return id
}

add_image :: proc(o: ^Ops, path: string) -> Image_Id {
	for f in o.images {
		if f.path == path {
			return f.id
		}
	}
	id := Image_Id(len(o.images))
	append(&o.images, Image_Ref{id, path})
	return id
}
