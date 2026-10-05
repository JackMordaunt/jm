// Package testutil holds the handful of assertions a jm:ui package's own
// tests and a downstream package's tests (ui/diagram, say) both want, kept
// dependency-free of jm:ui itself so ui's own tests can import it without
// an import cycle.
package testutil

import "base:runtime"

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

// same_params reports whether procedures a and b take the same parameters,
// by name and type, in order: a guard and the opener it forwards to, which
// must agree so a call reads the same in either form. Defaults are not
// compared: runtime.Type_Info_Parameters holds only types and names.
same_params :: proc(a, b: typeid) -> bool {
	pa, oka := runtime.type_info_base(type_info_of(a)).variant.(runtime.Type_Info_Procedure)
	pb, okb := runtime.type_info_base(type_info_of(b)).variant.(runtime.Type_Info_Procedure)
	if !oka || !okb {
		return false
	}
	if pa.params == nil || pb.params == nil {
		return pa.params == pb.params
	}
	ta := pa.params.variant.(runtime.Type_Info_Parameters)
	tb := pb.params.variant.(runtime.Type_Info_Parameters)
	if len(ta.types) != len(tb.types) {
		return false
	}
	for ii in 0 ..< len(ta.types) {
		if ta.names[ii] != tb.names[ii] || ta.types[ii].id != tb.types[ii].id {
			return false
		}
	}
	return true
}
