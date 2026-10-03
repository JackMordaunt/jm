package main

import "core:testing"

import "jm:ui"

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	p: ui.Probe
	ui.probe_init(&p, view, m, {460, 70})
	return p
}

@(test)
typing_either_field_converts_into_the_other :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, ui.probe_click(&p, "Celsius"))
	ui.probe_type(&p, "100")
	testing.expect_value(t, ui.text_string(&m.fahrenheit), "212")

	testing.expect(t, ui.probe_click(&p, "Fahrenheit"))
	ui.probe_key(&p, .A, {ui.SHORTCUT})
	ui.probe_type(&p, "-40")
	testing.expect_value(t, ui.text_string(&m.celsius), "-40")
	ui.probe_type(&p, ".5")
	testing.expect_value(t, ui.text_string(&m.celsius), "-40.28")
}

@(test)
text_that_is_not_a_number_leaves_the_other_field_alone :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, ui.probe_click(&p, "Celsius"))
	ui.probe_type(&p, "37")
	testing.expect_value(t, ui.text_string(&m.fahrenheit), "98.6")
	ui.probe_type(&p, "x")
	testing.expect_value(t, ui.text_string(&m.celsius), "37x")
	testing.expect_value(t, ui.text_string(&m.fahrenheit), "98.6")
	testing.expect(t, !is_number_or_empty(&m.celsius))
	testing.expect(t, is_number_or_empty(&m.fahrenheit))
}
