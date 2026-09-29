package main

import "core:fmt"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"
import "jm:ui/ops"

// The overlays and the rest of the button family, on the fluent-kit's
// menu.json, dialog.json, tooltip.json, toggle-button.json,
// split-button.json, menu-button.json and compound-button.json.

page_menu :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Items", "32px rows in a 4px-padded popover; hover turns the icon brand and filled; nothing transitions")
	state_header(gtx, 180)
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			fluent.menu_item(gtx, "Rename", .Edit, "F2", state = st, key = key)
		}
		state_row(gtx, m, "Item", cell, 1, 180)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			on := true
			fluent.menu_item(gtx, "Word wrap", check = .Checkbox, checked = &on, state = st, key = key)
		}
		state_row(gtx, m, "Checked", cell, 2, 180)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			fluent.menu_item(gtx, "Share", .Share, subtext = "Send a copy or a link", submenu = true, state = st, key = key)
		}
		state_row(gtx, m, "Multiline", cell, 3, 180)
	}
	section(gtx, "Live", "a menu button and its menu: click, Enter, Space or ArrowDown open it; an item, Escape or a press outside closes it")
	r := ui.row_open(gtx, gap = 16)
	defer ui.close(&r)
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		fluent.menu_button(gtx, "Edit", &m.menu_open)
		if fluent.menu(gtx, &m.menu_open) {
			if fluent.menu_item(gtx, "Cut", .Delete, "Ctrl+X") {
				m.menu_pick = "Cut"
			}
			if fluent.menu_item(gtx, "Copy", .Copy, "Ctrl+C") {
				m.menu_pick = "Copy"
			}
			if fluent.menu_item(gtx, "Paste", .Clipboard, "Ctrl+V", disabled = true) {
				m.menu_pick = "Paste"
			}
			fluent.menu_divider(gtx)
			fluent.menu_header(gtx, "Format")
			fluent.menu_item(gtx, "Bold", .Text_Bold, check = .Checkbox, checked = &m.menu_bold, persist = true)
			fluent.menu_item(gtx, "Italic", .Text_Italic, check = .Checkbox, checked = &m.menu_italic, persist = true)
			fluent.menu_divider(gtx)
			fluent.menu_item(gtx, "Share", .Share, subtext = "Send a copy or a link", submenu = true)
		}
	}
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		if fluent.split_button(gtx, "Save", &m.split_open, .Primary, .Save) {
			m.menu_pick = "Save"
		}
		if fluent.menu(gtx, &m.split_open) {
			if fluent.menu_item(gtx, "Save as…") {
				m.menu_pick = "Save as"
			}
			if fluent.menu_item(gtx, "Save a copy") {
				m.menu_pick = "Save a copy"
			}
		}
	}
	base.label(gtx, fmt.tprintf("Last: %s", m.menu_pick), {color = fluent.color(.Neutral_Foreground2)})
}

page_dialog :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Live", "modal: the backdrop dims and a press on it closes; alert: only an action or Escape; non-modal: no backdrop, a close button in the title")
	r := ui.wrap_open(gtx, gap = 12)
	defer ui.close(&r)
	if fluent.button(gtx, "Open modal", .Primary) {
		m.dialog_kind, m.dialog_open = .Modal, true
	}
	if fluent.button(gtx, "Open alert") {
		m.dialog_kind, m.dialog_open = .Alert, true
	}
	if fluent.button(gtx, "Open non-modal") {
		m.dialog_kind, m.dialog_open = .Non_Modal, true
	}
	base.label(gtx, fmt.tprintf("Result: %s", m.dialog_result), {color = fluent.color(.Neutral_Foreground2)})
	if fluent.dialog(gtx, &m.dialog_open, m.window, m.dialog_kind) {
		fluent.dialog_title(gtx, "Discard unsaved changes?")
		fluent.text_block(gtx, "You have edits that have not been saved. Closing now discards them; keep editing to save them first.", .Body1, fluent.color(.Neutral_Foreground1), 550)
		if fluent.dialog_actions(gtx) {
			if fluent.button(gtx, "Keep editing") {
				m.dialog_result, m.dialog_open = "kept", false
			}
			if fluent.button(gtx, "Discard", .Primary) {
				m.dialog_result, m.dialog_open = "discarded", false
			}
		}
	}
}

page_tooltip :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Live", "hover or focus an anchor for 250ms; the bubble hides 250ms after leaving, or at once on Escape")
	r := ui.wrap_open(gtx, gap = 24, line_gap = 40)
	defer ui.close(&r)
	tip_anchor(gtx, "Normal", "Saves the document", .Normal, .Above, false, 1)
	tip_anchor(gtx, "Inverted", "The static dark bubble, the same in every theme", .Inverted, .Above, false, 2)
	tip_anchor(gtx, "Arrow", "With the 6px arrow", .Normal, .Above, true, 3)
	tip_anchor(gtx, "Below", "Placed under the anchor instead", .Normal, .Below, true, 4)
	tip_anchor(gtx, "Long", "A bubble is at most 240px wide, so a long description wraps onto as many caption lines as it needs.", .Normal, .Above, false, 5)
}

// tip_anchor is a labelled box that shows a tooltip, standing in for any
// component that calls fluent.tooltip from inside its own widget.
tip_anchor :: proc(gtx: ^ui.Ctx, label, tip: string, appearance: fluent.Tooltip_Appearance, position: fluent.Tooltip_Position, arrow: bool, key: u64) {
	p := ui.widget_open(gtx, key)
	t := fluent.shape_text(gtx, label, .Body1)
	sz := ops.Size{t.width + 24, 32}
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := fluent.control(gtx, p.id, area, .Live)
	bg := fluent.color_for({.Neutral_Background3, .Neutral_Background3_Hover, .Neutral_Background3_Pressed, .Neutral_Background_Disabled}, c)
	ops.fill(gtx.scene, ops.Round_Rect{area, 4}, bg)
	fluent.draw_text(gtx, t, {12, (sz.y - t.height) / 2}, fluent.color(.Neutral_Foreground1))
	fluent.paint_focus_outline(gtx, c, {area, 4})
	fluent.listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	fluent.tooltip(gtx, p.id, c, tip, sz, appearance, position, arrow)
	ui.widget_close(gtx, &p, {size = sz})
}

page_toggle_button :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Checked", "the appearance's Selected tokens at rest; hover and press read the ordinary tokens, so on and off look alike under the pointer")
	state_header(gtx)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			on := true
			fluent.toggle_button(gtx, "Bold", &on, APPEARANCES[key / 16 - 1], .Text_Bold, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1))
	}
	section(gtx, "Unchecked", "as button")
	state_header(gtx)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			off := false
			fluent.toggle_button(gtx, "Bold", &off, APPEARANCES[key / 16 - 11], .Text_Bold, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 11))
	}
	section(gtx, "Live", "click, Enter or Space flips each")
	r := ui.wrap_open(gtx, gap = 12)
	defer ui.close(&r)
	fluent.toggle_button(gtx, "Bold", &m.fmt_bold, .Subtle, .Text_Bold, key = 100)
	fluent.toggle_button(gtx, "Italic", &m.fmt_italic, .Subtle, .Text_Italic, key = 101)
	fluent.toggle_button(gtx, "Underline", &m.fmt_underline, .Subtle, .Text_Underline, key = 102)
	fluent.toggle_button(gtx, "", &m.fmt_star, .Transparent, .Star, name = "Starred", shape = .Circular, key = 103)
	fluent.toggle_button(gtx, "Outline", &m.fmt_bold, .Outline, key = 104)
	fluent.toggle_button(gtx, "Primary", &m.fmt_italic, .Primary, key = 105)
}

page_split_button :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Appearances", "the primary action and a 24px-minimum menu half joined on the primary's end border; each half draws its own inset ring")
	state_header(gtx, 150)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			open := false
			fluent.split_button(gtx, "Save", &open, APPEARANCES[key / 16 - 1], state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1), 150)
	}
	section(gtx, "Sizes and shapes")
	state_header(gtx, 150)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			open := false
			fluent.split_button(gtx, "Save", &open, .Secondary, .Save, size = fluent.Size(key / 16 - 11), state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 11), 150)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			open := false
			fluent.split_button(gtx, "Save", &open, .Primary, shape = .Circular, state = st, key = key)
		}
		state_row(gtx, m, "Circular", cell, 20, 150)
	}
	section(gtx, "Live", "the primary half acts; the chevron half opens the menu")
	r := ui.row_open(gtx, gap = 16, align = .Center)
	defer ui.close(&r)
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		if fluent.split_button(gtx, "Save", &m.split_live, .Secondary, .Save, key = 100) {
			m.split_count += 1
		}
		if fluent.menu(gtx, &m.split_live) {
			if fluent.menu_item(gtx, "Save as…") {
				m.split_count += 10
			}
			if fluent.menu_item(gtx, "Save all") {
				m.split_count += 100
			}
		}
	}
	base.label(gtx, fmt.tprintf("Saved %d", m.split_count), {color = fluent.color(.Neutral_Foreground2)})
}

page_menu_button :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Closed", "as button, with the 12px chevron (16px at large) spacingHorizontalXS after the label")
	state_header(gtx)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			open := false
			fluent.menu_button(gtx, "Options", &open, APPEARANCES[key / 16 - 1], state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1))
	}
	section(gtx, "Expanded", "while its menu is open: the Selected tokens and filled icons")
	state_header(gtx)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			open := true
			fluent.menu_button(gtx, "Options", &open, APPEARANCES[key / 16 - 11], .Settings, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 11))
	}
	section(gtx, "Sizes")
	state_header(gtx)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			open := false
			fluent.menu_button(gtx, "Options", &open, .Secondary, size = fluent.Size(key / 16 - 21), state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 21))
	}
	section(gtx, "Live", "click, Enter, Space or ArrowDown opens; the menu closes it")
	r := ui.row_open(gtx, gap = 16)
	defer ui.close(&r)
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		fluent.menu_button(gtx, "Options", &m.menu_button_open, .Secondary, .Settings, key = 100)
		if fluent.menu(gtx, &m.menu_button_open) {
			fluent.menu_item(gtx, "Preferences", .Settings)
			fluent.menu_item(gtx, "Keyboard shortcuts")
			fluent.menu_divider(gtx)
			fluent.menu_item(gtx, "Sign out")
		}
	}
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		fluent.menu_button(gtx, "", &m.menu_icon_open, .Subtle, .More_Horizontal, name = "More", key = 101)
		if fluent.menu(gtx, &m.menu_icon_open) {
			fluent.menu_item(gtx, "Pin")
			fluent.menu_item(gtx, "Archive", .Folder)
		}
	}
}

page_compound_button :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	section(gtx, "Appearances", "medium: 14px top, spacingHorizontalM sides and L bottom around the 40px icon, the label and the secondary line")
	state_header(gtx, 230)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			fluent.compound_button(gtx, "Create", "Start from a blank file", APPEARANCES[key / 16 - 1], .Add, state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 1), 230)
	}
	section(gtx, "Sizes", "small 8/S/MNudge, medium 14/M/L, large 18/L/XL padding; large raises the secondary text to fontSizeBase300")
	state_header(gtx, 230)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, m: ^Model, st: fluent.Interaction, key: u64) {
			fluent.compound_button(gtx, "Create", "Start from a blank file", .Secondary, .Add, size = fluent.Size(key / 16 - 11), state = st, key = key)
		}
		state_row(gtx, m, n, cell, u64(i + 11), 230)
	}
	section(gtx, "Without an icon, and icon-only", "48, 52 and 56px squares")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	if fluent.compound_button(gtx, "Open", "A file from this device", key = 100) {
		m.clicks += 1
	}
	fluent.compound_button(gtx, "", "", .Secondary, .Settings, size = .Small, name = "Settings", key = 101)
	fluent.compound_button(gtx, "", "", .Primary, .Settings, size = .Medium, name = "Settings", key = 102)
	fluent.compound_button(gtx, "", "", .Outline, .Settings, size = .Large, name = "Settings", key = 103)
	fluent.compound_button(gtx, "After", "The icon on the end side", .Subtle, .Arrow_Right, icon_position = .After, key = 104)
}
