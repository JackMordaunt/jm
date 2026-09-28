package ui

import "core:fmt"
import "core:strings"
import "core:time"

// Frame_Stats is what a frame loop measured of one frame: for the debug
// tray, and for -stats in a headless session.
Frame_Stats :: struct {
	frame:       u64,
	dt:          f32, // seconds since the frame before
	ui_ms:       f32, // the app's ui proc: layout and recording
	build_ms:    f32, // flattening, and encoding for the host when there is one
	ops:         int,
	draws:       int,
	hits:        int,
	boxes:       int, // Debug_Box records, under Debug_Flag.Inspect
	states:      int, // retained Widget_States
	data:        int, // retained widget_data values
	arena_bytes: int, // the frame arena's allocations this frame
	rss_bytes:   int, // the process's resident memory, or -1 where not read
}

// TRAY_HISTORY is how many frames the tray's frame-time graph shows.
TRAY_HISTORY :: 120

// Debug_Tray is a frame loop's debug panel: DEBUG_TOGGLE_KEY opens and
// closes it, its toggles set the debug flags, and it shows the loop's
// Frame_Stats. The loop owns it; the app never sees it.
Debug_Tray :: struct {
	open:        bool,
	flags:       Debug_Flags, // what the toggles set while open
	full_frames: bool, // the compositor redraws every frame whole, damage tracking off
	last:        Frame_Stats,
	history:     [TRAY_HISTORY]f32, // frame times in ms, newest at head - 1
	head:        int,
	count:       int,
	rect:        Rect, // where it was drawn last, in the ui's own units, so the inspector can skip it
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

// debug_tray_record stores s as t's latest stats and its frame time in the
// graph.
debug_tray_record :: proc(t: ^Debug_Tray, s: Frame_Stats) {
	t.last = s
	t.history[t.head] = s.dt * 1000
	t.head = (t.head + 1) % TRAY_HISTORY
	t.count = min(t.count + 1, TRAY_HISTORY)
}

// frame_stats gathers what gtx's frame left in its ops, layout and frame
// f, with the loop's timings and arena use.
frame_stats :: proc(gtx: ^Ctx, f: ^Frame, ui_ms, build_ms: f32, arena_bytes: int) -> Frame_Stats {
	s := Frame_Stats {
		frame       = gtx.frame,
		dt          = gtx.dt,
		ui_ms       = ui_ms,
		build_ms    = build_ms,
		ops         = len(gtx.ops.ops),
		arena_bytes = arena_bytes,
		rss_bytes   = process_rss(),
	}
	if f != nil {
		s.draws, s.hits, s.boxes = len(f.draws), len(f.hits), len(f.boxes)
	}
	if l := gtx.layout; l != nil {
		s.states, s.data = len(l.state), len(l.data)
	}
	return s
}

// debug_inspect paints the inspector for device point p when flags ask for
// it and p is not over the open tray t (which it would otherwise inspect).
// density is the display scale; call it outside the scale transform.
debug_inspect :: proc(gtx: ^Ctx, flags: Debug_Flags, t: ^Debug_Tray, prev: ^Frame, p: Point, density: f32) {
	if .Inspect not_in flags || prev == nil {
		return
	}
	if t.open && rect_contains(t.rect, p / density) {
		return
	}
	paint_inspector(gtx, prev, p, density)
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
	append(&lines, fmt.aprintf("ops %d   draws %d   hits %d   boxes %d", s.ops, s.draws, s.hits, s.boxes, allocator = allocator))
	append(&lines, fmt.aprintf("widget state %d   widget data %d", s.states, s.data, allocator = allocator))
	rss := s.rss_bytes >= 0 ? fmt.tprintf("%.1f MiB", f64(s.rss_bytes) / (1 << 20)) : "n/a"
	append(&lines, fmt.aprintf("frame arena %.1f KiB   resident %s", f64(s.arena_bytes) / 1024, rss, allocator = allocator))
	return lines[:]
}

// TRAY_WIDTH fits the longest toggle label at 12sp with its check.
TRAY_WIDTH :: f32(300)

// debug_tray draws t, when open, in the window's bottom-right corner above
// everything: a toggle a line for each debug switch, then the latest stats
// and a graph of recent frame times. It is laid out with debug flags off,
// so it neither outlines nor inspects itself. The frame loops call it
// after the app's ui, under the display scale.
debug_tray :: proc(gtx: ^Ctx, t: ^Debug_Tray) {
	if !t.open {
		return
	}
	saved, saved_ops := gtx.debug, gtx.ops.debug
	gtx.debug, gtx.ops.debug = {}, {}
	defer gtx.debug, gtx.ops.debug = saved, saved_ops

	TOGGLES :: [?]struct {
		flag: Debug_Flag,
		name: string,
	}{{.Bounds, "Outline widgets and input areas"}, {.Inspect, "Inspect under the pointer"}, {.Reveal, "Reveal hidden parts"}, {.Slow, "Slow motion (quarter speed)"}}
	pad, row, text :: f32(10), f32(22), f32(12)
	lines := stats_lines(t.last, gtx.allocator)
	graph_h :: f32(36)
	h := 2 * pad + row * f32(len(TOGGLES) + 1) + 6 + f32(len(lines)) * (text + 5) + 6 + graph_h
	window := gtx.constraints.max
	at := Point{max(window.x - TRAY_WIDTH - 12, 0), max(window.y - h - 12, 0)}
	o := overlay(gtx, at, exact({TRAY_WIDTH, h}))
	defer end(&o)
	t.rect = {at.x, at.y, TRAY_WIDTH, h}
	fill(gtx.ops, Round_Rect{{0, 0, TRAY_WIDTH, h}, 8}, Color{24, 22, 30, 240})
	// Its own hit area, below the toggles: presses on the tray's padding
	// reach nothing under it.
	input_area(gtx.ops, scoped_id(gtx, 1), Rect{0, 0, TRAY_WIDTH, h}, {.Press, .Release, .Move, .Scroll})

	y := pad
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
	y += row + 6
	for l in lines {
		tray_text(gtx, l, {pad, y + text}, text, Color{220, 218, 228, 255})
		y += text + 5
	}
	y += 6
	// Frame times, oldest to newest, against a 16.7 ms (60 Hz) line.
	gw := TRAY_WIDTH - 2 * pad
	fill(gtx.ops, Rect{pad, y, gw, graph_h}, Color{40, 38, 48, 255})
	budget := f32(1000.0 / 60)
	top := budget * 2
	line_y := y + graph_h - graph_h * budget / top
	fill(gtx.ops, Rect{pad, line_y, gw, 1}, Color{255, 170, 0, 160})
	bar := gw / TRAY_HISTORY
	for k in 0 ..< t.count {
		v := t.history[(t.head - t.count + k + TRAY_HISTORY) % TRAY_HISTORY]
		bh := min(v / top, 1) * graph_h
		c := v > budget * 1.05 ? Color{255, 90, 90, 255} : Color{120, 200, 140, 255} // a hair over, from rounding, is on time
		fill(gtx.ops, Rect{pad + f32(TRAY_HISTORY - t.count + k) * bar, y + graph_h - bh, max(bar - 0.5, 0.5), bh}, c)
	}
}

// tray_toggle draws a check and name in r and reports a click on it.
@(private = "file")
tray_toggle :: proc(gtx: ^Ctx, r: Rect, name: string, on: bool, key: u64) -> bool {
	id := scoped_id(gtx, key)
	st := widget_state(gtx, id)
	clicked := click_from_events(gtx, id, st, r)
	if st.hovered {
		fill(gtx.ops, Round_Rect{r, 4}, Color{255, 255, 255, 18})
	}
	box := Rect{r.x + 2, r.y + (r.h - 12) / 2, 12, 12}
	if on {
		fill(gtx.ops, Round_Rect{box, 3}, Color{120, 200, 140, 255})
	} else {
		stroke(gtx.ops, Round_Rect{box, 3}, Color{160, 158, 170, 255}, {width = 1})
	}
	tray_text(gtx, name, {r.x + 22, r.y + (r.h + 12) / 2 - 1}, 12, Color{235, 233, 242, 255})
	input_area(gtx.ops, id, r, {.Press, .Release, .Enter, .Leave, .Move})
	tag(gtx.ops, id, name)
	return clicked
}

// tray_text draws s with its baseline at pos, in the theme font.
@(private = "file")
tray_text :: proc(gtx: ^Ctx, s: string, pos: Point, size: f32, c: Color) {
	run := shape(gtx.shaper, gtx.theme.font, size, s, gtx.allocator)
	glyphs(gtx.ops, add_run(gtx.ops, run), pos, c)
}
