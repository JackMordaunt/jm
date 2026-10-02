package ui

import "core:fmt"
import "jm:ui/ops"
import "core:strings"

// Semantics describe widgets to assistive technology, and to a test or an
// agent reading the screen the way a screen reader would. A widget says
// what it is during its bracket, and widget_close records it with the
// widget's box and depth; flatten places it on the Frame as a
// Semantic_Node, and semantics_report prints the tree. Nothing is
// retained between frames: the tree is part of the frame, like the hits,
// as Gio v0.10.2 rebuilds its semantic tree from each frame's ops
// (io/semantic, io/input/pointer.go AppendSemantics).
//
//	p := ui.widget_open(gtx, key, loc)
//	...
//	ui.semantics(gtx, &p, {role = .Checkbox, label = label, states = {.Checked} if checked^ else {}})
//	return ui.widget_close(gtx, &p, dims)
//
// A design system's controls declare their role; base.label declares
// Text. A container declares one for itself with container_semantics,
// right after opening it, and its children nest under it: a node's
// parent is the nearest enclosing widget or container that declared
// semantics, whatever undeclared containers lie between. A part of a
// widget that is not a widget of its own (a tab, a calendar's day) is
// declared with part_semantics and nests under the widget.

// semantics sets what widget p says about itself; widget_close emits it.
// The strings must live until the frame ends (frame_string). gtx is
// taken for symmetry with the other declarations.
semantics :: proc(gtx: ^Ctx, p: ^Placement, s: ops.Semantics) {
	p.semantics = s
	p.semantic = true
}

// part_semantics describes a part of widget p that is not a widget of
// its own: id is the part's area (one mixed from p.id), rect its box in
// p's space. It nests under p, whether p declares its own semantics
// before or after it or never (then p is an unlabelled group of its
// parts), or under an earlier part of p when under names one: a toast's
// dismiss button under the toast. Call it inside p's bracket, under p's
// own transform.
part_semantics :: proc(gtx: ^Ctx, p: ^Placement, id: ops.Area_Id, rect: ops.Rect, s: ops.Semantics, under: ops.Area_Id = 0) {
	p.parts = true
	ops.semantic(gtx.scene, id, under if under != 0 else p.id, s, rect)
}

// container_semantics is semantics for an open container: a column that
// is a list, a dialog's column in its overlay. index is the container's
// handle index (ui.Flex.index and the like), so a title drawn deeper can
// still label the container it names; -1 is the innermost open one.
container_semantics :: proc(gtx: ^Ctx, s: ops.Semantics, index := -1) {
	l := gtx.layout
	if l == nil {
		return
	}
	c := innermost(l) if index < 0 else container_at(l, index)
	if c != nil {
		c.place.semantics = s
		c.place.semantic = true
	}
}

// overlay_semantics describes an open overlay or popup as a node of its
// own, a root of the layer: a tooltip, a list box, a toaster. It returns
// the node's id, for the parts drawn straight into the overlay to nest
// under with child_semantics. The node is emitted at overlay_close, with
// a popup's size as its box, or rect for a plain overlay, which has no
// size of its own. id names the node when the overlay already has an
// area (a focusable surface, whose focus should show on the node); 0
// claims a fresh one at key and loc.
overlay_semantics :: proc(gtx: ^Ctx, o: ^Overlay, s: ops.Semantics, key: u64 = 0, id: ops.Area_Id = 0, rect: ops.Rect = {}, loc := #caller_location) -> ops.Area_Id {
	o.node = id if id != 0 else claim_id(gtx, key, loc)
	o.semantics = s
	o.node_rect = rect
	return o.node
}

// child_semantics describes id, a part with no widget of its own, as a
// child of the node parent: a part of an overlay (overlay_semantics), or
// a part under a part. rect is in the space current at the call.
// part_semantics is this with the widget as parent.
child_semantics :: proc(gtx: ^Ctx, parent, id: ops.Area_Id, rect: ops.Rect, s: ops.Semantics) {
	ops.semantic(gtx.scene, id, parent, s, rect)
}

// semantic_parent is the id of the nearest container at or above stack
// index parent that declared semantics; when none has, the node a
// recording was opened under (record_open), else 0.
@(private)
semantic_parent :: proc(l: ^Layout, parent: int) -> ops.Area_Id {
	if l == nil {
		return 0
	}
	for i := min(parent, depth(l) - 1); i >= 0; i -= 1 {
		if c := container_at(l, i); c.place.semantic {
			return c.place.id
		}
	}
	return l.root_semantic
}

// key_interest asks that area be sent every Key event matching key (None
// for any) with mods, and optionally optional, whether or not it holds
// focus: Escape for a dialog, a shortcut for an app. The focused area
// still receives every key first. Record it each frame, with the area.
key_interest :: proc(gtx: ^Ctx, area: ops.Area_Id, key: Key, mods: Mods = {}, optional: Mods = {}, topmost := false) {
	ops.key_interest(gtx.scene, area, key, mods, optional, topmost)
}

// semantics_report prints f's semantic tree, one node a line, children
// indented under their parent: the role, the label (the labelled_by
// node's when the node has none), the value and description when set,
// a heading's level when set, the states, `focused` on the area focus names, and the device rect, in
// document order: the order a reader is meant to take them in. A node
// whose parent is in no frame node is a root; a Presentation node is not
// printed, its children take its place.
semantics_report :: proc(f: ^Frame, focus: ops.Area_Id = 0, allocator := context.allocator) -> string {
	if len(f.nodes) == 0 {
		return strings.clone("no semantics: nothing in the frame declares a role\n", allocator)
	}
	index := make(map[ops.Area_Id]int, context.temp_allocator)
	for n, i in f.nodes {
		index[n.id] = i
	}
	parent := make([]int, len(f.nodes), context.temp_allocator)
	for n, i in f.nodes {
		p, ok := index[n.parent]
		parent[i] = p if ok && n.parent != 0 && p != i else -1
	}
	b := strings.builder_make(allocator)
	write_semantic_children(&b, f, parent, -1, 0, focus)
	return strings.to_string(b)
}

@(private = "file")
write_semantic_children :: proc(b: ^strings.Builder, f: ^Frame, parent: []int, of, indent: int, focus: ops.Area_Id) {
	for n, i in f.nodes {
		if parent[i] != of {
			continue
		}
		if n.semantics.role == .Presentation {
			write_semantic_children(b, f, parent, i, indent, focus)
			continue
		}
		for _ in 0 ..< indent {
			strings.write_string(b, "  ")
		}
		strings.write_string(b, role_name(n.semantics.role))
		strings.write_byte(b, ' ')
		strings.write_quoted_string(b, semantic_label(f, n.semantics))
		if n.semantics.value != "" {
			strings.write_string(b, " value ")
			strings.write_quoted_string(b, n.semantics.value)
		}
		if n.semantics.description != "" {
			strings.write_string(b, " desc ")
			strings.write_quoted_string(b, n.semantics.description)
		}
		if n.semantics.level != 0 {
			fmt.sbprintf(b, " level %d", n.semantics.level)
		}
		for st in ops.State {
			if st in n.semantics.states {
				fmt.sbprintf(b, " %s", state_name(st))
			}
		}
		if focus != 0 && n.id == focus {
			strings.write_string(b, " focused")
		}
		fmt.sbprintf(b, " at %.0f,%.0f %.0fx%.0f\n", n.rect.x, n.rect.y, n.rect.w, n.rect.h)
		write_semantic_children(b, f, parent, i, indent + 1, focus)
	}
}

// semantic_label is s's own label, or the label of the node labelled_by
// names when s has none and the frame has that node.
semantic_label :: proc(f: ^Frame, s: ops.Semantics) -> string {
	if s.label != "" || s.labelled_by == 0 {
		return s.label
	}
	for n in f.nodes {
		if n.id == s.labelled_by {
			return n.semantics.label
		}
	}
	return ""
}

// role_name is r as a reader says it: "text field", "list item".
role_name :: proc(r: ops.Role) -> string {
	switch r {
	case .Unknown:
		return "unknown"
	case .Group:
		return "group"
	case .Text:
		return "text"
	case .Heading:
		return "heading"
	case .Link:
		return "link"
	case .Image:
		return "image"
	case .Button:
		return "button"
	case .Checkbox:
		return "checkbox"
	case .Radio:
		return "radio"
	case .Switch:
		return "switch"
	case .Slider:
		return "slider"
	case .Text_Field:
		return "text field"
	case .Combo_Box:
		return "combo box"
	case .Tab_List:
		return "tab list"
	case .Tab:
		return "tab"
	case .List:
		return "list"
	case .List_Item:
		return "list item"
	case .Menu:
		return "menu"
	case .Menu_Item:
		return "menu item"
	case .Toolbar:
		return "toolbar"
	case .Navigation:
		return "navigation"
	case .Dialog:
		return "dialog"
	case .Tooltip:
		return "tooltip"
	case .Progress:
		return "progress"
	case .Status:
		return "status"
	case .Table:
		return "table"
	case .Row:
		return "row"
	case .Cell:
		return "cell"
	case .Separator:
		return "separator"
	case .Radio_Group:
		return "radio group"
	case .Alert:
		return "alert"
	case .Grid:
		return "grid"
	case .Grid_Cell:
		return "grid cell"
	case .List_Box:
		return "list box"
	case .Option:
		return "option"
	case .Region:
		return "region"
	case .Presentation:
		return "presentation"
	}
	return "unknown"
}

// state_name is s in lower case, as the report prints it.
state_name :: proc(s: ops.State) -> string {
	switch s {
	case .Checked:
		return "checked"
	case .Mixed:
		return "mixed"
	case .Selected:
		return "selected"
	case .Expandable:
		return "expandable"
	case .Expanded:
		return "expanded"
	case .Disabled:
		return "disabled"
	case .Readonly:
		return "readonly"
	case .Required:
		return "required"
	case .Invalid:
		return "invalid"
	case .Busy:
		return "busy"
	case .Modal:
		return "modal"
	}
	return ""
}
