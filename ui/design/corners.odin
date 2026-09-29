package design

import "core:math"
import "jm:ui"

// Corners are per-corner radii, clockwise from top-left. ui.Round_Rect has
// one radius for all four, but design systems often differ per corner (a
// split button's inner edge, a sheet's top-only rounding, a tab indicator).
Corners :: struct {
	tl, tr, br, bl: f32,
}

corners_all :: proc(r: f32) -> Corners {
	return {r, r, r, r}
}

// lerp_corners is the morph from a to b at t, per corner. t may overshoot
// [0, 1] under a spring; rounded clamps the result.
lerp_corners :: proc(a, b: Corners, t: f32) -> Corners {
	return {a.tl + (b.tl - a.tl) * t, a.tr + (b.tr - a.tr) * t, a.br + (b.br - a.br) * t, a.bl + (b.bl - a.bl) * t}
}

// grow_corners is k for a shape grown outward by d on every side.
grow_corners :: proc(k: Corners, d: f32) -> Corners {
	return {max(k.tl + d, 0), max(k.tr + d, 0), max(k.br + d, 0), max(k.bl + d, 0)}
}

// KAPPA places a cubic's control points to approximate a quarter circle.
KAPPA :: f32(0.5522847)

// rounded is a Path_Ref for r with per-corner radii c, each clamped to
// half the shorter side. Built on gtx.allocator, like ui.polygon.
rounded :: proc(gtx: ^ui.Ctx, r: ui.Rect, c: Corners) -> ui.Path_Ref {
	lim := min(r.w, r.h) / 2
	tl, tr, br, bl := clamp(c.tl, 0, lim), clamp(c.tr, 0, lim), clamp(c.br, 0, lim), clamp(c.bl, 0, lim)
	verbs := make([]ui.Path_Verb, 10, gtx.allocator)
	pts := make([]ui.Point, 17, gtx.allocator)
	x0, y0, x1, y1 := r.x, r.y, r.x + r.w, r.y + r.h
	k := KAPPA
	verbs[0] = .Move
	pts[0] = {x0 + tl, y0}
	verbs[1] = .Line
	pts[1] = {x1 - tr, y0}
	verbs[2] = .Cubic
	pts[2], pts[3], pts[4] = {x1 - tr + tr * k, y0}, {x1, y0 + tr - tr * k}, {x1, y0 + tr}
	verbs[3] = .Line
	pts[5] = {x1, y1 - br}
	verbs[4] = .Cubic
	pts[6], pts[7], pts[8] = {x1, y1 - br + br * k}, {x1 - br + br * k, y1}, {x1 - br, y1}
	verbs[5] = .Line
	pts[9] = {x0 + bl, y1}
	verbs[6] = .Cubic
	pts[10], pts[11], pts[12] = {x0 + bl - bl * k, y1}, {x0, y1 - bl + bl * k}, {x0, y1 - bl}
	verbs[7] = .Line
	pts[13] = {x0, y0 + tl}
	verbs[8] = .Cubic
	pts[14], pts[15], pts[16] = {x0, y0 + tl - tl * k}, {x0 + tl - tl * k, y0}, {x0 + tl, y0}
	verbs[9] = .Close
	return {ui.add_path(gtx.ops, {verbs, pts})}
}

// arc is an open Path_Ref along the circle at c of radius r from angle a0
// to a1 (radians, y down, so positive turns clockwise), in cubic segments
// of at most a quarter turn each.
arc :: proc(gtx: ^ui.Ctx, c: ui.Point, r: f32, a0, a1: f32) -> ui.Path_Ref {
	sweep := a1 - a0
	n := max(int(math.ceil(abs(sweep) / (math.PI / 2))), 1)
	verbs := make([]ui.Path_Verb, n + 1, gtx.allocator)
	pts := make([]ui.Point, 1 + 3 * n, gtx.allocator)
	step := sweep / f32(n)
	// Control distance for a circular arc of angle step: 4/3 tan(step/4).
	k := 4.0 / 3.0 * math.tan(step / 4) * r
	a := a0
	p0 := c + r * ui.Point{math.cos(a), math.sin(a)}
	verbs[0] = .Move
	pts[0] = p0
	for i in 0 ..< n {
		b := a + step
		p1 := c + r * ui.Point{math.cos(b), math.sin(b)}
		t0 := ui.Point{-math.sin(a), math.cos(a)}
		t1 := ui.Point{-math.sin(b), math.cos(b)}
		verbs[i + 1] = .Cubic
		pts[1 + 3 * i] = p0 + k * t0
		pts[2 + 3 * i] = p1 - k * t1
		pts[3 + 3 * i] = p1
		p0, a = p1, b
	}
	return {ui.add_path(gtx.ops, {verbs, pts})}
}
