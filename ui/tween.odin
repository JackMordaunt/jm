package ui

import "core:math"

// Tween is a value moving from from to to over duration seconds, advanced
// by tween_update. It replaces the boilerplate of keeping t, adding
// gtx.dt and calling request_frame by hand for a straight-line animation
// — the way examples/ui-kitchen's kitchen proc turns the badge widget it
// draws, inline, before this existed.
Tween :: struct {
	from, to: f32,
	duration: f32, // seconds; <= 0 jumps straight to to
	loop:     bool, // wrap back to from instead of stopping at to
	t:        f32, // elapsed seconds; tween_update advances this
}

// tween_update advances tw by gtx.dt, asks for another frame while tw is
// still moving, and returns its value at the new t.
tween_update :: proc(tw: ^Tween, gtx: ^Ctx) -> f32 {
	if tw.duration <= 0 {
		return tw.to
	}
	tw.t += gtx.dt
	moving := true
	if tw.loop {
		tw.t = math.mod(tw.t, tw.duration)
	} else if tw.t >= tw.duration {
		tw.t = tw.duration
		moving = false
	}
	if moving {
		request_frame(gtx)
	}
	return tw.from + (tw.to - tw.from) * (tw.t / tw.duration)
}
