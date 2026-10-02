package render

import "core:strings"
import "jm:ui/ops"

import bl "jm:ui/blend2d"
import "jm:ui/glyf"

// Variable is a font id whose Font_Ref weight moves a variable font off
// its default instance. Blend2D at blend2d_rev (3525b5f) keeps a font's
// variation settings but draws every glyph from the default outline, so
// such an id's glyphs are decoded at coords by jm:ui/glyf and filled as
// paths instead.
@(private)
Variable :: struct {
	data:   bl.FontDataCore, // owns the bytes font's tables point into
	font:   glyf.Font,
	coords: glyf.Coords,
}

// Glyph_Key names a glyph of one font id, whose outline is cached.
@(private)
Glyph_Key :: struct {
	font:  ops.Font_Id,
	glyph: u32,
}

// load_variable registers ref in r.variable when its weight varies the
// font: the font has a wght axis and weight is not its default. A static
// font, or a weight of 0, is drawn by Blend2D as it always was: nil.
@(private)
load_variable :: proc(r: ^Renderer, ref: ops.Font_Ref) -> ^Variable {
	if ref.weight == 0 {
		return nil
	}
	v: Variable
	bl.font_data_init(&v.data)
	cpath := strings.clone_to_cstring(ref.path, context.temp_allocator)
	loaded := bl.font_data_create_from_file(&v.data, cpath, .NO_FLAGS) == 0 && read_tables(&v)
	if !loaded || !glyf.has_axis(&v.font, glyf.WGHT) || len(v.font.gvar) == 0 {
		bl.font_data_destroy(&v.data)
		return nil
	}
	v.coords = glyf.coords(&v.font, {{glyf.WGHT, ref.weight}})
	if v.coords == {} {
		bl.font_data_destroy(&v.data)
		return nil
	}
	r.variable[ref.id] = v
	return &r.variable[ref.id]
}

// read_tables points v.font at the tables of v.data's first face;
// false when they do not make a TrueType font.
@(private)
read_tables :: proc(v: ^Variable) -> bool {
	tag :: proc(s: string) -> bl.Tag {
		return bl.Tag(s[0]) << 24 | bl.Tag(s[1]) << 16 | bl.Tag(s[2]) << 8 | bl.Tag(s[3])
	}
	tags := [6]bl.Tag{tag("head"), tag("loca"), tag("glyf"), tag("gvar"), tag("fvar"), tag("avar")}
	found: [6]bl.FontTable
	bl.font_data_get_tables(&v.data, 0, &found[0], &tags[0], len(tags))
	bytes: [6][]byte
	for t, i in found {
		if t.data != nil {
			bytes[i] = ([^]byte)(t.data)[:t.size]
		}
	}
	t := glyf.Tables {
		head = bytes[0],
		loca = bytes[1],
		glyf = bytes[2],
		gvar = bytes[3],
		fvar = bytes[4],
		avar = bytes[5],
	}
	return glyf.font_init(&v.font, t)
}

// glyph_path is glyph's outline in v's font at v's coords, in font units
// with y up, decoded on first use and cached for the Renderer's life. A
// glyph that does not decode is an empty path, as a missing glyph draws
// nothing through Blend2D.
@(private)
glyph_path :: proc(r: ^Renderer, id: ops.Font_Id, v: ^Variable, glyph: u32) -> ^bl.PathCore {
	key := Glyph_Key{id, glyph}
	if p, ok := &r.glyph_paths[key]; ok {
		return p
	}
	if r.glyph_scratch == nil {
		r.glyph_scratch = new(glyf.Scratch, r.allocator)
	}
	p: bl.PathCore
	bl.path_init(&p)
	if glyph <= u32(max(u16)) {
		if o, ok := glyf.outline(&v.font, u16(glyph), v.coords, r.glyph_scratch); ok {
			append_outline(&p, o)
		}
	}
	r.glyph_paths[key] = p
	return &r.glyph_paths[key]
}

// append_outline appends o's quadratic contours to p: between two off-curve
// points lies an implied on-curve point at their midpoint.
@(private)
append_outline :: proc(p: ^bl.PathCore, o: glyf.Outline) {
	first := 0
	for e in o.ends {
		last := int(e)
		if last >= len(o.points) || last < first {
			return
		}
		append_contour(p, o.points[first:last + 1], o.on_curve[first:last + 1])
		first = last + 1
	}
}

@(private)
append_contour :: proc(p: ^bl.PathCore, pts: []glyf.Point, on: []bool) {
	n := len(pts)
	if n < 2 {
		return
	}
	// Start on an on-curve point; with none, at the implied one between
	// the last point and the first.
	begin := -1
	for i in 0 ..< n {
		if on[i] {
			begin = i
			break
		}
	}
	start := pts[begin] if begin >= 0 else (pts[n - 1] + pts[0]) / 2
	bl.path_move_to(p, f64(start.x), f64(start.y))
	ctrl: glyf.Point
	pending := false
	count := n - 1 if begin >= 0 else n
	for k in 1 ..= count {
		i := (begin + k) %% n
		pt := pts[i]
		switch {
		case on[i] && pending:
			bl.path_quad_to(p, f64(ctrl.x), f64(ctrl.y), f64(pt.x), f64(pt.y))
			pending = false
		case on[i]:
			bl.path_line_to(p, f64(pt.x), f64(pt.y))
		case pending:
			mid := (ctrl + pt) / 2
			bl.path_quad_to(p, f64(ctrl.x), f64(ctrl.y), f64(mid.x), f64(mid.y))
			ctrl = pt
		case:
			ctrl, pending = pt, true
		}
	}
	if pending {
		bl.path_quad_to(p, f64(ctrl.x), f64(ctrl.y), f64(start.x), f64(start.y))
	}
	bl.path_close(p)
}

// fill_variable fills glyphs ids, each at origin plus its placement, from
// v's outlines at size pixels: one path for the stretch, so the fill is
// one call as Blend2D's glyph run fill is.
@(private)
fill_variable :: proc(r: ^Renderer, ctx: ^bl.ContextCore, id: ops.Font_Id, v: ^Variable, ids: []u32, pts: []bl.Point, origin: bl.Point, size: f32, color: u32) {
	s := f64(size / v.font.units_per_em)
	bl.path_clear(&r.glyph_run)
	for g, i in ids {
		m := bl.Matrix2D {
			m = {s, 0, 0, -s, origin.x + pts[i].x, origin.y + pts[i].y},
		}
		bl.path_add_transformed_path(&r.glyph_run, glyph_path(r, id, v, g), nil, &m)
	}
	zero := bl.Point{}
	bl.context_fill_path_d_rgba32(ctx, &zero, &r.glyph_run, color)
}

// destroy_variable releases the variable fonts and glyph outlines r holds.
@(private)
destroy_variable :: proc(r: ^Renderer) {
	for _, &v in r.variable {
		bl.font_data_destroy(&v.data)
	}
	for _, &p in r.glyph_paths {
		bl.path_destroy(&p)
	}
	delete(r.variable)
	delete(r.glyph_paths)
	free(r.glyph_scratch, r.allocator)
	bl.path_destroy(&r.glyph_run)
}
