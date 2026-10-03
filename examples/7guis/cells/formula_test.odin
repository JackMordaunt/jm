package main

import "core:testing"

@(private = "file")
value_of :: proc(s: ^Sheet, name: string) -> Value {
	c, ok := parse_cell(name)
	assert(ok, name)
	return s.value[c.row][c.col]
}

@(private = "file")
set :: proc(s: ^Sheet, name, text: string) {
	c, ok := parse_cell(name)
	assert(ok, name)
	sheet_set(s, c, text)
}

@(test)
formulas_follow_precedence_references_and_functions :: proc(t: ^testing.T) {
	s := new(Sheet)
	defer free(s)
	defer sheet_destroy(s)

	set(s, "A0", "2")
	set(s, "A1", "3")
	set(s, "A2", "=A0 + A1 * 4")
	testing.expect_value(t, value_of(s, "A2"), Value{.Number, 14})
	set(s, "B0", "=(a0 + a1) * -2")
	testing.expect_value(t, value_of(s, "B0"), Value{.Number, -10})
	set(s, "B1", "=SUM(A0:A2) / avg(A0, A1, 1)")
	testing.expect_value(t, value_of(s, "B1"), Value{.Number, 19.0 / 2})
	set(s, "B2", "=MAX(A0:A1, 7) - MIN(A0:A9)")
	testing.expect_value(t, value_of(s, "B2"), Value{.Number, 5})
}

@(test)
an_edit_propagates_to_every_cell_that_depends_on_it :: proc(t: ^testing.T) {
	s := new(Sheet)
	defer free(s)
	defer sheet_destroy(s)

	set(s, "C3", "=B3 * 2")
	set(s, "B3", "=A3 + 1")
	set(s, "A3", "10")
	testing.expect_value(t, value_of(s, "C3"), Value{.Number, 22})
	set(s, "A3", "20")
	testing.expect_value(t, value_of(s, "C3"), Value{.Number, 42})
}

@(test)
bad_formulas_text_and_cycles_are_errors :: proc(t: ^testing.T) {
	s := new(Sheet)
	defer free(s)
	defer sheet_destroy(s)

	set(s, "A0", "hello")
	testing.expect_value(t, value_of(s, "A0").kind, Value_Kind.Text)
	for src in ([]string{"=A0 + 1", "=1 +", "=(1", "=1 / 0", "=NOPE(1)", "=Z100", "=1 2", "=AVG(B0:B5)"}) {
		set(s, "B9", src)
		testing.expectf(t, value_of(s, "B9").kind == .Error, "%q should be an error", src)
	}
	set(s, "C0", "=C1")
	set(s, "C1", "=C0 + 1")
	testing.expect_value(t, value_of(s, "C0").kind, Value_Kind.Error)
	testing.expect_value(t, value_of(s, "C1").kind, Value_Kind.Error)
	set(s, "C1", "5") // breaking the cycle clears both
	testing.expect_value(t, value_of(s, "C0"), Value{.Number, 5})
}
