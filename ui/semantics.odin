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
// right after opening it, and its children nest under it.

// semantics sets what widget p says about itself; widget_close emits it.
// The strings must live until the frame ends (frame_string).
semantics :: proc(gtx: ^Ctx, p: ^Placement, s: ops.Semantics) {
	p.semantics = s
	p.semantic = true
}

// container_semantics is semantics for the innermost open container: a
// column that is a list, an overlay that is a dialog or a menu.
container_semantics :: proc(gtx: ^Ctx, s: ops.Semantics) {
	l := gtx.layout
	if l == nil {
		return
	}
	if c := innermost(l); c != nil {
		c.place.semantics = s
		c.place.semantic = true
	}
}

// key_interest asks that area be sent every Key event matching key (None
// for any) with mods, and optionally optional, whether or not it holds
// focus: Escape for a dialog, a shortcut for an app. The focused area
// still receives every key first. Record it each frame, with the area.
key_interest :: proc(gtx: ^Ctx, area: ops.Area_Id, key: Key, mods: Mods = {}, optional: Mods = {}) {
	ops.key_interest(gtx.scene, area, key, mods, optional)
}

// semantics_report prints f's semantic tree, one node a line, children
// indented under their parent: the role, the label, the value and
// description when set, the states, `focused` on the area focus names,
// and the device rect, in document order: the order a reader is meant
// to take them in.
semantics_report :: proc(f: ^Frame, focus: ops.Area_Id = 0, allocator := context.allocator) -> string {
	if len(f.nodes) == 0 {
		return strings.clone("no semantics: nothing in the frame declares a role\n", allocator)
	}
	// Nodes close children-first; a node's parent is the next shallower
	// node after it on its layer.
	parent := make([]int, len(f.nodes), context.temp_allocator)
	for n, i in f.nodes {
		parent[i] = -1
		for j in i + 1 ..< len(f.nodes) {
			if f.nodes[j].layer == n.layer && f.nodes[j].depth < n.depth {
				parent[i] = j
				break
			}
		}
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
		for _ in 0 ..< indent {
			strings.write_string(b, "  ")
		}
		strings.write_string(b, role_name(n.semantics.role))
		strings.write_byte(b, ' ')
		strings.write_quoted_string(b, n.semantics.label)
		if n.semantics.value != "" {
			strings.write_string(b, " value ")
			strings.write_quoted_string(b, n.semantics.value)
		}
		if n.semantics.description != "" {
			strings.write_string(b, " desc ")
			strings.write_quoted_string(b, n.semantics.description)
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
	case .Busy:
		return "busy"
	case .Modal:
		return "modal"
	}
	return ""
}
