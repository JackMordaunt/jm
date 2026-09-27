package ui

// Shape constructors for custom widgets and canvases: a line, an open
// polyline, a closed polygon and a circle, each returned the way Round_Rect
// and Ellipse are — a value to hand to fill or stroke, not a draw call
// itself. line, polyline and polygon build their Path on gtx.allocator (the
// frame arena), the same rule every other widget follows for anything that
// must outlive the call — see Path.

// line is the two-point Path_Ref from p0 to p1.
line :: proc(gtx: ^Ctx, p0, p1: Point) -> Path_Ref {
	return polyline(gtx, []Point{p0, p1})
}

// polyline is the open Path_Ref through points in order: Move to the first,
// Line to each after. Fewer than two points records an empty path.
polyline :: proc(gtx: ^Ctx, points: []Point) -> Path_Ref {
	return Path_Ref{path_through(gtx, points, close = false)}
}

// polygon is the closed Path_Ref through points, in order, back to the
// first. Fewer than two points records an empty path.
polygon :: proc(gtx: ^Ctx, points: []Point) -> Path_Ref {
	return Path_Ref{path_through(gtx, points, close = true)}
}

// circle is the Ellipse of radius r centred at c.
circle :: proc(c: Point, r: f32) -> Ellipse {
	return Ellipse{{c.x - r, c.y - r, r * 2, r * 2}}
}

@(private = "file")
path_through :: proc(gtx: ^Ctx, points: []Point, close: bool) -> Path_Id {
	if len(points) < 2 {
		return add_path(gtx.ops, {})
	}
	n := len(points) + (1 if close else 0)
	verbs := make([]Path_Verb, n, gtx.allocator)
	pts := make([]Point, len(points), gtx.allocator)
	copy(pts, points)
	verbs[0] = .Move
	for i in 1 ..< len(points) {
		verbs[i] = .Line
	}
	if close {
		verbs[n - 1] = .Close
	}
	return add_path(gtx.ops, {verbs, pts})
}
