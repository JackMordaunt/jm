package design

import "core:math"
import "core:strconv"
import "jm:ui/ops"

// parse_svg_path turns SVG path data into an ops.Path. It handles every
// SVG 1.1 path command, M L H V C S Q T A Z, in both cases (each system's
// icon test checks its own set parses); quadratics and elliptical arcs
// become cubics. ok is false when it met anything else and stopped
// there; the partial path still draws.
parse_svg_path :: proc(d: string, allocator := context.allocator) -> (path: ops.Path, ok: bool) {
	b := Svg_Builder {
		verbs  = make([dynamic]ops.Path_Verb, allocator),
		points = make([dynamic]ops.Point, allocator),
	}
	i := 0
	cmd: u8 = 0
	for {
		skip_separators(d, &i)
		if i >= len(d) {
			break
		}
		if ch := d[i]; (ch >= 'A' && ch <= 'Z') || (ch >= 'a' && ch <= 'z') {
			cmd = ch
			i += 1
			if cmd == 'Z' || cmd == 'z' {
				append(&b.verbs, ops.Path_Verb.Close)
				b.cur = b.start
				b.last = cmd
				continue
			}
		}
		if !read_svg_command(&b, d, &i, &cmd) {
			return {b.verbs[:], b.points[:]}, false
		}
	}
	return {b.verbs[:], b.points[:]}, true
}

@(private = "file")
Svg_Builder :: struct {
	verbs:            [dynamic]ops.Path_Verb,
	points:           [dynamic]ops.Point,
	cur, start, ctrl: ops.Point, // ctrl: the last control point, for S and T
	last:             u8, // the previous command
}

// read_svg_command reads one set of cmd's arguments at i and appends the
// segment. A moveto turns cmd into lineto: per SVG 1.1 (paths, 8.3.2),
// further pairs after a moveto are implicit linetos.
@(private = "file")
read_svg_command :: proc(b: ^Svg_Builder, d: string, i: ^int, cmd: ^u8) -> bool {
	c := cmd^
	rel := c >= 'a' && c <= 'z'
	base := rel ? b.cur : ops.Point{}
	switch c {
	case 'M', 'm':
		p := read_svg_point(d, i) or_return
		b.cur = base + p
		b.start = b.cur
		append(&b.verbs, ops.Path_Verb.Move)
		append(&b.points, b.cur)
		cmd^ = rel ? 'l' : 'L'
	case 'L', 'l':
		p := read_svg_point(d, i) or_return
		b.cur = base + p
		append(&b.verbs, ops.Path_Verb.Line)
		append(&b.points, b.cur)
	case 'H', 'h':
		x := read_svg_number(d, i) or_return
		b.cur.x = base.x + x
		append(&b.verbs, ops.Path_Verb.Line)
		append(&b.points, b.cur)
	case 'V', 'v':
		y := read_svg_number(d, i) or_return
		b.cur.y = base.y + y
		append(&b.verbs, ops.Path_Verb.Line)
		append(&b.points, b.cur)
	case 'C', 'c':
		c1 := read_svg_point(d, i) or_return
		c2 := read_svg_point(d, i) or_return
		p := read_svg_point(d, i) or_return
		append_svg_cubic(b, base + c1, base + c2, base + p)
	case 'S', 's':
		c2 := read_svg_point(d, i) or_return
		p := read_svg_point(d, i) or_return
		c1 := b.cur
		if b.last == 'C' || b.last == 'c' || b.last == 'S' || b.last == 's' {
			c1 = 2 * b.cur - b.ctrl
		}
		append_svg_cubic(b, c1, base + c2, base + p)
	case 'Q', 'q', 'T', 't':
		q: ops.Point
		if c == 'Q' || c == 'q' {
			q = base + (read_svg_point(d, i) or_return)
		} else {
			q = b.cur
			if b.last == 'Q' || b.last == 'q' || b.last == 'T' || b.last == 't' {
				q = 2 * b.cur - b.ctrl
			}
		}
		p := base + (read_svg_point(d, i) or_return)
		append_svg_cubic(b, b.cur + (q - b.cur) * (2.0 / 3), p + (q - p) * (2.0 / 3), p)
		b.ctrl = q // the quadratic's own control, for a following T
	case 'A', 'a':
		r := read_svg_point(d, i) or_return
		rotation := read_svg_number(d, i) or_return
		large := read_svg_flag(d, i) or_return
		sweep := read_svg_flag(d, i) or_return
		p := read_svg_point(d, i) or_return
		append_svg_arc(b, r, rotation, large, sweep, base + p)
	case:
		return false
	}
	b.last = c
	return true
}

// append_svg_arc appends the elliptical arc from the current point to p:
// radii r, the ellipse rotated by rotation degrees, large and sweep
// choosing among the four arcs that join the two points. It converts to
// centre form (SVG 1.1 implementation notes, F.6.5), scaling radii too
// small to reach p up as F.6.6 says, and emits a cubic per quarter turn
// at most. A zero radius is a line, and an arc to the current point is
// nothing (F.6.2).
@(private = "file")
append_svg_arc :: proc(b: ^Svg_Builder, r: ops.Point, rotation: f32, large, sweep: bool, p: ops.Point) {
	p0 := b.cur
	if p0 == p {
		return
	}
	rx, ry := abs(r.x), abs(r.y)
	if rx == 0 || ry == 0 {
		append(&b.verbs, ops.Path_Verb.Line)
		append(&b.points, p)
		b.cur = p
		return
	}
	phi := rotation * math.PI / 180
	cos_phi, sin_phi := math.cos(phi), math.sin(phi)
	// F.6.5.1: the midpoint, in the ellipse's own axes.
	h := (p0 - p) / 2
	x1 := cos_phi * h.x + sin_phi * h.y
	y1 := -sin_phi * h.x + cos_phi * h.y
	// F.6.6.2: grow the radii until the ellipse reaches both points.
	lambda := (x1 * x1) / (rx * rx) + (y1 * y1) / (ry * ry)
	if lambda > 1 {
		k := math.sqrt(lambda)
		rx, ry = rx * k, ry * k
	}
	// F.6.5.2: the centre in the ellipse's axes, then back.
	num := rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
	den := rx * rx * y1 * y1 + ry * ry * x1 * x1
	co := math.sqrt(max(num / den, 0))
	if large == sweep {
		co = -co
	}
	cx1, cy1 := co * rx * y1 / ry, -co * ry * x1 / rx
	mid := (p0 + p) / 2
	c := ops.Point{cos_phi * cx1 - sin_phi * cy1 + mid.x, sin_phi * cx1 + cos_phi * cy1 + mid.y}
	// F.6.5.5-6: the start angle and the sweep.
	angle :: proc(u, v: ops.Point) -> f32 {
		return math.atan2(u.x * v.y - u.y * v.x, u.x * v.x + u.y * v.y)
	}
	u := ops.Point{(x1 - cx1) / rx, (y1 - cy1) / ry}
	v := ops.Point{(-x1 - cx1) / rx, (-y1 - cy1) / ry}
	theta := angle({1, 0}, u)
	delta := angle(u, v)
	if !sweep && delta > 0 {
		delta -= 2 * math.PI
	} else if sweep && delta < 0 {
		delta += 2 * math.PI
	}
	n := max(int(math.ceil(abs(delta) / (math.PI / 2) - 1e-4)), 1)
	step := delta / f32(n)
	k := 4.0 / 3.0 * math.tan(step / 4)
	on :: proc(c: ops.Point, rx, ry, cos_phi, sin_phi, t: f32) -> (pt, d: ops.Point) {
		x, y := rx * math.cos(t), ry * math.sin(t)
		dx, dy := -rx * math.sin(t), ry * math.cos(t)
		pt = c + {cos_phi * x - sin_phi * y, sin_phi * x + cos_phi * y}
		d = {cos_phi * dx - sin_phi * dy, sin_phi * dx + cos_phi * dy}
		return
	}
	t := theta
	from, d0 := on(c, rx, ry, cos_phi, sin_phi, t)
	for s in 0 ..< n {
		to, d1 := on(c, rx, ry, cos_phi, sin_phi, t + step)
		if s == n - 1 {
			to = p // land exactly where the path says
		}
		append_svg_cubic(b, from + k * d0, to - k * d1, to)
		from, d0, t = to, d1, t + step
	}
}

// append_svg_cubic appends a cubic to p, remembering c2 for a following S.
@(private = "file")
append_svg_cubic :: proc(b: ^Svg_Builder, c1, c2, p: ops.Point) {
	append(&b.verbs, ops.Path_Verb.Cubic)
	append(&b.points, c1, c2, p)
	b.ctrl = c2
	b.cur = p
}

@(private = "file")
skip_separators :: proc(d: string, i: ^int) {
	for i^ < len(d) && (d[i^] == ' ' || d[i^] == ',' || d[i^] == '\n' || d[i^] == '\t') {
		i^ += 1
	}
}

@(private = "file")
read_svg_number :: proc(d: string, i: ^int) -> (f32, bool) {
	skip_separators(d, i)
	j := i^
	if j < len(d) && (d[j] == '-' || d[j] == '+') {
		j += 1
	}
	dot := false
	for j < len(d) && ((d[j] >= '0' && d[j] <= '9') || (d[j] == '.' && !dot)) {
		if d[j] == '.' {
			dot = true
		}
		j += 1
	}
	if j < len(d) && (d[j] == 'e' || d[j] == 'E') {
		j += 1
		if j < len(d) && (d[j] == '-' || d[j] == '+') {
			j += 1
		}
		for j < len(d) && d[j] >= '0' && d[j] <= '9' {
			j += 1
		}
	}
	if j == i^ {
		return 0, false
	}
	v, ok := strconv.parse_f32(d[i^:j])
	i^ = j
	return v, ok
}

// read_svg_flag reads an arc flag: a single 0 or 1, which SVG lets run
// into what follows (a1 1 0 01.5.5 is flags 0 and 1, then .5 .5).
@(private = "file")
read_svg_flag :: proc(d: string, i: ^int) -> (bool, bool) {
	skip_separators(d, i)
	if i^ >= len(d) || (d[i^] != '0' && d[i^] != '1') {
		return false, false
	}
	on := d[i^] == '1'
	i^ += 1
	return on, true
}

@(private = "file")
read_svg_point :: proc(d: string, i: ^int) -> (p: ops.Point, ok: bool) {
	p.x = read_svg_number(d, i) or_return
	p.y = read_svg_number(d, i) or_return
	return p, true
}
