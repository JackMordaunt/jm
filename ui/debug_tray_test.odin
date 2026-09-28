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
