/*
Package shapes is the todo application's contract: the queries its ui may
need, the shapes that answer them, and the commands the ui may ask the
application to process. The ui (examples/todo/view) and the application
(examples/todo/logic, examples/todo/store) both import this and never each
other, which is what lets the frame be tested with no application linked and
the application run with no window.

Every type here is plain data: it crosses a queue, a pipe or a wire as cbor,
under its "shapes.Name" kind, and ui.need keys a query by its bytes.
*/
package todo_shapes

// ---------------------------------------------------------------------------
// Needs: what the ui asks for, and the shape each is answered with
// ---------------------------------------------------------------------------

// Filter is which todos a page shows.
Filter :: enum u8 {
	All,
	Active,
	Completed,
}

// Todos is the list under a filter.
Todos :: struct {
	filter: Filter,
}

Todo :: struct {
	id:    i64,
	title: string,
	done:  bool,
}

// Todos_Result answers Todos: the rows the filter keeps, and the counts
// across every row, so the footer needs no second query.
Todos_Result :: struct {
	items:     []Todo,
	active:    int,
	completed: int,
}

// Problems is what went wrong with commands and has not been dismissed.
// The application keeps these in memory; nothing about them is stored.
Problems :: struct {}

Problem :: struct {
	id:      u64,
	message: string,
}

Problems_Result :: struct {
	items: []Problem,
}

// ---------------------------------------------------------------------------
// Commands: what the ui asks the application to do
// ---------------------------------------------------------------------------

Add :: struct {
	title: string,
}

Toggle :: struct {
	id: i64,
}

// Toggle_All sets every todo done, or every todo active.
Toggle_All :: struct {
	done: bool,
}

// Edit retitles a todo; an empty title deletes it, as TodoMVC does.
Edit :: struct {
	id:    i64,
	title: string,
}

Delete :: struct {
	id: i64,
}

Clear_Completed :: struct {}

// Dismiss drops a problem from Problems.
Dismiss :: struct {
	id: u64,
}
