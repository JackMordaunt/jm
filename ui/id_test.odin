package ui

import "core:testing"
import "jm:ui/ops"

// at_site claims from one call site, however often it is called: a helper.
@(private = "file")
at_site :: proc(gtx: ^Ctx, key: u64 = 0) -> ops.Area_Id {
	return claim_id(gtx, key)
}

@(test)
test_claims_from_one_site_are_distinct_and_stable :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	first: [3]ops.Area_Id
	for &id in first {
		id = at_site(&h.gtx)
	}
	testing.expect(t, first[0] != first[1] && first[1] != first[2] && first[0] != first[2])
	harness_frame(&h)
	for id in first {
		testing.expect_value(t, at_site(&h.gtx), id)
	}
}

// A widget drawn only sometimes, from its own call site, moves no other
// widget's id: here one appears before two helpers between frames.
@(test)
test_a_conditional_widget_shifts_nothing_else :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	a, b := at_site(&h.gtx), at_site(&h.gtx)
	harness_frame(&h)
	claim_id(&h.gtx) // the error label that now shows
	testing.expect_value(t, at_site(&h.gtx), a)
	testing.expect_value(t, at_site(&h.gtx), b)
}

// A key replaces the occurrence, so state follows the data when the rows
// reorder: row 5 drawn second, then first, keeps its id.
@(test)
test_a_key_follows_its_data_through_a_reorder :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	at_site(&h.gtx, 9)
	five := at_site(&h.gtx, 5)
	harness_frame(&h)
	testing.expect_value(t, at_site(&h.gtx, 5), five)
	testing.expect(t, at_site(&h.gtx, 9) != five)
}

// The same call site in two containers is two widgets, and a popup's
// content counts apart from another popup's, so opening one shifts nothing
// in the other.
@(test)
test_parents_keep_their_own_counts :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	in_row :: proc(gtx: ^Ctx) -> ops.Area_Id {
		r := row_open(gtx)
		defer close(&r)
		return at_site(gtx)
	}
	testing.expect(t, in_row(&h.gtx) != in_row(&h.gtx))

	in_popup :: proc(gtx: ^Ctx, key: ops.Area_Id) -> ops.Area_Id {
		o := popup_open(gtx, {0, 0, 10, 10}, key)
		defer popup_close(&o, {10, 10})
		return at_site(gtx)
	}
	harness_frame(&h)
	second := in_popup(&h.gtx, 2)
	harness_frame(&h)
	in_popup(&h.gtx, 1) // another popup, opened first this frame
	testing.expect_value(t, in_popup(&h.gtx, 2), second)
}
