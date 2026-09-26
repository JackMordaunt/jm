/*
Package render executes a ui.Frame on Blend2D and shapes text with Blend2D's
own font_shape. It is the only place that knows how a draw becomes pixels:
ui records and flattens, render rasterizes, a platform (ui/sdl) presents.

	r: render.Renderer
	render.init(&r)
	defer render.destroy(&r)

	gtx.shaper = render.shaper(&r, ops.fonts[:])
	// ... ui(gtx), ui.flatten(&ops, &frame) ...
	render.render_png(&r, &frame, 640, 480, "build/frame.png", {255, 255, 255, 255})

Clipping: a draw whose clip chain is all rects under translate/scale
transforms is clipped with Blend2D's rect clip. Any other chain (a round rect,
an ellipse, a path, a rotated rect) is rasterized once per render into an A8
mask covering only the chain's bounds. Each run of consecutive draws under
that clip is rendered together into a transparent layer and painted onto the
target through the mask in one pass, so the clip's antialiased edge applies
once to the group, as clipping a group should. Where a chain of rects and
round rects under axis-aligned transforms covers pixels fully, its group
draws there straight onto the target, and only the ring around that
interior goes through the layer.

Memory: fonts, font sizes and images are cached for the life of the Renderer,
keyed by the ids in Ops, so an Ops must keep its ids stable (add_font and
add_image do). Masks live for one render call; their pixels are buffers the
Renderer reuses from call to call. Everything is released by destroy.

Threads: a Renderer is not thread-safe. The Shaper it hands out shares the
font cache, so shape and render must happen on the same thread. Setting
Renderer.threads renders the target on that many Blend2D workers; render
still returns only once every pixel is written.
*/
package render

import "core:math"
import "core:mem"
import "core:strings"

import "jm:ui"
import bl "jm:ui/blend2d"

// Font_Key names one Blend2D font instance: a face at a pixel size.
Font_Key :: struct {
	id:   ui.Font_Id,
	size: f32,
}

// Renderer holds the Blend2D contexts and the resource caches a frame
// draws from. Zero it and call init before use.
Renderer :: struct {
	ctx:        bl.ContextCore, // draws into the target
	layer_ctx:  bl.ContextCore, // draws a clipped command into layer
	mask_ctx:   bl.ContextCore, // rasterizes clip shapes into masks
	faces:      map[ui.Font_Id]bl.FontFaceCore,
	fonts:      map[Font_Key]bl.FontCore,
	images:     map[ui.Image_Id]bl.ImageCore,
	masks:      map[ui.Clip_Id]Mask, // per render call
	pool:       [dynamic][]u8, // mask pixel buffers, reused across calls
	pool_used:  int, // buffers handed out this call
	layer:      bl.ImageCore, // at least as big as every target so far
	layer_size: [2]i32,
	path:       bl.PathCore,
	font_refs:  []ui.Font_Ref, // what the shaper loads from
	allocator:  mem.Allocator,
	// threads > 0 makes the target context asynchronous with that many
	// workers (1 = the calling thread only). Layer and mask contexts stay
	// synchronous. Zero renders synchronously.
	threads:    u32,
}

// Mask is a clip chain's coverage over box, the part of the target the
// chain can show; img is box-sized, empty when box is. Inside inner the
// chain covers every pixel fully, so img holds coverage only in the ring
// around inner; the bytes under inner are never written or read.
@(private)
Mask :: struct {
	img:   bl.ImageCore,
	box:   ui.Rect, // whole pixels
	inner: ui.Rect, // whole pixels inside box, empty when the chain has none
}

// init prepares r. Caches allocate from allocator.
init :: proc(r: ^Renderer, allocator := context.allocator) {
	r.allocator = allocator
	bl.context_init(&r.ctx)
	bl.context_init(&r.layer_ctx)
	bl.context_init(&r.mask_ctx)
	bl.image_init(&r.layer)
	bl.path_init(&r.path)
	r.faces = make(map[ui.Font_Id]bl.FontFaceCore, allocator)
	r.fonts = make(map[Font_Key]bl.FontCore, allocator)
	r.images = make(map[ui.Image_Id]bl.ImageCore, allocator)
	r.masks = make(map[ui.Clip_Id]Mask, allocator)
	r.pool = make([dynamic][]u8, allocator)
}

// destroy releases every Blend2D object and cache r holds.
destroy :: proc(r: ^Renderer) {
	for _, &f in r.fonts {
		bl.font_destroy(&f)
	}
	for _, &f in r.faces {
		bl.font_face_destroy(&f)
	}
	for _, &img in r.images {
		bl.image_destroy(&img)
	}
	clear_masks(r)
	delete(r.fonts)
	delete(r.faces)
	delete(r.images)
	delete(r.masks)
	for b in r.pool {
		delete(b, r.allocator)
	}
	delete(r.pool)
	bl.image_destroy(&r.layer)
	bl.path_destroy(&r.path)
	bl.context_destroy(&r.ctx)
	bl.context_destroy(&r.layer_ctx)
	bl.context_destroy(&r.mask_ctx)
	r^ = {}
}

// render clears target to clear and executes f.draws in order onto it.
// target must be a PRGB32 image; f.ops supplies paths, runs, fonts and images.
render :: proc(r: ^Renderer, f: ^ui.Frame, target: ^bl.ImageCore, clear: ui.Color) {
	clear_masks(r)
	data: bl.ImageData
	if bl.image_get_data(target, &data) != 0 {
		return
	}
	w, h := data.size.w, data.size.h
	if w <= 0 || h <= 0 {
		return
	}
	cci: ^bl.ContextCreateInfo
	info: bl.ContextCreateInfo
	if r.threads > 0 {
		info = {
			flags        = u32(bl.ContextCreateFlags.FLAG_FALLBACK_TO_SYNC),
			thread_count = r.threads,
		}
		cci = &info
	}
	if bl.context_begin(&r.ctx, target, cci) != 0 {
		return
	}
	defer bl.context_end(&r.ctx)

	bl.context_clear_all(&r.ctx)
	bl.context_fill_all_rgba32(&r.ctx, rgba32(clear))
	if f.ops == nil {
		return
	}
	for i := 0; i < len(f.draws); {
		if exec(r, f, &f.draws[i]) {
			i += 1
			continue
		}
		j := i + 1
		for j < len(f.draws) && f.draws[j].clip == f.draws[i].clip {
			j += 1
		}
		exec_masked(r, f, f.draws[i:j], w, h)
		i = j
	}
}

// render_png renders f into a new w×h image and writes it to path; the
// codec is picked from the extension. It reports whether the write worked.
render_png :: proc(r: ^Renderer, f: ^ui.Frame, w, h: int, path: string, clear: ui.Color) -> bool {
	img: bl.ImageCore
	bl.image_init(&img)
	defer bl.image_destroy(&img)
	if bl.image_create(&img, i32(w), i32(h), .PRGB32) != 0 {
		return false
	}
	render(r, f, &img, clear)
	cpath := strings.clone_to_cstring(path, context.temp_allocator)
	return bl.image_write_to_file(&img, cpath, nil) == 0
}

// pixel reads the straight (unpremultiplied) color at (x, y) of a PRGB32
// image, or zero when the point is outside it.
pixel :: proc(img: ^bl.ImageCore, x, y: int) -> ui.Color {
	data: bl.ImageData
	if bl.image_get_data(img, &data) != 0 {
		return {}
	}
	if x < 0 || y < 0 || x >= int(data.size.w) || y >= int(data.size.h) {
		return {}
	}
	row := uintptr(data.pixel_data) + uintptr(y * int(data.stride))
	v := (^u32)(row + uintptr(x * 4))^
	a := u8(v >> 24)
	if a == 0 {
		return {}
	}
	un :: proc(c: u32, a: u8) -> u8 {
		return u8(min(255, (c & 0xFF) * 255 / u32(a)))
	}
	return {un(v >> 16, a), un(v >> 8, a), un(v, a), a}
}

// rgba32 packs a straight color the way Blend2D's *_rgba32 calls take it:
// 0xAARRGGBB, not premultiplied.
rgba32 :: proc(c: ui.Color) -> u32 {
	return u32(c.a) << 24 | u32(c.r) << 16 | u32(c.g) << 8 | u32(c.b)
}

@(private)
to_matrix :: proc(m: ui.Affine) -> bl.Matrix2D {
	out: bl.Matrix2D
	out.m = {m.a, m.b, m.c, m.d, m.e, m.f}
	return out
}

@(private)
set_transform :: proc(ctx: ^bl.ContextCore, m: ui.Affine) {
	mm := to_matrix(m)
	bl.context_apply_transform_op(ctx, .ASSIGN, &mm)
}

@(private)
clear_masks :: proc(r: ^Renderer) {
	for _, &m in r.masks {
		bl.image_destroy(&m.img)
	}
	clear(&r.masks)
	r.pool_used = 0
}

// pool_take hands out a reused buffer of at least n bytes for this call.
@(private)
pool_take :: proc(r: ^Renderer, n: int) -> []u8 {
	if r.pool_used == len(r.pool) {
		append(&r.pool, make([]u8, n, r.allocator))
	} else if len(r.pool[r.pool_used]) < n {
		delete(r.pool[r.pool_used], r.allocator)
		r.pool[r.pool_used] = make([]u8, n, r.allocator)
	}
	r.pool_used += 1
	return r.pool[r.pool_used - 1][:n]
}

// exec draws d unless its clip needs a mask, and reports whether it did.
@(private)
exec :: proc(r: ^Renderer, f: ^ui.Frame, d: ^ui.Draw) -> bool {
	if d.clip == ui.NO_CLIP {
		set_transform(&r.ctx, d.transform)
		draw_cmd(r, &r.ctx, f, d)
		return true
	}
	dev, ok := rect_chain(f, d.clip)
	if !ok {
		return false
	}
	if dev.w <= 0 || dev.h <= 0 {
		return true
	}
	bl.context_save(&r.ctx, nil)
	defer bl.context_restore(&r.ctx, nil)
	set_transform(&r.ctx, ui.IDENTITY)
	rect := bl.Rect{f64(dev.x), f64(dev.y), f64(dev.w), f64(dev.h)}
	bl.context_clip_to_rect_d(&r.ctx, &rect)
	set_transform(&r.ctx, d.transform)
	draw_cmd(r, &r.ctx, f, d)
	return true
}

// exec_masked draws draws, which share one clip, so that the clip's coverage
// applies to them once, as a group. Inside the clip's interior the coverage
// is full, so there they draw straight onto the target; only the ring
// between the interior and the mask's box is drawn into the layer and
// painted onto the target through the mask.
@(private)
exec_masked :: proc(r: ^Renderer, f: ^ui.Frame, draws: []ui.Draw, w, h: i32) {
	m := clip_mask(r, f, draws[0].clip, w, h)
	if m == nil {
		return
	}
	inner := m.inner
	if inner.w > 0 {
		bl.context_save(&r.ctx, nil)
		set_transform(&r.ctx, ui.IDENTITY)
		rect := bl.Rect{f64(inner.x), f64(inner.y), f64(inner.w), f64(inner.h)}
		bl.context_clip_to_rect_d(&r.ctx, &rect)
		for &d in draws {
			set_transform(&r.ctx, d.transform)
			draw_cmd(r, &r.ctx, f, &d)
		}
		bl.context_restore(&r.ctx, nil)
	}
	edges, n := ring(m.box, inner)
	if n == 0 || !ensure_layer(r, w, h) {
		return
	}
	if r.threads > 0 {
		// Drain the queue so the layer is reused in place; a queued command
		// still holding it makes the layer context copy it, which is slower.
		bl.context_flush(&r.ctx, .SYNC)
	}
	if bl.context_begin(&r.layer_ctx, &r.layer, nil) != 0 {
		return
	}
	for e in edges[:n] {
		bl.context_save(&r.layer_ctx, nil)
		area := bl.RectI{i32(e.x), i32(e.y), i32(e.w), i32(e.h)}
		bl.context_clip_to_rect_i(&r.layer_ctx, &area)
		bl.context_clear_rect_i(&r.layer_ctx, &area)
		for &d in draws {
			set_transform(&r.layer_ctx, d.transform)
			draw_cmd(r, &r.layer_ctx, f, &d)
		}
		bl.context_restore(&r.layer_ctx, nil)
	}
	bl.context_end(&r.layer_ctx)

	pattern: bl.PatternCore
	bl.pattern_init_as(&pattern, &r.layer, nil, .PAD, nil)
	defer bl.pattern_destroy(&pattern)
	bl.context_save(&r.ctx, nil)
	defer bl.context_restore(&r.ctx, nil)
	set_transform(&r.ctx, ui.IDENTITY)
	bl.context_set_comp_op(&r.ctx, .SRC_OVER)
	bl.context_set_fill_style(&r.ctx, (^bl.Unknown)(&pattern))
	for e in edges[:n] {
		origin := bl.Point{f64(e.x), f64(e.y)}
		area := bl.RectI{i32(e.x - m.box.x), i32(e.y - m.box.y), i32(e.w), i32(e.h)}
		bl.context_fill_mask_d(&r.ctx, &origin, &m.img, &area)
	}
}

// clip_interior is the whole pixels of a w×h target that a clip chain
// covers fully, where its mask is opaque. It is empty unless every node is
// a Rect or Round_Rect under an axis-aligned transform.
@(private)
clip_interior :: proc(f: ^ui.Frame, id: ui.Clip_Id, w, h: i32) -> ui.Rect {
	out := ui.Rect{0, 0, f32(w), f32(h)}
	for c := id; c != ui.NO_CLIP; c = f.clips[c].parent {
		node := f.clips[c]
		inside, ok := box_inside(node.shape, 0)
		if !ok || !ui.is_axis_aligned(node.transform) {
			return {}
		}
		out = ui.rect_intersect(out, ui.transform_rect(node.transform, inside))
	}
	return inner_pixels(out, {w, h})
}

// ring cuts box minus inner, which lies inside it, into at most four
// rects: full-width bands above and below inner, then its left and right.
// An empty inner leaves box whole.
@(private)
ring :: proc(box, inner: ui.Rect) -> (out: [4]ui.Rect, n: int) {
	if inner.w <= 0 || inner.h <= 0 {
		out[0] = box
		return out, 1
	}
	bx1, by1 := box.x + box.w, box.y + box.h
	ix1, iy1 := inner.x + inner.w, inner.y + inner.h
	parts := [4]ui.Rect {
		{box.x, box.y, box.w, inner.y - box.y},
		{box.x, iy1, box.w, by1 - iy1},
		{box.x, inner.y, inner.x - box.x, inner.h},
		{ix1, inner.y, bx1 - ix1, inner.h},
	}
	for p in parts {
		if p.w > 0 && p.h > 0 {
			out[n] = p
			n += 1
		}
	}
	return out, n
}

// rect_chain resolves a clip chain to one device rect when every node is a
// Rect under an axis-aligned transform.
@(private)
rect_chain :: proc(f: ^ui.Frame, id: ui.Clip_Id) -> (ui.Rect, bool) {
	out: ui.Rect
	first := true
	for c := id; c != ui.NO_CLIP; c = f.clips[c].parent {
		node := f.clips[c]
		rect, is_rect := node.shape.(ui.Rect)
		if !is_rect || !ui.is_axis_aligned(node.transform) {
			return {}, false
		}
		dev := ui.transform_rect(node.transform, rect)
		out = dev if first else ui.rect_intersect(out, dev)
		first = false
	}
	return out, true
}

// ensure_layer makes the layer at least w×h. It only grows, so targets of
// varying size, such as a compositor's bands, do not reallocate it.
@(private)
ensure_layer :: proc(r: ^Renderer, w, h: i32) -> bool {
	if r.layer_size.x >= w && r.layer_size.y >= h {
		return true
	}
	size := [2]i32{max(w, r.layer_size.x), max(h, r.layer_size.y)}
	if bl.image_create(&r.layer, size.x, size.y, .PRGB32) != 0 {
		r.layer_size = {}
		return false
	}
	r.layer_size = size
	return true
}

// clip_mask returns the coverage of a clip chain over the part of a w×h
// target it can show, rasterizing it on first use this call; nil when that
// part is empty. Only the ring around the chain's interior is rasterized.
// The first node is filled into the mask; every further node is filled
// into a scratch mask and multiplied in with DST_IN over the same ring,
// which leaves only the intersection.
@(private)
clip_mask :: proc(r: ^Renderer, f: ^ui.Frame, id: ui.Clip_Id, w, h: i32) -> ^Mask {
	if m, ok := &r.masks[id]; ok {
		return m if m.box.w > 0 else nil
	}
	m := Mask{}
	bl.image_init(&m.img)
	dev := ui.Rect{0, 0, f32(w), f32(h)}
	for c := id; c != ui.NO_CLIP; c = f.clips[c].parent {
		node := f.clips[c]
		dev = ui.rect_intersect(dev, ui.transform_rect(node.transform, ui.shape_bounds(f.ops, node.shape)))
	}
	if dev.w > 0 && dev.h > 0 {
		x0, y0 := math.floor(dev.x), math.floor(dev.y)
		m.box = {x0, y0, math.ceil(dev.x + dev.w) - x0, math.ceil(dev.y + dev.h) - y0}
	}
	if m.box.w <= 0 || m.box.h <= 0 || !mask_view(r, &m.img, m.box) {
		m.box = {}
		r.masks[id] = m
		return nil
	}
	m.inner = ui.rect_intersect(clip_interior(f, id, w, h), m.box)
	if m.inner.w <= 0 || m.inner.h <= 0 {
		m.inner = {}
	}
	// The ring's rects, moved into the mask's own coordinates.
	edges, n := ring(m.box, m.inner)
	for &e in edges[:n] {
		e.x -= m.box.x
		e.y -= m.box.y
	}
	shift := ui.translate(-m.box.x, -m.box.y)
	first := true
	for c := id; c != ui.NO_CLIP; c = f.clips[c].parent {
		node := f.clips[c]
		node.transform = ui.mul(node.transform, shift)
		if first {
			fill_coverage(r, f, &m.img, node, edges[:n])
			first = false
			continue
		}
		scratch: bl.ImageCore
		bl.image_init(&scratch)
		defer bl.image_destroy(&scratch)
		if !mask_view(r, &scratch, m.box) {
			continue
		}
		fill_coverage(r, f, &scratch, node, edges[:n])
		if bl.context_begin(&r.mask_ctx, &m.img, nil) != 0 {
			continue
		}
		bl.context_set_comp_op(&r.mask_ctx, .DST_IN)
		for e in edges[:n] {
			area := bl.RectI{i32(e.x), i32(e.y), i32(e.w), i32(e.h)}
			origin := bl.PointI{area.x, area.y}
			bl.context_blit_image_i(&r.mask_ctx, &origin, &scratch, &area)
		}
		bl.context_end(&r.mask_ctx)
	}
	r.masks[id] = m
	return &r.masks[id]
}

// mask_view points img at a pooled A8 buffer the size of box. Rows are
// padded to 16 bytes: with unpadded rows the mask fill painted outside the
// clip.
@(private)
mask_view :: proc(r: ^Renderer, img: ^bl.ImageCore, box: ui.Rect) -> bool {
	w, h := int(box.w), int(box.h)
	stride := mem.align_forward_int(w, 16)
	buf := pool_take(r, stride * h)
	return bl.image_create_from_data(img, i32(w), i32(h), .A8, raw_data(buf), stride, .RW, nil, nil) == 0
}

// fill_coverage clears each of areas in img and fills one clip node's shape
// opaque into them, leaving the rest of img untouched.
@(private)
fill_coverage :: proc(r: ^Renderer, f: ^ui.Frame, img: ^bl.ImageCore, node: ui.Clip, areas: []ui.Rect) {
	if bl.context_begin(&r.mask_ctx, img, nil) != 0 {
		return
	}
	defer bl.context_end(&r.mask_ctx)
	bl.context_set_fill_style_rgba32(&r.mask_ctx, 0xFFFFFFFF)
	for a in areas {
		bl.context_save(&r.mask_ctx, nil)
		area := bl.RectI{i32(a.x), i32(a.y), i32(a.w), i32(a.h)}
		bl.context_clip_to_rect_i(&r.mask_ctx, &area)
		bl.context_clear_rect_i(&r.mask_ctx, &area)
		set_transform(&r.mask_ctx, node.transform)
		fill_shape(r, &r.mask_ctx, f.ops, node.shape)
		bl.context_restore(&r.mask_ctx, nil)
	}
}

// draw_cmd executes one command on ctx under the transform already set.
@(private)
draw_cmd :: proc(r: ^Renderer, ctx: ^bl.ContextCore, f: ^ui.Frame, d: ^ui.Draw) {
	switch cmd in d.cmd {
	case ui.Fill:
		style := make_style(r, f, cmd.paint)
		defer destroy_style(&style)
		set_style(ctx, &style, true)
		fill_shape(r, ctx, f.ops, cmd.shape)
	case ui.Stroke:
		style := make_style(r, f, cmd.paint)
		defer destroy_style(&style)
		set_style(ctx, &style, false)
		bl.context_set_stroke_width(ctx, f64(cmd.style.width))
		bl.context_set_stroke_caps(ctx, stroke_cap(cmd.style.cap))
		bl.context_set_stroke_join(ctx, stroke_join(cmd.style.join))
		stroke_shape(r, ctx, f.ops, cmd.shape)
	case ui.Glyphs:
		draw_glyphs(r, ctx, f, cmd)
	case ui.Image:
		img := image(r, f.ops, cmd.id)
		if img == nil {
			return
		}
		src: ^bl.RectI
		area := bl.RectI{i32(cmd.src.x), i32(cmd.src.y), i32(cmd.src.w), i32(cmd.src.h)}
		if cmd.src.w > 0 && cmd.src.h > 0 {
			src = &area
		}
		if cmd.dst.w > 0 && cmd.dst.h > 0 {
			dst := bl.Rect{f64(cmd.dst.x), f64(cmd.dst.y), f64(cmd.dst.w), f64(cmd.dst.h)}
			bl.context_blit_scaled_image_d(ctx, &dst, img, src)
		} else {
			origin := bl.Point{f64(cmd.dst.x), f64(cmd.dst.y)}
			bl.context_blit_image_d(ctx, &origin, img, src)
		}
	}
}

@(private)
stroke_cap :: proc(c: ui.Line_Cap) -> bl.StrokeCap {
	switch c {
	case .Butt:
		return .BUTT
	case .Round:
		return .ROUND
	case .Square:
		return .SQUARE
	}
	return .BUTT
}

@(private)
stroke_join :: proc(j: ui.Line_Join) -> bl.StrokeJoin {
	switch j {
	case .Miter:
		return .MITER_CLIP
	case .Round:
		return .ROUND
	case .Bevel:
		return .BEVEL
	}
	return .MITER_CLIP
}

@(private)
draw_glyphs :: proc(r: ^Renderer, ctx: ^bl.ContextCore, f: ^ui.Frame, g: ui.Glyphs) {
	if int(g.run) >= len(f.ops.runs) {
		return
	}
	run := f.ops.runs[g.run]
	n := len(run.glyphs)
	if n == 0 {
		return
	}
	font := font_for(r, run.font, run.size, f.ops.fonts[:])
	if font == nil {
		return
	}
	ids := make([]u32, n, context.temp_allocator)
	pts := make([]bl.Point, n, context.temp_allocator)
	for gl, i in run.glyphs {
		ids[i] = gl.id
		pts[i] = {f64(gl.x), f64(gl.y)}
	}
	// USER_UNITS: each placement is a bl.Point position relative to the
	// origin, mapped by the user transform only (not the font matrix).
	gr := bl.GlyphRun {
		glyph_data        = raw_data(ids),
		placement_data    = raw_data(pts),
		size              = uint(n),
		placement_type    = u8(bl.GlyphPlacementType.USER_UNITS),
		glyph_advance     = size_of(u32),
		placement_advance = size_of(bl.Point),
	}
	origin := bl.Point{f64(g.origin.x), f64(g.origin.y)}
	bl.context_fill_glyph_run_d_rgba32(ctx, &origin, font, &gr, rgba32(g.color))
}

@(private)
fill_shape :: proc(r: ^Renderer, ctx: ^bl.ContextCore, ops: ^ui.Ops, s: ui.Shape) {
	switch v in s {
	case ui.Rect:
		rect := bl.Rect{f64(v.x), f64(v.y), f64(v.w), f64(v.h)}
		bl.context_fill_rect_d(ctx, &rect)
	case ui.Round_Rect:
		rr := round_rect(v)
		bl.context_fill_geometry(ctx, .ROUND_RECT, &rr)
	case ui.Ellipse:
		e := ellipse(v)
		bl.context_fill_geometry(ctx, .ELLIPSE, &e)
	case ui.Path_Ref:
		if build_path(r, ops, v.id) {
			origin := bl.Point{0, 0}
			bl.context_fill_path_d(ctx, &origin, &r.path)
		}
	}
}

@(private)
stroke_shape :: proc(r: ^Renderer, ctx: ^bl.ContextCore, ops: ^ui.Ops, s: ui.Shape) {
	switch v in s {
	case ui.Rect:
		rect := bl.Rect{f64(v.x), f64(v.y), f64(v.w), f64(v.h)}
		bl.context_stroke_rect_d(ctx, &rect)
	case ui.Round_Rect:
		rr := round_rect(v)
		bl.context_stroke_geometry(ctx, .ROUND_RECT, &rr)
	case ui.Ellipse:
		e := ellipse(v)
		bl.context_stroke_geometry(ctx, .ELLIPSE, &e)
	case ui.Path_Ref:
		if build_path(r, ops, v.id) {
			origin := bl.Point{0, 0}
			bl.context_stroke_path_d(ctx, &origin, &r.path)
		}
	}
}

@(private)
round_rect :: proc(v: ui.Round_Rect) -> bl.RoundRect {
	rad := f64(v.radius)
	return {f64(v.rect.x), f64(v.rect.y), f64(v.rect.w), f64(v.rect.h), rad, rad}
}

@(private)
ellipse :: proc(v: ui.Ellipse) -> bl.Ellipse {
	rx, ry := f64(v.rect.w) / 2, f64(v.rect.h) / 2
	return {f64(v.rect.x) + rx, f64(v.rect.y) + ry, rx, ry}
}

// build_path decodes ops.paths[id] into r.path. Move and Line consume one
// point, Cubic three, Close none; a path that runs out of points stops there.
@(private)
build_path :: proc(r: ^Renderer, ops: ^ui.Ops, id: ui.Path_Id) -> bool {
	if int(id) >= len(ops.paths) {
		return false
	}
	p := ops.paths[id]
	bl.path_clear(&r.path)
	i := 0
	for verb in p.verbs {
		switch verb {
		case .Move:
			if i + 1 > len(p.points) {
				return true
			}
			q := p.points[i]
			bl.path_move_to(&r.path, f64(q.x), f64(q.y))
			i += 1
		case .Line:
			if i + 1 > len(p.points) {
				return true
			}
			q := p.points[i]
			bl.path_line_to(&r.path, f64(q.x), f64(q.y))
			i += 1
		case .Cubic:
			if i + 3 > len(p.points) {
				return true
			}
			a, b, c := p.points[i], p.points[i + 1], p.points[i + 2]
			bl.path_cubic_to(&r.path, f64(a.x), f64(a.y), f64(b.x), f64(b.y), f64(c.x), f64(c.y))
			i += 3
		case .Close:
			bl.path_close(&r.path)
		}
	}
	return true
}

// Style is a paint made into a Blend2D style object for one command.
@(private)
Style :: struct {
	kind:     enum u8 {
		Solid,
		Gradient,
		Pattern,
		None,
	},
	color:    u32,
	gradient: bl.GradientCore,
	pattern:  bl.PatternCore,
}

@(private)
make_style :: proc(r: ^Renderer, f: ^ui.Frame, p: ui.Paint) -> Style {
	s: Style
	switch v in p {
	case ui.Color:
		s.kind = .Solid
		s.color = rgba32(v)
	case ui.Linear_Gradient:
		values := bl.LinearGradientValues{f64(v.p0.x), f64(v.p0.y), f64(v.p1.x), f64(v.p1.y)}
		gradient(&s, .LINEAR, &values, v.stops)
	case ui.Radial_Gradient:
		cx, cy := f64(v.center.x), f64(v.center.y)
		values := bl.RadialGradientValues{cx, cy, cx, cy, f64(v.radius), 0}
		gradient(&s, .RADIAL, &values, v.stops)
	case ui.Image_Paint:
		img := image(r, f.ops, v.image)
		if img == nil {
			s.kind = .None
			return s
		}
		s.kind = .Pattern
		bl.pattern_init_as(&s.pattern, img, nil, .REPEAT, nil)
	case:
		s.kind = .None
	}
	return s
}

@(private)
gradient :: proc(s: ^Style, type: bl.GradientType, values: rawptr, stops: []ui.Gradient_Stop) {
	s.kind = .Gradient
	bl.gradient_init_as(&s.gradient, type, values, .PAD, nil, 0, nil)
	for st in stops {
		bl.gradient_add_stop_rgba32(&s.gradient, f64(st.t), rgba32(st.color))
	}
}

@(private)
set_style :: proc(ctx: ^bl.ContextCore, s: ^Style, fill: bool) {
	switch s.kind {
	case .Solid:
		if fill {
			bl.context_set_fill_style_rgba32(ctx, s.color)
		} else {
			bl.context_set_stroke_style_rgba32(ctx, s.color)
		}
	case .Gradient:
		if fill {
			bl.context_set_fill_style(ctx, (^bl.Unknown)(&s.gradient))
		} else {
			bl.context_set_stroke_style(ctx, (^bl.Unknown)(&s.gradient))
		}
	case .Pattern:
		if fill {
			bl.context_set_fill_style(ctx, (^bl.Unknown)(&s.pattern))
		} else {
			bl.context_set_stroke_style(ctx, (^bl.Unknown)(&s.pattern))
		}
	case .None:
		if fill {
			bl.context_set_fill_style_rgba32(ctx, 0)
		} else {
			bl.context_set_stroke_style_rgba32(ctx, 0)
		}
	}
}

@(private)
destroy_style :: proc(s: ^Style) {
	switch s.kind {
	case .Gradient:
		bl.gradient_destroy(&s.gradient)
	case .Pattern:
		bl.pattern_destroy(&s.pattern)
	case .Solid, .None:
	}
}

// image returns the cached image for id, reading it from ops.images on
// first use. A missing or unreadable file yields nil every time after a
// single failed read.
@(private)
image :: proc(r: ^Renderer, ops: ^ui.Ops, id: ui.Image_Id) -> ^bl.ImageCore {
	if img, ok := &r.images[id]; ok {
		data: bl.ImageData
		if bl.image_get_data(img, &data) != 0 || data.size.w == 0 {
			return nil
		}
		return img
	}
	img: bl.ImageCore
	bl.image_init(&img)
	for ref in ops.images {
		if ref.id == id {
			cpath := strings.clone_to_cstring(ref.path, context.temp_allocator)
			if bl.image_read_from_file(&img, cpath, nil) != 0 {
				bl.image_reset(&img)
			} else {
				bl.image_convert(&img, .PRGB32)
			}
			break
		}
	}
	r.images[id] = img
	return image(r, ops, id)
}

// face returns the cached font face for id, loading it from the path refs
// name on first use; nil when the id is unknown or the file does not load.
@(private)
face :: proc(r: ^Renderer, id: ui.Font_Id, refs: []ui.Font_Ref) -> ^bl.FontFaceCore {
	if fc, ok := &r.faces[id]; ok {
		return fc
	}
	for ref in refs {
		if ref.id != id {
			continue
		}
		fc: bl.FontFaceCore
		bl.font_face_init(&fc)
		cpath := strings.clone_to_cstring(ref.path, context.temp_allocator)
		if bl.font_face_create_from_file(&fc, cpath, .NO_FLAGS) != 0 {
			bl.font_face_destroy(&fc)
			return nil
		}
		r.faces[id] = fc
		return &r.faces[id]
	}
	return nil
}

// font_for returns the cached Blend2D font for (id, size).
@(private)
font_for :: proc(r: ^Renderer, id: ui.Font_Id, size: f32, refs: []ui.Font_Ref) -> ^bl.FontCore {
	key := Font_Key{id, size}
	if fnt, ok := &r.fonts[key]; ok {
		return fnt
	}
	fc := face(r, id, refs)
	if fc == nil {
		return nil
	}
	fnt: bl.FontCore
	bl.font_init(&fnt)
	if bl.font_create_from_face(&fnt, fc, size) != 0 {
		bl.font_destroy(&fnt)
		return nil
	}
	r.fonts[key] = fnt
	return &r.fonts[key]
}
