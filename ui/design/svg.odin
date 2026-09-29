package design

import "core:strconv"
import "jm:ui/ops"

// parse_svg_path turns SVG path data into an ops.Path. It handles M L H
// V C S Q T Z in both cases, which covers every icon the systems on
// jm:ui draw (each system's icon test checks its own set); quadratics
// become cubics. ok is false when it met anything else, such as an A
// (arc), and stopped there; the partial path still draws.
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
	case:
		return false
	}
	b.last = c
	return true
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

@(private = "file")
read_svg_point :: proc(d: string, i: ^int) -> (p: ops.Point, ok: bool) {
	p.x = read_svg_number(d, i) or_return
	p.y = read_svg_number(d, i) or_return
	return p, true
}
