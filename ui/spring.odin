package ui

import "core:math"

// Spring is a value chasing a target along a damped spring of unit mass,
// evaluated in closed form from the moment its target last changed, so it
// is frame-rate independent. Retargeting mid-flight starts a new spring
// from the current value and velocity (the m3e-kit's foundations.json,
// motion.algorithm.rules).
//
// The zero Spring is unstarted: its first spring_update snaps to the
// target, so a widget appearing for the first time does not animate in
// from zero.
Spring :: struct {
	value:    f32,
	velocity: f32,
	target:   f32,
	x0, v0:   f32, // offset from target and velocity when target was set
	t:        f32, // seconds since target was set
	started:  bool,
}

// Spring_Params are a spring's damping ratio (1 = critical, no overshoot)
// and stiffness (N/m at unit mass).
Spring_Params :: struct {
	damping, stiffness: f32,
}

// SPRING_THRESHOLD is the default settle distance: 0.01 suits a 0-1
// fraction; pass 0.1 for a distance in dp.
SPRING_THRESHOLD :: f32(0.01)

// spring_update moves s toward target by gtx.dt under p, asks for another
// frame while it is still moving, and returns its value. It settles —
// snaps to target and stops asking for frames — once both its offset and
// its velocity fall below threshold.
spring_update :: proc(s: ^Spring, gtx: ^Ctx, target: f32, p: Spring_Params, threshold := SPRING_THRESHOLD) -> f32 {
	if !s.started {
		s^ = {value = target, target = target, started = true}
		return target
	}
	if target != s.target {
		s.x0 = s.value - target
		s.v0 = s.velocity
		s.target = target
		s.t = 0
	}
	if s.value == s.target && s.velocity == 0 {
		return s.value
	}
	s.t += gtx.dt
	x, v := spring_at(s.x0, s.v0, s.t, p)
	if abs(x) < threshold && abs(v) < threshold {
		s.value, s.velocity = s.target, 0
		return s.value
	}
	s.value, s.velocity = s.target + x, v
	request_frame(gtx)
	return s.value
}

// spring_at is the offset from target and the velocity t seconds after a
// spring started at offset x0 with velocity v0.
spring_at :: proc(x0, v0, t: f32, p: Spring_Params) -> (x, v: f32) {
	w := math.sqrt(max(p.stiffness, 0))
	z := p.damping
	if z < 1 {
		wd := w * math.sqrt(1 - z * z)
		a := x0
		b := (v0 + z * w * x0) / wd
		e := math.exp(-z * w * t)
		c, sn := math.cos(wd * t), math.sin(wd * t)
		x = e * (a * c + b * sn)
		v = e * ((b * wd - z * w * a) * c - (a * wd + z * w * b) * sn)
		return
	}
	// Critical (and, treated as critical, over-) damping.
	b := v0 + w * x0
	e := math.exp(-w * t)
	x = e * (x0 + b * t)
	v = e * (b - w * (x0 + b * t))
	return
}
