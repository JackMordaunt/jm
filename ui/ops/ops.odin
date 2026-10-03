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

// Push_Sticky is a translation down that flatten works out, popped by
// Pop_Transform: what follows moves down until its origin is top below
// the top edge of the innermost clip (the scroll box it scrolls in), by
// no more than room, as CSS position: sticky with top pins a box inside
// its container while the page scrolls. Pinned content stays where it
// is drawn for hit-testing too.
Push_Sticky :: struct {
	top, room: f32,
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
// transform current at the Defer (when root, the frame's root transform,
// the host's density scale; see ui.flatten) and no clip. It is
// how a menu or tooltip paints above everything while still positioned
// against the widget that opened it — that widget cannot know its own
// device position while recording, since a container may place it later
// through a macro — and how a dialog covers the whole window (root).
//
// A placed Defer (place.set) is a popup: its macro is laid out from its
// own origin, and flatten chooses where that origin lands so the popup
// stays in the viewport (see Placement).
//
// A covering Defer (cover) stacks above everything recorded in a
// container, not only what came before it: it keeps the transform current
// where it is met but joins the run order at the Cover_End for covers, so
// the container's later children and the Defers they raise sit under it.
// covers 0 is the window: it joins once every other Defer has run.
//
// A top Defer runs after every other, covers of the window included, in
// the order met among top ones: the debug tray, which must stay usable
// over a modal that covers the window.
Defer :: struct {
	id:     Macro_Id,
	root:   bool,
	cover:  bool,
	top:    bool,
	covers: Area_Id,
	place:  Placement,
}

// Cover_End is the end of container id: the covering Defers that name it
// join the run order here, in the order they were met.
Cover_End :: struct {
	id: Area_Id,
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
// the edge by align and moved nudge from the aligned edge toward the
// centre (away from the anchor's end for End), the popup being size.
// With inside it sits within the anchor against side's edge, gap in
// from it, and never changes side.
//
// Fitting it into the viewport, each test along one axis only:
//
//   - Side. With no sides given, flatten flips to the opposite side when
//     side leaves the popup outside the viewport on side's axis and the
//     opposite leaves it less outside. With sides given (side_count of
//     them), it tries them in order while the one placed overflows on its
//     own axis; the first that fits wins, else the last tried stands.
//   - Alignment. With aligns given, it tries them in order while the
//     popup overflows the viewport horizontally, whatever the side: past
//     either edge for Start and Center, past the left for End; the first
//     that fits wins, else the last tried stands. A popup beside its
//     anchor that overflows vertically is left to the shift.
//   - Shift. Last, it shifts the popup along both axes to lie inside,
//     flush with the viewport's start when larger than it. With overhang
//     the bottom edge is left where it falls once the sides ran out or
//     there were none to try (inside): the viewport is taken to scroll
//     that way, as a web page does.
//
// This is @primer/behaviors' getAnchoredPosition when sides, aligns and
// overhang are given (tools/primer/source/npm/behaviors/esm/
// anchored-position.mjs:112-176), and jm:ui's own flip-and-shift without
// them. key names the popup, so the side and alignment flatten chose can
// be read back the next frame (ui.placed).
Placement :: struct {
	set:         bool,
	key:         Area_Id,
	anchor:      Rect,
	size:        Size,
	side:        Side,
	align:       Side_Align,
	gap:         f32,
	nudge:       f32,
	inside:      bool,
	overhang:    bool,
	side_count:  u8,
	align_count: u8,
	sides:       [4]Side,
	aligns:      [2]Side_Align,
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

// Image draws an image, or src of it, into dst at alpha (255 opaque): an
// avatar faded in a stack. A literal must set alpha, as 0 draws nothing;
// image sets it.
Image :: struct {
	id:    Image_Id,
	dst:   Rect,
	src:   Rect, // in image pixels; zero rect means the whole image
	alpha: u8,
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

// Semantic describes a widget to assistive technology: ui.semantics on a
// widget's Placement emits one at widget_close, as Debug_Box is emitted;
// ui.overlay_semantics emits one for a layer at overlay_close. parent is
// the nearest enclosing widget or container that declared semantics of
// its own, 0 at the top (every overlay's), so a reader rebuilds the tree
// by id whatever lies between; rect is the widget's box in the recording
// space, zero for one with no box. A node with no label of its own may
// name another by semantics.labelled_by, whose label a reader speaks,
// a heading gives its place in the page's outline, or a tree item its
// depth in the tree, by semantics.level,
// and a control that keeps focus while it highlights a node (a combo
// box's option) names that node by semantics.active_descendant (AccessKit's
// active_descendant, aria-activedescendant on the web).
Semantic :: struct {
	id:        Area_Id,
	parent:    Area_Id,
	semantics: Semantics,
	rect:      Rect,
}

// Key_Interest asks that area be sent Key events matching key (None is
// any key) whose modifiers include mods and nothing outside mods and
// optional, whether or not it is focused: a dialog's Escape, an app's
// shortcuts. The focused area still gets every key first, as before.
//
// A topmost interest is one of a stack: of the topmost interests a key
// matches, only the last recorded (the top-most layer's) is sent it. It
// is how Escape closes the newest of several open popups and leaves the
// ones beneath open.
Key_Interest :: struct {
	area:     Area_Id,
	key:      Key,
	mods:     Mods, // required
	optional: Mods, // allowed as well
	topmost:  bool,
}

// Tag names an area for the dump and the probe: probe.find("Save").
// bounds is the tagged widget's box in the recording space, so a probe can
// find a widget that has no input area (a label, a message); the zero rect
// means unknown, and then only an area with the id is findable.
Tag :: struct {
	id:     Area_Id,
	name:   string,
	bounds: Rect,
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
	Cover_End,
	Semantic,
	Key_Interest,
	Push_Sticky,
	Focus_Scope,
	Focus_Scope_End,
	Push_Opacity,
	Pop_Opacity,
}

// Push_Opacity fades what is drawn until its Pop_Opacity, and the layers
// deferred from inside it, by alpha: 1 leaves it as it is, 0 hides it;
// nested pushes multiply. Each draw is faded on its own (the renderer's
// global alpha), not composited as a group and then faded as CSS opacity
// does, so where draws inside overlap the lower shows through the upper
// while alpha is below 1: right for a surface fading in, whose content
// sits on its own background, wrong for a stack of opaque cards. Input
// is not faded: a faded area still takes its events.
Push_Opacity :: struct {
	alpha: f32,
}

// Pop_Opacity ends the innermost Push_Opacity.
Pop_Opacity :: struct {}

// Focus_Scope opens a region of keyboard focus, ended by the next
// Focus_Scope_End: the areas recorded in between, and in every layer
// deferred from inside it, belong to it. Scopes nest. A trapping scope
// keeps keyboard focus inside itself while it is the last trap in the
// frame: Tab cycles its areas and a press cannot take focus out of it. A
// dialog is a trap; a newer one, a menu opened inside it, suspends it
// until it closes. A trap that still holds focus when it goes gives
// focus back to where it was when it came; taking focus in as it opens
// is the design system's choice (ui.focus_first). A roving scope (rove set) is one Tab stop however
// many areas it holds: the arrow keys of its axis move focus among its
// members, the areas whose nearest roving scope it is (see Rove). A
// plain scope only names a region, for ui.focus_first. See
// ui.focus_scope_open.
Focus_Scope :: struct {
	id:   Area_Id,
	trap: bool,
	rove: Rove,
	wrap: bool, // a roving scope's arrows run off one end onto the other
}

// Rove is the axis whose arrow keys move focus inside a roving focus
// scope, in frame order: Left and Up to the previous member, Right and
// Down to the next, Home and End to the first and last. Both takes all
// four arrows, as the WAI-ARIA radio group pattern does. A member that
// takes text, or holds a Key_Interest for the key, keeps the key instead.
Rove :: enum u8 {
	None,
	Horizontal,
	Vertical,
	Both,
}

// Focus_Scope_End closes the innermost Focus_Scope. entry names the
// member Tab enters a roving scope at when no member has held focus yet
// (the selected tab, the checked radio); 0 for the first.
Focus_Scope_End :: struct {
	entry: Area_Id,
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

// Font_Ref names the file a Font_Id draws from. weight is the value for
// the font's wght variation axis, 0 for the font's default: one variable
// font file, such as macOS's SFNS.ttf, serves several weights under
// several ids. A font without a wght axis draws at its one weight
// whatever weight says.
Font_Ref :: struct {
	id:     Font_Id,
	path:   string,
	weight: f32,
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
	free_images(o)
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

// sticky_push pins what follows, up to transform_pop, top below the top
// of the innermost clip, moving it down by no more than room (see
// Push_Sticky).
sticky_push :: proc(o: ^Scene, top, room: f32) {
	append(&o.ops, Push_Sticky{top, room})
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

image :: proc(o: ^Scene, id: Image_Id, dst: Rect, src: Rect = {}, alpha: u8 = 255) {
	append(&o.ops, Image{id, dst, src, alpha})
}

input_area :: proc(o: ^Scene, id: Area_Id, shape: Shape, kinds: Event_Kinds, cursor := Cursor.Default, yields := false) {
	append(&o.ops, Input_Area{id, shape, kinds, cursor, yields, false})
	if o.outline_areas {
		// Every area a user can reach, widget or painted row alike.
		stroke(o, shape, HIT_BOUNDS_COLOR, {width = 1})
	}
}

// opacity_push opens a Push_Opacity of alpha; opacity_pop closes it.
opacity_push :: proc(o: ^Scene, alpha: f32) {
	append(&o.ops, Push_Opacity{alpha})
}

opacity_pop :: proc(o: ^Scene) {
	append(&o.ops, Pop_Opacity{})
}

// focus_scope opens a Focus_Scope; focus_scope_end closes it.
focus_scope :: proc(o: ^Scene, id: Area_Id, trap := false, rove := Rove.None, wrap := false) {
	append(&o.ops, Focus_Scope{id, trap, rove, wrap})
}

focus_scope_end :: proc(o: ^Scene, entry: Area_Id = 0) {
	append(&o.ops, Focus_Scope_End{entry})
}

// outside_area records shape as part of id's inside for Outside presses
// (see Event_Kind.Outside): a press in any of id's outside areas is
// inside it. It is an observer, so it takes no hover, press or cursor
// from what lies under it: a popup records one over its surface and one
// over its anchor, so a press on the anchor toggles it rather than
// closing and reopening it.
outside_area :: proc(o: ^Scene, id: Area_Id, shape: Shape) {
	append(&o.ops, Input_Area{id = id, shape = shape, kinds = {.Outside}, observes = true})
}

// observer_area records an observer (Input_Area.observes) over shape:
// id is sent Enter and Leave as the pointer crosses it, and nothing else.
observer_area :: proc(o: ^Scene, id: Area_Id, shape: Shape) {
	append(&o.ops, Input_Area{id = id, shape = shape, kinds = {.Enter, .Leave}, observes = true})
}

// HIT_BOUNDS_COLOR outlines input areas under Debug_Flag.Bounds: cyan,
// against BOUNDS_COLOR's magenta for widget boxes.
HIT_BOUNDS_COLOR :: Color{0, 200, 255, 160}

tag :: proc(o: ^Scene, id: Area_Id, name: string, bounds: Rect = {}) {
	append(&o.ops, Tag{id, name, bounds})
}

// semantic records a Semantic for id under parent; ui.semantics and
// ui.part_semantics are the usual callers.
semantic :: proc(o: ^Scene, id, parent: Area_Id, s: Semantics, rect: Rect) {
	append(&o.ops, Semantic{id, parent, s, rect})
}

// key_interest records a Key_Interest for area; ui.key_interest is the
// usual caller.
key_interest :: proc(o: ^Scene, area: Area_Id, key: Key, mods: Mods = {}, optional: Mods = {}, topmost := false) {
	append(&o.ops, Key_Interest{area, key, mods, optional, topmost})
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
// popup placed by place; with cover, over all of container covers. See
// Defer and Placement.
defer_place :: proc(o: ^Scene, id: Macro_Id, place: Placement, cover := false, covers := Area_Id(0)) {
	p := place
	p.set = true
	append(&o.ops, Defer{id = id, cover = cover, covers = covers, place = p})
}

// defer_call runs macro id after the rest of the frame, on top; with
// cover, over all of container covers. See Defer.
defer_call :: proc(o: ^Scene, id: Macro_Id, root := false, cover := false, covers := Area_Id(0), top := false) {
	append(&o.ops, Defer{id = id, root = root, cover = cover, covers = covers, top = top})
}

// cover_end marks the end of container id, where the Defers covering it
// join the run order; see Cover_End.
cover_end :: proc(o: ^Scene, id: Area_Id) {
	append(&o.ops, Cover_End{id})
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

// add_font registers a font file at a weight (see Font_Ref) once; ids are
// stable for the life of Scene. The same file at two weights is two ids.
add_font :: proc(o: ^Scene, path: string, weight: f32 = 0) -> Font_Id {
	next := Font_Id(0)
	for f in o.fonts {
		if f.path == path && f.weight == weight {
			return f.id
		}
		next = max(next, f.id + 1)
	}
	append(&o.fonts, Font_Ref{next, path, weight})
	return next
}

// add_fonts registers each ref under its own id, even when refs share a
// path: an app that falls back to one file for several weights still
// draws with every id it asked for.
add_fonts :: proc(o: ^Scene, refs: []Font_Ref) {
	append(&o.fonts, ..refs)
}

// add_image registers the image at path under an id, or returns the id
// it already has. The path is copied: a caller's string may be a frame's
// or a shape's, gone before the renderer reads the file.
add_image :: proc(o: ^Scene, path: string) -> Image_Id {
	for f in o.images {
		if f.path == path {
			return f.id
		}
	}
	id := Image_Id(len(o.images))
	append(&o.images, Image_Ref{id, own_path(o, path)})
	return id
}

// own_path is path copied into the scene's allocator: the scene owns
// every image path it holds, whether add_image or decode put it there.
@(private)
own_path :: proc(o: ^Scene, path: string) -> string {
	kept := make([]byte, len(path), o.images.allocator)
	copy(kept, path)
	return string(kept)
}

// free_images forgets the scene's images and their paths.
@(private)
free_images :: proc(o: ^Scene) {
	for f in o.images {
		delete(f.path, o.images.allocator)
	}
	clear(&o.images)
}
