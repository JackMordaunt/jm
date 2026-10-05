package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"

// The containers group: card, divider, tab list, toolbar and accordion,
// on the fluent-kit's specs.

CARD_APPEARANCES := [?]fluent.Card_Appearance{.Filled, .Filled_Alternative, .Outline, .Subtle}
CARD_APPEARANCE_NAMES := [?]string{"Filled", "Filled alternative", "Outline", "Subtle"}
CARD_CELL_W :: f32(150)

// card_cell is a small card with a title and a line of text.
card_cell :: proc(gtx: ^ui.Ctx, appearance: fluent.Card_Appearance, size := fluent.Size.Medium, interactive := true, selected: ^bool = nil, state := fluent.Interaction.Live, key: u64 = 0) {
	s := fluent.scheme()
	if fluent.card(gtx, appearance, size, interactive, selected, name = "card", state = state, key = key) {
		if ui.column(gtx, gap = 4) {
			base.label(gtx, "Title", {size = 14, color = s[.Neutral_Foreground1]})
			base.label(gtx, "A line of text", {size = 12, color = s[.Neutral_Foreground2]})
		}
	}
}

page_card :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Appearances", "interactive cards: shadow4 at rest, shadow8 hovered, Stroke 1 Selected border when selected; disabled reads the Disabled tokens and shadow2")
	kitchen.state_header(gtx, CARD_CELL_W)
	for n, i in CARD_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			card_cell(gtx, CARD_APPEARANCES[key / 16 - 1], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), CARD_CELL_W)
	}
	kitchen.section(gtx, "Sizes", "8 / 12 / 16px padding with borderRadiusSmall / Medium / Large; a plain card is static")
	if ui.row(gtx, gap = 16, align = .Start) {
		for sz, i in ([?]fluent.Size{.Small, .Medium, .Large}) {
			card_cell(gtx, .Filled, sz, interactive = false, key = u64(20 + i))
		}
	}
	kitchen.section(gtx, "Live", "selectable: click toggles the selection; the outline one is interactive but not selectable")
	if ui.row(gtx, gap = 16, align = .Start) {
		for i in 0 ..< 3 {
			card_cell(gtx, .Filled, selected = &m.card_sel[i], key = u64(30 + i))
		}
		if fluent.card(gtx, .Outline, interactive = true, clicked = &m.card_hit, name = "Outline card", key = 33) {
			base.label(gtx, fmt.tprintf("Clicked %d", m.card_hits), {size = 14, color = fluent.scheme()[.Neutral_Foreground1]})
		}
		if m.card_hit {
			m.card_hits += 1
		}
	}
}

DIVIDER_APPEARANCES := [?]fluent.Divider_Appearance{.Default, .Subtle, .Strong, .Brand}
DIVIDER_APPEARANCE_NAMES := [?]string{"Default", "Subtle", "Strong", "Brand"}

page_divider :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Appearances", "strokeWidthThin lines: Stroke 2 / 3 / 1 / Brand Stroke 1, labels in the matching foreground")
	for n, i in DIVIDER_APPEARANCE_NAMES {
		base.label(gtx, n, {size = 12, color = s[.Neutral_Foreground2]})
		fluent.divider(gtx, appearance = DIVIDER_APPEARANCES[i], key = u64(i))
		fluent.divider(gtx, n, appearance = DIVIDER_APPEARANCES[i], key = u64(10 + i))
	}
	kitchen.section(gtx, "Alignment and inset", "the label 8px from the start or end; inset pulls the line in 12px at each end")
	fluent.divider(gtx, "Start", align = .Start, key = 20)
	fluent.divider(gtx, "Center", key = 21)
	fluent.divider(gtx, "End", align = .End, key = 22)
	fluent.divider(gtx, "Inset", inset = true, key = 23)
	fluent.divider(gtx, inset = true, key = 24)
	kitchen.section(gtx, "Vertical", "at least 20px tall, 84px with a label; it takes the row's height")
	if ui.row(gtx, gap = 16, align = .Fill) {
		base.label(gtx, "Left", {color = s[.Neutral_Foreground1]})
		fluent.divider(gtx, vertical = true, key = 30)
		base.label(gtx, "Middle", {color = s[.Neutral_Foreground1]})
		fluent.divider(gtx, "Or", vertical = true, key = 31)
		base.label(gtx, "Right", {color = s[.Neutral_Foreground1]})
		fluent.divider(gtx, vertical = true, inset = true, appearance = .Brand, key = 32)
		base.label(gtx, "Inset", {color = s[.Neutral_Foreground1]})
	}
}

TAB_APPEARANCES := [?]fluent.Tab_Appearance{.Transparent, .Subtle, .Subtle_Circular, .Filled_Circular}
TAB_APPEARANCE_NAMES := [?]string{"Transparent", "Subtle", "Subtle circular", "Filled circular"}
TAB_LABELS := [?]string{"First", "Second", "Third"}
TAB_ICONS := [?]fluent.Icon{.Home, .Document, .Settings}
TAB_CELL_W :: f32(240)

page_tab_list :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Appearances", "medium: 44px tall; the selected tab is body1Strong with a Compound Brand Stroke bar, a hovered one shows the Stroke 1 Hover bar under it")
	kitchen.state_header(gtx, TAB_CELL_W)
	for n, i in TAB_APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			sel := 1
			fluent.tab_list(gtx, TAB_LABELS[:], &sel, TAB_APPEARANCES[key / 16 - 1], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1), TAB_CELL_W)
	}
	kitchen.section(gtx, "Sizes", "32 / 44 / 56px tall with icons; large reads body2, subtitle2 when selected; a selected tab shows the filled icon")
	if ui.row(gtx, gap = 24, align = .Start) {
		for sz, i in ([?]fluent.Size{.Small, .Medium, .Large}) {
			fluent.tab_list(gtx, TAB_LABELS[:], &m.tab_a, size = sz, icons = TAB_ICONS[:], key = u64(20 + i))
		}
	}
	kitchen.section(gtx, "Vertical", "24 / 32 / 40px rows, the bar along the left edge; Up and Down move the selection")
	if ui.row(gtx, gap = 24, align = .Start) {
		for sz, i in ([?]fluent.Size{.Small, .Medium, .Large}) {
			fluent.tab_list(gtx, TAB_LABELS[:], &m.tab_b, size = sz, vertical = true, icons = TAB_ICONS[:], key = u64(30 + i))
		}
		fluent.tab_list(gtx, TAB_LABELS[:], &m.tab_b, .Subtle_Circular, vertical = true, key = 34)
	}
	kitchen.section(gtx, "Live", "click or Left and Right; the bar slides over durationSlow with curveDecelerateMax")
	if ui.column(gtx, gap = 12) {
		fluent.tab_list(gtx, TAB_LABELS[:], &m.tab_c, key = 40)
		fluent.tab_list(gtx, TAB_LABELS[:], &m.tab_d, .Filled_Circular, key = 41)
	}
}

page_toolbar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "items edge to edge, subtle by default, 24 / 32 / 40px tall; padding 0 by 4, 4 by 8, 4 by 20px; a divider is 1px with 12px each side")
	for sz, i in ([?]fluent.Size{.Small, .Medium, .Large}) {
		base.label(gtx, SIZE_NAMES[i], {size = 12, color = s[.Neutral_Foreground2]})
		if fluent.toolbar(gtx, sz, key = u64(i)) {
			if fluent.toolbar_button(gtx, "", .Text_Bold, name = "Bold") {
				m.tool_clicks += 1
			}
			fluent.toolbar_button(gtx, "", .Text_Italic, name = "Italic")
			fluent.toolbar_button(gtx, "", .Text_Underline, name = "Underline")
			fluent.toolbar_divider(gtx)
			fluent.toolbar_button(gtx, "Insert", .Add)
			fluent.toolbar_button(gtx, "Share", .Share, .Primary)
		}
	}
	kitchen.section(gtx, "Vertical", "a column as wide as its content, base padding at every size; dividers turn horizontal")
	if ui.row(gtx, gap = 24, align = .Start) {
		if fluent.toolbar(gtx, .Medium, vertical = true, key = 10) {
			fluent.toolbar_button(gtx, "", .Text_Bold, name = "Bold")
			fluent.toolbar_button(gtx, "", .Text_Italic, name = "Italic")
			fluent.toolbar_divider(gtx)
			fluent.toolbar_button(gtx, "", .Share, name = "Share")
		}
		base.label(gtx, fmt.tprintf("Bold clicked %d times", m.tool_clicks), {color = s[.Neutral_Foreground1]})
	}
}

ACCORDION_SIZES := [?]fluent.Accordion_Size{.Small, .Medium, .Large, .Extra_Large}
ACCORDION_SIZE_NAMES := [?]string{"Small", "Medium", "Large", "Extra large"}

page_accordion :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "32px minimum at small, 44px otherwise; the header has no hover colour, only the pointer and the focus outline")
	for n, i in ACCORDION_SIZE_NAMES {
		base.label(gtx, n, {size = 12, color = s[.Neutral_Foreground2]})
		if fluent.accordion_item(gtx, "Accordion header", &m.acc_open[i], size = ACCORDION_SIZES[i], key = u64(i)) {
			base.label(gtx, "Accordion panel", {color = s[.Neutral_Foreground1]})
		}
	}
	kitchen.section(gtx, "With an icon, chevron at the end, disabled", "the icon 20px after the chevron; at the end the chevron right-aligns")
	if fluent.accordion_item(gtx, "With an icon", &m.acc_open[4], .Folder, key = 10) {
		base.label(gtx, "Panel", {color = s[.Neutral_Foreground1]})
	}
	if fluent.accordion_item(gtx, "Chevron at the end", &m.acc_open[5], icon_end = true, key = 11) {
		base.label(gtx, "Panel", {color = s[.Neutral_Foreground1]})
	}
	if fluent.accordion_item(gtx, "Icon and chevron at the end", &m.acc_open[6], .Mail, icon_end = true, key = 12) {
		base.label(gtx, "Panel", {color = s[.Neutral_Foreground1]})
	}
	off := false
	fluent.accordion_item(gtx, "Disabled", &off, state = .Disabled, key = 13)
	kitchen.section(gtx, "Single open", "opening one closes the other: the caller owns the flags")
	for i in 0 ..< 3 {
		before := m.acc_single[i]
		if fluent.accordion_item(gtx, fmt.tprintf("Section %d", i + 1), &m.acc_single[i], key = u64(20 + i)) {
			base.label(gtx, "Only one of these stays open.", {color = s[.Neutral_Foreground1]})
		}
		if m.acc_single[i] && !before {
			for j in 0 ..< 3 {
				m.acc_single[j] = j == i
			}
		}
	}
}
