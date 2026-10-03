package ui

import "jm:ui/ops"
import "core:testing"

// focus_map_view is a page button, then a trap holding a button and a
// toolbar roving across two buttons, the trap's area tagged "Dialog".
@(private = "file")
focus_map_view :: proc(gtx: ^Ctx, user: rawptr) {
	button :: proc(gtx: ^Ctx, id: ops.Area_Id, name: string, x, y: f32) {
		ops.input_area(gtx.scene, id, ops.Rect{x, y, 40, 20}, {.Press, .Release, .Key, .Focus, .Blur})
		ops.tag(gtx.scene, id, name)
	}
	button(gtx, 1, "page", 0, 0)
	focus_scope_open(gtx, 50, trap = true)
	ops.tag(gtx.scene, 50, "Dialog")
	button(gtx, 10, "ok", 100, 100)
	focus_scope_open(gtx, 60, rove = .Horizontal)
	button(gtx, 20, "bold", 100, 140)
	button(gtx, 21, "italic", 150, 140)
	focus_scope_close(gtx, entry = 21)
	focus_scope_close(gtx)
}

@(test)
test_the_focus_map_boxes_scopes_numbers_stops_and_rings_focus :: proc(t: ^testing.T) {
	p: Probe
	probe_init(&p, focus_map_view, nil, {400, 300}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	probe_key(&p, .Tab)
	probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, ops.Area_Id(21)) // the toolbar's entry, after ok

	m := focus_map(&p.prev, &p.router, 1, context.temp_allocator)
	testing.expect_value(t, len(m.scopes), 2)
	if len(m.scopes) != 2 {
		return
	}
	trap, bar := m.scopes[0], m.scopes[1]
	testing.expect(t, trap.active)
	testing.expect_value(t, trap.name, "Dialog")
	testing.expect_value(t, trap.height, 1)
	testing.expect_value(t, bar.height, 0)
	g := FOCUS_SCOPE_GROW
	testing.expect_value(t, bar.rect, ops.Rect{100 - g, 140 - g, 90 + 2 * g, 20 + 2 * g}) // round bold and italic
	testing.expect_value(t, trap.rect, ops.Rect{100 - 2 * g, 100 - 2 * g, 90 + 4 * g, 60 + 4 * g}) // round all three, outside the toolbar's
	// The trap holds Tab: ok, then the toolbar as one stop at its entry.
	testing.expect_value(t, len(m.stops), 2)
	if len(m.stops) == 2 {
		testing.expect_value(t, m.stops[0], ops.Rect{100, 100, 40, 20})
		testing.expect_value(t, m.stops[1], ops.Rect{150, 140, 40, 20})
	}
	testing.expect_value(t, m.focus, ops.Rect{150, 140, 40, 20})
}

@(test)
test_the_tray_toggles_the_focus_map :: proc(t: ^testing.T) {
	p: Probe
	probe_init(&p, focus_map_view, nil, {800, 600}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	count_defers :: proc(p: ^Probe) -> (n: int) {
		for op in p.scene.ops {
			if _, ok := op.(ops.Defer); ok {
				n += 1
			}
		}
		return
	}
	probe_key(&p, DEBUG_TOGGLE_KEY)
	testing.expect(t, probe_click(&p, "Focus scopes and Tab stops"))
	probe_frame(&p)
	testing.expect(t, .Focus in p.tray.flags)
	on := count_defers(&p)
	// Off again, with the pointer still over the tray: one layer fewer.
	testing.expect(t, probe_click(&p, "Focus scopes and Tab stops"))
	probe_frame(&p)
	testing.expect(t, .Focus not_in p.tray.flags)
	testing.expect_value(t, count_defers(&p), on - 1) // the map is a layer over the app
}
