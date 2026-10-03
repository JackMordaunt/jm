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
