/*
Package query is what the todo ui may read: each query is a pair, the
params a need asks with and the result it is answered with, named Name and
Name_Result. The view needs these; the host answers them from the store,
or from memory for Problems. It imports nothing.

Every type here is plain data: it crosses a pipe or a wire as cbor, under
its "query.Name" kind, and ui.need keys a query by its bytes.
*/
package todo_query

// Filter is which todos the list shows.
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
