package material

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
		{"card", type_of(card), type_of(card_open)},
		{"tooltip", type_of(tooltip), type_of(tooltip_open)},
		{"bottom_sheet", type_of(bottom_sheet), type_of(bottom_sheet_open)},
		{"side_sheet", type_of(side_sheet), type_of(side_sheet_open)},
		{"radio_group", type_of(radio_group), type_of(radio_group_open)},
	}
	for p in pairs {
		testing.expectf(t, testutil.same_params(p.guard, p.open), "%s and %s_open take different parameters", p.name, p.name)
	}
}
