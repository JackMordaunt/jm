package main

import "core:fmt"
import "jm:ui"
import "jm:ui/primer"

import "../../kitchen"

// Lists is the lists pages' demo state: the live lists' selections and
// what they last reported.
Lists :: struct {
	single:   int,
	multiple: [4]bool,
	radio:    int,
	current:  int,
	said:     string,
	menu:     bool,
	sub:      bool,
	view:     int, // the live menu's single selection
	shown:    [3]bool, // its multiple-selection group
}

// The list and picker pages, on the primer-kit's components/action-list
// .json, action-menu.json, select-panel.json, autocomplete.json and
// text-input-with-tokens.json.

// list_box is a fixed-width band a page's list sits in, as a list sits
// in a page's column.
@(private = "file")
list_box :: proc(gtx: ^ui.Ctx, w: f32, key: u64) -> ui.Inset {
	return ui.sized_open(gtx, {min = {w, 0}, max = {w, ui.INF}}, key = key)
}

ITEM_VARIANT_NAMES := [?]string{"Default", "Danger", "Active", "Selected (single)", "Loading"}

page_action_list :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "States", "32px rows, 6px by 8px padding; hover fills --control-transparent-bgColor-hover, active adds the 4px accent bar")
	kitchen.state_header(gtx)
	for n, i in ITEM_VARIANT_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			v := key / 16 - 1
			l := primer.action_list_open(gtx, .Full, selection = v == 3 ? .Single : .None, key = key)
			primer.action_list_item(&l, "Edit", leading = .Pencil, variant = v == 1 ? .Danger : .Default, active = v == 2, selected = v == 3, loading = v == 4, state = st)
			primer.action_list_close(&l)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	kitchen.section(gtx, "Anatomy", "selection, leading visual, label, inline or block description, trailing visual; 8px between present columns")
	ls := &m.lists
	{
		r := ui.row_open(gtx, gap = 24, align = .Start)
		defer ui.close(&r)
		{
			b := list_box(gtx, 320, 1)
			l := primer.action_list_open(gtx, heading = "Repository", key = 2)
			primer.action_list_item(&l, "Code", leading = .Code, active = ls.current == 0)
			primer.action_list_item(&l, "Issues", leading = .Issue_Opened, trailing_text = "12")
			primer.action_list_item(&l, "Settings", leading = .Gear, hint = "Mod+,")
			primer.action_list_divider(&l)
			primer.action_list_item(&l, "Copy link", description = "Inline description", leading = .Link)
			primer.action_list_item(&l, "Rename", description = "Block descriptions sit under the label and wrap", description_variant = .Block, leading = .Pencil)
			primer.action_list_item(&l, "Delete repository", leading = .Trash, variant = .Danger)
			primer.action_list_item(&l, "Unavailable", leading = .Archive, inactive = "Archiving is down for maintenance")
			primer.action_list_item(&l, "Disabled", leading = .Eye, disabled = true)
			for i in 0 ..< 3 {
				if l.activated == i {
					ls.current = i
				}
			}
			primer.action_list_close(&l)
			ui.close(&b)
		}
		{
			b := list_box(gtx, 280, 3)
			l := primer.action_list_open(gtx, .Horizontal_Inset, dividers = true, key = 4)
			primer.action_list_group_open(&l, "Filled group", .Filled, auxiliary = "Auxiliary text under the heading")
			primer.action_list_item(&l, "Assignees", leading = .Person)
			primer.action_list_item(&l, "Labels", leading = .Tag, size = .Large)
			primer.action_list_group_open(&l, "Subtle group")
			primer.action_list_item(&l, "Projects", leading = .Repo, trailing = .Chevron_Right)
			primer.action_list_item(&l, "Milestone", leading = .Star, loading = true)
			primer.action_list_close(&l)
			ui.close(&b)
		}
	}
	kitchen.section(gtx, "Selection", "a checkmark (single), radio, or checkbox (multiple) column, reserved on every item")
	{
		r := ui.row_open(gtx, gap = 24, align = .Start)
		defer ui.close(&r)
		names := [4]string{"Bug", "Feature", "Question", "Documentation"}
		{
			b := list_box(gtx, 220, 5)
			l := primer.action_list_open(gtx, selection = .Single, role = .Listbox, focus = .Roving, name = "Single", key = 6)
			for n, i in names {
				if primer.action_list_item(&l, n, selected = ls.single == i) {
					ls.single = i
					ls.said = fmt.aprintf("single: %s", n)
				}
			}
			primer.action_list_close(&l)
			ui.close(&b)
		}
		{
			b := list_box(gtx, 220, 7)
			l := primer.action_list_open(gtx, selection = .Multiple, role = .Listbox, focus = .Roving, name = "Multiple", key = 8)
			for n, i in names {
				if primer.action_list_item(&l, n, selected = ls.multiple[i]) {
					ls.multiple[i] = !ls.multiple[i]
				}
			}
			primer.action_list_close(&l)
			ui.close(&b)
		}
		{
			b := list_box(gtx, 220, 9)
			l := primer.action_list_open(gtx, selection = .Radio, role = .Listbox, focus = .Roving, name = "Radio", key = 10)
			for n, i in names {
				if primer.action_list_item(&l, n, selected = ls.radio == i, disabled = i == 3) {
					ls.radio = i
				}
			}
			primer.action_list_close(&l)
			ui.close(&b)
		}
	}
	said(gtx, ls.said)
}

MENU_VIEWS := [3]string{"Comfortable", "Compact", "Spacious"}

page_action_menu :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Anchor", "ActionMenu.Button: a button with a trailing triangle-down; expanded, it keeps its pressed fill until hovered")
	kitchen.state_header(gtx)
	for n, i in ([2]string{"Closed", "Open"}) {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			open := key / 16 == 2
			primer.button(gtx, "Menu", action = .Triangle_Down, expanded = open, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	kitchen.section(gtx, "Menu", "the overlay surface around an inset menu list: 192px wide at least, 8px above and below, 32px items")
	{
		band := ui.sized_open(gtx, {min = {0, 250}, max = {ui.INF, 250}}, key = 3)
		defer ui.close(&band)
		open := true
		if primer.overlay(gtx, &open, {0, 4}, focus = {prevent = true}, key = 4) {
			l := primer.action_list_open(gtx, role = .Menu, selection = .Single, name = "View", key = 5)
			primer.action_list_item(&l, "Comfortable", selected = true)
			primer.action_list_item(&l, "Compact", hint = "Mod+K")
			primer.action_list_divider(&l)
			primer.action_list_item(&l, "More options", trailing = .Chevron_Right)
			primer.action_list_item(&l, "Delete view", variant = .Danger, leading = .Trash)
			primer.action_list_close(&l)
		}
	}
	kitchen.section(gtx, "Live", "a click leaves focus on the button, Enter or ArrowDown focuses the first item; arrows wrap, letters jump, Right opens the submenu")
	ls := &m.lists
	st := ui.stack_open(gtx)
	primer.action_menu_button(gtx, "View", &ls.menu)
	mn := primer.action_menu_open(gtx, &ls.menu, ui.last_widget(gtx), name = "View")
	primer.action_menu_group_open(&mn, "Density", selection = primer.Selection_Variant.Single)
	for n, i in MENU_VIEWS {
		if primer.action_menu_item(&mn, n, selected = ls.view == i) {
			ls.view = i
			ls.said = fmt.aprintf("view: %s", n)
		}
	}
	primer.action_menu_group_close(&mn)
	primer.action_menu_group_open(&mn, "Show", selection = primer.Selection_Variant.Multiple)
	for n, i in ([3]string{"Labels", "Assignees", "Milestones"}) {
		if primer.action_menu_item(&mn, n, selected = ls.shown[i], keep_open = true) {
			ls.shown[i] = !ls.shown[i]
		}
	}
	primer.action_menu_group_close(&mn)
	primer.action_menu_divider(&mn)
	primer.action_menu_item(&mn, "Export", leading = .Archive, submenu = &ls.sub)
	if primer.action_menu_item(&mn, "Reset view", leading = .Trash, variant = .Danger) {
		ls.said = "reset"
	}
	sub := primer.action_menu_submenu_open(&mn, &ls.sub)
	for n in ([2]string{"As CSV", "As JSON"}) {
		if primer.action_menu_item(&sub, n) {
			ls.said = fmt.aprintf("export: %s", n)
		}
	}
	primer.action_menu_close(&sub)
	primer.action_menu_close(&mn)
	ui.close(&st)
	said(gtx, ls.said)
}
