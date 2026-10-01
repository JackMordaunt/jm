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

// The pickers and overlays: a calendar's grid, a combobox's list box,
// a tooltip and a toast as roots of their layers, and a slider named
// by its caption.

@(private = "file")
Picker_Model :: struct {
	date, view: Date,
	fruit:      ui.Text_State,
	pick:       int,
	bright:     f32,
	toasts:     Toasts,
}

@(private = "file")
PICKER_OPTIONS := [3]string{"Apple", "Banana", "Cherry"}

@(private = "file")
picks_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Picker_Model)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	calendar(gtx, &m.date, &m.view, Date{2026, 9, 28})
	combobox(gtx, &m.fruit, PICKER_OPTIONS[:], &m.pick, "Fruit", width = 260)
	// The caption's node names the slider, which gives no name of its own.
	_, caption := label(gtx, "Brightness")
	slider(gtx, &m.bright, labelled_by = caption)
	tip_box(gtx)
	toaster(gtx, &m.toasts, WINDOW)
}

// tip_box is a plain 40px square that shows a tooltip, the way a
// component calls tooltip from inside its own widget.
@(private = "file")
tip_box :: proc(gtx: ^ui.Ctx) {
	p := ui.widget_open(gtx)
	area := ops.Rect{0, 0, 40, 40}
	c := control(gtx, p.id, area, .Live)
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, "anchor")
	tooltip(gtx, p.id, c, "Saves the file", {40, 40})
	ui.widget_close(gtx, &p, {size = {40, 40}})
}

@(test)
test_calendar_is_a_grid_of_cells_and_a_slider_reads_its_caption :: proc(t: ^testing.T) {
	m: Picker_Model
	m.date = {2026, 9, 28}
	m.pick = -1
	defer ui.text_destroy(&m.fruit)
	defer toasts_destroy(&m.toasts)
	p: ui.Probe
	m.bright = 35 // a value no default could fake
	ui.probe_init(&p, picks_view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	got := ui.probe_semantics(&p, context.temp_allocator)
	for want in ([]string {
			"group \"September 2026\" at",
			"  grid \"September 2026\" at",
			"    grid cell \"1 Sep 2026\" at",
			"    grid cell \"28 Sep 2026\" selected at",
			"  button \"Go to today\" at",
			"text \"Brightness\" at",
			"slider \"Brightness\" value \"35\" at",
		}) {
		testing.expectf(t, strings.contains(got, want), "missing %q in:\n%s", want, got)
	}
	testing.expect(t, !strings.contains(got, "list box"), got)
}

@(test)
test_combobox_opens_a_list_box_of_options :: proc(t: ^testing.T) {
	m: Picker_Model
	m.pick = 1
	defer ui.text_destroy(&m.fruit)
	defer toasts_destroy(&m.toasts)
	p: ui.Probe
	ui.probe_init(&p, picks_view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Fruit"))
	got := ui.probe_semantics(&p, context.temp_allocator)
	for want in ([]string{"\nlist box \"\" at", "\n  option \"Apple\" at", "\n  option \"Banana\" selected at"}) {
		testing.expectf(t, strings.contains(got, want), "missing %q in:\n%s", want, got)
	}
	testing.expect(t, !strings.contains(got, "list item"), got)
}

@(test)
test_tooltip_and_toast_are_roots_of_their_layers :: proc(t: ^testing.T) {
	m: Picker_Model
	m.pick = -1
	defer ui.text_destroy(&m.fruit)
	defer toasts_destroy(&m.toasts)
	p: ui.Probe
	ui.probe_init(&p, picks_view, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// The tooltip is its popup's node, under no bare group.
	a := ui.probe_bounds(&p, "anchor")
	ui.probe_move(&p, a.x + 10, a.y + 10)
	ui.probe_advance(&p, 6, 0.05) // past the show delay
	got := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(got, "\ntooltip \"Saves the file\" at"), got)
	testing.expect(t, !strings.contains(got, "group \"\""), got)

	// A toast is a root too, the toaster's column passed over, and its
	// dismiss button nests under it.
	toast_push(&m.toasts, "Saved", "Your changes are saved.")
	ui.probe_advance(&p, 40, 0.02) // through the enter motion
	got = ui.probe_semantics(&p, context.temp_allocator)
	status := "\nstatus \"Saved\" desc \"Your changes are saved.\" at"
	i := strings.index(got, status)
	testing.expectf(t, i >= 0, "missing %q in:\n%s", status, got)
	if i >= 0 {
		rest := got[i + 1:]
		rest = rest[strings.index_byte(rest, '\n') + 1:]
		testing.expect(t, strings.has_prefix(rest, "  button \"Dismiss Saved\" at"), got)
	}
}
