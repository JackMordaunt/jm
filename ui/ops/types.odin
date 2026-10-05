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
	rule:   Fill_Rule,
}

// Fill_Rule is what a fill of a path counts as inside: Non_Zero where its
// subpaths' windings around a point do not cancel, Even_Odd where an odd
// number of subpaths enclose it, so a hole cuts through whichever way it
// winds (SVG's fill-rule). A stroke ignores it.
Fill_Rule :: enum u8 {
	Non_Zero,
	Even_Odd,
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
	// Cancel tells a pressed area its press was taken from it: a drag that
	// started on yielding text over it went to the text instead. It clears
	// the press without a click, and is delivered whatever kinds the area
	// asked for, since a press it never hears the end of would stick.
	Cancel,
	// Outside tells an area a press landed outside it: what a popup reads
	// to close. On each press the areas that ask for it are walked from the
	// top-most down; each that does not contain the press is sent Outside,
	// with the press's button, and the walk stops at the first that does,
	// so a press inside a parent popup closes only the children above it.
	// The press itself is routed as usual. See ops.outside_area.
	Outside,
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

// Keys and modifiers, as a platform reports them and as an area asks for
// them (Key_Interest). They live here rather than in ui because ops names
// them in its own records; ui aliases them.
Button :: enum u8 {
	Left,
	Right,
	Middle,
}

Key :: enum u8 {
	None, // in a Key_Interest: any key
	Enter,
	Escape,
	Tab,
	Backspace,
	Delete,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Page_Up,
	Page_Down,
	Space,
	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	N0, N1, N2, N3, N4, N5, N6, N7, N8, N9,
	F11, // ui.DEBUG_TOGGLE_KEY: the frame loops take it before routing
	// The mouse's back and forward buttons arrive as keys, as a browser
	// takes them: an app reads them app-wide with ui.key_interest, like
	// Alt with Left and Right, which mean the same.
	Browser_Back,
	Browser_Forward,
}

Mod :: enum u8 {
	Shift,
	Ctrl,
	Alt,
	Super,
}

Mods :: bit_set[Mod;u8]

// Role is what a widget is to assistive technology, a screen reader or a
// test reading the screen: the vocabulary of a Semantic op, named after
// the WAI-ARIA 1.2 roles (button, checkbox, listitem, tablist, dialog,
// status, …) so a platform bridge maps each by name.
Role :: enum u8 {
	Unknown,
	Group, // a region that only holds others: a card, a toolbar's row
	Text, // static text
	Heading,
	Link,
	Image,
	Button,
	Checkbox,
	Radio,
	Switch,
	Slider,
	Text_Field,
	Combo_Box,
	Tab_List,
	Tab,
	List,
	List_Item,
	Menu,
	Menu_Item,
	Toolbar,
	Navigation,
	Dialog,
	Tooltip,
	Progress,
	Status, // a live region: a snackbar, a toast
	Table,
	Row,
	Cell,
	Separator, // a divider: read as a break, not as content
	Radio_Group,
	Alert, // a message a reader announces at once: a validation error
	Grid, // a two-dimensional pick: a calendar's month
	Grid_Cell,
	List_Box, // a list to pick from: a combo box's options
	Option,
	Region, // a landmark section a reader can jump to by its label: a page-level message
	Presentation, // decoration: a reader skips the node and reads its children
	Menu_Item_Checkbox, // a menu item that toggles: Checked says whether it is on
	Menu_Item_Radio, // one of a menu's mutually exclusive choices: Checked marks the chosen
	Tree, // a hierarchy of items that expand and collapse: a file tree
	Tree_Item, // one item of a tree; its level is its depth, 1 at the top
	Tab_Panel, // the content a tab shows
	Column_Header, // a grid's or table's column heading: a calendar's weekday over its days
}

// State is one of the states a Semantic op may carry.
State :: enum u8 {
	Checked,
	Mixed, // a checkbox neither checked nor clear
	Selected,
	Expandable,
	Expanded,
	Disabled,
	Readonly,
	Required,
	Invalid, // its value fails validation: a field in error (aria-invalid)
	Busy,
	Modal,
	Current, // the current item of a set (aria-current="true"): a tree's open file
	Current_Page, // the link to the page being shown (aria-current="page")
	Current_Date, // the date that is today in a calendar (aria-current="date")
}

States :: bit_set[State;u16]

// Semantics is what a widget says about itself: its role, the label a
// reader speaks for it, or the widget whose label names it (a slider
// after its caption) when it has none of its own, its value when it has
// one (a slider's, a field's text), a longer description (a tooltip's
// text), its states, a heading's level in the page's outline or a tree
// item's depth in its tree, and the descendant it points a reader at
// while it keeps focus itself.
Semantics :: struct {
	role:              Role,
	label:             string,
	labelled_by:       Area_Id, // another node, whose label is read when label is ""
	value:             string,
	description:       string,
	states:            States,
	level:             u8, // a heading's outline level, 1 as h1 through 6 as h6, or a tree item's depth, 1 at the top; 0 is none, which a heading reads as 1
	active_descendant: Area_Id, // the node a focused control points a reader at while it keeps focus (aria-activedescendant): a combo box's highlighted option; 0 is none
}
