package render

import "core:hash"
import "core:math"
import "core:mem"
import "core:slice"

import "jm:ui"
import bl "jm:ui/blend2d"

// TILE is the side of a damage tile in pixels.
TILE :: 64

// Damage finds the parts of a target that can differ from the previous
// frame. Each TILE×TILE tile keeps a hash of every draw touching it, in draw
// order; a tile whose hash changed is dirty.
//
// Scrolls: when the draws under an axis-aligned rect clip moved by one
// whole-pixel offset, the previous frame's tiles are rehashed as if that
// content had moved, and the region is reported as a Scroll whose pixels
// the caller moves before repainting. Only the uncovered strip and whatever
// else changed stay dirty. A region only scrolls when everything else drawn
// over it looks the same after the move.
//
// Zero it, or damage_init it to choose the allocator. Its buffers keep their
// capacity between frames, so a steady stream of similar frames allocates
// nothing. damage_update does one frame. To share the per-draw work out,
// call damage_begin, damage_draws over disjoint ranges from any threads,
// damage_find, damage_model over disjoint ranges of what it returns from
// any threads, then damage_finish.
Damage :: struct {
	size:       [2]i32,
	cols, rows: int,
	clear:      ui.Color,
	valid:      bool, // prev describes what the target holds
	curr, prev: [dynamic]u64, // tile hashes
	draws:      [dynamic]Draw_Rec, // this frame
	clips:      [dynamic]Clip_Rec,
	old_draws:  [dynamic]Draw_Rec, // the previous frame
	old_clips:  [dynamic]Clip_Rec,
	rects:      [dynamic]ui.Rect, // to repaint
	scrolls:    [dynamic]Scroll, // to apply before repainting
	glyph_box:  map[Font_Key]ui.Rect, // per font and size: the box every glyph fits, from its origin
	// resize_in_place says the target keeps its pixels across a change of
	// size, as a view into one buffer does. A new size then repaints only
	// what changed and what it uncovers, not the whole target. Leave it
	// false for a target reallocated at each size.
	resize_in_place: bool,
	resized:    bool, // this frame's size differs from the last one's
	scratch:    Damage_Scratch,
}

// Scroll moves the pixels inside rect by delta; pixels moved out of rect are
// dropped and the ones uncovered are among the rects to repaint.
Scroll :: struct {
	rect:  ui.Rect, // whole pixels
	delta: [2]i32,
}

// Draw_Rec is what damage keeps of one draw.
Draw_Rec :: struct {
	content: u64, // the command, without transform or clip
	local:   ui.Rect, // command bounds before the transform
	t:       ui.Affine,
	clip:    ui.Clip_Id,
	key:     u64, // content, transform and clip chain
	bounds:  ui.Rect, // device pixels it can touch, whole pixels; empty when none
	flat:    ui.Rect, // device rect where it paints one constant color, else empty
	// flat_local is flat before the transform and the clip, for the scroll
	// model to move; flat_key hashes what it paints there, the color alone.
	flat_local: ui.Rect,
	flat_key:   u64,
	hole:    ui.Rect, // device rect where it paints nothing, else empty
}

@(private)
Clip_Rec :: struct {
	parent:    ui.Clip_Id,
	shape:     u64,
	t:         ui.Affine,
	local:     ui.Rect,
	key:       u64, // shape and transform of this clip and its ancestors
	bounds:    ui.Rect, // device bounds of the chain
	// Whole pixels the chain's coverage can reach. A pixel two shapes each
	// cover in part gets both coverages multiplied, so this can be wider
	// than bounds, and a draw is bounded by it, not by bounds.
	reach:     ui.Rect,
	rect:      bool, // an axis-aligned Rect
	all_rects: bool, // this clip and every ancestor are rect
}

@(private)
Damage_Scratch :: struct {
	curr_keys:  map[u64]int, // clip key -> first clip with it, this frame
	old_keys:   map[u64]int, // the same for the previous frame
	anchors:    [dynamic]int, // per draw
	sigs:       [dynamic]u64, // per draw anchored to an all-rect clip chain: its signature
	old_anchor: [dynamic]int,
	anchoring:  bool, // damage_draws fills anchors and sigs this frame
	scrolled:   bool, // this frame found scrolls to model
	old_placed: [dynamic]Placed,
	new_placed: [dynamic]Placed,
	sort_tmp:   [dynamic]Placed,
	groups:     [dynamic]Group,
	votes:      map[[3]i64]int, // {region, dx, dy} -> pairs agreeing
	best:       map[int][3]i64, // region -> {dx, dy, votes} of its leading offset
	placed_ok:  bool, // new_placed and anchors describe the frame just recorded
	shift:      [dynamic]int, // per old clip: which found scroll moves it, or -1
	keys:       [dynamic]u64, // per old clip, as moved
	boxes:      [dynamic]ui.Rect,
	draw_keys:  [dynamic]u64, // per old draw, as moved
	draw_boxes: [dynamic]ui.Rect,
	draw_flats: [dynamic]ui.Rect, // per old draw, as moved
	geo:        [dynamic]ui.Rect, // per old clip, as moved: its chain's device bounds
	found:      [dynamic]Found_Scroll,
	last_run:   [dynamic]int, // bin's scratch: per tile, the run of the last draw binned
	strips:     [dynamic]ui.Rect, // pixels the found scrolls cannot fill
	pieces:     [dynamic]ui.Rect, // what is left of a strip once the rects before it are cut out
}

@(private)
Found_Scroll :: struct {
	curr, old: int, // the region's clip in each frame
	delta:     [2]i32,
	inner:     ui.Rect,
}

// damage_init makes d's buffers in allocator.
damage_init :: proc(d: ^Damage, allocator := context.allocator) {
	d.curr = make([dynamic]u64, allocator)
	d.prev = make([dynamic]u64, allocator)
	d.draws = make([dynamic]Draw_Rec, allocator)
	d.clips = make([dynamic]Clip_Rec, allocator)
	d.old_draws = make([dynamic]Draw_Rec, allocator)
	d.old_clips = make([dynamic]Clip_Rec, allocator)
	d.rects = make([dynamic]ui.Rect, allocator)
	d.scrolls = make([dynamic]Scroll, allocator)
	d.glyph_box = make(map[Font_Key]ui.Rect, allocator)
	s := &d.scratch
	s.curr_keys = make(map[u64]int, allocator)
	s.old_keys = make(map[u64]int, allocator)
	s.anchors = make([dynamic]int, allocator)
	s.sigs = make([dynamic]u64, allocator)
	s.old_anchor = make([dynamic]int, allocator)
	s.old_placed = make([dynamic]Placed, allocator)
	s.new_placed = make([dynamic]Placed, allocator)
	s.sort_tmp = make([dynamic]Placed, allocator)
	s.groups = make([dynamic]Group, allocator)
	s.votes = make(map[[3]i64]int, allocator)
	s.best = make(map[int][3]i64, allocator)
	s.shift = make([dynamic]int, allocator)
	s.keys = make([dynamic]u64, allocator)
	s.boxes = make([dynamic]ui.Rect, allocator)
	s.draw_keys = make([dynamic]u64, allocator)
	s.draw_boxes = make([dynamic]ui.Rect, allocator)
	s.draw_flats = make([dynamic]ui.Rect, allocator)
	s.geo = make([dynamic]ui.Rect, allocator)
	s.found = make([dynamic]Found_Scroll, allocator)
	s.last_run = make([dynamic]int, allocator)
	s.strips = make([dynamic]ui.Rect, allocator)
	s.pieces = make([dynamic]ui.Rect, allocator)
}

damage_destroy :: proc(d: ^Damage) {
	delete(d.curr)
	delete(d.prev)
	delete(d.draws)
	delete(d.clips)
	delete(d.old_draws)
	delete(d.old_clips)
	delete(d.rects)
	delete(d.scrolls)
	delete(d.glyph_box)
	s := &d.scratch
	delete(s.curr_keys)
	delete(s.old_keys)
	delete(s.anchors)
	delete(s.sigs)
	delete(s.old_anchor)
	delete(s.old_placed)
	delete(s.new_placed)
	delete(s.sort_tmp)
	delete(s.groups)
	delete(s.votes)
	delete(s.best)
	delete(s.shift)
	delete(s.keys)
	delete(s.boxes)
	delete(s.draw_keys)
	delete(s.draw_boxes)
	delete(s.draw_flats)
	delete(s.geo)
	delete(s.found)
	delete(s.last_run)
	delete(s.strips)
	delete(s.pieces)
	d^ = {}
}

// damage_invalidate makes the next frame report the whole target, for when
// its pixels changed behind the tracker's back.
damage_invalidate :: proc(d: ^Damage) {
	d.valid = false
}

// damage_update diffs f against the previous frame for a w×h target cleared
// to bg. fonts, when given, supplies the font metrics that bound text;
// without it text bounds are estimated from the font size. It returns the rects to repaint, clipped to the target and
// tile-aligned except for strips next to a scroll, and the scrolls to apply
// before repainting. The first frame, a
// size change or a new bg yields the whole target and no scrolls. Results
// are valid until the next update.
damage_update :: proc(d: ^Damage, f: ^ui.Frame, w, h: i32, bg: ui.Color, fonts: ^Renderer = nil) -> ([]ui.Rect, []Scroll) {
	damage_begin(d, f, w, h, bg, fonts)
	damage_draws(d, f, 0, len(f.draws))
	damage_model(d, 0, damage_find(d))
	return damage_finish(d)
}

// damage_begin records f's clips, looks up the metrics of every font f's
// text uses (see damage_update) and sizes the per-draw records.
damage_begin :: proc(d: ^Damage, f: ^ui.Frame, w, h: i32, bg: ui.Color, fonts: ^Renderer = nil) {
	if d.clear != bg {
		d.valid = false
	}
	d.resized = d.size != {w, h}
	if d.resized && !(d.valid && d.resize_in_place) {
		d.valid = false
	}
	old_size, old_cols := d.size, d.cols
	d.size = {w, h}
	d.clear = bg
	d.cols = (int(w) + TILE - 1) / TILE
	d.rows = (int(h) + TILE - 1) / TILE
	if d.resized && d.valid {
		regrid(d, old_size, old_cols)
	}
	resize(&d.clips, len(f.clips))
	for c, i in f.clips {
		rec := Clip_Rec {
			parent = c.parent,
			shape  = hash_shape(ui.FNV_OFFSET, f.ops, c.shape),
			t      = c.transform,
			local  = ui.shape_bounds(f.ops, c.shape),
		}
		_, is_rect := c.shape.(ui.Rect)
		rec.rect = is_rect && ui.is_axis_aligned(c.transform)
		parent_key, parent_box, parent_reach, parent_rects := ui.FNV_OFFSET, EVERYWHERE, EVERYWHERE, true
		if c.parent != ui.NO_CLIP {
			p := &d.clips[c.parent] // flatten appends a parent before its children
			parent_key, parent_box, parent_reach, parent_rects = p.key, p.bounds, p.reach, p.all_rects
		}
		rec.key = hash_affine(hash_value(parent_key, rec.shape), rec.t)
		rec.bounds = ui.rect_intersect(ui.transform_rect(rec.t, rec.local), parent_box)
		rec.reach = ui.rect_intersect(pixel_bounds(ui.transform_rect(rec.t, rec.local)), parent_reach)
		rec.all_rects = rec.rect && parent_rects
		d.clips[i] = rec
	}
	if fonts != nil {
		last := Font_Key{max(ui.Font_Id), -1}
		for run in f.ops.runs {
			key := Font_Key{run.font, run.size}
			if key == last || key in d.glyph_box {
				last = key
				continue
			}
			last = key
			box: ui.Rect
			if fnt := font_for(fonts, run.font, run.size, f.ops.fonts[:]); fnt != nil {
				m: bl.FontMetrics
				if bl.font_get_metrics(fnt, &m) == 0 {
					box = {m.x_min, m.y_min, m.x_max - m.x_min, m.y_max - m.y_min}
				}
			}
			d.glyph_box[key] = box
		}
	}
	resize(&d.draws, len(f.draws))

	// Scroll detection anchors each draw to the innermost clip the previous
	// frame also has; damage_draws does it alongside the hashing. The
	// previous frame's anchors are kept for find_scrolls to reuse.
	s := &d.scratch
	s.old_anchor, s.anchors = s.anchors, s.old_anchor
	s.anchoring = d.valid && len(d.clips) > 0 && len(d.old_clips) > 0
	if s.anchoring {
		clear(&s.old_keys)
		for c, i in d.old_clips {
			if c.key not_in s.old_keys {
				s.old_keys[c.key] = i
			}
		}
		resize(&s.anchors, len(f.draws))
		resize(&s.sigs, len(f.draws))
	}
}

// damage_draws records draws lo ..< hi. Calls on disjoint ranges may run on
// different threads between damage_begin and damage_find.
damage_draws :: proc(d: ^Damage, f: ^ui.Frame, lo, hi: int) {
	s := &d.scratch
	for i in lo ..< hi {
		d.draws[i] = draw_rec(f, d.clips[:], &d.glyph_box, &f.draws[i])
		if !s.anchoring {
			continue
		}
		a := anchor(d.clips[:], f.draws[i].clip, &s.old_keys)
		s.anchors[i] = a
		if a >= 0 && d.clips[a].all_rects {
			s.sigs[i] = signature(d.clips[:], &d.draws[i], a)
		}
	}
}

// flat_rect is the whole device pixels inside local under t, less a pixel
// along the edge of the clip bounds clip.
@(private)
flat_rect :: proc(t: ui.Affine, local, clip: ui.Rect) -> ui.Rect {
	d := ui.transform_rect(t, local)
	x0, y0 := math.ceil(d.x), math.ceil(d.y)
	x1, y1 := math.floor(d.x + d.w), math.floor(d.y + d.h)
	if x1 <= x0 || y1 <= y0 {
		return {}
	}
	return ui.rect_intersect({x0, y0, x1 - x0, y1 - y0}, outset(clip, -1))
}

// FLAT_TAG marks a flat_key, so a flat fill never hashes like another draw.
@(private)
FLAT_TAG :: u64(0x464c41545f46494c)

// STALE is the hash of a tile whose pixels were never drawn: one a resize
// uncovered. A drawn tile's hash is a 64-bit FNV-1a chain, so it equals
// STALE, and stays clean when it should repaint, with odds of 1 in 2^64.
@(private)
STALE :: u64(0x5354414c455f5449)

// regrid carries the previous frame's tile hashes from a grid of old_cols
// columns over old_size to the current one. A tile keeps its hash only when
// all of it that lies inside the new size lay inside the old one; the rest
// were uncovered, and hold nothing drawn.
@(private)
regrid :: proc(d: ^Damage, old_size: [2]i32, old_cols: int) {
	n := d.cols * d.rows
	resize(&d.curr, n)
	for ty in 0 ..< d.rows {
		for tx in 0 ..< d.cols {
			x1 := min((tx + 1) * TILE, int(d.size.x))
			y1 := min((ty + 1) * TILE, int(d.size.y))
			kept := x1 <= int(old_size.x) && y1 <= int(old_size.y)
			d.curr[ty * d.cols + tx] = d.prev[ty * old_cols + tx] if kept else STALE
		}
	}
	d.prev, d.curr = d.curr, d.prev
}

// damage_find looks for scrolls between the recorded frame and the
// previous one, and returns how many of the previous frame's draws
// damage_model must then see; zero when nothing scrolled.
damage_find :: proc(d: ^Damage) -> int {
	n := d.cols * d.rows
	resize(&d.curr, n)
	resize(&d.prev, n)
	clear(&d.rects)
	clear(&d.scrolls)
	bin(d.curr[:], d.cols, d.rows, d.draws[:], d.clips[:], &d.scratch.last_run)
	s := &d.scratch
	s.scrolled = false
	if !d.valid {
		s.placed_ok = false
		return 0
	}
	// A resize frame does not scroll: the scroll model rebuilds the previous
	// frame's tiles, which would forget the ones the resize uncovered. Nor
	// does it record this frame's placed draws for the next frame to reuse.
	if d.resized {
		s.placed_ok = false
		return 0
	}
	if !find_scrolls(d) {
		return 0
	}
	s.scrolled = true
	model_clips(d)
	return len(d.old_draws)
}

// damage_finish works out what to repaint and files the recorded frame as
// the previous one; see damage_update for the results.
damage_finish :: proc(d: ^Damage) -> ([]ui.Rect, []Scroll) {
	s := &d.scratch
	if !d.valid {
		append(&d.rects, ui.Rect{0, 0, f32(d.size.x), f32(d.size.y)})
	} else {
		if s.scrolled {
			model_finish(d)
		}
		dirty_rects(d)
		if s.scrolled {
			// The rects must not overlap: workers paint them at once, and two
			// painting one pixel would blend a translucent draw into it twice.
			// Each strip goes in less what is already there.
			full := ui.Rect{0, 0, f32(d.size.x), f32(d.size.y)}
			for r in s.strips {
				c := ui.rect_intersect(r, full)
				if c.w <= 0 || c.h <= 0 {
					continue
				}
				clear(&s.pieces)
				append(&s.pieces, c)
				for q in d.rects {
					n := len(s.pieces)
					for i in 0 ..< n {
						parts, count := subtract(s.pieces[i], q)
						append(&s.pieces, ..parts[:count])
					}
					remove_range(&s.pieces, 0, n)
				}
				append(&d.rects, ..s.pieces[:])
			}
		}
	}
	d.prev, d.curr = d.curr, d.prev
	d.old_draws, d.draws = d.draws, d.old_draws
	d.old_clips, d.clips = d.clips, d.old_clips
	d.valid = true
	return d.rects[:], d.scrolls[:]
}

// subtract cuts b out of a, leaving up to four rects: full-width bands
// above and below b, then the parts beside it.
@(private)
subtract :: proc(a, b: ui.Rect) -> (out: [4]ui.Rect, n: int) {
	i := ui.rect_intersect(a, b)
	if i.w <= 0 || i.h <= 0 {
		out[0] = a
		return out, 1
	}
	ax1, ay1 := a.x + a.w, a.y + a.h
	ix1, iy1 := i.x + i.w, i.y + i.h
	parts := [4]ui.Rect {
		{a.x, a.y, a.w, i.y - a.y},
		{a.x, iy1, a.w, ay1 - iy1},
		{a.x, i.y, i.x - a.x, i.h},
		{ix1, i.y, ax1 - ix1, i.h},
	}
	for p in parts {
		if p.w > 0 && p.h > 0 {
			out[n] = p
			n += 1
		}
	}
	return out, n
}

@(private)
EVERYWHERE :: ui.Rect{-1e7, -1e7, 2e7, 2e7}

// draw_rec hashes what decides d's pixels and works out where it can paint.
// It only reads glyph_box, so calls may run on several threads at once.
@(private)
draw_rec :: proc(f: ^ui.Frame, clips: []Clip_Rec, glyph_box: ^map[Font_Key]ui.Rect, d: ^ui.Draw) -> Draw_Rec {
	ops := f.ops
	rec := Draw_Rec {
		t    = d.transform,
		clip = d.clip,
	}
	h := ui.FNV_OFFSET
	switch c in d.cmd {
	case ui.Fill:
		h = hash_paint(hash_shape(hash_value(h, 1), ops, c.shape), c.paint)
		rec.local = ui.shape_bounds(ops, c.shape)
	case ui.Stroke:
		h = hash_value(hash_paint(hash_shape(hash_value(h, 2), ops, c.shape), c.paint), c.style)
		// Two widths covers a miter at Blend2D's default limit.
		rec.local = outset(ui.shape_bounds(ops, c.shape), 2 * c.style.width)
	case ui.Glyphs:
		if int(c.run) < len(ops.runs) {
			run := ops.runs[c.run]
			h = hash_value(hash_value(hash_value(h, 3), run.font), run.size)
			h = hash.fnv64a(mem.slice_to_bytes(run.glyphs), h)
			h = hash_value(hash_value(h, c.origin), c.color)
			rec.local = glyphs_bounds(run, c.origin, glyph_box)
		}
	case ui.Image:
		h = hash_value(hash_value(h, 4), c)
		rec.local = c.dst if c.dst.w > 0 && c.dst.h > 0 else EVERYWHERE
	}
	rec.content = h
	clip_key, clip_box, clip_reach, clip_rects := ui.FNV_OFFSET, EVERYWHERE, EVERYWHERE, true
	if d.clip != ui.NO_CLIP {
		cl := &clips[d.clip]
		clip_key, clip_box, clip_reach, clip_rects = cl.key, cl.bounds, cl.reach, cl.all_rects
	}
	rec.key = hash_affine(hash_value(clip_key, h), rec.t)
	rec.bounds = ui.rect_intersect(pixel_bounds(ui.transform_rect(rec.t, rec.local)), clip_reach)

	// What a scroll beneath may rely on: a solid axis-aligned fill is one
	// color inside its corners and its clip's inner edge, and a stroked box
	// paints nothing well inside its line.
	if !ui.is_axis_aligned(rec.t) {
		return rec
	}
	#partial switch c in d.cmd {
	case ui.Fill:
		if _, solid := c.paint.(ui.Color); solid && clip_rects {
			// A rect's edges need no margin: the whole pixels inside it are
			// fully covered. A round rect's corners do.
			_, square := c.shape.(ui.Rect)
			if r, ok := box_inside(c.shape, 0 if square else 1); ok {
				rec.flat = flat_rect(rec.t, r, clip_box)
				rec.flat_local = r
				rec.flat_key = hash_value(hash_value(ui.FNV_OFFSET, FLAT_TAG), c.paint.(ui.Color))
			}
		}
	case ui.Stroke:
		if r, ok := box_inside(c.shape, c.style.width / 2 + 1); ok {
			rec.hole = ui.transform_rect(rec.t, r)
		}
	}
	return rec
}

// glyphs_bounds is where a run drawn at origin can paint: the font's glyph
// box at every glyph position. A font without metrics falls back to a
// size-relative box around the advance.
@(private)
glyphs_bounds :: proc(run: ui.Glyph_Run, origin: ui.Point, glyph_box: ^map[Font_Key]ui.Rect) -> ui.Rect {
	box, ok := glyph_box[Font_Key{run.font, run.size}]
	if !ok || box.w <= 0 || box.h <= 0 || len(run.glyphs) == 0 {
		s := run.size
		return {origin.x - s * 0.5, origin.y - s * 1.5, run.advance + s, s * 2.2}
	}
	lo := [2]f32{run.glyphs[0].x, run.glyphs[0].y}
	hi := lo
	for g in run.glyphs[1:] {
		lo = {min(lo.x, g.x), min(lo.y, g.y)}
		hi = {max(hi.x, g.x), max(hi.y, g.y)}
	}
	x0, y0 := origin.x + lo.x + box.x, origin.y + lo.y + box.y
	return {x0, y0, origin.x + hi.x + box.x + box.w - x0, origin.y + hi.y + box.y + box.h - y0}
}

// box_inside is the part of a Rect or Round_Rect at least margin inside its
// outline. A rounded corner's arc reaches radius*(1 - 1/√2) further in.
@(private)
box_inside :: proc(s: ui.Shape, margin: f32) -> (ui.Rect, bool) {
	#partial switch v in s {
	case ui.Rect:
		return outset(v, -margin), true
	case ui.Round_Rect:
		return outset(v.rect, -(margin + v.radius * (1 - math.SQRT_TWO / 2))), true
	}
	return {}, false
}

// pixel_bounds grows r by a pixel of antialiasing and out to whole pixels.
@(private)
pixel_bounds :: proc(r: ui.Rect) -> ui.Rect {
	if r.w <= 0 || r.h <= 0 {
		return {}
	}
	x0 := math.floor(r.x - 1)
	y0 := math.floor(r.y - 1)
	return {x0, y0, math.ceil(r.x + r.w + 1) - x0, math.ceil(r.y + r.h + 1) - y0}
}

// bin folds each draw's key into the tiles its bounds touch, in draw order.
// Given keys and boxes, draw i is binned as keys[i] over boxes[i] instead.
//
// render draws a run of consecutive draws under a clip that needs a mask as
// one group, so the clip's edge covers them once; which draws share a run
// changes pixels even when a draw that splits the run lies elsewhere. So a
// draw under such a clip also folds in whether it is in the same run as the
// draw before it in the tile. last is scratch, one entry per tile.
//
// A tile a solid fill covers completely gets the fill's color alone,
// flat_key: the fill paints that tile the same whatever its size or place,
// so a background or panel that grows with the window changes only the
// tiles along its edges. Whole tiles are tested, not the part inside the
// target, so a tile does not change key when only the target's size does.
// flats, given with keys, are the draws' flat rects as moved.
@(private)
bin :: proc(tiles: []u64, cols, rows: int, draws: []Draw_Rec, clips: []Clip_Rec, last: ^[dynamic]int, keys: []u64 = nil, boxes: []ui.Rect = nil, flats: []ui.Rect = nil) {
	for &t in tiles {
		t = ui.FNV_OFFSET
	}
	resize(last, len(tiles))
	for &l in last {
		l = -1
	}
	run := 0
	for &dr, i in draws {
		if i > 0 && dr.clip != draws[i - 1].clip {
			run += 1
		}
		k, b, flat := dr.key, dr.bounds, dr.flat
		if keys != nil {
			k, b, flat = keys[i], boxes[i], flats[i]
		}
		if b.w <= 0 || b.h <= 0 {
			continue
		}
		masked := dr.clip != ui.NO_CLIP && !clips[dr.clip].all_rects
		x0 := clamp(int(b.x) / TILE, 0, cols - 1)
		y0 := clamp(int(b.y) / TILE, 0, rows - 1)
		x1 := clamp(int(b.x + b.w - 1) / TILE, 0, cols - 1)
		y1 := clamp(int(b.y + b.h - 1) / TILE, 0, rows - 1)
		for ty in y0 ..= y1 {
			for tx in x0 ..= x1 {
				t := ty * cols + tx
				kt := k
				if flat.w > 0 {
					tile := ui.Rect{f32(tx * TILE), f32(ty * TILE), TILE, TILE}
					if contains(flat, tile) {
						kt = dr.flat_key
					}
				}
				h := hash_value(tiles[t], kt)
				if masked {
					h = hash_value(h, last[t] == run)
				}
				tiles[t] = h
				last[t] = run
			}
		}
	}
}

// dirty_rects merges dirty tiles into runs along each row, then
// stacks runs with the same span on consecutive rows.
@(private)
dirty_rects :: proc(d: ^Damage) {
	w, h := f32(d.size.x), f32(d.size.y)
	dirty :: proc(d: ^Damage, i: int) -> bool {
		return d.curr[i] != d.prev[i]
	}
	for ty in 0 ..< d.rows {
		row := ty * d.cols
		tx := 0
		for tx < d.cols {
			if !dirty(d, row + tx) {
				tx += 1
				continue
			}
			x0 := tx
			for tx < d.cols && dirty(d, row + tx) {
				tx += 1
			}
			r := ui.Rect{f32(x0 * TILE), f32(ty * TILE), f32((tx - x0) * TILE), TILE}
			r.w = min(r.w, w - r.x)
			r.h = min(r.h, h - r.y)
			merged := false
			for &q in d.rects {
				if q.x == r.x && q.w == r.w && q.y + q.h == r.y {
					q.h += r.h
					merged = true
					break
				}
			}
			if !merged {
				append(&d.rects, r)
			}
		}
	}
}

// anchor is the innermost clip in id's chain whose key the other frame also
// has, or -1.
@(private)
anchor :: proc(clips: []Clip_Rec, id: ui.Clip_Id, other: ^map[u64]int) -> int {
	for c := id; c != ui.NO_CLIP; c = clips[c].parent {
		if clips[c].key in other {
			return int(c)
		}
	}
	return -1
}

// signature hashes a draw relative to its anchor a: everything except how
// far the anchor's content has scrolled.
@(private)
signature :: proc(clips: []Clip_Rec, dr: ^Draw_Rec, a: int) -> u64 {
	h := hash_value(hash_value(dr.content, [4]f64{dr.t.a, dr.t.b, dr.t.c, dr.t.d}), clips[a].key)
	for c := dr.clip; c != ui.NO_CLIP && int(c) != a; c = clips[c].parent {
		cl := &clips[c]
		h = hash_value(hash_value(h, cl.shape), [4]f64{cl.t.a, cl.t.b, cl.t.c, cl.t.d})
		h = hash_value(h, [2]i64{quantize(cl.t.e - dr.t.e), quantize(cl.t.f - dr.t.f)})
	}
	return h
}

// PAIR_BUDGET caps the look-alike pairs a frame spends finding offsets, and
// CONFIRM_SAMPLES the draws per region it checks one against.
@(private)
PAIR_BUDGET :: 1 << 12
@(private)
CONFIRM_SAMPLES :: 256

// Group is a run of draws sharing a signature in each frame's placed list.
@(private)
Group :: struct {
	old_lo, old_hi: int,
	new_lo, new_hi: int,
}

// Placed is a draw under a candidate region: its signature, the region and
// where the draw sits, exactly and quantized.
@(private)
Placed :: struct {
	sig:    u64,
	region: int,
	e, f:   f64,
	q:      [2]i64,
	at:     u64, // pos(q)
}

// pos packs a quantized position into one ordered key. Each axis keeps 32
// bits, ±8 million pixels; beyond that positions may alias, which can only
// cost a match.
@(private)
pos :: proc(q: [2]i64) -> u64 {
	return u64(u32(q[0]) ~ 0x8000_0000) << 32 | u64(u32(q[1]) ~ 0x8000_0000)
}

// placed lists the draws anchored to a clip whose chain is all axis-aligned
// rects, sorted by signature and then position; tmp is scratch for the
// sort. sigs, when given, holds the draws' signatures already worked out.
// A clip under any other shape cannot scroll: its parent's mask stays put
// while the pixels under it move.
@(private)
placed :: proc(out, tmp: ^[dynamic]Placed, draws: []Draw_Rec, clips: []Clip_Rec, anchors: []int, sigs: []u64 = nil) {
	clear(out)
	for &dr, i in draws {
		a := anchors[i]
		if a >= 0 && clips[a].all_rects {
			q := [2]i64{quantize(dr.t.e), quantize(dr.t.f)}
			sig := sigs[i] if sigs != nil else signature(clips, &dr, a)
			append(out, Placed{sig, a, dr.t.e, dr.t.f, q, pos(q)})
		}
	}
	sort_placed(out, tmp)
}

// sort_placed orders list by signature, then position, with a byte-wise
// LSD radix sort: a comparison sort took four times as long on the tens of
// thousands of draws of a 4K frame. Bytes that are equal throughout the
// list are skipped.
@(private)
sort_placed :: proc(list, tmp: ^[dynamic]Placed) {
	n := len(list)
	resize(tmp, n)
	src, dst := list[:], tmp[:]
	for pass in 0 ..< 16 {
		shift := u64(pass % 8) * 8
		digit :: proc(p: ^Placed, pass: int, shift: u64) -> int {
			return int(((p.at if pass < 8 else p.sig) >> shift) & 0xFF)
		}
		counts: [257]int
		for &p in src {
			counts[digit(&p, pass, shift) + 1] += 1
		}
		if slice.contains(counts[1:], n) {
			continue
		}
		for b in 0 ..< 256 {
			counts[b + 1] += counts[b]
		}
		for &p in src {
			b := digit(&p, pass, shift)
			dst[counts[b]] = p
			counts[b] += 1
		}
		src, dst = dst, src
	}
	if raw_data(src) != raw_data(list[:]) {
		copy(list[:], src)
	}
}

// has_placed reports whether sorted list holds a draw with sig at q.
@(private)
has_placed :: proc(list: []Placed, sig: u64, q: [2]i64) -> bool {
	at := pos(q)
	lo, hi := 0, len(list)
	for lo < hi {
		mid := (lo + hi) / 2
		m := &list[mid]
		if m.sig < sig || (m.sig == sig && m.at < at) {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return lo < len(list) && list[lo].sig == sig && list[lo].at == at
}

// find_scrolls looks for rect clips kept from the previous frame whose
// content moved by one whole-pixel offset, and keeps the ones safe to move.
@(private)
find_scrolls :: proc(d: ^Damage) -> bool {
	s := &d.scratch
	clear(&s.found)
	reuse := s.placed_ok
	s.placed_ok = false
	if len(d.clips) == 0 || len(d.old_clips) == 0 {
		return false
	}

	// Every draw is anchored to the innermost clip both frames have; the new
	// frame's draws were anchored as they were recorded. The previous
	// frame's anchors and placed list, worked out when it was the new frame,
	// are reused. They were anchored against the frame before it; that can
	// only cost matches, never pixels, because the safety check and the
	// shifted model read the same anchors.
	if reuse && len(s.old_anchor) == len(d.old_draws) {
		s.old_placed, s.new_placed = s.new_placed, s.old_placed
	} else {
		reuse = false
		clear(&s.curr_keys)
		for c, i in d.clips {
			if c.key not_in s.curr_keys {
				s.curr_keys[c.key] = i
			}
		}
		resize(&s.old_anchor, len(d.old_draws))
		for &dr, i in d.old_draws {
			s.old_anchor[i] = anchor(d.old_clips[:], dr.clip, &s.curr_keys)
		}
	}

	// Candidates: each draw votes for how far its region moved, once per
	// draw of the previous frame that matches it but for position. The true
	// offset collects votes from every group while wrong pairings scatter.
	// Small groups say the most for the fewest pairs, so they go first until
	// the budget is spent; wide layouts repeat everything, so no group size
	// is ruled out.
	if !reuse {
		placed(&s.old_placed, &s.sort_tmp, d.old_draws[:], d.old_clips[:], s.old_anchor[:])
	}
	placed(&s.new_placed, &s.sort_tmp, d.draws[:], d.clips[:], s.anchors[:], s.sigs[:])
	s.placed_ok = true
	old_p, new_p := s.old_placed[:], s.new_placed[:]
	clear(&s.groups)
	for i, j := 0, 0; i < len(old_p) && j < len(new_p); {
		if old_p[i].sig < new_p[j].sig {
			i += 1
			continue
		}
		if new_p[j].sig < old_p[i].sig {
			j += 1
			continue
		}
		i1, j1 := i, j
		for i1 < len(old_p) && old_p[i1].sig == old_p[i].sig {
			i1 += 1
		}
		for j1 < len(new_p) && new_p[j1].sig == new_p[j].sig {
			j1 += 1
		}
		append(&s.groups, Group{i, i1, j, j1})
		i, j = i1, j1
	}
	slice.sort_by(s.groups[:], proc(x, y: Group) -> bool {
		return (x.old_hi - x.old_lo) * (x.new_hi - x.new_lo) < (y.old_hi - y.old_lo) * (y.new_hi - y.new_lo)
	})
	clear(&s.votes)
	budget := PAIR_BUDGET
	for g in s.groups {
		pairs := (g.old_hi - g.old_lo) * (g.new_hi - g.new_lo)
		if pairs > budget {
			break
		}
		budget -= pairs
		for n in new_p[g.new_lo:g.new_hi] {
			for o in old_p[g.old_lo:g.old_hi] {
				// Pairs that did not move vote too: content that repeats can
				// look scrolled by its period when nothing moved at all.
				dx, dy := n.e - o.e, n.f - o.f
				if abs(dx - math.round(dx)) <= 1e-3 && abs(dy - math.round(dy)) <= 1e-3 {
					s.votes[{i64(n.region), i64(math.round(dx)), i64(math.round(dy))}] += 1
				}
			}
		}
	}
	clear(&s.best)
	for k, n in s.votes {
		if i64(n) > s.best[int(k[0])].z {
			s.best[int(k[0])] = {k[1], k[2], i64(n)}
		}
	}

	// Confirmation: a region scrolls when at least half its draws have a
	// look-alike in the previous frame exactly one offset away. A spread of
	// up to CONFIRM_SAMPLES of them is checked.
	for a, cand in s.best {
		if cand.z < 2 || (cand.x == 0 && cand.y == 0) {
			continue
		}
		best := [2]i32{i32(cand.x), i32(cand.y)}
		members := 0
		for n in new_p {
			if n.region == a {
				members += 1
			}
		}
		every := max(1, members / CONFIRM_SAMPLES)
		total, hit, k := 0, 0, 0
		for n in new_p {
			if n.region != a {
				continue
			}
			k += 1
			if k % every != 0 {
				continue
			}
			total += 1
			if has_placed(old_p, n.sig, n.q - {i64(best.x) * 256, i64(best.y) * 256}) {
				hit += 1
			}
		}
		if hit < 2 || 2 * hit < total {
			continue
		}
		old := s.old_keys[d.clips[a].key]
		inner := inner_pixels(d.clips[a].bounds, d.size)
		if inner.w <= abs(f32(best.x)) || inner.h <= abs(f32(best.y)) {
			continue
		}
		if !safe_to_move(d.draws[:], s.anchors[:], a, inner) || !safe_to_move(d.old_draws[:], s.old_anchor[:], old, inner) {
			continue
		}
		overlaps := false
		for q in s.found {
			if ui.rect_intersect(q.inner, outset(inner, 1)).w > 0 {
				overlaps = true
			}
		}
		if !overlaps {
			append(&s.found, Found_Scroll{a, old, best, inner})
		}
	}
	return len(s.found) > 0
}

// inner_pixels is the whole pixels fully inside r and the target.
@(private)
inner_pixels :: proc(r: ui.Rect, size: [2]i32) -> ui.Rect {
	x0 := max(math.ceil(r.x), 0)
	y0 := max(math.ceil(r.y), 0)
	x1 := min(math.floor(r.x + r.w), f32(size.x))
	y1 := min(math.floor(r.y + r.h), f32(size.y))
	if x1 <= x0 || y1 <= y0 {
		return {}
	}
	return {x0, y0, x1 - x0, y1 - y0}
}

@(private)
contains :: proc(outer, inner: ui.Rect) -> bool {
	return(
		outer.w > 0 &&
		outer.h > 0 &&
		inner.x >= outer.x &&
		inner.y >= outer.y &&
		inner.x + inner.w <= outer.x + outer.w &&
		inner.y + inner.h <= outer.y + outer.h \
	)
}

// safe_to_move reports whether every draw over inner that is not the
// region's own content looks the same after the region's pixels move.
@(private)
safe_to_move :: proc(draws: []Draw_Rec, anchors: []int, a: int, inner: ui.Rect) -> bool {
	for &dr, i in draws {
		if anchors[i] == a || ui.rect_intersect(dr.bounds, inner).w <= 0 {
			continue
		}
		if !contains(dr.flat, inner) && !contains(dr.hole, inner) {
			return false
		}
	}
	return true
}

// The previous frame's tiles are rehashed as if every found region's
// content had moved: model_clips moves the clips, damage_model the draws,
// and model_finish bins them and forces the tiles a move cannot fill.
@(private)
model_clips :: proc(d: ^Damage) {
	s := &d.scratch
	// Clips below a region move with it; the region and its ancestors stay.
	resize(&s.shift, len(d.old_clips))
	resize(&s.keys, len(d.old_clips))
	resize(&s.boxes, len(d.old_clips))
	resize(&s.geo, len(d.old_clips))
	for c, i in d.old_clips {
		s.shift[i] = -1
		s.keys[i] = c.key
		s.boxes[i] = c.reach
		s.geo[i] = c.bounds
		if c.parent == ui.NO_CLIP {
			continue
		}
		for q, qi in s.found {
			if int(c.parent) == q.old {
				s.shift[i] = qi
			}
		}
		if s.shift[i] < 0 && s.shift[c.parent] >= 0 {
			s.shift[i] = s.shift[c.parent]
		}
		if s.shift[i] < 0 {
			continue
		}
		t := shifted(c.t, s.found[s.shift[i]].delta)
		s.keys[i] = hash_affine(hash_value(s.keys[c.parent], c.shape), t)
		s.boxes[i] = ui.rect_intersect(pixel_bounds(ui.transform_rect(t, c.local)), s.boxes[c.parent])
		s.geo[i] = ui.rect_intersect(ui.transform_rect(t, c.local), s.geo[c.parent])
	}

	resize(&s.draw_keys, len(d.old_draws))
	resize(&s.draw_boxes, len(d.old_draws))
	resize(&s.draw_flats, len(d.old_draws))
}

// damage_model moves the previous frame's draws lo ..< hi with the found
// scrolls. Calls on disjoint ranges may run on different threads between
// damage_find and damage_finish.
damage_model :: proc(d: ^Damage, lo, hi: int) {
	s := &d.scratch
	for i in lo ..< hi {
		dr := &d.old_draws[i]
		s.draw_keys[i], s.draw_boxes[i], s.draw_flats[i] = dr.key, dr.bounds, dr.flat
		qi := -1
		for q, n in s.found {
			if s.old_anchor[i] == q.old {
				qi = n
			}
		}
		if qi < 0 {
			continue
		}
		t := shifted(dr.t, s.found[qi].delta)
		clip_key, clip_box, clip_geo := ui.FNV_OFFSET, EVERYWHERE, EVERYWHERE
		if dr.clip != ui.NO_CLIP {
			clip_key, clip_box, clip_geo = s.keys[dr.clip], s.boxes[dr.clip], s.geo[dr.clip]
		}
		s.draw_keys[i] = hash_affine(hash_value(clip_key, dr.content), t)
		s.draw_boxes[i] = ui.rect_intersect(pixel_bounds(ui.transform_rect(t, dr.local)), clip_box)
		s.draw_flats[i] = {}
		if dr.flat_local.w > 0 {
			s.draw_flats[i] = flat_rect(t, dr.flat_local, clip_geo)
		}
	}
}

@(private)
model_finish :: proc(d: ^Damage) {
	s := &d.scratch
	bin(d.prev[:], d.cols, d.rows, d.old_draws[:], d.old_clips[:], &s.last_run, s.draw_keys[:], s.draw_boxes[:], s.draw_flats[:])

	// A move cannot fill the strip it uncovers, nor the partly covered
	// pixels along a fractional edge, which it leaves in place. Those are
	// repainted exactly, whatever their tiles' hashes say.
	clear(&s.strips)
	for q in s.found {
		r := q.inner
		dx, dy := f32(q.delta.x), f32(q.delta.y)
		if dy > 0 {
			append(&s.strips, ui.Rect{r.x, r.y, r.w, dy})
		} else if dy < 0 {
			append(&s.strips, ui.Rect{r.x, r.y + r.h + dy, r.w, -dy})
		}
		if dx > 0 {
			append(&s.strips, ui.Rect{r.x, r.y, dx, r.h})
		} else if dx < 0 {
			append(&s.strips, ui.Rect{r.x + r.w + dx, r.y, -dx, r.h})
		}
		b := d.clips[q.curr].bounds
		if b.x < r.x {
			append(&s.strips, ui.Rect{r.x - 1, r.y - 1, 1, r.h + 2})
		}
		if b.x + b.w > r.x + r.w {
			append(&s.strips, ui.Rect{r.x + r.w, r.y - 1, 1, r.h + 2})
		}
		if b.y < r.y {
			append(&s.strips, ui.Rect{r.x - 1, r.y - 1, r.w + 2, 1})
		}
		if b.y + b.h > r.y + r.h {
			append(&s.strips, ui.Rect{r.x - 1, r.y + r.h, r.w + 2, 1})
		}
		append(&d.scrolls, Scroll{r, q.delta})
	}
}

@(private)
shifted :: proc(t: ui.Affine, delta: [2]i32) -> ui.Affine {
	out := t
	out.e += f64(delta.x)
	out.f += f64(delta.y)
	return out
}

@(private)
outset :: proc(r: ui.Rect, d: f32) -> ui.Rect {
	return {r.x - d, r.y - d, r.w + 2 * d, r.h + 2 * d}
}

// quantize rounds a translation to 1/256 px, Blend2D's subpixel precision,
// so content moved by a whole offset hashes like the original moved.
@(private)
quantize :: proc(v: f64) -> i64 {
	return i64(math.round(v * 256))
}

@(private)
hash_affine :: proc(h: u64, t: ui.Affine) -> u64 {
	return hash_value(hash_value(h, [4]f64{t.a, t.b, t.c, t.d}), [2]i64{quantize(t.e), quantize(t.f)})
}

@(private)
hash_value :: proc(h: u64, v: $T) -> u64 {
	v := v
	return hash.fnv64a(mem.ptr_to_bytes(&v), h)
}

@(private)
hash_shape :: proc(h: u64, ops: ^ui.Ops, s: ui.Shape) -> u64 {
	switch v in s {
	case ui.Rect:
		return hash_value(hash_value(h, 1), v)
	case ui.Round_Rect:
		return hash_value(hash_value(h, 2), v)
	case ui.Ellipse:
		return hash_value(hash_value(h, 3), v)
	case ui.Path_Ref:
		if int(v.id) >= len(ops.paths) {
			return hash_value(h, 4)
		}
		p := ops.paths[v.id]
		out := hash.fnv64a(mem.slice_to_bytes(p.verbs), hash_value(h, 4))
		return hash.fnv64a(mem.slice_to_bytes(p.points), out)
	}
	return h
}

@(private)
hash_paint :: proc(h: u64, p: ui.Paint) -> u64 {
	switch v in p {
	case ui.Color:
		return hash_value(hash_value(h, 1), v)
	case ui.Linear_Gradient:
		out := hash_value(hash_value(hash_value(h, 2), v.p0), v.p1)
		return hash.fnv64a(mem.slice_to_bytes(v.stops), out)
	case ui.Radial_Gradient:
		out := hash_value(hash_value(hash_value(h, 3), v.center), v.radius)
		return hash.fnv64a(mem.slice_to_bytes(v.stops), out)
	case ui.Image_Paint:
		return hash_value(hash_value(h, 4), v.image)
	}
	return h
}
