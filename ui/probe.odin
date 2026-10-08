package ui

import "core:mem"
import "jm:ui/ops"
import "core:time"
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
// Memory: sc and frames use the allocator given to probe_init. Each frame
// gets a fresh arena (Ctx.allocator) that is reset at the start of the next
// probe_frame; slices returned by probe_names live in it.
Probe :: struct {
	scene:         ops.Scene,
	frame:       Frame, // scratch: the next flatten target
	prev:        Frame, // the frame just laid out; probe_current returns it
	router:      Router,
	layout:      Layout,
	font:        ops.Font_Id, // gtx.font for every frame
	shaper:      Shaper,
	ui:          proc(gtx: ^Ctx, user: rawptr),
	user:        rawptr,
	size:        ops.Size,
	dt:          f32, // gtx.dt for the next probe_frame; probe_set_dt overrides
	time:        f64, // gtx.time: advanced by each frame's dt; set it to jump the clock
	frame_no:    u64,
	wants_frame: bool, // the last frame called request_frame
	frame_after: f32, // then: the soonest it asked for, in seconds
	debug:       Debug_Flags, // gtx.debug for every frame; probe_init takes it
	reduce_motion: bool, // gtx.reduce_motion for every frame: a test sets it, never the platform
	density:     f32, // gtx.density for every frame: device pixels per unit; 0 reads as 1
	tray:        Debug_Tray, // DEBUG_TOGGLE_KEY opens it, as in a live loop; its stats are the last frame's
	arena:       ops.Frame_Arena,
	allocator:   mem.Allocator,
	clipboard:   [dynamic]u8, // the fake system clipboard frames write and read
	opened:      [dynamic]u8, // the last URL a frame asked to open
	text_input:  Text_Input, // the last Text_Input a frame asked for
	text_inputs: int, // how many Text_Inputs frames have asked for
	persisted:   [dynamic]u8, // what the last frame that called persist asked to keep: the host's copy, in a live loop
	persists:    int, // frames that called persist
	restore:     [dynamic]u8, // probe_restore's bytes, given to the next frame as restored
	restoring:   bool,
	subs:        Subscriptions, // the host's view of the frame's needs; see probe_added
	inbox:       Inbox, // shapes on their way to the next frame; see probe_deliver
	data:        ^Data_Host, // an application answering the needs itself, as a live loop's
}

// probe_init prepares p to drive ui with user at a window of size, then
// runs the first frame so names are findable at once. shaper is
// stub_shaper(); font is the toolkit's face. data, when given, is an
// application in the probe's process, as a live loop's Data_Host: each
// frame's need diff and commands go to it, and its inbox is drained
// before each frame, beside the probe's own.
probe_init :: proc(
	p: ^Probe,
	ui: proc(gtx: ^Ctx, user: rawptr),
	user: rawptr,
	size: ops.Size,
	font: ops.Font_Id = 0,
	allocator := context.allocator,
	debug: Debug_Flags = {},
	data: ^Data_Host = nil,
) {
	p^ = {}
	p.debug = debug
	p.data = data
	debug_tray_init(&p.tray)
	p.ui = ui
	p.user = user
	p.size = size
	p.allocator = allocator
	p.clipboard = make([dynamic]u8, allocator)
	p.opened = make([dynamic]u8, allocator)
	p.persisted = make([dynamic]u8, allocator)
	p.restore = make([dynamic]u8, allocator)
	p.shaper = stub_shaper()
	p.font = font
	p.dt = 1.0 / 60
	subscriptions_init(&p.subs, allocator)
	inbox_init(&p.inbox, allocator)
	ops.init(&p.scene, allocator)
	frame_init(&p.frame, allocator)
	frame_init(&p.prev, allocator)
	router_init(&p.router, allocator)
	layout_init(&p.layout, allocator)
	err := ops.frame_arena_init(&p.arena)
	assert(err == nil, "probe: arena init failed")
	probe_frame(p)
}

// probe_destroy frees everything p owns.
probe_destroy :: proc(p: ^Probe) {
	layout_destroy(&p.layout)
	router_destroy(&p.router)
	frame_destroy(&p.frame)
	frame_destroy(&p.prev)
	ops.destroy(&p.scene)
	ops.frame_arena_destroy(&p.arena)
	delete(p.clipboard)
	delete(p.opened)
	delete(p.persisted)
	delete(p.restore)
	subscriptions_destroy(&p.subs)
	inbox_destroy(&p.inbox)
	p^ = {}
}

// probe_frame runs one frame: route queued input against the last frame,
// record the ui, flatten it. Afterwards probe_current is the new frame.
probe_frame :: proc(p: ^Probe) {
	if debug_take_toggles(&p.router) {
		p.tray.open = !p.tray.open
	}
	debug := p.debug | debug_tray_flags(&p.tray)
	router_route(&p.router, &p.prev)
	debug_tray_log(&p.tray, &p.router, &p.prev, p.frame_no)
	ops.frame_arena_reset(&p.arena)
	ops.reset(&p.scene)
	p.scene.outline_areas = .Bounds in debug
	layout_reset(&p.layout)
	// Last frame's needs and commands were readable until now, as a
	// host reads them between frames; this frame's shapes land first.
	router_needs_clear(&p.router)
	router_commands_clear(&p.router)
	inbox_drain(&p.inbox, &p.layout)
	if p.data != nil && p.data.inbox != nil {
		inbox_drain(p.data.inbox, &p.layout)
	}
	dt := debug_dt(debug, p.dt)
	p.time += f64(dt)
	gtx := Ctx {
		scene         = &p.scene,
		constraints = exact(p.size),
		viewport    = p.size,
		density     = p.density,
		font        = p.font,
		shaper      = p.shaper,
		router      = &p.router,
		layout      = &p.layout,
		frame       = p.frame_no,
		dt          = dt,
		time        = p.time,
		allocator   = ops.frame_arena_allocator(&p.arena),
		debug       = debug,
		restored    = p.restore[:] if p.restoring else nil,
		reduce_motion = p.reduce_motion,
	}
	p.restoring = false
	ui_start := time.tick_now()
	p.ui(&gtx, p.user)
	ui_ms := ms(ui_start)
	if gtx.persist != nil {
		clear(&p.persisted)
		append(&p.persisted, ..gtx.persist)
		p.persists += 1
	}
	debug_inspect(&gtx, debug, &p.tray, &p.prev, p.router.pointer, 1)
	debug_tray(&gtx, &p.tray) // last: over the inspector's highlight too
	p.wants_frame, p.frame_after = gtx.wants_frame, gtx.frame_after
	build_start := time.tick_now()
	flatten(&p.scene, &p.frame, {0, 0, p.size.x, p.size.y})
	text_input_update(&p.router, &p.frame)
	debug_tray_record(&p.tray, frame_stats(&gtx, &p.frame, ui_ms, ms(build_start), ops.frame_arena_used(&p.arena)))
	p.frame, p.prev = p.prev, p.frame
	p.frame_no += 1
	probe_platform(p)
	added, dropped := subscriptions_update(&p.subs, router_needs(&p.router))
	if p.data != nil {
		data_dispatch(p.data, added, dropped, router_commands(&p.router))
	}
}

// probe_platform carries out the frame's requests as a host would, on
// the probe's fake clipboard: a write replaces it, a read answers with a
// Paste for the next frame. An opened URL is kept for probe_opened_url,
// a Text_Input in p.text_input.
@(private = "file")
probe_platform :: proc(p: ^Probe) {
	for q in router_requests(&p.router) {
		switch v in q {
		case Clipboard_Write:
			clear(&p.clipboard)
			append(&p.clipboard, v.data)
		case Clipboard_Read:
			router_push(&p.router, {kind = .Paste, text = string(p.clipboard[:]), mime = v.mime})
		case Open_Url:
			clear(&p.opened)
			append(&p.opened, v.url)
		case Text_Input:
			p.text_input = v
			p.text_inputs += 1
		}
	}
	router_requests_clear(&p.router)
}

// probe_clipboard is the fake clipboard's text; valid until the next frame
// that writes it.
probe_clipboard :: proc(p: ^Probe) -> string {
	return string(p.clipboard[:])
}

// probe_opened_url is the last URL a frame asked to open, "" if none;
// valid until the next frame that opens one.
probe_opened_url :: proc(p: ^Probe) -> string {
	return string(p.opened[:])
}

// probe_persisted is what the last frame that called persist asked the
// host to keep, as a host would hold it; empty until a frame does.
probe_persisted :: proc(p: ^Probe) -> []byte {
	return p.persisted[:]
}

// probe_restore gives data to the next frame as restored, as the host
// gives a respawned child what the last one persisted: run probe_frame
// to deliver it. The frame after sees nil again.
probe_restore :: proc(p: ^Probe, data: []byte) {
	clear(&p.restore)
	append(&p.restore, ..data)
	p.restoring = true
}

// probe_needs is the set of shapes the last frame asked for, each once, in
// the order first asked: what a host would subscribe to. Valid until the
// next frame.
probe_needs :: proc(p: ^Probe) -> []Need {
	return router_needs(&p.router)
}

// probe_commands is what the last frame asked the application to process,
// in order. Valid until the next frame.
probe_commands :: proc(p: ^Probe) -> []Command {
	return router_commands(&p.router)
}

// probe_added is what the last frame needed that the frame before did not:
// what a host starts. Valid until the next frame.
probe_added :: proc(p: ^Probe) -> []Need {
	return p.subs.added[:]
}

// probe_dropped is what the frame before needed and the last frame did not:
// what a host cancels. Valid until the next frame.
probe_dropped :: proc(p: ^Probe) -> []Need {
	return p.subs.dropped[:]
}

// probe_needs_q reports whether the last frame needed the shape for q.
probe_needs_q :: proc(p: ^Probe, q: $Q) -> bool {
	return subscriptions_live(&p.subs, key_of(q))
}

// probe_deliver gives the next frame the shape v for query q, as a host
// answering the need would: run probe_frame to deliver it.
probe_deliver :: proc(p: ^Probe, q: $Q, v: $R, status: Status = .Ready) {
	inbox_put_value(&p.inbox, q, v, status)
}

// probe_deliver_raw is probe_deliver with the shape as bytes under key.
probe_deliver_raw :: proc(p: ^Probe, key: Need_Key, data: []byte, status: Status = .Ready) {
	inbox_put(&p.inbox, key, data, status)
}

// probe_set_clipboard puts text on the fake clipboard, as another app would.
probe_set_clipboard :: proc(p: ^Probe, text: string) {
	clear(&p.clipboard)
	append(&p.clipboard, text)
}

// probe_cursor is the pointer's look after the last frame's route.
probe_cursor :: proc(p: ^Probe) -> ops.Cursor {
	return router_cursor(&p.router)
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

// probe_bounds is the device-space bounding rect of the area tagged
// name, or the zero rect when nothing is: where a widget landed, for a
// test that measures rather than clicks.
probe_bounds :: proc(p: ^Probe, name: string) -> ops.Rect {
	h, ok := probe_find(p, name)
	if !ok {
		return {}
	}
	return ops.transform_rect(h.transform, ops.shape_bounds(&p.scene, h.shape))
}

// probe_focus_name is the tag of the area holding keyboard focus in the
// current frame, "" when none does or it has no tag.
probe_focus_name :: proc(p: ^Probe) -> string {
	for t in probe_current(p).tags {
		if t.id == p.router.focus {
			return t.name
		}
	}
	return ""
}

// probe_find returns the hit of the first area tagged name in the current
// frame (the top-most hit when the area has several). A tag with no area
// but with bounds (a label, a message: anything tagged with its box)
// finds as a hit of no kinds over those bounds, so probe_bounds and
// probe_center measure it and a click lands on whatever is under it.
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
		if t.bounds != {} {
			return Hit{area = t.id, shape = t.bounds, transform = ops.IDENTITY, clip = NO_CLIP}, true
		}
	}
	return {}, false
}

// probe_find_top is probe_find for the last-drawn area tagged name: the
// one on top, which a hand would hit, where probe_find takes the first.
// An open panel's item and the grid cell under it with the same text, or a
// nav item and a heading of one name, tell apart this way.
probe_find_top :: proc(p: ^Probe, name: string) -> (Hit, bool) {
	f := probe_current(p)
	#reverse for t in f.tags {
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

// probe_click_top clicks the center of the last-drawn area tagged name
// that takes input (probe_find_top). It returns false, and does nothing,
// when there is none.
probe_click_top :: proc(p: ^Probe, name: string, button: Button = .Left, clicks: u8 = 1) -> bool {
	h, ok := probe_find_top(p, name)
	if !ok {
		return false
	}
	r := ops.transform_rect(h.transform, ops.shape_bounds(&p.scene, h.shape))
	probe_click_at(p, {r.x + r.w / 2, r.y + r.h / 2}, button, clicks)
	return true
}

// probe_center returns the device-space center of the bounding rect of the
// area tagged name.
probe_center :: proc(p: ^Probe, name: string) -> (ops.Point, bool) {
	h, ok := probe_find(p, name)
	if !ok {
		return {}, false
	}
	r := ops.transform_rect(h.transform, ops.shape_bounds(&p.scene, h.shape))
	return {r.x + r.w / 2, r.y + r.h / 2}, true
}

// probe_click moves to the center of the area tagged name, presses, runs a
// frame, releases and runs another, so the ui has seen both Press and
// Release. clicks is the press's count, 2 for a double click. It returns
// false, and does nothing, when name is not found.
probe_click :: proc(p: ^Probe, name: string, button: Button = .Left, clicks: u8 = 1) -> bool {
	c, ok := probe_center(p, name)
	if !ok {
		return false
	}
	probe_click_at(p, c, button, clicks)
	return true
}

// probe_click_at clicks as probe_click does, at device point pos rather
// than a tag's center: a point on a canvas, which has one area for all it
// draws.
probe_click_at :: proc(p: ^Probe, pos: ops.Point, button: Button = .Left, clicks: u8 = 1) {
	router_push(&p.router, {kind = .Move, pos = pos})
	router_push(&p.router, {kind = .Press, pos = pos, button = button, clicks = clicks})
	probe_frame(p)
	router_push(&p.router, {kind = .Release, pos = pos, button = button})
	probe_frame(p)
}

// probe_drag presses at the center of the area tagged name, moves the
// pointer by (dx, dy) in steps equal moves, a frame after each, and
// releases where it ends: a drag as a hand makes one, so a slop threshold
// or a per-move gesture sees several Moves, not one jump. It returns
// false, and does nothing, when name is not found.
probe_drag :: proc(p: ^Probe, name: string, dx, dy: f32, steps := 4, button: Button = .Left) -> bool {
	c, ok := probe_center(p, name)
	if !ok {
		return false
	}
	router_push(&p.router, {kind = .Move, pos = c})
	router_push(&p.router, {kind = .Press, pos = c, button = button})
	probe_frame(p)
	n := max(steps, 1)
	at := c
	for i in 1 ..= n {
		at = {c.x + dx * f32(i) / f32(n), c.y + dy * f32(i) / f32(n)}
		router_push(&p.router, {kind = .Move, pos = at})
		probe_frame(p)
	}
	router_push(&p.router, {kind = .Release, pos = at, button = button})
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

// probe_compose sends an input method's preedit text, its caret or
// selection lo to hi in bytes, to the focused area and runs a frame; ""
// ends the composition. A commit is a probe_type.
probe_compose :: proc(p: ^Probe, text: string, lo := -1, hi := -1) {
	assert(utf8.valid_string(text), "probe_compose: text is not UTF-8")
	at := lo if lo >= 0 else len(text)
	router_push(&p.router, {kind = .Compose, text = text, span = {at, hi if hi >= at else at}})
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
	probe_scroll_at(p, c, dy)
	return true
}

// probe_scroll_at scrolls by dy with the pointer at device point pos and
// runs a frame: for a region whose own name is ambiguous or untagged, such
// as a grid's body, scrolled where its rows are.
probe_scroll_at :: proc(p: ^Probe, pos: ops.Point, dy: f32) {
	router_push(&p.router, {kind = .Scroll, pos = pos, scroll = {0, dy}})
	probe_frame(p)
}

// probe_move moves the pointer to device point (x, y) and runs a frame.
probe_move :: proc(p: ^Probe, x, y: f32) {
	router_push(&p.router, {kind = .Move, pos = {x, y}})
	probe_frame(p)
}

// probe_dump is dump of the sc recorded by the last frame.
probe_dump :: proc(p: ^Probe) -> string {
	return ops.dump(&p.scene)
}

// probe_dump_frame is dump_frame of the current frame.
probe_dump_frame :: proc(p: ^Probe) -> string {
	return dump_frame(probe_current(p))
}

// probe_semantics is semantics_report of the current frame, with the
// focused area marked: the screen as a screen reader would read it.
probe_semantics :: proc(p: ^Probe, allocator := context.allocator) -> string {
	return semantics_report(probe_current(p), p.router.focus, allocator)
}

// probe_tagged reports whether the current frame tags anything name,
// whether or not it has an input area: a label, a message, a row that
// only paints. probe_find is the one for what a pointer can reach.
probe_tagged :: proc(p: ^Probe, name: string) -> bool {
	for t in probe_current(p).tags {
		if t.name == name {
			return true
		}
	}
	return false
}

// probe_names lists every tag name in the current frame in recording
// order. The slice lives in the frame arena, valid until the next frame.
probe_names :: proc(p: ^Probe) -> []string {
	f := probe_current(p)
	out := make([]string, len(f.tags), ops.frame_arena_allocator(&p.arena))
	for t, i in f.tags {
		out[i] = t.name
	}
	return out
}
