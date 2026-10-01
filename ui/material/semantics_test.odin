package material

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/base"

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
	city:        ui.Text_State,
	city_open:   bool,
	date:        Date,
	date_view:   Date,
}

@(private = "file")
SEM_CITIES := [?]string{"Lima", "Oslo"}

@(private = "file")
SEM_TODAY :: Date{2026, 10, 1}

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
	// The slider has no text of its own: the caption above names it.
	_, caption := base.label(gtx, "Level")
	slider(gtx, &m.level, 0, 100, labelled_by = caption)
	text_field(gtx, &m.name, "Name", supporting = "Required")
	tabs(gtx, SEM_TABS[:], &m.tab)
	plain_tooltip(gtx, "Saves the draft")
	autocomplete(gtx, &m.city, "City", SEM_CITIES[:], &m.city_open)
	date_picker(gtx, &m.date, &m.date_view, SEM_TODAY)
	dialog(gtx, &m.dialog, {400, 1400}, "Discard draft?", "Your changes will be lost.", SEM_ACTIONS[:])
}

@(private = "file")
expect_line :: proc(t: ^testing.T, got, want: string, loc := #caller_location) {
	testing.expect(t, strings.contains(got, want), got, loc = loc)
}

@(test)
components_declare_their_roles :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Sem_Model {
		agree     = true,
		wifi      = true,
		level     = 50,
		tab       = 1,
		city_open = true,
		date      = {2026, 10, 14},
	}
	ui.text_set(&m.name, "Jack")
	defer ui.text_destroy(&m.name)
	ui.text_set(&m.city, "Oslo")
	defer ui.text_destroy(&m.city)
	p: ui.Probe
	ui.probe_init(&p, sem_view, &m, {400, 1400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	got := ui.probe_semantics(&p, context.temp_allocator)
	expect_line(t, got, "button \"Save\" at ")
	expect_line(t, got, "checkbox \"Agree\" checked at ")
	expect_line(t, got, "switch \"Wi-Fi\" checked at ")
	// The slider reads the caption's label through labelled_by.
	expect_line(t, got, "slider \"Level\" value \"50\" at ")
	expect_line(t, got, "text field \"Name\" value \"Jack\" desc \"Required\" at ")
	expect_line(t, got, "tab list \"\" at ")
	expect_line(t, got, "\n  tab \"Flights\" at ")
	expect_line(t, got, "\n  tab \"Hotels\" selected at ")
	// A tooltip is a root of its own, with no bare group around it.
	expect_line(t, got, "\ntooltip \"Saves the draft\" at ")
	testing.expect(t, !strings.contains(got, "group \"\""), got)
	// The autocomplete's popup is a list box of options, the typed one selected.
	expect_line(t, got, "combo box \"City\" value \"Oslo\"")
	expect_line(t, got, "\nlist box \"City\" at ")
	expect_line(t, got, "\n  option \"Oslo\" selected at ")
	// The date picker's month is a grid of day cells under the picker.
	expect_line(t, got, "\ngroup \"Wed, Oct 14\" desc \"Select date\" at ")
	expect_line(t, got, "\n  grid \"October 2026\" at ")
	expect_line(t, got, "\n    grid cell \"2026-10-01\" at ")
	expect_line(t, got, "\n    grid cell \"2026-10-14\" selected at ")
	expect_line(t, got, "\n    grid cell \"2026-10-31\" at ")
	testing.expect(t, !strings.contains(got, "dialog"), got)

	// Escape reaches the combo box without focus and closes its list box;
	// while it is open, its scrim would take the clicks below.
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.city_open, "Escape did not close the list box")

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
	ui.probe_init(&p, sem_view, &m, {400, 1400}, allocator = context.temp_allocator)
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
