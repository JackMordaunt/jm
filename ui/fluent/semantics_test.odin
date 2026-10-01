package fluent

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// What the components say to a screen reader, read back through
// ui.probe_semantics, and that Escape closes a dialog nothing in has
// focus.

@(private = "file")
Semantic_Model :: struct {
	dark:   bool,
	wifi:   bool,
	volume: f32,
	name:   ui.Text_State,
	tab:    int,
	docs:   bool,
	dialog: bool,
	saves:  int,
}

@(private = "file")
WINDOW :: ops.Size{800, 600}

@(private = "file")
TABS := [3]string{"Home", "Pages", "Settings"}

@(private = "file")
semantic_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Semantic_Model)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	if button(gtx, "Save", .Primary) {
		m.saves += 1
	}
	checkbox(gtx, &m.dark, "Dark mode")
	toggle_switch(gtx, &m.wifi, "Wi-Fi")
	slider(gtx, &m.volume, name = "Volume")
	if field(gtx, "Name", hint = "As on your passport") {
		input(gtx, &m.name, "Enter a name")
	}
	tab_list(gtx, TABS[:], &m.tab)
	if tree_item(gtx, "Docs", &m.docs) {
		tree_item(gtx, "Readme", level = 2)
	}
	if dialog(gtx, &m.dialog, WINDOW) {
		dialog_title(gtx, "Discard changes?")
		if dialog_actions(gtx) {
			if button(gtx, "Discard", .Primary) {
				m.dialog = false
			}
		}
	}
}

@(test)
test_components_declare_their_roles_and_states :: proc(t: ^testing.T) {
	m: Semantic_Model
	m.dark = true
	m.wifi = true
	m.volume = 40
	m.tab = 1
	m.docs = true
	ui.text_set(&m.name, "Jack")
	defer ui.text_destroy(&m.name)
	p: ui.Probe
	ui.probe_init(&p, semantic_view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	got := ui.probe_semantics(&p, context.temp_allocator)
	for want in ([]string {
			"button \"Save\" at",
			"checkbox \"Dark mode\" checked at",
			"switch \"Wi-Fi\" checked at",
			"slider \"Volume\" value \"40\" at",
			// The field names the input and its hint describes it.
			"text \"Name\" at",
			"text field \"Name\" value \"Jack\" desc \"As on your passport\" at",
			"tab list \"\" at",
			"  tab \"Home\" at",
			"  tab \"Pages\" selected at",
			"list item \"Docs\" expandable expanded at",
			"list \"\" at",
			"  list item \"Readme\" at",
		}) {
		testing.expectf(t, strings.contains(got, want), "missing %q in:\n%s", want, got)
	}
	testing.expect(t, !strings.contains(got, "dialog"), got)

	// Toggling the switch and collapsing the tree change their states.
	testing.expect(t, ui.probe_click(&p, "Wi-Fi"))
	testing.expect(t, ui.probe_click(&p, "Docs"))
	got = ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(got, "switch \"Wi-Fi\" at"), got)
	testing.expect(t, strings.contains(got, "list item \"Docs\" expandable focused at"), got)
	testing.expect(t, !strings.contains(got, "Readme"), got)
}

@(test)
test_dialog_is_a_modal_dialog_named_by_its_title_and_escape_closes_it_unfocused :: proc(t: ^testing.T) {
	m: Semantic_Model
	defer ui.text_destroy(&m.name)
	p: ui.Probe
	ui.probe_init(&p, semantic_view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Opened by the app, not a click: nothing holds focus.
	m.dialog = true
	ui.probe_frame(&p)
	got := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(got, "dialog \"Discard changes?\" modal at"), got)
	testing.expect(t, strings.contains(got, "  heading \"Discard changes?\" at"), got)
	testing.expect(t, strings.contains(got, "  button \"Discard\" at"), got)
	testing.expect(t, !strings.contains(got, "focused"), got)

	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.dialog)
	ui.probe_frame(&p)
	got = ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, !strings.contains(got, "dialog"), got)
	// Escape with the dialog closed reaches nothing.
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.dialog)
}
