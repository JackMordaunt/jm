package ops

// Geometry shared by every stage.

Point :: [2]f32
Size :: [2]f32

Rect :: struct {
	x, y, w, h: f32,
}

// Color is straight (not premultiplied) RGBA, 8 bits per channel.
Color :: [4]u8

Round_Rect :: struct {
	rect:   Rect,
	radius: f32,
}

Ellipse :: struct {
	rect: Rect,
}

Path_Id :: distinct u32
Run_Id :: distinct u32
Macro_Id :: distinct u32
Image_Id :: distinct u32
Font_Id :: distinct u32
Area_Id :: distinct u64

Path_Ref :: struct {
	id: Path_Id,
}

// Shape is anything that can be filled, stroked, clipped to or hit-tested.
Shape :: union {
	Rect,
	Round_Rect,
	Ellipse,
	Path_Ref,
}

// Path is a flat verb/point encoding. Move and Line take one point, Cubic
// three, Close none. It lives in Scene.paths and is referenced by Path_Ref.
Path_Verb :: enum u8 {
	Move,
	Line,
	Cubic,
	Close,
}

// verbs and points must be built with make(..., gtx.allocator) — or with
// line, polyline or polygon, which do this for you — never a bare
// composite literal like []Point{a, b}. In an isolated repro against odin
// dev-2026-09 (a6650ce78), such a literal read back correctly inside the
// proc that wrote it and as garbage from its caller once that proc
// returned — consistent with that literal being backed by the proc's own
// stack frame rather than any allocator, though only this one case was
// checked. add_path stores the slices exactly as given and never copies
// them.
Path :: struct {
	verbs:  []Path_Verb,
	points: []Point,
}

Gradient_Stop :: struct {
	t:     f32,
	color: Color,
}

Linear_Gradient :: struct {
	p0, p1: Point,
	stops:  []Gradient_Stop,
}

Radial_Gradient :: struct {
	center: Point,
	radius: f32,
	stops:  []Gradient_Stop,
}

Image_Paint :: struct {
	image: Image_Id,
}

Paint :: union {
	Color,
	Linear_Gradient,
	Radial_Gradient,
	Image_Paint,
}

Line_Cap :: enum u8 {
	Butt,
	Round,
	Square,
}

Line_Join :: enum u8 {
	Miter,
	Round,
	Bevel,
}

Stroke_Style :: struct {
	width: f32,
	cap:   Line_Cap,
	join:  Line_Join,
}

// Events, as widgets see them. Positions are in the widget's own space: the
// router inverts the area's transform before delivery.

Event_Kind :: enum u8 {
	Press,
	Release,
	Move,
	Enter,
	Leave,
	Scroll,
	Key,
	Text,
	Focus,
	Blur,
	// Paste answers a clipboard read (ui.clipboard_read): delivered to the
	// areas that asked, never hit-tested, its bytes in text.
	Paste,
}

// Cursor is the pointer's look over an input area. An area that sets none
// shows Default: the topmost area under the pointer decides, so a button
// over selectable text shows the arrow, not the I-beam.
Cursor :: enum u8 {
	Default,
	Text,
	Pointer, // a link or other clickable
	Grab,
	Grabbing,
	Move,
	Resize_EW,
	Resize_NS,
	Resize_NESW,
	Resize_NWSE,
	Not_Allowed,
	Crosshair,
	Wait,
	Progress,
	None, // hidden
}

Event_Kinds :: bit_set[Event_Kind;u16]

// rect_contains reports whether p lies inside r (half-open on max edges).
rect_contains :: proc(r: Rect, p: Point) -> bool {
	return p.x >= r.x && p.y >= r.y && p.x < r.x + r.w && p.y < r.y + r.h
}

// rect_intersect returns the overlap of a and b, or a zero rect.
rect_intersect :: proc(a, b: Rect) -> Rect {
	x0 := max(a.x, b.x)
	y0 := max(a.y, b.y)
	x1 := min(a.x + a.w, b.x + b.w)
	y1 := min(a.y + a.h, b.y + b.h)
	if x1 <= x0 || y1 <= y0 {
		return {}
	}
	return {x0, y0, x1 - x0, y1 - y0}
}

// shape_bounds is the axis-aligned bounding rect of s in its own space.
shape_bounds :: proc(ops: ^Scene, s: Shape) -> Rect {
	switch v in s {
	case Rect:
		return v
	case Round_Rect:
		return v.rect
	case Ellipse:
		return v.rect
	case Path_Ref:
		p := ops.paths[v.id]
		if len(p.points) == 0 {
			return {}
		}
		lo, hi := p.points[0], p.points[0]
		for q in p.points[1:] {
			lo = {min(lo.x, q.x), min(lo.y, q.y)}
			hi = {max(hi.x, q.x), max(hi.y, q.y)}
		}
		return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
	}
	return {}
}
