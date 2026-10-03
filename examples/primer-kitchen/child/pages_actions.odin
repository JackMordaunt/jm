package main

import "core:fmt"
import "core:strings"
import "jm:ui"
import "jm:ui/primer"

import "../../kitchen"

// Actions is the actions pages' demo state: what a live toolbar last
// reported.
Actions :: struct {
	said: string,
}

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

page_link :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10, align = .Start)
	defer ui.close(&col)
	kitchen.section(gtx, "Standalone", "accent, underlined on hover; muted turns accent on hover with no underline")
	if primer.link(gtx, "View all issues", key = 1) {
		m.clicks += 1
	}
	primer.link(gtx, "Muted link", muted = true, key = 2)
	kitchen.section(gtx, "In prose", "a link's hit area follows the lines it wraps across; with underlines on, links are underlined at rest")
	box := ui.sized_open(gtx, {max = {420, ui.INF}})
	defer ui.close(&box)
	inner := ui.column_open(gtx, gap = 12)
	defer ui.close(&inner)
	text := "Read the contributing guide before you open a pull request, and check the code of conduct."
	links := []primer.Link_Span{span(text, "contributing guide"), span(text, "code of conduct")}
	primer.prose(gtx, text, links, key = 3)
	primer.prose(gtx, text, links, underlines = true, key = 4)
}

page_keybinding_hint :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10, align = .Start)
	defer ui.close(&col)
	kitchen.section(gtx, "Condensed and full", "one cap per chord, modifiers first, named for this platform; chords a space apart")
	for keys, i in ([]string{"Mod+K", "Mod+Shift+P", "g i", "ArrowUp", "Escape"}) {
		r := ui.row_open(gtx, gap = 16, align = .Center, key = u64(i))
		primer.keybinding_hint(gtx, keys, key = 1)
		primer.keybinding_hint(gtx, keys, .Full, key = 2)
		primer.keybinding_hint(gtx, keys, size = .Small, key = 3)
		ui.close(&r)
	}
	kitchen.section(gtx, "On emphasis and on primary", "a filled cap with onEmphasis text, for tooltips and primary buttons")
	r := ui.row_open(gtx, gap = 16, align = .Center)
	defer ui.close(&r)
	primer.keybinding_hint(gtx, "Mod+Enter", variant = .On_Emphasis, key = 10)
	primer.keybinding_hint(gtx, "Mod+Enter", variant = .On_Primary, key = 11)
}

// span is the bytes of the first sub in text, as a link.
span :: proc(text, sub: string) -> primer.Link_Span {
	i := strings.index(text, sub)
	return {i, i + len(sub)}
}

// toolbar is a formatting toolbar, as ActionBar's stories show one, in a
// band w wide; what it reports goes to a.said.
@(private = "file")
toolbar :: proc(gtx: ^ui.Ctx, a: ^Actions, w: f32, size: primer.Button_Size, gap: primer.Action_Bar_Gap, key: u64) {
	band := ui.sized_open(gtx, {min = {w, 0}, max = {w, ui.INF}}, key = key)
	defer ui.close(&band)
	b := primer.action_bar_open(gtx, "Formatting tools", size, gap, key = key + 1)
	names := [3]string{"Bold", "Italic", "Code"}
	icons := [3]primer.Icon{.Bold, .Italic, .Code}
	for n, i in names {
		if primer.action_bar_icon_button(&b, icons[i], n) {
			a.said = fmt.aprintf("%s", n)
		}
	}
	primer.action_bar_divider(&b)
	primer.action_bar_group_open(&b)
	if primer.action_bar_icon_button(&b, .List_Unordered, "Bulleted list") {
		a.said = "Bulleted list"
	}
	if primer.action_bar_icon_button(&b, .List_Ordered, "Numbered list") {
		a.said = "Numbered list"
	}
	primer.action_bar_group_close(&b)
	primer.action_bar_divider(&b)
	if primer.action_bar_button(&b, "Mention", leading = .Mention) {
		a.said = "Mention"
	}
	primer.action_bar_icon_button(&b, .Image, "Add image", disabled = true)
	primer.action_bar_close(&b)
}

page_action_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	a := &m.actions
	kitchen.section(gtx, "Sizes", "28, 32 or 40px rows of invisible buttons, 8px apart, 16px side padding, at the container's end")
	for s, i in ([3]primer.Button_Size{.Small, .Medium, .Large}) {
		toolbar(gtx, a, 560, s, .Condensed, u64(10 * (i + 1)))
	}
	kitchen.section(gtx, "Overflow", "what does not fit moves, from the end, into the More items menu; a group goes as one")
	for w, i in ([3]f32{400, 260, 160}) {
		toolbar(gtx, a, w, .Medium, .Condensed, u64(100 + 10 * i))
	}
	kitchen.section(gtx, "No gap", "items touch; dividers pad 8px each side")
	toolbar(gtx, a, 560, .Medium, .None, 200)
	if a.said != "" {
		kitchen.section(gtx, "Live", a.said)
	}
}

page_button_group :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10, align = .Start)
	defer ui.close(&col)
	kitchen.section(gtx, "Joined", "no gap; each over the next by 1px; the ends round, the joints square; a hovered item's border wins the joint")
	kitchen.state_header(gtx, 220)
	cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: primer.Interaction, key: u64) {
		g := primer.button_group_open(gtx, 3, "Views", key = key)
		primer.button(gtx, "Code", group = &g, state = st, key = 1)
		primer.button(gtx, "Preview", group = &g, key = 2)
		primer.button(gtx, "Blame", group = &g, key = 3)
		primer.button_group_close(&g)
	}
	kitchen.state_row(gtx, m, "First item", cell, 1, 220)
	kitchen.section(gtx, "Icon buttons and a split button", "a toolbar: Left and Right move focus and wrap")
	r := ui.row_open(gtx, gap = 24, align = .Center)
	defer ui.close(&r)
	{
		g := primer.button_group_open(gtx, 3, "Formatting", toolbar = true, key = 10)
		primer.icon_button(gtx, .Bold, "Bold", group = &g, key = 11)
		primer.icon_button(gtx, .Italic, "Italic", group = &g, key = 12)
		primer.icon_button(gtx, .Code, "Code", group = &g, key = 13)
		primer.button_group_close(&g)
	}
	{
		g := primer.button_group_open(gtx, 2, "Merge", key = 20)
		if primer.button(gtx, "Merge pull request", .Primary, group = &g, key = 21) {
			m.clicks += 1
		}
		primer.icon_button(gtx, .Triangle_Down, "More merge options", .Primary, group = &g, key = 22)
		primer.button_group_close(&g)
	}
}
