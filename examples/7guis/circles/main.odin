/*
circles is 7GUIs task 6: a canvas where a click adds a circle, the circle
under the pointer is filled, and a right click on it opens a menu whose
item opens a slider beside it that resizes it; Undo and Redo step through the
creations and resizes, one opening of the slider being one step
(https://eugenkiss.github.io/7guis/tasks#circle). The canvas is a widget
written here from jm:ui's core: an input area, its events and paint ops.
Undo is a list of actions and a cursor into it, kept in the model.
*/
package main

import "core:fmt"
import "core:math/linalg"

import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../shell"

CANVAS :: ops.Size{440, 300}
DIAMETER :: 40
MIN_DIAMETER :: 4
MAX_DIAMETER :: 200

Circle :: struct {
	center:   ops.Point,
	diameter: f32,
}

// Action is one undoable step: a circle made, or one resized.
Action :: union {
	Circle_Added,
	Circle_Resized,
}

Circle_Added :: struct {
	circle: Circle,
}

Circle_Resized :: struct {
	index:    int,
	from, to: f32,
}

Model :: struct {
	circles:     [dynamic]Circle,
	history:     [dynamic]Action,
	done:        int, // the actions in history applied; those after are redoable
	pointer:     ops.Point, // in the canvas
	inside:      bool, // the pointer is over the canvas
	menu:        bool,
	menu_at:     ops.Point,
	menu_for:    int, // the circle the menu was opened on
	adjusting:   int, // the circle the slider resizes, -1 for none
	slider_open: bool,
	original:    f32, // its diameter when the slider opened
}

model_init :: proc(m: ^Model) {
	m.adjusting = -1
}

model_destroy :: proc(m: ^Model) {
	delete(m.circles)
	delete(m.history)
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	page := shell.page_open(gtx)
	defer ui.close(&page)
	col := ui.column_open(gtx, gap = 12, align = .Center)
	defer ui.close(&col)

	{
		row := ui.row_open(gtx, gap = 8)
		defer ui.close(&row)
		if fluent.button(gtx, "Undo", state = m.done > 0 ? .Live : .Disabled) {
			undo(m)
		}
		if fluent.button(gtx, "Redo", state = m.done < len(m.history) ? .Live : .Disabled) {
			redo(m)
		}
	}
	canvas(gtx, m)
}

// canvas draws the circles and takes the clicks: a left click on empty
// canvas adds a circle, a right click on the selected one opens its menu.
canvas :: proc(gtx: ^ui.Ctx, m: ^Model) {
	p := ui.widget_open(gtx)
	area := ops.Rect{0, 0, CANVAS.x, CANVAS.y}
	for e in ui.events(gtx, p.id) {
		#partial switch e.kind {
		case .Move, .Enter:
			m.pointer, m.inside = e.pos, true
		case .Leave:
			m.inside = false
		case .Press:
			m.pointer, m.inside = e.pos, true
			press(m, e.button)
		}
	}
	// While the popover shows, the circle it resizes stays selected.
	selected := m.adjusting >= 0 ? m.adjusting : under_pointer(m)

	ops.fill(gtx.scene, area, fluent.color(.Neutral_Background1))
	ops.clip_push(gtx.scene, area)
	for c, i in m.circles {
		r := c.diameter / 2
		disc := ops.Ellipse{{c.center.x - r, c.center.y - r, c.diameter, c.diameter}}
		if i == selected {
			ops.fill(gtx.scene, disc, fluent.color(.Neutral_Background5))
		}
		ops.stroke(gtx.scene, disc, fluent.color(.Neutral_Foreground1), {width = 1})
	}
	ops.clip_pop(gtx.scene)
	ops.stroke(gtx.scene, area, fluent.color(.Neutral_Stroke1), {width = 1})
	ops.input_area(gtx.scene, p.id, area, {.Press, .Move, .Enter, .Leave})
	ops.tag(gtx.scene, p.id, "Canvas")

	if fluent.menu(gtx, &m.menu, ops.Rect{m.menu_at.x, m.menu_at.y, 0, 0}) {
		if fluent.menu_item(gtx, "Adjust diameter...") {
			m.adjusting = m.menu_for
			m.original = m.circles[m.adjusting].diameter
			m.slider_open = true
		}
	}
	adjust(gtx, m)
	ui.widget_close(gtx, &p, {size = CANVAS})
}

press :: proc(m: ^Model, button: ui.Button) {
	hit := under_pointer(m)
	#partial switch button {
	case .Left:
		if hit < 0 {
			act(m, Circle_Added{{m.pointer, DIAMETER}})
		}
	case .Right:
		if hit >= 0 {
			m.menu, m.menu_at, m.menu_for = true, m.pointer, hit
		}
	}
}

// under_pointer is the circle whose centre is nearest the pointer among
// those the pointer is inside, or -1.
under_pointer :: proc(m: ^Model) -> int {
	if !m.inside {
		return -1
	}
	best, best_d := -1, max(f32)
	for c, i in m.circles {
		d := linalg.distance(c.center, m.pointer)
		if d < c.diameter / 2 && d < best_d {
			best, best_d = i, d
		}
	}
	return best
}

// adjust opens a popover beside the circle the menu chose, whose slider
// resizes it live; when the popover closes, by a press outside it or by
// Escape, the whole change is recorded as one action. The popover is
// anchored to the circle as it was when it opened, so it holds still
// while the circle grows under the slider.
adjust :: proc(gtx: ^ui.Ctx, m: ^Model) {
	if m.adjusting < 0 {
		return
	}
	c := &m.circles[m.adjusting]
	r := m.original / 2
	{
		at := ui.overlay_open(gtx, {c.center.x - r, c.center.y - r})
		defer ui.close(&at)
		if fluent.popover(gtx, &m.slider_open, {m.original, m.original}, .After, arrow = true) {
			col := ui.column_open(gtx, gap = 8)
			defer ui.close(&col)
			fluent.text(gtx, fmt.tprintf("Adjust diameter of circle at (%.0f, %.0f).", c.center.x, c.center.y), fluent.popover_fg())
			fluent.slider(gtx, &c.diameter, MIN_DIAMETER, MAX_DIAMETER, length = 200, name = "Diameter")
		}
	}
	if !m.slider_open {
		to := c.diameter
		if to != m.original {
			c.diameter = m.original
			act(m, Circle_Resized{m.adjusting, m.original, to})
		}
		m.adjusting = -1
	}
}

// act applies a, records it after the actions done, and drops the ones
// that were undone: a new step forks history and the old future goes.
act :: proc(m: ^Model, a: Action) {
	resize(&m.history, m.done)
	append(&m.history, a)
	redo(m)
}

undo :: proc(m: ^Model) {
	m.done -= 1
	switch a in m.history[m.done] {
	case Circle_Added:
		pop(&m.circles)
	case Circle_Resized:
		m.circles[a.index].diameter = a.from
	}
}

redo :: proc(m: ^Model) {
	switch a in m.history[m.done] {
	case Circle_Added:
		append(&m.circles, a.circle)
	case Circle_Resized:
		m.circles[a.index].diameter = a.to
	}
	m.done += 1
}

main :: proc() {
	m: Model
	model_init(&m)
	defer model_destroy(&m)
	shell.run("Circle Drawer", 480, 390, view, &m)
}
