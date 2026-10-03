package main

import "core:testing"

import "jm:ui"

@(test)
time_runs_to_the_duration_and_stops :: proc(t: ^testing.T) {
	m := Model{duration = 2}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {380, 180})
	defer ui.probe_destroy(&p)

	ui.probe_advance(&p, 10, 0.1)
	testing.expect(t, abs(m.elapsed - 1) < 0.15)
	testing.expect(t, p.wants_frame)
	ui.probe_advance(&p, 30, 0.1)
	testing.expect_value(t, m.elapsed, f32(2))
	testing.expect(t, ui.probe_tagged(&p, "2.0s"))
	testing.expect(t, !p.wants_frame) // stopped: the window sleeps
}

@(test)
a_longer_duration_restarts_it_and_reset_zeroes_it :: proc(t: ^testing.T) {
	m := Model{duration = 1}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {380, 180})
	defer ui.probe_destroy(&p)

	ui.probe_advance(&p, 20, 0.1)
	testing.expect_value(t, m.elapsed, f32(1))
	testing.expect(t, ui.probe_drag(&p, "Duration", 60, 0))
	testing.expect(t, m.duration > 1)
	ui.probe_advance(&p, 5, 0.1)
	testing.expect(t, m.elapsed > 1)

	testing.expect(t, ui.probe_click(&p, "Reset"))
	testing.expect(t, m.elapsed < 0.15)
}
