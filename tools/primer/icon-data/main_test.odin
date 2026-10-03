package main

import "core:strings"
import "core:testing"

@(test)
test_icons_keep_each_path_and_its_fill_rule :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	data := `{
		"agent": {"keywords": [], "heights": {
			"16": {"width": 16, "paths": [{"d": "M1 1L2 2Z", "evenodd": false}, {"d": "m3 3 1 1Z", "evenodd": false}]}}},
		"logo-gist": {"keywords": [], "heights": {
			"16": {"width": 25, "paths": [{"d": "M7 7Z", "evenodd": false}]}}},
		"chat-add": {"keywords": [], "heights": {
			"16": {"width": 16, "paths": [{"d": "M1 2Z", "evenodd": false}, {"d": "M5 6Z", "evenodd": true}]},
			"24": {"width": 24, "paths": [{"d": "M3 4Z", "evenodd": true}]}}}
	}`
	out, ok := generate(transmute([]u8)data)
	testing.expect(t, ok)
	for want in ([]string {
			"Icon :: enum u16 {\n\tNone,\n\tAgent,\n\tChat_Add,\n\tLogo_Gist,\n}",
			// apart, so the relative m stays relative to the origin
			"\t.Agent = {d = {0 = \"M1 1L2 2Z\", 1 = \"m3 3 1 1Z\"}},",
			"\t.Chat_Add = {d = {0 = \"M1 2Z\", 1 = \"M5 6Z\"}, even_odd = {1}},",
			"\t.Chat_Add = {d = {0 = \"M3 4Z\"}, even_odd = {0}},",
			"ICON_WIDTH_16 := #partial [Icon]u8 {\n\t.Logo_Gist = 25,\n}", // only the one not square
		}) {
		testing.expectf(t, strings.contains(out, want), "missing %q", want)
	}
}

@(test)
test_an_icon_of_more_paths_than_an_entry_holds_is_refused :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p := `{"d": "M0 0Z", "evenodd": false}`
	four := strings.concatenate({`{"full": {"keywords": [], "heights": {"16": {"width": 16, "paths": [`, p, ",", p, ",", p, ",", p, `]}}}}`})
	_, fits := generate(transmute([]u8)four)
	testing.expect(t, fits, "an icon of as many paths as an entry holds is drawn")
	five := strings.concatenate({`{"many": {"keywords": [], "heights": {"16": {"width": 16, "paths": [`, p, ",", p, ",", p, ",", p, ",", p, `]}}}}`})
	_, ok := generate(transmute([]u8)five)
	testing.expect(t, !ok)
}

@(test)
test_the_checked_in_icon_data_is_current :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	out, ok := generate(#load("../upstream/npm/octicons/data.json"))
	testing.expect(t, ok)
	testing.expect(
		t,
		out == string(#load("../../../ui/primer/icon_data.odin")),
		"ui/primer/icon_data.odin is stale; run just primer-icons",
	)
}
