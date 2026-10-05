package todo_completion

import "core:testing"

@(test)
a_toggle_flips :: proc(t: ^testing.T) {
	testing.expect(t, toggled(false))
	testing.expect(t, !toggled(true))
}

@(test)
toggle_all_finishes_until_nothing_is_active :: proc(t: ^testing.T) {
	testing.expect(t, all_done(1))
	testing.expect(t, all_done(5))
	testing.expect(t, !all_done(0))
}
