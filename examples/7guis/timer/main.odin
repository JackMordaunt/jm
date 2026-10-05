/*
timer is 7GUIs task 4: a gauge and a count of the time elapsed, a slider
for the duration, and a reset button; the time runs while it is short of
the duration, so stretching the duration past it starts it again
(https://eugenkiss.github.io/7guis/tasks#timer). Time is the frame's dt:
the frame asks for the next one while the timer runs and the window
sleeps once it stops, and a test steps time with ui.probe_advance instead
of waiting for a clock.
*/
package main

import "core:fmt"

import "jm:ui"
import "jm:ui/fluent"

import "../shell"

MAX_DURATION :: 30
WIDTH :: 240

Model :: struct {
	elapsed:  f32, // seconds
	duration: f32, // seconds
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	page := shell.page_open(gtx)
	defer ui.close(&page)
	ui.grid(gtx, {{}, {}}, column_gap = 12, row_gap = 12, align = .Center)

	if m.elapsed < m.duration {
		m.elapsed = min(m.elapsed + gtx.dt, m.duration)
		ui.request_frame(gtx)
	}
	fluent.label(gtx, "Elapsed Time:")
	{
		ui.row(gtx, gap = 8, align = .Center)
		fluent.progress_bar(gtx, m.elapsed, max(m.duration, 1e-3), width = WIDTH - 48, name = "Elapsed")
		fluent.text(gtx, fmt.tprintf("%.1fs", m.elapsed), fluent.color(.Neutral_Foreground1))
	}
	fluent.label(gtx, "Duration:")
	fluent.slider(gtx, &m.duration, 0, MAX_DURATION, length = WIDTH, name = "Duration")
	ui.grid_span(gtx)
	if fluent.button(gtx, "Reset", .Primary) {
		m.elapsed = 0
	}
}

main :: proc() {
	m := Model{duration = 10}
	shell.run("Timer", 380, 180, view, &m)
}
