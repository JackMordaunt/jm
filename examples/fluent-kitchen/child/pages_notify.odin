package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Notifications and anchored surfaces, on the fluent-kit's toast.json,
// message-bar.json, popover.json, teaching-popover.json, info-label.json
// and carousel.json. None of these has interaction states of its own
// (only the buttons inside do), so the pages show variants and live
// examples rather than state grids.

INTENTS := [?]fluent.Intent{.Info, .Success, .Warning, .Error}
INTENT_NAMES := [?]string{"Info", "Success", "Warning", "Error"}

page_toast :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	if !m.toast_seeded {
		// Two that stay, so a render shows the column at rest.
		m.toast_seeded = true
		fluent.toast_push(&m.toasts, "Upload complete", "report-2026.pdf is in Documents.", .Success, fluent.TOAST_STICKY, "Just now")
		fluent.toast_push(&m.toasts, "Couldn't sync", "Check your connection and try again.", .Error, fluent.TOAST_STICKY)
	}
	kitchen.section(gtx, "Intents", "a 292px column 20px from the end and 16px from the bottom; each toast a 12px-padded surface under shadow8, 16px apart")
	{
		ui.wrap(gtx, gap = 12, align = .Center)
		for name, i in INTENT_NAMES {
			if fluent.button(gtx, fmt.tprintf("Show %s", name), key = u64(i + 1)) {
				fluent.toast_push(&m.toasts, INTENT_NAMES[i], "Dismisses itself after 3 seconds.", INTENTS[i])
			}
		}
		if fluent.button(gtx, "Sticky", .Primary, key = 9) {
			fluent.toast_push(&m.toasts, "Stays until dismissed", intent = .Info, timeout = fluent.TOAST_STICKY)
		}
		if fluent.button(gtx, "Dismiss all", .Subtle, key = 10) {
			fluent.toast_dismiss_all(&m.toasts)
		}
	}
	kitchen.section(gtx, "Timing", "the height grows over durationNormal, then the text fades in over durationSlower; the timeout starts after; hover pauses it here")
	fluent.toaster(gtx, &m.toasts, m.window, pause_on_hover = true)
}

page_message_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 12)
	kitchen.section(gtx, "Intents", "one line while it fits: intent icon, a body1Strong title running into body1 text, actions, and the dismiss")
	for name, i in INTENT_NAMES {
		fluent.message_bar(gtx, INTENTS[i], name, "A short message about what happened.", {"Action"}, dismissable = true, key = u64(i + 1))
	}
	kitchen.section(gtx, "Two lines", "auto reflows once the single line overflows: the body wraps and the actions take a row of their own")
	{
		ui.box(gtx, {padding = {right = 0}}, key = 20)
		ui.column(gtx, gap = 12)
		fluent.message_bar(gtx, .Warning, "Storage almost full", "You have used 95% of your storage. Delete files or upgrade to keep syncing.", {"Upgrade", "Manage"}, dismissable = true, layout = .Multiline, key = 21)
		fluent.message_bar(gtx, .Info, "", "Square corners, for a bar spanning the page.", shape = .Square, key = 22)
	}
	kitchen.section(gtx, "Live", "dismiss removes the bar; the page owns it")
	if !m.bar_closed {
		a, d := fluent.message_bar(gtx, .Success, "Saved", "Your changes were saved.", {"Undo"}, dismissable = true, key = 30)
		if a == 0 {
			m.bar_action = "Undo"
		}
		if d {
			m.bar_closed = true
		}
	} else if fluent.button(gtx, "Show the bar again", key = 31) {
		m.bar_closed = false
	}
	base.label(gtx, fmt.tprintf("Last action: %s", m.bar_action), {color = fluent.color(.Neutral_Foreground2)})
}

POPOVER_APPEARANCES := [?]fluent.Popover_Appearance{.Normal, .Brand, .Inverted}
POPOVER_APPEARANCE_NAMES := [?]string{"Normal", "Brand", "Inverted"}
POPOVER_POSITIONS := [?]fluent.Popover_Position{.Above, .Below, .Before, .After}
POPOVER_POSITION_NAMES := [?]string{"Above", "Below", "Before", "After"}

// popover_demo is a trigger button and its popover in a stack, the
// popover anchored to the button's 96x32 box.
popover_demo :: proc(gtx: ^ui.Ctx, label: string, open: ^bool, position := fluent.Popover_Position.Above, appearance := fluent.Popover_Appearance.Normal, size := fluent.Size.Medium, arrow := true, key: u64) {
	// Keys from the demo's own, as every demo shares these call sites.
	ui.stack(gtx, key = key)
	if fluent.button(gtx, label, key = key * 16 + 1) {
		open^ = !open^
	}
	if fluent.popover(gtx, open, {96, 32}, position, appearance, size, arrow, key = key * 16 + 2) {
		fluent.popover_text(gtx, "Popover content", .Body1_Strong)
		fluent.popover_text(gtx, "Anything goes in here.", .Body1)
	}
}

page_popover :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	if !m.pop_seeded {
		m.pop_seeded = true
		m.pop_open = {true, true, true, true, true, false, false, false}
	}
	kitchen.section(gtx, "Appearances", "a 1px Transparent_Stroke border, borderRadiusMedium, shadow16; it fades and slides 10px in over durationSlower")
	ui.spacer(gtx, 90)
	{
		ui.row(gtx, gap = 180)
		for name, i in POPOVER_APPEARANCE_NAMES {
			popover_demo(gtx, name, &m.pop_open[i], appearance = POPOVER_APPEARANCES[i], key = u64(i + 1))
		}
	}
	kitchen.section(gtx, "Positions and sizes", "above, below, before or after the trigger; padding 12 / 16 / 20px and a 6 / 8 / 8px arrow by size")
	ui.spacer(gtx, 40)
	{
		ui.row(gtx, gap = 200)
		ui.spacer(gtx, 60)
		popover_demo(gtx, "Before", &m.pop_open[3], .Before, size = .Small, key = 11)
		popover_demo(gtx, "After", &m.pop_open[4], .After, size = .Large, key = 12)
		popover_demo(gtx, "Below", &m.pop_open[5], .Below, key = 13)
		popover_demo(gtx, "No arrow", &m.pop_open[6], .Below, arrow = false, key = 14)
	}
	ui.spacer(gtx, 120)
	kitchen.section(gtx, "Live", "click a trigger; Escape once the surface has focus, or a press outside, closes it")
}

page_teaching_popover :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	if !m.teach_seeded {
		m.teach_seeded = true
		m.teach_open = true
	}
	kitchen.section(gtx, "Paged", "a popover padded spacingVerticalL with borderRadiusXLarge, 322px (the 288px media plus padding); dots, the count, previous and next")
	ui.row(gtx, gap = 380)
	TITLES := [3]string{"Find anything", "Share in a click", "Stay in sync"}
	BODIES := [3]string{"Search across your files, mail and chats from one box.", "Send a link that opens right where you are.", "Changes appear on every device as you make them."}
	{
		ui.stack(gtx, key = 1)
		if fluent.button(gtx, "Take the tour", .Primary, key = 1) {
			m.teach_open = true
			m.teach_page = 0
		}
		if fluent.teaching_popover(gtx, &m.teach_open, {96, 32}, key = 2) {
			fluent.teaching_popover_header(gtx, "Tips", .Info)
			page := clamp(m.teach_page, 0, 2)
			fluent.teaching_popover_title(gtx, TITLES[page])
			fluent.teaching_popover_media(gtx, .Short)
			fluent.teaching_popover_body(gtx, BODIES[page])
			fluent.teaching_popover_carousel_footer(gtx, &m.teach_page, 3)
		}
	}
	{
		ui.stack(gtx, key = 2)
		if fluent.button(gtx, "Brand", key = 1) {
			m.teach_brand = !m.teach_brand
		}
		if fluent.teaching_popover(gtx, &m.teach_brand, {96, 32}, .Brand, key = 2) {
			fluent.teaching_popover_title(gtx, "New: shortcuts", dismiss = true)
			fluent.teaching_popover_body(gtx, "Press Ctrl+K to jump anywhere.")
			fluent.teaching_popover_footer(gtx, "Try it", "Not now")
		}
	}
}

page_info_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 16)
	if !m.info_seeded {
		m.info_seeded = true
		m.info_open = true
	}
	kitchen.section(gtx, "Sizes", "a Label and a transparent button with a 12 / 16 / 20px Info icon; hover and the open state fill it and turn it brand")
	ui.spacer(gtx, 70)
	SIZES := [?]fluent.Size{.Small, .Medium, .Large}
	r := ui.row_open(gtx, gap = 120, align = .Start)
	for s, i in SIZES {
		o: ^bool = i == 1 ? &m.info_open : nil
		fluent.info_label(gtx, SIZE_NAMES[i], "The popover opens above the button's start, at most 264px wide.", s, open = o, key = u64(i + 1))
	}
	ui.close(&r)
	kitchen.section(gtx, "Required and semibold", "")
	fluent.info_label(gtx, "Display name", "Shown to everyone in your organisation.", weight = .Semibold, required = true, key = 10)
	kitchen.section(gtx, "Button states", "")
	kitchen.state_header(gtx)
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.info_label(gtx, "Label", "Help", state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Medium", cell, 20)
	}
}

// slide_card is one carousel card: a tinted block with a title.
slide_card :: proc(gtx: ^ui.Ctx, i: int, elevated: bool) {
	ROLES := [4]tok.Role{.Palette_Blue_Background2, .Palette_Green_Background2, .Palette_Marigold_Background2, .Palette_Berry_Background2}
	// An elevated card's surface is the carousel's; a flat one is tinted.
	fill := elevated ? ops.Color{} : fluent.color(ROLES[i % 4])
	ui.box(gtx, {fill = fill, radius = elevated ? 0 : 4, padding = ui.pad_all(24)}, key = u64(i))
	ui.column(gtx, gap = 8)
	base.label(gtx, fmt.tprintf("Card %d", i + 1), {size = 20, color = fluent.color(.Neutral_Foreground1)})
	base.label(gtx, "Cards move a page at a time.", {color = fluent.color(.Neutral_Foreground2)})
	ui.spacer(gtx, 60)
}

page_carousel :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Flat", "previous and next, the nav of 24px dots on a translucent pill; the strip slides a page over durationSlow")
	{
		ui.box(gtx, {}, key = 1)
		if fluent.carousel(gtx, &m.slide_flat, 4, key = 2) {
			for i in 0 ..< 4 {
				if fluent.carousel_card(gtx, i, key = u64(i)) {
					slide_card(gtx, i, false)
				}
			}
		}
	}
	kitchen.section(gtx, "Elevated, circular, autoplay", "cards rounded to borderRadiusXLarge under shadow16, spacingHorizontalXXL apart; the ends wrap; autoplay advances every 4s")
	if fluent.carousel(gtx, &m.slide_elevated, 4, .Elevated, circular = true, autoplay = &m.slide_auto, brand_nav = true, key = 3) {
		for i in 0 ..< 4 {
			if fluent.carousel_card(gtx, i, key = u64(i)) {
				slide_card(gtx, i, true)
			}
		}
	}
}
