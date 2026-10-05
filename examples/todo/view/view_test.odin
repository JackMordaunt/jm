package todo_view

import "core:testing"

import "jm:ui"

import "../query"
import "../todo"

@(private = "file")
open :: proc(m: ^Model) -> ui.Probe {
	p: ui.Probe
	ui.probe_init(&p, view, m, {800, 600})
	return p
}

// command_of decodes a frame's command as the host does; nil if it is not
// a todo.Command.
@(private = "file")
command_of :: proc(c: ui.Command) -> todo.Command {
	cmd, _ := ui.command_as(c, todo.Command)
	return cmd
}

@(private = "file")
two :: proc(p: ^ui.Probe) {
	ui.probe_deliver(p, query.Todos{filter = .All}, query.Todos_Result{items = {{1, "milk", false}, {2, "eggs", true}}, active = 1, completed = 1})
	ui.probe_frame(p)
}

@(test)
first_frame_needs_the_list_and_the_problems :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_needs_q(&p, query.Todos{filter = .All}))
	testing.expect(t, ui.probe_needs_q(&p, query.Problems{}))
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
	testing.expect(t, command_of(cmds[0]) == todo.Delete{id = 1})

	testing.expect(t, ui.probe_click(&p, "Clear completed"))
	testing.expect(t, command_of(ui.probe_commands(&p)[0]) == todo.Clear_Completed{})

	// Mark all says nothing of what to mark: the application counts.
	testing.expect(t, ui.probe_click(&p, "Mark all"))
	testing.expect(t, command_of(ui.probe_commands(&p)[0]) == todo.Toggle_All{})
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
	testing.expect(t, command_of(cmds[0]) == todo.Add{title = todo.text_make("bread")})
	testing.expect_value(t, ui.text_string(&m.entry), "")
}

@(test)
a_filter_change_keeps_the_old_list_until_the_new_one_lands :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	two(&p)
	testing.expect(t, ui.probe_click(&p, "Completed"))
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, m.filter, query.Filter.Completed)
	// Both lists are needed: the new one to come, the old one to keep
	// drawing from meanwhile, so the rows never flicker.
	testing.expect(t, ui.probe_needs_q(&p, query.Todos{filter = .Completed}))
	testing.expect(t, ui.probe_needs_q(&p, query.Todos{filter = .All}))
	testing.expect(t, ui.probe_tagged(&p, "Delete milk"))
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
	ui.probe_deliver(&p, query.Todos{filter = .Completed}, query.Todos_Result{items = {{2, "eggs", true}}, active = 1, completed = 1})
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Delete eggs"))
	testing.expect(t, !ui.probe_tagged(&p, "Delete milk"))
	// The frame that draws the new list is the one that lets the old go.
	testing.expect(t, !ui.probe_needs_q(&p, query.Todos{filter = .All}))
	testing.expect_value(t, len(ui.probe_dropped(&p)), 1)
}

@(test)
loading_shows_only_after_a_perceptible_wait :: proc(t: ^testing.T) {
	m: Model
	defer model_destroy(&m)
	p := open(&m)
	defer ui.probe_destroy(&p)
	// The first frames have no list and say nothing about it; they ask
	// for a frame at the deadline instead.
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
	testing.expect(t, p.wants_frame)
	ui.probe_advance(&p, 2, 0.05)
	testing.expect(t, !ui.probe_tagged(&p, "Loading…"))
	ui.probe_advance(&p, 2, 0.05)
	testing.expect(t, ui.probe_tagged(&p, "Loading…"))
	// A list ends the wait; the next wait starts afresh.
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
	ui.probe_deliver(&p, query.Problems{}, query.Problems_Result{items = {{7, "A todo needs a title."}}})
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
	testing.expect(t, command_of(cmds[0]) == todo.Dismiss{id = 7})
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
	testing.expect(t, command_of(cmds[0]) == todo.Edit{id = 1, title = todo.text_make("milk!")})
	testing.expect_value(t, m.editing, i64(0))
}
