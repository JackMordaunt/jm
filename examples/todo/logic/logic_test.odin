package todo_logic

import "core:strings"
import "core:testing"

import "../todo"

@(test)
each_command_comes_to_its_effect :: proc(t: ^testing.T) {
	long := strings.repeat("x", todo.MAX_TITLE + 5)
	defer delete(long)
	there := Facts{exists = true}
	cases := []struct {
		name:  string,
		c:     todo.Command,
		f:     Facts,
		want:  Effect,
	} {
		{"add trims", todo.Add{todo.text_make("  buy milk ")}, {}, Insert{todo.text_make("buy milk")}},
		{"add blank", todo.Add{todo.text_make("   ")}, {}, Report{NO_TITLE}},
		{"add too long", todo.Add{todo.text_make(long)}, {}, Report{TOO_LONG}},
		{"edit retitles", todo.Edit{7, todo.text_make(" new ")}, there, Set_Title{7, todo.text_make("new")}},
		{"edit to nothing deletes", todo.Edit{7, todo.text_make(" ")}, there, Remove{7}},
		{"edit too long", todo.Edit{7, todo.text_make(long)}, there, Report{TOO_LONG}},
		{"edit a gone todo", todo.Edit{7, todo.text_make("new")}, {}, Report{GONE}},
		{"toggle an active todo", todo.Toggle{3}, there, Set_Done{3, true}},
		{"toggle a done todo", todo.Toggle{3}, {exists = true, done = true}, Set_Done{3, false}},
		{"toggle a gone todo", todo.Toggle{3}, {}, Report{GONE}},
		{"toggle all with some active", todo.Toggle_All{}, {active = 2}, Set_All{true}},
		{"toggle all with none active", todo.Toggle_All{}, {}, Set_All{false}},
		{"delete", todo.Delete{3}, {}, Remove{3}},
		{"clear completed", todo.Clear_Completed{}, {}, Remove_Done{}},
		{"dismiss", todo.Dismiss{9}, {}, Withdraw{9}},
	}
	for c in cases {
		got := effect(c.c, c.f)
		testing.expectf(t, got == c.want, "%s: %v, want %v", c.name, got, c.want)
	}
	testing.expect(t, effect(nil, {}) == nil)
}
