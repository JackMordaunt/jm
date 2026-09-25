package ui

import "core:fmt"
import "core:math"
import "core:strings"

// Canonical text forms of Ops and Frame. Tests compare against these and the
// probe prints them, so the format is part of the contract: one op per line,
// two spaces per open push or macro, numbers via write_num.

// dump renders ops one per line. Pops and macro ends print nothing and
// dedent; a macro body is indented under its `macro N` line.
dump :: proc(ops: ^Ops, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	depth := 0
	for op in ops.ops {
		#partial switch _ in op {
		case Pop_Transform, Pop_Clip, Macro_End:
			depth = max(depth - 1, 0)
			continue
		case nil:
			continue
		}
		for _ in 0 ..< depth {
			strings.write_string(&sb, "  ")
		}
		#partial switch v in op {
		case Push_Transform:
			strings.write_string(&sb, "transform ")
			write_affine(&sb, v.m)
			depth += 1
		case Push_Clip:
			strings.write_string(&sb, "clip ")
			write_shape(&sb, v.shape)
			depth += 1
		case Macro_Begin:
			fmt.sbprintf(&sb, "macro %d", v.id)
			depth += 1
		case Call:
			fmt.sbprintf(&sb, "call %d", v.id)
		case Fill:
			write_draw(&sb, ops, v)
		case Stroke:
			write_draw(&sb, ops, v)
		case Glyphs:
			write_draw(&sb, ops, v)
		case Image:
			write_draw(&sb, ops, v)
		case Input_Area:
			fmt.sbprintf(&sb, "input %d ", v.id)
			write_shape(&sb, v.shape)
			strings.write_string(&sb, " kinds=")
			write_kinds(&sb, v.kinds)
		case Tag:
			write_tag(&sb, v)
		}
		strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// dump_frame renders f in four sections, draws, clips, hits and tags, one
// entry per line indented under its section. Transforms print in brackets;
// a missing clip prints as clip=none.
dump_frame :: proc(f: ^Frame, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	strings.write_string(&sb, "draws\n")
	for d, i in f.draws {
		fmt.sbprintf(&sb, "  draw %d clip=", i)
		write_clip_id(&sb, d.clip)
		strings.write_string(&sb, " [")
		write_affine(&sb, d.transform)
		strings.write_string(&sb, "] ")
		switch v in d.cmd {
		case Fill:
			write_draw(&sb, f.ops, v)
		case Stroke:
			write_draw(&sb, f.ops, v)
		case Glyphs:
			write_draw(&sb, f.ops, v)
		case Image:
			write_draw(&sb, f.ops, v)
		}
		strings.write_byte(&sb, '\n')
	}
	strings.write_string(&sb, "clips\n")
	for c, i in f.clips {
		fmt.sbprintf(&sb, "  clip %d parent=", i)
		write_clip_id(&sb, c.parent)
		strings.write_string(&sb, " [")
		write_affine(&sb, c.transform)
		strings.write_string(&sb, "] ")
		write_shape(&sb, c.shape)
		strings.write_byte(&sb, '\n')
	}
	strings.write_string(&sb, "hits\n")
	for h, i in f.hits {
		fmt.sbprintf(&sb, "  hit %d area=%d order=%d clip=", i, h.area, h.order)
		write_clip_id(&sb, h.clip)
		strings.write_string(&sb, " [")
		write_affine(&sb, h.transform)
		strings.write_string(&sb, "] ")
		write_shape(&sb, h.shape)
		strings.write_string(&sb, " kinds=")
		write_kinds(&sb, h.kinds)
		strings.write_byte(&sb, '\n')
	}
	strings.write_string(&sb, "tags\n")
	for t in f.tags {
		strings.write_string(&sb, "  ")
		write_tag(&sb, t)
		strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// write_num writes v compactly: rounded to 3 decimals, integers without a
// decimal point, trailing zeros trimmed, never "-0". NaN and infinities
// print as nan, inf and -inf.
write_num :: proc(sb: ^strings.Builder, v: f64) {
	switch math.classify(v) {
	case .NaN:
		strings.write_string(sb, "nan")
		return
	case .Inf:
		strings.write_string(sb, "inf")
		return
	case .Neg_Inf:
		strings.write_string(sb, "-inf")
		return
	case .Normal, .Subnormal, .Zero, .Neg_Zero:
	}
	// Past 1e15 an f64 has no thousandths left to round, and scaling by 1000
	// would itself perturb the value.
	if abs(v) >= 1e15 {
		fmt.sbprintf(sb, "%.0f", v)
		return
	}
	r := math.round(v * 1000) / 1000
	if r == math.trunc(r) {
		fmt.sbprintf(sb, "%d", i64(r))
		return
	}
	buf: [64]byte
	s := fmt.bprintf(buf[:], "%.3f", r)
	s = strings.trim_right(s, "0")
	s = strings.trim_suffix(s, ".")
	strings.write_string(sb, s)
}

@(private = "file")
write_affine :: proc(sb: ^strings.Builder, m: Affine) {
	for v, i in ([6]f64{m.a, m.b, m.c, m.d, m.e, m.f}) {
		if i > 0 {
			strings.write_byte(sb, ' ')
		}
		write_num(sb, v)
	}
}

@(private = "file")
write_nums :: proc(sb: ^strings.Builder, vs: ..f32) {
	for v, i in vs {
		if i > 0 {
			strings.write_byte(sb, ' ')
		}
		write_num(sb, f64(v))
	}
}

@(private = "file")
write_rect :: proc(sb: ^strings.Builder, r: Rect) {
	write_nums(sb, r.x, r.y, r.w, r.h)
}

@(private = "file")
write_color :: proc(sb: ^strings.Builder, c: Color) {
	if c.a == 255 {
		fmt.sbprintf(sb, "#%02x%02x%02x", c.r, c.g, c.b)
	} else {
		fmt.sbprintf(sb, "#%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
	}
}

@(private = "file")
write_shape :: proc(sb: ^strings.Builder, s: Shape) {
	switch v in s {
	case Rect:
		strings.write_string(sb, "rect ")
		write_rect(sb, v)
	case Round_Rect:
		strings.write_string(sb, "rrect ")
		write_nums(sb, v.rect.x, v.rect.y, v.rect.w, v.rect.h, v.radius)
	case Ellipse:
		strings.write_string(sb, "ellipse ")
		write_rect(sb, v.rect)
	case Path_Ref:
		fmt.sbprintf(sb, "path#%d", v.id)
	case:
		strings.write_string(sb, "none")
	}
}

@(private = "file")
write_paint :: proc(sb: ^strings.Builder, p: Paint) {
	switch v in p {
	case Color:
		write_color(sb, v)
	case Linear_Gradient:
		strings.write_string(sb, "linear ")
		write_nums(sb, v.p0.x, v.p0.y, v.p1.x, v.p1.y)
		fmt.sbprintf(sb, " stops=%d", len(v.stops))
	case Radial_Gradient:
		strings.write_string(sb, "radial ")
		write_nums(sb, v.center.x, v.center.y, v.radius)
		fmt.sbprintf(sb, " stops=%d", len(v.stops))
	case Image_Paint:
		fmt.sbprintf(sb, "image#%d", v.image)
	case:
		strings.write_string(sb, "none")
	}
}

@(private = "file")
write_kinds :: proc(sb: ^strings.Builder, ks: Event_Kinds) {
	first := true
	for k in Event_Kind {
		if k not_in ks {
			continue
		}
		if !first {
			strings.write_byte(sb, ',')
		}
		first = false
		strings.write_string(sb, strings.to_lower(fmt.tprint(k), context.temp_allocator))
	}
}

@(private = "file")
write_clip_id :: proc(sb: ^strings.Builder, c: Clip_Id) {
	if c == NO_CLIP {
		strings.write_string(sb, "none")
	} else {
		fmt.sbprintf(sb, "%d", c)
	}
}

@(private = "file")
write_tag :: proc(sb: ^strings.Builder, t: Tag) {
	fmt.sbprintf(sb, "tag %d ", t.id)
	strings.write_quoted_string(sb, t.name)
}

// write_draw prints the four drawing ops, shared by dump and dump_frame.
// ops may be nil or lack the run a Glyphs names; the run fields then print ?.
@(private = "file")
write_draw :: proc(sb: ^strings.Builder, ops: ^Ops, cmd: Draw_Cmd) {
	switch v in cmd {
	case Fill:
		strings.write_string(sb, "fill ")
		write_shape(sb, v.shape)
		strings.write_byte(sb, ' ')
		write_paint(sb, v.paint)
	case Stroke:
		strings.write_string(sb, "stroke ")
		write_shape(sb, v.shape)
		strings.write_byte(sb, ' ')
		write_paint(sb, v.paint)
		strings.write_string(sb, " w=")
		write_num(sb, f64(v.style.width))
		cap := strings.to_lower(fmt.tprint(v.style.cap), context.temp_allocator)
		join := strings.to_lower(fmt.tprint(v.style.join), context.temp_allocator)
		fmt.sbprintf(sb, " cap=%s join=%s", cap, join)
	case Glyphs:
		if ops != nil && int(v.run) < len(ops.runs) {
			r := ops.runs[v.run]
			fmt.sbprintf(sb, "glyphs font=%d size=", r.font)
			write_num(sb, f64(r.size))
			fmt.sbprintf(sb, " run#%d n=%d adv=", v.run, len(r.glyphs))
			write_num(sb, f64(r.advance))
		} else {
			fmt.sbprintf(sb, "glyphs font=? size=? run#%d n=? adv=?", v.run)
		}
		strings.write_byte(sb, ' ')
		write_color(sb, v.color)
		strings.write_string(sb, " @ ")
		write_nums(sb, v.origin.x, v.origin.y)
	case Image:
		fmt.sbprintf(sb, "image#%d dst ", v.id)
		write_rect(sb, v.dst)
		strings.write_string(sb, " src ")
		write_rect(sb, v.src)
	}
}
