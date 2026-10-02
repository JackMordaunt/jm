package glyf

// vary adds to out (n points, the 4 phantom points last) the deltas
// 'gvar' gives glyph at coords. orig and ends are a simple glyph's points
// before variation and its contour ends (absolute: base is orig[0]'s
// index), from which deltas a tuple leaves out are interpolated; a
// composite passes none, and a component a tuple leaves out does not
// move. A glyph gvar has no data for does not vary.
@(private)
vary :: proc(f: ^Font, glyph: u16, coords: ^Coords, n: int, orig: []Point, ends: []u16, base: int, out: []Point, s: ^Scratch) -> bool {
	h := Reader{data = f.gvar, pos = 4}
	axis_count := int(read_u16(&h))
	shared_count := int(read_u16(&h))
	shared_at := int(read_u32(&h))
	glyph_count := int(read_u16(&h))
	long := read_u16(&h) & 1 != 0
	array_at := int(read_u32(&h))
	if h.bad || axis_count != f.axis_count || int(glyph) >= glyph_count {
		return !h.bad
	}
	start, end: int
	if long {
		h.pos = 20 + 4 * int(glyph)
		start, end = int(read_u32(&h)), int(read_u32(&h))
	} else {
		h.pos = 20 + 2 * int(glyph)
		start, end = 2 * int(read_u16(&h)), 2 * int(read_u16(&h))
	}
	start, end = array_at + start, array_at + end
	if h.bad || start > end || end > len(f.gvar) {
		return false
	}
	if start == end {
		return true
	}
	data := f.gvar[start:end]
	r := Reader{data = data}
	header := read_u16(&r)
	serial := Reader{data = data, pos = int(read_u16(&r))}
	shared_all, shared_n := true, 0
	if header & 0x8000 != 0 {
		shared_all, shared_n = read_points(&serial, s.shared[:])
	}
	for _ in 0 ..< int(header & 0x0FFF) {
		size := int(read_u16(&r))
		index := read_u16(&r)
		peak, lo, hi: [MAX_AXES]f32
		if index & 0x8000 != 0 {
			read_tuple(&r, peak[:axis_count])
		} else {
			if int(index & 0x0FFF) >= shared_count {
				return false
			}
			t := Reader{data = f.gvar, pos = shared_at + 2 * axis_count * int(index & 0x0FFF)}
			read_tuple(&t, peak[:axis_count])
			if t.bad {
				return false
			}
		}
		intermediate := index & 0x4000 != 0
		if intermediate {
			read_tuple(&r, lo[:axis_count])
			read_tuple(&r, hi[:axis_count])
		}
		if r.bad || serial.pos + size > len(data) {
			return false
		}
		t := Reader{data = data[:serial.pos + size], pos = serial.pos}
		serial.pos += size
		scalar := tuple_scalar(coords[:axis_count], peak[:axis_count], lo[:axis_count], hi[:axis_count], intermediate)
		if scalar == 0 {
			continue
		}
		all, count := shared_all, shared_n
		points := s.shared[:]
		if index & 0x2000 != 0 {
			all, count = read_points(&t, s.private[:])
			points = s.private[:]
		}
		if all {
			count = n
		}
		deltas := s.deltas[:2 * count]
		read_deltas(&t, deltas)
		if t.bad {
			return false
		}
		apply_tuple(s, scalar, all, points[:count], deltas, orig, ends, base, out)
	}
	return !r.bad
}

// apply_tuple adds scalar times one tuple's deltas (all x, then all y,
// one pair per point named) to out.
@(private)
apply_tuple :: proc(s: ^Scratch, scalar: f32, all: bool, points: []u16, deltas: []f32, orig: []Point, ends: []u16, base: int, out: []Point) {
	count := len(deltas) / 2
	if all {
		for i in 0 ..< count {
			out[i] += scalar * Point{deltas[i], deltas[count + i]}
		}
		return
	}
	if orig == nil {
		for p, i in points {
			if int(p) < len(out) {
				out[p] += scalar * Point{deltas[i], deltas[count + i]}
			}
		}
		return
	}
	tuple, touched := s.tuple[:len(out)], s.touched[:len(out)]
	for i in 0 ..< len(out) {
		tuple[i], touched[i] = {}, false
	}
	for p, i in points {
		if int(p) < len(out) {
			tuple[p], touched[p] = {deltas[i], deltas[count + i]}, true
		}
	}
	first := 0
	for e in ends {
		last := int(e) - base
		iup_contour(orig, tuple, touched, first, last)
		first = last + 1
	}
	for d, i in tuple {
		out[i] += scalar * d
	}
}

// iup_contour infers the deltas of contour [first, last]'s untouched
// points from the touched points either side, as the OpenType spec's
// "Inferred deltas for un-referenced point numbers" describes: a point
// between its neighbours' original coordinates is interpolated, one
// outside takes the nearer neighbour's delta. A contour with no touched
// point does not move.
@(private)
iup_contour :: proc(orig, tuple: []Point, touched: []bool, first, last: int) {
	start := -1
	for i in first ..= last {
		if touched[i] {
			start = i
			break
		}
	}
	if start < 0 {
		return
	}
	n := last - first + 1
	prev := start
	for k in 1 ..= n {
		i := first + (start - first + k) % n
		if !touched[i] {
			continue
		}
		for j := first + (prev - first + 1) % n; j != i; j = first + (j - first + 1) % n {
			for axis in 0 ..< 2 {
				tuple[j][axis] = iup_axis(orig[j][axis], orig[prev][axis], orig[i][axis], tuple[prev][axis], tuple[i][axis])
			}
		}
		prev = i
	}
}

// iup_axis is the delta of coordinate v between reference coordinates a
// and b with deltas da and db.
@(private)
iup_axis :: proc(v, a, b, da, db: f32) -> f32 {
	a, b, da, db := a, b, da, db
	if a == b {
		return da if da == db else 0
	}
	if a > b {
		a, b, da, db = b, a, db, da
	}
	if v <= a {
		return da
	}
	if v >= b {
		return db
	}
	return da + (v - a) * (db - da) / (b - a)
}

// tuple_scalar is how much of a tuple's deltas apply at coords: 1 at its
// peak, falling linearly to 0 at its region's edges.
@(private)
tuple_scalar :: proc(coords, peak, lo, hi: []f32, intermediate: bool) -> f32 {
	scalar: f32 = 1
	for p, i in peak {
		v := coords[i]
		if p == 0 || v == p {
			continue
		}
		if !intermediate {
			if v == 0 || v < min(0, p) || v > max(0, p) {
				return 0
			}
			scalar *= v / p
			continue
		}
		a, b := lo[i], hi[i]
		if a > p || p > b || (a < 0 && b > 0) {
			continue // a malformed region does not narrow the tuple
		}
		if v <= a || v >= b {
			return 0
		}
		scalar *= (v - a) / (p - a) if v < p else (b - v) / (b - p)
	}
	return scalar
}

@(private)
read_tuple :: proc(r: ^Reader, out: []f32) {
	for &v in out {
		v = read_f2dot14(r)
	}
}

// read_points reads packed point numbers into out: all is true for the
// "every point" form, which names none.
@(private)
read_points :: proc(r: ^Reader, out: []u16) -> (all: bool, count: int) {
	b := int(read_u8(r))
	if b == 0 {
		return true, 0
	}
	count = b
	if b & 0x80 != 0 {
		count = (b & 0x7F) << 8 | int(read_u8(r))
	}
	if count > len(out) {
		r.bad = true
		return false, 0
	}
	p: u16
	for i := 0; i < count && !r.bad; {
		control := read_u8(r)
		for _ in 0 ..< int(control & 0x7F) + 1 {
			if i == count {
				break
			}
			p += read_u16(r) if control & 0x80 != 0 else u16(read_u8(r))
			out[i] = p
			i += 1
		}
	}
	return false, count
}

// read_deltas reads packed deltas until out is full: runs of zeros,
// bytes, words or, for the 0xC0 form, longs.
@(private)
read_deltas :: proc(r: ^Reader, out: []f32) {
	for i := 0; i < len(out) && !r.bad; {
		control := read_u8(r)
		for _ in 0 ..< int(control & 0x3F) + 1 {
			if i == len(out) {
				break
			}
			switch control & 0xC0 {
			case 0x80:
				out[i] = 0
			case 0x40:
				out[i] = f32(i16(read_u16(r)))
			case 0xC0:
				out[i] = f32(i32(read_u32(r)))
			case:
				out[i] = f32(i8(read_u8(r)))
			}
			i += 1
		}
	}
}

// Reader reads big-endian values; a read past the end yields 0 and sets
// bad, which stays set.
@(private)
Reader :: struct {
	data: []byte,
	pos:  int,
	bad:  bool,
}

@(private)
read_u8 :: proc(r: ^Reader) -> u8 {
	if r.pos < 0 || r.pos + 1 > len(r.data) {
		r.bad = true
		return 0
	}
	r.pos += 1
	return r.data[r.pos - 1]
}

@(private)
read_u16 :: proc(r: ^Reader) -> u16 {
	return u16(read_u8(r)) << 8 | u16(read_u8(r))
}

@(private)
read_u32 :: proc(r: ^Reader) -> u32 {
	return u32(read_u16(r)) << 16 | u32(read_u16(r))
}

@(private)
read_f2dot14 :: proc(r: ^Reader) -> f32 {
	return f32(i16(read_u16(r))) / 16384
}

@(private)
read_fixed :: proc(r: ^Reader) -> f32 {
	return f32(i32(read_u32(r))) / 65536
}
