package material

import "core:testing"
import "jm:ui/ops"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Behaviour of the sliders, progress indicators and loading indicator,
// driven through ui.Probe, plus the pure motion helpers they share.

// SLIDER_W is the test sliders' length: the track then spans 2..238, so a
// fraction f of the range sits at 2 + 236 f.
@(private = "file")
SLIDER_W :: 240

@(private = "file")
track_x :: proc(f: f32) -> f32 {
	half := tok.SLIDER_HANDLE_WIDTH / 2
	return half + f * (SLIDER_W - 2 * half)
}

@(private = "file")
press_at :: proc(p: ^ui.Probe, pos: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = pos})
	ui.router_push(&p.router, {kind = .Press, pos = pos, button = .Left})
	ui.probe_frame(p)
}

@(private = "file")
drag_to :: proc(p: ^ui.Probe, pos: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = pos})
	ui.probe_frame(p)
}

@(private = "file")
release_at :: proc(p: ^ui.Probe, pos: ops.Point) {
	ui.router_push(&p.router, {kind = .Release, pos = pos, button = .Left})
	ui.probe_frame(p)
}

@(private = "file")
Slider_Model :: struct {
	v, lo, hi: f32,
	step:      f32,
	vertical:  bool,
	range:     bool,
}

@(private = "file")
slider_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Slider_Model)(user)
	col := ui.column_open(gtx) // the root is the whole window; a column lets the slider take its own size
	defer ui.close(&col)
	if m.range {
		range_slider(gtx, &m.lo, &m.hi, 0, 100, m.step, width = SLIDER_W)
		return
	}
	slider(gtx, &m.v, 0, 100, m.step, width = SLIDER_W, vertical = m.vertical, top_to_bottom = false)
}

@(test)
test_stepped_slider_snaps_on_every_move_of_a_drag :: proc(t: ^testing.T) {
	m := Slider_Model{step = 10}
	p: ui.Probe
	ui.probe_init(&p, slider_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	press_at(&p, {track_x(0.33), 24})
	testing.expect_value(t, m.v, 30)
	// Mid-drag, before any release, the value is already on a stop.
	drag_to(&p, {track_x(0.47), 24})
	testing.expect_value(t, m.v, 50)
	drag_to(&p, {track_x(0.64), 40})
	testing.expect_value(t, m.v, 60)
	release_at(&p, {track_x(0.64), 40})
	testing.expect_value(t, m.v, 60)
}

@(test)
test_slider_keys_step_page_and_jump :: proc(t: ^testing.T) {
	m := Slider_Model{}
	p: ui.Probe
	ui.probe_init(&p, slider_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "slider"))
	testing.expect_value(t, m.v, 50)
	// Continuous: an arrow is 1% of the range, a page 10%.
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.v, 51)
	ui.probe_key(&p, .Page_Down)
	testing.expect_value(t, m.v, 41)
	ui.probe_key(&p, .Home)
	testing.expect_value(t, m.v, 0)
	ui.probe_key(&p, .Down) // clamps at the minimum
	testing.expect_value(t, m.v, 0)
	ui.probe_key(&p, .End)
	testing.expect_value(t, m.v, 100)

	// Stepped with 10 intervals: a page is one tenth of them, one step.
	m.step = 10
	ui.probe_key(&p, .Page_Down)
	testing.expect_value(t, m.v, 90)
	ui.probe_key(&p, .Left)
	testing.expect_value(t, m.v, 80)
}

@(test)
test_bottom_to_top_slider_reads_from_the_bottom :: proc(t: ^testing.T) {
	m := Slider_Model{vertical = true}
	p: ui.Probe
	ui.probe_init(&p, slider_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// The low end is at the bottom: a press a quarter of the way up.
	press_at(&p, {24, SLIDER_W - track_x(0.25)})
	testing.expect_value(t, m.v, 25)
	release_at(&p, {24, SLIDER_W - track_x(0.25)})
}

@(test)
test_range_slider_takes_the_nearer_handle_and_never_crosses :: proc(t: ^testing.T) {
	m := Slider_Model{lo = 20, hi = 70, range = true}
	p: ui.Probe
	ui.probe_init(&p, slider_view, &m, {400, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	press_at(&p, {track_x(0.8), 24})
	release_at(&p, {track_x(0.8), 24})
	testing.expect_value(t, m.hi, 80)
	testing.expect_value(t, m.lo, 20)
	// Tab hands the keys to the low handle, which stops at the high one.
	ui.probe_key(&p, .Tab)
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.lo, 21)
	ui.probe_key(&p, .End)
	testing.expect_value(t, m.lo, 80)
	testing.expect_value(t, m.hi, 80)
	// Dragging the low handle past the high one leaves it at the high one.
	press_at(&p, {track_x(0.1), 24})
	testing.expect_value(t, m.lo, 10)
	drag_to(&p, {track_x(0.95), 24})
	testing.expect_value(t, m.lo, 80)
	testing.expect_value(t, m.hi, 80)
	release_at(&p, {track_x(0.95), 24})
}

@(test)
test_indicators_animate_only_when_indeterminate_or_live :: proc(t: ^testing.T) {
	Mode :: enum {
		Determinate,
		Indeterminate,
		Frozen,
		Loading,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx)
		defer ui.close(&col)
		switch (^Mode)(user)^ {
		case .Determinate:
			linear_progress(gtx, 0.5)
			circular_progress(gtx, 0.5)
			loading_indicator(gtx, progress = 0.5)
		case .Indeterminate:
			circular_progress(gtx, -1)
		case .Frozen:
			linear_progress(gtx, -1, at = 0.5)
			circular_progress(gtx, -1, style = .Wavy, at = 2)
			loading_indicator(gtx, at = 1)
		case .Loading:
			loading_indicator(gtx)
		}
	}
	for mode in Mode {
		m := mode
		p: ui.Probe
		ui.probe_init(&p, view, &m, {400, 300}, allocator = context.temp_allocator)
		ui.probe_frame(&p)
		want := mode == .Indeterminate || mode == .Loading
		testing.expectf(t, p.wants_frame == want, "%v: wants_frame %v", mode, p.wants_frame)
		ui.probe_destroy(&p)
	}
	free_all(context.temp_allocator)
}

@(test)
test_morph_spring_overshoots_then_settles_within_a_morph :: proc(t: ^testing.T) {
	testing.expect_value(t, morph_spring(0), 0)
	peak: f32
	for i in 0 ..< 65 {
		peak = max(peak, morph_spring(f32(i) * 0.01))
	}
	testing.expect(t, peak > 1) // damping 0.6 overshoots
	testing.expect_value(t, morph_spring(0.649), 1) // settled before the next morph starts
}

@(test)
test_bezier_ease_solves_css_curves :: proc(t: ^testing.T) {
	near :: proc(a, b: f32) -> bool {
		return abs(a - b) < 1e-3
	}
	testing.expect(t, near(bezier_ease(tok.SYS_MOTION_EASING_LINEAR, 0.3), 0.3))
	testing.expect_value(t, bezier_ease(tok.SYS_MOTION_EASING_LINEAR, 0), 0)
	testing.expect_value(t, bezier_ease(tok.SYS_MOTION_EASING_LINEAR, 1), 1)
	// Emphasized-accelerate starts slow: well under halfway at the midpoint.
	testing.expect(t, bezier_ease(tok.SYS_MOTION_EASING_EMPHASIZED_ACCELERATE, 0.5) < 0.3)
}

@(test)
test_circular_indeterminate_follows_its_keyframes :: proc(t: ^testing.T) {
	near :: proc(a, b: f32) -> bool {
		return abs(a - b) < 1e-2
	}
	rot, sweep := circular_indeterminate(0)
	testing.expect(t, near(rot, 0) && near(sweep, 0.1))
	// At 3s: half the 1080° turn, two 90° steps done, the sweep at its max.
	rot, sweep = circular_indeterminate(3)
	testing.expect(t, near(rot, 540 + 180))
	testing.expect(t, near(sweep, 0.87))
	// The loop wraps at 6s.
	rot, sweep = circular_indeterminate(6)
	testing.expect(t, near(rot, 0) && near(sweep, 0.1))
}
