package main

import "core:fmt"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/base"
import "jm:ui/primer"

import "../../kitchen"

// Navs is the navigation pages' demo state.
Navs :: struct {
	tree:      Tree_Demo,
	tree_said: string, // the last tree event
	page:      int, // the live pagination's page
	view:      int, // the live sub nav's link
	tab:       int, // the live underline panels' tab
	manual:    int,
	loading:   bool,
}

// Tree_Demo is the tree view page's items and its lazy folder's loading.
Tree_Demo :: struct {
	roots:      [5]primer.Tree_Item,
	src:        [4]primer.Tree_Item,
	ui:         [3]primer.Tree_Item,
	docs:       [2]primer.Tree_Item,
	lazy:       [3]primer.Tree_Item,
	flat:       [4]primer.Tree_Item,
	actions:    [2]primer.Tree_Action,
	one_action: [1]primer.Tree_Action,
	state:      primer.Tree_Sub_Tree,
	loaded_at:  f64, // when loading began
	skeleton:   bool,
}

// fill_tree_demo fills the page's items for this frame.
@(private = "file")
fill_tree_demo :: proc(d: ^Tree_Demo) -> []primer.Tree_Item {
	d.actions = {{label = "Rename", icon = .Pencil}, {label = "Comments", icon = .Comment, count = "3"}}
	d.one_action = {{label = "Copy path", icon = .Copy}}
	d.ui = {
		{id = "src/ui/tree.odin", label = "tree.odin", leading = .File, current = true, trailing = .Diff_Modified, trailing_label = "modified"},
		{id = "src/ui/layout.odin", label = "layout.odin", leading = .File, actions = d.one_action[:]},
		{id = "src/ui/flatten.odin", label = "flatten.odin", leading = .File, trailing = .Diff_Added, trailing_label = "added"},
	}
	d.src = {
		{id = "src/ui", label = "ui", directory = true, children = d.ui[:], default_expanded = true},
		{id = "src/main.odin", label = "main.odin", leading = .File, actions = d.actions[:]},
		{id = "src/a-very-long-file-name", label = "a_file_with_a_name_long_enough_to_truncate_at_this_width.odin", leading = .File},
		{id = "src/empty", label = "empty", directory = true, sub_tree = .Known},
	}
	d.docs = {{id = "docs/readme.md", label = "readme.md", leading = .File}, {id = "docs/guide.md", label = "guide.md", leading = .File}}
	d.lazy = {{id = "lazy/a", label = "alpha.txt", leading = .File}, {id = "lazy/b", label = "beta.txt", leading = .File}, {id = "lazy/c", label = "gamma.txt", leading = .File}}
	d.roots = {
		{id = "src", label = "src", directory = true, children = d.src[:], default_expanded = true},
		{id = "docs", label = "docs", directory = true, children = d.docs[:]},
		{id = "lazy", label = "lazy (loads in 1.5s)", directory = true, sub_tree = d.state, count = d.skeleton ? 3 : 0, children = d.state == .Done ? d.lazy[:] : nil, error = "The folder could not be read."},
		{id = "broken", label = "broken (fails to load)", directory = true, sub_tree = .Error, error = "Permission denied reading broken/."},
		{id = "LICENSE", label = "LICENSE", leading = .Law},
	}
	return d.roots[:]
}

page_tree_view :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	n := &m.navs
	d := &n.tree
	if d.state == .None {
		d.state = .Initial
	}
	if d.state == .Loading {
		if gtx.time - d.loaded_at > 1.5 {
			d.state = .Done
		} else {
			ui.request_frame(gtx, 0.1)
		}
	}
	kitchen.section(gtx, "Files", "32px rows, 8px a level; the current item's bar sits 8px left; hover shows the level lines; Tab enters at the current item")
	{
		pad := ui.inset_open(gtx, {12, 0, 0, 0})
		defer ui.close(&pad)
		box := ui.sized_open(gtx, {max = {360, 0}})
		defer ui.close(&box)
		ev := primer.tree_view(gtx, fill_tree_demo(d), "Files")
		#partial switch ev.kind {
		case .None:
		case .Expand:
			if ev.id == "lazy" && (d.state == .Initial || d.state == .Error) {
				d.state, d.loaded_at = .Loading, gtx.time
			}
			n.tree_said = fmt.aprintf("%v %s", ev.kind, ev.id)
		case:
			n.tree_said = fmt.aprintf("%v %s %d", ev.kind, ev.id, ev.action)
		}
	}
	{
		r := ui.row_open(gtx, gap = 8, align = .Center)
		defer ui.close(&r)
		if primer.button(gtx, d.skeleton ? "Loading shows 3 skeleton rows" : "Loading shows a spinner", size = .Small) {
			d.skeleton = !d.skeleton
		}
		if primer.button(gtx, "Reset lazy", size = .Small) {
			d.state = .Initial
		}
		if n.tree_said != "" {
			base.label(gtx, n.tree_said, {size = 12, color = base.color(.Muted)})
		}
	}
	kitchen.section(gtx, "Flat", "no indentation or toggle columns")
	{
		pad := ui.inset_open(gtx, {12, 0, 0, 0})
		defer ui.close(&pad)
		box := ui.sized_open(gtx, {max = {360, 0}})
		defer ui.close(&box)
		d.flat = {
			{id = "f1", label = "Issues", leading = .Issue_Opened},
			{id = "f2", label = "Pull requests", leading = .Git_Pull_Request, current = true},
			{id = "f3", label = "Discussions", leading = .Comment_Discussion},
			{id = "f4", label = "Actions", leading = .Play},
		}
		primer.tree_view(gtx, d.flat[:], "Flat", flat = true)
	}
	kitchen.section(gtx, "Wrapped", "truncate off: long labels wrap by word, the visuals stay on the first line")
	{
		pad := ui.inset_open(gtx, {12, 0, 0, 0})
		defer ui.close(&pad)
		box := ui.sized_open(gtx, {max = {260, 0}})
		defer ui.close(&box)
		primer.tree_view(gtx, d.src[2:3], "Wrapped", truncate = false)
	}
}

// state_list shows draw once per forced state, each under its name: the
// navigation components are too wide for the state grid's cells.
@(private = "file")
state_list :: proc(gtx: ^ui.Ctx, m: ^Model, draw: proc(gtx: ^ui.Ctx, m: ^Model, st: primer.Interaction, key: u64)) {
	names := [?]string{"Enabled", "Hovered", "Focused", "Pressed", "Disabled", "Dragged"}
	for st, i in design.STATES {
		if st == .Dragged {
			continue
		}
		r := ui.row_open(gtx, gap = 12, align = .Center, key = u64(900 + i))
		c := ui.sized_open(gtx, {min = {80, 0}, max = {80, ui.INF}})
		base.label(gtx, names[i], {size = 12, color = base.color(.Muted)})
		ui.close(&c)
		ui.flexible(gtx, 1)
		draw(gtx, m, st, u64(i + 1))
		ui.close(&r)
	}
}

page_pagination :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 4)
	defer ui.close(&col)
	n := &m.navs
	if n.page == 0 {
		n.page = 6
	}
	kitchen.section(gtx, "Live", "15 pages: one page at each end, two either side of the current one; an ellipsis never stands for one page")
	primer.pagination(gtx, &n.page, 15)
	kitchen.section(gtx, "Models", "first, last, few pages, and Previous and Next only")
	for c, i in ([4][2]int{{1, 15}, {15, 15}, {3, 5}, {2, 15}}) {
		page := c[0]
		primer.pagination(gtx, &page, c[1], show_pages = i < 3, key = u64(10 + i))
	}
	kitchen.section(gtx, "States", "hover and any focus fade --control-transparent-bgColor-hover in; keyboard focus outlines 2px of --bgColor-accent-emphasis inside")
	state_list(gtx, m, proc(gtx: ^ui.Ctx, m: ^Model, st: primer.Interaction, key: u64) {
		page := 2
		primer.pagination(gtx, &page, 3, state = st, key = key)
	})
}

page_sub_nav :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10, align = .Fill)
	defer ui.close(&col)
	n := &m.navs
	kitchen.section(gtx, "Live", "links joined into one 34px segmented box sharing 1px borders; the selected one fills --bgColor-accent-emphasis; actions sit at the far end")
	links := [3]primer.Sub_Nav_Link{{"Labels", n.view == 0}, {"Milestones", n.view == 1}, {"Projects", n.view == 2}}
	sn := primer.sub_nav_open(gtx, "Issue views", links[:])
	if sn.clicked >= 0 {
		n.view = sn.clicked
	}
	primer.button(gtx, "New label", .Primary)
	primer.sub_nav_close(&sn)
	kitchen.section(gtx, "States", "hover and any focus fade --bgColor-muted in over 200ms; keyboard focus also draws the focus outline")
	state_list(gtx, m, proc(gtx: ^ui.Ctx, m: ^Model, st: primer.Interaction, key: u64) {
		links := [3]primer.Sub_Nav_Link{{"Labels", true}, {"Milestones", false}, {"Projects", false}}
		sn := primer.sub_nav_open(gtx, "States", links[:], state = st, key = key)
		primer.sub_nav_close(&sn)
	})
}

page_underline_panels :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10, align = .Fill)
	defer ui.close(&col)
	n := &m.navs
	tabs := [4]primer.Underline_Tab{{"Code", .Code, ""}, {"Issues", .Issue_Opened, "12"}, {"Pull requests", .Git_Pull_Request, "3"}, {"Actions", .Play, ""}}
	bodies := [4]string{"The repository's files.", "Twelve open issues.", "Three open pull requests.", "Workflow runs."}
	kitchen.section(gtx, "Automatic", "48px strip, 32px tabs 8px apart, a 2px underline on the strip's edge; arrows select as they move")
	{
		up := primer.underline_panels_open(gtx, "Repository", tabs[:], &n.tab, loading_counters = n.loading)
		pad := ui.inset_open(gtx, {16, 12, 16, 12})
		base.label(gtx, bodies[n.tab])
		ui.close(&pad)
		primer.underline_panels_close(&up)
	}
	{
		r := ui.row_open(gtx)
		defer ui.close(&r)
		if primer.button(gtx, n.loading ? "Show counters" : "Load counters", size = .Small) {
			n.loading = !n.loading
		}
	}
	kitchen.section(gtx, "Manual", "arrows move focus only; Enter, Space or a press selects")
	{
		up := primer.underline_panels_open(gtx, "Manual", tabs[:], &n.manual, mode = .Manual)
		pad := ui.inset_open(gtx, {16, 12, 16, 12})
		base.label(gtx, bodies[n.manual])
		ui.close(&pad)
		primer.underline_panels_close(&up)
	}
	kitchen.section(gtx, "Narrow", "a strip narrower than its tabs scrolls sideways")
	{
		r := ui.row_open(gtx)
		box := ui.sized_open(gtx, {max = {280, 0}})
		sel := 0
		up := primer.underline_panels_open(gtx, "Narrow", tabs[:], &sel)
		primer.underline_panels_close(&up)
		ui.close(&box)
		ui.close(&r)
	}
	kitchen.section(gtx, "States", "hover fades --bgColor-neutral-muted in over 120ms; keyboard focus rings the tab inside with 2px of --fgColor-accent")
	state_list(gtx, m, proc(gtx: ^ui.Ctx, m: ^Model, st: primer.Interaction, key: u64) {
		tabs := [3]primer.Underline_Tab{{"Code", .Code, ""}, {"Issues", .Issue_Opened, "12"}, {"Pull requests", .Git_Pull_Request, "3"}}
		sel := 0
		up := primer.underline_panels_open(gtx, "States", tabs[:], &sel, state = st, key = key)
		primer.underline_panels_close(&up)
	})
}
