package ui

// SKELETON, owned by work package D (see the plan). Rewrite freely but keep
// the names other packages use: Router, router_init, events.

// Router turns device events into per-area events by hit-testing against
// the previous frame's hits. Widgets read their events during layout.
Router :: struct {
	events: [dynamic]Event, // this frame's routed events
	focus:  Area_Id,
	hover:  Area_Id,
}

router_init :: proc(r: ^Router, allocator := context.allocator) {
	r.events = make([dynamic]Event, allocator)
}

router_destroy :: proc(r: ^Router) {
	delete(r.events)
	r^ = {}
}

// events returns the events routed to area this frame, in arrival order.
// The slice aliases router storage and is valid for the frame.
events :: proc(gtx: ^Ctx, area: Area_Id) -> []Event {
	if gtx.router == nil {
		return nil
	}
	out := make([dynamic]Event, gtx.allocator)
	for e in gtx.router.events {
		if e.area == area {
			append(&out, e)
		}
	}
	return out[:]
}
