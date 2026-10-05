package main

import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"

// The inputs group: input, textarea, field, label and link, on the
// fluent-kit's specs.

INPUT_APPEARANCES := [?]fluent.Input_Appearance{.Outline, .Underline, .Filled_Darker, .Filled_Lighter}
INPUT_APPEARANCE_NAMES := [?]string{"Outline", "Underline", "Filled darker", "Filled lighter"}
INPUT_CELL_W :: f32(170)

page_input :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Appearances", "medium: 32px, body1; the bottom edge is its own token, focus grows a 2px brand line from the centre")
	kitchen.state_header(gtx, INPUT_CELL_W)
	for n, i in INPUT_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			s := &m.input_cells[key / 16 - 1]
			fluent.input(gtx, s, "Placeholder", INPUT_APPEARANCES[key / 16 - 1], width = 150, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), INPUT_CELL_W)
	}
	kitchen.section(gtx, "Sizes and content", "24 / 32 / 40px; icons 16 / 20 / 24px in Foreground 3 before or after the text")
	kitchen.state_header(gtx, INPUT_CELL_W)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			s := &m.input_cells[key / 16 - 11 + 4]
			fluent.input(gtx, s, "Search", size = fluent.Size(key / 16 - 11), before = .Search, after = .Dismiss, width = 150, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), INPUT_CELL_W)
	}
	kitchen.section(gtx, "Invalid", "aria-invalid: every border Palette_Red_Border2 until focus is within")
	kitchen.state_header(gtx, INPUT_CELL_W)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.input(gtx, &m.input_cells[7], "Required", invalid = true, width = 150, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Outline", cell, 21, INPUT_CELL_W)
	}
	kitchen.section(gtx, "Live", "click, type, Tab between them")
	ui.wrap(gtx, gap = 12, align = .Center)
	fluent.input(gtx, &m.first, "First name", width = 180, key = 100)
	fluent.input(gtx, &m.last, "Last name", .Underline, width = 180, key = 101)
	fluent.input(gtx, &m.query, "Search", .Filled_Darker, before = .Search, width = 220, key = 102)
	fluent.input(gtx, &m.mail, "Email", .Filled_Lighter, size = .Large, after = .Mail, width = 220, key = 103)
}

page_textarea :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Appearances", "medium: 52 to 260px tall, growing with its lines, then scrolling; Enter adds a line")
	kitchen.state_header(gtx, INPUT_CELL_W)
	for n, i in INPUT_APPEARANCE_NAMES {
		if i == 1 {
			continue // no underline textarea
		}
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.textarea(gtx, &m.area_cells[key / 16 - 1], "Placeholder", INPUT_APPEARANCES[key / 16 - 1], width = 150, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), INPUT_CELL_W)
	}
	kitchen.section(gtx, "Sizes", "40 / 52 / 64px minimum")
	kitchen.state_header(gtx, INPUT_CELL_W)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			m := (^Model)(user)
			fluent.textarea(gtx, &m.area_cells[key / 16 - 11 + 4], "Notes", size = fluent.Size(key / 16 - 11), width = 150, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11), INPUT_CELL_W)
	}
	kitchen.section(gtx, "Live", "type past the box's width to wrap; Up and Down move between lines")
	fluent.textarea(gtx, &m.notes, "Write something", width = 360, key = 100)
}

page_field :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 16)
	kitchen.section(gtx, "Vertical", "label above, then the control, the validation message with its state icon, and the hint")
	{
		ui.wrap(gtx, gap = 24, line_gap = 16)
		if fluent.field(gtx, "Name", required = true, hint = "As on your passport", key = 1) {
			fluent.input(gtx, &m.field_a, "First and last", width = 220)
		}
		if fluent.field(gtx, "Email", message = "Enter a valid address", validation = .Error, key = 2) {
			fluent.input(gtx, &m.field_b, "name@example.com", invalid = true, width = 220)
		}
		if fluent.field(gtx, "Password", message = "Weak: add a number", validation = .Warning, key = 3) {
			fluent.input(gtx, &m.field_c, "At least 8 characters", after = .Eye, width = 220)
		}
		if fluent.field(gtx, "Username", message = "Available", validation = .Success, key = 4) {
			fluent.input(gtx, &m.field_d, "", width = 220)
		}
		if fluent.field(gtx, "Note", message = "Optional", validation = .None, size = .Large, key = 5) {
			fluent.textarea(gtx, &m.field_e, "Anything else", size = .Large, width = 220)
		}
		if fluent.field(gtx, "Disabled", hint = "Cannot change this", disabled = true, key = 6) {
			fluent.input(gtx, &m.field_f, "Locked", width = 220, state = .Disabled)
		}
	}
	kitchen.section(gtx, "Horizontal", "the label takes a 33% column, padded to centre on a control of its size")
	{
		ui.column(gtx, gap = 12)
		if fluent.field(gtx, "Small", orientation = .Horizontal, size = .Small, key = 11) {
			fluent.input(gtx, &m.field_g, "Small", size = .Small)
		}
		if fluent.field(gtx, "Medium", required = true, hint = "A hint below the control", orientation = .Horizontal, key = 12) {
			fluent.input(gtx, &m.field_h, "Medium")
		}
		if fluent.field(gtx, "Large", message = "Something is wrong", orientation = .Horizontal, size = .Large, key = 13) {
			fluent.input(gtx, &m.field_i, "Large", size = .Large, invalid = true)
		}
	}
}

page_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	ui.column(gtx, gap = 12)
	kitchen.section(gtx, "Sizes", "caption1 / body1 / body2 line heights; large is always semibold")
	{
		ui.wrap(gtx, gap = 24, align = .End)
		for n, i in SIZE_NAMES {
			fluent.label(gtx, n, size = fluent.Size(i), key = u64(i))
		}
	}
	kitchen.section(gtx, "Weight and required", "semibold at any size; the asterisk is Palette_Red_Foreground3, XS after the text")
	{
		ui.wrap(gtx, gap = 24, align = .End)
		fluent.label(gtx, "Regular", key = 10)
		fluent.label(gtx, "Semibold", weight = .Semibold, key = 11)
		fluent.label(gtx, "Required", required = true, key = 12)
		fluent.label(gtx, "Required semibold", required = true, weight = .Semibold, key = 13)
	}
	kitchen.section(gtx, "Disabled", "text and indicator both in the Disabled foreground")
	{
		ui.wrap(gtx, gap = 24, align = .End)
		fluent.label(gtx, "Disabled", disabled = true, key = 20)
		fluent.label(gtx, "Disabled required", required = true, disabled = true, key = 21)
	}
	base.label(gtx, "A label is not focusable: the control it names draws the focus.", {size = 12, color = s[.Neutral_Foreground2]})
}

LINK_APPEARANCE_NAMES := [?]string{"Default", "Subtle"}

page_link :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Appearances", "underline on hover and press; keyboard focus double-underlines in Stroke_Focus2")
	kitchen.state_header(gtx)
	for n, i in LINK_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.link(gtx, "Learn more", fluent.Link_Appearance(key / 16 - 1), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.link(gtx, "Learn more", inline = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Inline", cell, 3)
	}
	kitchen.section(gtx, "On other surfaces", "an inverted surface keeps one colour in every state; a brand surface steps the inverted link family")
	{
		ui.wrap(gtx, gap = 16)
		{
			ui.box(gtx, {fill = s[.Neutral_Background_Inverted], padding = ui.pad_all(12), radius = 4})
			fluent.link(gtx, "Inverted link", on = .Inverted, key = 10)
		}
		{
			ui.box(gtx, {fill = s[.Brand_Background], padding = ui.pad_all(12), radius = 4})
			fluent.link(gtx, "Brand link", on = .Brand, key = 11)
		}
	}
	kitchen.section(gtx, "Live", "click, or Tab to it and press Enter")
	{
		ui.row(gtx, gap = 4, align = .Center)
		base.label(gtx, "Read the", {size = 14, color = s[.Neutral_Foreground1]})
		if fluent.link(gtx, "documentation", inline = true, key = 20) {
			m.link_clicks += 1
		}
		base.label(gtx, "before you start.", {size = 14, color = s[.Neutral_Foreground1]})
	}
	if m.link_clicks > 0 {
		base.label(gtx, "Followed.", {size = 12, color = s[.Neutral_Foreground2]})
	}
}
