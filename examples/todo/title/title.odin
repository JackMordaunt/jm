/*
Package title decides what makes a todo's title one the application keeps.
*/
package todo_title

import "core:strings"

import "../todo"

Validity :: enum u8 {
	Valid,
	Empty, // nothing but space
	Too_Long, // filled the buffer, so it may have been cut short
}

// validity answers "is this a title we keep?", and gives the title as it
// is kept: without the space around it. The title points into t.
validity :: proc(t: ^todo.Text) -> (v: Validity, title: string) {
	title = strings.trim_space(todo.text_of(t))
	if title == "" {
		return .Empty, ""
	}
	if t.len == todo.MAX_TITLE {
		return .Too_Long, title
	}
	return .Valid, title
}
