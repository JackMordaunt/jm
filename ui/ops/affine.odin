package ops

import "core:math"

// Affine is a 2D transform in the layout of Blend2D's Matrix2D (m00 m01 m10
// m11 m20 m21 in ui/blend2d/matrix.odin), so it copies straight through:
//   x' = a*x + c*y + e
//   y' = b*x + d*y + f
Affine :: struct {
	a, b, c, d, e, f: f64,
}

IDENTITY :: Affine{1, 0, 0, 1, 0, 0}

translate :: proc(x, y: f32) -> Affine {
	return {1, 0, 0, 1, f64(x), f64(y)}
}

scale :: proc(sx, sy: f32) -> Affine {
	return {f64(sx), 0, 0, f64(sy), 0, 0}
}

// rotate is counter-clockwise in a y-down space by radians.
rotate :: proc(radians: f32) -> Affine {
	s, c := math.sincos(f64(radians))
	return {c, s, -s, c, 0, 0}
}

// mul returns the transform that applies m first, then n.
mul :: proc(m, n: Affine) -> Affine {
	return {
		a = m.a * n.a + m.b * n.c,
		b = m.a * n.b + m.b * n.d,
		c = m.c * n.a + m.d * n.c,
		d = m.c * n.b + m.d * n.d,
		e = m.e * n.a + m.f * n.c + n.e,
		f = m.e * n.b + m.f * n.d + n.f,
	}
}

apply :: proc(m: Affine, p: Point) -> Point {
	x, y := f64(p.x), f64(p.y)
	return {f32(m.a * x + m.c * y + m.e), f32(m.b * x + m.d * y + m.f)}
}

// invert returns the inverse, and false when m is singular.
invert :: proc(m: Affine) -> (Affine, bool) {
	det := m.a * m.d - m.b * m.c
	if abs(det) < 1e-12 {
		return {}, false
	}
	id := 1 / det
	return {
		a = m.d * id,
		b = -m.b * id,
		c = -m.c * id,
		d = m.a * id,
		e = (m.c * m.f - m.d * m.e) * id,
		f = (m.b * m.e - m.a * m.f) * id,
	}, true
}

// is_axis_aligned reports whether m is translate and/or scale only, so an
// axis-aligned rect stays one under it. Executors use it to pick the rect
// clip fast path.
is_axis_aligned :: proc(m: Affine) -> bool {
	return abs(m.b) < 1e-9 && abs(m.c) < 1e-9
}

// transform_rect maps r through m and returns the bounding rect.
transform_rect :: proc(m: Affine, r: Rect) -> Rect {
	p := [4]Point{
		apply(m, {r.x, r.y}),
		apply(m, {r.x + r.w, r.y}),
		apply(m, {r.x, r.y + r.h}),
		apply(m, {r.x + r.w, r.y + r.h}),
	}
	lo, hi := p[0], p[0]
	for q in p[1:] {
		lo = {min(lo.x, q.x), min(lo.y, q.y)}
		hi = {max(hi.x, q.x), max(hi.y, q.y)}
	}
	return {lo.x, lo.y, hi.x - lo.x, hi.y - lo.y}
}
