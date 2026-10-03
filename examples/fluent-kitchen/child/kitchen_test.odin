package main

import "core:strings"
import "core:testing"

import "../../kitchen"

// Every group on every page (a tab list, radio group, toolbar, tree, menu
// or listbox) is one Tab stop: its widget opened a roving focus scope.
@(test)
test_every_group_on_every_page_is_one_tab_stop :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	m: Model
	got := kitchen.group_stop_violations(kitchen_app(&m))
	testing.expectf(t, len(got) == 0, "groups with more than one Tab stop:\n%s", strings.join(got, "\n"))
}
