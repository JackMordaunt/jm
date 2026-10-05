package ui

import "core:testing"

import "jm:ui/testutil"

// Every guard takes exactly its opener's parameters, so a call reads the
// same in either form and a guard cannot fall behind its opener.
@(test)
test_guards_take_their_openers_parameters :: proc(t: ^testing.T) {
	pairs := []struct {
		name:        string,
		guard, open: typeid,
	} {
		{"column", type_of(column), type_of(column_open)},
		{"row", type_of(row), type_of(row_open)},
		{"wrap", type_of(wrap), type_of(wrap_open)},
		{"stack", type_of(stack), type_of(stack_open)},
		{"inset", type_of(inset), type_of(inset_open)},
		{"sized", type_of(sized), type_of(sized_open)},
		{"box", type_of(box), type_of(box_open)},
		{"clip_box", type_of(clip_box), type_of(clip_box_open)},
		{"centered", type_of(centered), type_of(centered_open)},
		{"scroll_box", type_of(scroll_box), type_of(scroll_box_open)},
		{"grid", type_of(grid), type_of(grid_open)},
		{"overlay", type_of(overlay), type_of(overlay_open)},
	}
	for p in pairs {
		testing.expectf(t, testutil.same_params(p.guard, p.open), "%s and %s_open take different parameters", p.name, p.name)
	}
}
