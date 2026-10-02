package accesskit

import "core:mem"
import "core:slice"
import "jm:ui"
import "jm:ui/ops"

// A Snapshot is a ui.Frame's semantic nodes as plain data the adapter can
// be fed from: everything AccessKit reads, with no pointer into the frame
// and the strings copied, so the frame thread takes one and the adapter's
// own thread builds a Tree_Update from it (the activation handler runs
// there) while the next frame is laid out. Two snapshots compare as
// bytes, which is how the bridge learns that nothing changed.

// Node_Id is what names a node across updates; ui.Area_Id is used as is,
// with 0 (never a widget's) as the window.
Node_Id :: u64

// Rect is a box by its edges, in the window's coordinates: accesskit_rect
// (accesskit.h 0.23.1, line 941), x0 and y0 the left and top edges.
Rect :: struct {
	x0, y0, x1, y1: f64,
}

// Snapshot_Node is one node of a snapshot (Node is the library's own, in
// api.odin). Its strings live in Snapshot.text as NUL-terminated runs, by
// offset, so each is a cstring where it lies.
Snapshot_Node :: struct {
	id, parent:  Node_Id,
	role:        Role,
	label:       i32, // offsets into Snapshot.text; -1 for none
	value:       i32,
	description: i32,
	labelled_by: Node_Id,
	rect:        Rect,
	toggled:     Toggled,
	has_toggled: bool,
	selected:    bool,
	expanded:    bool,
	expandable:  bool,
	disabled:    bool,
	read_only:   bool,
	required:    bool,
	invalid:     bool,
	busy:        bool,
	modal:       bool,
	hidden:      bool, // its box lies wholly outside its clip: scrolled away
	live:        Live,
	level:       u8, // headings: 1
	focusable:   bool, // an input area of the id wants Key or Focus
	clickable:   bool, // one wants Press
}

Snapshot :: struct {
	records: [dynamic]Snapshot_Node,
	text:    [dynamic]u8,
	focus:   Node_Id, // the focused area when it is a node, else the window
	title:   i32, // the window's label, in text
}

// WINDOW is the root node: ui.Area_Id 0 is never a widget's.
WINDOW :: Node_Id(0)

snapshot_init :: proc(s: ^Snapshot, allocator := context.allocator) {
	s.records = make([dynamic]Snapshot_Node, allocator)
	s.text = make([dynamic]u8, allocator)
}

snapshot_destroy :: proc(s: ^Snapshot) {
	delete(s.records)
	delete(s.text)
	s^ = {}
}

// snapshot_take fills s from f: one record per semantic node, in f's
// order, the window titled title, focus the router's focused area when a
// node has it, rects scaled by scale: 1 / the display density, since f
// is in device pixels and the window bounds the bridge gives the adapter
// are SDL's window size, in points. It reuses s's capacity, so a steady
// frame allocates nothing.
snapshot_take :: proc(s: ^Snapshot, f: ^ui.Frame, focus: ops.Area_Id, title: string, scale: f32 = 1) {
	clear(&s.records)
	clear(&s.text)
	s.title = put_text(s, title)
	s.focus = WINDOW
	for n in f.nodes {
		r := Snapshot_Node {
			id          = Node_Id(n.id),
			parent      = Node_Id(n.parent),
			role        = role_of(n.semantics.role),
			label       = put_text(s, n.semantics.label),
			value       = put_text(s, n.semantics.value),
			description = put_text(s, n.semantics.description),
			labelled_by = Node_Id(n.semantics.labelled_by),
			rect        = {f64(n.rect.x * scale), f64(n.rect.y * scale), f64((n.rect.x + n.rect.w) * scale), f64((n.rect.y + n.rect.h) * scale)},
			selected    = .Selected in n.semantics.states,
			expandable  = .Expandable in n.semantics.states || .Expanded in n.semantics.states,
			expanded    = .Expanded in n.semantics.states,
			disabled    = .Disabled in n.semantics.states,
			read_only   = .Readonly in n.semantics.states,
			required    = .Required in n.semantics.states,
			invalid     = .Invalid in n.semantics.states,
			busy        = .Busy in n.semantics.states,
			modal       = .Modal in n.semantics.states,
		}
		if .Mixed in n.semantics.states {
			r.toggled, r.has_toggled = .Mixed, true
		} else if n.semantics.role == .Checkbox || n.semantics.role == .Radio || n.semantics.role == .Switch {
			r.toggled, r.has_toggled = .True if .Checked in n.semantics.states else .False, true
		}
		#partial switch n.semantics.role {
		case .Heading:
			r.level = max(n.semantics.level, 1)
		case .Status:
			r.live = .Polite
		case .Alert:
			r.live = .Assertive
		}
		if n.rect.w > 0 && n.rect.h > 0 {
			seen := ops.rect_intersect(ui.clip_chain_bounds(f, n.clip), n.rect)
			r.hidden = seen.w <= 0 || seen.h <= 0
		} else if n.rect != {} {
			// A box with one side collapsed is a closed drawer or sheet: in
			// the frame, with nothing to see.
			r.hidden = true
		}
		if n.semantics.role == .Text || n.semantics.role == .Heading {
			// Static text is read from the node's value: accesskit-c's
			// examples/sdl/hello_world.c announces through a Label whose
			// value is the text, and a live dump of the kitchen read a
			// Label with only a label as nameless. A heading is named by
			// its label; both get the text.
			r.value = r.label
		}
		if interactive(n.semantics.role) {
			// Only a control takes the reader's focus and clicks: selectable
			// text wants keys for copying, but a reader stepping through
			// every label would be no use.
			for h in f.hits {
				if h.area != n.id {
					continue
				}
				r.focusable |= .Key in h.kinds || .Focus in h.kinds
				r.clickable |= .Press in h.kinds
			}
		}
		if ops.Area_Id(r.id) == focus && focus != 0 {
			s.focus = r.id
		}
		append(&s.records, r)
	}
}

// snapshot_equal reports whether a and b describe the same tree: the
// same records and the same strings. Focus is compared apart, since a
// focus that moved alone is a smaller update.
snapshot_equal :: proc(a, b: ^Snapshot) -> bool {
	if len(a.records) != len(b.records) || a.title != b.title {
		return false
	}
	return slice.equal(a.text[:], b.text[:]) && mem.compare(slice.to_bytes(a.records[:]), slice.to_bytes(b.records[:])) == 0
}

// text is the string at offset off in s, as a cstring; nil for -1.
text :: proc(s: ^Snapshot, off: i32) -> cstring {
	if off < 0 {
		return nil
	}
	return cstring(raw_data(s.text[off:]))
}

// put_text appends str to s.text, NUL-terminated, and returns its
// offset; -1 for an empty string.
@(private)
put_text :: proc(s: ^Snapshot, str: string) -> i32 {
	if str == "" {
		return -1
	}
	off := i32(len(s.text))
	append(&s.text, str)
	append(&s.text, 0)
	return off
}

// interactive reports whether r is a control the reader may focus or
// click, rather than content it reads past.
interactive :: proc(r: ops.Role) -> bool {
	#partial switch r {
	case .Button, .Checkbox, .Radio, .Switch, .Slider, .Text_Field, .Combo_Box, .Tab, .List_Item, .Menu_Item, .Link, .Option, .Grid_Cell, .Row, .Cell:
		return true
	}
	return false
}

// role_of is the AccessKit role for an ops.Role: the same name where
// both have it, else the nearest. Presentation is a generic container,
// which readers pass over as they do our report.
role_of :: proc(r: ops.Role) -> Role {
	switch r {
	case .Unknown:
		return .Unknown
	case .Group:
		return .Group
	case .Text:
		return .Label
	case .Heading:
		return .Heading
	case .Link:
		return .Link
	case .Image:
		return .Image
	case .Button:
		return .Button
	case .Checkbox:
		return .Check_Box
	case .Radio:
		return .Radio_Button
	case .Switch:
		return .Switch
	case .Slider:
		return .Slider
	case .Text_Field:
		return .Text_Input
	case .Combo_Box:
		return .Combo_Box
	case .Tab_List:
		return .Tab_List
	case .Tab:
		return .Tab
	case .List:
		return .List
	case .List_Item:
		return .List_Item
	case .Menu:
		return .Menu
	case .Menu_Item:
		return .Menu_Item
	case .Toolbar:
		return .Toolbar
	case .Navigation:
		return .Navigation
	case .Dialog:
		return .Dialog
	case .Tooltip:
		return .Tooltip
	case .Progress:
		return .Progress_Indicator
	case .Status:
		return .Status
	case .Table:
		return .Table
	case .Row:
		return .Row
	case .Cell:
		return .Cell
	case .Separator:
		return .Splitter
	case .Radio_Group:
		return .Radio_Group
	case .Alert:
		return .Alert
	case .Grid:
		return .Grid
	case .Grid_Cell:
		return .Grid_Cell
	case .List_Box:
		return .List_Box
	case .Option:
		return .List_Box_Option
	case .Region:
		return .Region
	case .Presentation:
		return .Generic_Container
	}
	return .Unknown
}
