package primer

import "core:strings"
import "core:testing"
import "jm:ui"

// A segment with a tooltip says it in a bubble when the pointer rests on it.

@(private = "file")
segments_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	at := (^int)(user)
	segs := [?]Segment {
		{label = "Map", icon = .Circle},
		{label = "Reclaim", icon = .Trash, tooltip = "Free up space"},
	}
	segmented_control(gtx, segs[:], at, name = "View")
}

@(test)
test_a_segment_with_a_tooltip_says_it_on_hover :: proc(t: ^testing.T) {
	at := 0
	p: ui.Probe
	ui.probe_init(&p, segments_view, &at, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, !strings.contains(said, "Free up space"), said)

	c, _ := ui.probe_center(&p, "Reclaim")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 12, 1.0 / 60) // past the delay
	said = ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `tooltip "Free up space"`), said)

	// Another segment has none to show.
	c, _ = ui.probe_center(&p, "Map")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 12, 1.0 / 60)
	said = ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, !strings.contains(said, "Free up space"), said)
}
