// Package testutil holds the handful of assertions a jm:ui package's own
// tests and a downstream package's tests (ui/diagram, say) both want, kept
// dependency-free of jm:ui itself so ui's own tests can import it without
// an import cycle.
package testutil

// count_ops returns how many elements of sc are exactly variant T of the
// union type E — e.g. count_ops(o.ops[:], ui.Fill) for how many Fill draws
// a Scene holds.
count_ops :: proc(sc: []$E, $T: typeid) -> int {
	n := 0
	for op in sc {
		if _, ok := op.(T); ok {
			n += 1
		}
	}
	return n
}

// near reports whether a and b agree within tol: a float equality for
// positions built from fractional text widths and scaled layouts, whose
// last bits round differently by the path that computed them.
near :: proc(a, b: f32, tol: f32 = 1e-3) -> bool {
	return abs(a - b) < tol
}
