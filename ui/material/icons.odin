package material

import "core:mem/virtual"
import "core:strconv"
import "jm:ui"

// Icons are Material Symbols (Outlined, and the _fill1 variants), drawn as
// vector paths rather than through an icon font: jm:ui has one text font
// and no font fallback, and a path needs no font file on the target
// machine. icon_data.odin holds each symbol's SVG path data; icon_path
// parses it once into a ui.Path in the symbols' 960-unit space, and icon
// scales that to the requested size.

@(private = "file", thread_local)
cache: [Icon]ui.Path

@(private = "file", thread_local)
parsed: [Icon]bool

@(private = "file", thread_local)
boxes: [Icon]f32

// arena owns every parsed icon for the life of the thread: the cache is
// package state, so it does not borrow whichever allocator its first
// caller happened to have. The cache is per thread, like everything else
// in jm:ui (one Ctx per thread): a shared one raced when two threads
// parsed the same icon, shifting one path's points twice.
@(private = "file", thread_local)
arena: virtual.Arena

// icon_path is i's outline in a box-unit square with its origin at the
// top-left (box is 960 for current symbols, 24 for a few older ones).
// Parsed on first use into a per-thread arena and kept for the life of
// the thread, so the slices outlive every frame that adds them.
icon_path :: proc(i: Icon) -> (path: ui.Path, box: f32) {
	if !parsed[i] {
		data, b := icon_svg(i)
		cache[i], _ = parse_svg_path(data, virtual.arena_allocator(&arena)) // a partial path still draws; the test catches it
		if b == 960 {
			for &q in cache[i].points {
				q.y += 960 // the symbols' viewBox starts at y = -960
			}
		}
		boxes[i] = b
		parsed[i] = true
	}
	return cache[i], boxes[i]
}

// icon fills i at size pixels with its top-left at pos.
icon :: proc(gtx: ^ui.Ctx, i: Icon, pos: ui.Point, size: f32, color: ui.Color) {
	if i == .None || !ui.painted(color) {
		return
	}
	p, box := icon_path(i)
	if len(p.points) == 0 {
		return
	}
	k := size / box
	ui.transform_push(gtx.ops, ui.mul(ui.scale(k, k), ui.translate(pos.x, pos.y)))
	ui.fill(gtx.ops, ui.Path_Ref{ui.add_path(gtx.ops, p)}, color)
	ui.transform_pop(gtx.ops)
}

// parse_svg_path turns SVG path data into a ui.Path. It handles M L H V
// C S Q T Z in both cases, which covers every symbol in icon_data.odin
// (test_every_icon_parses checks each one); quadratics become cubics. ok
// is false when it met anything else, such as an A (arc), and stopped
// there.
parse_svg_path :: proc(d: string, allocator := context.allocator) -> (path: ui.Path, ok: bool) {
	b := Svg_Builder {
		verbs  = make([dynamic]ui.Path_Verb, allocator),
		points = make([dynamic]ui.Point, allocator),
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
				append(&b.verbs, ui.Path_Verb.Close)
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
	verbs:             [dynamic]ui.Path_Verb,
	points:            [dynamic]ui.Point,
	cur, start, ctrl:  ui.Point, // ctrl: the last control point, for S and T
	last:              u8, // the previous command
}

// read_svg_command reads one set of cmd's arguments at i and appends the
// segment. A moveto turns cmd into lineto: per SVG 1.1 (paths, 8.3.2),
// further pairs after a moveto are implicit linetos.
@(private = "file")
read_svg_command :: proc(b: ^Svg_Builder, d: string, i: ^int, cmd: ^u8) -> bool {
	c := cmd^
	rel := c >= 'a' && c <= 'z'
	base := rel ? b.cur : ui.Point{}
	switch c {
	case 'M', 'm':
		p := svg_point(d, i) or_return
		b.cur = base + p
		b.start = b.cur
		append(&b.verbs, ui.Path_Verb.Move)
		append(&b.points, b.cur)
		cmd^ = rel ? 'l' : 'L'
	case 'L', 'l':
		p := svg_point(d, i) or_return
		b.cur = base + p
		append(&b.verbs, ui.Path_Verb.Line)
		append(&b.points, b.cur)
	case 'H', 'h':
		x := svg_number(d, i) or_return
		b.cur.x = base.x + x
		append(&b.verbs, ui.Path_Verb.Line)
		append(&b.points, b.cur)
	case 'V', 'v':
		y := svg_number(d, i) or_return
		b.cur.y = base.y + y
		append(&b.verbs, ui.Path_Verb.Line)
		append(&b.points, b.cur)
	case 'C', 'c':
		c1 := svg_point(d, i) or_return
		c2 := svg_point(d, i) or_return
		p := svg_point(d, i) or_return
		append_svg_cubic(b, base + c1, base + c2, base + p)
	case 'S', 's':
		c2 := svg_point(d, i) or_return
		p := svg_point(d, i) or_return
		c1 := b.cur
		if b.last == 'C' || b.last == 'c' || b.last == 'S' || b.last == 's' {
			c1 = 2 * b.cur - b.ctrl
		}
		append_svg_cubic(b, c1, base + c2, base + p)
	case 'Q', 'q', 'T', 't':
		q: ui.Point
		if c == 'Q' || c == 'q' {
			q = base + (svg_point(d, i) or_return)
		} else {
			q = b.cur
			if b.last == 'Q' || b.last == 'q' || b.last == 'T' || b.last == 't' {
				q = 2 * b.cur - b.ctrl
			}
		}
		p := base + (svg_point(d, i) or_return)
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
append_svg_cubic :: proc(b: ^Svg_Builder, c1, c2, p: ui.Point) {
	append(&b.verbs, ui.Path_Verb.Cubic)
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
svg_number :: proc(d: string, i: ^int) -> (f32, bool) {
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
svg_point :: proc(d: string, i: ^int) -> (p: ui.Point, ok: bool) {
	p.x = svg_number(d, i) or_return
	p.y = svg_number(d, i) or_return
	return p, true
}
