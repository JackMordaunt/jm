/*
temperature is 7GUIs task 2: two fields, Celsius and Fahrenheit, each
updating the other as it is typed in, and neither touching the other while
its text is not a number (https://eugenkiss.github.io/7guis/tasks#temp).
The two-way binding is two if statements: whichever field changed this
frame writes the other.
*/
package main

import "core:fmt"
import "core:strconv"
import "core:strings"

import "jm:ui"
import "jm:ui/fluent"

import "../shell"

Model :: struct {
	celsius, fahrenheit: ui.Text_State,
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	page := shell.page_open(gtx)
	defer ui.close(&page)
	row := ui.row_open(gtx, gap = 8, align = .Center)
	defer ui.close(&row)

	if fluent.input(gtx, &m.celsius, invalid = !is_number_or_empty(&m.celsius), width = 100, name = "Celsius").changed {
		if c, ok := strconv.parse_f64(ui.text_string(&m.celsius)); ok {
			ui.text_set(&m.fahrenheit, format_temperature(c * 9 / 5 + 32))
		}
	}
	fluent.label(gtx, "Celsius =")
	if fluent.input(gtx, &m.fahrenheit, invalid = !is_number_or_empty(&m.fahrenheit), width = 100, name = "Fahrenheit").changed {
		if f, ok := strconv.parse_f64(ui.text_string(&m.fahrenheit)); ok {
			ui.text_set(&m.celsius, format_temperature((f - 32) * 5 / 9))
		}
	}
	fluent.label(gtx, "Fahrenheit")
}

// is_number_or_empty is whether a field's text is a number, or empty: an empty field
// is not yet an error.
is_number_or_empty :: proc(s: ^ui.Text_State) -> bool {
	_, ok := strconv.parse_f64(ui.text_string(s))
	return ok || len(s.buf) == 0
}

// format_temperature formats a temperature with at most two decimals: 37.78, 212.
format_temperature :: proc(v: f64) -> string {
	s := fmt.tprintf("%.2f", v)
	s = strings.trim_right(s, "0")
	return strings.trim_suffix(s, ".")
}

model_destroy :: proc(m: ^Model) {
	ui.text_destroy(&m.celsius)
	ui.text_destroy(&m.fahrenheit)
}

main :: proc() {
	m: Model
	defer model_destroy(&m)
	shell.run("Temperature Converter", 460, 70, view, &m)
}
