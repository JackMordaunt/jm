package ui

import "core:fmt"
import "jm:ui/ops"
import "core:strings"
import "core:time"

// Host_Stats is what presenting a frame cost whoever composites it: the
// SDL loop itself, or the hot-reload host, which sends them to its child
// with the next input.
Host_Stats :: struct {
	present_ms:    f32, // compose, upload and present
	roundtrip_ms:  f32, // host only: sending the input to getting the reply
	repaint_rects: int, // rects the compositor redrew
	repaint_px:    int, // their area in device pixels
	rss_bytes:     int, // host only: the host process's resident memory, 0 where unknown
}

// Frame_Stats is what a frame loop measured of one frame: for the debug
// tray, and for -stats in a headless session.
Frame_Stats :: struct {
	frame:       u64,
	dt:          f32, // seconds since the frame before
	ui_ms:       f32, // the app's ui proc: layout and recording
	build_ms:    f32, // flattening, and encoding for the host when there is one
	ops:        int,
	draws:       int,
	hits:        int,
	boxes:       int, // Debug_Box records, under Debug_Flag.Inspect
	states:      int, // retained Widget_States
	data:        int, // retained widget_data values
	arena_bytes: int, // the frame arena's allocations this frame
	rss_bytes:   int, // the process's resident memory, or -1 where not read
	host:        Host_Stats, // the frame before's presentation
}

// Logged_Event is one routed event in the debug tray's log. The target's
// tag is copied into name, as the frame it came from is gone next frame.
Logged_Event :: struct {
	frame:    u64,
	kind:     ops.Event_Kind,
	key:      Key,
	pos:      ops.Point,
	name:     [32]u8,
	name_len: u8,
	area:     ops.Area_Id,
}

// EVENT_LOG_CAP is how many routed events the tray keeps; it shows the last
// few, -events prints them all.
EVENT_LOG_CAP :: 32

// TRAY_HISTORY is how many frames the tray's frame-time graph shows.
TRAY_HISTORY :: 120

// Debug_Tray is a frame loop's debug panel: DEBUG_TOGGLE_KEY opens and
// closes it, its toggles set the debug flags, and it shows the loop's
// Frame_Stats. The loop owns it; the app never sees it.
Debug_Tray :: struct {
	open:        bool,
	flags:       Debug_Flags, // what the toggles set while open
	full_frames: bool, // the compositor redraws every frame whole, damage tracking off
	flash:       bool, // the compositor tints what it repaints, fading
	events:      [EVENT_LOG_CAP]Logged_Event, // newest at events_head - 1
	events_head: int,
	events_n:    int,
	last:        Frame_Stats,
	history:     [TRAY_HISTORY]f32, // frame times in ms, newest at head - 1
	head:        int,
	count:       int,
	rect:        ops.Rect, // where it was drawn last, in the ui's own units, so the inspector can skip it
	panel:       ops.Rect, // the inspector's panel this frame, device space, or empty
	offset:      ops.Point, // where its title bar has dragged it from the bottom-right corner
	dragging:    bool,
	collapsed:   bool, // only the title bar shows, to see more of the ui
}

// debug_tray_init gives t its opening toggles: what F11 turned on before
// the tray existed.
debug_tray_init :: proc(t: ^Debug_Tray) {
	t.flags = DEBUG_TOGGLE
}

// debug_tray_flags is what t adds to the environment's debug flags: its
// toggles while open, nothing while closed.
debug_tray_flags :: proc(t: ^Debug_Tray) -> Debug_Flags {
	return t.open ? t.flags : {}
}

// debug_tray_wants_full_frames reports whether t asks the compositor to redraw
// every frame whole.
debug_tray_wants_full_frames :: proc(t: ^Debug_Tray) -> bool {
	return t.open && t.full_frames
}

// debug_tray_wants_flash reports whether t asks the compositor to tint
// what it repaints. Not under full frames: every frame repaints the whole
// window then, and the flash would only tint all of it.
debug_tray_wants_flash :: proc(t: ^Debug_Tray) -> bool {
	return t.open && t.flash && !t.full_frames
}

// debug_tray_log records the events r routed this frame into t's log,
// naming each target by its tag in prev, the frame they were routed
// against. Moves are left out: they would flood it.
debug_tray_log :: proc(t: ^Debug_Tray, r: ^Router, prev: ^Frame, frame: u64) {
	for e in r.events {
		if e.kind == .Move {
			continue
		}
		l := Logged_Event {
			frame = frame,
			kind  = e.kind,
			key   = e.key,
			pos   = e.pos,
			area  = e.area,
		}
		if prev != nil {
			for tg in prev.tags {
				if tg.id == e.area {
					l.name_len = u8(copy(l.name[:], tg.name))
					break
				}
			}
		}
		t.events[t.events_head] = l
		t.events_head = (t.events_head + 1) % EVENT_LOG_CAP
		t.events_n = min(t.events_n + 1, EVENT_LOG_CAP)
	}
}

// event_log_lines is t's newest most logged events as text, oldest first.
@(private)
event_log_lines :: proc(t: ^Debug_Tray, most: int, allocator := context.allocator) -> []string {
	n := min(most, t.events_n)
	lines := make([]string, n, allocator)
	for k in 0 ..< n {
		e := t.events[(t.events_head - n + k + EVENT_LOG_CAP) % EVENT_LOG_CAP]
		target := string(e.name[:e.name_len])
		if target == "" {
			target = fmt.tprintf("area %x", u64(e.area))
		}
		detail := ""
		#partial switch e.kind {
		case .Key:
			detail = fmt.tprintf(" %v", e.key)
		case .Press, .Release, .Scroll:
			detail = fmt.tprintf(" at %.0f,%.0f", e.pos.x, e.pos.y)
		}
		lines[k] = fmt.aprintf("%d %v%s -> %q", e.frame, e.kind, detail, target, allocator = allocator)
	}
	return lines
}

// event_log_report is t's whole event log as text: -events.
event_log_report :: proc(t: ^Debug_Tray, allocator := context.allocator) -> string {
	if t.events_n == 0 {
		return strings.clone("no events\n", allocator)
	}
	b := strings.builder_make(allocator)
	for l in event_log_lines(t, EVENT_LOG_CAP, context.temp_allocator) {
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

// debug_tray_record stores s as t's latest stats and its frame time in the
// graph.
debug_tray_record :: proc(t: ^Debug_Tray, s: Frame_Stats) {
	t.last = s
	t.history[t.head] = s.dt * 1000
	t.head = (t.head + 1) % TRAY_HISTORY
	t.count = min(t.count + 1, TRAY_HISTORY)
}

// frame_stats gathers what gtx's frame left in its sc, layout and frame
// f, with the loop's timings and arena use.
frame_stats :: proc(gtx: ^Ctx, f: ^Frame, ui_ms, build_ms: f32, arena_bytes: int, host: Host_Stats = {}) -> Frame_Stats {
	s := Frame_Stats {
		frame       = gtx.frame,
		dt          = gtx.dt,
		ui_ms       = ui_ms,
		build_ms    = build_ms,
		ops         = len(gtx.scene.ops),
		arena_bytes = arena_bytes,
		rss_bytes   = process_rss(),
		host        = host,
	}
	if f != nil {
		s.draws, s.hits, s.boxes = len(f.draws), len(f.hits), len(f.boxes)
	}
	if l := gtx.layout; l != nil {
		s.states, s.data = len(l.state), len(l.data)
	}
	return s
}

// debug_inspect paints the focus map when flags ask for it, then the
// inspector for device point p when flags ask for it and p is not over
// the open tray t (which it would otherwise inspect). density is the
// display scale; call it outside the scale transform.
debug_inspect :: proc(gtx: ^Ctx, flags: Debug_Flags, t: ^Debug_Tray, prev: ^Frame, p: ops.Point, density: f32) {
	t.panel = {}
	if .Focus in flags && prev != nil && gtx.router != nil {
		paint_focus_map(gtx, focus_map(prev, gtx.router, density, gtx.allocator), density)
	}
	if .Inspect not_in flags || prev == nil {
		return
	}
	if t.open && ops.rect_contains(t.rect, p / density) {
		return
	}
	t.panel = paint_inspector(gtx, prev, p, density)
}

// debug_tray_overlays is where t's own panels are, in device space for display
// density density: the tray and the inspector's panel, both redrawn every
// frame. The repaint flash leaves them out, or their own repaints would
// tint them past reading. Empty rects are left out; the slice is into buf.
debug_tray_overlays :: proc(t: ^Debug_Tray, density: f32, buf: ^[2]ops.Rect) -> []ops.Rect {
	n := 0
	if t.open {
		r := t.rect
		buf[n] = {r.x * density, r.y * density, r.w * density, r.h * density}
		n += 1
	}
	if t.panel.w > 0 && t.panel.h > 0 {
		buf[n] = t.panel
		n += 1
	}
	return buf[:n]
}

// ms is the milliseconds since start, for the loops' timings.
ms :: proc(start: time.Tick) -> f32 {
	return f32(time.duration_milliseconds(time.tick_since(start)))
}

// frame_stats_report is s as text, one figure a line: -stats.
frame_stats_report :: proc(s: Frame_Stats, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for l in stats_lines(s, context.temp_allocator) {
		strings.write_string(&b, l)
		strings.write_byte(&b, '\n')
	}
	return strings.to_string(b)
}

// stats_lines is s as the tray's lines of text.
@(private)
stats_lines :: proc(s: Frame_Stats, allocator := context.allocator) -> []string {
	lines := make([dynamic]string, allocator)
	fps := s.dt > 0 ? 1 / s.dt : 0
	append(&lines, fmt.aprintf("frame %d   %.1f ms   %.0f fps", s.frame, s.dt * 1000, fps, allocator = allocator))
	append(&lines, fmt.aprintf("ui %.2f ms   build %.2f ms", s.ui_ms, s.build_ms, allocator = allocator))
	append(&lines, fmt.aprintf("sc %d   draws %d   hits %d   boxes %d", s.ops, s.draws, s.hits, s.boxes, allocator = allocator))
	append(&lines, fmt.aprintf("widget state %d   widget data %d", s.states, s.data, allocator = allocator))
	rss := s.rss_bytes >= 0 ? fmt.tprintf("%.1f MiB", f64(s.rss_bytes) / (1 << 20)) : "n/a"
	append(&lines, fmt.aprintf("frame arena %.1f KiB   resident %s", f64(s.arena_bytes) / 1024, rss, allocator = allocator))
	if s.host.rss_bytes > 0 {
		// Hot reload: resident above is this ui process's; the host holds
		// the window, the renderer's textures and the compositor's image.
		append(&lines, fmt.aprintf("host resident %.1f MiB", f64(s.host.rss_bytes) / (1 << 20), allocator = allocator))
	}
	h := s.host
	rt := h.roundtrip_ms > 0 ? fmt.tprintf("   round trip %.2f ms", h.roundtrip_ms) : ""
	append(&lines, fmt.aprintf("present %.2f ms%s", h.present_ms, rt, allocator = allocator))
	append(&lines, fmt.aprintf("repainted %d rects, %.0fk px", h.repaint_rects, f64(h.repaint_px) / 1000, allocator = allocator))
	return lines[:]
}

// TRAY_TITLE is the height of the title bar the tray is dragged by.
TRAY_TITLE :: f32(24)

// TRAY_EVENTS is how many of the logged events the tray shows.
TRAY_EVENTS :: 6

// TRAY_WIDTH fits the longest toggle label at 12sp with its check.
TRAY_WIDTH :: f32(340)

// debug_tray draws t, when open, in the window's bottom-right corner above
// everything: a toggle a line for each debug switch, then the latest stats
// and a graph of recent frame times. It is laid out with debug flags off,
// so it neither outlines nor inspects itself. The frame loops call it
// after the app's ui, under the display scale.
debug_tray :: proc(gtx: ^Ctx, t: ^Debug_Tray) {
	if !t.open {
		return
	}
	saved, saved_outline := gtx.debug, gtx.scene.outline_areas
	gtx.debug, gtx.scene.outline_areas = {}, false
	defer gtx.debug, gtx.scene.outline_areas = saved, saved_outline

	TOGGLES :: [?]struct {
		flag: Debug_Flag,
		name: string,
	}{{.Bounds, "Outline widgets and input areas"}, {.Inspect, "Inspect under the pointer"}, {.Reveal, "Reveal hidden parts"}, {.Focus, "Focus scopes and Tab stops"}, {.Slow, "Slow motion (quarter speed)"}}
	pad, row, text :: f32(10), f32(22), f32(12)
	lines := stats_lines(t.last, gtx.allocator)
	log := event_log_lines(t, TRAY_EVENTS, gtx.allocator)
	graph_h :: f32(36)
	h := TRAY_TITLE + pad + row * f32(len(TOGGLES) + 2) + 6 + f32(len(lines)) * (text + 5) + 6 + graph_h + 8 + f32(TRAY_EVENTS) * (text + 3)
	// The fold button, at the title's right end, collapses the tray to
	// its title bar and expands it again.
	fold := claim_id(gtx, 3)
	for e in events(gtx, fold) {
		if e.kind == .Release {
			t.collapsed = !t.collapsed
		}
	}
	if t.collapsed {
		h = TRAY_TITLE
	}

	// The title bar drags it: by the pointer's travel, which holds however
	// the bar itself moves (see Event.travel). Kept inside the window.
	grip := claim_id(gtx, 2)
	for e in events(gtx, grip) {
		#partial switch e.kind {
		case .Press:
			t.dragging = true
		case .Release:
			t.dragging = false
		case .Move:
			if t.dragging {
				t.offset += e.travel
			}
		}
	}
	window := gtx.constraints.max
	corner := ops.Point{window.x - TRAY_WIDTH - 12, window.y - h - 12}
	at := corner + t.offset
	at = {clamp(at.x, 0, max(window.x - TRAY_WIDTH, 0)), clamp(at.y, 0, max(window.y - h, 0))}
	t.offset = at - corner // a drag past the edge does not bank distance to come back through

	// Top: over a modal's scrim and anything else, or it could not be used
	// to inspect them.
	o := overlay_open(gtx, at, exact({TRAY_WIDTH, h}), top = true)
	defer close(&o)
	t.rect = {at.x, at.y, TRAY_WIDTH, h}
	ops.fill(gtx.scene, ops.Round_Rect{{0, 0, TRAY_WIDTH, h}, 8}, ops.Color{24, 22, 30, 240})
	// Its own hit area, below the toggles: presses on the tray's padding
	// reach nothing under it.
	ops.input_area(gtx.scene, claim_id(gtx, 1), ops.Rect{0, 0, TRAY_WIDTH, h}, {.Press, .Release, .Move, .Scroll})
	// The title bar: a name and a grip, darker, to drag by.
	title := ops.Rect{0, 0, TRAY_WIDTH, TRAY_TITLE}
	title_color := ops.Color{40, 37, 50, 255}
	ops.fill(gtx.scene, ops.Round_Rect{title, 8}, title_color)
	ops.fill(gtx.scene, ops.Rect{0, TRAY_TITLE / 2, TRAY_WIDTH, TRAY_TITLE / 2}, title_color) // square lower corners, flush with the body
	tray_text(gtx, "Debug", {pad, TRAY_TITLE / 2 + 4}, 12, ops.Color{235, 233, 242, 255})
	tray_text(gtx, t.dragging ? "moving" : "drag to move", {TRAY_WIDTH - pad - 100, TRAY_TITLE / 2 + 4}, 11, ops.Color{150, 148, 162, 255})
	ops.input_area(gtx.scene, grip, title, {.Press, .Release, .Move, .Enter, .Leave})
	ops.tag(gtx.scene, grip, "Debug tray")
	fold_box := ops.Rect{TRAY_WIDTH - TRAY_TITLE, 0, TRAY_TITLE, TRAY_TITLE}
	tray_text(gtx, t.collapsed ? "+" : "−", {fold_box.x + 7, TRAY_TITLE / 2 + 4}, 12, ops.Color{235, 233, 242, 255})
	ops.input_area(gtx.scene, fold, fold_box, {.Press, .Release})
	ops.tag(gtx.scene, fold, t.collapsed ? "Expand tray" : "Collapse tray")
	if t.collapsed {
		return
	}

	y := TRAY_TITLE + pad
	for tg, i in TOGGLES {
		on := tg.flag in t.flags
		if tray_toggle(gtx, {pad, y, TRAY_WIDTH - 2 * pad, row}, tg.name, on, u64(10 + i)) {
			t.flags ~= {tg.flag}
		}
		y += row
	}
	if tray_toggle(gtx, {pad, y, TRAY_WIDTH - 2 * pad, row}, "Full frames (compositor damage off)", t.full_frames, 20) {
		t.full_frames = !t.full_frames
	}
	y += row
	// Off under full frames (see debug_tray_wants_flash), and shown so.
	if tray_toggle(gtx, {pad, y, TRAY_WIDTH - 2 * pad, row}, "Flash repaints", t.flash, 21, enabled = !t.full_frames) {
		t.flash = !t.flash
	}
	y += row + 6
	for l in lines {
		tray_text(gtx, l, {pad, y + text}, text, ops.Color{220, 218, 228, 255})
		y += text + 5
	}
	y += 6
	// Frame times, oldest to newest, against a 16.7 ms (60 Hz) line.
	gw := TRAY_WIDTH - 2 * pad
	ops.fill(gtx.scene, ops.Rect{pad, y, gw, graph_h}, ops.Color{40, 38, 48, 255})
	budget := f32(1000.0 / 60)
	top := budget * 2
	line_y := y + graph_h - graph_h * budget / top
	ops.fill(gtx.scene, ops.Rect{pad, line_y, gw, 1}, ops.Color{255, 170, 0, 160})
	bar := gw / TRAY_HISTORY
	for k in 0 ..< t.count {
		v := t.history[(t.head - t.count + k + TRAY_HISTORY) % TRAY_HISTORY]
		bh := min(v / top, 1) * graph_h
		c := v > budget * 1.05 ? ops.Color{255, 90, 90, 255} : ops.Color{120, 200, 140, 255} // a hair over, from rounding, is on time
		ops.fill(gtx.scene, ops.Rect{pad + f32(TRAY_HISTORY - t.count + k) * bar, y + graph_h - bh, max(bar - 0.5, 0.5), bh}, c)
	}
	// The event log, newest last, under the graph.
	y += graph_h + 8
	for l in log {
		tray_text(gtx, l, {pad, y + text - 2}, text - 1, ops.Color{180, 190, 230, 255})
		y += text + 3
	}
}

// tray_toggle draws a check and name in r and reports a click on it. A
// toggle that is not enabled is drawn dimmed, unchecked, and takes no
// input.
@(private = "file")
tray_toggle :: proc(gtx: ^Ctx, r: ops.Rect, name: string, on: bool, key: u64, enabled := true) -> bool {
	if !enabled {
		box := ops.Rect{r.x + 2, r.y + (r.h - 12) / 2, 12, 12}
		ops.stroke(gtx.scene, ops.Round_Rect{box, 3}, ops.Color{90, 88, 100, 255}, {width = 1})
		tray_text(gtx, name, {r.x + 22, r.y + (r.h + 12) / 2 - 1}, 12, ops.Color{120, 118, 130, 255})
		return false
	}
	id := claim_id(gtx, key)
	st := widget_state(gtx, id)
	clicked := click_from_events(gtx, id, st, r)
	if st.hovered {
		ops.fill(gtx.scene, ops.Round_Rect{r, 4}, ops.Color{255, 255, 255, 18})
	}
	box := ops.Rect{r.x + 2, r.y + (r.h - 12) / 2, 12, 12}
	if on {
		ops.fill(gtx.scene, ops.Round_Rect{box, 3}, ops.Color{120, 200, 140, 255})
	} else {
		ops.stroke(gtx.scene, ops.Round_Rect{box, 3}, ops.Color{160, 158, 170, 255}, {width = 1})
	}
	tray_text(gtx, name, {r.x + 22, r.y + (r.h + 12) / 2 - 1}, 12, ops.Color{235, 233, 242, 255})
	ops.input_area(gtx.scene, id, r, {.Press, .Release, .Enter, .Leave, .Move})
	ops.tag(gtx.scene, id, name)
	return clicked
}

// tray_text draws s with its baseline at pos, in the theme font.
@(private = "file")
tray_text :: proc(gtx: ^Ctx, s: string, pos: ops.Point, size: f32, c: ops.Color) {
	run := shape(gtx.shaper, gtx.font, size, s, gtx.allocator)
	ops.glyphs(gtx.scene, ops.add_run(gtx.scene, run), pos, c)
}
