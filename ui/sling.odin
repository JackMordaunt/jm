package ui

import "core:math"
import "jm:ui/ops"

// Sling carries a released drag on, slowing under a drag force
// proportional to its speed, as Gio's internal/fling does: from velocity
// v0 at t0 it has travelled v0 (e^(k t) - 1) / k after t seconds, and moves
// at v0 e^(k t). It stops when its speed falls below SLING_STOP.
Sling :: struct {
	v0:    ops.Point, // logical px/s when it started; zero when at rest
	t0:    f64, // Ctx.time it started
	moved: ops.Point, // how far it had gone at the last sling_step
}

// SLING_MIN and SLING_MAX bound the release speed, in logical px/s, that
// starts a sling and the speed it starts at; SLING_STOP is the speed it
// stops below. Gio's values (internal/fling/animation.go).
SLING_MIN :: f32(50)
SLING_MAX :: f32(8000)
SLING_STOP :: f32(1)

// SLING_DECAY is k, the rate the speed decays at per second: Gio's -2 on
// Apple platforms, a long glide like iOS, and Android's -4.2 elsewhere.
SLING_DECAY :: f32(-2) when ODIN_OS == .Darwin else f32(-4.2)

// sling_start starts s at velocity from now, clamped to SLING_MAX, and
// reports whether it did: a release slower than SLING_MIN stays put.
sling_start :: proc(s: ^Sling, velocity: ops.Point, now: f64) -> bool {
	speed := math.sqrt(velocity.x * velocity.x + velocity.y * velocity.y)
	if speed < SLING_MIN {
		s^ = {}
		return false
	}
	v := velocity
	if speed > SLING_MAX {
		v *= SLING_MAX / speed
	}
	s^ = {v0 = v, t0 = now}
	return true
}

// sling_step is how far s moved between the last step (or its start) and
// now, and whether it is still moving after it. A widget adds the travel
// to its offset and requests a frame while it moves; one that hits an
// edge calls sling_stop.
sling_step :: proc(s: ^Sling, now: f64) -> (travel: ops.Point, moving: bool) {
	if !sling_active(s) {
		return {}, false
	}
	k := SLING_DECAY
	t := f32(max(now - s.t0, 0))
	ekt := math.exp(k * t)
	at := s.v0 * ((ekt - 1) / k)
	travel = at - s.moved
	s.moved = at
	speed := math.sqrt(s.v0.x * s.v0.x + s.v0.y * s.v0.y) * ekt
	if speed < SLING_STOP {
		s^ = {}
		return travel, false
	}
	return travel, true
}

sling_active :: proc(s: ^Sling) -> bool {
	return s.v0 != {}
}

sling_stop :: proc(s: ^Sling) {
	s^ = {}
}
