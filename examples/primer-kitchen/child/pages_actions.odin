package main

import "core:fmt"
import "jm:ui"
import "jm:ui/primer"

import "../../kitchen"

// The action pages, on the primer-kit's components/button.json and
// icon-button.json.

VARIANTS := [?]primer.Button_Variant{.Default, .Primary, .Danger, .Invisible, .Link}
VARIANT_NAMES := [?]string{"Default", "Primary", "Danger", "Invisible", "Link"}
SIZE_NAMES := [?]string{"Small", "Medium", "Large"}

page_button :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Variants", "32px, 12px sides, medium-weight label; the focus outline sits 2px inside, primary adds an onEmphasis ring")
	kitchen.state_header(gtx)
	for n, i in VARIANT_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.button(gtx, "Button", VARIANTS[key / 16 - 1], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	kitchen.section(gtx, "Visuals and count", "16px octicons in the variant's icon colour; a count is a CounterLabel in the variant's colours")
	kitchen.state_header(gtx)
	for n, i in VARIANT_NAMES[:4] {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.button(gtx, "Issues", VARIANTS[key / 16 - 11], leading = .Issue_Opened, count = "12", state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11))
	}
	kitchen.section(gtx, "Sizes", "28 / 32 / 40px; small reads the small body size with 8px sides, large 16px sides")
	kitchen.state_header(gtx)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.button(gtx, "Menu", size = primer.Button_Size(key / 16 - 21), action = .Triangle_Down, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 21))
	}
	kitchen.section(gtx, "Loading and inactive", "loading swaps the first visual for a spinner and keeps focus; inactive looks disabled but stays live")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.button(gtx, "Saving", .Primary, leading = .Check, loading = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Loading", cell, 31)
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.button(gtx, "Unavailable", inactive = true, state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Inactive", cell, 32)
	}
	kitchen.section(gtx, "Live", "hover, press, Tab and Enter these")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	for v, i in VARIANTS {
		if primer.button(gtx, fmt.tprintf("Clicked %d", m.clicks), v, leading = .Plus, key = u64(100 + i)) {
			m.clicks += 1
		}
	}
	if primer.button(gtx, m.loading ? "Saving" : "Save", .Primary, loading = m.loading, dot = .Button, key = 200) {
		m.loading = true
	}
	if primer.button(gtx, "Reset", .Invisible, leading = .Sync, key = 201) {
		m.loading = false
	}
}

ICON_SIZES := [?]primer.Button_Size{.Small, .Medium, .Large}

page_icon_button :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Variants", "a square of the size's height, the icon centred; default draws it muted, invisible in its rest colour throughout")
	kitchen.state_header(gtx)
	for n, i in VARIANT_NAMES[:4] {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.icon_button(gtx, .Kebab_Horizontal, "More", VARIANTS[key / 16 - 1], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	kitchen.section(gtx, "Sizes", "28 / 32 / 40px squares")
	kitchen.state_header(gtx)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
			primer.icon_button(gtx, .Gear, "Settings", size = ICON_SIZES[key / 16 - 11], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11))
	}
	kitchen.section(gtx, "Unread dot", "an 8px accent dot, ringed in the inset background")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	if primer.icon_button(gtx, .Bell, "Notifications", dot = .Button, key = 300) {
		m.clicks += 1
	}
	primer.icon_button(gtx, .Bell, "Notifications on the icon", .Invisible, dot = .Leading, key = 301)
}
