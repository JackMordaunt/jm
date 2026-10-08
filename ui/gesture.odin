package ui

import "core:math/linalg"
import "jm:ui/ops"

// Drag gestures: a press that moves past a slop, the travel that follows,
// and the pointer's velocity when it lets go, for a sling (sling.odin) to
// carry on. A widget asks for Press, Move and Release on its area and
// calls drag each frame; the router's grab sends it the moves and the
// release even once the pointer has left the area.

// Drag_Axis is the way a drag may move. A locked axis also decides the
// slop, so a vertical list's drag waits for vertical travel and leaves a
// sideways swipe to a carousel inside it.
Drag_Axis :: enum u8 {
	Both,
	Horizontal,
	Vertical,
}

// Drag_Phase is where a drag stands: Pressed until the pointer passes the
// slop, then Dragging until it is released.
Drag_Phase :: enum u8 {
	Idle,
	Pressed,
	Dragging,
}

// DRAG_SLOP is how far, in logical pixels, a press moves before it is a
// drag rather than a click: touchSlop in Gio v0.9.0's gesture/gesture.go.
DRAG_SLOP :: f32(3)

// Drag is one area's drag gesture, kept across frames.
Drag :: struct {
	phase:    Drag_Phase,
	delta:    ops.Point, // the travel this frame added while Dragging, on the axis
	total:    ops.Point, // the travel since the press, on the axis
	velocity: ops.Point, // logical px/s: the running estimate while Dragging, the release's on the frame it ends
	released: bool, // this frame ended a drag: carry it on with velocity
	tapped:   bool, // this frame released a press that never passed the slop
	tracker:  Velocity_Tracker,
}

// drag reads this frame's events for area into its Drag, kept in the
// area's widget_data, and returns it.
drag :: proc(gtx: ^Ctx, area: ops.Area_Id, axis := Drag_Axis.Both, slop := DRAG_SLOP) -> ^Drag {
	d := widget_data(gtx, area, Drag)
	drag_update(d, events(gtx, area), axis, slop)
	return d
}

// drag_update applies one frame's events to d. Only the left button
// drags; a Cancel drops the drag without a release.
drag_update :: proc(d: ^Drag, evs: []Event, axis := Drag_Axis.Both, slop := DRAG_SLOP) {
	d.delta = {}
	d.released, d.tapped = false, false
	for e in evs {
		#partial switch e.kind {
		case .Press:
			if e.button != .Left || d.phase != .Idle {
				continue
			}
			d.phase = .Pressed
			d.total, d.velocity = {}, {}
			velocity_reset(&d.tracker)
			velocity_add(&d.tracker, e.time, {})
		case .Move:
			if d.phase == .Idle {
				continue
			}
			step := on_axis(e.travel, axis)
			d.total += step
			velocity_add(&d.tracker, e.time, d.total)
			if d.phase == .Pressed && length_sq(d.total) > slop * slop {
				d.phase = .Dragging
				step = d.total // the slop's travel lands with the drag's first frame
			}
			if d.phase == .Dragging {
				d.delta += step
				d.velocity = on_axis(velocity_estimate(&d.tracker, e.time), axis)
			}
		case .Release:
			if e.button != .Left || d.phase == .Idle {
				continue
			}
			if d.phase == .Dragging {
				d.released = true
				d.velocity = on_axis(velocity_estimate(&d.tracker, e.time), axis)
			} else {
				d.tapped = true
			}
			d.phase = .Idle
		case .Cancel:
			d.phase = .Idle
			d.velocity = {}
		}
	}
}

@(private = "file")
on_axis :: proc(p: ops.Point, axis: Drag_Axis) -> ops.Point {
	switch axis {
	case .Both:
		return p
	case .Horizontal:
		return {p.x, 0}
	case .Vertical:
		return {0, p.y}
	}
	return p
}

@(private = "file")
length_sq :: proc(p: ops.Point) -> f32 {
	return p.x * p.x + p.y * p.y
}

// Velocity_Tracker estimates a pointer's velocity from its recent
// positions: a least-squares quadratic through the samples of the last
// VELOCITY_WINDOW, its slope at the newest one, as Android's
// VelocityTracker and Gio's internal/fling do.
Velocity_Tracker :: struct {
	samples: [VELOCITY_SAMPLES]Velocity_Sample,
	next:    int, // where the next sample goes
	count:   int,
}

Velocity_Sample :: struct {
	time: f64, // seconds, Event.time's clock
	pos:  ops.Point,
}

// VELOCITY_SAMPLES is how many samples a tracker keeps; VELOCITY_WINDOW is
// how far back from the newest it looks, and VELOCITY_GAP the longest
// pause between samples, or after the last before the release, that it
// still counts as one movement: historySize, maxAge and maxSampleGap in
// Gio v0.9.0's internal/fling/extrapolation.go. The pause before the
// release is Android's ASSUME_POINTER_STOPPED_TIME (40 ms,
// libs/input/VelocityTracker.cpp), which Gio does not apply.
VELOCITY_SAMPLES :: 20
VELOCITY_WINDOW :: 0.100
VELOCITY_GAP :: 0.040

velocity_reset :: proc(v: ^Velocity_Tracker) {
	v^ = {}
}

velocity_add :: proc(v: ^Velocity_Tracker, time: f64, pos: ops.Point) {
	v.samples[v.next] = {time, pos}
	v.next = (v.next + 1) % VELOCITY_SAMPLES
	v.count = min(v.count + 1, VELOCITY_SAMPLES)
}

// velocity_estimate is the velocity, in position units per second, at
// time now: zero when the pointer has paused for longer than VELOCITY_GAP
// before now, or when fewer than three samples with distinct times are
// recent enough to fit a curve through.
velocity_estimate :: proc(v: ^Velocity_Tracker, now: f64) -> ops.Point {
	if v.count == 0 {
		return {}
	}
	newest := v.samples[(v.next - 1 + VELOCITY_SAMPLES) % VELOCITY_SAMPLES]
	if now - newest.time > VELOCITY_GAP {
		return {}
	}
	ts, xs, ys: [VELOCITY_SAMPLES]f64
	n := 0
	prev := newest.time
	for back in 0 ..< v.count {
		s := v.samples[(v.next - 1 - back + 2 * VELOCITY_SAMPLES) % VELOCITY_SAMPLES]
		if newest.time - s.time >= VELOCITY_WINDOW || prev - s.time >= VELOCITY_GAP {
			break
		}
		prev = s.time
		ts[n] = s.time - newest.time
		xs[n] = f64(s.pos.x - newest.pos.x)
		ys[n] = f64(s.pos.y - newest.pos.y)
		n += 1
	}
	vx, okx := slope_at_zero(ts[:n], xs[:n])
	vy, oky := slope_at_zero(ts[:n], ys[:n])
	if !okx || !oky {
		return {}
	}
	return {f32(vx), f32(vy)}
}

// slope_at_zero fits y = c0 + c1 t + c2 t² to the points by least squares
// and returns c1, the slope at t = 0, from the normal equations in f64
// (gesture_test fits frame-spaced samples to within 0.5 px/s); false when the
// times are too few or too alike to fit.
@(private = "file")
slope_at_zero :: proc(t, y: []f64) -> (f64, bool) {
	if len(t) < 3 {
		return 0, false
	}
	// s[k] = Σ t^k, r[k] = Σ y t^k.
	s: [5]f64
	r: [3]f64
	for ti, i in t {
		p := 1.0
		for k in 0 ..< 5 {
			s[k] += p
			if k < 3 {
				r[k] += y[i] * p
			}
			p *= ti
		}
	}
	m := matrix[3, 3]f64{
		s[0], s[1], s[2],
		s[1], s[2], s[3],
		s[2], s[3], s[4],
	}
	det := linalg.determinant(m)
	// The determinant scales as t^6: compare it with s[2]³, its own scale.
	if abs(det) <= 1e-9 * s[2] * s[2] * s[2] || s[2] == 0 {
		return 0, false
	}
	// Cramer's rule for c1: m with its second column replaced by r.
	m1 := m
	m1[0, 1], m1[1, 1], m1[2, 1] = r[0], r[1], r[2]
	return linalg.determinant(m1) / det, true
}
