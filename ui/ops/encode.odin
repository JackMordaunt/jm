package ops

import "core:encoding/endian"
import "core:mem"

// Binary wire form of Scene. Little-endian throughout:
//
//	"UIOP" u8(version)
//	fonts   u32 n, n × (u32 id, str path, f32 weight)
//	images  u32 n, n × (u32 id, str path)
//	paths   u32 n, n × (u32 n, n × u8 verb; u32 n, n × (f32 x, f32 y); u8 rule)
//	runs    u32 n, n × (u32 font, f32 size, u32 n, n × (u32 id, u32 cluster, f32 x, f32 y, u32 font), f32 advance)
//	macros  u32 n, n × (i64 first, i64 last)
//	ops     u32 n, n × (u8 tag, payload)
//
// str is u32 length then bytes. Unions (Op, Shape, Paint) are a u8 tag, 0
// for nil and then the variant's position in the union from 1, followed by
// the variant's fields in declaration order. Floats are their raw bits.

ENCODE_MAGIC :: "UIOP"
// ENCODE_VERSION changes whenever an op is added or its layout changes: a
// decoder built against another version rejects the stream outright (see
// encoded_version) rather than failing on the first unknown tag. 2 added
// Defer; 8 gave Defer its Placement; 9 added Shadow; 10 gave Glyph its
// cluster; 11 its font; 12 gave Input_Area a cursor and Event_Kind Paste;
// 13 Input_Area yields and Event_Kind Cancel; 14 turned yields into a
// flags byte, bit 0 yields and bit 1 observes; 15 gave Defer cover and
// covers and added Cover_End; 20 gave Defer top, bit 1 of its cover byte;
// 21 added Key Browser_Back and Browser_Forward; 22 gave each font its
// weight; 23 gave each Image an alpha; 24 gave Semantic a heading level
// and Role Region; 25 added Push_Sticky; 26 gave Placement its nudge,
// inside, overhang and fallbacks; 27 added Event_Kind Outside and
// Key_Interest topmost; 28 added Focus_Scope and Focus_Scope_End; 29
// added Push_Opacity and Pop_Opacity; 30 gave Semantic an active
// descendant and Role Menu_Item_Checkbox and Menu_Item_Radio; 31 added
// Role Tree, Tree_Item and Tab_Panel and State Current and Current_Page;
// 32 turned Focus_Scope's trap into a flags byte (bit 0 trap, bit 1
// wrap, bits 2-3 rove) and gave Focus_Scope_End an entry; 33 gave
// Input_Area's flags no_tab, bit 2; 34 gave Path its fill rule.
ENCODE_VERSION :: u8(34)

// encoded_version is the version byte of an encoded stream, false when
// data does not start with ENCODE_MAGIC and a version.
encoded_version :: proc(data: []byte) -> (u8, bool) {
	if len(data) < len(ENCODE_MAGIC) + 1 || string(data[:len(ENCODE_MAGIC)]) != ENCODE_MAGIC {
		return 0, false
	}
	return data[len(ENCODE_MAGIC)], true
}

// encode serializes ops, resources included, into a new byte slice.
encode :: proc(ops: ^Scene, allocator := context.allocator) -> []byte {
	w := make([dynamic]byte, 0, 256, allocator)
	for c in transmute([]byte)string(ENCODE_MAGIC) {
		append(&w, c)
	}
	append(&w, ENCODE_VERSION)

	put_u32(&w, u32(len(ops.fonts)))
	for f in ops.fonts {
		put_u32(&w, u32(f.id))
		put_str(&w, f.path)
		put_f32(&w, f.weight)
	}
	put_u32(&w, u32(len(ops.images)))
	for im in ops.images {
		put_u32(&w, u32(im.id))
		put_str(&w, im.path)
	}
	put_u32(&w, u32(len(ops.paths)))
	for p in ops.paths {
		put_u32(&w, u32(len(p.verbs)))
		for v in p.verbs {
			append(&w, u8(v))
		}
		put_u32(&w, u32(len(p.points)))
		for q in p.points {
			put_point(&w, q)
		}
		append(&w, u8(p.rule))
	}
	put_u32(&w, u32(len(ops.runs)))
	for r in ops.runs {
		put_u32(&w, u32(r.font))
		put_f32(&w, r.size)
		put_u32(&w, u32(len(r.glyphs)))
		for g in r.glyphs {
			put_u32(&w, g.id)
			put_u32(&w, g.cluster)
			put_f32(&w, g.x)
			put_f32(&w, g.y)
			put_u32(&w, u32(g.font))
		}
		put_f32(&w, r.advance)
	}
	put_u32(&w, u32(len(ops.macros)))
	for m in ops.macros {
		put_u64(&w, u64(i64(m.first)))
		put_u64(&w, u64(i64(m.last)))
	}
	put_u32(&w, u32(len(ops.ops)))
	for op in ops.ops {
		put_op(&w, op)
	}
	return w[:]
}

// decode reads an encoded stream into ops, which is emptied first (fonts
// and images too: the stream is authoritative). Its slices and strings live
// in ops' own decode arena until the next decode into ops resets it, so a
// decoded frame is valid until then and none of it accumulates. It returns false on truncation, bad magic
// or version, an unknown tag or enum value, trailing bytes, or a reference
// (path, run, macro) out of range; ops then holds a partial decode. It never
// panics on hostile input.
decode :: proc(data: []byte, ops: ^Scene) -> bool {
	reset(ops)
	clear(&ops.fonts)
	free_images(ops)
	if !ops.has_decoded {
		if frame_arena_init(&ops.decoded) != nil {
			return false
		}
		ops.has_decoded = true
	}
	frame_arena_reset(&ops.decoded)
	a := frame_arena_allocator(&ops.decoded)
	r := Reader {
		data      = data,
		allocator = a,
	}
	for c in transmute([]byte)string(ENCODE_MAGIC) {
		if b, ok := get_u8(&r); !ok || b != c {
			return false
		}
	}
	if v, ok := get_u8(&r); !ok || v != ENCODE_VERSION {
		return false
	}

	// Every entry takes at least one byte, which bounds each count by what
	// is left and keeps a hostile count from forcing a huge allocation.
	n: int
	ok: bool
	if n, ok = get_count(&r, 1); !ok {
		return false
	}
	for _ in 0 ..< n {
		id := get_u32(&r) or_return
		path := get_str(&r) or_return
		weight := get_f32(&r) or_return
		append(&ops.fonts, Font_Ref{Font_Id(id), path, weight})
	}
	if n, ok = get_count(&r, 1); !ok {
		return false
	}
	for _ in 0 ..< n {
		id := get_u32(&r) or_return
		path := get_str(&r) or_return
		append(&ops.images, Image_Ref{Image_Id(id), own_path(ops, path)})
	}
	if n, ok = get_count(&r, 1); !ok {
		return false
	}
	for _ in 0 ..< n {
		nv := get_count(&r, 1) or_return
		verbs := make([]Path_Verb, nv, a)
		for &v in verbs {
			b := get_u8(&r) or_return
			if b > u8(max(Path_Verb)) {
				return false
			}
			v = Path_Verb(b)
		}
		np := get_count(&r, 8) or_return
		points := make([]Point, np, a)
		for &q in points {
			q = get_point(&r) or_return
		}
		rule := get_u8(&r) or_return
		if rule > u8(max(Fill_Rule)) {
			return false
		}
		append(&ops.paths, Path{verbs = verbs, points = points, rule = Fill_Rule(rule)})
	}
	if n, ok = get_count(&r, 1); !ok {
		return false
	}
	for _ in 0 ..< n {
		run: Glyph_Run
		run.font = Font_Id(get_u32(&r) or_return)
		run.size = get_f32(&r) or_return
		ng := get_count(&r, 20) or_return
		run.glyphs = make([]Glyph, ng, a)
		for &g in run.glyphs {
			g.id = get_u32(&r) or_return
			g.cluster = get_u32(&r) or_return
			g.x = get_f32(&r) or_return
			g.y = get_f32(&r) or_return
			g.font = Font_Id(get_u32(&r) or_return)
		}
		run.advance = get_f32(&r) or_return
		append(&ops.runs, run)
	}
	if n, ok = get_count(&r, 16); !ok {
		return false
	}
	for _ in 0 ..< n {
		first := i64(get_u64(&r) or_return)
		last := i64(get_u64(&r) or_return)
		// Checked against len(ops) once the ops are in.
		if first < 0 || first > i64(max(i32)) || last < -1 || last > i64(max(i32)) {
			return false
		}
		append(&ops.macros, Macro{int(first), int(last)})
	}
	if n, ok = get_count(&r, 1); !ok {
		return false
	}
	for _ in 0 ..< n {
		op := get_op(&r, ops) or_return
		append(&ops.ops, op)
	}
	if r.pos != len(r.data) {
		return false
	}
	for m in ops.macros {
		if m.first > len(ops.ops) || (m.last >= 0 && (m.last < m.first || m.last >= len(ops.ops))) {
			return false
		}
	}
	return true
}

// Writing.

// Shared with wire.odin: the host/subprocess wire messages, a separate
// format from this file's, reuse this little-endian layout.
put_u32 :: proc(w: ^[dynamic]byte, v: u32) {
	b: [4]byte
	endian.put_u32(b[:], .Little, v)
	append(w, ..b[:])
}

put_u64 :: proc(w: ^[dynamic]byte, v: u64) {
	b: [8]byte
	endian.put_u64(b[:], .Little, v)
	append(w, ..b[:])
}

put_f32 :: proc(w: ^[dynamic]byte, v: f32) {
	put_u32(w, transmute(u32)v)
}

put_f64 :: proc(w: ^[dynamic]byte, v: f64) {
	put_u64(w, transmute(u64)v)
}

put_point :: proc(w: ^[dynamic]byte, p: Point) {
	put_f32(w, p.x)
	put_f32(w, p.y)
}

put_rect :: proc(w: ^[dynamic]byte, r: Rect) {
	put_f32(w, r.x)
	put_f32(w, r.y)
	put_f32(w, r.w)
	put_f32(w, r.h)
}

put_str :: proc(w: ^[dynamic]byte, s: string) {
	put_u32(w, u32(len(s)))
	append(w, s)
}

put_color :: proc(w: ^[dynamic]byte, c: Color) {
	append(w, c.r, c.g, c.b, c.a)
}

put_stops :: proc(w: ^[dynamic]byte, stops: []Gradient_Stop) {
	put_u32(w, u32(len(stops)))
	for s in stops {
		put_f32(w, s.t)
		put_color(w, s.color)
	}
}

put_shape :: proc(w: ^[dynamic]byte, s: Shape) {
	switch v in s {
	case Rect:
		append(w, 1)
		put_rect(w, v)
	case Round_Rect:
		append(w, 2)
		put_rect(w, v.rect)
		put_f32(w, v.radius)
	case Ellipse:
		append(w, 3)
		put_rect(w, v.rect)
	case Path_Ref:
		append(w, 4)
		put_u32(w, u32(v.id))
	case:
		append(w, 0)
	}
}

put_paint :: proc(w: ^[dynamic]byte, p: Paint) {
	switch v in p {
	case Color:
		append(w, 1)
		put_color(w, v)
	case Linear_Gradient:
		append(w, 2)
		put_point(w, v.p0)
		put_point(w, v.p1)
		put_stops(w, v.stops)
	case Radial_Gradient:
		append(w, 3)
		put_point(w, v.center)
		put_f32(w, v.radius)
		put_stops(w, v.stops)
	case Image_Paint:
		append(w, 4)
		put_u32(w, u32(v.image))
	case:
		append(w, 0)
	}
}

put_op :: proc(w: ^[dynamic]byte, op: Op) {
	switch v in op {
	case Push_Transform:
		append(w, 1)
		m := v.m
		for f in ([6]f64{m.a, m.b, m.c, m.d, m.e, m.f}) {
			put_f64(w, f)
		}
	case Pop_Transform:
		append(w, 2)
	case Push_Sticky:
		append(w, 20)
		put_f32(w, v.top)
		put_f32(w, v.room)
	case Push_Clip:
		append(w, 3)
		put_shape(w, v.shape)
	case Pop_Clip:
		append(w, 4)
	case Macro_Begin:
		append(w, 5)
		put_u32(w, u32(v.id))
	case Macro_End:
		append(w, 6)
		put_u32(w, u32(v.id))
	case Call:
		append(w, 7)
		put_u32(w, u32(v.id))
	case Fill:
		append(w, 8)
		put_shape(w, v.shape)
		put_paint(w, v.paint)
	case Stroke:
		append(w, 9)
		put_shape(w, v.shape)
		put_paint(w, v.paint)
		put_f32(w, v.style.width)
		append(w, u8(v.style.cap), u8(v.style.join))
	case Glyphs:
		append(w, 10)
		put_u32(w, u32(v.run))
		put_point(w, v.origin)
		put_color(w, v.color)
	case Shadow:
		append(w, 16)
		put_rect(w, v.rect)
		put_f32(w, v.radius)
		put_f32(w, v.blur)
		put_color(w, v.color)
	case Image:
		append(w, 11)
		put_u32(w, u32(v.id))
		put_rect(w, v.dst)
		put_rect(w, v.src)
		append(w, v.alpha)
	case Input_Area:
		append(w, 12)
		put_u64(w, u64(v.id))
		put_shape(w, v.shape)
		put_u32(w, u32(transmute(u16)v.kinds))
		append(w, u8(v.cursor))
		append(w, u8(v.yields) | u8(v.observes) << 1 | u8(v.no_tab) << 2)
	case Tag:
		append(w, 13)
		put_u64(w, u64(v.id))
		put_str(w, v.name)
		put_rect(w, v.bounds)
	case Defer:
		append(w, 14)
		put_u32(w, u32(v.id))
		append(w, v.root ? 1 : 0)
		append(w, (v.cover ? u8(1) : 0) | (v.top ? u8(2) : 0))
		put_u64(w, u64(v.covers))
		append(w, v.place.set ? 1 : 0)
		if v.place.set {
			put_u64(w, u64(v.place.key))
			put_rect(w, v.place.anchor)
			put_point(w, v.place.size)
			append(w, u8(v.place.side), u8(v.place.align))
			put_f32(w, v.place.gap)
			put_f32(w, v.place.nudge)
			append(w, u8(v.place.inside) | u8(v.place.overhang) << 1)
			append(w, v.place.side_count, v.place.align_count)
			for s in v.place.sides {
				append(w, u8(s))
			}
			for a in v.place.aligns {
				append(w, u8(a))
			}
		}
	case Cover_End:
		append(w, 17)
		put_u64(w, u64(v.id))
	case Debug_Box:
		append(w, 15)
		put_u64(w, u64(v.id))
		put_point(w, v.size)
		put_point(w, v.min)
		put_point(w, v.max)
		put_u32(w, u32(v.depth))
		put_str(w, v.file)
		put_u32(w, u32(v.line))
		put_str(w, v.procedure)
		put_str(w, v.kind)
	case Semantic:
		append(w, 18)
		put_u64(w, u64(v.id))
		put_u64(w, u64(v.parent))
		append(w, u8(v.semantics.role))
		put_str(w, v.semantics.label)
		put_u64(w, u64(v.semantics.labelled_by))
		put_str(w, v.semantics.value)
		put_str(w, v.semantics.description)
		put_u32(w, u32(transmute(u16)v.semantics.states))
		append(w, v.semantics.level)
		put_u64(w, u64(v.semantics.active_descendant))
		put_rect(w, v.rect)
	case Key_Interest:
		append(w, 19)
		put_u64(w, u64(v.area))
		append(w, u8(v.key))
		append(w, transmute(u8)v.mods)
		append(w, transmute(u8)v.optional)
		append(w, u8(v.topmost))
	case Focus_Scope:
		append(w, 21)
		put_u64(w, u64(v.id))
		append(w, u8(v.trap) | u8(v.wrap) << 1 | u8(v.rove) << 2)
	case Focus_Scope_End:
		append(w, 22)
		put_u64(w, u64(v.entry))
	case Push_Opacity:
		append(w, 23)
		put_f32(w, v.alpha)
	case Pop_Opacity:
		append(w, 24)
	case:
		append(w, 0)
	}
}

// Reading. Every get_* bounds-checks and returns ok=false rather than
// reading past the end.

Reader :: struct {
	data:      []byte,
	pos:       int,
	allocator: mem.Allocator,
}

take :: proc(r: ^Reader, n: int) -> (v: []byte, ok: bool) {
	if n < 0 || n > len(r.data) - r.pos {
		return nil, false
	}
	b := r.data[r.pos:][:n]
	r.pos += n
	return b, true
}

get_u8 :: proc(r: ^Reader) -> (v: u8, ok: bool) {
	b := take(r, 1) or_return
	return b[0], true
}

get_u32 :: proc(r: ^Reader) -> (v: u32, ok: bool) {
	b := take(r, 4) or_return
	return endian.get_u32(b, .Little)
}

get_u64 :: proc(r: ^Reader) -> (v: u64, ok: bool) {
	b := take(r, 8) or_return
	return endian.get_u64(b, .Little)
}

get_f32 :: proc(r: ^Reader) -> (v: f32, ok: bool) {
	bits := get_u32(r) or_return
	return transmute(f32)bits, true
}

get_f64 :: proc(r: ^Reader) -> (v: f64, ok: bool) {
	bits := get_u64(r) or_return
	return transmute(f64)bits, true
}

// get_count reads a u32 count and rejects one whose entries, at least
// min_size bytes each, could not fit in what is left.
get_count :: proc(r: ^Reader, min_size: int) -> (v: int, ok: bool) {
	n := int(get_u32(r) or_return)
	if n * min_size > len(r.data) - r.pos {
		return 0, false
	}
	return n, true
}

get_str :: proc(r: ^Reader) -> (v: string, ok: bool) {
	n := get_count(r, 1) or_return
	b := take(r, n) or_return
	s := make([]byte, n, r.allocator)
	copy(s, b)
	return string(s), true
}

get_point :: proc(r: ^Reader) -> (p: Point, ok: bool) {
	p.x = get_f32(r) or_return
	p.y = get_f32(r) or_return
	return p, true
}

get_rect :: proc(r: ^Reader) -> (v: Rect, ok: bool) {
	v.x = get_f32(r) or_return
	v.y = get_f32(r) or_return
	v.w = get_f32(r) or_return
	v.h = get_f32(r) or_return
	return v, true
}

get_color :: proc(r: ^Reader) -> (v: Color, ok: bool) {
	b := take(r, 4) or_return
	return {b[0], b[1], b[2], b[3]}, true
}

get_stops :: proc(r: ^Reader) -> (v: []Gradient_Stop, ok: bool) {
	n := get_count(r, 8) or_return
	stops := make([]Gradient_Stop, n, r.allocator)
	for &s in stops {
		s.t = get_f32(r) or_return
		s.color = get_color(r) or_return
	}
	return stops, true
}

get_shape :: proc(r: ^Reader, ops: ^Scene) -> (s: Shape, ok: bool) {
	switch get_u8(r) or_return {
	case 0:
		return nil, true
	case 1:
		return get_rect(r)
	case 2:
		rr: Round_Rect
		rr.rect = get_rect(r) or_return
		rr.radius = get_f32(r) or_return
		return rr, true
	case 3:
		return Ellipse{get_rect(r) or_return}, true
	case 4:
		id := get_u32(r) or_return
		if int(id) >= len(ops.paths) {
			return nil, false
		}
		return Path_Ref{Path_Id(id)}, true
	}
	return nil, false
}

get_paint :: proc(r: ^Reader) -> (p: Paint, ok: bool) {
	switch get_u8(r) or_return {
	case 0:
		return nil, true
	case 1:
		return get_color(r)
	case 2:
		g: Linear_Gradient
		g.p0 = get_point(r) or_return
		g.p1 = get_point(r) or_return
		g.stops = get_stops(r) or_return
		return g, true
	case 3:
		g: Radial_Gradient
		g.center = get_point(r) or_return
		g.radius = get_f32(r) or_return
		g.stops = get_stops(r) or_return
		return g, true
	case 4:
		return Image_Paint{Image_Id(get_u32(r) or_return)}, true
	}
	return nil, false
}

get_macro_id :: proc(r: ^Reader, ops: ^Scene) -> (v: Macro_Id, ok: bool) {
	id := get_u32(r) or_return
	if int(id) >= len(ops.macros) {
		return 0, false
	}
	return Macro_Id(id), true
}

get_op :: proc(r: ^Reader, ops: ^Scene) -> (op: Op, ok: bool) {
	switch get_u8(r) or_return {
	case 0:
		return nil, true
	case 1:
		m: Affine
		m.a = get_f64(r) or_return
		m.b = get_f64(r) or_return
		m.c = get_f64(r) or_return
		m.d = get_f64(r) or_return
		m.e = get_f64(r) or_return
		m.f = get_f64(r) or_return
		return Push_Transform{m}, true
	case 2:
		return Pop_Transform{}, true
	case 3:
		return Push_Clip{get_shape(r, ops) or_return}, true
	case 4:
		return Pop_Clip{}, true
	case 5:
		return Macro_Begin{get_macro_id(r, ops) or_return}, true
	case 6:
		return Macro_End{get_macro_id(r, ops) or_return}, true
	case 7:
		return Call{get_macro_id(r, ops) or_return}, true
	case 8:
		v: Fill
		v.shape = get_shape(r, ops) or_return
		v.paint = get_paint(r) or_return
		return v, true
	case 9:
		v: Stroke
		v.shape = get_shape(r, ops) or_return
		v.paint = get_paint(r) or_return
		v.style.width = get_f32(r) or_return
		cap := get_u8(r) or_return
		join := get_u8(r) or_return
		if cap > u8(max(Line_Cap)) || join > u8(max(Line_Join)) {
			return nil, false
		}
		v.style.cap = Line_Cap(cap)
		v.style.join = Line_Join(join)
		return v, true
	case 10:
		v: Glyphs
		id := get_u32(r) or_return
		if int(id) >= len(ops.runs) {
			return nil, false
		}
		v.run = Run_Id(id)
		v.origin = get_point(r) or_return
		v.color = get_color(r) or_return
		return v, true
	case 11:
		v: Image
		v.id = Image_Id(get_u32(r) or_return)
		v.dst = get_rect(r) or_return
		v.src = get_rect(r) or_return
		v.alpha = get_u8(r) or_return
		return v, true
	case 12:
		v: Input_Area
		v.id = Area_Id(get_u64(r) or_return)
		v.shape = get_shape(r, ops) or_return
		bits := get_u32(r) or_return
		if bits >= 1 << (uint(max(Event_Kind)) + 1) {
			return nil, false
		}
		v.kinds = transmute(Event_Kinds)u16(bits)
		c := get_u8(r) or_return
		if c > u8(max(Cursor)) {
			return nil, false
		}
		v.cursor = Cursor(c)
		flags := get_u8(r) or_return
		if flags > 7 {
			return nil, false
		}
		v.yields, v.observes, v.no_tab = flags & 1 != 0, flags & 2 != 0, flags & 4 != 0
		return v, true
	case 13:
		v: Tag
		v.id = Area_Id(get_u64(r) or_return)
		v.name = get_str(r) or_return
		v.bounds = get_rect(r) or_return
		return v, true
	case 14:
		v: Defer
		v.id = get_macro_id(r, ops) or_return
		root := get_u8(r) or_return
		if root > 1 {
			return nil, false
		}
		v.root = root == 1
		cover := get_u8(r) or_return
		if cover > 3 {
			return nil, false
		}
		v.cover = cover & 1 != 0
		v.top = cover & 2 != 0
		v.covers = Area_Id(get_u64(r) or_return)
		placed := get_u8(r) or_return
		if placed > 1 {
			return nil, false
		}
		if placed == 1 {
			v.place.set = true
			v.place.key = Area_Id(get_u64(r) or_return)
			v.place.anchor = get_rect(r) or_return
			v.place.size = get_point(r) or_return
			side := get_u8(r) or_return
			align := get_u8(r) or_return
			if int(side) >= len(Side) || int(align) >= len(Side_Align) {
				return nil, false
			}
			v.place.side, v.place.align = Side(side), Side_Align(align)
			v.place.gap = get_f32(r) or_return
			v.place.nudge = get_f32(r) or_return
			flags := get_u8(r) or_return
			if flags > 3 {
				return nil, false
			}
			v.place.inside, v.place.overhang = flags & 1 != 0, flags & 2 != 0
			v.place.side_count = get_u8(r) or_return
			v.place.align_count = get_u8(r) or_return
			if int(v.place.side_count) > len(v.place.sides) || int(v.place.align_count) > len(v.place.aligns) {
				return nil, false
			}
			for &s in v.place.sides {
				b := get_u8(r) or_return
				if int(b) >= len(Side) {
					return nil, false
				}
				s = Side(b)
			}
			for &a in v.place.aligns {
				b := get_u8(r) or_return
				if int(b) >= len(Side_Align) {
					return nil, false
				}
				a = Side_Align(b)
			}
		}
		return v, true
	case 16:
		v: Shadow
		v.rect = get_rect(r) or_return
		v.radius = get_f32(r) or_return
		v.blur = get_f32(r) or_return
		v.color = get_color(r) or_return
		return v, true
	case 17:
		v: Cover_End
		v.id = Area_Id(get_u64(r) or_return)
		return v, true
	case 15:
		v: Debug_Box
		v.id = Area_Id(get_u64(r) or_return)
		v.size = get_point(r) or_return
		v.min = get_point(r) or_return
		v.max = get_point(r) or_return
		v.depth = i32(get_u32(r) or_return)
		v.file = get_str(r) or_return
		v.line = i32(get_u32(r) or_return)
		v.procedure = get_str(r) or_return
		v.kind = get_str(r) or_return
		return v, true
	case 18:
		v: Semantic
		v.id = Area_Id(get_u64(r) or_return)
		v.parent = Area_Id(get_u64(r) or_return)
		role := get_u8(r) or_return
		if role > u8(max(Role)) {
			return nil, false
		}
		v.semantics.role = Role(role)
		v.semantics.label = get_str(r) or_return
		v.semantics.labelled_by = Area_Id(get_u64(r) or_return)
		v.semantics.value = get_str(r) or_return
		v.semantics.description = get_str(r) or_return
		states := get_u32(r) or_return
		if states >= 1 << (uint(max(State)) + 1) {
			return nil, false
		}
		v.semantics.states = transmute(States)u16(states)
		v.semantics.level = get_u8(r) or_return
		v.semantics.active_descendant = Area_Id(get_u64(r) or_return)
		v.rect = get_rect(r) or_return
		return v, true
	case 19:
		v: Key_Interest
		v.area = Area_Id(get_u64(r) or_return)
		key := get_u8(r) or_return
		if key > u8(max(Key)) {
			return nil, false
		}
		v.key = Key(key)
		mods := get_u8(r) or_return
		optional := get_u8(r) or_return
		if mods >= 1 << (uint(max(Mod)) + 1) || optional >= 1 << (uint(max(Mod)) + 1) {
			return nil, false
		}
		v.mods = transmute(Mods)mods
		v.optional = transmute(Mods)optional
		topmost := get_u8(r) or_return
		if topmost > 1 {
			return nil, false
		}
		v.topmost = topmost == 1
		return v, true
	case 20:
		v: Push_Sticky
		v.top = get_f32(r) or_return
		v.room = get_f32(r) or_return
		return v, true
	case 21:
		v: Focus_Scope
		v.id = Area_Id(get_u64(r) or_return)
		flags := get_u8(r) or_return
		if flags >> 2 > u8(max(Rove)) {
			return nil, false
		}
		v.trap, v.wrap, v.rove = flags & 1 != 0, flags & 2 != 0, Rove(flags >> 2)
		return v, true
	case 22:
		return Focus_Scope_End{Area_Id(get_u64(r) or_return)}, true
	case 23:
		return Push_Opacity{get_f32(r) or_return}, true
	case 24:
		return Pop_Opacity{}, true
	}
	return nil, false
}
