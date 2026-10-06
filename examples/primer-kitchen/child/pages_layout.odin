package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/primer"

import "../../kitchen"

// Layouts is the layout pages' demo state.
Layouts :: struct {
	stars:      int,
	home:       int,
	gap:        primer.Stack_Space,
	justify:    primer.Stack_Justify,
	horizontal: bool,
	pane_width: f32, // the resizable pane's, saved by the page when it settles
	saved:      int,
	split_width: f32,
	sidebar_width: f32, // the resizable sidebar's
	sidebar_open:  bool, // the fullscreen sidebar shows
	backs:      int,
}

// The layout pages, on the primer-kit's components/stack.json,
// card.json, header.json, page-header.json, page-layout.json and
// split-page-layout.json.

STACK_SPACE_NAMES := [primer.Stack_Space]string {
	.None      = "none",
	.Tight     = "tight",
	.Condensed = "condensed",
	.Cozy      = "cozy",
	.Normal    = "normal",
	.Spacious  = "spacious",
}
JUSTIFY_NAMES := [primer.Stack_Justify]string {
	.Start         = "start",
	.Center        = "center",
	.End           = "end",
	.Space_Between = "space-between",
	.Space_Evenly  = "space-evenly",
}

// chip is a small labelled tile a layout page arranges, so its gaps and
// padding show.
chip :: proc(gtx: ^ui.Ctx, text: string, key: u64 = 0, loc := #caller_location) {
	ui.box(gtx, {fill = primer.color(.Bg_Color_Accent_Muted), radius = 6, padding = {10, 6, 10, 6}}, key, loc)
	base.label(gtx, text, {size = 12, color = primer.color(.Fg_Color_Accent)})
}

// outline is a box drawn round what a page lays out, since a Stack draws
// nothing of its own.
outline_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> ui.Box {
	return ui.box_open(gtx, {outline = primer.color(.Border_Color_Default), stroke = 1, radius = 6}, key, loc)
}

page_stack :: proc(gtx: ^ui.Ctx, m: ^Model) {
	l := &m.layouts
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(gtx, "Gap", "none 0, tight 4, condensed 8, cozy 12, normal 16, spacious 24px between children")
	for name, g in STACK_SPACE_NAMES {
		ui.row(gtx, gap = 12, align = .Center, key = u64(g))
		sz := ui.sized_open(gtx, {min = {90, 0}, max = {90, ui.INF}})
		base.label(gtx, name, {size = 12, color = primer.color(.Fg_Color_Muted)})
		ui.close(&sz)
		primer.stack(gtx, gap = g, direction = .Horizontal)
		chip(gtx, "One")
		chip(gtx, "Two")
		chip(gtx, "Three")
	}
	kitchen.section(gtx, "Justify", "start, center, end, space-between and space-evenly along a 480px row")
	for name, j in JUSTIFY_NAMES {
		ui.row(gtx, gap = 12, align = .Center, key = u64(10 + int(j)))
		sz := ui.sized_open(gtx, {min = {90, 0}, max = {90, ui.INF}})
		base.label(gtx, name, {size = 12, color = primer.color(.Fg_Color_Muted)})
		ui.close(&sz)
		ui.sized(gtx, {min = {480, 0}, max = {480, ui.INF}})
		o := outline_open(gtx)
		s := primer.stack_open(gtx, gap = .Condensed, direction = .Horizontal, justify = j, padding = .Condensed)
		chip(gtx, "A")
		chip(gtx, "B")
		chip(gtx, "C")
		primer.stack_close(&s)
		ui.close(&o)
	}
	kitchen.section(gtx, "Align and padding", "align stretch, start, center and end across a column; padding normal (16px)")
	{
		ui.row(gtx, gap = 16)
		ALIGNS := [?]primer.Stack_Align{.Stretch, .Start, .Center, .End}
		for a, i in ALIGNS {
			ui.sized(gtx, {min = {160, 0}, max = {160, ui.INF}}, key = u64(i))
			o := outline_open(gtx)
			s := primer.stack_open(gtx, gap = .Condensed, align = a, padding = .Normal)
			chip(gtx, fmt.tprintf("%v", a))
			chip(gtx, "Wider child")
			primer.stack_close(&s)
			ui.close(&o)
		}
	}
	kitchen.section(gtx, "Wrap and grow", "a wrapping row reflows at its width with the gap between lines too; a Stack.Item that grows takes the rest")
	{
		ui.row(gtx)
		ui.sized(gtx, {min = {320, 0}, max = {320, ui.INF}})
		o := outline_open(gtx)
		s := primer.stack_open(gtx, gap = .Condensed, direction = .Horizontal, wrap = true, padding = .Condensed)
		for word in ([?]string{"layout", "data", "stack", "card", "header", "table", "pane", "grid"}) {
			chip(gtx, word)
		}
		primer.stack_close(&s)
		ui.close(&o)
	}
	{
		o := outline_open(gtx)
		s := primer.stack_open(gtx, gap = .Condensed, direction = .Horizontal, padding = .Condensed, align = .Center)
		chip(gtx, "Fixed")
		primer.stack_item(gtx)
		{
			b := ui.box_open(gtx, {fill = primer.color(.Bg_Color_Success_Muted), radius = 6, padding = {10, 6, 10, 6}})
			base.label(gtx, "Grows", {size = 12, color = primer.color(.Fg_Color_Success)})
			ui.close(&b)
		}
		chip(gtx, "Fixed")
		primer.stack_close(&s)
		ui.close(&o)
	}
	kitchen.section(gtx, "Live", "the gap and justify follow the buttons; a responsive gap is condensed below 768px and spacious from 1400px")
	{
		ui.wrap(gtx, gap = 8, align = .Center)
		if primer.button(gtx, fmt.tprintf("Gap: %s", STACK_SPACE_NAMES[l.gap]), key = 1) {
			l.gap = primer.Stack_Space((int(l.gap) + 1) % len(primer.Stack_Space))
		}
		if primer.button(gtx, fmt.tprintf("Justify: %s", JUSTIFY_NAMES[l.justify]), key = 2) {
			l.justify = primer.Stack_Justify((int(l.justify) + 1) % len(primer.Stack_Justify))
		}
	}
	{
		o := outline_open(gtx)
		s := primer.stack_open(gtx, gap = l.gap, direction = .Horizontal, justify = l.justify, padding = .Normal)
		chip(gtx, "Alpha")
		chip(gtx, "Beta")
		chip(gtx, "Gamma")
		primer.stack_close(&s)
		ui.close(&o)
	}
	{
		g := primer.responsive(gtx, primer.Responsive(primer.Stack_Space){narrow = .Condensed, wide = .Spacious}, primer.Stack_Space.Normal)
		o := outline_open(gtx)
		s := primer.stack_open(gtx, gap = g, direction = .Horizontal, padding = .Normal)
		chip(gtx, fmt.tprintf("At this window: %s", STACK_SPACE_NAMES[g]))
		chip(gtx, "Responsive")
		primer.stack_close(&s)
		ui.close(&o)
	}
}

page_card :: proc(gtx: ^ui.Ctx, m: ^Model) {
	l := &m.layouts
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(gtx, "Default", "1px border, resting-small shadow, 24px padding, 12px corners; the icon in a 32px muted tile; the action 16px from the corner")
	{
		ui.row(gtx, gap = 16, align = .Start)
		{
			ui.sized(gtx, {min = {320, 0}, max = {320, ui.INF}})
			c := primer.card_open(gtx, "primer/react", "React components for the Primer design system", icon = .Repo, standalone = true)
			primer.card_metadata_open(&c)
			primer.card_metadata_item(gtx, fmt.tprintf("%d stars", 3200 + l.stars), .Star)
			primer.card_metadata_item(gtx, "Updated today", .Clock)
			primer.card_metadata_close(&c)
			primer.card_action_open(&c)
			if primer.icon_button(gtx, .Star, "Star primer/react", .Invisible, .Small) {
				l.stars += 1
			}
			primer.card_action_close(&c)
			primer.card_close(&c)
		}
		{
			ui.sized(gtx, {min = {320, 0}, max = {320, ui.INF}})
			primer.card(gtx, "Medium corners", "Condensed padding, 8px, and medium (6px) corners", radius = .Medium, padding = .Condensed)
		}
	}
	kitchen.section(gtx, "Compact", "the bare icon beside the body, 8px apart; 16px padding; the heading at body size raised 4px")
	{
		ui.row(gtx)
		ui.sized(gtx, {min = {360, 0}, max = {360, ui.INF}})
		c := primer.card_open(gtx, "Compact card", "Its icon sits beside the heading rather than above it", icon = .Repo, layout = .Compact)
		primer.card_metadata_open(&c)
		primer.card_metadata_item(gtx, "Primer", .Mark_Github)
		primer.card_metadata_close(&c)
		primer.card_close(&c)
	}
}

page_header :: proc(gtx: ^ui.Ctx, m: ^Model) {
	l := &m.layouts
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(gtx, "Link states", "the logo colour dims to the bar's default on hover and focus; a keyboard focus adds the outline")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			ui.box(gtx, {fill = primer.color(.Header_Bg_Color), padding = {8, 4, 8, 4}}, key)
			primer.header_link(gtx, "GitHub", .Mark_Github, 24, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Link", cell, 1)
	}
	kitchen.section(gtx, "Bar", "dark in every theme; 16px padding; each item 16px apart; the full item takes the free width")
	{
		primer.header(gtx)
		{
			primer.header_item(gtx)
			if primer.header_link(gtx, "GitHub", .Mark_Github) {
				l.home += 1
			}
		}
		{
			primer.header_item(gtx, full = true)
			primer.header_link(gtx, "Pull requests", key = 1)
			primer.header_link(gtx, "Issues", key = 2)
			primer.header_link(gtx, "Codespaces", key = 3)
		}
		{
			primer.header_item(gtx)
			primer.header_link(gtx, "", .Bell, 16, key = 4)
		}
		{
			primer.header_item(gtx)
			primer.header_link(gtx, fmt.tprintf("Home %d", l.home), .Person, 16, key = 5)
		}
	}
	kitchen.section(gtx, "Overflow", "a 360px bar scrolls its items sideways rather than wrapping them")
	{
		ui.row(gtx)
		ui.sized(gtx, {min = {360, 0}, max = {360, ui.INF}})
		primer.header(gtx)
		for name, i in ([?]string{"Overview", "Repositories", "Projects", "Packages", "Stars"}) {
			primer.header_item(gtx, key = u64(i))
			primer.header_link(gtx, name, key = u64(10 + i))
		}
	}
}

// region_box stands in for a page region's content: a muted panel h tall
// with its name, filling the region's width.
region_box :: proc(gtx: ^ui.Ctx, name: string, h: f32, key: u64 = 0, loc := #caller_location) {
	ui.column(gtx, align = .Fill, key = key, loc = loc)
	ui.sized(gtx, {min = {0, h}, max = {0, h}})
	ui.box(gtx, {fill = primer.color(.Bg_Color_Muted), outline = primer.color(.Border_Color_Muted), stroke = 1, radius = 6, padding = {12, 8, 12, 8}})
	base.label(gtx, name, {size = 12, color = primer.color(.Fg_Color_Muted)})
}

// preview lays its body out as if the window were width wide, so a page
// shows a layout's narrow range inside a wide kitchen.
Preview :: struct {
	gtx:    ^ui.Ctx,
	viewport: [2]f32,
	row:    ui.Flex,
	sized:  ui.Inset,
}

preview_open :: proc(gtx: ^ui.Ctx, width: f32, key: u64 = 0, loc := #caller_location) -> (p: Preview) {
	p.gtx, p.viewport = gtx, gtx.viewport
	p.row = ui.row_open(gtx, key = key, loc = loc)
	p.sized = ui.sized_open(gtx, {min = {width, 0}, max = {width, ui.INF}})
	gtx.viewport.x = width
	return
}

preview_close :: proc(p: ^Preview) {
	p.gtx.viewport = p.viewport
	ui.close(&p.sized)
	ui.close(&p.row)
}

// demo_page_header is a page header with every row-2 slot filled, the
// context area's parent link, a description and a bordered bottom.
demo_page_header :: proc(gtx: ^ui.Ctx, m: ^Model, title: string, variant: primer.Title_Variant, key: u64 = 0) {
	l := &m.layouts
	h := primer.page_header_open(gtx, title, variant, leading_visual = .Repo, has_border = true, key = key)
	primer.page_header_parent_link(&h, "Repositories")
	primer.page_header_slot_open(&h, .Leading_Action)
	if primer.icon_button(gtx, .Arrow_Left, "Back", .Invisible, key = key) {
		l.backs += 1
	}
	primer.page_header_slot_close(&h)
	primer.page_header_slot_open(&h, .Trailing_Action)
	primer.icon_button(gtx, .Pencil, "Rename", .Invisible, key = key)
	primer.page_header_slot_close(&h)
	primer.page_header_slot_open(&h, .Actions)
	primer.button(gtx, "Watch", leading = .Eye, count = "12", key = key)
	primer.button(gtx, "Star", .Primary, leading = .Star, key = key)
	primer.page_header_slot_close(&h)
	primer.page_header_slot_open(&h, .Description)
	base.label(gtx, fmt.tprintf("Updated 2 days ago; back pressed %d times", l.backs), {size = 14, color = primer.color(.Fg_Color_Muted)})
	primer.page_header_slot_close(&h)
	primer.page_header_close(&h)
}

page_page_header :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(gtx, "Regular", "leading action, 16px visual, title, trailing action, then the actions end-aligned; each one title line tall; a 1px rule 8px under it")
	demo_page_header(gtx, m, "primer/react", .Medium, 1)
	kitchen.section(gtx, "Large and subtitle", "32px normal on a 48px line; 20px normal")
	demo_page_header(gtx, m, "Large title", .Large, 2)
	demo_page_header(gtx, m, "A subtitle", .Subtitle, 3)
	kitchen.section(gtx, "Wrapping", "a long title wraps beside the actions, which keep their width")
	{
		p := preview_open(gtx, 900, key = 4)
		demo_page_header(gtx, m, "A long title that does not fit on one line beside its actions at this width", .Medium, 4)
		preview_close(&p)
	}
	kitchen.section(gtx, "Narrow (a 600px window)", "below 768px the leading and trailing actions hide and the parent link shows above the title")
	{
		p := preview_open(gtx, 600, key = 5)
		demo_page_header(gtx, m, "primer/react", .Medium, 5)
		preview_close(&p)
	}
}

// demo_page_layout is a page layout of placeholder regions, its pane
// resizable and sticky, its width saved when it settles.
demo_page_layout :: proc(gtx: ^ui.Ctx, m: ^Model, position: primer.Pane_Position, divider: primer.Pane_Divider, content_h: f32, key: u64) {
	l := &m.layouts
	pane := primer.Pane{position = position, resizable = true, sticky = true, divider = divider, width = &l.pane_width, padding = .Condensed}
	pl := primer.page_layout_open(gtx, pane = pane, key = key)
	primer.page_layout_region_open(&pl, .Header, divider = .Line)
	region_box(gtx, "Header", 48)
	primer.page_layout_region_close(&pl)
	primer.page_layout_region_open(&pl, .Content)
	region_box(gtx, "Content", content_h)
	primer.page_layout_region_close(&pl)
	primer.page_layout_region_open(&pl, .Pane)
	region_box(gtx, fmt.tprintf("Pane, %dpx (saved %d times)", int(l.pane_width), l.saved), 240)
	primer.page_layout_region_close(&pl)
	primer.page_layout_region_open(&pl, .Footer, divider = .Line)
	region_box(gtx, "Footer", 40)
	primer.page_layout_region_close(&pl)
	if primer.page_layout_close(&pl) {
		l.saved += 1
	}
}

page_page_layout :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(gtx, "Regular", "24px padding and gaps from 1012px; the pane at the end behind a line divider centred in two gaps; drag the 5px handle, arrow it, double-click to reset; the pane is sticky as the page scrolls")
	demo_page_layout(gtx, m, .End, .Line, 900, 1)
	kitchen.section(gtx, "Narrow (a 600px window)", "below 768px the pane stacks full width, here above the content, behind a filled divider that reaches the page's edges")
	{
		p := preview_open(gtx, 600, key = 2)
		demo_page_layout(gtx, m, .Start, .Filled, 160, 2)
		preview_close(&p)
	}
	l := &m.layouts
	kitchen.section(gtx, "Sidebar", "a full-height column outside the container, beside header, content and footer alike; resizable from 256px to the window less 256px behind its line divider")
	{
		ui.box(gtx, {outline = primer.color(.Border_Color_Default), stroke = 1}, key = 3)
		side := primer.Sidebar{resizable = true, width = &l.sidebar_width, label = "Sidebar splitter"}
		demo_sidebar_layout(gtx, m, side, fmt.tprintf("Sidebar, %dpx", int(l.sidebar_width)), 3)
	}
	kitchen.section(gtx, "Sidebar at the end, narrow (a 600px window)", "the default variant stays beside the container below 768px and squeezes it")
	{
		p := preview_open(gtx, 600, key = 4)
		demo_sidebar_layout(gtx, m, {position = .End, divider = .Line}, "Sidebar", 4)
		preview_close(&p)
	}
	kitchen.section(gtx, "Fullscreen sidebar (a 600px window)", "below 768px the fullscreen variant covers the window on the default background; the page shows and hides it")
	{
		p := preview_open(gtx, 600, key = 5)
		stack := ui.column_open(gtx, gap = 10, align = .Start)
		if primer.button(gtx, l.sidebar_open ? "Close the sidebar" : "Open the sidebar", key = 5) {
			l.sidebar_open = !l.sidebar_open
		}
		demo_sidebar_layout(gtx, m, {variant = .Fullscreen, hidden = !l.sidebar_open}, "Fullscreen sidebar", 5)
		ui.close(&stack)
		preview_close(&p)
	}
}

// demo_sidebar_layout is a page layout of placeholder regions with
// sidebar beside them, its width saved when it settles.
demo_sidebar_layout :: proc(gtx: ^ui.Ctx, m: ^Model, sidebar: primer.Sidebar, label: string, key: u64) {
	l := &m.layouts
	pl := primer.page_layout_open(gtx, sidebar = sidebar, key = key)
	primer.page_layout_region_open(&pl, .Sidebar)
	{
		ui.column(gtx, gap = 8, align = .Fill)
		region_box(gtx, label, 120)
		if sidebar.variant == .Fullscreen && primer.button(gtx, "Close the sidebar", key = key + 100) {
			l.sidebar_open = false
		}
	}
	primer.page_layout_region_close(&pl)
	primer.page_layout_region_open(&pl, .Header, divider = .Line)
	region_box(gtx, "Header", 48)
	primer.page_layout_region_close(&pl)
	primer.page_layout_region_open(&pl, .Content)
	region_box(gtx, "Content", 160)
	primer.page_layout_region_close(&pl)
	primer.page_layout_region_open(&pl, .Footer, divider = .Line)
	region_box(gtx, "Footer", 40)
	primer.page_layout_region_close(&pl)
	if primer.page_layout_close(&pl) {
		l.saved += 1
	}
}

page_split_page_layout :: proc(gtx: ^ui.Ctx, m: ^Model) {
	l := &m.layouts
	ui.column(gtx, gap = 10, align = .Fill)
	kitchen.section(gtx, "Split", "no padding or gaps: a sticky start pane flush with the edge, line dividers touching the padded header, content and footer")
	ui.box(gtx, {outline = primer.color(.Border_Color_Default), stroke = 1})
	pane := primer.SPLIT_PANE
	pane.resizable = true
	pane.width = &l.split_width
	pl := primer.split_page_layout_open(gtx, pane)
	primer.split_page_layout_region_open(&pl, .Header)
	region_box(gtx, "Header", 40)
	primer.page_layout_region_close(&pl)
	primer.split_page_layout_region_open(&pl, .Pane)
	region_box(gtx, "Pane", 260)
	primer.page_layout_region_close(&pl)
	primer.split_page_layout_region_open(&pl, .Content)
	region_box(gtx, "Content, capped at 1012px", 600)
	primer.page_layout_region_close(&pl)
	primer.split_page_layout_region_open(&pl, .Footer)
	region_box(gtx, "Footer", 40)
	primer.page_layout_region_close(&pl)
	primer.page_layout_close(&pl)
}
