package main

import "core:testing"

import "jm:ui"

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	model_init(m)
	p: ui.Probe
	ui.probe_init(&p, view, m, {420, 260})
	return p
}

@(private = "file")
retype :: proc(p: ^ui.Probe, field, text: string) {
	ui.probe_click(p, field)
	ui.probe_key(p, .A, {ui.SHORTCUT})
	ui.probe_type(p, text)
}

@(test)
a_one_way_flight_books_with_the_return_date_disabled :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, !ui.probe_click(&p, "Return date")) // disabled: no area to click
	testing.expect(t, ui.probe_click(&p, "Book"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Booked"))
	testing.expect_value(t, m.booked, "You have booked a one-way flight on 2026-10-03.")
}

@(test)
a_return_flight_cannot_come_back_before_it_leaves :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, ui.probe_click(&p, "Flight type"))
	testing.expect(t, ui.probe_click(&p, "return flight"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.kind, RETURN)

	retype(&p, "Return date", "2026-10-01")
	testing.expect(t, !ui.probe_click(&p, "Book"))
	retype(&p, "Return date", "2026-10-10")
	testing.expect(t, ui.probe_click(&p, "Book"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.booked, "You have booked a return flight from 2026-10-03 to 2026-10-10.")
}

@(test)
a_date_that_does_not_parse_disables_book :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	retype(&p, "Start date", "2026-02-30")
	testing.expect(t, !is_date(&m.start))
	testing.expect(t, !ui.probe_click(&p, "Book"))
	retype(&p, "Start date", "2026-02-28")
	testing.expect(t, ui.probe_click(&p, "Book"))
}
