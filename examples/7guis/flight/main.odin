/*
flight is 7GUIs task 3: a one-way or return flight with a start date and,
for a return, a return date no earlier than it; the return date's field is
disabled for a one-way flight, a field whose text is not a date is marked
invalid, and Book is disabled until the booking is valid
(https://eugenkiss.github.io/7guis/tasks#flight). Dates are ISO 8601,
YYYY-MM-DD, as fluent.parse_date reads them. Every constraint is computed
from the text in the frame; nothing is cached to fall out of step.
*/
package main

import "core:fmt"

import "jm:ui"
import "jm:ui/fluent"

import "../shell"

KINDS := []string{"one-way flight", "return flight"}

ONE_WAY :: 0
RETURN :: 1

WIDTH :: 260

Model :: struct {
	kind:        int,
	start, back: ui.Text_State,
	booked:      string, // the confirmation shown, "" for none
	booked_buf:  [128]u8,
}

model_init :: proc(m: ^Model) {
	ui.text_set(&m.start, "2026-10-03")
	ui.text_set(&m.back, "2026-10-03")
}

model_destroy :: proc(m: ^Model) {
	ui.text_destroy(&m.start)
	ui.text_destroy(&m.back)
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	page := shell.page_open(gtx)
	defer ui.close(&page)
	col := ui.column_open(gtx, gap = 8)
	defer ui.close(&col)

	fluent.dropdown(gtx, KINDS, &m.kind, width = WIDTH, name = "Flight type")
	fluent.input(gtx, &m.start, invalid = !is_date(&m.start), width = WIDTH, name = "Start date")
	fluent.input(gtx, &m.back, invalid = !is_date(&m.back), width = WIDTH, name = "Return date", state = m.kind == RETURN ? .Live : .Disabled)

	start, start_ok := fluent.parse_date(ui.text_string(&m.start))
	back, back_ok := fluent.parse_date(ui.text_string(&m.back))

	bookable := start_ok && (m.kind == ONE_WAY || back_ok && !fluent.date_less(back, start))
	if fluent.button(gtx, "Book", .Primary, state = bookable ? .Live : .Disabled) {
		if m.kind == ONE_WAY {
			m.booked = fmt.bprintf(m.booked_buf[:], "You have booked a one-way flight on %s.", ui.text_string(&m.start))
		} else {
			m.booked = fmt.bprintf(m.booked_buf[:], "You have booked a return flight from %s to %s.", ui.text_string(&m.start), ui.text_string(&m.back))
		}
	}
	if m.booked != "" {
		if _, dismissed := fluent.message_bar(gtx, .Success, "Booked", m.booked, dismissable = true); dismissed {
			m.booked = ""
		}
	}
}

is_date :: proc(s: ^ui.Text_State) -> bool {
	_, ok := fluent.parse_date(ui.text_string(s))
	return ok
}

main :: proc() {
	m: Model
	model_init(&m)
	defer model_destroy(&m)
	shell.run("Flight Booker", 420, 260, view, &m)
}
