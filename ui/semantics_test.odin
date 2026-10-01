package ui

import "jm:ui/ops"
import "core:strings"
import "core:testing"

// screen_view is a list of two items, one selected, a checkbox, a label
// and an overlay dialog with a button: the shapes a reader meets.
@(private = "file")
Screen_Model :: struct {
	dialog:  bool,
	escapes: int, // Escape presses the dialog heard
	keys:    [dynamic]Key, // what the text field heard
}

@(private = "file")
screen_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Screen_Model)(user)
	col := column_open(gtx, key = 1)
	defer close(&col)
	{
		list := column_open(gtx, key = 2)
		defer close(&list)
		container_semantics(gtx, {role = .List, label = "Fruit"})
		for name, i in ([]string{"Apple", "Pear"}) {
			p := widget_open(gtx, u64(10 + i))
			ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 80, 20}, {.Press})
			semantics(gtx, &p, {role = .List_Item, label = name, states = i == 1 ? {.Selected} : {}})
			widget_close(gtx, &p, {size = {80, 20}})
		}
	}
	{
		// An undeclared column around it: the checkbox still sits at the
		// top, not under the text that follows the column.
		wrap := column_open(gtx, key = 30)
		defer close(&wrap)
		p := widget_open(gtx, 3)
		ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 24, 24}, {.Press})
		semantics(gtx, &p, {role = .Checkbox, label = "Dark", states = {.Checked}})
		part_semantics(gtx, &p, id_mix(p.id, 1), {0, 0, 12, 12}, {role = .Text, label = "box"})
		widget_close(gtx, &p, {size = {24, 24}})
	}
	label(gtx, "Status: ready", key = 4)
	{
		p := widget_open(gtx, 5)
		ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 120, 24}, {.Press, .Key, .Text, .Focus, .Blur})
		ops.tag(gtx.scene, p.id, "Name")
		semantics(gtx, &p, {role = .Text_Field, label = "Name", value = "Jack"})
		for e in events(gtx, p.id) {
			if e.kind == .Key {
				append(&m.keys, e.key)
			}
		}
		widget_close(gtx, &p, {size = {120, 24}})
	}
	if m.dialog {
		o := overlay_open(gtx)
		defer close(&o)
		box := column_open(gtx, key = 6)
		defer close(&box)
		container_semantics(gtx, {role = .Dialog, label = "Discard?", states = {.Modal}})
		id := claim_id(gtx, 60)
		key_interest(gtx, id, .Escape)
		for e in events(gtx, id) {
			if e.kind == .Key && e.key == .Escape {
				m.escapes += 1
			}
		}
		p := widget_open(gtx, 7)
		ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 60, 24}, {.Press})
		ops.tag(gtx.scene, p.id, "Discard")
		semantics(gtx, &p, {role = .Button, label = "Discard"})
		widget_close(gtx, &p, {size = {60, 24}})
	}
}

@(test)
semantics_report_reads_the_screen_as_a_tree :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Screen_Model
	defer delete(m.keys)
	p: Probe
	probe_init(&p, screen_view, &m, {300, 300})
	defer probe_destroy(&p)
	got := probe_semantics(&p, context.temp_allocator)
	want := strings.concatenate(
		{
			"list \"Fruit\" at 0,0 80x40\n",
			"  list item \"Apple\" at 0,0 80x20\n",
			"  list item \"Pear\" selected at 0,20 80x20\n",
			"checkbox \"Dark\" checked at 0,40 24x24\n",
			"  text \"box\" at 0,40 12x12\n",
			"text \"Status: ready\" at 0,64 109x14\n",
			"text field \"Name\" value \"Jack\" at 0,78 120x24\n",
		},
		context.temp_allocator,
	)
	testing.expect_value(t, got, want)

	// Focus shows on the node, and an overlay's nodes come after the
	// page's, nested under the overlay's own role.
	testing.expect(t, probe_click(&p, "Name"))
	m.dialog = true
	probe_frame(&p)
	got = probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(got, "text field \"Name\" value \"Jack\" focused at"), got)
	testing.expect(t, strings.has_suffix(got, "dialog \"Discard?\" modal at 0,0 60x24\n  button \"Discard\" at 0,0 60x24\n"), got)
}

@(test)
key_interest_delivers_keys_without_focus :: proc(t: ^testing.T) {
	m: Screen_Model
	defer delete(m.keys)
	m.dialog = true
	p: Probe
	probe_init(&p, screen_view, &m, {300, 300})
	defer probe_destroy(&p)
	probe_frame(&p) // the dialog's interest is in the routed frame
	// Nothing focused: the dialog alone hears Escape, and only Escape.
	probe_key(&p, .Escape)
	probe_key(&p, .A)
	probe_frame(&p)
	testing.expect_value(t, m.escapes, 1)
	testing.expect_value(t, len(m.keys), 0)
	// The field focused: it hears every key, and the dialog still hears
	// Escape, after it.
	testing.expect(t, probe_click(&p, "Name"))
	probe_key(&p, .Escape)
	probe_key(&p, .A)
	probe_frame(&p)
	testing.expect_value(t, m.escapes, 2)
	testing.expect_value(t, len(m.keys), 2)
	testing.expect_value(t, m.keys[0], Key.Escape)
	// A modifier the interest did not ask for is not a match.
	probe_key(&p, .Escape, {.Ctrl})
	probe_frame(&p)
	testing.expect_value(t, m.escapes, 2)
}

@(test)
key_interest_matches_by_key_and_modifiers :: proc(t: ^testing.T) {
	save := ops.Key_Interest{1, .S, {.Ctrl}, {.Shift}}
	testing.expect(t, key_interest_matches(save, .S, {.Ctrl}))
	testing.expect(t, key_interest_matches(save, .S, {.Ctrl, .Shift}))
	testing.expect(t, !key_interest_matches(save, .S, {}))
	testing.expect(t, !key_interest_matches(save, .S, {.Ctrl, .Alt}))
	testing.expect(t, !key_interest_matches(save, .A, {.Ctrl}))
	any := ops.Key_Interest{1, .None, {}, {.Shift, .Ctrl, .Alt, .Super}}
	testing.expect(t, key_interest_matches(any, .F11, {.Alt}))
	testing.expect(t, !key_interest_matches(ops.Key_Interest{1, .None, {}, {}}, .A, {.Shift}))
}
