/*
Package view is the todo application's ui: a frame that needs the todos
under a filter and the current problems, draws them in Fluent, and turns
clicks and keys into todo.Commands. It imports the two leaf packages, todo
and query, and jm:ui, and nothing that reads or writes, so a probe drives
it with results it delivers by hand (view_test.odin), and the same proc
runs under ui/shell or ui/child.
*/
package todo_view

import "core:fmt"

import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../../common"
import "../query"
import "../todo"

WIDTH :: 560
// A row is the checkbox (32 with its gap), the title, and two 24px icon
// buttons with their gaps. The title's width is what is left, given here
// so the first frame lays the row out exactly: a weighted child would take
// its share from the frame before.
TITLE_WIDTH :: WIDTH - 40 - 2 * (24 + 8)


// Model is the ui's own state: what the frame needs between frames and
// nothing the application knows. The text being typed is ui state until
// Enter makes it a command.
Model :: struct {
	theme:   fluent.Theme,
	scheme:  fluent.Scheme,
	filter:  query.Filter,
	entry:   ui.Text_State, // the new todo being typed
	editing: i64, // the todo being retitled, 0 for none
	edit:    ui.Text_State, // its title being typed
	scroll:  ui.Scroll_Offset,
	shown:   query.Filter, // the filter whose list was drawn last; see shown_todos
	waiting: f64, // gtx.time when the current wait for a list began, or 0
}

// shown_todos is the list of todos to draw: the current filter's once it
// has arrived, and until then the list drawn last, which stays needed so it
// is not released under us. Switching filters never shows an empty list for
// the frame the new one takes; a wait is reported only once it has lasted
// common.LOADING_DELAY, and a frame is asked for to report it. The second
// result says whether there is a list at all.
@(private)
shown_todos :: proc(
	gtx: ^ui.Ctx,
	m: ^Model,
) -> (
	todos: ^query.Todos_Result,
	ok: bool,
	loading: bool,
) {
	now, status := ui.need(gtx, query.Todos{filter = m.filter}, query.Todos_Result)
	if status == .Ready || status == .Stale {
		m.shown = m.filter
		m.waiting = 0
		return now, true, false
	}
	if m.waiting == 0 {
		m.waiting = gtx.time
	}
	waited := gtx.time - m.waiting
	if waited < common.LOADING_DELAY {
		ui.request_frame(gtx, f32(common.LOADING_DELAY - waited))
	} else {
		loading = true
	}
	if m.shown != m.filter {
		last, lstatus := ui.need(gtx, query.Todos{filter = m.shown}, query.Todos_Result)
		if lstatus == .Ready || lstatus == .Stale {
			return last, true, loading
		}
	}
	return nil, false, loading
}

model_destroy :: proc(m: ^Model) {
	ui.text_destroy(&m.entry)
	ui.text_destroy(&m.edit)
}

// view is the frame.
view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	m.scheme = fluent.theme_scheme(m.theme)
	fluent.use(&m.scheme, fluent.mode_of(m.theme))
	fluent.use_fonts({0, 1, 2})
	s := &m.scheme
	ops.fill(gtx.scene, ops.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, s[.Neutral_Background3])

	// The whole page scrolls, as a TodoMVC page does, and the scroll box
	// spans the window so its bar sits at the window's edge; the page is
	// a fixed-width column centred inside it.
	ui.scroll_box(gtx, offset = &m.scroll)
	ui.column(gtx, align = .Center)
	ui.sized(gtx, {min = {WIDTH, 0}, max = {WIDTH, ui.INF}})
	ui.column(gtx, gap = 12, align = .Fill)

	header(gtx, m)
	problems(gtx, m)
	entry(gtx, m)
	todos(gtx, m)
}

// Rows here are made of fixed-width cells with deferred alignment inside
// them, never a weighted child before an unweighted one: a weighted child
// takes its share from the previous frame's totals, and a frame that
// arrives with a shape and no input would otherwise keep that layout.

@(private)
header :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := &m.scheme
	ui.row(gtx, align = .Baseline)
	if common.cell(gtx, WIDTH - 120, .Start) {
		fluent.text(gtx, "todos", s[.Brand_Foreground1], .S1000, .Semibold, selectable = false)
	}
	if common.cell(gtx, 120, .End) {
		dark := m.theme == .Web_Dark
		if fluent.link(gtx, "Dark" if !dark else "Light") {
			m.theme = .Web_Light if dark else .Web_Dark
		}
	}
}


// problems shows what the application refused, one bar each, until
// dismissed. Missing means none have been reported yet.
@(private)
problems :: proc(gtx: ^ui.Ctx, m: ^Model) {
	list, status := ui.need(gtx, query.Problems{}, query.Problems_Result)
	if status != .Ready && status != .Stale {
		return
	}
	for p in list.items {
		ui.scope(gtx, p.id)
		_, dismissed := fluent.message_bar(gtx, .Error, "", p.message, dismissable = true)
		if dismissed {
			ui.command(gtx, todo.Command(todo.Dismiss{id = p.id}))
		}
	}
}

// entry is the new-todo line: the toggle-all box and the input. Enter is
// the command; the text is cleared at once, since the application will
// either add the todo or report a problem.
@(private)
entry :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.row(gtx, gap = 8, align = .Center)
	list, have, _ := shown_todos(gtx, m)
	all := false
	if have {
		all = list.active == 0 && list.completed > 0
	}
	if fluent.checkbox(gtx, &all, "Mark all", state = .Live if have else .Disabled) {
		ui.command(gtx, todo.Command(todo.Toggle_All{}))
	}
	ui.flexible(gtx, 1)
	e := fluent.input(gtx, &m.entry, "What needs to be done?", name = "New todo")
	if gtx.frame == 0 {
		ui.focus_request(gtx, e.id) // the page opens ready to type into
	}
	if e.submitted {
		ui.command(gtx, todo.Command(todo.Add{title = todo.text_make(ui.text_string(&m.entry))}))
		ui.text_set(&m.entry, "")
	}
}

@(private)
todos :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := &m.scheme
	list, have, loading := shown_todos(gtx, m)
	if loading {
		fluent.text(gtx, "Loading…", s[.Neutral_Foreground3], selectable = false)
	}
	if !have {
		return
	}
	rows(gtx, m, list)
	footer(gtx, m, list)
}

@(private)
rows :: proc(gtx: ^ui.Ctx, m: ^Model, list: ^query.Todos_Result) {
	ui.column(gtx, gap = 2, align = .Fill)
	for row in list.items {
		todo_row(gtx, m, row)
	}
}

@(private)
todo_row :: proc(gtx: ^ui.Ctx, m: ^Model, row: query.Todo) {
	s := &m.scheme
	ui.scope(gtx, row.id)
	ui.row(gtx, gap = 8, align = .Center)
	done := row.done
	if fluent.checkbox(gtx, &done, "") {
		ui.command(gtx, todo.Command(todo.Toggle{id = row.id}))
	}
	if m.editing == row.id {
		e := fluent.input(gtx, &m.edit, name = "Edit todo", width = TITLE_WIDTH - 60)
		if e.submitted {
			title := todo.text_make(ui.text_string(&m.edit))
			ui.command(gtx, todo.Command(todo.Edit{id = row.id, title = title}))
			m.editing = 0
		}
		if fluent.button(gtx, "Cancel", .Subtle, size = .Small) {
			m.editing = 0
		}
		return
	}
	fluent.text(gtx, row.title, s[.Neutral_Foreground3] if done else s[.Neutral_Foreground1], strikethrough = done, width = TITLE_WIDTH, truncate = true)
	if fluent.button(gtx, "", .Subtle, .Edit, .Small, name = fmt.tprintf("Edit %s", row.title)) {
		m.editing = row.id
		ui.text_set(&m.edit, row.title)
	}
	if fluent.button(gtx, "", .Subtle, .Delete, .Small, name = fmt.tprintf("Delete %s", row.title)) {
		ui.command(gtx, todo.Command(todo.Delete{id = row.id}))
	}
}

@(private)
FILTERS :: []string{"All", "Active", "Completed"}

@(private)
footer :: proc(gtx: ^ui.Ctx, m: ^Model, list: ^query.Todos_Result) {
	s := &m.scheme
	ui.row(gtx, align = .Center)
	left := list.active
	if common.cell(gtx, 150, .Start) {
		fluent.text(gtx, fmt.tprintf("%d item%s left", left, "" if left == 1 else "s"), s[.Neutral_Foreground2], selectable = false)
	}
	if common.cell(gtx, WIDTH - 300, .Center) {
		selected := int(m.filter)
		if fluent.tab_list(gtx, FILTERS, &selected, size = .Small) {
			m.filter = query.Filter(selected)
		}
	}
	if common.cell(gtx, 150, .End) {
		if list.completed > 0 {
			if fluent.button(gtx, "Clear completed", .Subtle, size = .Small) {
				ui.command(gtx, todo.Command(todo.Clear_Completed{}))
			}
		}
	}
}
