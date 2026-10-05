package base

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
		{"box", type_of(box), type_of(box_open)},
		{"panel", type_of(panel), type_of(panel_open)},
	}
	for p in pairs {
		testing.expectf(t, testutil.same_params(p.guard, p.open), "%s and %s_open take different parameters", p.name, p.name)
	}
}
