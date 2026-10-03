package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/primer"

import "../../kitchen"

// Navs is the navigation pages' demo state.
Navs :: struct {
	tree:      Tree_Demo,
	tree_said: string, // the last tree event
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
