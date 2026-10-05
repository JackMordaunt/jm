package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"

// The feedback pages: badge, avatar, progress bar and spinner, on the
// fluent-kit's badge.json, avatar.json, progress-bar.json and
// spinner.json. None of these has interaction states, so the pages are
// rows of variants rather than state grids.

BADGE_COLORS := [?]fluent.Badge_Color{.Brand, .Danger, .Important, .Informative, .Severe, .Subtle, .Success, .Warning}
BADGE_COLOR_NAMES := [?]string{"Brand", "Danger", "Important", "Informative", "Severe", "Subtle", "Success", "Warning"}
BADGE_APPEARANCES := [?]fluent.Badge_Appearance{.Filled, .Ghost, .Outline, .Tint}
BADGE_APPEARANCE_NAMES := [?]string{"Filled", "Ghost", "Outline", "Tint"}
BADGE_SIZES := [?]fluent.Badge_Size{.Tiny, .Extra_Small, .Small, .Medium, .Large, .Extra_Large}
PRESENCE := [?]fluent.Presence_Status{.Available, .Away, .Busy, .Do_Not_Disturb, .Offline, .Out_Of_Office, .Blocked, .Unknown}

// variant_row is a labelled row of cells: the row label in the grid's
// label column, then whatever follows in a wrap.
variant_row_open :: proc(gtx: ^ui.Ctx, label: string, key: u64 = 0) -> (ui.Flex, ui.Flex) {
	s := fluent.scheme()
	r := ui.row_open(gtx, align = .Center, key = key)
	{
		ui.stack(gtx)
		base.label(gtx, label, {size = 12, color = s[.Neutral_Foreground2]})
	}
	ui.spacer(gtx, max(kitchen.LABEL_W - label_width(gtx, label), 0))
	w := ui.wrap_open(gtx, gap = 12, line_gap = 8, align = .Center)
	return r, w
}

variant_row_close :: proc(r, w: ^ui.Flex) {
	ui.close(w)
	ui.close(r)
}

page_badge :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Appearance by colour", "medium: 20px, caption1Strong; ghost and outline subtle are white, for dark surfaces")
	for a, i in BADGE_APPEARANCES {
		r, w := variant_row_open(gtx, BADGE_APPEARANCE_NAMES[i], u64(i + 1))
		for c, j in BADGE_COLORS {
			fluent.badge(gtx, BADGE_COLOR_NAMES[j], c, a, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Sizes and shapes", "6 / 10 / 16 / 20 / 24 / 32px; tiny and extra-small are dots; rounded drops to borderRadiusSmall at small and below")
	{
		r, w := variant_row_open(gtx, "Circular", 10)
		for sz, j in BADGE_SIZES {
			fluent.badge(gtx, "99", size = sz, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	{
		r, w := variant_row_open(gtx, "Rounded", 11)
		for sz, j in BADGE_SIZES {
			fluent.badge(gtx, "99", .Informative, size = sz, shape = .Rounded, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	{
		r, w := variant_row_open(gtx, "Square", 12)
		for sz, j in BADGE_SIZES {
			fluent.badge(gtx, "99", .Success, .Tint, size = sz, shape = .Square, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "With an icon", "12px icon at medium; before, after, or alone")
	{
		r, w := variant_row_open(gtx, "Icon", 13)
		fluent.badge(gtx, "Sent", .Success, ic = .Checkmark, key = 1)
		fluent.badge(gtx, "Later", .Warning, .Tint, ic = .Clipboard, icon_position = .After, key = 2)
		fluent.badge(gtx, "", .Danger, ic = .Dismiss, key = 3)
		fluent.badge(gtx, "Star", .Brand, .Outline, ic = .Star, size = .Extra_Large, key = 4)
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Counter badge", "capped at 99 with a plus; zero hides; dot is 6px")
	{
		r, w := variant_row_open(gtx, "Counts", 14)
		fluent.counter_badge(gtx, 5, key = 1)
		fluent.counter_badge(gtx, 42, color = .Danger, key = 2)
		fluent.counter_badge(gtx, 105, color = .Important, shape = .Rounded, key = 3)
		fluent.counter_badge(gtx, 0, show_zero = true, color = .Informative, key = 4)
		fluent.counter_badge(gtx, 7, dot = true, color = .Danger, key = 5)
		fluent.counter_badge(gtx, 3, color = .Brand, appearance = .Tint, size = .Large, key = 6)
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Presence badge", "the status colour on a Neutral_Background1 disc; out of office draws each as a ring")
	{
		r, w := variant_row_open(gtx, "Status", 15)
		for st, j in PRESENCE {
			fluent.presence_badge(gtx, st, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	{
		r, w := variant_row_open(gtx, "Out of office", 16)
		for st, j in PRESENCE {
			fluent.presence_badge(gtx, st, out_of_office = true, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	{
		r, w := variant_row_open(gtx, "Sizes", 17)
		for sz, j in BADGE_SIZES {
			fluent.presence_badge(gtx, .Available, size = sz, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
}

AVATAR_SIZES := [?]fluent.Avatar_Size{.S16, .S20, .S24, .S28, .S32, .S36, .S40, .S48, .S56, .S64, .S72, .S96, .S120, .S128}
AVATAR_NAMES := [?]string{"Katri Ahokas", "Ada Lovelace", "Grace Hopper", "Alan Turing", "Edsger Dijkstra", "Barbara Liskov", "Donald Knuth", "Margaret Hamilton", "Linus Torvalds", "Ken Thompson"}

page_avatar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "16 to 128px; initials semibold at the size's font step; only the first initial at 16")
	{
		r, w := variant_row_open(gtx, "Circular", 1)
		for sz, j in AVATAR_SIZES {
			fluent.avatar(gtx, "Katri Ahokas", sz, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	{
		r, w := variant_row_open(gtx, "Square", 2)
		for sz, j in AVATAR_SIZES {
			fluent.avatar(gtx, "Ada Lovelace", sz, .Square, .Brand, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Colorful", "each name hashes to one of the 30 named colours, the same one every time")
	{
		r, w := variant_row_open(gtx, "Names", 3)
		for n, j in AVATAR_NAMES {
			fluent.avatar(gtx, n, .S40, color = .Colorful, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	{
		r, w := variant_row_open(gtx, "Named", 4)
		for c in fluent.Avatar_Color.Dark_Red ..= fluent.Avatar_Color.Anchor {
			fluent.avatar(gtx, "Ab", .S32, color = c, key = u64(c))
		}
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Icon and presence", "no initials shows the person icon; a presence badge sits bottom-right in a cutout")
	{
		r, w := variant_row_open(gtx, "Icon", 5)
		fluent.avatar(gtx, "", .S32, key = 1)
		fluent.avatar(gtx, "", .S48, .Square, .Brand, key = 2)
		fluent.avatar(gtx, "", .S64, key = 3)
		variant_row_close(&r, &w)
	}
	{
		r, w := variant_row_open(gtx, "Presence", 6)
		for st, j in PRESENCE {
			fluent.avatar(gtx, AVATAR_NAMES[j], .S48, color = .Colorful, presence = true, status = st, key = u64(j))
		}
		fluent.avatar(gtx, "Katri Ahokas", .S96, color = .Colorful, presence = true, status = .Away, out_of_office = true, key = 20)
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Active", "ring, shadow or both outside the avatar; inactive shrinks to 0.875 and fades to 0.8")
	{
		r, w := variant_row_open(gtx, "Static", 7)
		fluent.avatar(gtx, "Katri Ahokas", .S48, color = .Colorful, active = .Active, key = 1)
		fluent.avatar(gtx, "Katri Ahokas", .S48, color = .Colorful, active = .Active, appearance = .Shadow, key = 2)
		fluent.avatar(gtx, "Katri Ahokas", .S48, color = .Colorful, active = .Active, appearance = .Ring_Shadow, key = 3)
		fluent.avatar(gtx, "Katri Ahokas", .S48, color = .Colorful, active = .Inactive, key = 4)
		fluent.avatar(gtx, "Ada Lovelace", .S72, .Square, .Brand, active = .Active, appearance = .Ring_Shadow, key = 5)
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Live", "toggle to see the ring grow out over durationUltraSlow")
	{
		r, w := variant_row_open(gtx, "Toggle", 8)
		if fluent.button(gtx, m.avatar_active ? "Deactivate" : "Activate", key = 1) {
			m.avatar_active = !m.avatar_active
		}
		for n, j in AVATAR_NAMES[:4] {
			fluent.avatar(gtx, n, .S56, color = .Colorful, active = m.avatar_active ? .Active : .Inactive, appearance = .Ring_Shadow, presence = true, status = .Available, key = u64(10 + j))
		}
		variant_row_close(&r, &w)
	}
}

page_progress_bar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Determinate", "2px medium or 4px large; the bar's colour by validation state, reading palette tokens")
	bars :: proc(gtx: ^ui.Ctx, label: string, thickness: fluent.Progress_Thickness, shape: fluent.Progress_Shape, key: u64) {
		r, w := variant_row_open(gtx, label, key)
		colors := [?]fluent.Progress_Color{.Brand, .Success, .Warning, .Error}
		values := [?]f32{0.25, 0.5, 0.75, 1}
		for c, j in colors {
			fluent.progress_bar(gtx, values[j], thickness = thickness, shape = shape, color = c, width = 160, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	bars(gtx, "Medium", .Medium, .Rounded, 1)
	bars(gtx, "Large", .Large, .Rounded, 2)
	bars(gtx, "Square", .Large, .Square, 3)
	kitchen.section(gtx, "Indeterminate", "a 33% brand segment fading at both ends crosses the track every 3s; colour is ignored")
	{
		r, w := variant_row_open(gtx, "Loading", 4)
		fluent.progress_bar(gtx, width = 240, key = 1)
		fluent.progress_bar(gtx, thickness = .Large, width = 240, key = 2)
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Live", "width changes ease over 300ms; a reset to 0 jumps")
	{
		r, w := variant_row_open(gtx, "Value", 5)
		if fluent.button(gtx, "+10%", size = .Small, key = 1) {
			m.progress = min(m.progress + 0.1, 1)
		}
		if fluent.button(gtx, "Reset", size = .Small, key = 2) {
			m.progress = 0
		}
		base.label(gtx, fmt.tprintf("%.0f%%", m.progress * 100), {size = 12})
		variant_row_close(&r, &w)
	}
	fluent.progress_bar(gtx, m.progress, thickness = .Large, width = 400, key = 6)
}

SPINNER_SIZES := [?]fluent.Spinner_Size{.Extra_Tiny, .Tiny, .Extra_Small, .Small, .Medium, .Large, .Extra_Large, .Huge}

page_spinner :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := fluent.scheme()
	ui.column(gtx, gap = 10)
	kitchen.section(gtx, "Sizes", "16 to 44px in 4px steps; the arc spins every 1.5s and breathes from 30° to 255°")
	{
		r, w := variant_row_open(gtx, "Primary", 1)
		for sz, j in SPINNER_SIZES {
			fluent.spinner(gtx, size = sz, key = u64(j))
		}
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "With a label", "8px gap; body1 up to small, subtitle2 to extra-large, subtitle1 at huge")
	{
		r, w := variant_row_open(gtx, "Position", 2)
		fluent.spinner(gtx, "After", key = 1)
		fluent.spinner(gtx, "Before", label_position = .Before, key = 2)
		fluent.spinner(gtx, "Above", label_position = .Above, key = 3)
		fluent.spinner(gtx, "Below", label_position = .Below, key = 4)
		fluent.spinner(gtx, "Huge", .Huge, key = 5)
		fluent.spinner(gtx, "Tiny", .Extra_Tiny, key = 6)
		variant_row_close(&r, &w)
	}
	kitchen.section(gtx, "Inverted", "for brand or dark surfaces")
	{
		r, w := variant_row_open(gtx, "On brand", 3)
		panel := ui.box_open(gtx, {fill = s[.Brand_Background], radius = 4, padding = ui.pad_all(16)})
		inner := ui.row_open(gtx, gap = 24, align = .Center)
		fluent.spinner(gtx, "Loading", appearance = .Inverted, key = 1)
		fluent.spinner(gtx, size = .Huge, appearance = .Inverted, key = 2)
		ui.close(&inner)
		ui.close(&panel)
		variant_row_close(&r, &w)
	}
}
