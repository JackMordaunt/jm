package base

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Page is a test ui: a free label, and a clickable card with a label on
// it, the card's area recorded under the label's as a container's is.
@(private = "file")
Page :: struct {
	clicks:    int,
	cancelled: bool,
	card:      ops.Area_Id,
}

@(private = "file")
page :: proc(gtx: ^ui.Ctx, user: rawptr) {
	pg := (^Page)(user)
	col := ui.column_open(gtx, gap = 20)
	defer ui.close(&col)
	label(gtx, "free text here")
	// The card: a stack, its own area first, then its label over it.
	stack := ui.stack_open(gtx)
	defer ui.close(&stack)
	w := ui.widget_open(gtx)
	pg.card = w.id
	st := ui.widget_state(gtx, w.id)
	bounds := ops.Rect{0, 0, 300, 40}
	for e in ui.events(gtx, w.id) {
		if e.kind == .Cancel {
			pg.cancelled = true
		}
	}
	if ui.click_from_events(gtx, w.id, st, bounds) {
		pg.clicks += 1
	}
	ops.input_area(gtx.scene, w.id, bounds, {.Press, .Release, .Enter, .Leave, .Move})
	ops.tag(gtx.scene, w.id, "card")
	ui.widget_close(gtx, &w, {{300, 40}, 12})
	label(gtx, "card title words")
}

@(private = "file")
open :: proc(p: ^ui.Probe, pg: ^Page) {
	ui.probe_init(p, page, pg, {400, 200})
}

// drag presses at a, moves to b and releases, clicks times pressed.
@(private = "file")
drag :: proc(p: ^ui.Probe, a, b: ops.Point, clicks: u8 = 1) {
	ui.router_push(&p.router, {kind = .Press, pos = a, clicks = clicks})
	ui.router_push(&p.router, {kind = .Move, pos = b})
	ui.router_push(&p.router, {kind = .Release, pos = b, clicks = clicks})
	ui.probe_frame(p)
	ui.probe_frame(p)
}

@(test)
test_a_label_selects_by_drag_and_copies :: proc(t: ^testing.T) {
	pg: Page
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	b := ui.probe_bounds(&p, "free text here")
	drag(&p, {b.x + 1, b.y + b.h / 2}, {b.x + b.w + 20, b.y + b.h / 2})
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect_value(t, ui.label_selection(&ctx), "free text here")
	ui.probe_key(&p, .C, {ui.SHORTCUT})
	testing.expect_value(t, ui.probe_clipboard(&p), "free text here")
	// Typing into read-only text changes nothing.
	ui.probe_type(&p, "x")
	testing.expect_value(t, ui.label_selection(&ctx), "free text here")
}

@(test)
test_a_click_on_text_in_a_card_clicks_the_card :: proc(t: ^testing.T) {
	pg: Page
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	c, _ := ui.probe_center(&p, "card title words")
	drag(&p, c, c) // a press and release where it began: a click
	testing.expect_value(t, pg.clicks, 1)
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect_value(t, ui.label_selection(&ctx), "")
	testing.expect_value(t, ui.probe_cursor(&p), ops.Cursor.Text)
}

@(test)
test_a_drag_on_text_in_a_card_selects_instead :: proc(t: ^testing.T) {
	pg: Page
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	b := ui.probe_bounds(&p, "card title words")
	drag(&p, {b.x + 1, b.y + b.h / 2}, {b.x + b.w + 5, b.y + b.h / 2})
	testing.expect_value(t, pg.clicks, 0)
	testing.expect(t, pg.cancelled, "the card heard its press was taken")
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect_value(t, ui.label_selection(&ctx), "card title words")
}

@(test)
test_a_double_click_on_text_in_a_card_selects_a_word :: proc(t: ^testing.T) {
	pg: Page
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	b := ui.probe_bounds(&p, "card title words")
	at := ops.Point{b.x + 2, b.y + b.h / 2} // in "card"
	drag(&p, at, at, clicks = 2)
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect_value(t, ui.label_selection(&ctx), "card")
	testing.expect_value(t, pg.clicks, 0)
}

@(test)
test_a_press_elsewhere_clears_a_label_selection :: proc(t: ^testing.T) {
	pg: Page
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	b := ui.probe_bounds(&p, "free text here")
	drag(&p, {b.x + 1, b.y + b.h / 2}, {b.x + b.w + 20, b.y + b.h / 2})
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect(t, ui.label_selection(&ctx) != "")
	testing.expect(t, ui.probe_click(&p, "card"))
	testing.expect_value(t, ui.label_selection(&ctx), "")
}


@(test)
test_a_card_keeps_its_hover_over_its_own_text :: proc(t: ^testing.T) {
	pg: Page
	p: ui.Probe
	open(&p, &pg)
	defer ui.probe_destroy(&p)
	c, _ := ui.probe_center(&p, "card title words")
	ui.probe_move(&p, c.x, c.y)
	testing.expect_value(t, p.router.hover, pg.card)
	testing.expect_value(t, ui.probe_cursor(&p), ops.Cursor.Text) // yet the pointer shows the text
}
