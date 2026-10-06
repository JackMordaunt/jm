package plot

import "core:math"
import "jm:ui/ops"

// Step is how a line goes from one point to the next.
Step :: enum u8 {
	None, // straight
	After, // level until the next point's x, then up or down: a value that holds until it changes
	Before, // up or down at once, then level
	Middle, // level to halfway, up or down, level again
}

// Reducer thins a polyline to what a pixel column can show: of the points
// that fall in one column it keeps the first, the lowest, the highest and
// the last, in their order along the line (min/max decimation). Every
// extreme survives, so a spike one point wide still reaches its height,
// and a line of n points costs at most four points a column however large
// n is. Points arrive with reduce_push in increasing x; reduce_break ends
// a run at a gap.
Reducer :: struct {
	out:                 ^Polyline,
	col:                 f32,
	have:                bool,
	first, last, lo, hi: Sample,
}

// Sample is a point and its place along the line.
Sample :: struct {
	p: ops.Point,
	i: int,
}

// Polyline is a run of points in runs: starts[k] is where run k begins in
// points, so a gap between runs is a pen lift.
Polyline :: struct {
	points: [dynamic]ops.Point,
	starts: [dynamic]int,
	step:   Step,
	open:   bool, // a run is open: the next point continues it
}

// reduce_push adds point p, the i-th of the line.
reduce_push :: proc(r: ^Reducer, p: ops.Point, i: int) {
	col := math.floor(p.x)
	if r.have && col != r.col {
		reduce_flush(r)
	}
	s := Sample{p, i}
	if !r.have {
		r.col, r.have = col, true
		r.first, r.last, r.lo, r.hi = s, s, s, s
		return
	}
	r.last = s
	if p.y < r.lo.p.y {
		r.lo = s
	}
	if p.y > r.hi.p.y {
		r.hi = s
	}
}

// reduce_break ends the run at a gap: the points after it start a new one.
reduce_break :: proc(r: ^Reducer) {
	reduce_flush(r)
	r.out.open = false
}

// reduce_flush emits the column held so far.
reduce_flush :: proc(r: ^Reducer) {
	if !r.have {
		return
	}
	r.have = false
	keep := [4]Sample{r.first, r.lo, r.hi, r.last}
	// The four in line order; at most four, so an insertion sort.
	for i in 1 ..< 4 {
		for j := i; j > 0 && keep[j].i < keep[j - 1].i; j -= 1 {
			keep[j], keep[j - 1] = keep[j - 1], keep[j]
		}
	}
	prev := -1
	for k in keep {
		if k.i != prev {
			polyline_add(r.out, k.p)
			prev = k.i
		}
	}
}

// polyline_add continues the open run to p, or starts a run at p, putting
// in the corners a stepped line turns at.
polyline_add :: proc(l: ^Polyline, p: ops.Point) {
	if !l.open {
		append(&l.starts, len(l.points))
		append(&l.points, p)
		l.open = true
		return
	}
	q := l.points[len(l.points) - 1]
	switch l.step {
	case .None:
	case .After:
		append(&l.points, ops.Point{p.x, q.y})
	case .Before:
		append(&l.points, ops.Point{q.x, p.y})
	case .Middle:
		m := (q.x + p.x) / 2
		append(&l.points, ops.Point{m, q.y}, ops.Point{m, p.y})
	}
	append(&l.points, p)
}

// polyline_run is run k's points: from its start to the next run's.
polyline_run :: proc(l: ^Polyline, k: int) -> []ops.Point {
	end := len(l.points) if k + 1 >= len(l.starts) else l.starts[k + 1]
	return l.points[l.starts[k]:end]
}
