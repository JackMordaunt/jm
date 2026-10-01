package material

import "core:strings"
import "core:testing"
import "jm:ui"

// What the components say to assistive technology, read back through
// ui.probe_semantics, and that a dialog hears Escape without focus.

@(private = "file")
Sem_Model :: struct {
	agree, wifi: bool,
	level:       f32,
	name:        ui.Text_State,
	tab:         int,
	dialog:      bool,
	saves:       int,
}

@(private = "file")
SEM_TABS := [?]string{"Flights", "Hotels"}

@(private = "file")
SEM_ACTIONS := [?]string{"Cancel", "Discard"}

@(private = "file")
sem_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Sem_Model)(user)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)
	if button(gtx, "Save") {
		m.saves += 1
	}
	checkbox(gtx, &m.agree, "Agree")
	switch_(gtx, &m.wifi, "Wi-Fi")
	slider(gtx, &m.level, 0, 100)
	text_field(gtx, &m.name, "Name", supporting = "Required")
	tabs(gtx, SEM_TABS[:], &m.tab)
	dialog(gtx, &m.dialog, {400, 900}, "Discard draft?", "Your changes will be lost.", SEM_ACTIONS[:])
}

@(private = "file")
expect_line :: proc(t: ^testing.T, got, want: string, loc := #caller_location) {
	testing.expect(t, strings.contains(got, want), got, loc = loc)
}

@(test)
components_declare_their_roles :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Sem_Model {
		agree = true,
		wifi  = true,
		level = 50,
		tab   = 1,
	}
	ui.text_set(&m.name, "Jack")
	defer ui.text_destroy(&m.name)
	p: ui.Probe
	ui.probe_init(&p, sem_view, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	got := ui.probe_semantics(&p, context.temp_allocator)
	expect_line(t, got, "button \"Save\" at ")
	expect_line(t, got, "checkbox \"Agree\" checked at ")
	expect_line(t, got, "switch \"Wi-Fi\" checked at ")
	expect_line(t, got, "slider \"\" value \"50\" at ")
	expect_line(t, got, "text field \"Name\" value \"Jack\" desc \"Required\" at ")
	expect_line(t, got, "tab list \"\" at ")
	expect_line(t, got, "\n  tab \"Flights\" at ")
	expect_line(t, got, "\n  tab \"Hotels\" selected at ")
	testing.expect(t, !strings.contains(got, "dialog"), got)

	// Clearing the checkbox and picking the first tab show in the tree.
	testing.expect(t, ui.probe_click(&p, "Agree"))
	testing.expect(t, ui.probe_click(&p, "Flights"))
	got = ui.probe_semantics(&p, context.temp_allocator)
	expect_line(t, got, "checkbox \"Agree\" at ")
	expect_line(t, got, "\n  tab \"Flights\" selected focused at ")
	expect_line(t, got, "\n  tab \"Hotels\" at ")
}

@(test)
escape_closes_a_dialog_without_focus :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Sem_Model {
		dialog = true,
	}
	defer ui.text_destroy(&m.name)
	p: ui.Probe
	ui.probe_init(&p, sem_view, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_frame(&p) // the dialog's interest is in the routed frame
	got := ui.probe_semantics(&p, context.temp_allocator)
	expect_line(t, got, "dialog \"Discard draft?\" modal at ")
	expect_line(t, got, "\n  heading \"Discard draft?\" at ")
	expect_line(t, got, "\n  button \"Discard\" at ")
	testing.expect(t, !strings.contains(got, "focused"), got)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.dialog, "Escape did not close the dialog")
}
