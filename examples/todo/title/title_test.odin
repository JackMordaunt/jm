package todo_title

import "core:strings"
import "core:testing"

import "../todo"

@(test)
validity_trims_and_judges :: proc(t: ^testing.T) {
	long := strings.repeat("x", todo.MAX_TITLE + 5)
	defer delete(long)
	cases := []struct {
		raw:   string,
		v:     Validity,
		title: string,
	} {
		{"  buy milk ", .Valid, "buy milk"},
		{"", .Empty, ""},
		{" \t ", .Empty, ""},
		{long, .Too_Long, long[:todo.MAX_TITLE]},
	}
	for c in cases {
		text := todo.text_make(c.raw)
		v, title := validity(&text)
		testing.expectf(t, v == c.v, "%q: %v, want %v", c.raw, v, c.v)
		testing.expectf(t, title == c.title, "%q: %q, want %q", c.raw, title, c.title)
	}
}
