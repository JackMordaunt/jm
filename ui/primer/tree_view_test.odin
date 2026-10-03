package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of tree_view, driven through ui.Probe by tags.

@(private = "file")
Tree_Model :: struct {
	lib, src, docs, misc:      [1]Tree_Item,
	roots:                     [6]Tree_Item,
	src_kids:                  [3]Tree_Item,
	lib_kids, docs_kids:       [1]Tree_Item,
	tools_kids:                [1]Tree_Item,
	lazy_kids:                 [2]Tree_Item,
	lazy:                      Tree_Sub_Tree,
	lazy_count:                int,
	lazy_children:             bool,
	copy_actions, two_actions: [2]Tree_Action,
	last:                      Tree_Event,
	events:                    int,
	flat, wrap:                bool,
	src_open:                  bool,
}

@(private = "file")
tree_model :: proc(m: ^Tree_Model) {
	m.lib_kids = {{id = "src/lib/a.odin", label = "a.odin", leading = .File}}
	m.src_kids = {
		{id = "src/lib", label = "lib", directory = true, children = m.lib_kids[:]},
		{id = "src/main.odin", label = "main.odin", leading = .File, current = true},
		{id = "src/util.odin", label = "util.odin", leading = .File},
	}
	m.tools_kids = {{id = "tools/build.sh", label = "build.sh"}}
	m.docs_kids = {{id = "docs/readme.md", label = "readme.md", leading = .File}}
	m.lazy_kids = {{id = "lazy/one", label = "one"}, {id = "lazy/two", label = "two"}}
	m.copy_actions = {{label = "Copy path", icon = .Copy}, {}}
	m.two_actions = {{label = "Rename", icon = .Pencil}, {label = "Delete", icon = .Trash}}
	m.src_open = true
}

@(private = "file")
tree_items :: proc(m: ^Tree_Model) -> []Tree_Item {
	m.roots = {
		{id = "src", label = "src", directory = true, children = m.src_kids[:], expanded = &m.src_open},
		{id = "docs", label = "docs", directory = true, children = m.docs_kids[:]},
		{id = "lazy", label = "lazy", sub_tree = m.lazy, count = m.lazy_count, children = m.lazy_children ? m.lazy_kids[:] : nil, error = "Could not load lazy"},
		{id = "empty", label = "empty", sub_tree = .Known},
		{id = "notes.txt", label = "notes.txt", leading = .File, selectable = true, actions = m.copy_actions[:1]},
		{id = "tools", label = "tools", selectable = true, children = m.tools_kids[:], actions = m.two_actions[:]},
	}
	return m.roots[:]
}

@(private = "file")
tree_view_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Tree_Model)(user)
	pad := ui.inset_open(gtx, {16, 0, 0, 0})
	defer ui.close(&pad)
	col := ui.column_open(gtx, align = .Start)
	defer ui.close(&col)
	sized := ui.sized_open(gtx, {max = {300, ui.INF}})
	defer ui.close(&sized)
	ev := tree_view(gtx, tree_items(m), "Files", flat = m.flat, truncate = !m.wrap, page_height = 3 * TREE_ROW)
	if ev.kind != .None {
		m.last = ev
		m.events += 1
	}
}

@(private = "file")
tree_probe :: proc(p: ^ui.Probe, m: ^Tree_Model) {
	tree_model(m)
	ui.probe_init(p, tree_view_ui, m, {600, 600}, allocator = context.temp_allocator)
}

// focused_label is the label of the node focus is on, from the report.
@(private = "file")
focused_label :: proc(p: ^ui.Probe) -> string {
	said := ui.probe_semantics(p, context.temp_allocator)
	for line in strings.split_lines(said, context.temp_allocator) {
		if strings.contains(line, " focused") {
			q := strings.index_byte(line, '"')
			e := strings.index_byte(line[q + 1:], '"')
			return line[q + 1:][:e]
		}
	}
	return ""
}

// label_x is where the default-coloured text in row starts, in the
// window, -1 when none is drawn there.
@(private = "file")
label_x :: proc(p: ^ui.Probe, row: ops.Rect) -> f32 {
	for d in ui.probe_current(p).draws {
		if g, ok := d.cmd.(ops.Glyphs); ok && g.color == color(.Fg_Color_Default) {
			at := ops.apply(d.transform, g.origin)
			if at.y > row.y && at.y < row.y + row.h {
				return at.x
			}
		}
	}
	return -1
}

@(test)
test_tree_rows_indent_8px_a_level_and_stand_32px_tall :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	src := ui.probe_bounds(&p, "src")
	main := ui.probe_bounds(&p, "main.odin")
	testing.expect_value(t, src, ops.Rect{16, 0, 300, TREE_ROW})
	testing.expect_value(t, main.y, 2 * TREE_ROW) // after lib
	testing.expect_value(t, main.h, TREE_ROW)
	testing.expect(t, !ui.probe_tagged(&p, "a.odin")) // lib starts closed
	testing.expect(t, !ui.probe_tagged(&p, "readme.md"))
	testing.expect(t, ui.probe_tagged(&p, "No items found") == false) // empty is closed
	// The label starts after the 8px indent, the 16px toggle, 8px of
	// padding, the 16px icon and the 8px gap.
	testing.expect_value(t, label_x(&p, main), main.x + 8 + TREE_TOGGLE + 8 + BUTTON_ICON + tok.STACK_GAP_CONDENSED)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "tree item \"main.odin\" level 2 current"), "%s", said)
	testing.expectf(t, strings.contains(said, "tree item \"src\" level 1 expandable expanded"), "%s", said)
	testing.expectf(t, strings.contains(said, "tree item \"empty\" level 1 at"), "a closed empty item reports no expanded state: %s", said)
}

@(test)
test_tree_click_toggles_and_keeps_state_by_id :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "lib"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "a.odin"))
	testing.expect_value(t, m.last, Tree_Event{.Expand, "src/lib", 0})
	// src is controlled: a click writes the caller's bool.
	testing.expect(t, ui.probe_click(&p, "src"))
	ui.probe_frame(&p)
	testing.expect(t, !m.src_open)
	testing.expect(t, !ui.probe_tagged(&p, "lib"))
	m.src_open = true
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "a.odin")) // lib reopened as it was, though unmounted
	ui.probe_click(&p, "empty")
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "No items found"))
}

@(test)
test_tree_keyboard_walks_visible_rows :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "main.odin") // enters at the current item
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "util.odin")
	ui.probe_key(&p, .Left) // a leaf: to the parent
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "src")
	ui.probe_key(&p, .Left) // open: closes, focus stays
	ui.probe_frame(&p)
	testing.expect(t, !m.src_open)
	testing.expect_value(t, focused_label(&p), "src")
	ui.probe_key(&p, .Right) // closed: opens
	ui.probe_frame(&p)
	testing.expect(t, m.src_open)
	ui.probe_key(&p, .Right) // open: into the first child
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "lib")
	ui.probe_key(&p, .Backspace)
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "src")
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "tools")
	ui.probe_key(&p, .Down) // nothing wraps
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "tools")
	ui.probe_key(&p, .Page_Up) // three rows a page
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "lazy")
	ui.probe_key(&p, .Home)
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "src")
	ui.probe_key(&p, .Right, {.Alt}) // ignored with Alt
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "src")
	ui.probe_key(&p, .Tab) // one tab stop, and the page's only one: Tab comes back to it
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "src")
}

@(test)
test_tree_typeahead_matches_prefixes_and_cycles :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	ui.probe_type(&p, "t")
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "tools")
	ui.probe_advance(&p, 1, 0.5) // the search clears
	ui.probe_type(&p, "N")
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "notes.txt") // wraps, ignores case
	ui.probe_type(&p, "o")
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "notes.txt") // "no" stays on it
	ui.probe_advance(&p, 1, 0.5)
	ui.probe_type(&p, "l") // from notes.txt, wrapping: lib
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "lib")
	ui.probe_advance(&p, 1, 0.5)
	ui.probe_type(&p, "l") // a letter again moves on to the next match
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "lazy")
	ui.probe_advance(&p, 1, 0.5)
	ui.probe_type(&p, " ")
	ui.probe_frame(&p)
	testing.expect_value(t, focused_label(&p), "lazy") // a space is no search
}

@(test)
test_tree_selectable_items_select_and_toggle_by_chevron :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "tools"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.last, Tree_Event{.Select, "tools", 0})
	testing.expect(t, !ui.probe_tagged(&p, "build.sh")) // selecting does not open it
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect_value(t, m.events, 2)
	testing.expect_value(t, m.last.kind, Tree_Event_Kind.Select)
	// The chevron's 16px column is its own target, and toggles.
	b := ui.probe_bounds(&p, "tools")
	ui.probe_move(&p, b.x + TREE_TOGGLE / 2, b.y + b.h / 2)
	ui.router_push(&p.router, {kind = .Press, pos = {b.x + TREE_TOGGLE / 2, b.y + b.h / 2}, button = .Left, clicks = 1})
	ui.router_push(&p.router, {kind = .Release, pos = {b.x + TREE_TOGGLE / 2, b.y + b.h / 2}, button = .Left})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, m.last, Tree_Event{.Expand, "tools", 0})
	testing.expect(t, ui.probe_tagged(&p, "build.sh"))
}

@(test)
test_tree_secondary_actions_run_from_the_shortcut :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	shortcut := PLATFORM == .Apple ? ui.Mods{.Shift, .Super} : ui.Mods{.Shift, .Ctrl}
	testing.expect(t, ui.probe_click(&p, "Copy path")) // the action's own button
	testing.expect_value(t, m.last, Tree_Event{.Action, "notes.txt", 0})
	ui.probe_click(&p, "notes.txt")
	ui.probe_frame(&p)
	m.last = {}
	ui.probe_key(&p, .U, shortcut)
	ui.probe_frame(&p)
	testing.expect_value(t, m.last, Tree_Event{.Action, "notes.txt", 0})
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	ui.probe_key(&p, .U, shortcut) // two actions: the dialog lists them
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Supplemental actions"))
	// The row's own buttons share the labels; walk the dialog's instead.
	ui.probe_frame(&p)
	for i := 0; i < 6 && focused_label(&p) != "Delete"; i += 1 {
		ui.probe_key(&p, .Tab)
		ui.probe_frame(&p)
	}
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect_value(t, m.last, Tree_Event{.Action, "tools", 1})
	testing.expect(t, !ui.probe_tagged(&p, "Supplemental actions"))
	// The buttons are no tab stops: Tab from the tree leaves it for good.
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "Press (Shift+"), "the shortcut is described: %s", said)
}

@(test)
test_tree_loading_announces_and_shows_placeholders :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	m.lazy = .Initial
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "lazy"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.last, Tree_Event{.Expand, "lazy", 0})
	m.lazy = .Loading
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Loading..."))
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "status \"lazy content loading\""), "%s", said)
	m.lazy_count = 3
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Loading 3 items").h, 3 * TREE_ROW)
	// Focus on the placeholder moves to the first child once loaded.
	ui.probe_click(&p, "Loading 3 items")
	ui.probe_frame(&p)
	m.lazy, m.lazy_children = .Done, true
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	said = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, "status \"lazy content loaded\""), "%s", said)
	testing.expect_value(t, focused_label(&p), "one")
	m.lazy, m.lazy_children = .Error, false
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Could not load lazy"))
	testing.expect(t, ui.probe_click(&p, "Retry"))
	testing.expect_value(t, m.last, Tree_Event{.Retry, "lazy", 0})
	testing.expect(t, ui.probe_click(&p, "Dismiss"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.last, Tree_Event{.Dismiss, "lazy", 0})
	testing.expect(t, !ui.probe_tagged(&p, "Could not load lazy")) // collapsed
}

@(test)
test_tree_flat_drops_indent_and_wrap_grows_rows :: proc(t: ^testing.T) {
	m: Tree_Model
	p: ui.Probe
	tree_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	m.flat = true
	m.src_kids[2].label = "a very long name that cannot fit in one line of a three hundred pixel tree"
	ui.probe_frame(&p)
	main := ui.probe_bounds(&p, "main.odin")
	testing.expect_value(t, label_x(&p, main), main.x + 8 + BUTTON_ICON + tok.STACK_GAP_CONDENSED)
	long := m.src_kids[2].label
	testing.expect_value(t, ui.probe_bounds(&p, long).h, TREE_ROW)
	m.wrap = true
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_bounds(&p, long).h > TREE_ROW)
}

@(private = "file")
tree_scrolled_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Tree_Model)(user)
	col := ui.column_open(gtx, align = .Start)
	defer ui.close(&col)
	box := ui.sized_open(gtx, {min = {300, 3 * TREE_ROW}, max = {300, 3 * TREE_ROW}})
	defer ui.close(&box)
	sb := ui.scroll_box_open(gtx)
	defer ui.close(&sb)
	tree_view(gtx, tree_items(m), "Files")
}

@(test)
test_tree_scrolls_the_focused_row_into_view :: proc(t: ^testing.T) {
	m: Tree_Model
	tree_model(&m)
	p: ui.Probe
	ui.probe_init(&p, tree_scrolled_view, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_bounds(&p, "tools").y >= 3 * TREE_ROW) // below the 96px box
	ui.probe_key(&p, .Tab)
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	tools := ui.probe_bounds(&p, "tools")
	testing.expect_value(t, tools.y, 2 * TREE_ROW) // its bottom at the box's
	ui.probe_key(&p, .Home)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "src").y, 0)
}
