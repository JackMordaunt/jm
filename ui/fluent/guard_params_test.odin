package fluent

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
		{"carousel", type_of(carousel), type_of(carousel_open)},
		{"carousel_card", type_of(carousel_card), type_of(carousel_card_open)},
		{"card", type_of(card), type_of(card_open)},
		{"toolbar", type_of(toolbar), type_of(toolbar_open)},
		{"accordion_item", type_of(accordion_item), type_of(accordion_item_open)},
		{"table", type_of(table), type_of(table_open)},
		{"table_row", type_of(table_row), type_of(table_row_open)},
		{"table_header", type_of(table_header), type_of(table_header_open)},
		{"list", type_of(list), type_of(list_open)},
		{"tag_group", type_of(tag_group), type_of(tag_group_open)},
		{"field", type_of(field), type_of(field_open)},
		{"drawer", type_of(drawer), type_of(drawer_open)},
		{"drawer_header", type_of(drawer_header), type_of(drawer_header_open)},
		{"drawer_body", type_of(drawer_body), type_of(drawer_body_open)},
		{"drawer_footer", type_of(drawer_footer), type_of(drawer_footer_open)},
		{"nav", type_of(nav), type_of(nav_open)},
		{"nav_category", type_of(nav_category), type_of(nav_category_open)},
		{"nav_header", type_of(nav_header), type_of(nav_header_open)},
		{"nav_body", type_of(nav_body), type_of(nav_body_open)},
		{"nav_footer", type_of(nav_footer), type_of(nav_footer_open)},
		{"tree", type_of(tree), type_of(tree_open)},
		{"tree_item", type_of(tree_item), type_of(tree_item_open)},
		{"menu", type_of(menu), type_of(menu_open)},
		{"dialog", type_of(dialog), type_of(dialog_open)},
		{"dialog_actions", type_of(dialog_actions), type_of(dialog_actions_open)},
		{"popover", type_of(popover), type_of(popover_open)},
		{"teaching_popover", type_of(teaching_popover), type_of(teaching_popover_open)},
	}
	for p in pairs {
		testing.expectf(t, testutil.same_params(p.guard, p.open), "%s and %s_open take different parameters", p.name, p.name)
	}
}
