package ui

import "core:fmt"
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
		// A part before its widget's own declaration, and a part under
		// that part: both nest where they belong.
		part_semantics(gtx, &p, id_mix(p.id, 1), {0, 0, 12, 12}, {role = .Text, label = "box"})
		part_semantics(gtx, &p, id_mix(p.id, 2), {0, 0, 6, 6}, {role = .Text, label = "tick"}, under = id_mix(p.id, 1))
		semantics(gtx, &p, {role = .Checkbox, label = "Dark", states = {.Checked}})
		widget_close(gtx, &p, {size = {24, 24}})
	}
	{
		// A widget that declares nothing itself but has parts is a group
		// of them.
		p := widget_open(gtx, 8)
		part_semantics(gtx, &p, id_mix(p.id, 1), {0, 0, 10, 10}, {role = .Tab, label = "One", states = {.Selected}})
		widget_close(gtx, &p, {size = {40, 10}})
	}
	caption: ops.Area_Id
	{
		// A caption, as base.label returns its id for.
		c := widget_open(gtx, 4)
		semantics(gtx, &c, {role = .Text, label = "Status: ready"})
		caption = c.id
		widget_close(gtx, &c, {size = {100, 14}})
	}
	{
		// A slider with no label of its own, named by the caption above
		// it, inside a decorative container a reader passes over.
		wrap := column_open(gtx, key = 40)
		defer close(&wrap)
		container_semantics(gtx, {role = .Presentation})
		p := widget_open(gtx, 41)
		semantics(gtx, &p, {role = .Slider, labelled_by = caption, value = "50"})
		widget_close(gtx, &p, {size = {100, 10}})
	}
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
		// A tooltip painted straight into a popup: the overlay is its node.
		{
			tip := popup_open(gtx, {0, 0, 10, 10}, key = 70)
			node := overlay_semantics(gtx, &tip, {role = .Tooltip, label = "Saves the file"})
			child_semantics(gtx, node, id_mix(node, 1), {2, 2, 8, 8}, {role = .Text, label = "arrow"})
			popup_close(&tip, {40, 16})
		}
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
			"    text \"tick\" at 0,40 6x6\n",
			"group \"\" at 0,64 40x10\n",
			"  tab \"One\" selected at 0,64 10x10\n",
			"text \"Status: ready\" at 0,74 100x14\n",
			"slider \"Status: ready\" value \"50\" at 0,88 100x10\n",
			"text field \"Name\" value \"Jack\" at 0,98 120x24\n",
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
	testing.expect(t, strings.contains(got, "tooltip \"Saves the file\" at 0,10 40x16\n  text \"arrow\" at 2,12 8x8\n"), got)
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

@(private = "file")
Stack_Model :: struct {
	menu:    bool, // the menu is open over the dialog
	escapes: [3]int, // dialog, menu, shortcut
}

// stack_view is a dialog with a topmost Escape, a menu raised over it with
// one of its own while m.menu, and a plain interest that hears every Escape.
@(private = "file")
stack_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Stack_Model)(user)
	ids := [3]ops.Area_Id{40, 41, 42}
	for e, i in ids {
		for ev in events(gtx, e) {
			if ev.kind == .Key && ev.key == .Escape {
				m.escapes[i] += 1
			}
		}
	}
	key_interest(gtx, ids[2], .Escape)
	d := overlay_open(gtx)
	key_interest(gtx, ids[0], .Escape, topmost = true)
	if m.menu {
		menu := popup_open(gtx, {0, 0, 10, 10}, ids[1])
		key_interest(gtx, ids[1], .Escape, topmost = true)
		popup_close(&menu, {50, 50})
	}
	overlay_close(&d)
}

@(test)
topmost_key_interest_goes_to_the_top_layer_alone :: proc(t: ^testing.T) {
	m := Stack_Model{menu = true}
	p: Probe
	probe_init(&p, stack_view, &m, {300, 300})
	defer probe_destroy(&p)
	probe_key(&p, .Escape)
	probe_frame(&p)
	testing.expect_value(t, m.escapes, [3]int{0, 1, 1}) // the menu, raised last, alone of the stack
	m.menu = false
	probe_frame(&p)
	probe_key(&p, .Escape)
	probe_frame(&p)
	testing.expect_value(t, m.escapes, [3]int{1, 1, 2}) // with the menu gone, the dialog
}

@(test)
key_interest_matches_by_key_and_modifiers :: proc(t: ^testing.T) {
	save := ops.Key_Interest{1, .S, {.Ctrl}, {.Shift}, false}
	testing.expect(t, key_interest_matches(save, .S, {.Ctrl}))
	testing.expect(t, key_interest_matches(save, .S, {.Ctrl, .Shift}))
	testing.expect(t, !key_interest_matches(save, .S, {}))
	testing.expect(t, !key_interest_matches(save, .S, {.Ctrl, .Alt}))
	testing.expect(t, !key_interest_matches(save, .A, {.Ctrl}))
	any := ops.Key_Interest{1, .None, {}, {.Shift, .Ctrl, .Alt, .Super}, false}
	testing.expect(t, key_interest_matches(any, .F11, {.Alt}))
	testing.expect(t, !key_interest_matches(ops.Key_Interest{1, .None, {}, {}, false}, .A, {.Shift}))
}

@(test)
a_pushed_focus_names_the_area_an_assistive_technology_asked_for :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Screen_Model
	defer delete(m.keys)
	p: Probe
	probe_init(&p, screen_view, &m, {300, 300})
	defer probe_destroy(&p)
	field, ok := probe_find(&p, "Name")
	testing.expect(t, ok)
	router_push(&p.router, {kind = .Focus, area = field.area})
	probe_frame(&p)
	testing.expect_value(t, p.router.focus, field.area)
	testing.expect(t, p.router.keyboard) // shown as keyboard focus
	testing.expect(t, strings.contains(probe_semantics(&p, context.temp_allocator), "text field \"Name\" value \"Jack\" focused at"))
	// An area the frame does not have is not focused, and focus stays.
	router_push(&p.router, {kind = .Focus, area = 999999})
	probe_frame(&p)
	testing.expect_value(t, p.router.focus, field.area)
}

@(test)
semantics_report_says_a_headings_level_and_names_a_region :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		col := column_open(gtx, key = 1)
		defer close(&col)
		container_semantics(gtx, {role = .Region, label = "Saved"})
		h := widget_open(gtx, 2)
		semantics(gtx, &h, {role = .Heading, label = "Saved", level = 2})
		widget_close(gtx, &h, {size = {60, 20}})
	}
	defer free_all(context.temp_allocator)
	p: Probe
	probe_init(&p, view, nil, {300, 300})
	defer probe_destroy(&p)
	testing.expect_value(t, probe_semantics(&p, context.temp_allocator), "region \"Saved\" at 0,0 300x300\n  heading \"Saved\" level 2 at 0,0 60x20\n")
	testing.expect(t, strings.contains(probe_dump(&p), "Heading \"Saved\" level 2"), probe_dump(&p))
}

@(test)
semantics_report_names_an_active_descendant_and_the_checkable_menu_items :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		col := column_open(gtx, key = 1)
		defer close(&col)
		field := widget_open(gtx, 2)
		option := id_mix(field.id, 1)
		semantics(gtx, &field, {role = .Combo_Box, label = "Fruit", active_descendant = option})
		part_semantics(gtx, &field, option, {0, 20, 60, 20}, {role = .Option, label = "Apple"})
		widget_close(gtx, &field, {size = {60, 40}})
		a := widget_open(gtx, 3)
		semantics(gtx, &a, {role = .Menu_Item_Checkbox, label = "Wrap", states = {.Checked}})
		widget_close(gtx, &a, {size = {60, 20}})
		b := widget_open(gtx, 4)
		semantics(gtx, &b, {role = .Menu_Item_Radio, label = "Dark"})
		widget_close(gtx, &b, {size = {60, 20}})
	}
	defer free_all(context.temp_allocator)
	p: Probe
	probe_init(&p, view, nil, {300, 300})
	defer probe_destroy(&p)
	got := probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(got, "combo box \"Fruit\" active \"Apple\" at 0,0 60x40\n  option \"Apple\""), got)
	testing.expect(t, strings.contains(got, "menu item checkbox \"Wrap\" checked"), got)
	testing.expect(t, strings.contains(got, "menu item radio \"Dark\" at"), got)
	apple: ops.Area_Id
	for n in probe_current(&p).nodes {
		if n.semantics.label == "Apple" {
			apple = n.id
		}
	}
	testing.expect(t, apple != 0)
	context.allocator = context.temp_allocator // the dump's builder
	dump := probe_dump(&p)
	testing.expect(t, strings.contains(dump, fmt.tprintf("Combo_Box \"Fruit\" active_descendant %d", apple)), dump)
}

@(test)
semantics_report_names_a_tree_its_items_levels_and_the_current_one :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		col := column_open(gtx, key = 1)
		defer close(&col)
		container_semantics(gtx, {role = .Tree, label = "Files"})
		a := widget_open(gtx, 2)
		semantics(gtx, &a, {role = .Tree_Item, label = "src", level = 1, states = {.Expanded}})
		widget_close(gtx, &a, {size = {60, 20}})
		b := widget_open(gtx, 3)
		semantics(gtx, &b, {role = .Tree_Item, label = "main.odin", level = 2, states = {.Current}})
		widget_close(gtx, &b, {size = {60, 20}})
		c := widget_open(gtx, 4)
		semantics(gtx, &c, {role = .Link, label = "Home", states = {.Current_Page}})
		widget_close(gtx, &c, {size = {60, 20}})
		d := widget_open(gtx, 5)
		semantics(gtx, &d, {role = .Tab_Panel, label = "Code"})
		widget_close(gtx, &d, {size = {60, 20}})
	}
	defer free_all(context.temp_allocator)
	p: Probe
	probe_init(&p, view, nil, {300, 300})
	defer probe_destroy(&p)
	testing.expect_value(
		t,
		probe_semantics(&p, context.temp_allocator),
		"tree \"Files\" at 0,0 300x300\n  tree item \"src\" level 1 expanded at 0,0 60x20\n  tree item \"main.odin\" level 2 current at 0,20 60x20\n  link \"Home\" current page at 0,40 60x20\n  tab panel \"Code\" at 0,60 60x20\n",
	)
}
