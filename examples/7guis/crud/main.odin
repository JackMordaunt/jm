/*
crud is 7GUIs task 5: a list of people filtered by a surname prefix, the
name and surname of the one to create or update, and Create, Update and
Delete (https://eugenkiss.github.io/7guis/tasks#crud). The filtered view
is computed in the frame from the list and the prefix, so there is no
second list to keep in step with the first.
*/
package main

import "core:fmt"
import "core:strings"

import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../shell"

LIST_WIDTH :: 220
LIST_HEIGHT :: 160
FIELD_WIDTH :: 160

Person :: struct {
	name, surname: string,
}

Model :: struct {
	people:                [dynamic]Person,
	selected:              int, // into people, -1 for none
	filter, name, surname: ui.Text_State,
	scroll:                ui.Scroll_Offset,
}

model_init :: proc(m: ^Model) {
	m.selected = -1
	for p in ([]Person{{"Hans", "Emil"}, {"Max", "Mustermann"}, {"Roman", "Tisch"}}) {
		append(&m.people, Person{strings.clone(p.name), strings.clone(p.surname)})
	}
}

model_destroy :: proc(m: ^Model) {
	for &p in m.people {
		person_destroy(&p)
	}
	delete(m.people)
	ui.text_destroy(&m.filter)
	ui.text_destroy(&m.name)
	ui.text_destroy(&m.surname)
}

person_destroy :: proc(p: ^Person) {
	delete(p.name)
	delete(p.surname)
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	page := shell.page_open(gtx)
	defer ui.close(&page)
	col := ui.column_open(gtx, gap = 12)
	defer ui.close(&col)

	{
		row := ui.row_open(gtx, gap = 8, align = .Center)
		defer ui.close(&row)
		fluent.label(gtx, "Filter prefix:")
		fluent.input(gtx, &m.filter, width = FIELD_WIDTH, name = "Filter prefix")
	}
	{
		row := ui.row_open(gtx, gap = 16)
		defer ui.close(&row)
		people(gtx, m)
		form := ui.grid_open(gtx, {{}, {}}, column_gap = 8, row_gap = 8, align = .Center)
		defer ui.close(&form)
		fluent.label(gtx, "Name:")
		fluent.input(gtx, &m.name, width = FIELD_WIDTH, name = "Name")
		fluent.label(gtx, "Surname:")
		fluent.input(gtx, &m.surname, width = FIELD_WIDTH, name = "Surname")
	}
	row := ui.row_open(gtx, gap = 8)
	defer ui.close(&row)
	chosen := m.selected >= 0 ? fluent.Interaction.Live : .Disabled
	if fluent.button(gtx, "Create") {
		append(&m.people, from_fields(m))
		m.selected = len(m.people) - 1
	}
	if fluent.button(gtx, "Update", state = chosen) {
		person_destroy(&m.people[m.selected])
		m.people[m.selected] = from_fields(m)
	}
	if fluent.button(gtx, "Delete", state = chosen) {
		person_destroy(&m.people[m.selected])
		ordered_remove(&m.people, m.selected)
		m.selected = -1
	}
}

// people lists the people whose surname starts with the filter, as
// "Surname, Name"; choosing one selects it and copies it into the fields.
people :: proc(gtx: ^ui.Ctx, m: ^Model) {
	box := ui.sized_open(gtx, {min = {LIST_WIDTH, LIST_HEIGHT}, max = {LIST_WIDTH, LIST_HEIGHT}})
	defer ui.close(&box)
	frame := ops.Round_Rect{{0.5, 0.5, LIST_WIDTH - 1, LIST_HEIGHT - 1}, 4}
	ops.stroke(gtx.scene, frame, fluent.color(.Neutral_Stroke1), {width = 1})
	pad := ui.inset_open(gtx, ui.pad_all(4))
	defer ui.close(&pad)
	scroll := ui.scroll_box_open(gtx, offset = &m.scroll)
	defer ui.close(&scroll)

	prefix := ui.text_string(&m.filter)
	shown := -1 // the selection's index among the items shown
	l := fluent.list_open(gtx, .Single, &shown)
	defer fluent.list_close(&l)
	for p, i in m.people {
		if !strings.has_prefix(p.surname, prefix) {
			continue
		}
		if i == m.selected {
			shown = l.next
		}
		if fluent.list_item(gtx, &l, fmt.tprintf("%s, %s", p.surname, p.name), key = u64(i) + 1) {
			m.selected = i
			ui.text_set(&m.name, p.name)
			ui.text_set(&m.surname, p.surname)
		}
	}
}

from_fields :: proc(m: ^Model) -> Person {
	return {strings.clone(ui.text_string(&m.name)), strings.clone(ui.text_string(&m.surname))}
}

main :: proc() {
	m: Model
	model_init(&m)
	defer model_destroy(&m)
	shell.run("CRUD", 480, 290, view, &m)
}
