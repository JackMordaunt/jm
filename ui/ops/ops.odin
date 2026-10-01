package ops

import "core:mem"

// Package ops is the recorded drawing. A Scene is one frame of it: what a ui proc emits and what
// flatten, encode, dump and the renderer read. Its types are the scene's
// vocabulary — geometry, colour, paint, shapes, glyph runs and the ops
// themselves — so nothing above it defines a Rect of its own.
//
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

// Defer runs a macro after the rest of the frame, on top of it, under the
// transform current at the Defer (identity when root) and no clip. It is
// how a menu or tooltip paints above everything while still positioned
// against the widget that opened it — that widget cannot know its own
// device position while recording, since a container may place it later
// through a macro — and how a dialog covers the whole window (root).
//
// A placed Defer (place.set) is a popup: its macro is laid out from its
// own origin, and flatten chooses where that origin lands so the popup
// stays in the viewport (see Placement).
Defer :: struct {
	id:    Macro_Id,
	root:  bool,
	place: Placement,
}

// Side is which side of its anchor a popup opens on. After is the
// inline end (right, left to right), Before the inline start.
Side :: enum u8 {
	Below,
	Above,
	After,
	Before,
}

// Side_Align is where a popup sits along its anchor's edge: flush with
// the anchor's start, centred on it, or flush with its end.
Side_Align :: enum u8 {
	Start,
	Center,
	End,
}

// Placement is a popup's position asked of flatten, in the coordinates
// current at the Defer: open on side of anchor, gap away, aligned along
// the edge by align, the popup being size. flatten flips to the opposite
// side when side leaves the popup outside the viewport and the opposite
// side does not, or leaves it less outside; then it shifts the popup
// along both axes to keep it inside. key names the popup, so the side
// flatten chose can be read back the next frame (ui.placed_side).
Placement :: struct {
	set:    bool,
	key:    Area_Id,
	anchor: Rect,
	size:   Size,
	side:   Side,
	align:  Side_Align,
	gap:    f32,
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
	id:     Area_Id,
	shape:  Shape,
	kinds:  Event_Kinds,
	cursor: Cursor, // the pointer's look while it is over this area
	// yields: a press here goes to the area under it that wants Press, if
	// any, until the pointer drags past ui.YIELD_DRAG or a double click
	// lands; then this area takes the press (and the other a Cancel). It is
	// how selectable text inside a clickable card keeps the card clickable.
	yields: bool,
	// observes: the area is an observer. It is sent Enter and Leave while
	// the pointer is over it, whatever lies on top, and nothing else; it
	// takes no hover, press or cursor from the areas it overlaps. It is
	// how a tooltip wrapping a control learns the pointer is over it.
	observes: bool,
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
	Defer,
	Fill,
	Stroke,
	Glyphs,
	Image,
	Input_Area,
	Tag,
	Debug_Box,
	Shadow,
}

// Shadow is the soft shadow of a rounded rect, as a CSS box-shadow draws
// one: rect is the shape casting it, already offset and spread by the
// caller, radius its corners, blur the CSS blur radius (the Gaussian's
// sigma is half of it, CSS Backgrounds and Borders 3, 7.2 "Drop Shadows";
// the shadow reaches 1.5 blur past rect), color the
// shadow at its densest. The renderer computes it in closed form, not by
// blurring pixels, so it is exact at any size and cheap to repeat.
Shadow :: struct {
	rect:   Rect,
	radius: f32,
	blur:   f32,
	color:  Color,
}

// Debug_Box records one widget's layout for the inspector, when
// Debug_Flag.Inspect is on: its box, size wide and tall from the local
// origin, the constraints it was given, how deep in the container stack it
// sat, and the call that made it. It draws nothing.
Debug_Box :: struct {
	id:        Area_Id,
	size:      Size,
	min, max:  Size, // the constraints the widget was given
	depth:     i32,
	file:      string,
	line:      i32,
	procedure: string,
	kind:      string, // the widget proc that made it, its _open suffix dropped: button, column
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

// Scene is one frame of scene ops plus the resources they reference. It is
// the wire format: encode(ops) is everything a remote renderer needs, given
// it can open the font and image paths.
Scene :: struct {
	ops:       [dynamic]Op,
	paths:     [dynamic]Path,
	runs:      [dynamic]Glyph_Run,
	macros:    [dynamic]Macro,
	fonts:     [dynamic]Font_Ref,
	images:    [dynamic]Image_Ref,
	allocator: mem.Allocator,
	outline_areas: bool, // input_area also records each area's outline, for a debug view
	// decoded holds what decode read (paths, glyphs, strings) until the next
	// decode resets it: a host decodes a frame a refresh, and anything kept
	// longer piles up.
	decoded:   Frame_Arena,
	has_decoded: bool,
}

init :: proc(o: ^Scene, allocator := context.allocator) {
	o.allocator = allocator
	o.ops = make([dynamic]Op, allocator)
	o.paths = make([dynamic]Path, allocator)
	o.runs = make([dynamic]Glyph_Run, allocator)
	o.macros = make([dynamic]Macro, allocator)
	o.fonts = make([dynamic]Font_Ref, allocator)
	o.images = make([dynamic]Image_Ref, allocator)
}

// reset empties the frame but keeps fonts and images: those are
// registered once and referenced by id every frame.
reset :: proc(o: ^Scene) {
	clear(&o.ops)
	clear(&o.paths)
	clear(&o.runs)
	clear(&o.macros)
}

destroy :: proc(o: ^Scene) {
	if o.has_decoded {
		frame_arena_destroy(&o.decoded)
	}
	delete(o.ops)
	delete(o.paths)
	delete(o.runs)
	delete(o.macros)
	delete(o.fonts)
	delete(o.images)
	o^ = {}
}

// Recorders. Each appends one op; the widget layer builds on these.

transform_push :: proc(o: ^Scene, m: Affine) {
	append(&o.ops, Push_Transform{m})
}

transform_pop :: proc(o: ^Scene) {
	append(&o.ops, Pop_Transform{})
}

clip_push :: proc(o: ^Scene, shape: Shape) {
	append(&o.ops, Push_Clip{shape})
}

clip_pop :: proc(o: ^Scene) {
	append(&o.ops, Pop_Clip{})
}

fill :: proc(o: ^Scene, shape: Shape, paint: Paint) {
	append(&o.ops, Fill{shape, paint})
}

stroke :: proc(o: ^Scene, shape: Shape, paint: Paint, style: Stroke_Style) {
	append(&o.ops, Stroke{shape, paint, style})
}

glyphs :: proc(o: ^Scene, run: Run_Id, origin: Point, color: Color) {
	append(&o.ops, Glyphs{run, origin, color})
}

// shadow_bounds is where s paints: its rect grown by three sigmas, 1.5
// blur. What lies past that is the Gaussian's tail beyond 3 sigma, 0.13%
// of the shadow's density, under one step of 8-bit alpha.
shadow_bounds :: proc(s: Shadow) -> Rect {
	e := max(s.blur, 0) * 1.5
	return {s.rect.x - e, s.rect.y - e, s.rect.w + 2 * e, s.rect.h + 2 * e}
}

// shadow records the soft shadow of the rounded rect r; see Shadow.
shadow :: proc(o: ^Scene, r: Rect, radius, blur: f32, color: Color) {
	append(&o.ops, Shadow{r, radius, blur, color})
}

image :: proc(o: ^Scene, id: Image_Id, dst: Rect, src: Rect = {}) {
	append(&o.ops, Image{id, dst, src})
}

input_area :: proc(o: ^Scene, id: Area_Id, shape: Shape, kinds: Event_Kinds, cursor := Cursor.Default, yields := false) {
	append(&o.ops, Input_Area{id, shape, kinds, cursor, yields, false})
	if o.outline_areas {
		// Every area a user can reach, widget or painted row alike.
		stroke(o, shape, HIT_BOUNDS_COLOR, {width = 1})
	}
}

// observer_area records an observer (Input_Area.observes) over shape:
// id is sent Enter and Leave as the pointer crosses it, and nothing else.
observer_area :: proc(o: ^Scene, id: Area_Id, shape: Shape) {
	append(&o.ops, Input_Area{id = id, shape = shape, kinds = {.Enter, .Leave}, observes = true})
}

// HIT_BOUNDS_COLOR outlines input areas under Debug_Flag.Bounds: cyan,
// against BOUNDS_COLOR's magenta for widget boxes.
HIT_BOUNDS_COLOR :: Color{0, 200, 255, 160}

tag :: proc(o: ^Scene, id: Area_Id, name: string) {
	append(&o.ops, Tag{id, name})
}

// macro_open opens a macro; ops recorded until macro_close are not run
// inline. Returns the id to macro_close and call.
macro_open :: proc(o: ^Scene) -> Macro_Id {
	id := Macro_Id(len(o.macros))
	append(&o.macros, Macro{first = len(o.ops) + 1, last = -1})
	append(&o.ops, Macro_Begin{id})
	return id
}

macro_close :: proc(o: ^Scene, id: Macro_Id) {
	o.macros[id].last = len(o.ops)
	append(&o.ops, Macro_End{id})
}

call :: proc(o: ^Scene, id: Macro_Id) {
	append(&o.ops, Call{id})
}

// defer_place runs macro id after the rest of the frame, on top, as a
// popup placed by place; see Defer and Placement.
defer_place :: proc(o: ^Scene, id: Macro_Id, place: Placement) {
	p := place
	p.set = true
	append(&o.ops, Defer{id = id, place = p})
}

// defer_call runs macro id after the rest of the frame, on top; see Defer.
defer_call :: proc(o: ^Scene, id: Macro_Id, root := false) {
	append(&o.ops, Defer{id = id, root = root})
}

// Resources.

// add_path records p as given: it does not copy verbs or points, so they
// must outlive the frame (gtx.allocator, never a bare composite literal —
// see Path). add_run and add_image/add_font follow the same rule for their
// own slices.
add_path :: proc(o: ^Scene, p: Path) -> Path_Id {
	append(&o.paths, p)
	return Path_Id(len(o.paths) - 1)
}

add_run :: proc(o: ^Scene, r: Glyph_Run) -> Run_Id {
	append(&o.runs, r)
	return Run_Id(len(o.runs) - 1)
}

// add_font registers a font file once; ids are stable for the life of Scene.
add_font :: proc(o: ^Scene, path: string) -> Font_Id {
	next := Font_Id(0)
	for f in o.fonts {
		if f.path == path {
			return f.id
		}
		next = max(next, f.id + 1)
	}
	append(&o.fonts, Font_Ref{next, path})
	return next
}

// add_fonts registers each ref under its own id, even when refs share a
// path: an app that falls back to one file for several weights still
// draws with every id it asked for.
add_fonts :: proc(o: ^Scene, refs: []Font_Ref) {
	append(&o.fonts, ..refs)
}

add_image :: proc(o: ^Scene, path: string) -> Image_Id {
	for f in o.images {
		if f.path == path {
			return f.id
		}
	}
	id := Image_Id(len(o.images))
	append(&o.images, Image_Ref{id, path})
	return id
}
