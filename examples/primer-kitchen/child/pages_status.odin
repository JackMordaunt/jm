package main

import "jm:ui"
import "jm:ui/primer"

import "../../kitchen"

// The label and status pages, on the primer-kit's components/
// counter-label.json and spinner.json.

page_counter_label :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Variants", "a pill 2px by 6px around semibold small text; an empty count draws nothing, \"0\" is a count")
	r := ui.wrap_open(gtx, gap = 12, align = .Center)
	defer ui.close(&r)
	primer.counter_label(gtx, "12")
	primer.counter_label(gtx, "12", .Primary)
	primer.counter_label(gtx, "0")
	primer.counter_label(gtx, "1,204", .Primary)
	primer.counter_label(gtx, "")
}

SPINNER_SIZES := [?]primer.Spinner_Size{.Small, .Medium, .Large}

page_spinner :: proc(gtx: ^ui.Ctx, m: ^Model) {
	col := ui.column_open(gtx, gap = 10)
	defer ui.close(&col)
	kitchen.section(gtx, "Sizes", "16, 32 and 64px; the stroke stays 2px; every spinner shows the same angle")
	r := ui.wrap_open(gtx, gap = 24, align = .Center)
	defer ui.close(&r)
	for s in SPINNER_SIZES {
		primer.spinner(gtx, s, key = u64(s))
	}
	primer.spinner(gtx, .Medium, primer.color(.Fg_Color_Accent), key = 10)
	primer.spinner(gtx, .Medium, delay = .Long, key = 11)
}
