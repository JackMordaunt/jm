package design

import "core:math"
import "core:testing"
import "jm:ui/ops"

// cubic_mid is the point halfway along cubic s of p (its points at
// s*3+1 after the move).
@(private = "file")
cubic_mid :: proc(p: ops.Path, s: int) -> ops.Point {
	at := 1 + 3 * s
	p0 := p.points[at - 1]
	c1, c2, p3 := p.points[at], p.points[at + 1], p.points[at + 2]
	return (p0 + 3 * c1 + 3 * c2 + p3) / 8
}

@(private = "file")
dist :: proc(a, b: ops.Point) -> f32 {
	return math.sqrt((a.x - b.x) * (a.x - b.x) + (a.y - b.y) * (a.y - b.y))
}

@(test)
test_an_arc_follows_its_circle_to_its_end :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	// A quarter turn clockwise (sweep 1, y down) from (0,0) to (10,10):
	// the small arc is centred on (0,10).
	p, ok := parse_svg_path("M0 0 A10 10 0 0 1 10 10")
	testing.expect(t, ok)
	testing.expect_value(t, p.verbs[1], ops.Path_Verb.Cubic)
	testing.expect_value(t, len(p.verbs), 2) // one cubic for a quarter
	testing.expect_value(t, p.points[len(p.points) - 1], ops.Point{10, 10})
	testing.expectf(t, abs(dist(cubic_mid(p, 0), {0, 10}) - 10) < 0.05, "mid %v", cubic_mid(p, 0))
	// The other sweep bends the other way, round (10,0).
	q, _ := parse_svg_path("M0 0 A10 10 0 0 0 10 10")
	testing.expectf(t, abs(dist(cubic_mid(q, 0), {10, 0}) - 10) < 0.05, "mid %v", cubic_mid(q, 0))
}

@(test)
test_a_large_arc_takes_the_long_way_in_quarter_turns :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p, ok := parse_svg_path("M0 0 A10 10 0 1 1 10 10") // three quarters of the circle round (10,0)
	testing.expect(t, ok)
	testing.expect_value(t, len(p.verbs), 4)
	for s in 0 ..< 3 {
		testing.expectf(t, abs(dist(cubic_mid(p, s), {10, 0}) - 10) < 0.05, "segment %d mid %v", s, cubic_mid(p, s))
	}
}

@(test)
test_radii_too_small_grow_to_reach_the_end :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	p, ok := parse_svg_path("M0 0 A1 1 0 0 1 10 0") // a half circle of radius 5 round (5,0)
	testing.expect(t, ok)
	testing.expect_value(t, p.points[len(p.points) - 1], ops.Point{10, 0})
	for s in 0 ..< len(p.verbs) - 1 {
		testing.expectf(t, abs(dist(cubic_mid(p, s), {5, 0}) - 5) < 0.05, "segment %d mid %v", s, cubic_mid(p, s))
	}
}

@(test)
test_arc_numbers_and_flags_may_run_together :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	defer free_all(context.temp_allocator)
	// The 16px triangle-down octicon, verbatim (the primer-kit's
	// upstream/npm/octicons/data.json): radii run together (.25.25) and a
	// minus sign separates (0-.177).
	tri, ok := parse_svg_path("m4.427 7.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.396 7H4.604a.25.25 0 0 0-.177.427Z")
	testing.expect(t, ok)
	ends := make([dynamic]ops.Point)
	at := 0
	for v in tri.verbs {
		switch v {
		case .Move, .Line:
			at += 1
		case .Cubic:
			at += 3
		case .Close:
			continue
		}
		append(&ends, tri.points[at - 1])
	}
	near :: proc(a, b: ops.Point) -> bool {
		return abs(a.x - b.x) < 1e-3 && abs(a.y - b.y) < 1e-3
	}
	for want in ([]ops.Point{{4.427, 7.427}, {7.823, 10.823}, {8.177, 10.823}, {11.573, 7.427}, {11.396, 7}, {4.604, 7}, {4.427, 7.427}}) {
		found := false
		for e in ends {
			found ||= near(e, want)
		}
		testing.expectf(t, found, "no segment ends at %v; ends %v", want, ends[:])
	}
	// SVG's grammar also lets a flag run into what follows: 011 1 is the
	// flags 0 and 1, then the point 1,1 (SVG 1.1, 8.3.9).
	p, ok2 := parse_svg_path("M0 0a1 1 0 011 1")
	testing.expect(t, ok2)
	testing.expect(t, near(p.points[len(p.points) - 1], {1, 1}))
	a, ok3 := parse_svg_path("M0 0a1 1 0 0 1 0 0") // to the same point: nothing
	testing.expect(t, ok3)
	testing.expect_value(t, len(a.verbs), 1)
	_, bad := parse_svg_path("M0 0a1 1 0 2 1 4 4") // a flag is 0 or 1
	testing.expect(t, !bad)
}
