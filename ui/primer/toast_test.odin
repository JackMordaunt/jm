package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// The toaster, through probes: placement, the clock and what holds it,
// sticky errors, actions, updates in place, the limit and Escape.

@(private = "file")
TOAST_WINDOW :: ops.Size{800, 600}

@(private = "file")
Toast_Model :: struct {
	toasts:   Toasts,
	position: Toast_Position,
	events:   [dynamic]Toaster_Event,
}

@(private = "file")
toast_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Toast_Model)(user)
	button(gtx, "Elsewhere")
	if e := toaster(gtx, &m.toasts, m.position); e != {} {
		append(&m.events, e)
	}
}

@(private = "file")
toast_probe :: proc(p: ^ui.Probe, m: ^Toast_Model, window := TOAST_WINDOW) {
	ui.probe_init(p, toast_view, m, window, allocator = context.temp_allocator)
	ui.probe_frame(p)
}

@(private = "file")
toast_model_destroy :: proc(m: ^Toast_Model) {
	toasts_destroy(&m.toasts)
	delete(m.events)
}

// SETTLE_FRAMES is enough 20ms frames for the 180ms enter or exit to end.
@(private = "file")
SETTLE_FRAMES :: 12

@(test)
test_a_toast_rises_into_the_bottom_end_and_times_out :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	toast_push(&m.toasts, "Saved", .Success)
	ui.probe_advance(&p, 4, 0.02) // mid-enter: still below its resting place
	mid := ui.probe_bounds(&p, "Saved")
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	r := ui.probe_bounds(&p, "Saved")
	testing.expect(t, mid.y > r.y, "the toast rises as it enters")
	testing.expect_value(t, r.x + r.w, TOAST_WINDOW.x - 16)
	testing.expect_value(t, r.y + r.h, TOAST_WINDOW.y - 16)
	testing.expect_value(t, r.h, 16 + 21 + 16) // one line padded 16px
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "status \"Saved\""), sem)
	testing.expect(t, strings.contains(sem, "  button \"Dismiss\""), sem)

	// 5s after the enter, then the exit: gone, and nothing reported.
	ui.probe_advance(&p, 240, 0.02)
	testing.expect_value(t, len(m.toasts.items), 1)
	ui.probe_advance(&p, 20, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
	testing.expect(t, !ui.probe_tagged(&p, "Saved"))
	testing.expect_value(t, len(m.events), 0)
}

@(test)
test_hovering_a_toast_holds_its_clock :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	toast_push(&m.toasts, "Saved", .Success)
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	c, ok := ui.probe_center(&p, "Saved")
	testing.expect(t, ok)
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 600, 0.02) // 12s, over twice the timeout
	testing.expect_value(t, len(m.toasts.items), 1)
	// Over its dismiss button still counts as over the toast.
	d, _ := ui.probe_center(&p, "Dismiss Saved")
	ui.probe_move(&p, d.x, d.y)
	ui.probe_advance(&p, 300, 0.02)
	testing.expect_value(t, len(m.toasts.items), 1)
	ui.probe_move(&p, 10, 10)
	ui.probe_advance(&p, 300, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_keyboard_focus_in_a_toast_holds_its_clock_and_escape_dismisses_it :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	id := toast_push(&m.toasts, "Rig 12 restarted", opts = {action = "View"})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	for _ in 0 ..< 4 {
		if ui.probe_focus_name(&p) == "View" {
			break
		}
		ui.probe_key(&p, .Tab)
	}
	testing.expect_value(t, ui.probe_focus_name(&p), "View")
	ui.probe_advance(&p, 600, 0.02)
	testing.expect_value(t, len(m.toasts.items), 1)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "Dismiss Rig 12 restarted")
	ui.probe_advance(&p, 600, 0.02)
	testing.expect_value(t, len(m.toasts.items), 1)

	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect_value(t, len(m.events), 1)
	testing.expect_value(t, m.events[0], Toaster_Event{dismissed = id})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_an_error_toast_stays_and_announces_assertively_until_dismissed :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	cause := Toast_Options {
		detail = "QuickBooks returned 503.",
	}
	id := toast_push(&m.toasts, "Could not save the rig", .Error, cause)
	ui.probe_advance(&p, 1500, 0.02) // 30s
	testing.expect_value(t, len(m.toasts.items), 1)
	r := ui.probe_bounds(&p, "Could not save the rig")
	testing.expect_value(t, r.h, 16 + 21 + 4 + 21 + 16) // the detail 4px under the message
	sem := ui.probe_semantics(&p, context.temp_allocator)
	said := "alert \"Could not save the rig\" desc \"QuickBooks returned 503.\""
	testing.expect(t, strings.contains(sem, said), sem)

	testing.expect(t, ui.probe_click(&p, "Dismiss Could not save the rig"))
	testing.expect_value(t, m.events[0], Toaster_Event{dismissed = id})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_a_toasts_action_is_reported_and_dismisses_it :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	id := toast_push(&m.toasts, "Invoice failed", .Error, {action = "Retry"})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	retry, msg := ui.probe_bounds(&p, "Retry"), ui.probe_bounds(&p, "Invoice failed")
	testing.expect_value(t, retry.y, msg.y + 16) // on the message's first line
	testing.expect(t, ui.probe_click(&p, "Retry"))
	testing.expect_value(t, len(m.events), 1)
	testing.expect_value(t, m.events[0], Toaster_Event{action = id})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_a_loading_toast_updates_in_place_and_then_times_out :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	toast_push(&m.toasts, "Older", .Success, {timeout = TOAST_STICKY})
	id := toast_push(&m.toasts, "Syncing 40 rigs", .Loading)
	ui.probe_advance(&p, 600, 0.02) // loading is sticky
	testing.expect(t, ui.probe_tagged(&p, "Syncing 40 rigs"))
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "status \"Syncing 40 rigs\" busy"), sem)
	before := ui.probe_bounds(&p, "Syncing 40 rigs")

	testing.expect(t, toast_update(&m.toasts, id, "Synced 40 rigs", .Success))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Syncing 40 rigs"))
	after := ui.probe_bounds(&p, "Synced 40 rigs")
	testing.expect_value(t, after.y, before.y) // in place: still the newest, nearest the edge
	testing.expect_value(t, m.toasts.items[1].id, id)
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "status \"Synced 40 rigs\" at"), sem)

	ui.probe_advance(&p, 200, 0.02) // 4s of a success's 5s
	// A second update restarts the clock: 4s more and it still shows.
	testing.expect(t, toast_update(&m.toasts, id, "Synced 41 rigs", .Success))
	ui.probe_advance(&p, 200, 0.02)
	testing.expect(t, ui.probe_tagged(&p, "Synced 41 rigs"))
	ui.probe_advance(&p, 80, 0.02) // the rest, then the exit
	testing.expect_value(t, len(m.toasts.items), 1)
	testing.expect_value(t, m.toasts.items[0].message, "Older")
	testing.expect(t, !toast_update(&m.toasts, id, "Too late", .Success))
}

@(test)
test_a_push_past_the_limit_evicts_the_oldest :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Toast_Model{toasts = {limit = 3}}
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	toast_push(&m.toasts, "One")
	toast_push(&m.toasts, "Two")
	toast_push(&m.toasts, "Three")
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	toast_push(&m.toasts, "Four")
	testing.expect(t, m.toasts.items[0].leaving, "the oldest leaves")
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect_value(t, len(m.toasts.items), 3)
	testing.expect(t, !ui.probe_tagged(&p, "One"))
	// Stacked newest nearest the edge, 16px apart.
	four, three := ui.probe_bounds(&p, "Four"), ui.probe_bounds(&p, "Three")
	two := ui.probe_bounds(&p, "Two")
	testing.expect_value(t, four.y + four.h, TOAST_WINDOW.y - 16)
	testing.expect_value(t, three.y + three.h, four.y - 16)
	testing.expect_value(t, two.y + two.h, three.y - 16)
}

@(test)
test_toasts_stack_at_the_top_start_and_fill_a_narrow_window :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Toast_Model{position = .Top_Start}
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)
	toast_push(&m.toasts, "First")
	toast_push(&m.toasts, "Second")
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	first, second := ui.probe_bounds(&p, "First"), ui.probe_bounds(&p, "Second")
	testing.expect_value(t, second.x, 16)
	testing.expect_value(t, second.y, 16) // newest nearest the top
	testing.expect_value(t, first.y, second.y + second.h + 16)
	testing.expect(t, second.w < 450, "as wide as the text needs")

	// A long message wraps at 450px.
	toast_push(&m.toasts, strings.repeat("word ", 40, context.temp_allocator))
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	long := ui.probe_bounds(&p, strings.repeat("word ", 40, context.temp_allocator))
	testing.expect_value(t, long.w, 450)
	testing.expect(t, long.h > 16 + 21 + 16)

	// Under 544px a toast fills the window less 8px a side.
	n := Toast_Model{}
	defer toast_model_destroy(&n)
	q: ui.Probe
	toast_probe(&q, &n, {400, 600})
	defer ui.probe_destroy(&q)
	toast_push(&n.toasts, "Narrow")
	ui.probe_advance(&q, SETTLE_FRAMES, 0.02)
	r := ui.probe_bounds(&q, "Narrow")
	testing.expect_value(t, r, ops.Rect{8, 600 - 8 - 53, 400 - 16, 53})
}

@(test)
test_reduced_motion_shows_and_removes_a_toast_at_once :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)
	p.reduce_motion = true
	id := toast_push(&m.toasts, "Saved")
	ui.probe_frame(&p)
	r := ui.probe_bounds(&p, "Saved")
	testing.expect_value(t, r.y + r.h, TOAST_WINDOW.y - 16)
	toast_dismiss(&m.toasts, id)
	ui.probe_frame(&p)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_the_queue_keeps_its_own_copy_of_a_message :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)
	buf := [5]u8{'r', 'i', 'g', ' ', '7'}
	toast_push(&m.toasts, string(buf[:]))
	buf[4] = '9'
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect(t, ui.probe_tagged(&p, "rig 7"))
}

@(test)
test_a_push_past_the_limit_spares_sticky_toasts_while_any_would_time_out :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Toast_Model{toasts = {limit = 3}}
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	toast_push(&m.toasts, "Sync failed", .Error)
	toast_push(&m.toasts, "Saved")
	toast_push(&m.toasts, "Syncing", .Loading)
	toast_push(&m.toasts, "Sent")
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect(t, ui.probe_tagged(&p, "Sync failed"), "the oldest, an error, stays")
	testing.expect(t, !ui.probe_tagged(&p, "Saved"), "the oldest that times out leaves")
	testing.expect(t, ui.probe_tagged(&p, "Syncing"))
	testing.expect(t, ui.probe_tagged(&p, "Sent"))
}

@(test)
test_a_push_past_the_limit_evicts_the_oldest_sticky_when_all_are :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m := Toast_Model{toasts = {limit = 2}}
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	toast_push(&m.toasts, "First error", .Error)
	toast_push(&m.toasts, "Syncing", .Loading)
	toast_push(&m.toasts, "Second error", .Error)
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect(t, !ui.probe_tagged(&p, "First error"))
	testing.expect(t, ui.probe_tagged(&p, "Syncing"))
	testing.expect(t, ui.probe_tagged(&p, "Second error"))
}

@(test)
test_a_toasts_text_selects_copies_and_holds_its_clock :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	toast_push(&m.toasts, "Rig 12 restarted", opts = {detail = "Uptime reset"})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	b := ui.probe_bounds(&p, "Rig 12 restarted")
	// A double click on the detail's first word: past the 48px band and
	// 16px padding, on the second line.
	at := ops.Point{b.x + 48 + 16 + 10, b.y + 16 + 21 + 4 + 10}
	ui.router_push(&p.router, {kind = .Press, pos = at, clicks = 2})
	ui.router_push(&p.router, {kind = .Release, pos = at, clicks = 2})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	ui.probe_key(&p, .C, {ui.SHORTCUT})
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_clipboard(&p), "Uptime")
	testing.expect(t, ui.probe_tagged(&p, "Rig 12 restarted"), "a press on text keeps it")

	// Focus in the text holds the clock with the pointer gone.
	ui.probe_move(&p, 10, 590)
	ui.probe_advance(&p, 600, 0.02)
	testing.expect_value(t, len(m.toasts.items), 1)
	testing.expect(t, ui.probe_click(&p, "Elsewhere"))
	ui.probe_advance(&p, 300, 0.02)
	testing.expect_value(t, len(m.toasts.items), 0)
}

@(test)
test_an_error_toasts_copy_button_copies_its_message_and_detail :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m)
	defer ui.probe_destroy(&p)

	opts := Toast_Options {
		detail = "QuickBooks returned 503.",
		action = "Retry",
	}
	id := toast_push(&m.toasts, "Invoice failed", .Error, opts)
	toast_push(&m.toasts, "Saved", .Success)
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect(t, !ui.probe_tagged(&p, "Copy Saved"), "only an error has Copy")
	retry, copy := ui.probe_bounds(&p, "Retry"), ui.probe_bounds(&p, "Copy Invoice failed")
	close := ui.probe_bounds(&p, "Dismiss Invoice failed")
	testing.expect_value(t, copy.x, retry.x + retry.w + 16) // packed: action, Copy, X
	testing.expect_value(t, close.x, copy.x + 48)
	testing.expect(t, ui.probe_click(&p, "Copy Invoice failed"))
	testing.expect_value(t, ui.probe_clipboard(&p), "Invoice failed\nQuickBooks returned 503.")
	testing.expect_value(t, m.events[0], Toaster_Event{copied = id})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	testing.expect(t, ui.probe_tagged(&p, "Invoice failed"), "copying keeps the toast")
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(sem, "  button \"Copy\""), sem)
}

@(test)
test_a_narrow_toast_packs_its_buttons_after_the_text :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Toast_Model
	defer toast_model_destroy(&m)
	p: ui.Probe
	toast_probe(&p, &m, {400, 600})
	defer ui.probe_destroy(&p)
	toast_push(&m.toasts, "Saved", opts = {action = "View"})
	ui.probe_advance(&p, SETTLE_FRAMES, 0.02)
	r := ui.probe_bounds(&p, "Saved")
	view, close := ui.probe_bounds(&p, "View"), ui.probe_bounds(&p, "Dismiss Saved")
	testing.expect_value(t, r.w, 400 - 16) // the surface still fills the window
	testing.expect(t, view.x < r.x + 48 + 16 + 60, "the action follows the short text")
	testing.expect_value(t, close.x, view.x + view.w + 16)
	testing.expect(t, close.x + close.w < r.x + r.w - 100, "the X is not pinned to the end")
}
