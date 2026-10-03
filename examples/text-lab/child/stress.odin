package main

import "core:fmt"
import "core:math"
import "core:slice"
import "core:time"
import "jm:ui"
import "jm:ui/base"
import "jm:ui/fluent"

// The Stress page is a benchmark: how many paragraphs the lab can lay out
// and draw every frame and still present at 60 fps. Each paragraph wraps
// at a width that sways from frame to frame, so every frame reshapes,
// rewraps and repaints; nothing a cache or the damage tracker could skip.
//
// A run doubles the count while frames keep up, then bisects between the
// last count that kept up and the first that did not. A count keeps up
// when STRESS_PASS of its STRESS_FRAMES frames arrive within
// STRESS_BUDGET_MS of the one before. Frame time is Ctx.dt, the host's
// time between frames: the whole round trip of layout, flatten, encode,
// the pipe, rasterizing and present, not just the text code.

STRESS_BUDGET_MS :: f32(1000.0 / 60.0) * 1.1 // vsync jitter allowance
STRESS_FRAMES :: 60 // frames measured per count
STRESS_SETTLE :: 10 // frames dropped after the count changes
STRESS_PASS :: 0.95 // share of frames within budget for a count to pass
STRESS_MAX :: 1 << 16
STRESS_PREVIEW :: 32 // the count shown before any run
STRESS_STEPS :: 40

Stress_Phase :: enum {
	Idle,
	Ramp, // doubling until a count fails
	Search, // bisecting between lo (passed) and hi (failed)
	Done,
}

// Stress_Step is one count measured: its frame times and verdict.
Stress_Step :: struct {
	count:     int,
	glyphs:    int,
	median:    f32, // ms between frames
	p95:       f32,
	text_ms:   f32, // mean ms spent in paragraph_layout and paragraph_draw
	on_time:   f32, // share of frames within budget
	pass:      bool,
}

Stress :: struct {
	phase:   Stress_Phase,
	mixed:   bool, // every WRAPPED script in turn, not only Latin
	count:   int,
	lo, hi:  int,
	settle:  int,
	frames:  [STRESS_FRAMES]f32,
	text:    [STRESS_FRAMES]f32,
	n:       int,
	steps:   [STRESS_STEPS]Stress_Step,
	n_steps: int,
	glyphs:  int, // laid out last frame
	text_ms: f32, // last frame
	dt_ms:   f32, // smoothed, for the live readout
}

STRESS_PANEL :: 360 // the results panel's width
STRESS_COLUMNS := [?]f32{56, 64, 56, 64, 0}

// page_stress keeps the run's controls and live figures fixed above two
// panes: the counts measured so far, and the paragraphs themselves,
// scrolling to the window's edge.
page_stress :: proc(gtx: ^ui.Ctx, m: ^Model) {
	b := &m.stress
	if b.count == 0 {
		b.count = STRESS_PREVIEW
	}
	if stress_running(b) {
		stress_measure(b, gtx.dt)
		ui.request_frame(gtx)
	}
	col := ui.column_open(gtx, align = .Fill)
	defer ui.close(&col)
	{
		head := ui.inset_open(gtx, {24, 0, 24, 16})
		defer ui.close(&head)
		hc := ui.column_open(gtx, gap = 16)
		defer ui.close(&hc)
		note(gtx, "Paragraphs laid out and drawn every frame, rewrapping as their width sways. Run finds the most that hold 60 fps.")
		stress_controls(gtx, m)
		stress_metrics(gtx, b)
	}
	fluent.divider(gtx)
	ui.flexible(gtx, 1)
	panes := ui.row_open(gtx, align = .Fill)
	defer ui.close(&panes)
	{
		side := ui.sized_open(gtx, {min = {STRESS_PANEL, 0}, max = {STRESS_PANEL, 0}})
		defer ui.close(&side)
		sb := ui.scroll_box_open(gtx)
		defer ui.close(&sb)
		pad := ui.inset_open(gtx, {24, 16, 16, 24})
		defer ui.close(&pad)
		stress_results(gtx, b)
	}
	fluent.divider(gtx, vertical = true)
	ui.flexible(gtx, 1)
	sb := ui.scroll_box_open(gtx)
	defer ui.close(&sb)
	pad := ui.inset_open(gtx, {24, 16, 24, 48})
	defer ui.close(&pad)
	stress_tiles(gtx, m)
}

stress_running :: proc(b: ^Stress) -> bool {
	return b.phase == .Ramp || b.phase == .Search
}

// stress_controls is Run or Stop, the sample switch and where the run is.
stress_controls :: proc(gtx: ^ui.Ctx, m: ^Model) {
	b := &m.stress
	s := fluent.scheme()
	r := ui.row_open(gtx, gap = 8, align = .Center)
	defer ui.close(&r)
	running := stress_running(b)
	if fluent.button(gtx, "Stop" if running else "Run", .Primary) {
		if running {
			b.phase = .Idle
		} else {
			stress_start(b)
		}
	}
	fluent.toggle_switch(gtx, &b.mixed, "Mixed scripts", state = .Disabled if running else .Live)
	ui.spacer(gtx, 8)
	status: string
	switch b.phase {
	case .Idle:
		status = "Stopped." if b.n_steps > 0 else "Not run yet."
	case .Ramp:
		status = fmt.tprintf("Doubling: measuring %d paragraphs", b.count)
	case .Search:
		status = fmt.tprintf("Narrowing between %d and %d: measuring %d", b.lo, b.hi, b.count)
	case .Done:
		status = stress_verdict(b, m.size)
	}
	if running {
		fluent.spinner(gtx, size = .Tiny)
	}
	color := s[.Neutral_Foreground1] if b.phase == .Done else s[.Neutral_Foreground2]
	base.label(gtx, status, {size = 14, color = color})
}

// stress_verdict is a finished run's answer, from the best count that passed.
stress_verdict :: proc(b: ^Stress, size: int) -> string {
	best := Stress_Step{}
	for st in b.steps[:b.n_steps] {
		if st.pass && st.count > best.count {
			best = st
		}
	}
	if best.count == 0 {
		return "Misses 60 fps even at one paragraph."
	}
	return fmt.tprintf("Holds 60 fps up to %d paragraphs (%d glyphs) of %s at %.0fpx.", best.count, best.glyphs, "mixed scripts" if b.mixed else "Latin", SIZES[size])
}

// stress_metrics are the live figures for the frame just drawn.
stress_metrics :: proc(gtx: ^ui.Ctx, b: ^Stress) {
	r := ui.row_open(gtx, gap = 40)
	defer ui.close(&r)
	stress_metric(gtx, "Paragraphs", fmt.tprint(b.count))
	stress_metric(gtx, "Glyphs a frame", fmt.tprint(b.glyphs))
	stress_metric(gtx, "Layout and draw", fmt.tprintf("%.2f ms", b.text_ms))
	frame := "—"
	if stress_running(b) && b.dt_ms > 0 {
		frame = fmt.tprintf("%.1f ms · %.0f fps", b.dt_ms, 1000 / b.dt_ms)
	}
	stress_metric(gtx, "Frame", frame)
}

stress_metric :: proc(gtx: ^ui.Ctx, label, value: string, loc := #caller_location) {
	s := fluent.scheme()
	c := ui.column_open(gtx, gap = 2, loc = loc)
	defer ui.close(&c)
	base.label(gtx, label, {size = 12, color = s[.Neutral_Foreground3]})
	base.label(gtx, value, {size = 20, color = s[.Neutral_Foreground1]})
}

// stress_results is every count measured, in the order measured.
stress_results :: proc(gtx: ^ui.Ctx, b: ^Stress) {
	s := fluent.scheme()
	col := ui.column_open(gtx, gap = 8, align = .Fill)
	defer ui.close(&col)
	base.label(gtx, "Measured", {size = 14, color = s[.Neutral_Foreground1]})
	if b.n_steps == 0 {
		base.label(gtx, "Each count a run tries shows here.", {size = 12, color = s[.Neutral_Foreground3]})
		return
	}
	t := fluent.table_open(gtx, STRESS_COLUMNS[:], .Extra_Small)
	defer fluent.table_close(&t)
	{
		h := fluent.table_header_open(gtx, &t)
		defer fluent.table_header_close(&h)
		for name, i in ([]string{"Count", "Glyphs", "p95 ms", "Text ms", "Result"}) {
			fluent.table_cell(gtx, &h, name, s[.Neutral_Foreground2], key = u64(i))
		}
	}
	for st, i in b.steps[:b.n_steps] {
		row := fluent.table_row_open(gtx, &t, interactive = false, key = u64(i))
		fluent.table_cell(gtx, &row, fmt.tprint(st.count))
		fluent.table_cell(gtx, &row, fmt.tprint(st.glyphs))
		fluent.table_cell(gtx, &row, fmt.tprintf("%.1f", st.p95))
		fluent.table_cell(gtx, &row, fmt.tprintf("%.2f", st.text_ms))
		verdict := fmt.tprintf("pass %.0f%%" if st.pass else "miss %.0f%%", st.on_time * 100)
		fluent.table_cell(gtx, &row, verdict, s[.Status_Success_Foreground1] if st.pass else s[.Status_Danger_Foreground1])
		fluent.table_row_close(&row)
	}
}

// stress_tiles lays out and draws b.count paragraphs, timing just that.
stress_tiles :: proc(gtx: ^ui.Ctx, m: ^Model) {
	b := &m.stress
	s := fluent.scheme()
	size := SIZES[m.size]
	tile := max(360, size * 20)
	sway := f32(0) if b.phase == .Idle || b.phase == .Done else f32(gtx.time)
	w := ui.wrap_open(gtx, gap = 16)
	defer ui.close(&w)
	glyphs := 0
	text_time: time.Duration
	for i in 0 ..< b.count {
		sm := WRAPPED[i % len(WRAPPED)] if b.mixed else WRAPPED[0]
		width := tile * (0.8 + 0.1 * (1 + math.sin(sway * 2 + f32(i) * 0.7)))
		start := time.tick_now()
		p := ui.paragraph_layout(gtx.shaper, m.font[sm.script], size, sm.text, width, gtx.allocator)
		pl := ui.widget_open(gtx, u64(i))
		ui.paragraph_draw(gtx.scene, p, {}, s[.Neutral_Foreground1])
		text_time += time.tick_since(start)
		ui.widget_close(gtx, &pl, {{tile, p.height}, p.metrics.ascent})
		for ln in p.lines {
			for r in ln.runs {
				glyphs += len(r.glyphs.glyphs)
			}
		}
	}
	b.glyphs = glyphs
	b.text_ms = f32(time.duration_milliseconds(text_time))
}

stress_start :: proc(b: ^Stress) {
	b.phase = .Ramp
	b.count = 1
	b.n_steps = 0
	b.n = 0
	b.settle = STRESS_SETTLE
}

// stress_measure records this frame's time against the count drawn last
// frame and, once STRESS_FRAMES are in, judges the count and picks the next.
stress_measure :: proc(b: ^Stress, dt: f32) {
	ms := dt * 1000
	b.dt_ms = ms if b.dt_ms == 0 else b.dt_ms * 0.9 + ms * 0.1
	if b.settle > 0 {
		b.settle -= 1
		return
	}
	b.frames[b.n] = ms
	b.text[b.n] = b.text_ms
	b.n += 1
	if b.n < STRESS_FRAMES {
		return
	}
	st := stress_judge(b)
	if b.n_steps < STRESS_STEPS {
		b.steps[b.n_steps] = st
		b.n_steps += 1
	}
	fmt.eprintfln("stress: %d paragraphs, %d glyphs: median %.2f ms, p95 %.2f ms, text %.2f ms, %.0f%% on time, %s", st.count, st.glyphs, st.median, st.p95, st.text_ms, st.on_time * 100, "pass" if st.pass else "miss")
	stress_next(b, st.pass)
	if b.phase == .Done {
		fmt.eprintfln("stress: holds 60 fps up to %d paragraphs", b.count if b.lo > 0 else 0)
	}
	b.n = 0
	b.settle = STRESS_SETTLE
}

stress_judge :: proc(b: ^Stress) -> Stress_Step {
	sorted := b.frames
	slice.sort(sorted[:])
	on_time := 0
	for f in sorted {
		if f <= STRESS_BUDGET_MS {
			on_time += 1
		}
	}
	share := f32(on_time) / STRESS_FRAMES
	return {
		count = b.count,
		glyphs = b.glyphs,
		median = sorted[STRESS_FRAMES / 2],
		p95 = sorted[STRESS_FRAMES * 95 / 100],
		text_ms = math.sum(b.text[:]) / STRESS_FRAMES,
		on_time = share,
		pass = share >= STRESS_PASS,
	}
}

// stress_next moves the run on from a count that passed or failed: double
// while ramping, halve the gap while searching, stop within 2%.
stress_next :: proc(b: ^Stress, pass: bool) {
	switch b.phase {
	case .Ramp:
		if !pass {
			b.lo, b.hi = b.count / 2, b.count
			b.phase = .Search
		} else if b.count >= STRESS_MAX {
			b.lo, b.hi = b.count, b.count
		} else {
			b.count *= 2
			return
		}
	case .Search:
		if pass {
			b.lo = b.count
		} else {
			b.hi = b.count
		}
	case .Idle, .Done:
		return
	}
	if b.hi - b.lo <= max(1, b.lo / 50) || b.lo == 0 {
		b.phase = .Done
		b.count = max(b.lo, 1)
		return
	}
	b.count = (b.lo + b.hi) / 2
}

// stress_abandon stops a run when its page is not the one shown: its
// frames would measure the wrong work.
stress_abandon :: proc(m: ^Model) {
	if PAGES[m.page].draw != page_stress && stress_running(&m.stress) {
		m.stress.phase = .Idle
	}
}
