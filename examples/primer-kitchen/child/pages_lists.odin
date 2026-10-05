package main

import "core:fmt"
import "core:strings"
import "jm:ui"
import "jm:ui/base"
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
	seeded:   bool,
	sizes:    [4]Token_Demo,
	collapse: Token_Demo,
	invalid:  Token_Demo,
	disabled: Token_Demo,
	fruit_text, tag_text: ui.Text_State,
	fruit, tags: [8]bool,
	panel, single_panel, modal_panel: bool,
	panel_filter, single_filter, modal_filter: ui.Text_State,
	panel_sel, single_sel, modal_sel: [8]bool,
}

// Token_Demo is a live token field's text and labels.
Token_Demo :: struct {
	text:   ui.Text_State,
	labels: [8]string,
	n:      int,
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
	ui.column(gtx, gap = 10)
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
		ui.row(gtx, gap = 24, align = .Start)
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
		ui.row(gtx, gap = 24, align = .Start)
		names := [4]string{"Bug", "Feature", "Question", "Documentation"}
		{
			b := list_box(gtx, 220, 5)
			l := primer.action_list_open(gtx, selection = .Single, role = .Listbox, name = "Single", key = 6)
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
			l := primer.action_list_open(gtx, selection = .Multiple, role = .Listbox, name = "Multiple", key = 8)
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
			l := primer.action_list_open(gtx, selection = .Radio, role = .Listbox, name = "Radio", key = 10)
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
	ui.column(gtx, gap = 10)
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
		ui.sized(gtx, {min = {0, 250}, max = {ui.INF, 250}}, key = 3)
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


// remove_label drops label i from a field's labels.
@(private = "file")
remove_label :: proc(f: ^Token_Demo, i: int) {
	if i < 0 || i >= f.n {
		return
	}
	copy(f.labels[i:f.n - 1], f.labels[i + 1:f.n])
	f.n -= 1
}

page_text_input_with_tokens :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	ls := &m.lists
	if !ls.seeded {
		seed_lists(ls)
	}
	kitchen.section(gtx, "Sizes", "tokens 16, 20, 24 or 32px, 4px apart; small and medium put the field in its 28px size; the field pads 6px by 12px")
	for name, i in TOKEN_SIZE_NAMES {
		ui.row(gtx, gap = 16, align = .Center, key = u64(i + 1))
		{
			ui.sized(gtx, {min = {110, 0}, max = {110, ui.INF}})
			base.label(gtx, name, {size = 12, color = base.color(.Muted)})
		}
		f := &ls.sizes[i]
		res := primer.text_input_with_tokens(gtx, &f.text, f.labels[:f.n], primer.Token_Size(i), placeholder = "Add a label", width = 360, key = u64(i + 1))
		remove_label(f, res.removed)
	}
	kitchen.section(gtx, "Visuals, validation and collapse", "leading and trailing octicons; error borders the field; visible_count shows +N until the field has focus")
	{
		f := &ls.collapse
		res := primer.text_input_with_tokens(gtx, &f.text, f.labels[:f.n], .Large, placeholder = "Reviewers", leading = .Person, trailing = .Search, visible_count = 2, width = 360)
		remove_label(f, res.removed)
		f2 := &ls.invalid
		res2 := primer.text_input_with_tokens(gtx, &f2.text, f2.labels[:f2.n], .Large, placeholder = "Labels", validation = .Error, width = 360)
		remove_label(f2, res2.removed)
		f3 := &ls.disabled
		primer.text_input_with_tokens(gtx, &f3.text, f3.labels[:f3.n], .Large, placeholder = "Disabled", width = 360, state = .Disabled)
	}
}

page_autocomplete :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	ls := &m.lists
	kitchen.section(gtx, "Single", "typing opens matches; Up and Down move the highlight, which completes inline; Enter chooses and writes its text")
	{
		ui.sized(gtx, {min = {300, 0}, max = {300, ui.INF}})
		r := primer.autocomplete(gtx, &ls.fruit_text, FRUITS[:], ls.fruit[:], placeholder = "Choose a fruit", block = true)
		if r.changed {
			ls.said = "chose a fruit"
		}
	}
	kitchen.section(gtx, "Multiple, with tokens", "choices become tokens; choosing clears the input and keeps the menu open; Backspace in the empty input takes the last back")
	{
		ui.sized(gtx, {min = {360, 0}, max = {360, ui.INF}})
		r := primer.autocomplete(gtx, &ls.tag_text, FRUITS[:], ls.tags[:], tokens = true, placeholder = "Add fruits", add_new = "Add a new fruit", block = true)
		if r.added {
			ls.said = "add new"
		}
	}
	said(gtx, ls.said)
}

FRUITS := [8]primer.Autocomplete_Item {
	{text = "Apple", leading = .Star},
	{text = "Apricot"},
	{text = "Banana"},
	{text = "Blueberry"},
	{text = "Cherry", description = "out of season", disabled = true},
	{text = "Grape"},
	{text = "Lemon"},
	{text = "Lime"},
}

// seed_lists gives the token fields their first labels.
@(private = "file")
seed_lists :: proc(ls: ^Lists) {
	ls.seeded = true
	for &f in ls.sizes {
		f.labels[0], f.labels[1], f.labels[2] = "bug", "enhancement", "docs"
		f.n = 3
	}
	ls.collapse.labels = {"mona", "hubot", "octocat", "monalisa", "", "", "", ""}
	ls.collapse.n = 4
	ls.invalid.labels[0] = "wontfix"
	ls.invalid.n = 1
	ls.disabled.labels[0], ls.disabled.labels[1] = "frozen", "locked"
	ls.disabled.n = 2
}

PANEL_LABELS := [8]primer.Select_Panel_Item {
	{text = "bug", description = "Something isn't working", leading = .Tag, group = 0},
	{text = "documentation", description = "Improvements or additions", leading = .Tag, group = 0},
	{text = "enhancement", leading = .Tag, group = 0},
	{text = "good first issue", leading = .Tag, group = 1},
	{text = "help wanted", leading = .Tag, group = 1},
	{text = "question", leading = .Tag, group = 1},
	{text = "wontfix", leading = .Tag, group = 1, disabled = true},
	{text = "duplicate", leading = .Tag, group = 1},
}

PANEL_GROUPS := [2]primer.Select_Panel_Group{{"Type", .Filled}, {"Triage", .Filled}}

// filtered is the labels matching the filter text, case-blind anywhere,
// and the selection flags that go with them: SelectPanel leaves
// filtering to its caller.
@(private = "file")
filtered :: proc(gtx: ^ui.Ctx, text: string, sel: []bool) -> (items: []primer.Select_Panel_Item, flags: []bool, owners: []int) {
	out := make([dynamic]primer.Select_Panel_Item, gtx.allocator)
	fl := make([dynamic]bool, gtx.allocator)
	ow := make([dynamic]int, gtx.allocator)
	needle := strings.to_lower(text, gtx.allocator)
	for it, i in PANEL_LABELS {
		if strings.contains(strings.to_lower(it.text, gtx.allocator), needle) {
			append(&out, it)
			append(&fl, sel[i])
			append(&ow, i)
		}
	}
	return out[:], fl[:], ow[:]
}

page_select_panel :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	ls := &m.lists
	kitchen.section(gtx, "Multiple, anchored", "a filter over grouped checkbox options; focus stays in the filter, Up and Down move the highlight, Enter toggles")
	{
		ui.stack(gtx)
		primer.select_panel_button(gtx, &ls.panel, PANEL_LABELS[:], ls.panel_sel[:], "Labels", leading = .Tag)
		anchor := ui.last_widget(gtx)
		items, flags, owners := filtered(gtx, ui.text_string(&ls.panel_filter), ls.panel_sel[:])
		r := primer.select_panel(gtx, &ls.panel, anchor, &ls.panel_filter, items, flags, multiple = true, title = "Apply labels", subtitle = "Choose any that fit", groups = PANEL_GROUPS[:], select_all = true, secondary = "Edit labels")
		for f, i in flags {
			ls.panel_sel[owners[i]] = f
		}
		if r.closed != .None {
			ls.said = fmt.aprintf("closed by %v", r.closed)
		}
	}
	kitchen.section(gtx, "Single, anchored", "a checkmark column; choosing selects and closes, choosing the selection clears it")
	{
		ui.stack(gtx)
		primer.select_panel_button(gtx, &ls.single_panel, PANEL_LABELS[:], ls.single_sel[:], "Choose a label")
		anchor := ui.last_widget(gtx)
		items, flags, owners := filtered(gtx, ui.text_string(&ls.single_filter), ls.single_sel[:])
		primer.select_panel(gtx, &ls.single_panel, anchor, &ls.single_filter, items, flags, title = "Choose a label")
		for f, i in flags {
			ls.single_sel[owners[i]] = f
		}
	}
	kitchen.section(gtx, "Single, modal", "centred over a backdrop; radios hold the choice until Save")
	{
		ui.stack(gtx)
		primer.select_panel_button(gtx, &ls.modal_panel, PANEL_LABELS[:], ls.modal_sel[:], "Choose in a modal")
		anchor := ui.last_widget(gtx)
		items, flags, owners := filtered(gtx, ui.text_string(&ls.modal_filter), ls.modal_sel[:])
		primer.select_panel(gtx, &ls.modal_panel, anchor, &ls.modal_filter, items, flags, variant = .Modal, title = "Choose a label")
		for f, i in flags {
			ls.modal_sel[owners[i]] = f
		}
	}
	said(gtx, ls.said)
}
