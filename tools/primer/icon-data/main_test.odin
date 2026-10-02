package main

import "core:strings"
import "core:testing"

@(test)
test_icons_join_their_paths_and_drop_even_odd_heights :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	data := `{
		"triangle-down": {"keywords": [], "heights": {
			"16": {"width": 16, "evenodd": false, "d": ["M1 1L2 2Z"]},
			"24": {"width": 24, "evenodd": false, "d": ["M3 3L4 4Z", "M5 5L6 6Z"]}}},
		"logo-gist": {"keywords": [], "heights": {
			"16": {"width": 25, "evenodd": false, "d": ["M7 7Z"]}}},
		"comment-fill": {"keywords": [], "heights": {
			"16": {"width": 16, "evenodd": true, "d": ["M8 8Z"]},
			"24": {"width": 24, "evenodd": true, "d": ["M9 9Z"]}}},
		"chat-add": {"keywords": [], "heights": {
			"16": {"width": 16, "evenodd": true, "d": ["M1 2Z"]},
			"24": {"width": 24, "evenodd": false, "d": ["M3 4Z"]}}}
	}`
	out, ok := generate(transmute([]u8)data)
	testing.expect(t, ok)
	for want in ([]string {
			"Icon :: enum u16 {\n\tNone,\n\tChat_Add,\n\tLogo_Gist,\n\tTriangle_Down,\n}",
			"\t.Triangle_Down = \"M3 3L4 4Z M5 5L6 6Z\",", // two paths, one path's subpaths
			"\t.Chat_Add = \"M3 4Z\",", // its 24px design stays
			"ICON_WIDTH_16 := #partial [Icon]u8 {\n\t.Logo_Gist = 25,\n}", // only the one not square
			"// Left out, filling even-odd: chat-add-16, comment-fill-16,\n// comment-fill-24.",
		}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
	testing.expect(t, !strings.contains(out, "Comment_Fill"), "an icon with no height left is no member")
	testing.expect(t, !strings.contains(out, "M1 2Z"), "an even-odd height is no entry")
}

@(test)
test_the_checked_in_icon_data_is_current :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	out, ok := generate(#load("../source/npm/octicons/data.json"))
	testing.expect(t, ok)
	testing.expect(
		t,
		out == string(#load("../../../ui/primer/icon_data.odin")),
		"ui/primer/icon_data.odin is stale; run just primer-icons",
	)
}
