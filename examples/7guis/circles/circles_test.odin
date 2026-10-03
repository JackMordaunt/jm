package main

import "core:testing"

import "jm:ui"
import "jm:ui/ops"

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	model_init(m)
	p: ui.Probe
	ui.probe_init(&p, view, m, {480, 390})
	return p
}

// at is a point on the canvas, in the window's device space.
@(private = "file")
at :: proc(p: ^ui.Probe, x, y: f32) -> ops.Point {
	c := ui.probe_bounds(p, "Canvas")
	return {c.x + x, c.y + y}
}

@(test)
clicks_add_circles_and_undo_redo_step_through_them :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	testing.expect(t, !ui.probe_click(&p, "Undo")) // nothing to undo: disabled
	ui.probe_click_at(&p, at(&p, 100, 100))
	ui.probe_click_at(&p, at(&p, 300, 200))
	testing.expect_value(t, len(m.circles), 2)
	ui.probe_click_at(&p, at(&p, 105, 100)) // inside the first: selects, adds nothing
	testing.expect_value(t, len(m.circles), 2)
	testing.expect_value(t, under_pointer(&m), 0)

	testing.expect(t, ui.probe_click(&p, "Undo"))
	testing.expect_value(t, len(m.circles), 1)
	testing.expect(t, ui.probe_click(&p, "Redo"))
	testing.expect_value(t, len(m.circles), 2)
	testing.expect_value(t, m.circles[1].center, ops.Point{300, 200})

	// A new circle after an undo drops the undone one for good.
	testing.expect(t, ui.probe_click(&p, "Undo"))
	ui.probe_click_at(&p, at(&p, 200, 50))
	ui.probe_frame(&p)
	testing.expect_value(t, len(m.circles), 2)
	testing.expect(t, !ui.probe_click(&p, "Redo"))
}

@(test)
a_slider_resizes_live_and_undoes_as_one_step :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	ui.probe_click_at(&p, at(&p, 100, 100))
	ui.probe_click_at(&p, at(&p, 300, 100), .Right) // on no circle: no menu
	testing.expect(t, !ui.probe_tagged(&p, "Adjust diameter..."))
	ui.probe_click_at(&p, at(&p, 100, 100), .Right)
	testing.expect(t, ui.probe_click(&p, "Adjust diameter..."))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Diameter"))

	// Two drags on the slider are two changes, yet one step to undo.
	testing.expect(t, ui.probe_drag(&p, "Diameter", 40, 0))
	testing.expect(t, ui.probe_drag(&p, "Diameter", 40, 0))
	grown := m.circles[0].diameter
	testing.expect(t, grown > DIAMETER)
	testing.expect_value(t, len(m.history), 1) // nothing recorded while it is open
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Diameter"))
	testing.expect_value(t, len(m.history), 2)
	testing.expect_value(t, m.circles[0].diameter, grown)

	testing.expect(t, ui.probe_click(&p, "Undo"))
	testing.expect_value(t, m.circles[0].diameter, f32(DIAMETER))
	testing.expect(t, ui.probe_click(&p, "Redo"))
	testing.expect_value(t, m.circles[0].diameter, grown)
}

@(test)
a_press_outside_closes_the_slider_and_adds_no_circle :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)

	ui.probe_click_at(&p, at(&p, 100, 100))
	ui.probe_click_at(&p, at(&p, 100, 100), .Right)
	testing.expect(t, ui.probe_click(&p, "Adjust diameter..."))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Diameter"))
	ui.probe_click_at(&p, at(&p, 400, 280))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Diameter"))
	testing.expect_value(t, len(m.circles), 1)
}
