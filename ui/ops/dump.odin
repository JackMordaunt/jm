package ops

import "core:fmt"
import "core:math"
import "core:strings"

// Canonical text form of Scene (ui's dump_frame does Frame). Tests compare
// against these and the probe prints them, so the format is part of the contract: one op per line,
// two spaces per open push or macro, numbers via write_num.

// dump renders ops one per line. Pops and macro ends print nothing and
// dedent; a macro body is indented under its `macro N` line.
dump :: proc(ops: ^Scene, allocator := context.allocator) -> string {
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
		case Push_Sticky:
			strings.write_string(&sb, "sticky ")
			write_num(&sb, f64(v.top))
			strings.write_string(&sb, " ")
			write_num(&sb, f64(v.room))
			depth += 1
		case Push_Clip:
			strings.write_string(&sb, "clip ")
			write_shape(&sb, v.shape)
			write_fill_rule(&sb, ops, v.shape)
			depth += 1
		case Macro_Begin:
			fmt.sbprintf(&sb, "macro %d", v.id)
			depth += 1
		case Call:
			fmt.sbprintf(&sb, "call %d", v.id)
		case Defer:
			fmt.sbprintf(&sb, "defer %d%s%s", v.id, v.root ? " root" : "", v.top ? " top" : "")
			if v.cover {
				fmt.sbprintf(&sb, " covers %d", v.covers)
			}
			if v.place.set {
				a := v.place.anchor
				fmt.sbprintf(&sb, " place %v %v of %v %v %v %v size %v %v gap %v", v.place.side, v.place.align, a.x, a.y, a.w, a.h, v.place.size.x, v.place.size.y, v.place.gap)
				if v.place.nudge != 0 {
					fmt.sbprintf(&sb, " nudge %v", v.place.nudge)
				}
				if v.place.inside {
					strings.write_string(&sb, " inside")
				}
				if v.place.overhang {
					strings.write_string(&sb, " overhang")
				}
				if v.place.side_count > 0 {
					sides := v.place.sides
					fmt.sbprintf(&sb, " sides %v", sides[:v.place.side_count])
				}
				if v.place.align_count > 0 {
					aligns := v.place.aligns
					fmt.sbprintf(&sb, " aligns %v", aligns[:v.place.align_count])
				}
			}
		case Fill:
			write_draw(&sb, ops, v)
		case Stroke:
			write_draw(&sb, ops, v)
		case Glyphs:
			write_draw(&sb, ops, v)
		case Image:
			write_draw(&sb, ops, v)
		case Shadow:
			write_draw(&sb, ops, v)
		case Input_Area:
			fmt.sbprintf(&sb, "input %d ", v.id)
			write_shape(&sb, v.shape)
			strings.write_string(&sb, " kinds=")
			write_kinds(&sb, v.kinds)
			if v.cursor != .Default {
				fmt.sbprintf(&sb, " cursor=%s", strings.to_lower(fmt.tprint(v.cursor), context.temp_allocator))
			}
			if v.yields {
				strings.write_string(&sb, " yields")
			}
			if v.no_tab {
				strings.write_string(&sb, " no_tab")
			}
			if v.observes {
				strings.write_string(&sb, " observes")
			}
		case Tag:
			write_tag(&sb, v)
		case Cover_End:
			fmt.sbprintf(&sb, "cover end %d", v.id)
		case Debug_Box:
			fmt.sbprintf(&sb, "box %d %s %vx%v min %vx%v max %vx%v %s:%d", v.id, v.kind, v.size.x, v.size.y, v.min.x, v.min.y, v.max.x, v.max.y, v.file, v.line)
		case Semantic:
			fmt.sbprintf(&sb, "semantic %d in %d ", v.id, v.parent)
			write_semantics(&sb, v.semantics)
			strings.write_byte(&sb, ' ')
			write_rect(&sb, v.rect)
		case Key_Interest:
			fmt.sbprintf(&sb, "key_interest %d %v", v.area, v.key)
			write_mods(&sb, " mods", v.mods)
			write_mods(&sb, " optional", v.optional)
			if v.topmost {
				strings.write_string(&sb, " topmost")
			}
			if v.claim {
				strings.write_string(&sb, " claim")
			}
		case Focus_Scope:
			fmt.sbprintf(&sb, "focus scope %d%s", v.id, v.trap ? " trap" : "")
			if v.rove != .None {
				fmt.sbprintf(&sb, " rove %v%s", v.rove, v.wrap ? " wrap" : "")
			}
		case Focus_Scope_End:
			strings.write_string(&sb, "focus scope end")
			if v.entry != 0 {
				fmt.sbprintf(&sb, " entry %d", v.entry)
			}
		case Push_Opacity:
			fmt.sbprintf(&sb, "opacity %v", v.alpha)
		case Pop_Opacity:
			strings.write_string(&sb, "opacity end")
		}
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

write_affine :: proc(sb: ^strings.Builder, m: Affine) {
	for v, i in ([6]f64{m.a, m.b, m.c, m.d, m.e, m.f}) {
		if i > 0 {
			strings.write_byte(sb, ' ')
		}
		write_num(sb, v)
	}
}

write_nums :: proc(sb: ^strings.Builder, vs: ..f32) {
	for v, i in vs {
		if i > 0 {
			strings.write_byte(sb, ' ')
		}
		write_num(sb, f64(v))
	}
}

write_rect :: proc(sb: ^strings.Builder, r: Rect) {
	write_nums(sb, r.x, r.y, r.w, r.h)
}

write_color :: proc(sb: ^strings.Builder, c: Color) {
	if c.a == 255 {
		fmt.sbprintf(sb, "#%02x%02x%02x", c.r, c.g, c.b)
	} else {
		fmt.sbprintf(sb, "#%02x%02x%02x%02x", c.r, c.g, c.b, c.a)
	}
}

// write_fill_rule marks a path that fills even-odd, which s's path#id
// alone does not show; non-zero, the default, is left unsaid.
write_fill_rule :: proc(sb: ^strings.Builder, o: ^Scene, s: Shape) {
	if p, is_path := s.(Path_Ref); is_path && int(p.id) < len(o.paths) && o.paths[p.id].rule == .Even_Odd {
		strings.write_string(sb, " evenodd")
	}
}

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

// write_semantics writes s as `role "label"`, then ` value "…"`,
// ` desc "…"`, the states that are set, ` level n` (a heading's or a
// tree item's), ` active_descendant id`, and a table's ` rows n`,
// ` cols n`, ` row n`, ` col n` and ` sort order`, each only when present.
write_semantics :: proc(sb: ^strings.Builder, s: Semantics) {
	fmt.sbprint(sb, s.role)
	strings.write_byte(sb, ' ')
	strings.write_quoted_string(sb, s.label)
	if s.labelled_by != 0 {
		fmt.sbprintf(sb, " labelled_by %d", s.labelled_by)
	}
	if s.value != "" {
		strings.write_string(sb, " value ")
		strings.write_quoted_string(sb, s.value)
	}
	if s.description != "" {
		strings.write_string(sb, " desc ")
		strings.write_quoted_string(sb, s.description)
	}
	for st in State {
		if st in s.states {
			fmt.sbprintf(sb, " %v", st)
		}
	}
	if s.level != 0 {
		fmt.sbprintf(sb, " level %d", s.level)
	}
	if s.active_descendant != 0 {
		fmt.sbprintf(sb, " active_descendant %d", s.active_descendant)
	}
	counts := [4]i32{s.row_count, s.col_count, s.row_index, s.col_index}
	names := [4]string{"rows", "cols", "row", "col"}
	for n, i in counts {
		if n != 0 {
			fmt.sbprintf(sb, " %s %d", names[i], n)
		}
	}
	if s.sort != .None {
		fmt.sbprintf(sb, " sort %v", s.sort)
	}
}

// write_mods writes label and the modifiers in m, or nothing for none.
write_mods :: proc(sb: ^strings.Builder, label: string, m: Mods) {
	if m == {} {
		return
	}
	strings.write_string(sb, label)
	sep := " "
	for mod in Mod {
		if mod in m {
			fmt.sbprintf(sb, "%s%v", sep, mod)
			sep = "+"
		}
	}
}

// write_tag writes a tag as `tag ID "name"`, then its bounds when it has
// them, so a dump says where a label is as well as that it is.
write_tag :: proc(sb: ^strings.Builder, t: Tag) {
	fmt.sbprintf(sb, "tag %d ", t.id)
	strings.write_quoted_string(sb, t.name)
	if t.bounds != {} {
		strings.write_byte(sb, ' ')
		write_rect(sb, t.bounds)
	}
}

// write_draw writes a draw op — a Fill, Stroke, Glyphs, Image or Shadow — as dump
// prints one; ui's dump_frame prints a Frame's Draw_Cmd through it too.
write_draw :: proc(sb: ^strings.Builder, o: ^Scene, cmd: Op) {
	#partial switch v in cmd {
	case Fill:
		strings.write_string(sb, "fill ")
		write_shape(sb, v.shape)
		write_fill_rule(sb, o, v.shape)
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
		if o != nil && int(v.run) < len(o.runs) {
			r := o.runs[v.run]
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
		if v.alpha < 255 {
			fmt.sbprintf(sb, " alpha %d", v.alpha)
		}
	case Shadow:
		strings.write_string(sb, "shadow ")
		write_rect(sb, v.rect)
		strings.write_string(sb, " r=")
		write_num(sb, f64(v.radius))
		strings.write_string(sb, " blur=")
		write_num(sb, f64(v.blur))
		strings.write_byte(sb, ' ')
		write_color(sb, v.color)
	}
}
