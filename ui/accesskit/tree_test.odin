#+build linux, darwin, windows
package accesskit

import "core:fmt"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// bridge_view is a list of two items under a heading, a checked checkbox,
// a field that takes focus, and a label that names a slider.
@(private = "file")
bridge_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, key = 1)
	defer ui.close(&col)
	{
		h := ui.widget_open(gtx, 2)
		ui.semantics(gtx, &h, {role = .Heading, label = "Fruit"})
		ui.widget_close(gtx, &h, {size = {80, 20}})
	}
	{
		list := ui.column_open(gtx, key = 3)
		defer ui.close(&list)
		ui.container_semantics(gtx, {role = .List})
		for name, i in ([]string{"Apple", "Pear"}) {
			p := ui.widget_open(gtx, u64(10 + i))
			ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 80, 20}, {.Press})
			ui.semantics(gtx, &p, {role = .List_Item, label = name, states = i == 1 ? {.Selected} : {}})
			ui.widget_close(gtx, &p, {size = {80, 20}})
		}
	}
	{
		p := ui.widget_open(gtx, 4)
		ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 24, 24}, {.Press})
		ui.semantics(gtx, &p, {role = .Checkbox, label = "Dark", states = {.Checked}})
		ui.widget_close(gtx, &p, {size = {24, 24}})
	}
	{
		p := ui.widget_open(gtx, 5)
		ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 120, 24}, {.Press, .Key, .Text, .Focus, .Blur})
		ops.tag(gtx.scene, p.id, "Name")
		ui.semantics(gtx, &p, {role = .Text_Field, label = "Name", value = "Jack"})
		ui.widget_close(gtx, &p, {size = {120, 24}})
	}
	caption: ops.Area_Id
	{
		c := ui.widget_open(gtx, 6)
		ui.semantics(gtx, &c, {role = .Text, label = "Volume"})
		caption = c.id
		ui.widget_close(gtx, &c, {size = {60, 14}})
	}
	{
		p := ui.widget_open(gtx, 7)
		ui.semantics(gtx, &p, {role = .Slider, labelled_by = caption, value = "50"})
		ui.widget_close(gtx, &p, {size = {100, 10}})
	}
}

@(test)
test_snapshot_builds_the_tree_accesskit_reads :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, bridge_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	// Focus on an area that is no node leaves the window focused.
	snapshot_take(&s, ui.probe_current(&p), 123456789, "Bridge")
	testing.expect_value(t, len(s.records), 8) // the list column counts
	testing.expect_value(t, s.focus, WINDOW)
	got := debug(&s, context.temp_allocator)
	// The window roots the heading, the list, the checkbox, the field,
	// the caption and the slider, in order; the list holds its items.
	r := s.records[:]
	testing.expect(t, strings.contains(got, fmt.tprintf("role: Window, children: [#%d, #%d, #%d, #%d, #%d, #%d], label: \"Bridge\"", r[0].id, r[3].id, r[4].id, r[5].id, r[6].id, r[7].id)), got)
	testing.expect(t, strings.count(got, "role: ") == 9, got)
	testing.expect(t, strings.contains(got, `role: Heading, label: "Fruit", value: "Fruit", level: 1, bounds: Rect { x0: 0.0, y0: 0.0, x1: 80.0, y1: 20.0 }`), got)
	testing.expect(t, strings.contains(got, `role: Label, label: "Volume", value: "Volume", bounds:`), got) // static text is read from its value
	testing.expect(t, strings.contains(got, `role: ListItem, actions: [Click], label: "Pear", is_selected: true`), got)
	testing.expect(t, strings.contains(got, fmt.tprintf("role: List, children: [#%d, #%d]", s.records[1].id, s.records[2].id)), got)
	testing.expect(t, strings.contains(got, `role: CheckBox, actions: [Click], label: "Dark", toggled: True`), got)
	testing.expect(t, strings.contains(got, `role: TextInput, actions: [Click, Focus], label: "Name", value: "Jack"`), got)
	testing.expect(t, strings.contains(got, fmt.tprintf(`role: Slider, labelled_by: [#%d], value: "50"`, s.records[6].id)), got)
	testing.expect(t, strings.contains(got, "focus: #0 }"), got)
	// Nothing changed: the same frame takes the same snapshot.
	again: Snapshot
	snapshot_init(&again)
	defer snapshot_destroy(&again)
	snapshot_take(&again, ui.probe_current(&p), 0, "Bridge")
	testing.expect(t, snapshot_equal(&s, &again))
	// Focus on the field: a different snapshot, named in the update.
	testing.expect(t, ui.probe_click(&p, "Name"))
	snapshot_take(&again, ui.probe_current(&p), p.router.focus, "Bridge")
	testing.expect(t, snapshot_equal(&s, &again)) // focus is compared apart
	testing.expect(t, s.focus != again.focus)
	testing.expect_value(t, again.focus, Node_Id(p.router.focus))
	testing.expect(t, strings.contains(debug(&again, context.temp_allocator), fmt.tprintf("focus: #%d }", p.router.focus)))
}

// dense_view is bridge_view under the scale the shell pushes on a display
// of density 2, so the frame's rects are in device pixels.
dense_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	ops.transform_push(gtx.scene, ops.scale(2, 2))
	bridge_view(gtx, user)
	ops.transform_pop(gtx.scene)
}

@(test)
test_snapshot_bounds_are_device_pixels :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, dense_view, nil, {600, 600})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Bridge")
	// AccessKit takes physical pixels and scales to points itself, so the
	// 80 by 20 heading is reported at twice its size, not divided back.
	got := debug(&s, context.temp_allocator)
	testing.expect(t, strings.contains(got, `role: Heading, label: "Fruit", value: "Fruit", level: 1, bounds: Rect { x0: 0.0, y0: 0.0, x1: 160.0, y1: 40.0 }`), got)
}

// scrolled_view is a list taller than its scroll box: items below the
// box are clipped away.
@(private = "file")
scrolled_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	sb := ui.scroll_box_open(gtx, key = 1)
	defer ui.close(&sb)
	col := ui.column_open(gtx, key = 2)
	defer ui.close(&col)
	for i in 0 ..< 10 {
		p := ui.widget_open(gtx, u64(10 + i))
		ui.semantics(gtx, &p, {role = .List_Item, label = "row"})
		ui.widget_close(gtx, &p, {size = {80, 20}})
	}
}

// collapsed_view is a drawer closed to no width: in the frame, unseen.
@(private = "file")
collapsed_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, key = 1) // the root would force the window's size on it
	defer ui.close(&col)
	p := ui.widget_open(gtx, 2)
	ui.semantics(gtx, &p, {role = .Navigation})
	ui.widget_close(gtx, &p, {size = {0, 300}})
}

@(private = "file")
invalid_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, key = 1)
	defer ui.close(&col)
	for name, i in ([]string{"Email", "Phone"}) {
		p := ui.widget_open(gtx, u64(10 + i))
		ui.semantics(gtx, &p, {role = .Text_Field, label = name, states = i == 0 ? {.Invalid} : {}})
		ui.widget_close(gtx, &p, {size = {120, 24}})
	}
}

@(private = "file")
password_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	p := ui.widget_open(gtx, 1)
	ui.semantics(gtx, &p, {role = .Password_Field, label = "Password", value = "●●●"})
	ui.widget_close(gtx, &p, {size = {120, 24}})
}

@(test)
test_a_password_field_reaches_accesskit_as_a_password_input :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, password_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Sign in")
	got := debug(&s, context.temp_allocator)
	testing.expect(t, strings.contains(got, `role: PasswordInput, label: "Password"`), got)
}

@(test)
test_an_invalid_field_reaches_accesskit_invalid :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, invalid_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Form")
	got := debug(&s, context.temp_allocator)
	testing.expect(t, strings.contains(got, `label: "Email", invalid: True`), got)
	testing.expect_value(t, strings.count(got, "invalid"), 1) // Phone is not
}

@(test)
test_a_collapsed_node_is_hidden :: proc(t: ^testing.T) {
	p: ui.Probe
	ui.probe_init(&p, collapsed_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Drawer")
	testing.expect_value(t, len(s.records), 1)
	testing.expect(t, s.records[0].hidden)
}

@(test)
test_a_node_scrolled_out_of_its_clip_is_hidden :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, scrolled_view, nil, {100, 50})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Scroll")
	testing.expect_value(t, len(s.records), 10)
	hidden := 0
	for r in s.records {
		if r.hidden {
			hidden += 1
		}
	}
	testing.expect_value(t, hidden, 7) // 50px shows two rows and part of a third
	testing.expect(t, strings.count(debug(&s, context.temp_allocator), "hidden: true") == 7)
}

// outline_view is a region holding an h3 and a heading with no level.
@(private = "file")
outline_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, key = 1)
	defer ui.close(&col)
	ui.container_semantics(gtx, {role = .Region, label = "Saved"})
	{
		h := ui.widget_open(gtx, 2)
		ui.semantics(gtx, &h, {role = .Heading, label = "Third", level = 3})
		ui.widget_close(gtx, &h, {size = {80, 20}})
	}
	{
		h := ui.widget_open(gtx, 3)
		ui.semantics(gtx, &h, {role = .Heading, label = "Plain"})
		ui.widget_close(gtx, &h, {size = {80, 20}})
	}
}

@(test)
test_a_heading_carries_its_level_and_a_region_its_role :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, outline_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Outline")
	got := debug(&s, context.temp_allocator)
	testing.expect(t, strings.contains(got, `role: Region, children:`), got)
	testing.expect(t, strings.contains(got, `role: Heading, label: "Third", value: "Third", level: 3,`), got)
	testing.expect(t, strings.contains(got, `role: Heading, label: "Plain", value: "Plain", level: 1,`), got) // no level reads as 1
}

// picker_view is a combo box pointing at its second option, beside a
// checked menu item checkbox and an unchecked menu item radio.
@(private = "file")
picker_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, key = 1)
	defer ui.close(&col)
	field := ui.widget_open(gtx, 2)
	second := ui.id_mix(field.id, 2)
	ui.semantics(gtx, &field, {role = .Combo_Box, label = "Fruit", active_descendant = second})
	ui.part_semantics(gtx, &field, ui.id_mix(field.id, 1), {0, 20, 80, 20}, {role = .Option, label = "Apple"})
	ui.part_semantics(gtx, &field, second, {0, 40, 80, 20}, {role = .Option, label = "Pear"})
	ui.widget_close(gtx, &field, {size = {80, 60}})
	a := ui.widget_open(gtx, 3)
	ui.semantics(gtx, &a, {role = .Menu_Item_Checkbox, label = "Wrap", states = {.Checked}})
	ui.widget_close(gtx, &a, {size = {80, 20}})
	b := ui.widget_open(gtx, 4)
	ui.semantics(gtx, &b, {role = .Menu_Item_Radio, label = "Dark"})
	ui.widget_close(gtx, &b, {size = {80, 20}})
}

@(test)
test_a_combo_box_names_its_active_descendant_and_menu_items_toggle :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, picker_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Picker")
	pear: Node_Id
	wrap, dark: Snapshot_Node
	for r in s.records {
		switch r.label >= 0 ? string(text(&s, r.label)) : "" {
		case "Pear":
			pear = r.id
		case "Wrap":
			wrap = r
		case "Dark":
			dark = r
		}
	}
	testing.expect(t, pear != 0)
	got := debug(&s, context.temp_allocator)
	testing.expect(t, strings.contains(got, fmt.tprintf(`active_descendant: #%d, label: "Fruit"`, pear)), got)
	testing.expect_value(t, wrap.role, Role.Menu_Item_Check_Box)
	testing.expect(t, wrap.has_toggled && wrap.toggled == .True)
	testing.expect_value(t, dark.role, Role.Menu_Item_Radio)
	testing.expect(t, dark.has_toggled && dark.toggled == .False)
}

// tree_view is a tree of two items, the second current, and a link to
// the page shown.
@(private = "file")
tree_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, key = 1)
	defer ui.close(&col)
	ui.container_semantics(gtx, {role = .Tree, label = "Files"})
	{
		a := ui.widget_open(gtx, 2)
		ui.semantics(gtx, &a, {role = .Tree_Item, label = "src", level = 1, states = {.Expanded}})
		ui.widget_close(gtx, &a, {size = {80, 20}})
	}
	{
		b := ui.widget_open(gtx, 3)
		ui.semantics(gtx, &b, {role = .Tree_Item, label = "main.odin", level = 2, states = {.Current}})
		ui.widget_close(gtx, &b, {size = {80, 20}})
	}
	{
		c := ui.widget_open(gtx, 4)
		ui.semantics(gtx, &c, {role = .Link, label = "Home", states = {.Current_Page}})
		ui.widget_close(gtx, &c, {size = {80, 20}})
	}
}

@(test)
test_a_tree_item_carries_its_level_and_current_items_say_so :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, tree_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Tree")
	got := debug(&s, context.temp_allocator)
	testing.expect(t, strings.contains(got, `role: Tree, children:`), got)
	testing.expect(t, strings.contains(got, `level: 1,`), got)
	testing.expect(t, strings.contains(got, `level: 2,`), got)
	testing.expect(t, strings.contains(got, `aria_current: True`), got)
	testing.expect(t, strings.contains(got, `aria_current: Page`), got)
}

// calendar_view is a grid with a weekday's column header and a day cell
// that is today.
@(private = "file")
calendar_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	col := ui.column_open(gtx, key = 1)
	defer ui.close(&col)
	ui.container_semantics(gtx, {role = .Grid, label = "October 2026"})
	{
		a := ui.widget_open(gtx, 2)
		ui.semantics(gtx, &a, {role = .Column_Header, label = "Monday"})
		ui.widget_close(gtx, &a, {size = {32, 20}})
	}
	{
		b := ui.widget_open(gtx, 3)
		ui.semantics(gtx, &b, {role = .Grid_Cell, label = "October 5", states = {.Current_Date}})
		ui.widget_close(gtx, &b, {size = {32, 32}})
	}
}

@(test)
test_a_column_header_and_the_current_date_reach_accesskit :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, calendar_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Calendar")
	got := debug(&s, context.temp_allocator)
	testing.expect(t, strings.contains(got, `role: ColumnHeader`), got)
	testing.expect(t, strings.contains(got, `aria_current: Date`), got)
}

// table_view is a grid of 20,000 rows, of which it draws one: its header
// sorted descending, and a cell at row 4,812, column 2.
@(private = "file")
table_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	g := ui.widget_open(gtx, 1)
	ui.semantics(gtx, &g, {role = .Grid, label = "Rigs", row_count = 20_001, col_count = 3})
	head := ui.id_mix(g.id, 1)
	ui.part_semantics(gtx, &g, head, {0, 0, 300, 20}, {role = .Column_Header, label = "Serial", col_index = 2, sort = .Descending})
	ui.part_semantics(gtx, &g, ui.id_mix(g.id, 2), {0, 20, 300, 20}, {role = .Grid_Cell, label = "SN-1", row_index = 4812, col_index = 2})
	ui.widget_close(gtx, &g, {size = {300, 40}})
}

@(test)
test_a_grid_counts_its_rows_and_places_a_virtual_cell :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p: ui.Probe
	ui.probe_init(&p, table_view, nil, {300, 300})
	defer ui.probe_destroy(&p)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `grid "Rigs" rows 20001 cols 3`), said)
	testing.expect(t, strings.contains(said, `column header "Serial" col 2 sorted descending`), said)
	s: Snapshot
	snapshot_init(&s)
	defer snapshot_destroy(&s)
	snapshot_take(&s, ui.probe_current(&p), 0, "Table")
	got := debug(&s, context.temp_allocator)
	// set_table_place takes 1 off ARIA's 1-based places for AccessKit.
	testing.expect(t, strings.contains(got, `row_count: 20001`), got)
	testing.expect(t, strings.contains(got, `row_index: 4811`), got)
	testing.expect(t, strings.contains(got, `column_index: 1`), got)
	testing.expect(t, strings.contains(got, `sort_direction: Descending`), got)
}
