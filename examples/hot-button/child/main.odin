// The M3 "all buttons" stress test: every M3 button type with a shipped
// or spec'd definition (elevated, filled, filled tonal, outlined, text,
// icon, FAB small/regular/large, extended FAB, segmented, split), each
// live against the real widgets in ui/widget_button.odin, widget_icon_
// button.odin, widget_fab.odin, widget_segmented_button.odin, widget_
// split_button.odin and theme.odin. Every row is the actual widget — hover,
// click and Tab/Enter it; there's no separate "preview" rendering path.
// Not included: a FAB menu and a split button's actual dropdown menu, both
// of which need a popup/overlay system jm:ui doesn't have.
//
//	hot-button-child                          run as the subprocess
//	hot-button-child -dump                    the scene ops as text
//	hot-button-child -png build/button.png    render it headlessly
package main

import "core:fmt"
import "core:os"
import "jm:ui"
import "jm:ui/child"
import "jm:ui/render"

WIDTH :: 720
HEIGHT :: 700

Model :: struct {
	count:          int,
	icon_off:       bool,
	icon_on:        bool,
	segmented:      [3]bool,
	split_expanded: bool,
}

hot_button_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	th := gtx.theme
	ops := gtx.ops
	ui.fill(ops, ui.Rect{0, 0, gtx.constraints.max.x, gtx.constraints.max.y}, th.bg)

	page := ui.inset(gtx, ui.pad_all(20))
	defer ui.end(&page)
	col := ui.column(gtx, gap = 14)
	defer ui.end(&col)

	ui.label(gtx, "M3 all-buttons stress test", {size = th.heading_size})
	ui.label(gtx, "edit ui/widget_button.odin, widget_icon_button.odin, widget_fab.odin or theme.odin and save", {size = 11, color = th.muted})

	kind_row(gtx, "Elevated", .Elevated, m, 10)
	kind_row(gtx, "Filled", .Filled, m, 20)
	kind_row(gtx, "Filled tonal", .Tonal, m, 30)
	kind_row(gtx, "Outlined", .Outlined, m, 40)
	kind_row(gtx, "Text", .Text, m, 50)

	{
		r := ui.row(gtx, gap = 16, align = .Center)
		defer ui.end(&r)
		ui.label(gtx, "Icon button", {size = 11, color = th.muted})
		ui.icon_button(gtx, "♥", &m.icon_off, key = 60)
		ui.icon_button(gtx, "♥", &m.icon_on, key = 61)
		ui.icon_button(gtx, "♥", &m.icon_off, disabled = true, key = 62)
	}
	{
		r := ui.row(gtx, gap = 16, align = .Center)
		defer ui.end(&r)
		ui.label(gtx, "FAB", {size = 11, color = th.muted})
		if ui.fab(gtx, "+", .Small, key = 70) {}
		if ui.fab(gtx, "+", .Regular, key = 71) {}
		if ui.fab(gtx, "+", .Large, key = 72) {}
	}
	{
		r := ui.row(gtx, gap = 16, align = .Center)
		defer ui.end(&r)
		ui.label(gtx, "Extended FAB", {size = 11, color = th.muted})
		if ui.extended_fab(gtx, "+", "Compose", key = 80) {}
	}
	{
		r := ui.row(gtx, gap = 16, align = .Center)
		defer ui.end(&r)
		ui.label(gtx, "Segmented", {size = 11, color = th.muted})
		labels := [3]string{"Day", "Week", "Month"}
		ui.segmented_button(gtx, labels[:], m.segmented[:], key = 90)
	}
	{
		r := ui.row(gtx, gap = 16, align = .Center)
		defer ui.end(&r)
		ui.label(gtx, "Split", {size = 11, color = th.muted})
		ui.split_button(gtx, "Save", &m.split_expanded, key = 100)
	}
}

// kind_row is one M3 common-button kind: a live enabled instance (counts
// its own clicks so hover/press/focus are visible against a real click
// count) and a live disabled twin, side by side.
kind_row :: proc(gtx: ^ui.Ctx, label: string, kind: ui.Button_Kind, m: ^Model, key: u64) {
	th := gtx.theme
	r := ui.row(gtx, gap = 16, align = .Center)
	defer ui.end(&r)
	ui.label(gtx, label, {size = 11, color = th.muted})
	if ui.button(gtx, fmt.tprintf("Click %d", m.count), {kind = kind}, key = key) {
		m.count += 1
	}
	ui.button(gtx, "Disabled", {kind = kind}, disabled = true, key = key + 1)
}

main :: proc() {
	m: Model
	m.icon_on = true // so the selected icon-button state is visible without a click
	m.segmented[1] = true // so the selected segment is visible without a click

	if len(os.args) == 1 {
		child.run({ui = hot_button_ui, user = &m, fonts = {{0, ui.default_font()}}})
		return
	}

	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		switch args[i] {
		case "-dump":
			p: ui.Probe
			ui.probe_init(&p, hot_button_ui, &m, {WIDTH, HEIGHT})
			defer ui.probe_destroy(&p)
			fmt.print(ui.probe_dump(&p))
		case "-png":
			if i + 1 >= len(args) {
				fmt.eprintln("-png needs a path")
				os.exit(2)
			}
			i += 1
			path := args[i]
			if !render.snapshot(hot_button_ui, &m, {WIDTH, HEIGHT}, {{0, ui.default_font()}}, path) {
				fmt.eprintfln("could not write %s", path)
				os.exit(1)
			}
		case:
			fmt.eprintfln("unknown flag %s", args[i])
			os.exit(2)
		}
	}
}
