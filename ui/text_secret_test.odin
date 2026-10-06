package ui

import "core:testing"

@(test)
test_a_secret_view_shows_a_bullet_per_rune_and_maps_the_caret :: proc(t: ^testing.T) {
	s: Text_State
	defer text_destroy(&s)
	text_set(&s, "aé€x")
	s.cursor, s.anchor = 3, 1 // after "é", after "a"
	v := secret_view(&s, context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, string(v.buf[:]), "••••")
	testing.expect_value(t, v.cursor, 2 * len(SECRET_BULLET))
	testing.expect_value(t, v.anchor, 1 * len(SECRET_BULLET))
	v.cursor, v.anchor = 3 * len(SECRET_BULLET), 4 * len(SECRET_BULLET)
	secret_apply(&s, &v)
	testing.expect_value(t, s.cursor, 6) // after "€"
	testing.expect_value(t, s.anchor, 7) // the end
	// A view offset inside a bullet's bytes lands at that rune's start.
	v.cursor = len(SECRET_BULLET) + 1
	secret_apply(&s, &v)
	testing.expect_value(t, s.cursor, 1)
}

@(test)
test_a_secret_text_is_never_copied_or_cut :: proc(t: ^testing.T) {
	s: Text_State
	defer text_destroy(&s)
	text_set(&s, "hunter2")
	text_select(&s, 0, len(s.buf))
	gtx: Ctx
	r: Router
	router_init(&r, context.temp_allocator)
	defer free_all(context.temp_allocator)
	gtx.router = &r
	gtx.allocator = context.temp_allocator
	stops := secret_stops(&gtx, &s)
	testing.expect_value(t, len(stops.words), 2) // no word inside
	copy_key := Event {
		kind = .Key,
		key  = .C,
		mods = {SHORTCUT},
	}
	cut_key := copy_key
	cut_key.key = .X
	testing.expect(t, !text_edit(&gtx, &s, 1, copy_key, stops, secret = true))
	testing.expect(t, !text_edit(&gtx, &s, 1, cut_key, stops, secret = true))
	testing.expect_value(t, text_string(&s), "hunter2")
	testing.expect_value(t, len(r.requests), 0)
	// The same keys on a plain field do copy and cut.
	testing.expect(t, text_edit(&gtx, &s, 1, cut_key, stops))
	testing.expect_value(t, text_string(&s), "")
}
