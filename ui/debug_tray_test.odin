package ui

import "core:strings"
import "jm:ui/ops"
import "core:testing"

@(test)
test_debug_tray_opens_toggles_and_records_stats :: proc(t: ^testing.T) {
	Seen :: struct {
		debug: Debug_Flags,
	}
	view :: proc(gtx: ^Ctx, user: rawptr) {
		(^Seen)(user).debug = gtx.debug
		label(gtx, "page")
	}
	seen: Seen
	p: Probe
	probe_init(&p, view, &seen, {800, 600}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, !p.tray.open)
	testing.expect_value(t, seen.debug, Debug_Flags{})

	probe_key(&p, DEBUG_TOGGLE_KEY)
	testing.expect(t, p.tray.open)
	testing.expect_value(t, seen.debug, DEBUG_TOGGLE)

	// Its toggles are tagged areas like any other.
	testing.expect(t, probe_click(&p, "Slow motion (quarter speed)"))
	probe_frame(&p)
	testing.expect_value(t, seen.debug, DEBUG_TOGGLE + {.Slow})
	testing.expect(t, probe_click(&p, "Full frames (compositor damage off)"))
	testing.expect(t, debug_tray_wants_full_frames(&p.tray))

	// Stats are the last frame's, and the report is text for agents.
	testing.expect(t, p.tray.last.ops > 0 && p.tray.last.frame == p.frame_no - 1)
	testing.expect(t, strings.contains(frame_stats_report(p.tray.last, context.temp_allocator), "widget state"))

	// Closed, it adds nothing, and the full frames go with it.
	probe_key(&p, DEBUG_TOGGLE_KEY)
	testing.expect_value(t, seen.debug, Debug_Flags{})
	testing.expect(t, !debug_tray_wants_full_frames(&p.tray))
}

@(test)
test_inspector_skips_the_open_tray :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		label(gtx, "page")
	}
	p: Probe
	probe_init(&p, view, nil, {800, 600}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	probe_key(&p, DEBUG_TOGGLE_KEY)
	r := p.tray.rect
	probe_move(&p, r.x + r.w / 2, r.y + r.h / 2)
	probe_frame(&p)
	deferred := 0
	for op in p.scene.ops {
		if d, ok := op.(ops.Defer); ok && d.root {
			deferred += 1
		}
	}
	testing.expect_value(t, deferred, 0) // no inspector panel over the tray
}

@(test)
test_event_log_names_each_target_and_skips_moves :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		p := widget_open(gtx, 1)
		ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 80, 30}, {.Press, .Release, .Move, .Enter, .Leave})
		ops.tag(gtx.scene, p.id, frame_string(gtx, "Save"))
		widget_close(gtx, &p, {size = {80, 30}})
	}
	p: Probe
	probe_init(&p, view, nil, {200, 100}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, probe_click(&p, "Save"))
	lines := event_log_lines(&p.tray, EVENT_LOG_CAP, context.temp_allocator)
	kinds: [dynamic]ops.Event_Kind
	defer delete(kinds)
	testing.expect(t, p.tray.events_n >= 2) // so the loop below asserts something
	for i in 0 ..< p.tray.events_n {
		e := p.tray.events[i]
		append(&kinds, e.kind)
		testing.expect_value(t, string(e.name[:e.name_len]), "Save") // copied, though its frame is gone
	}
	testing.expect(t, len(kinds) >= 2)
	for k in kinds {
		testing.expect(t, k != .Move)
	}
	testing.expect(t, strings.contains(lines[len(lines) - 1], "-> \"Save\""))
	testing.expect(t, strings.contains(event_log_report(&p.tray, context.temp_allocator), "Press"))
}

@(test)
test_flash_is_off_and_untouchable_under_full_frames :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {}
	p: Probe
	probe_init(&p, view, nil, {800, 600}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	probe_key(&p, DEBUG_TOGGLE_KEY)
	testing.expect(t, probe_click(&p, "Flash repaints"))
	testing.expect(t, debug_tray_wants_flash(&p.tray))
	testing.expect(t, probe_click(&p, "Full frames (compositor damage off)"))
	probe_frame(&p)
	testing.expect(t, !debug_tray_wants_flash(&p.tray)) // the whole window repaints: nothing to flash
	testing.expect(t, !probe_click(&p, "Flash repaints")) // dimmed, with no area to click
	testing.expect(t, probe_click(&p, "Full frames (compositor damage off)"))
	probe_frame(&p)
	testing.expect(t, debug_tray_wants_flash(&p.tray)) // the choice was kept
}

@(test)
test_debug_tray_drags_by_its_title_and_stays_in_the_window :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {}
	p: Probe
	probe_init(&p, view, nil, {1200, 1000}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	probe_key(&p, DEBUG_TOGGLE_KEY)
	start := p.tray.rect
	testing.expect(t, start.x + start.w > 1100 && start.y + start.h > 900) // the bottom-right corner

	grip, ok := probe_center(&p, "Debug tray")
	testing.expect(t, ok)
	router_push(&p.router, {kind = .Move, pos = grip})
	router_push(&p.router, {kind = .Press, pos = grip, button = .Left})
	probe_frame(&p)
	router_push(&p.router, {kind = .Move, pos = grip - {300, 200}})
	probe_frame(&p)
	router_push(&p.router, {kind = .Release, pos = grip - {300, 200}, button = .Left})
	probe_frame(&p)
	testing.expect_value(t, ops.Point{p.tray.rect.x, p.tray.rect.y}, ops.Point{start.x - 300, start.y - 200})

	// Dragged far past the top-left, it stops at the window's edge.
	grip, _ = probe_center(&p, "Debug tray")
	router_push(&p.router, {kind = .Move, pos = grip})
	router_push(&p.router, {kind = .Press, pos = grip, button = .Left})
	probe_frame(&p)
	router_push(&p.router, {kind = .Move, pos = grip - {5000, 5000}})
	probe_frame(&p)
	router_push(&p.router, {kind = .Release, pos = grip - {5000, 5000}, button = .Left})
	probe_frame(&p)
	testing.expect_value(t, ops.Point{p.tray.rect.x, p.tray.rect.y}, ops.Point{0, 0})
}

@(test)
test_tray_collapses_to_its_title_and_sits_over_a_modal :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		// A modal that covers the window, as a dialog's scrim does.
		o := overlay_open(gtx, {0, 0}, cs = loose({800, 600}), root = true, cover = true)
		ops.fill(gtx.scene, ops.Rect{0, 0, 800, 600}, ops.Color{0, 0, 0, 128})
		ops.input_area(gtx.scene, claim_id(gtx), ops.Rect{0, 0, 800, 600}, {.Press, .Release})
		close(&o)
	}
	p: Probe
	probe_init(&p, view, nil, {800, 600})
	defer probe_destroy(&p)
	probe_key(&p, DEBUG_TOGGLE_KEY)
	open_h := p.tray.rect.h
	testing.expect(t, open_h > TRAY_TITLE)
	// The tray's title is hit over the modal's area: the tray is on top.
	testing.expect(t, probe_tagged(&p, "Collapse tray"))
	testing.expect(t, probe_click(&p, "Collapse tray"))
	testing.expect(t, p.tray.collapsed)
	testing.expect_value(t, p.tray.rect.h, TRAY_TITLE)
	testing.expect(t, probe_click(&p, "Expand tray"))
	testing.expect(t, !p.tray.collapsed)
	testing.expect_value(t, p.tray.rect.h, open_h)
}
