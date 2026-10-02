/*
Package glyf decodes TrueType glyph outlines (the 'glyf' and 'loca'
tables) at a variable font's chosen axis values, applying its 'gvar'
deltas. jm:ui/render draws glyphs with Blend2D, which reads 'glyf' but
not 'gvar': at the revision the justfile builds (blend2d_rev, 3525b5f),
font.cpp stores a font's variation settings and no source under
src/blend2d/opentype reads them or the 'gvar' table, so SFNS.ttf at wght
400 and 700 fills identical pixels. Without this package a variable font
draws its default instance whatever weight a Font_Ref asks for.

	f: glyf.Font
	if glyf.font_init(&f, tables) {
		coords := glyf.coords(&f, {{glyf.WGHT, 600}})
		o, ok := glyf.outline(&f, glyph_id, coords, &scratch)
	}

Outlines are in font units, y up, as 'glyf' stores them: quadratic
contours whose on_curve flags say which points the curve passes through.
Hinting instructions are skipped.

Memory: nothing allocates. A Font borrows its tables' bytes. outline
writes into a caller's Scratch (about 150 KiB, so a caller keeps one rather
than putting it on a stack), and the Outline it returns points into it
until the next call.
*/
package glyf

import "jm:ui/ops"

// MAX_AXES bounds the variation axes read from a font; SFNS.ttf has 4
// (wdth, opsz, GRAD, wght). A font with more varies along none.
MAX_AXES :: 16
// MAX_POINTS bounds the outline points of one glyph, its components'
// together; a glyph with more fails to decode rather than overrunning.
MAX_POINTS :: 4096
MAX_CONTOURS :: 1024
// MAX_COMPONENTS bounds the components of one composite glyph.
MAX_COMPONENTS :: 64
// MAX_DEPTH bounds composite nesting, so a font whose composites refer to
// each other in a cycle fails instead of recursing forever.
MAX_DEPTH :: 8

// WGHT is the tag of the weight axis.
WGHT :: u32('w') << 24 | u32('g') << 16 | u32('h') << 8 | u32('t')

Point :: ops.Point

// Tables are the font tables this package reads, each the table's bytes;
// gvar, fvar and avar are empty for a font that does not vary.
Tables :: struct {
	head, loca, glyf, gvar, fvar, avar: []byte,
}

Axis :: struct {
	tag:                u32,
	min, default, max: f32,
}

// Font is a font's tables, checked once by font_init.
Font :: struct {
	using tables: Tables,
	loca_long:    bool,
	glyph_count:  int,
	units_per_em: f32,
	axes:         [MAX_AXES]Axis,
	axis_count:   int,
}

// Coords are a point in a font's variation space, one normalized value in
// [-1, 1] per axis in the font's 'fvar' order; all zero is the default
// instance.
Coords :: [MAX_AXES]f32

// Setting is a user-space value for one axis, as CSS's
// font-variation-settings names one: {WGHT, 600}.
Setting :: struct {
	tag:   u32,
	value: f32,
}

// Outline is one glyph's contours: ends[i] is the index of contour i's
// last point.
Outline :: struct {
	points:   []Point,
	on_curve: []bool,
	ends:     []u16,
}

// Scratch holds an outline being decoded and the temporaries its
// variations need.
Scratch :: struct {
	points:     [MAX_POINTS]Point,
	on_curve:   [MAX_POINTS]bool,
	ends:       [MAX_CONTOURS]u16,
	n_points:   int,
	n_contours: int,
	shift:      f32, // the first phantom point's x delta: where the origin moved
	// per-glyph variation temporaries, phantom points included
	accum:      [MAX_POINTS + 4]Point,
	tuple:      [MAX_POINTS + 4]Point,
	touched:    [MAX_POINTS + 4]bool,
	shared:     [MAX_POINTS + 4]u16,
	private:    [MAX_POINTS + 4]u16,
	deltas:     [2 * (MAX_POINTS + 4)]f32,
}

// font_init checks t and reads the font's axes; false when head, loca or
// glyf is missing or malformed. A font with no 'fvar' has no axes, and
// every outline is its one instance.
font_init :: proc(f: ^Font, t: Tables) -> bool {
	f^ = {}
	f.tables = t
	head := Reader{data = t.head, pos = 18}
	f.units_per_em = f32(read_u16(&head))
	head.pos = 50
	loc_format := read_u16(&head)
	if head.bad || f.units_per_em == 0 || len(t.glyf) == 0 {
		return false
	}
	f.loca_long = loc_format == 1
	f.glyph_count = len(t.loca) / (4 if f.loca_long else 2) - 1
	if f.glyph_count <= 0 {
		return false
	}
	read_axes(f)
	return true
}

// read_axes fills f.axes from 'fvar'; a malformed table leaves none.
@(private)
read_axes :: proc(f: ^Font) {
	r := Reader{data = f.fvar}
	r.pos = 4
	axes_at := int(read_u16(&r))
	r.pos += 2
	count := int(read_u16(&r))
	size := int(read_u16(&r))
	if r.bad || size < 16 || count > MAX_AXES {
		return
	}
	for i in 0 ..< count {
		a := Reader{data = f.fvar, pos = axes_at + i * size}
		axis := Axis{tag = read_u32(&a)}
		axis.min = read_fixed(&a)
		axis.default = read_fixed(&a)
		axis.max = read_fixed(&a)
		if a.bad {
			return
		}
		f.axes[i] = axis
	}
	f.axis_count = count
}

// has_axis reports whether f varies along the axis tagged tag.
has_axis :: proc(f: ^Font, tag: u32) -> bool {
	for a in f.axes[:f.axis_count] {
		if a.tag == tag {
			return true
		}
	}
	return false
}

// coords is the normalized point for settings, each clamped to its axis'
// range; an axis not named stays at its default and a tag the font lacks
// is ignored. 'avar' remaps the result, which is then rounded to the
// F2Dot14 grid gvar's tuples are given on, so a coordinate at a tuple's
// peak equals it exactly.
coords :: proc(f: ^Font, settings: []Setting) -> Coords {
	c: Coords
	for a, i in f.axes[:f.axis_count] {
		v := a.default
		for s in settings {
			if s.tag == a.tag {
				v = clamp(s.value, a.min, a.max)
			}
		}
		n: f32
		if v < a.default && a.default > a.min {
			n = (v - a.default) / (a.default - a.min)
		} else if v > a.default && a.max > a.default {
			n = (v - a.default) / (a.max - a.default)
		}
		n = avar_map(f, i, n)
		c[i] = f32(i32(n * 16384 + (0.5 if n >= 0 else -0.5))) / 16384
	}
	return c
}

// avar_map applies axis' 'avar' segment map to normalized n.
@(private)
avar_map :: proc(f: ^Font, axis: int, n: f32) -> f32 {
	r := Reader{data = f.avar, pos = 6}
	if int(read_u16(&r)) != f.axis_count {
		return n
	}
	for _ in 0 ..< axis {
		r.pos += 4 * int(read_u16(&r))
	}
	count := int(read_u16(&r))
	if r.bad || count == 0 {
		return n
	}
	prev_from, prev_to: f32
	for i in 0 ..< count {
		from, to := read_f2dot14(&r), read_f2dot14(&r)
		if r.bad {
			return n
		}
		if i == 0 && n <= from {
			return n - from + to
		}
		if n < from {
			return prev_to + (n - prev_from) * (to - prev_to) / (from - prev_from)
		}
		prev_from, prev_to = from, to
	}
	return n - prev_from + prev_to
}

// outline decodes glyph at coords into s; false when the glyph is out of
// range or its data is malformed. An empty glyph (a space) is no contours.
outline :: proc(f: ^Font, glyph: u16, coords: Coords, s: ^Scratch) -> (Outline, bool) {
	s.n_points, s.n_contours, s.shift = 0, 0, 0
	c := coords
	ok := load(f, glyph, &c, s, 0)
	if !ok {
		return {}, false
	}
	if s.shift != 0 {
		for &p in s.points[:s.n_points] {
			p.x -= s.shift
		}
	}
	return {s.points[:s.n_points], s.on_curve[:s.n_points], s.ends[:s.n_contours]}, true
}

// glyph_data is glyph's record in 'glyf', empty for a glyph with none.
@(private)
glyph_data :: proc(f: ^Font, glyph: u16) -> ([]byte, bool) {
	g := int(glyph)
	if g >= f.glyph_count {
		return nil, false
	}
	r := Reader{data = f.loca}
	start, end: int
	if f.loca_long {
		r.pos = 4 * g
		start, end = int(read_u32(&r)), int(read_u32(&r))
	} else {
		r.pos = 2 * g
		start, end = 2 * int(read_u16(&r)), 2 * int(read_u16(&r))
	}
	if r.bad || start > end || end > len(f.glyf) {
		return nil, false
	}
	return f.glyf[start:end], true
}

// load appends glyph's points and contours to s, varied by coords.
@(private)
load :: proc(f: ^Font, glyph: u16, coords: ^Coords, s: ^Scratch, depth: int) -> bool {
	if depth > MAX_DEPTH {
		return false
	}
	data := glyph_data(f, glyph) or_return
	if len(data) == 0 {
		return true
	}
	r := Reader{data = data}
	contours := i16(read_u16(&r))
	if r.bad {
		return false
	}
	if contours < 0 {
		return load_composite(f, glyph, data, coords, s, depth)
	}
	base, first_end := s.n_points, s.n_contours
	n := decode_simple(data, int(contours), s) or_return
	if !varies(f, coords) {
		return true
	}
	accum := s.accum[:n + 4]
	for &d in accum {
		d = {}
	}
	ends := s.ends[first_end:s.n_contours]
	vary(f, glyph, coords, n + 4, s.points[base:base + n], ends, base, accum, s) or_return
	for i in 0 ..< n {
		s.points[base + i] += accum[i]
	}
	if depth == 0 {
		s.shift = accum[n].x
	}
	return true
}

// varies reports whether coords move f off its default instance.
@(private)
varies :: proc(f: ^Font, coords: ^Coords) -> bool {
	if len(f.gvar) == 0 {
		return false
	}
	for c in coords[:f.axis_count] {
		if c != 0 {
			return true
		}
	}
	return false
}

// decode_simple appends a simple glyph's points and contour ends to s and
// returns how many points it has.
@(private)
decode_simple :: proc(data: []byte, contours: int, s: ^Scratch) -> (int, bool) {
	base := s.n_points
	if s.n_contours + contours > MAX_CONTOURS {
		return 0, false
	}
	r := Reader{data = data, pos = 10}
	n := 0
	for i in 0 ..< contours {
		end := int(read_u16(&r)) + 1
		if end < n {
			return 0, false
		}
		n = end
		s.ends[s.n_contours + i] = u16(base + end - 1)
	}
	if r.bad || base + n > MAX_POINTS || (contours > 0 && base + n - 1 > int(max(u16))) {
		return 0, false
	}
	r.pos += int(read_u16(&r)) // instructions
	flags: [MAX_POINTS]u8
	for i := 0; i < n; {
		fl := read_u8(&r)
		repeat := int(read_u8(&r)) if fl & 8 != 0 else 0
		for _ in 0 ..= repeat {
			if i < n {
				flags[i] = fl
				i += 1
			}
		}
		if r.bad {
			return 0, false
		}
	}
	x, y: f32
	for i in 0 ..< n {
		x += read_coord(&r, flags[i], 0x02, 0x10)
		s.points[base + i].x = x
		s.on_curve[base + i] = flags[i] & 1 != 0
	}
	for i in 0 ..< n {
		y += read_coord(&r, flags[i], 0x04, 0x20)
		s.points[base + i].y = y
	}
	if r.bad {
		return 0, false
	}
	s.n_points += n
	s.n_contours += contours
	return n, true
}

// read_coord reads one x or y delta of a simple glyph: short is the flag
// bit for a byte, same the bit for a positive byte or, with short clear,
// a repeat of the last value.
@(private)
read_coord :: proc(r: ^Reader, flag, short, same: u8) -> f32 {
	if flag & short != 0 {
		d := f32(read_u8(r))
		return d if flag & same != 0 else -d
	}
	if flag & same != 0 {
		return 0
	}
	return f32(i16(read_u16(r)))
}

@(private)
Component :: struct {
	glyph:    u16,
	flags:    u16,
	arg:      [2]i32,
	m:        [4]f32, // x' = m[0]x + m[2]y, y' = m[1]x + m[3]y
}

// load_composite appends each component of a composite glyph to s,
// placed by its offset (varied by the glyph's own gvar deltas, one per
// component) or by matching a point of its own to one placed before it.
@(private)
load_composite :: proc(f: ^Font, glyph: u16, data: []byte, coords: ^Coords, s: ^Scratch, depth: int) -> bool {
	comps: [MAX_COMPONENTS]Component
	n := read_components(data, comps[:]) or_return
	deltas: [MAX_COMPONENTS + 4]Point
	if varies(f, coords) {
		vary(f, glyph, coords, n + 4, nil, nil, 0, deltas[:n + 4], s) or_return
	}
	base := s.n_points
	for c, i in comps[:n] {
		first := s.n_points
		load(f, c.glyph, coords, s, depth + 1) or_return
		pts := s.points[first:s.n_points]
		for &p in pts {
			p = {c.m[0] * p.x + c.m[2] * p.y, c.m[1] * p.x + c.m[3] * p.y}
		}
		off: Point
		if c.flags & ARGS_ARE_XY_VALUES != 0 {
			off = Point{f32(c.arg[0]), f32(c.arg[1])} + deltas[i]
			if c.flags & SCALED_COMPONENT_OFFSET != 0 && c.flags & UNSCALED_COMPONENT_OFFSET == 0 {
				off = {c.m[0] * off.x + c.m[2] * off.y, c.m[1] * off.x + c.m[3] * off.y}
			}
		} else {
			parent, child := base + int(c.arg[0]), first + int(c.arg[1])
			if parent >= first || child >= s.n_points {
				return false
			}
			off = s.points[parent] - s.points[child]
		}
		for &p in pts {
			p += off
		}
	}
	if depth == 0 {
		s.shift = deltas[n].x
	}
	return true
}

@(private)
ARG_1_AND_2_ARE_WORDS :: 0x0001
@(private)
ARGS_ARE_XY_VALUES :: 0x0002
@(private)
WE_HAVE_A_SCALE :: 0x0008
@(private)
MORE_COMPONENTS :: 0x0020
@(private)
WE_HAVE_AN_X_AND_Y_SCALE :: 0x0040
@(private)
WE_HAVE_A_TWO_BY_TWO :: 0x0080
@(private)
SCALED_COMPONENT_OFFSET :: 0x0800
@(private)
UNSCALED_COMPONENT_OFFSET :: 0x1000

// read_components fills comps from a composite glyph record.
@(private)
read_components :: proc(data: []byte, comps: []Component) -> (int, bool) {
	r := Reader{data = data, pos = 10}
	n := 0
	for {
		if n == len(comps) {
			return 0, false
		}
		c := Component{m = {1, 0, 0, 1}}
		c.flags = read_u16(&r)
		c.glyph = read_u16(&r)
		words, xy := c.flags & ARG_1_AND_2_ARE_WORDS != 0, c.flags & ARGS_ARE_XY_VALUES != 0
		for &a in c.arg {
			switch {
			case words && xy:
				a = i32(i16(read_u16(&r)))
			case words:
				a = i32(read_u16(&r))
			case xy:
				a = i32(i8(read_u8(&r)))
			case:
				a = i32(read_u8(&r))
			}
		}
		if c.flags & WE_HAVE_A_SCALE != 0 {
			c.m[0] = read_f2dot14(&r)
			c.m[3] = c.m[0]
		} else if c.flags & WE_HAVE_AN_X_AND_Y_SCALE != 0 {
			c.m[0], c.m[3] = read_f2dot14(&r), read_f2dot14(&r)
		} else if c.flags & WE_HAVE_A_TWO_BY_TWO != 0 {
			c.m = {read_f2dot14(&r), read_f2dot14(&r), read_f2dot14(&r), read_f2dot14(&r)}
		}
		if r.bad {
			return 0, false
		}
		comps[n] = c
		n += 1
		if c.flags & MORE_COMPONENTS == 0 {
			return n, true
		}
	}
}
