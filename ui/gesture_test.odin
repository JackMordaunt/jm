package ui

import "core:math"
import "core:testing"
import "jm:ui/ops"
import "jm:ui/testutil"

@(private = "file")
FRAME :: 1.0 / 60

@(private = "file")
track :: proc(v: ^Velocity_Tracker, pos: proc(t: f64) -> ops.Point, n: int) -> f64 {
	t: f64
	for i in 0 ..< n {
		t = 1 + f64(i) * FRAME
		velocity_add(v, t, pos(t))
	}
	return t
}

@(test)
velocity_of_a_steady_pointer_is_its_speed :: proc(t: ^testing.T) {
	v: Velocity_Tracker
	now := track(&v, proc(t: f64) -> ops.Point {return {f32(300 * t), f32(-120 * t)}}, 8)
	got := velocity_estimate(&v, now)
	testing.expectf(t, testutil.near(got.x, 300, 0.5) && testutil.near(got.y, -120, 0.5), "got %v", got)
}

@(test)
velocity_of_an_accelerating_pointer_is_its_latest :: proc(t: ^testing.T) {
	// x = 2000 (t-1)²: the speed at the newest sample is 4000 (t-1).
	v: Velocity_Tracker
	now := track(&v, proc(t: f64) -> ops.Point {return {f32(2000 * (t - 1) * (t - 1)), 0}}, 6)
	got := velocity_estimate(&v, now)
	testing.expectf(t, testutil.near(got.x, f32(4000 * (now - 1)), 1), "got %v, want %v", got.x, 4000 * (now - 1))
}

@(test)
velocity_is_zero_once_the_pointer_paused :: proc(t: ^testing.T) {
	v: Velocity_Tracker
	now := track(&v, proc(t: f64) -> ops.Point {return {f32(300 * t), 0}}, 8)
	testing.expect(t, velocity_estimate(&v, now + VELOCITY_GAP / 2).x > 250)
	testing.expect_value(t, velocity_estimate(&v, now + VELOCITY_GAP * 1.5), ops.Point{})
}

@(test)
velocity_forgets_samples_older_than_its_window :: proc(t: ^testing.T) {
	// Fast for a second, then slow for the last 0.1 s: only the slow counts.
	v: Velocity_Tracker
	at: f64 = 1
	pos: f32
	for _ in 0 ..< 60 {
		velocity_add(&v, at, {pos, 0})
		at += FRAME
		pos += 5000 * FRAME
	}
	for _ in 0 ..< 8 {
		velocity_add(&v, at, {pos, 0})
		at += FRAME
		pos += 100 * FRAME
	}
	got := velocity_estimate(&v, at - FRAME)
	testing.expectf(t, testutil.near(got.x, 100, 1), "got %v", got.x)
}

@(test)
velocity_needs_three_distinct_times :: proc(t: ^testing.T) {
	v: Velocity_Tracker
	testing.expect_value(t, velocity_estimate(&v, 1), ops.Point{})
	velocity_add(&v, 1, {0, 0})
	velocity_add(&v, 1 + FRAME, {10, 0})
	testing.expect_value(t, velocity_estimate(&v, 1 + FRAME), ops.Point{})
	// A third sample is enough: 10 px a frame is 600 px/s.
	velocity_add(&v, 1 + 2 * FRAME, {20, 0})
	testing.expect(t, testutil.near(velocity_estimate(&v, 1 + 2 * FRAME).x, 600, 0.5))
	// Events with no times (all 0) cannot give one either.
	velocity_reset(&v)
	for i in 0 ..< 5 {
		velocity_add(&v, 0, {f32(i) * 10, 0})
	}
	testing.expect_value(t, velocity_estimate(&v, 0), ops.Point{})
}

@(private = "file")
press :: proc(at: f64) -> Event {
	return {kind = .Press, button = .Left, time = at}
}

@(private = "file")
move :: proc(travel: ops.Point, at: f64) -> Event {
	return {kind = .Move, travel = travel, time = at}
}

@(private = "file")
release :: proc(at: f64) -> Event {
	return {kind = .Release, button = .Left, time = at}
}

@(test)
drag_within_the_slop_is_a_tap :: proc(t: ^testing.T) {
	d: Drag
	drag_update(&d, {press(1), move({2, 0}, 1 + FRAME)})
	testing.expect_value(t, d.phase, Drag_Phase.Pressed)
	testing.expect_value(t, d.delta, ops.Point{})
	drag_update(&d, {release(1 + 2 * FRAME)})
	testing.expect(t, d.tapped && !d.released)
	testing.expect_value(t, d.phase, Drag_Phase.Idle)
}

@(test)
drag_past_the_slop_moves_and_releases_with_its_velocity :: proc(t: ^testing.T) {
	d: Drag
	drag_update(&d, {press(1)})
	// The first move passes the slop: all of its travel lands at once.
	drag_update(&d, {move({0, 10}, 1 + FRAME)})
	testing.expect_value(t, d.phase, Drag_Phase.Dragging)
	testing.expect_value(t, d.delta, ops.Point{0, 10})
	// Two moves in one frame both count.
	drag_update(&d, {move({0, 5}, 1 + 1.5 * FRAME), move({0, 5}, 1 + 2 * FRAME)})
	testing.expect_value(t, d.delta, ops.Point{0, 10})
	testing.expect_value(t, d.total, ops.Point{0, 20})
	drag_update(&d, {move({0, 10}, 1 + 3 * FRAME), release(1 + 3 * FRAME)})
	testing.expect(t, d.released && !d.tapped)
	testing.expectf(t, testutil.near(d.velocity.y, 600, 1) && d.velocity.x == 0, "velocity %v", d.velocity)
}

@(test)
drag_on_an_axis_ignores_the_other :: proc(t: ^testing.T) {
	d: Drag
	drag_update(&d, {press(1), move({40, 1}, 1 + FRAME)}, .Vertical)
	testing.expect_value(t, d.phase, Drag_Phase.Pressed) // sideways travel is not past the slop
	drag_update(&d, {move({40, 5}, 1 + 2 * FRAME)}, .Vertical)
	testing.expect_value(t, d.phase, Drag_Phase.Dragging)
	testing.expect_value(t, d.delta, ops.Point{0, 6})
}

@(test)
drag_ignores_other_buttons_and_drops_on_cancel :: proc(t: ^testing.T) {
	d: Drag
	drag_update(&d, {{kind = .Press, button = .Right, time = 1}, move({0, 20}, 1 + FRAME)})
	testing.expect_value(t, d.phase, Drag_Phase.Idle)
	testing.expect_value(t, d.total, ops.Point{})
	// The same moves after a left press do drag, so the right one was refused.
	drag_update(&d, {press(2), move({0, 20}, 2 + FRAME), move({0, 20}, 2 + 2 * FRAME)})
	testing.expect_value(t, d.phase, Drag_Phase.Dragging)
	drag_update(&d, {move({0, 20}, 2 + 3 * FRAME)})
	testing.expect(t, d.velocity.y > 0)
	drag_update(&d, {{kind = .Cancel, time = 2 + 4 * FRAME}})
	testing.expect_value(t, d.phase, Drag_Phase.Idle)
	testing.expect(t, !d.released && !d.tapped)
	testing.expect_value(t, d.velocity, ops.Point{})
}

@(test)
sling_glides_its_whole_distance_and_stops :: proc(t: ^testing.T) {
	s: Sling
	testing.expect(t, !sling_start(&s, {0, SLING_MIN / 2}, 0))
	testing.expect(t, sling_start(&s, {0, 1000}, 10))
	// v0 (e^(kt) - 1) / k goes to -v0 / k.
	want := -1000 / SLING_DECAY
	sum: ops.Point
	now := f64(10)
	frames := 0
	for {
		now += FRAME
		travel, moving := sling_step(&s, now)
		sum += travel
		frames += 1
		if !moving {
			break
		}
		testing.expect(t, frames < 60 * 10)
	}
	testing.expectf(t, testutil.near(sum.y, want, 1) && sum.x == 0, "slid %v, want %v", sum, want)
	testing.expect(t, !sling_active(&s))
	travel, moving := sling_step(&s, now + 1)
	testing.expect(t, travel == {} && !moving)
}

@(test)
sling_caps_its_speed :: proc(t: ^testing.T) {
	s: Sling
	testing.expect(t, sling_start(&s, {3 * SLING_MAX, 4 * SLING_MAX}, 0))
	testing.expect(t, testutil.near(math.sqrt(s.v0.x * s.v0.x + s.v0.y * s.v0.y), SLING_MAX))
	sling_stop(&s)
	testing.expect(t, !sling_active(&s))
}

// Fling_Model is a handle a probe drags through ui.drag, the seam a widget
// uses: the router's events, their times from the probe's clock.
@(private = "file")
Fling_Model :: struct {
	moved:    ops.Point,
	released: bool,
	velocity: ops.Point,
}

@(private = "file")
fling_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Fling_Model)(user)
	p := widget_open(gtx, 1)
	ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 50, 50}, {.Press, .Move, .Release})
	ops.tag(gtx.scene, p.id, "handle")
	d := drag(gtx, p.id)
	m.moved += d.delta
	if d.released {
		m.released, m.velocity = true, d.velocity
	}
	widget_close(gtx, &p, {size = {50, 50}})
}

@(test)
drag_through_the_router_carries_the_probe_clock :: proc(t: ^testing.T) {
	m: Fling_Model
	p: Probe
	probe_init(&p, fling_view, &m, {400, 400})
	defer probe_destroy(&p)
	// 200 px in four moves a frame apart: 50 px per 1/60 s.
	testing.expect(t, probe_drag(&p, "handle", 0, 200, steps = 4))
	testing.expect(t, m.released)
	testing.expect_value(t, m.moved, ops.Point{0, 200})
	testing.expectf(t, testutil.near(m.velocity.y, 3000, 5), "velocity %v", m.velocity)
}
