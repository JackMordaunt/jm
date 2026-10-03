package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of the popovers and the carousel, driven through ui.Probe.

@(private = "file")
POP_WINDOW :: ops.Size{900, 700}

@(private = "file")
Pop_Model :: struct {
	open, teach, carousel_auto: bool,
	insides:                    int,
	page, slide:                int,
	finished:                   bool,
	card_hits:                  [3]int,
}

@(private = "file")
pop_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Pop_Model)(user)
	pad := ui.inset_open(gtx, {40, 300, 40, 40})
	defer ui.close(&pad)
	col := ui.column_open(gtx, gap = 24)
	defer ui.close(&col)
	{
		r := ui.row_open(gtx, gap = 24)
		defer ui.close(&r)
		{
			st := ui.stack_open(gtx)
			defer ui.close(&st)
			if button(gtx, "Open") {
				m.open = !m.open
			}
			if popover(gtx, &m.open, {96, 32}) {
				popover_text(gtx, "Anchored content")
				if button(gtx, "Inside") {
					m.insides += 1
				}
			}
		}
		{
			st := ui.stack_open(gtx)
			defer ui.close(&st)
			if button(gtx, "Tour") {
				m.teach = true
			}
			if teaching_popover(gtx, &m.teach, {96, 32}) {
				teaching_popover_header(gtx, "Tips")
				teaching_popover_title(gtx, "Step")
				teaching_popover_body(gtx, "Learn the basics.")
				if teaching_popover_carousel_footer(gtx, &m.page, 4, next_text = "Continue") {
					m.finished = true
				}
			}
		}
		info_label(gtx, "Name", "Your full name, as on your passport.")
	}
	if carousel(gtx, &m.slide, 3, autoplay = &m.carousel_auto) {
		NAMES := [3]string{"Card 0 action", "Card 1 action", "Card 2 action"}
		for i in 0 ..< 3 {
			if carousel_card(gtx, i) {
				if button(gtx, NAMES[i], key = u64(i)) {
					m.card_hits[i] += 1
				}
			}
		}
	}
}

@(test)
test_popover_opens_above_its_trigger_and_closes :: proc(t: ^testing.T) {
	m: Pop_Model
	p: ui.Probe
	ui.probe_init(&p, pop_ui, &m, POP_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	_, found := ui.probe_find(&p, "Popover")
	testing.expect(t, !found)
	testing.expect(t, ui.probe_click(&p, "Open"))
	testing.expect(t, m.open)
	ui.probe_advance(&p, 30, 0.02) // through the enter motion
	surface, trigger := ui.probe_bounds(&p, "Popover"), ui.probe_bounds(&p, "Open")
	testing.expect(t, surface.h > 0)
	testing.expect(t, abs(surface.y + surface.h + 4 - trigger.y) < 0.5) // above, 4px away
	testing.expect(t, abs(surface.x + surface.w / 2 - (trigger.x + 48)) < 0.5) // centred on the 96px anchor
	testing.expect(t, ui.probe_click(&p, "Inside"))
	testing.expect_value(t, m.insides, 1)
	testing.expect(t, m.open)
	// Escape once the surface has focus.
	ui.probe_click_at(&p, {surface.x + 4, surface.y + 4})
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
	// A press outside closes it.
	testing.expect(t, ui.probe_click(&p, "Open"))
	ui.probe_advance(&p, 30, 0.02)
	testing.expect(t, m.open)
	ui.probe_click_at(&p, {880, 690})
	testing.expect(t, !m.open)
}

@(test)
test_teaching_popover_pages_and_finishes :: proc(t: ^testing.T) {
	m: Pop_Model
	p: ui.Probe
	ui.probe_init(&p, pop_ui, &m, POP_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Tour"))
	ui.probe_advance(&p, 30, 0.02)
	testing.expect(t, ui.probe_tagged(&p, "1 of 4"))
	testing.expect(t, ui.probe_tagged(&p, "Not now"))
	surface := ui.probe_bounds(&p, "Teaching popover")
	testing.expect(t, surface.w >= 320)
	testing.expect(t, ui.probe_click(&p, "Continue"))
	testing.expect_value(t, m.page, 1)
	ui.probe_frame(&p) // the count redraws the frame after the click
	testing.expect(t, ui.probe_tagged(&p, "2 of 4"))
	testing.expect(t, ui.probe_tagged(&p, "Previous"))
	testing.expect(t, ui.probe_click(&p, "Page 1 of 4"))
	testing.expect_value(t, m.page, 0)
	ui.probe_frame(&p) // the selected bar widens a frame later, moving the dots after it
	ui.probe_key(&p, .Right) // arrows move focus between the dots, not the page
	testing.expect_value(t, ui.probe_focus_name(&p), "Page 2 of 4")
	testing.expect_value(t, m.page, 0)
	testing.expect(t, ui.probe_click(&p, "Page 4 of 4"))
	testing.expect_value(t, m.page, 3)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Finish"))
	testing.expect(t, ui.probe_click(&p, "Finish"))
	testing.expect(t, m.finished)
	testing.expect(t, !m.teach)
	// The header's dismiss closes it too.
	testing.expect(t, ui.probe_click(&p, "Tour"))
	ui.probe_advance(&p, 30, 0.02)
	testing.expect(t, ui.probe_click(&p, "Dismiss"))
	testing.expect(t, !m.teach)
}

@(test)
test_info_label_button_opens_its_popover :: proc(t: ^testing.T) {
	m: Pop_Model
	p: ui.Probe
	ui.probe_init(&p, pop_ui, &m, POP_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	b := ui.probe_bounds(&p, "Information: Name")
	testing.expect_value(t, b.w, 24) // a 16px icon padded 4px across
	testing.expect_value(t, b.h, 24)
	testing.expect(t, !ui.probe_tagged(&p, "Information"))
	testing.expect(t, ui.probe_click(&p, "Information: Name"))
	ui.probe_advance(&p, 30, 0.02)
	testing.expect(t, ui.probe_tagged(&p, "Your full name, as on your passport."))
	s := ui.probe_bounds(&p, "Information")
	testing.expect(t, s.w <= 264)
	testing.expect(t, s.y + s.h <= b.y) // above the button
	testing.expect_value(t, s.x, b.x) // flush with its start
	ui.probe_click_at(&p, {880, 690})
	testing.expect(t, !ui.probe_tagged(&p, "Information"))
}

@(test)
test_carousel_pages_by_buttons_dots_and_autoplay :: proc(t: ^testing.T) {
	m: Pop_Model
	p: ui.Probe
	ui.probe_init(&p, pop_ui, &m, POP_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_tagged(&p, "Card 0 action"))
	testing.expect(t, !ui.probe_tagged(&p, "Card 1 action"))
	testing.expect(t, !ui.probe_click(&p, "Previous")) // disabled on the first page
	testing.expect(t, ui.probe_click(&p, "Next"))
	testing.expect_value(t, m.slide, 1)
	ui.probe_advance(&p, 30, 0.02) // through the slide
	testing.expect(t, !ui.probe_tagged(&p, "Card 0 action"))
	// The slid card takes its clicks where it is drawn.
	testing.expect(t, ui.probe_click(&p, "Card 1 action"))
	testing.expect_value(t, m.card_hits[1], 1)
	testing.expect(t, ui.probe_click(&p, "Page 3 of 3"))
	testing.expect_value(t, m.slide, 2)
	ui.probe_advance(&p, 30, 0.02)
	testing.expect(t, !ui.probe_click(&p, "Next")) // disabled on the last page
	// Autoplay advances every 4s and wraps; a press on a dot stops it.
	testing.expect(t, ui.probe_click(&p, "Autoplay"))
	testing.expect(t, m.carousel_auto)
	ui.probe_advance(&p, 205, 0.02)
	testing.expect_value(t, m.slide, 0)
	ui.probe_advance(&p, 30, 0.02)
	testing.expect(t, ui.probe_click(&p, "Page 2 of 3"))
	testing.expect_value(t, m.slide, 1)
	testing.expect(t, !m.carousel_auto)
	// The dots are one tab stop whose arrows move focus; Enter selects.
	ui.probe_key(&p, .Right)
	testing.expect_value(t, ui.probe_focus_name(&p), "Page 3 of 3")
	testing.expect_value(t, m.slide, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.slide, 2)
	ui.probe_advance(&p, 30, 0.02)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "Autoplay") // Next is disabled on the last page
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, ui.probe_focus_name(&p), "Page 3 of 3")
}

// bottom_popover asks for a popover below a trigger 40px from the
// window's bottom edge.
@(private = "file")
bottom_popover :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Pop_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	ui.spacer(gtx, POP_WINDOW.y - 40)
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	if button(gtx, "Open") {
		m.open = !m.open
	}
	if popover(gtx, &m.open, {96, 32}, .Below, arrow = true) {
		if button(gtx, "Inside") {
			m.insides += 1
		}
	}
}

@(test)
test_popover_near_the_bottom_opens_above_its_trigger :: proc(t: ^testing.T) {
	m: Pop_Model
	p: ui.Probe
	ui.probe_init(&p, bottom_popover, &m, POP_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Open"))
	ui.probe_advance(&p, 30, 0.02) // through the enter motion
	trigger := ui.probe_bounds(&p, "Open")
	for name in ([]string{"Popover", "Inside"}) {
		r := ui.probe_bounds(&p, name)
		testing.expectf(t, r.h > 0 && r.y >= 0 && r.y + r.h <= POP_WINDOW.y, "%s at %v leaves the window", name, r)
		testing.expectf(t, r.y + r.h <= trigger.y, "%s at %v is not above the trigger at %v", name, r, trigger)
	}
	testing.expect(t, ui.probe_click(&p, "Inside"))
	testing.expect_value(t, m.insides, 1)
}
