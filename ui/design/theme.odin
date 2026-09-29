package design

import "base:intrinsics"
import "jm:ui"

// Theme is a design system's colour binding: for every context (light,
// dark, high contrast) and every role, one colour. Components read roles;
// only the binding knows which context is active. R is the system's role
// enum and C its context enum.
Theme :: struct($R, $C: typeid) where intrinsics.type_is_enum(R), intrinsics.type_is_enum(C) {
	bind: [C][R]ui.Color,
}

// Relation is what an axiom asserts about two bound roles a and b.
Relation :: enum u8 {
	Contrast_Min, // apca(a, b) >= k, a being the text and b its background
	Ratio_Min, // wcag_ratio(a, b) >= k
	Lighter_By, // oklch(a).l - oklch(b).l >= k
	Darker_By, // oklch(b).l - oklch(a).l >= k
	Hue_Within, // hue_dist(a, b) <= k, degrees
	Same, // a == b exactly; k unused
}

// Axiom is one relation a valid theme satisfies in every context.
Axiom :: struct($R: typeid) where intrinsics.type_is_enum(R) {
	rel:  Relation,
	a, b: R,
	k:    f32,
}

// Violation is an axiom a theme fails in one context, and what it
// measured there.
Violation :: struct($R, $C: typeid) where intrinsics.type_is_enum(R), intrinsics.type_is_enum(C) {
	ctx:   C,
	axiom: Axiom(R),
	got:   f32,
}

// check measures every axiom in every context of t and returns the ones
// that fail, allocated on allocator. An empty result means t is valid.
check :: proc(t: Theme($R, $C), axioms: []Axiom(R), allocator := context.allocator) -> [dynamic]Violation(R, C) {
	out := make([dynamic]Violation(R, C), allocator)
	for ctx in C {
		for ax in axioms {
			got, ok := measure(t.bind[ctx][ax.a], t.bind[ctx][ax.b], ax.rel, ax.k)
			if !ok {
				append(&out, Violation(R, C){ctx, ax, got})
			}
		}
	}
	return out
}

// measure applies rel to colours a and b against k: the value measured
// and whether it satisfies the relation.
measure :: proc(a, b: ui.Color, rel: Relation, k: f32) -> (got: f32, ok: bool) {
	switch rel {
	case .Contrast_Min:
		got = apca(a, b)
		ok = got >= k
	case .Ratio_Min:
		got = wcag_ratio(a, b)
		ok = got >= k
	case .Lighter_By:
		got = oklch(a).l - oklch(b).l
		ok = got >= k
	case .Darker_By:
		got = oklch(b).l - oklch(a).l
		ok = got >= k
	case .Hue_Within:
		got = hue_dist(oklch(a).h, oklch(b).h)
		ok = got <= k
	case .Same:
		ok = a == b
		got = ok ? 0 : 1
	}
	return
}
