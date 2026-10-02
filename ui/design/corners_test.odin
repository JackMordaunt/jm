package design

import "core:testing"

@(test)
test_reversed_traces_the_same_outline_the_other_way :: proc(t: ^testing.T) {
	o := outline({2, 3, 40, 20}, {4, 6, 8, 2})
	r := reversed(o)
	// A reversed outline is the same points backwards, control points of
	// each cubic swapped with it, and the same segments in reverse order.
	for i in 0 ..< len(o.points) {
		testing.expectf(t, r.points[i] == o.points[len(o.points) - 1 - i], "point %d: %v", i, r.points[i])
	}
	testing.expect_value(t, r.verbs[0], o.verbs[0])
	testing.expect_value(t, r.verbs[len(r.verbs) - 1], o.verbs[len(o.verbs) - 1])
	for i in 1 ..< len(o.verbs) - 1 {
		testing.expect_value(t, r.verbs[i], o.verbs[len(o.verbs) - 1 - i])
	}
	// So the signed area flips.
	area :: proc(o: Outline) -> (a: f32) {
		for i in 0 ..< len(o.points) - 1 {
			p, q := o.points[i], o.points[i + 1]
			a += p.x * q.y - q.x * p.y
		}
		return
	}
	testing.expectf(t, area(o) > 0 && abs(area(o) + area(r)) < 1e-3, "areas %v and %v", area(o), area(r))
}
