package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of the toaster and the message bar, driven through ui.Probe.

@(private = "file")
NOTIFY_WINDOW :: ops.Size{800, 600}

@(private = "file")
Notify_Model :: struct {
	toasts:    Toasts,
	pause:     bool,
	dismissed: int,
	action:    int,
	closed:    bool,
}

@(private = "file")
notify_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Notify_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if button(gtx, "Notify") {
		toast_push(&m.toasts, "Saved", "Your changes are saved.", .Success)
	}
	if button(gtx, "Sticky") {
		toast_push(&m.toasts, "Pinned", intent = .Warning, timeout = TOAST_STICKY)
	}
	a, d := message_bar(gtx, .Error, "Upload failed", "The file was too large to send.", {"Retry"}, dismissable = true)
	if a >= 0 {
		m.action = a + 1
	}
	if d {
		m.closed = true
	}
	if id := toaster(gtx, &m.toasts, NOTIFY_WINDOW, pause_on_hover = m.pause); id != 0 {
		m.dismissed = id
	}
}

@(test)
test_toast_appears_times_out_and_dismisses :: proc(t: ^testing.T) {
	m: Notify_Model
	defer toasts_destroy(&m.toasts)
	p: ui.Probe
	ui.probe_init(&p, notify_ui, &m, NOTIFY_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Notify"))
	testing.expect_value(t, len(m.toasts.items), 1)
	ui.probe_advance(&p, 40, 0.02) // through the enter motion
	testing.expect(t, ui.probe_tagged(&p, "Saved"))
	// Placed at the bottom end: 20px from the right, 16px from the bottom.
	r := ui.probe_bounds(&p, "Saved")
	testing.expect_value(t, r.x + r.w, NOTIFY_WINDOW.x - 20)
	testing.expect_value(t, r.w, 292)
	testing.expect(t, abs(r.y + r.h - (NOTIFY_WINDOW.y - 16)) < 0.5)
	// 3s after the enter motion, then the exit motion: gone.
	ui.probe_advance(&p, 200, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
	testing.expect(t, !ui.probe_tagged(&p, "Saved"))

	// A sticky toast stays until its dismiss button is pressed.
	testing.expect(t, ui.probe_click(&p, "Sticky"))
	ui.probe_advance(&p, 300, 0.02)
	testing.expect(t, ui.probe_tagged(&p, "Pinned"))
	testing.expect(t, ui.probe_click(&p, "Dismiss Pinned"))
	testing.expect(t, m.dismissed != 0)
	ui.probe_advance(&p, 50, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_toast_hover_pauses_its_clock :: proc(t: ^testing.T) {
	m := Notify_Model{pause = true}
	defer toasts_destroy(&m.toasts)
	p: ui.Probe
	ui.probe_init(&p, notify_ui, &m, NOTIFY_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Notify"))
	ui.probe_advance(&p, 40, 0.02)
	c, ok := ui.probe_center(&p, "Saved")
	testing.expect(t, ok)
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 300, 0.02) // 6s, twice the timeout
	testing.expect_value(t, len(m.toasts.items), 1)
	ui.probe_move(&p, 10, 590)
	ui.probe_advance(&p, 250, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_message_bar_actions_dismiss_and_reflow :: proc(t: ^testing.T) {
	m: Notify_Model
	p: ui.Probe
	ui.probe_init(&p, notify_ui, &m, NOTIFY_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_tagged(&p, "Upload failed"))
	testing.expect(t, ui.probe_click(&p, "Retry"))
	testing.expect_value(t, m.action, 1)
	testing.expect(t, ui.probe_click(&p, "Dismiss"))
	testing.expect(t, m.closed)
	// Wide: one line, so the action and the dismiss share a row.
	retry, dismiss := ui.probe_bounds(&p, "Retry"), ui.probe_bounds(&p, "Dismiss")
	testing.expect_value(t, retry.y, dismiss.y)

	// Narrow: two lines, the actions on a row of their own below.
	n: Notify_Model
	q: ui.Probe
	ui.probe_init(&q, notify_ui, &n, {320, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&q)
	ui.probe_frame(&q)
	retry, dismiss = ui.probe_bounds(&q, "Retry"), ui.probe_bounds(&q, "Dismiss")
	testing.expect(t, retry.y > dismiss.y + dismiss.h)
}

@(test)
test_a_toasts_text_selects_yet_the_toast_still_dismisses :: proc(t: ^testing.T) {
	m: Notify_Model
	defer toasts_destroy(&m.toasts)
	p: ui.Probe
	ui.probe_init(&p, notify_ui, &m, NOTIFY_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Sticky"))
	ui.probe_advance(&p, 40, 0.02)
	b := ui.probe_bounds(&p, "Pinned")
	at := ops.Point{b.x + 45, b.y + 20} // in the title, past the 37px of padding and icon
	ui.router_push(&p.router, {kind = .Press, pos = at, clicks = 2})
	ui.router_push(&p.router, {kind = .Release, pos = at, clicks = 2})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect_value(t, ui.label_selection(&ctx), "Pinned")
	testing.expect(t, ui.probe_click(&p, "Dismiss Pinned"))
	testing.expect(t, m.dismissed != 0)
}
