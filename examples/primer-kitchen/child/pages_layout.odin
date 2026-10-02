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
}

// The layout and data pages, on the primer-kit's components/stack.json,
// card.json, header.json, page-header.json, page-layout.json,
// split-page-layout.json and data-table.json.

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
	b := ui.box_open(gtx, {fill = primer.color(.Bg_Color_Accent_Muted), radius = 6, padding = {10, 6, 10, 6}}, key, loc)
	defer ui.close(&b)
	base.label(gtx, text, {size = 12, color = primer.color(.Fg_Color_Accent)})
}

// outline is a box drawn round what a page lays out, since a Stack draws
// nothing of its own.
outline_open :: proc(gtx: ^ui.Ctx, key: u64 = 0, loc := #caller_location) -> ui.Box {
	return ui.box_open(gtx, {outline = primer.color(.Border_Color_Default), stroke = 1, radius = 6}, key, loc)
}

page_stack :: proc(gtx: ^ui.Ctx, m: ^Model) {
	l := &m.layouts
	col := ui.column_open(gtx, gap = 10, align = .Fill)
	defer ui.close(&col)
	kitchen.section(gtx, "Gap", "none 0, tight 4, condensed 8, cozy 12, normal 16, spacious 24px between children")
	for name, g in STACK_SPACE_NAMES {
		r := ui.row_open(gtx, gap = 12, align = .Center, key = u64(g))
		sz := ui.sized_open(gtx, {min = {90, 0}, max = {90, ui.INF}})
		base.label(gtx, name, {size = 12, color = primer.color(.Fg_Color_Muted)})
		ui.close(&sz)
		s := primer.stack_open(gtx, gap = g, direction = .Horizontal)
		chip(gtx, "One")
		chip(gtx, "Two")
		chip(gtx, "Three")
		primer.stack_close(&s)
		ui.close(&r)
	}
	kitchen.section(gtx, "Justify", "start, center, end, space-between and space-evenly along a 480px row")
	for name, j in JUSTIFY_NAMES {
		r := ui.row_open(gtx, gap = 12, align = .Center, key = u64(10 + int(j)))
		sz := ui.sized_open(gtx, {min = {90, 0}, max = {90, ui.INF}})
		base.label(gtx, name, {size = 12, color = primer.color(.Fg_Color_Muted)})
		ui.close(&sz)
		w := ui.sized_open(gtx, {min = {480, 0}, max = {480, ui.INF}})
		o := outline_open(gtx)
		s := primer.stack_open(gtx, gap = .Condensed, direction = .Horizontal, justify = j, padding = .Condensed)
		chip(gtx, "A")
		chip(gtx, "B")
		chip(gtx, "C")
		primer.stack_close(&s)
		ui.close(&o)
		ui.close(&w)
		ui.close(&r)
	}
	kitchen.section(gtx, "Align and padding", "align stretch, start, center and end across a column; padding normal (16px)")
	{
		r := ui.row_open(gtx, gap = 16)
		defer ui.close(&r)
		ALIGNS := [?]primer.Stack_Align{.Stretch, .Start, .Center, .End}
		for a, i in ALIGNS {
			w := ui.sized_open(gtx, {min = {160, 0}, max = {160, ui.INF}}, key = u64(i))
			o := outline_open(gtx)
			s := primer.stack_open(gtx, gap = .Condensed, align = a, padding = .Normal)
			chip(gtx, fmt.tprintf("%v", a))
			chip(gtx, "Wider child")
			primer.stack_close(&s)
			ui.close(&o)
			ui.close(&w)
		}
	}
	kitchen.section(gtx, "Wrap and grow", "a wrapping row reflows at its width with the gap between lines too; a Stack.Item that grows takes the rest")
	{
		r := ui.row_open(gtx)
		defer ui.close(&r)
		w := ui.sized_open(gtx, {min = {320, 0}, max = {320, ui.INF}})
		o := outline_open(gtx)
		s := primer.stack_open(gtx, gap = .Condensed, direction = .Horizontal, wrap = true, padding = .Condensed)
		for word in ([?]string{"layout", "data", "stack", "card", "header", "table", "pane", "grid"}) {
			chip(gtx, word)
		}
		primer.stack_close(&s)
		ui.close(&o)
		ui.close(&w)
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
		r := ui.wrap_open(gtx, gap = 8, align = .Center)
		if primer.button(gtx, fmt.tprintf("Gap: %s", STACK_SPACE_NAMES[l.gap]), key = 1) {
			l.gap = primer.Stack_Space((int(l.gap) + 1) % len(primer.Stack_Space))
		}
		if primer.button(gtx, fmt.tprintf("Justify: %s", JUSTIFY_NAMES[l.justify]), key = 2) {
			l.justify = primer.Stack_Justify((int(l.justify) + 1) % len(primer.Stack_Justify))
		}
		ui.close(&r)
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
	col := ui.column_open(gtx, gap = 10, align = .Fill)
	defer ui.close(&col)
	kitchen.section(gtx, "Default", "1px border, resting-small shadow, 24px padding, 12px corners; the icon in a 32px muted tile; the action 16px from the corner")
	{
		r := ui.row_open(gtx, gap = 16, align = .Start)
		defer ui.close(&r)
		{
			w := ui.sized_open(gtx, {min = {320, 0}, max = {320, ui.INF}})
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
			ui.close(&w)
		}
		{
			w := ui.sized_open(gtx, {min = {320, 0}, max = {320, ui.INF}})
			c := primer.card_open(gtx, "Medium corners", "Condensed padding, 8px, and medium (6px) corners", radius = .Medium, padding = .Condensed)
			primer.card_close(&c)
			ui.close(&w)
		}
	}
	kitchen.section(gtx, "Compact", "the bare icon beside the body, 8px apart; 16px padding; the heading at body size raised 4px")
	{
		r := ui.row_open(gtx)
		defer ui.close(&r)
		w := ui.sized_open(gtx, {min = {360, 0}, max = {360, ui.INF}})
		c := primer.card_open(gtx, "Compact card", "Its icon sits beside the heading rather than above it", icon = .Repo, layout = .Compact)
		primer.card_metadata_open(&c)
		primer.card_metadata_item(gtx, "Primer", .Mark_Github)
		primer.card_metadata_close(&c)
		primer.card_close(&c)
		ui.close(&w)
	}
}

page_header :: proc(gtx: ^ui.Ctx, m: ^Model) {
	l := &m.layouts
	col := ui.column_open(gtx, gap = 10, align = .Fill)
	defer ui.close(&col)
	kitchen.section(gtx, "Link states", "the logo colour dims to the bar's default on hover and focus; a keyboard focus adds the outline")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			b := ui.box_open(gtx, {fill = primer.color(.Header_Bg_Color), padding = {8, 4, 8, 4}}, key)
			defer ui.close(&b)
			primer.header_link(gtx, "GitHub", .Mark_Github, 24, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Link", cell, 1)
	}
	kitchen.section(gtx, "Bar", "dark in every theme; 16px padding; each item 16px apart; the full item takes the free width")
	{
		h := primer.header_open(gtx)
		{
			it := primer.header_item_open(gtx)
			if primer.header_link(gtx, "GitHub", .Mark_Github) {
				l.home += 1
			}
			primer.header_item_close(&it)
		}
		{
			it := primer.header_item_open(gtx, full = true)
			primer.header_link(gtx, "Pull requests", key = 1)
			primer.header_link(gtx, "Issues", key = 2)
			primer.header_link(gtx, "Codespaces", key = 3)
			primer.header_item_close(&it)
		}
		{
			it := primer.header_item_open(gtx)
			primer.header_link(gtx, "", .Bell, 16, key = 4)
			primer.header_item_close(&it)
		}
		{
			it := primer.header_item_open(gtx)
			primer.header_link(gtx, fmt.tprintf("Home %d", l.home), .Person, 16, key = 5)
			primer.header_item_close(&it)
		}
		primer.header_close(&h)
	}
	kitchen.section(gtx, "Overflow", "a 360px bar scrolls its items sideways rather than wrapping them")
	{
		r := ui.row_open(gtx)
		defer ui.close(&r)
		w := ui.sized_open(gtx, {min = {360, 0}, max = {360, ui.INF}})
		defer ui.close(&w)
		h := primer.header_open(gtx)
		for name, i in ([?]string{"Overview", "Repositories", "Projects", "Packages", "Stars"}) {
			it := primer.header_item_open(gtx, key = u64(i))
			primer.header_link(gtx, name, key = u64(10 + i))
			primer.header_item_close(&it)
		}
		primer.header_close(&h)
	}
}
