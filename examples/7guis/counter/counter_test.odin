package main

import "core:testing"

import "jm:ui"

@(test)
each_click_adds_one :: proc(t: ^testing.T) {
	m: Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {260, 70})
	defer ui.probe_destroy(&p)

	testing.expect(t, ui.probe_tagged(&p, "0"))
	testing.expect(t, ui.probe_click(&p, "Count"))
	testing.expect(t, ui.probe_click(&p, "Count"))
	testing.expect_value(t, m.count, 2)
	ui.probe_frame(&p) // the label drew before the click landed; the next frame shows it
	testing.expect(t, ui.probe_tagged(&p, "2"))
}
