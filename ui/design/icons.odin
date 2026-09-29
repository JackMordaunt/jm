package design

import "base:intrinsics"
import "base:runtime"
import "core:mem/virtual"
import "jm:ui"
import "jm:ui/ops"

// A system's icons are vector paths rather than an icon font: jm:ui has
// one text font and no font fallback, and a path needs no font file on
// the target machine. Each system keeps its symbols' SVG path data and an
// Icon enum over them; Icon_Set parses each on first use into a path in
// the symbol's own box-unit square and keeps it for the life of the
// thread, and paint_icon scales that to the requested size.

// Icon_Set is the parsed-path cache for one system's Icon enum I. It is
// per thread, like everything else in jm:ui (one Ctx per thread): a
// shared one raced when two threads parsed the same icon, shifting one
// path's points twice. Its arena owns every parsed path, so the cache
// does not borrow whichever allocator its first caller happened to have.
Icon_Set :: struct($I: typeid) where intrinsics.type_is_enum(I) {
	cache:  [I]ops.Path,
	parsed: [I]bool,
	boxes:  [I]f32,
	arena:  virtual.Arena,
}

// icon_path is i's outline in its box-unit square with the origin at the
// top-left, parsed on first use. src is where the system's path data
// comes from: symbol i's SVG path data, the side of its square box, and
// the offset that moves its viewBox origin to the top-left (Material's
// symbols start at y = -960).
icon_path :: proc(set: ^Icon_Set($I), src: proc(i: I) -> (string, f32, ops.Point), i: I) -> (path: ops.Path, box: f32) {
	if !set.parsed[i] {
		data, b, offset := src(i)
		set.cache[i], _ = parse_svg_path(data, arena_allocator(&set.arena)) // a partial path still draws; the system's test catches it
		if offset != {} {
			for &q in set.cache[i].points {
				q += offset
			}
		}
		set.boxes[i] = b
		set.parsed[i] = true
	}
	return set.cache[i], set.boxes[i]
}

@(private = "file")
arena_allocator :: proc(a: ^virtual.Arena) -> runtime.Allocator {
	return virtual.arena_allocator(a)
}

// paint_icon fills i at size pixels with its top-left at pos.
paint_icon :: proc(gtx: ^ui.Ctx, set: ^Icon_Set($I), src: proc(i: I) -> (string, f32, ops.Point), i: I, pos: ops.Point, size: f32, color: ops.Color) {
	if !ui.painted(color) {
		return
	}
	p, box := icon_path(set, src, i)
	if len(p.points) == 0 {
		return
	}
	k := size / box
	ops.transform_push(gtx.scene, ops.mul(ops.scale(k, k), ops.translate(pos.x, pos.y)))
	ops.fill(gtx.scene, ops.Path_Ref{ops.add_path(gtx.scene, p)}, color)
	ops.transform_pop(gtx.scene)
}
