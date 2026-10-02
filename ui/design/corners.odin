package design

import "core:math"
import "jm:ui/ops"
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
rounded :: proc(gtx: ^ui.Ctx, r: ops.Rect, c: Corners) -> ops.Path_Ref {
	o := outline(r, c)
	verbs := make([]ops.Path_Verb, len(o.verbs), gtx.allocator)
	pts := make([]ops.Point, len(o.points), gtx.allocator)
	copy(verbs, o.verbs[:])
	copy(pts, o.points[:])
	return {ops.add_path(gtx.scene, {verbs, pts})}
}

// Outline is a rounded rect's closed path by value: a move, four sides
// each with its corner's cubic, and a close.
Outline :: struct {
	verbs:  [10]ops.Path_Verb,
	points: [17]ops.Point,
}

// outline is r with per-corner radii c, each clamped to half the shorter
// side, traced clockwise from the top-left corner's end.
outline :: proc(r: ops.Rect, c: Corners) -> (o: Outline) {
	lim := min(r.w, r.h) / 2
	tl, tr, br, bl := clamp(c.tl, 0, lim), clamp(c.tr, 0, lim), clamp(c.br, 0, lim), clamp(c.bl, 0, lim)
	x0, y0, x1, y1 := r.x, r.y, r.x + r.w, r.y + r.h
	k := KAPPA
	o.verbs = {.Move, .Line, .Cubic, .Line, .Cubic, .Line, .Cubic, .Line, .Cubic, .Close}
	o.points = {
		{x0 + tl, y0},
		{x1 - tr, y0},
		{x1 - tr + tr * k, y0},
		{x1, y0 + tr - tr * k},
		{x1, y0 + tr},
		{x1, y1 - br},
		{x1, y1 - br + br * k},
		{x1 - br + br * k, y1},
		{x1 - br, y1},
		{x0 + bl, y1},
		{x0 + bl - bl * k, y1},
		{x0, y1 - bl + bl * k},
		{x0, y1 - bl},
		{x0, y0 + tl},
		{x0, y0 + tl - tl * k},
		{x0 + tl - tl * k, y0},
		{x0 + tl, y0},
	}
	return
}

// ring_path is a Path_Ref for outer with hole cut out of it, per-corner
// radii ko and kh: outer's outline clockwise, then hole's anticlockwise,
// so a non-zero fill paints the ring between them. Where hole leaves
// outer, the fill covers hole's outside part too; clip to outer.
ring_path :: proc(gtx: ^ui.Ctx, outer: ops.Rect, ko: Corners, hole: ops.Rect, kh: Corners) -> ops.Path_Ref {
	o, h := outline(outer, ko), reversed(outline(hole, kh))
	verbs := make([]ops.Path_Verb, 2 * len(o.verbs), gtx.allocator)
	pts := make([]ops.Point, 2 * len(o.points), gtx.allocator)
	copy(verbs, o.verbs[:])
	copy(verbs[len(o.verbs):], h.verbs[:])
	copy(pts, o.points[:])
	copy(pts[len(o.points):], h.points[:])
	return {ops.add_path(gtx.scene, {verbs, pts})}
}

// reversed is o traced the other way round: the same corners and sides,
// anticlockwise from the same point.
reversed :: proc(o: Outline) -> (r: Outline) {
	r.verbs[0], r.points[0] = .Move, o.points[len(o.points) - 1]
	at := len(o.points) - 1 // the end of the segment being reversed
	vi, pi := 1, 1
	for i := len(o.verbs) - 2; i >= 1; i -= 1 {
		r.verbs[vi] = o.verbs[i]
		vi += 1
		switch o.verbs[i] {
		case .Cubic:
			r.points[pi], r.points[pi + 1], r.points[pi + 2] = o.points[at - 1], o.points[at - 2], o.points[at - 3]
			pi += 3
			at -= 3
		case .Line:
			r.points[pi] = o.points[at - 1]
			pi += 1
			at -= 1
		case .Move, .Close:
			panic("design: reversed takes an Outline's sides and corners")
		}
	}
	r.verbs[vi] = .Close
	return
}

// arc is an open Path_Ref along the circle at c of radius r from angle a0
// to a1 (radians, y down, so positive turns clockwise), in cubic segments
// of at most a quarter turn each.
arc :: proc(gtx: ^ui.Ctx, c: ops.Point, r: f32, a0, a1: f32) -> ops.Path_Ref {
	sweep := a1 - a0
	n := max(int(math.ceil(abs(sweep) / (math.PI / 2))), 1)
	verbs := make([]ops.Path_Verb, n + 1, gtx.allocator)
	pts := make([]ops.Point, 1 + 3 * n, gtx.allocator)
	step := sweep / f32(n)
	// Control distance for a circular arc of angle step: 4/3 tan(step/4).
	k := 4.0 / 3.0 * math.tan(step / 4) * r
	a := a0
	p0 := c + r * ops.Point{math.cos(a), math.sin(a)}
	verbs[0] = .Move
	pts[0] = p0
	for i in 0 ..< n {
		b := a + step
		p1 := c + r * ops.Point{math.cos(b), math.sin(b)}
		t0 := ops.Point{-math.sin(a), math.cos(a)}
		t1 := ops.Point{-math.sin(b), math.cos(b)}
		verbs[i + 1] = .Cubic
		pts[1 + 3 * i] = p0 + k * t0
		pts[2 + 3 * i] = p1 - k * t1
		pts[3 + 3 * i] = p1
		p0, a = p1, b
	}
	return {ops.add_path(gtx.scene, {verbs, pts})}
}
