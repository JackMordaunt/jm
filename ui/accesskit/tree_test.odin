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
