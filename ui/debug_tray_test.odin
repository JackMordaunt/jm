package ui

import "core:strings"
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
	for op in p.ops.ops {
		if d, ok := op.(Defer); ok && d.root {
			deferred += 1
		}
	}
	testing.expect_value(t, deferred, 0) // no inspector panel over the tray
}

@(test)
test_event_log_names_each_target_and_skips_moves :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		p := widget_begin(gtx, 1)
		input_area(gtx.ops, p.id, Rect{0, 0, 80, 30}, {.Press, .Release, .Move, .Enter, .Leave})
		tag(gtx.ops, p.id, frame_string(gtx, "Save"))
		widget_end(gtx, &p, {size = {80, 30}})
	}
	p: Probe
	probe_init(&p, view, nil, {200, 100}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, probe_click(&p, "Save"))
	lines := event_log_lines(&p.tray, EVENT_LOG_CAP, context.temp_allocator)
	kinds: [dynamic]Event_Kind
	defer delete(kinds)
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
