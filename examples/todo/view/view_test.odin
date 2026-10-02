package todo_view

import "core:testing"

import "jm:ui"

import "../shapes"

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	p: ui.Probe
	ui.probe_init(&p, view, m, {800, 600})
	return p
}

@(private = "file")
two :: proc(p: ^ui.Probe) {
	ui.probe_deliver(p, shapes.Todos{filter = .All}, shapes.Todos_Result{items = {{1, "milk", false}, {2, "eggs", true}}, active = 1, completed = 1})
	ui.probe_frame(p)
}

@(test)
first_frame_needs_the_list_and_the_problems :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_needs_q(&p, shapes.Todos{filter = .All}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Problems{}))
	testing.expect_value(t, len(ui.probe_needs(&p)), 2)
	testing.expect(t, !ui.probe_tagged(&p, "Delete milk"))
}

@(test)
rows_draw_from_the_delivered_shape_and_emit_commands :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	two(&p)
	testing.expect(t, ui.probe_tagged(&p, "Delete milk"))
	testing.expect(t, ui.probe_tagged(&p, "Clear completed"))
	testing.expect(t, ui.probe_click(&p, "Delete milk"))
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 1)
	d, ok := ui.command_as(cmds[0], shapes.Delete)
	testing.expect(t, ok)
	testing.expect_value(t, d.id, i64(1))

	testing.expect(t, ui.probe_click(&p, "Clear completed"))
	testing.expect(t, ui.command_is(ui.probe_commands(&p)[0], shapes.Clear_Completed))
}

@(test)
enter_in_the_entry_is_an_add_and_clears_the_text :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	two(&p)
	testing.expect(t, ui.probe_click(&p, "New todo"))
	ui.probe_type(&p, "bread")
	ui.probe_key(&p, .Enter)
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 1)
	a, ok := ui.command_as(cmds[0], shapes.Add)
	testing.expect(t, ok)
	testing.expect_value(t, a.title, "bread")
	testing.expect_value(t, ui.text_string(&m.entry), "")
}

@(test)
a_filter_change_keeps_the_old_page_until_the_new_one_lands :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	two(&p)
	testing.expect(t, ui.probe_click(&p, "Completed"))
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, m.filter, shapes.Filter.Completed)
	// Both pages are needed: the new one to come, the old one to keep
	// drawing from meanwhile, so the rows never flicker.
	testing.expect(t, ui.probe_needs_q(&p, shapes.Todos{filter = .Completed}))
	testing.expect(t, ui.probe_needs_q(&p, shapes.Todos{filter = .All}))
	testing.expect(t, ui.probe_tagged(&p, "Delete milk"))
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
	ui.probe_deliver(&p, shapes.Todos{filter = .Completed}, shapes.Todos_Result{items = {{2, "eggs", true}}, active = 1, completed = 1})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Delete eggs"))
	testing.expect(t, !ui.probe_tagged(&p, "Delete milk"))
	// The frame that draws the new page is the one that lets the old go.
	testing.expect(t, !ui.probe_needs_q(&p, shapes.Todos{filter = .All}))
	testing.expect_value(t, len(ui.probe_dropped(&p)), 1)
}

@(test)
loading_shows_only_after_a_perceptible_wait :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	// The first frames have no page and say nothing about it; they ask
	// for a frame at the deadline instead.
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
	testing.expect(t, p.wants_frame)
	ui.probe_advance(&p, 2, 0.05)
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
	ui.probe_advance(&p, 2, 0.05)
	testing.expect(t, ui.probe_tagged(&p, "Loading…"))
	// A page ends the wait; the next wait starts afresh.
	two(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
	testing.expect_value(t, m.waiting, 0)
}

@(test)
a_problem_shows_until_dismissed :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	two(&p)
	ui.probe_deliver(&p, shapes.Problems{}, shapes.Problems_Result{items = {{7, "A todo needs a title."}}})
	ui.probe_frame(&p)
	names := ui.probe_names(&p)
	found := false
	for n in names {
		if n == "Dismiss" {
			found = true
		}
	}
	testing.expect(t, found, "the message bar's dismiss button is tagged")
	testing.expect(t, ui.probe_click(&p, "Dismiss"))
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 1)
	d, ok := ui.command_as(cmds[0], shapes.Dismiss)
	testing.expect(t, ok)
	testing.expect_value(t, d.id, u64(7))
}

@(test)
editing_a_row_submits_an_edit :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	two(&p)
	testing.expect(t, ui.probe_click(&p, "Edit milk"))
	testing.expect_value(t, m.editing, i64(1))
	ui.probe_frame(&p) // the frame after the click draws the field
	testing.expect(t, ui.probe_click(&p, "Edit todo"))
	ui.probe_type(&p, "!")
	ui.probe_key(&p, .Enter)
	cmds := ui.probe_commands(&p)
	testing.expect_value(t, len(cmds), 1)
	e, ok := ui.command_as(cmds[0], shapes.Edit)
	testing.expect(t, ok)
	testing.expect_value(t, e.id, i64(1))
	testing.expect_value(t, e.title, "milk!")
	testing.expect_value(t, m.editing, i64(0))
}
