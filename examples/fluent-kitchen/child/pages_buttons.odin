package main

import "core:fmt"
import "jm:examples/kitchen"
import "jm:ui"
import "jm:ui/fluent"

// The button page, on the fluent-kit's components/button.json.

APPEARANCES := [?]fluent.Appearance{.Primary, .Secondary, .Outline, .Subtle, .Transparent}
APPEARANCE_NAMES := [?]string{"Primary", "Secondary", "Outline", "Subtle", "Transparent"}
SIZE_NAMES := [?]string{"Small", "Medium", "Large"}
SHAPE_NAMES := [?]string{"Rounded", "Circular", "Square"}

page_buttons :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Appearances", "medium: 32px, 96px minimum, body1 at semibold; focus draws inside the box, primary adds an on-brand ring")
	kitchen.state_header(gtx)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.button(gtx, "Button", APPEARANCES[key / 16 - 1], state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 1))
	}
	kitchen.section(gtx, "With an icon", "20px icon, SNudge from the label; subtle and transparent turn it brand and filled on hover")
	kitchen.state_header(gtx)
	for n, i in APPEARANCE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.button(gtx, "Send", APPEARANCES[key / 16 - 11], .Send, state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 11))
	}
	kitchen.section(gtx, "Sizes", "24 / 32 / 40px tall; small reads caption1 at regular, the ring radius follows the size")
	kitchen.state_header(gtx)
	for n, i in SIZE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.button(gtx, "Button", .Secondary, size = fluent.Size(key / 16 - 21), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 21))
	}
	kitchen.section(gtx, "Shapes and icon-only", "rounded, circular and square; an icon-only button is square, 32px at medium")
	kitchen.state_header(gtx)
	for n, i in SHAPE_NAMES {
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.button(gtx, "Button", .Primary, shape = fluent.Shape(key / 16 - 31), state = st, key = key)
		}
		kitchen.state_row(gtx, m, n, cell, u64(i + 31))
	}
	{
		cell :: proc(gtx: ^ui.Ctx, user: rawptr, st: fluent.Interaction, key: u64) {
			fluent.button(gtx, "", .Secondary, .Settings, name = "Settings", state = st, key = key)
		}
		kitchen.state_row(gtx, m, "Icon only", cell, 40)
	}
	kitchen.section(gtx, "Live", "hover, press, Tab and Enter these")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	for a, i in APPEARANCES {
		if fluent.button(gtx, fmt.tprintf("Clicked %d", m.clicks), a, .Add, key = u64(100 + i)) {
			m.clicks += 1
		}
	}
	if fluent.button(gtx, "Next", .Primary, .Arrow_Right, icon_position = .After, size = .Large, key = 200) {
		m.clicks += 1
	}
}
