// Package testutil holds the handful of assertions a jm:ui package's own
// tests and a downstream package's tests (ui/diagram, say) both want, kept
// dependency-free of jm:ui itself so ui's own tests can import it without
// an import cycle.
package testutil

// count_ops returns how many elements of ops are exactly variant T of the
// union type E — e.g. count_ops(o.ops[:], ui.Fill) for how many Fill draws
// an Ops buffer holds.
count_ops :: proc(ops: []$E, $T: typeid) -> int {
	n := 0
	for op in ops {
		if _, ok := op.(T); ok {
			n += 1
		}
	}
	return n
}
