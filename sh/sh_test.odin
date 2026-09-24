package sh

import "core:strings"
import "core:testing"

@(test)
which_finds_shell :: proc(t: ^testing.T) {
	name := "cmd" when ODIN_OS == .Windows else "sh"
	p, found := which(name, context.temp_allocator)
	testing.expect(t, found, "shell must be on PATH")
	testing.expect(t, len(p) > 0)
	_, found = which("definitely-not-a-program-3f9a", context.temp_allocator)
	testing.expect(t, !found)
}

@(test)
out_and_lines :: proc(t: ^testing.T) {
	s, ok := out("echo hello", allocator = context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, s, "hello")

	ls, lok := lines("echo one&& echo two", allocator = context.temp_allocator)
	testing.expect(t, lok)
	testing.expect_value(t, len(ls), 2)
	if len(ls) == 2 {
		testing.expect_value(t, ls[0], "one")
		testing.expect_value(t, ls[1], "two")
	}
}

@(test)
failure_is_reported :: proc(t: ^testing.T) {
	r := capture("exit 3", allocator = context.temp_allocator)
	testing.expect(t, !r.ok)
	testing.expect_value(t, r.code, 3)
	msg := error(r, context.temp_allocator)
	testing.expect(t, strings.has_prefix(msg, "command failed (exit 3): exit 3"), msg)

	r = exec({"definitely-not-a-program-3f9a"}, allocator = context.temp_allocator)
	testing.expect(t, !r.ok)
	testing.expect(t, r.err != nil, "starting a missing program must set err")
}

@(test)
split_lines_strips_endings :: proc(t: ^testing.T) {
	// Trailing empty lines are dropped; interior ones stay.
	ls := split_lines("a\r\nb\n\n", context.temp_allocator)
	testing.expect_value(t, len(ls), 2)
	if len(ls) == 2 {
		testing.expect_value(t, ls[0], "a")
		testing.expect_value(t, ls[1], "b")
	}
	ls = split_lines("a\n\nb\n", context.temp_allocator)
	testing.expect_value(t, len(ls), 3)
	testing.expect_value(t, len(split_lines("", context.temp_allocator)), 0)
}
