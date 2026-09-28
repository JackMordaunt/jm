package ui

import "core:mem"
import "core:unicode/utf8"

// Probe drives a ui proc headless, one frame per call, for tests and
// agents: inject input by tag name, then read the frame or its dump.
//
//	p: ui.Probe
//	ui.probe_init(&p, my_ui, &model, {800, 600})
//	defer ui.probe_destroy(&p)
//	ui.probe_click(&p, "Save")
//	fmt.println(ui.probe_names(&p))
//
// Every input proc pushes its device events and runs frames until the ui
// proc has seen them: input is routed against the previous frame, so an
// event lands one frame after it is pushed.
//
// Memory: ops and frames use the allocator given to probe_init. Each frame
// gets a fresh arena (Ctx.allocator) that is reset at the start of the next
// probe_frame; slices returned by probe_names live in it.
Probe :: struct {
	ops:         Ops,
	frame:       Frame, // scratch: the next flatten target
	prev:        Frame, // the frame just laid out; probe_current returns it
	router:      Router,
	layout:      Layout,
	theme:       Theme,
	shaper:      Shaper,
	ui:          proc(gtx: ^Ctx, user: rawptr),
	user:        rawptr,
	size:        Size,
	dt:          f32, // gtx.dt for the next probe_frame; probe_set_dt overrides
	time:        f64, // gtx.time: advanced by each frame's dt; set it to jump the clock
	frame_no:    u64,
	wants_frame: bool, // the last frame called request_frame
	frame_after: f32, // then: the soonest it asked for, in seconds
	debug:       Debug_Flags, // gtx.debug for every frame; probe_init takes it
	arena:       Frame_Arena,
	allocator:   mem.Allocator,
}

// probe_init prepares p to drive ui with user at a window of size, then
// runs the first frame so names are findable at once. shaper is
// stub_shaper(); theme defaults to default_theme(font).
probe_init :: proc(
	p: ^Probe,
	ui: proc(gtx: ^Ctx, user: rawptr),
	user: rawptr,
	size: Size,
	font: Font_Id = 0,
	theme: Maybe(Theme) = nil,
	allocator := context.allocator,
	debug: Debug_Flags = {},
) {
	p^ = {}
	p.debug = debug
	p.ui = ui
	p.user = user
	p.size = size
	p.allocator = allocator
	p.shaper = stub_shaper()
	p.theme = theme.? or_else default_theme(font)
	p.dt = 1.0 / 60
	ops_init(&p.ops, allocator)
	frame_init(&p.frame, allocator)
	frame_init(&p.prev, allocator)
	router_init(&p.router, allocator)
	layout_init(&p.layout, allocator)
	err := frame_arena_init(&p.arena)
	assert(err == nil, "probe: arena init failed")
	probe_frame(p)
}

// probe_destroy frees everything p owns.
probe_destroy :: proc(p: ^Probe) {
	layout_destroy(&p.layout)
	router_destroy(&p.router)
	frame_destroy(&p.frame)
	frame_destroy(&p.prev)
	ops_destroy(&p.ops)
	frame_arena_destroy(&p.arena)
	p^ = {}
}

// probe_frame runs one frame: route queued input against the last frame,
// record the ui, flatten it. Afterwards probe_current is the new frame.
probe_frame :: proc(p: ^Probe) {
	if debug_take_toggles(&p.router) {
		p.debug ~= DEBUG_TOGGLE
	}
	router_route(&p.router, &p.prev)
	frame_arena_reset(&p.arena)
	ops_reset(&p.ops)
	p.ops.debug = p.debug
	layout_reset(&p.layout)
	dt := debug_dt(p.debug, p.dt)
	p.time += f64(dt)
	gtx := Ctx {
		ops         = &p.ops,
		constraints = exact(p.size),
		theme       = &p.theme,
		shaper      = p.shaper,
		router      = &p.router,
		layout      = &p.layout,
		frame       = p.frame_no,
		dt          = dt,
		time        = p.time,
		allocator   = frame_arena_allocator(&p.arena),
		debug       = p.debug,
	}
	p.ui(&gtx, p.user)
	if .Inspect in p.debug {
		paint_inspector(&gtx, &p.prev, p.router.pointer)
	}
	p.wants_frame, p.frame_after = gtx.wants_frame, gtx.frame_after
	flatten(&p.ops, &p.frame)
	p.frame, p.prev = p.prev, p.frame
	p.frame_no += 1
}

// probe_set_dt overrides gtx.dt for every probe_frame from here on, in
// place of the fixed 1/60 s default: an animation driven by dt can be
// sampled at a chosen rate, or advanced by a chosen step with probe_advance,
// without waiting on a real clock.
probe_set_dt :: proc(p: ^Probe, dt: f32) {
	p.dt = dt
}

// probe_advance runs n frames (one when n <= 0), each dt seconds apart, and
// leaves probe_current as the last. It is probe_frame repeated for an
// animation that needs several steps to reach the state under test.
probe_advance :: proc(p: ^Probe, n: int, dt: f32) {
	prev := p.dt
	probe_set_dt(p, dt)
	defer probe_set_dt(p, prev)
	for _ in 0 ..< max(n, 1) {
		probe_frame(p)
	}
}

// probe_current returns the frame laid out by the last probe_frame.
probe_current :: proc(p: ^Probe) -> ^Frame {
	return &p.prev
}

// probe_find returns the hit of the first area tagged name in the current
// frame (the top-most hit when the area has several).
probe_find :: proc(p: ^Probe, name: string) -> (Hit, bool) {
	f := probe_current(p)
	for t in f.tags {
		if t.name != name {
			continue
		}
		#reverse for h in f.hits {
			if h.area == t.id {
				return h, true
			}
		}
	}
	return {}, false
}

// probe_center returns the device-space center of the bounding rect of the
// area tagged name.
probe_center :: proc(p: ^Probe, name: string) -> (Point, bool) {
	h, ok := probe_find(p, name)
	if !ok {
		return {}, false
	}
	r := transform_rect(h.transform, shape_bounds(&p.ops, h.shape))
	return {r.x + r.w / 2, r.y + r.h / 2}, true
}

// probe_click moves to the center of the area tagged name, presses, runs a
// frame, releases and runs another, so the ui has seen both Press and
// Release. It returns false, and does nothing, when name is not found.
probe_click :: proc(p: ^Probe, name: string, button: Button = .Left) -> bool {
	c, ok := probe_center(p, name)
	if !ok {
		return false
	}
	router_push(&p.router, {kind = .Move, pos = c})
	router_push(&p.router, {kind = .Press, pos = c, button = button})
	probe_frame(p)
	router_push(&p.router, {kind = .Release, pos = c, button = button})
	probe_frame(p)
	return true
}

// probe_type sends text as one Text event (the whole string, not one per
// rune) to the focused area and runs a frame.
probe_type :: proc(p: ^Probe, text: string) {
	assert(utf8.valid_string(text), "probe_type: text is not UTF-8")
	router_push(&p.router, {kind = .Text, text = text})
	probe_frame(p)
}

// probe_key sends key with mods to the focused area and runs a frame.
probe_key :: proc(p: ^Probe, key: Key, mods: Mods = {}) {
	router_push(&p.router, {kind = .Key, key = key, mods = mods})
	probe_frame(p)
}

// probe_scroll scrolls by dy at the center of the area tagged name and runs
// a frame. It returns false, and does nothing, when name is not found.
probe_scroll :: proc(p: ^Probe, name: string, dy: f32) -> bool {
	c, ok := probe_center(p, name)
	if !ok {
		return false
	}
	router_push(&p.router, {kind = .Scroll, pos = c, scroll = {0, dy}})
	probe_frame(p)
	return true
}

// probe_move moves the pointer to device point (x, y) and runs a frame.
probe_move :: proc(p: ^Probe, x, y: f32) {
	router_push(&p.router, {kind = .Move, pos = {x, y}})
	probe_frame(p)
}

// probe_dump is dump of the ops recorded by the last frame.
probe_dump :: proc(p: ^Probe) -> string {
	return dump(&p.ops)
}

// probe_dump_frame is dump_frame of the current frame.
probe_dump_frame :: proc(p: ^Probe) -> string {
	return dump_frame(probe_current(p))
}

// probe_names lists every tag name in the current frame in recording
// order. The slice lives in the frame arena, valid until the next frame.
probe_names :: proc(p: ^Probe) -> []string {
	f := probe_current(p)
	out := make([]string, len(f.tags), frame_arena_allocator(&p.arena))
	for t, i in f.tags {
		out[i] = t.name
	}
	return out
}
