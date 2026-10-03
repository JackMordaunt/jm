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
	got, groups := kitchen.group_stop_violations(kitchen_app(&m))
	testing.expect(t, groups > 0, "no group on any page held a Tab stop: the check did not run")
	testing.expectf(t, len(got) == 0, "groups with more than one Tab stop:\n%s", strings.join(got, "\n"))
}

// Nothing on any page in any theme is cut off or ungrouped beyond what
// lint.txt accepts: a shimmer, a cover-fit image, or a known defect.
// After a fix, or a cut that is meant, rewrite it with
// `just kitchen-lint <kit> accept`.
@(test)
test_no_page_is_cut_off_beyond_lint_txt :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	m: Model
	app := kitchen_app(&m)
	lines, renders := kitchen.lint(app)
	testing.expect_value(t, renders, len(app.pages) * len(app.themes))
	got := kitchen.lint_unaccepted(lines, #load("../lint.txt", string))
	testing.expectf(t, len(got) == 0, "cut off or ungrouped, and not in lint.txt:\n%s", strings.join(got, "\n"))
}
