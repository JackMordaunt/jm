/*
Package todo is what the todo ui may ask the application to do: the
Command union, holding only what the ui knows when it asks. Whatever else
a decision needs, the application gathers itself. The view emits these,
the host decodes them, and the logic decides them; it imports nothing.

Commands are values with fixed buffers, not strings, because they cross
stream edges by copy between threads: a Text is as long as the longest
title the application keeps.
*/
package todo

// MAX_TITLE is the longest title a command carries, in bytes.
MAX_TITLE :: 120

// Text is a string that fits in a message. One that filled the buffer
// may have been cut short.
Text :: struct {
	buf: [MAX_TITLE]u8,
	len: int,
}

text_make :: proc(s: string) -> (t: Text) {
	t.len = copy(t.buf[:], s)
	return
}

text_of :: proc(t: ^Text) -> string {
	return string(t.buf[:t.len])
}

Command :: union {
	Add,
	Toggle,
	Toggle_All,
	Edit,
	Delete,
	Clear_Completed,
	Dismiss,
}

Add :: struct {
	title: Text,
}

// Toggle flips a todo between done and active.
Toggle :: struct {
	id: i64,
}

// Toggle_All makes every todo done, or every todo active if all are done.
Toggle_All :: struct {}

// Edit retitles a todo.
Edit :: struct {
	id:    i64,
	title: Text,
}

Delete :: struct {
	id: i64,
}

Clear_Completed :: struct {}

// Dismiss drops a problem from query.Problems.
Dismiss :: struct {
	id: u64,
}
