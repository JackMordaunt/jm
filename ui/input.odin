package ui

// SKELETON, owned by work package D (see the plan). Rewrite freely but keep
// the names other packages use: Router, router_init, events.

// Router turns device events into per-area events by hit-testing against
// the previous frame's hits. Widgets read their events during layout.
Router :: struct {
	queue:  [dynamic]Raw_Event, // device events since the last route
	events: [dynamic]Event, // this frame's routed events
	focus:  Area_Id,
	hover:  Area_Id,
}

router_init :: proc(r: ^Router, allocator := context.allocator) {
	r.queue = make([dynamic]Raw_Event, allocator)
	r.events = make([dynamic]Event, allocator)
}

router_destroy :: proc(r: ^Router) {
	delete(r.queue)
	delete(r.events)
	r^ = {}
}

// router_push queues a device event for the next route.
router_push :: proc(r: ^Router, e: Raw_Event) {
	append(&r.queue, e)
}

// router_route hit-tests the queued device events against f (the previous
// frame) and fills r.events for the frame about to be laid out. Call it once
// per frame before the ui proc. f may be nil on the first frame.
router_route :: proc(r: ^Router, f: ^Frame) {
	clear(&r.events)
	clear(&r.queue)
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
