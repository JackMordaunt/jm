package main

import "core:testing"

import "jm:ui"

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	model_init(m)
	p: ui.Probe
	ui.probe_init(&p, view, m, {480, 290})
	return p
}

@(private = "file")
retype :: proc(p: ^ui.Probe, field, text: string) {
	ui.probe_click(p, field)
	ui.probe_key(p, .A, {ui.SHORTCUT})
	ui.probe_type(p, text)
}

@(test)
the_filter_shows_surnames_with_its_prefix :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, ui.probe_tagged(&p, "Emil, Hans"))
	retype(&p, "Filter prefix", "M")
	testing.expect(t, ui.probe_tagged(&p, "Mustermann, Max"))
	testing.expect(t, !ui.probe_tagged(&p, "Emil, Hans"))
	testing.expect(t, !ui.probe_tagged(&p, "Tisch, Roman"))
}

@(test)
create_update_and_delete_act_on_the_selection :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, !ui.probe_click(&p, "Update")) // nothing selected: disabled
	retype(&p, "Name", "Ada")
	retype(&p, "Surname", "Lovelace")
	testing.expect(t, ui.probe_click(&p, "Create"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Lovelace, Ada"))

	testing.expect(t, ui.probe_click(&p, "Tisch, Roman"))
	testing.expect_value(t, ui.text_string(&m.name), "Roman")
	retype(&p, "Name", "Rosa")
	testing.expect(t, ui.probe_click(&p, "Update"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Tisch, Rosa"))
	testing.expect(t, !ui.probe_tagged(&p, "Tisch, Roman"))

	testing.expect(t, ui.probe_click(&p, "Delete"))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Tisch, Rosa"))
	testing.expect_value(t, len(m.people), 3)
	testing.expect(t, !ui.probe_click(&p, "Delete")) // the selection went with it
}
