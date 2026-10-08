#+build linux, darwin, windows
package accesskit

import "core:strings"

// tree_update builds the Tree_Update an adapter takes from s: the window
// node with every node of no parent as its child, each node with the
// nodes naming it as its children, in snapshot order, labels by text or
// by labelled_by, and the actions an assistive technology may ask for.
// The update owns its nodes; the adapter frees it.
tree_update :: proc(s: ^Snapshot) -> ^Tree_Update {
	u := tree_update_with_capacity_and_focus(len(s.records) + 1, s.focus)
	tree_update_set_tree_info(u, tree_info_new(WINDOW))
	window := node_new(.Window)
	if t := text(s, s.title); t != nil {
		node_set_label(window, t)
	}
	// On the heap, not the temp allocator: the adapter's thread calls this
	// too, with whatever context it was given.
	known := make(map[Node_Id]bool, len(s.records))
	defer delete(known)
	for r in s.records {
		known[r.id] = true
	}
	for r in s.records {
		if r.parent == WINDOW || !known[r.parent] {
			node_push_child(window, r.id)
		}
	}
	tree_update_push_node(u, WINDOW, window)
	for r, i in s.records {
		n := node_new(r.role)
		if t := text(s, r.label); t != nil {
			node_set_label(n, t)
		} else if r.labelled_by != 0 && known[r.labelled_by] {
			by := r.labelled_by
			node_set_labelled_by(n, 1, &by)
		}
		if t := text(s, r.value); t != nil {
			node_set_value(n, t)
		}
		if t := text(s, r.description); t != nil {
			node_set_description(n, t)
		}
		node_set_bounds(n, r.rect)
		if r.has_toggled {
			node_set_toggled(n, r.toggled)
		}
		if r.selected {
			node_set_selected(n, true)
		}
		if r.expandable {
			node_set_expanded(n, r.expanded)
			// The one that applies, delivered as an Expand or Collapse event.
			node_add_action(n, .Collapse if r.expanded else .Expand)
		}
		if r.disabled {
			node_set_disabled(n)
		}
		if r.read_only {
			node_set_read_only(n)
		}
		if r.required {
			node_set_required(n)
		}
		if r.invalid {
			node_set_invalid(n, .True)
		}
		if r.busy {
			node_set_busy(n)
		}
		if r.modal {
			node_set_modal(n)
		}
		if r.hidden {
			node_set_hidden(n)
		}
		if r.live != .Off {
			node_set_live(n, r.live)
		}
		if r.level != 0 {
			node_set_level(n, uint(r.level))
		}
		set_table_place(n, r.table)
		if r.active != 0 && known[r.active] {
			node_set_active_descendant(n, r.active)
		}
		if r.current != .False {
			node_set_aria_current(n, r.current)
		}
		if r.focusable {
			node_add_action(n, .Focus)
		}
		if r.clickable {
			node_add_action(n, .Click)
		}
		for c in s.records[i + 1:] {
			if c.parent == r.id {
				node_push_child(n, c.id)
			}
		}
		for c in s.records[:i] {
			if c.parent == r.id {
				node_push_child(n, c.id)
			}
		}
		tree_update_push_node(u, r.id, n)
	}
	return u
}

// debug is tree_update_debug of the update built from s, as a string the
// caller frees: what a test or a log reads.
debug :: proc(s: ^Snapshot, allocator := context.allocator) -> string {
	u := tree_update(s)
	defer tree_update_free(u)
	c := tree_update_debug(u)
	defer string_free(c)
	return strings.clone(string(c), allocator)
}

// set_table_place sets n's table counts, its place and its sort, those
// that are set. AccessKit's indices are 0-based where ARIA's, and ours,
// are 1-based (accesskit/src/lib.rs, row_index: "aria-rowindex is
// one-based, while this property is zero-based"), and its counts are
// usize, with no unknown, so -1 sets none.
@(private)
set_table_place :: proc(n: ^Node, t: Table_Place) {
	if t.row_count > 0 {
		node_set_row_count(n, uint(t.row_count))
	}
	if t.col_count > 0 {
		node_set_column_count(n, uint(t.col_count))
	}
	if t.row_index > 0 {
		node_set_row_index(n, uint(t.row_index - 1))
	}
	if t.col_index > 0 {
		node_set_column_index(n, uint(t.col_index - 1))
	}
	if t.has_sort {
		node_set_sort_direction(n, t.sort)
	}
}
