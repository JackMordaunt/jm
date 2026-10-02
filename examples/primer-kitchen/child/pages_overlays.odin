package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/primer"

import "../../kitchen"

// Overlays is the overlays pages' demo state: which live overlay is
// open, and what the last one reported.
Overlays :: struct {
	overlay:      bool,
	menu:         bool,
	popover:      bool,
	details:      [3]bool,
	dialog:       bool,
	dialog_kind:  int,
	confirm:      bool,
	confirm_kind: int,
	saves:        int,
	said:         string, // the last gesture an overlay reported
}

// The overlay pages, on the primer-kit's components/overlay.json,
// anchored-overlay.json, popover.json, tooltip.json, dialog.json,
// confirmation-dialog.json and details.json. Overlays shown as
// illustrations reopen every frame: a click outside them closes them for
// that frame only.

// region lays out a fixed-height band the static overlays of a section
// float in, so the page leaves room for them.
@(private = "file")
region :: proc(gtx: ^ui.Ctx, h: f32, key: u64) -> ui.Inset {
	return ui.sized_open(gtx, {min = {0, h}, max = {0, h}}, key = key)
}

// lines is a column of muted text lines, an overlay's stand-in content.
@(private = "file")
lines :: proc(gtx: ^ui.Ctx, pad: f32, texts: ..string) {
	pad_box := ui.inset_open(gtx, ui.pad_all(pad))
	defer ui.close(&pad_box)
	col := ui.column_open(gtx, gap = 4)
	defer ui.close(&col)
	for t, i in texts {
		base.label(gtx, t, {size = 14, color = i == 0 ? base.color(.Fg) : base.color(.Muted)}, key = u64(i + 1))
	}
}

page_overlay :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Widths", "--overlay-bgColor, 12px corners, --shadow-floating-small; small 256, medium 320, auto hugs from 192")
	{
		band := region(gtx, 150, 1)
		defer ui.close(&band)
		widths := [3]primer.Overlay_Width{.Small, .Medium, .Auto}
		names := [3]string{"Small, 256px", "Medium, 320px", "Auto"}
		x: f32
		for w, i in widths {
			open := true
			if primer.overlay(gtx, &open, {x, 8}, width = w, focus = {prevent = true}, key = u64(10 + i)) {
				lines(gtx, 16, names[i], "An overlay adds no padding;", "its content brings its own.")
			}
			x += i == 2 ? 0 : (i == 0 ? 280 : 344)
		}
	}
	kitchen.section(gtx, "Live", "opens below the button, fades in and slides 8px down; Escape or a press outside closes it and focus returns")
	o := &m.overlays
	st := ui.stack_open(gtx)
	if primer.button(gtx, o.overlay ? "Close overlay" : "Open overlay", .Primary) {
		o.overlay = !o.overlay
	}
	trigger := ui.last_widget(gtx)
	ov := primer.overlay_open(gtx, &o.overlay, {0, trigger.size.y + 4}, width = .Medium, slide = primer.Anchor_Side.Outside_Bottom, ignore = {0, 0, trigger.size.x, trigger.size.y}, role = .Dialog, name = "Live overlay")
	if ov.visible {
		pad_box := ui.inset_open(gtx, ui.pad_all(12))
		c := ui.column_open(gtx, gap = 8, align = .Fill)
		base.label(gtx, "Focus moved to the first button.")
		primer.button(gtx, "First", block = true)
		primer.button(gtx, "Second", block = true)
		ui.close(&c)
		ui.close(&pad_box)
	}
	if ov.dismissed != .None {
		o.said = fmt.aprintf("closed by %v", ov.dismissed)
	}
	primer.overlay_close(&ov)
	ui.close(&st)
	said(gtx, o.said)
}

// said shows the last gesture an overlay reported.
@(private = "file")
said :: proc(gtx: ^ui.Ctx, s: string) {
	if s != "" {
		base.label(gtx, s, {size = 12, color = base.color(.Muted)}, key = 0x5a1d)
	}
}

ANCHOR_SIDES := [?]primer.Anchor_Side{.Inside_Center, .Outside_Bottom, .Outside_Top, .Outside_Right}
ANCHOR_SIDE_NAMES := [?]string{"Inside center", "Outside bottom", "Outside top", "Outside right"}

page_anchored_overlay :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sides", "4px from the anchor, start-aligned; it flips side, then alignment, then clamps when clipped")
	{
		ui.spacer(gtx, 110)
		r := ui.row_open(gtx, gap = 220, align = .Center)
		defer ui.close(&r)
		for side, i in ANCHOR_SIDES {
			st := ui.stack_open(gtx, key = u64(20 + i))
			primer.button(gtx, ANCHOR_SIDE_NAMES[i], key = u64(30 + i))
			anchor := ui.last_widget(gtx)
			open := true
			if primer.anchored_overlay(gtx, &open, anchor, side, focus = {prevent = true}, trap = false, key = u64(40 + i)) {
				lines(gtx, 12, ANCHOR_SIDE_NAMES[i], "hangs from its button")
			}
			ui.close(&st)
		}
	}
	ui.spacer(gtx, 110)
	kitchen.section(gtx, "Live", "Enter, Space, ArrowDown or a click opens it; focus is trapped inside and returns to the button")
	o := &m.overlays
	st := ui.stack_open(gtx)
	if primer.button(gtx, "Menu", action = .Triangle_Down) {
		o.menu = !o.menu
	}
	anchor := ui.last_widget(gtx)
	a := primer.anchored_overlay_open(gtx, &o.menu, anchor, width = .Small, role = .Menu, name = "Menu")
	if a.visible {
		pad_box := ui.inset_open(gtx, ui.pad_all(8))
		c := ui.column_open(gtx, gap = 2, align = .Fill)
		for item, i in ([3]string{"Copy link", "Quote reply", "Report"}) {
			if primer.button(gtx, item, .Invisible, block = true, align = .Start, key = u64(60 + i)) {
				o.menu = false
				o.said = fmt.aprintf("chose %s", item)
			}
		}
		ui.close(&c)
		ui.close(&pad_box)
	}
	if a.dismissed != .None {
		o.said = fmt.aprintf("closed by %v", a.dismissed)
	}
	primer.anchored_overlay_close(&a)
	ui.close(&st)
	said(gtx, o.said)
}

CARETS := [?]primer.Popover_Caret{.Top, .Bottom, .Left, .Right, .Top_Left, .Bottom_Right, .Left_Bottom, .Right_Top}
CARET_NAMES := [?]string{"Top", "Bottom", "Left", "Right", "Top left", "Bottom right", "Left bottom", "Right top"}

page_popover :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Carets", "24px padding, 6px corners; the caret's 16 by 8px outer triangle is --borderColor-default, its inner one the card's fill")
	{
		band := region(gtx, 300, 2)
		defer ui.close(&band)
		for c, i in CARETS {
			at := [2]f32{f32(i % 4) * 250 + 16, f32(i / 4) * 150 + 16}
			open := true
			if primer.popover(gtx, &open, at, caret = c, width = .XSmall, key = u64(80 + i)) {
				base.label(gtx, CARET_NAMES[i], {size = 14})
				base.label(gtx, "A callout tied to a spot.", {size = 12, color = base.color(.Muted)}, key = 1)
			}
		}
	}
	kitchen.section(gtx, "Live", "the caller places it; Escape or a press outside it closes it")
	o := &m.overlays
	st := ui.stack_open(gtx)
	if primer.button(gtx, "Show tip") {
		o.popover = !o.popover
	}
	t := ui.last_widget(gtx)
	if primer.popover(gtx, &o.popover, {0, t.size.y + 12}, ignore = {0, 0, t.size.x, t.size.y}) {
		base.label(gtx, "New: popovers", {size = 16})
		base.label(gtx, "They point at what they explain.", {size = 14, color = base.color(.Muted)})
	}
	ui.close(&st)
}

DIRECTIONS := [?]primer.Tooltip_Direction{.N, .NE, .E, .SE, .S, .SW, .W, .NW}
DIRECTION_NAMES := [?]string{"North", "North east", "East", "South east", "South", "South west", "West", "North west"}

page_tooltip :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Directions", "hover or Tab to one: a 50ms delay, 4px away, --tooltip-bgColor, 12px text centred in lines up to 250px")
	{
		ui.spacer(gtx, 24)
		w := ui.wrap_open(gtx, gap = 48, line_gap = 56)
		defer ui.close(&w)
		for d, i in DIRECTIONS {
			st := ui.stack_open(gtx, key = u64(90 + i))
			primer.button(gtx, DIRECTION_NAMES[i], key = u64(100 + i))
			primer.tooltip(gtx, DIRECTION_NAMES[i], ui.last_widget(gtx), direction = d)
			ui.close(&st)
		}
	}
	kitchen.section(gtx, "Wrapping and delays", "long text wraps into balanced lines; medium waits 400ms, long 1200ms")
	{
		ui.spacer(gtx, 8)
		r := ui.row_open(gtx, gap = 24)
		defer ui.close(&r)
		st := ui.stack_open(gtx, key = 110)
		primer.button(gtx, "Long text", key = 111)
		primer.tooltip(gtx, "Tooltips wrap by word once they reach 250px, and balance their lines so the last is not left alone.", ui.last_widget(gtx))
		ui.close(&st)
		st2 := ui.stack_open(gtx, key = 112)
		primer.button(gtx, "Medium delay", key = 113)
		primer.tooltip(gtx, "Shown after 400ms", ui.last_widget(gtx), delay = .Medium)
		ui.close(&st2)
		st3 := ui.stack_open(gtx, key = 114)
		primer.button(gtx, "Long delay", key = 115)
		primer.tooltip(gtx, "Shown after 1200ms", ui.last_widget(gtx), delay = .Long)
		ui.close(&st3)
	}
	kitchen.section(gtx, "Icon buttons", "an IconButton shows its name, or its description, as its tooltip")
	{
		ui.spacer(gtx, 8)
		r := ui.row_open(gtx, gap = 12)
		defer ui.close(&r)
		primer.icon_button(gtx, .Pencil, "Edit", key = 120)
		primer.icon_button(gtx, .Trash, "Delete", .Danger, description = "Deletes the file for everyone", key = 121)
		primer.icon_button(gtx, .Kebab_Horizontal, "More options", .Invisible, tooltip_direction = .E, key = 122)
		primer.icon_button(gtx, .Gear, "Settings", state = .Disabled, key = 123)
	}
}

DIALOG_KINDS := [?]string{"Default", "Small, subtitle", "Large, top", "Left sheet", "Right sheet", "Fixed height"}

page_dialog :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	o := &m.overlays
	kitchen.section(gtx, "Kinds", "a modal over a translucent backdrop; centred ones scale in from 0.5, sheets slide in over 250ms")
	{
		w := ui.wrap_open(gtx, gap = 12)
		defer ui.close(&w)
		for k, i in DIALOG_KINDS {
			if primer.button(gtx, k, key = u64(130 + i)) {
				o.dialog, o.dialog_kind = true, i
			}
		}
	}
	said(gtx, o.said)
	save, cancel := false, false
	buttons := [2]primer.Dialog_Button {
		{content = "Cancel", clicked = &cancel},
		{content = "Save", type = .Primary, auto_focus = true, clicked = &save},
	}
	width := [?]primer.Dialog_Width{.XLarge, .Small, .Large, .Medium, .Medium, .Large}
	height := [?]primer.Dialog_Height{.Auto, .Auto, .Auto, .Auto, .Auto, .Small}
	position := [?]primer.Dialog_Position{.Center, .Center, .Center, .Left, .Right, .Center}
	align := [?]primer.Dialog_Align{.Center, .Center, .Top, .Center, .Center, .Center}
	k := clamp(o.dialog_kind, 0, len(DIALOG_KINDS) - 1)
	subtitle := k == 1 ? "A smaller muted line under the title" : ""
	dl := primer.dialog_open(gtx, &o.dialog, "Edit profile", subtitle, buttons[:], width[k], height = height[k], position = position[k], align = align[k])
	if dl.visible {
		c := ui.column_open(gtx, gap = 8)
		base.label(gtx, "The body pads 16px and scrolls.")
		n := k == 5 ? 30 : 3
		for i in 0 ..< n {
			base.label(gtx, fmt.tprintf("Line %d of the body.", i + 1), {color = base.color(.Muted)}, key = u64(i + 1))
		}
		ui.close(&c)
	}
	if dl.dismissed != .None {
		o.said = fmt.aprintf("closed by %v", dl.dismissed)
	}
	primer.dialog_close(&dl)
	if save {
		o.saves += 1
		o.dialog = false
		o.said = fmt.aprintf("saved %d", o.saves)
	}
	if cancel {
		o.dialog = false
		o.said = "cancelled"
	}
}

CONFIRM_KINDS := [?]string{"Confirm", "Delete (danger)", "Loading"}

page_confirmation_dialog :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	o := &m.overlays
	kitchen.section(gtx, "Kinds", "320px wide; confirm takes focus, cancel does when confirm is danger")
	{
		w := ui.wrap_open(gtx, gap = 12)
		defer ui.close(&w)
		for k, i in CONFIRM_KINDS {
			if primer.button(gtx, k, key = u64(150 + i)) {
				o.confirm, o.confirm_kind = true, i
			}
		}
	}
	said(gtx, o.said)
	k := clamp(o.confirm_kind, 0, len(CONFIRM_KINDS) - 1)
	types := [?]primer.Button_Variant{.Primary, .Danger, .Default}
	titles := [?]string{"Publish this release?", "Delete this repository?", "Merging…"}
	bodies := [?]string{"Everyone watching the repository will be notified.", "This cannot be undone. The repository and its wiki will be gone.", "The confirm button shows its loading state and ignores activation."}
	confirms := [?]string{"Publish", "Delete", "Merge"}
	answer := primer.confirmation_dialog(gtx, &o.confirm, titles[k], bodies[k], confirm_content = confirms[k], confirm_type = types[k], confirm_loading = k == 2)
	if answer != .None {
		o.said = fmt.aprintf("answered %v", answer)
	}
}

page_details :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	o := &m.overlays
	kitchen.section(gtx, "Disclosure", "Details draws nothing itself: the summary is the caller's button, the content shows only while open")
	labels := [3]string{"Show more", "Advanced settings", "Closes on a press outside"}
	for l, i in labels {
		d := primer.details_open(gtx, &o.details[i], close_on_outside = i == 2, key = u64(160 + i))
		if primer.details_summary(&d, primer.button(gtx, l, .Invisible, trailing = o.details[i] ? .Chevron_Up : .Chevron_Down, key = u64(170 + i))) {
			pad_box := ui.inset_open(gtx, {16, 4, 0, 8}, key = u64(180 + i))
			base.label(gtx, "Content after the summary, laid out only while open.", {color = base.color(.Muted)})
			ui.close(&pad_box)
		}
		primer.details_close(&d)
	}
}
