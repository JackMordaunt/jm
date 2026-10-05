/*
Package completion decides whether todos are done.
*/
package todo_completion

// toggled is whether a todo is done after a toggle, given whether it is.
toggled :: proc(done: bool) -> bool {
	return !done
}

// all_done is whether Toggle_All leaves every todo done, given how many
// are active: done while any is active, otherwise every one active again.
all_done :: proc(active: int) -> bool {
	return active > 0
}
