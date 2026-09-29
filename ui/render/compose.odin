package render

import "core:mem"
import "core:sync"
import "core:thread"

import "jm:ui"
import bl "jm:ui/blend2d"

// Compositor repaints only what changed. Each compose diffs the frame
// against the previous one (see Damage), moves the pixels of scrolled
// regions, cuts the dirty rects into bands one tile high and renders the
// bands on a crew of workers, each with its own Renderer, straight into the
// target. The crew also shares the per-draw work of damage tracking on
// large frames, and the move of a large scroll. The
// target must keep its pixels from one compose to the next; call
// damage_invalidate(&c.damage) when it does not.
//
// Bands meet at tile edges, where Blend2D's antialiasing of a shape crossing
// the edge can differ from one whole-target render by a few steps in a
// channel; the fuzz suite in ui/render/fuzz holds it to three.
//
// A Compositor must not move after compositor_init.
Compositor :: struct {
	damage:    Damage,
	workers:   []Worker,
	threads:   []^thread.Thread,
	start:     sync.Barrier,
	done:      sync.Barrier,
	quit:      bool,
	phase:     enum u8 {
		Hash,
		Model,
		Move,
		Paint,
	},
	pixels:    bl.ImageData, // the target's, while composing
	move:      Scroll, // the one the Move phase is moving
	jobs:      [dynamic]ui.Rect, // bands to paint
	next:      int, // index of the next job or draw chunk, taken atomically
	count:     int, // draws the Hash or Model phase goes through
	frame:     ^ui.Frame,
	target:    ^bl.ImageCore,
	bg:        ui.Color,
	changed:   [dynamic]ui.Rect, // what compose returns
	row_start: [dynamic]int, // per tile row: where its draws start in row_draws
	row_draws: [dynamic]int, // draw indices touching each tile row, in draw order
	row_fill:  [dynamic]int,
	runs:      [dynamic]int, // per draw: which run of draws sharing a clip it is in
	allocator: mem.Allocator,
}

@(private)
Worker :: struct {
	c:   ^Compositor,
	r:   Renderer,
	sub: ui.Frame, // the draws of one band, shifted to its origin
}

// HASH_SHARED is the draw count from which the crew shares the per-draw
// work of damage tracking, HASH_CHUNK how many draws a worker takes per turn.
@(private)
HASH_SHARED :: 1024
@(private)
HASH_CHUNK :: 256

// A band thinner than THIN, such as the strip a scroll uncovers, is cut at
// multiples of BAND_W so the crew can share it. Thicker bands are not: each
// cut draws what spans it again: cutting every band at 1024 px took the
// full scene of ui-bench -compose at 4K from 2.5 to 3.2 ms.
@(private)
THIN :: TILE / 2
@(private)
BAND_W :: 4 * TILE

// MOVE_SHARED is the scrolled area, in pixels, from which the crew shares a
// move; MOVE_PARTS is how many parts each worker's share is cut into.
@(private)
MOVE_SHARED :: 1 << 18
@(private)
MOVE_PARTS :: 4

// compositor_init starts workers-1 threads; the thread calling compose is
// the last worker. Fewer than one worker counts as one. Every worker's
// Renderer allocates from allocator on its own thread, so with more than
// one worker it must be thread-safe: the default heap allocator is,
// core:mem's arenas, which take no lock, are not.
compositor_init :: proc(c: ^Compositor, workers: int, allocator := context.allocator) {
	n := max(workers, 1)
	c.allocator = allocator
	damage_init(&c.damage, allocator)
	c.jobs = make([dynamic]ui.Rect, allocator)
	c.changed = make([dynamic]ui.Rect, allocator)
	c.row_start = make([dynamic]int, allocator)
	c.row_draws = make([dynamic]int, allocator)
	c.row_fill = make([dynamic]int, allocator)
	c.runs = make([dynamic]int, allocator)
	c.workers = make([]Worker, n, allocator)
	for &w in c.workers {
		w.c = c
		init(&w.r, allocator)
		ui.frame_init(&w.sub, allocator)
	}
	if n == 1 {
		return
	}
	sync.barrier_init(&c.start, n)
	sync.barrier_init(&c.done, n)
	c.threads = make([]^thread.Thread, n - 1, allocator)
	for &t, i in c.threads {
		t = thread.create(worker_loop)
		t.data = &c.workers[i + 1]
		thread.start(t)
	}
}

// compositor_destroy stops the crew and releases everything c holds.
compositor_destroy :: proc(c: ^Compositor) {
	if len(c.threads) > 0 {
		sync.atomic_store(&c.quit, true)
		sync.barrier_wait(&c.start)
		for t in c.threads {
			thread.destroy(t)
		}
		delete(c.threads, c.allocator)
	}
	for &w in c.workers {
		destroy(&w.r)
		ui.frame_destroy(&w.sub)
	}
	delete(c.workers, c.allocator)
	delete(c.jobs)
	delete(c.changed)
	delete(c.row_start)
	delete(c.row_draws)
	delete(c.row_fill)
	delete(c.runs)
	damage_destroy(&c.damage)
	c^ = {}
}

// compose brings target up to date with f and returns the rects whose
// pixels changed, repainted or scrolled; nil when nothing did. target must
// be PRGB32. The result is valid until the next compose.
compose :: proc(c: ^Compositor, f: ^ui.Frame, target: ^bl.ImageCore, bg: ui.Color) -> []ui.Rect {
	data: bl.ImageData
	if bl.image_get_data(target, &data) != 0 || data.size.w <= 0 || data.size.h <= 0 {
		return nil
	}
	c.frame, c.target, c.bg = f, target, bg
	// Each worker's band buffers are sized for the whole frame up front:
	// which worker paints the largest band changes with scheduling, so
	// without this a frame that allocates nothing on one platform grows a
	// buffer mid-paint on another (CI's macOS runner, in paint_band).
	// A barrier can precede every kept draw, hence twice the draws.
	for &w in c.workers {
		reserve(&w.sub.draws, 2 * len(f.draws))
		reserve(&w.sub.clips, len(f.clips))
	}

	// Worker 0 is this thread, so its font cache is safe to use here.
	damage_open(&c.damage, f, data.size.w, data.size.h, bg, &c.workers[0].r)
	c.count = len(f.draws)
	if len(c.threads) > 0 && c.count > HASH_SHARED {
		run_phase(c, .Hash)
	} else {
		damage_draws(&c.damage, f, 0, c.count)
	}
	c.count = damage_find(&c.damage)
	if len(c.threads) > 0 && c.count > HASH_SHARED {
		run_phase(c, .Model)
	} else {
		damage_model(&c.damage, 0, c.count)
	}
	rects, scrolls := damage_close(&c.damage)

	clear(&c.changed)
	c.pixels = data
	for s in scrolls {
		if len(c.threads) > 0 && (s.delta.x == 0 || s.delta.y == 0) && s.rect.w * s.rect.h >= MOVE_SHARED {
			c.move = s
			run_phase(c, .Move)
		} else {
			move_part(&data, s, 0, 1)
		}
		append(&c.changed, s.rect)
	}
	if len(rects) == 0 {
		return c.changed[:] if len(c.changed) > 0 else nil
	}
	append(&c.changed, ..rects)

	// Bands never cross a tile row, and thin ones never a multiple of
	// BAND_W: that keeps masks band-sized, puts band edges in the same place
	// whatever the crew size, so the pixels do not depend on it, and lets a
	// band find its draws in one row's list.
	clear(&c.jobs)
	for r in rects {
		for y := r.y; y < r.y + r.h; {
			next_y := min(f32((int(y) / TILE + 1) * TILE), r.y + r.h)
			for x := r.x; x < r.x + r.w; {
				next_x := r.x + r.w
				if next_y - y < THIN {
					next_x = min(f32((int(x) / BAND_W + 1) * BAND_W), next_x)
				}
				append(&c.jobs, ui.Rect{x, y, next_x - x, next_y - y})
				x = next_x
			}
			y = next_y
		}
	}
	index_rows(c, c.damage.old_draws[:], c.damage.rows)
	number_runs(c, f)
	if len(c.threads) > 0 {
		run_phase(c, .Paint)
	} else {
		sync.atomic_store(&c.next, 0)
		drain(c, &c.workers[0])
	}
	return c.changed[:]
}

// run_phase has the whole crew, the caller included, work through phase.
@(private)
run_phase :: proc(c: ^Compositor, phase: type_of(c.phase)) {
	c.phase = phase
	sync.atomic_store(&c.next, 0)
	sync.barrier_wait(&c.start)
	work(c, &c.workers[0])
	sync.barrier_wait(&c.done)
}

@(private)
worker_loop :: proc(t: ^thread.Thread) {
	w := (^Worker)(t.data)
	c := w.c
	for {
		sync.barrier_wait(&c.start)
		if sync.atomic_load(&c.quit) {
			return
		}
		work(c, w)
		free_all(context.temp_allocator)
		sync.barrier_wait(&c.done)
	}
}

@(private)
work :: proc(c: ^Compositor, w: ^Worker) {
	switch c.phase {
	case .Hash, .Model:
		for {
			lo := sync.atomic_add(&c.next, HASH_CHUNK)
			if lo >= c.count {
				return
			}
			hi := min(lo + HASH_CHUNK, c.count)
			if c.phase == .Hash {
				damage_draws(&c.damage, c.frame, lo, hi)
			} else {
				damage_model(&c.damage, lo, hi)
			}
		}
	case .Move:
		n := len(c.workers) * MOVE_PARTS
		for {
			k := sync.atomic_add(&c.next, 1)
			if k >= n {
				return
			}
			move_part(&c.pixels, c.move, k, n)
		}
	case .Paint:
		drain(c, w)
	}
}

// drain paints jobs until none are left.
@(private)
drain :: proc(c: ^Compositor, w: ^Worker) {
	for {
		i := sync.atomic_add(&c.next, 1)
		if i >= len(c.jobs) {
			return
		}
		// damage_close has already filed this frame's records as the old ones.
		band := c.jobs[i]
		row := clamp(int(band.y) / TILE, 0, len(c.row_start) - 2)
		picks := c.row_draws[c.row_start[row]:c.row_start[row + 1]]
		paint_band(w, c.frame, c.target, band, c.damage.old_draws[:], picks, c.runs[:], c.bg)
	}
}

// index_rows lists, for each tile row, the draws whose bounds touch it, in
// draw order.
@(private)
index_rows :: proc(c: ^Compositor, recs: []Draw_Rec, rows: int) {
	resize(&c.row_start, rows + 1)
	mem.zero_slice(c.row_start[:])
	span :: proc(b: ui.Rect, rows: int) -> (int, int) {
		return clamp(int(b.y) / TILE, 0, rows - 1), clamp(int(b.y + b.h - 1) / TILE, 0, rows - 1)
	}
	for &rec in recs {
		if rec.bounds.w <= 0 || rec.bounds.h <= 0 {
			continue
		}
		y0, y1 := span(rec.bounds, rows)
		for r in y0 ..= y1 {
			c.row_start[r + 1] += 1
		}
	}
	for r in 0 ..< rows {
		c.row_start[r + 1] += c.row_start[r]
	}
	resize(&c.row_draws, c.row_start[rows])
	resize(&c.row_fill, rows)
	copy(c.row_fill[:], c.row_start[:rows])
	for &rec, i in recs {
		if rec.bounds.w <= 0 || rec.bounds.h <= 0 {
			continue
		}
		y0, y1 := span(rec.bounds, rows)
		for r in y0 ..= y1 {
			c.row_draws[c.row_fill[r]] = i
			c.row_fill[r] += 1
		}
	}
}

// move_part shifts part k of n of the pixels inside s.rect by s.delta. A
// vertical move is cut into bands of columns and any other into bands of
// rows, so parts touch disjoint pixels and may run at once; a move along
// both axes must be one part. Rows are copied in the order that never reads
// a row already overwritten.
@(private)
move_part :: proc(data: ^bl.ImageData, s: Scroll, k, n: int) {
	dx, dy := int(s.delta.x), int(s.delta.y)
	x0, y0 := int(s.rect.x), int(s.rect.y)
	cols := int(s.rect.w) - abs(dx)
	rows := int(s.rect.h) - abs(dy)
	if cols <= 0 || rows <= 0 {
		return
	}
	c0, c1 := 0, cols
	r0, r1 := 0, rows
	if dx == 0 {
		// Cut at target columns that are multiples of 16: 16 PRGB32 pixels
		// are 64 bytes, x86-64's cache line, so on a target whose rows
		// start on one no two parts write the same line.
		cut :: proc(x0, cols, k, n: int) -> int {
			if k == 0 || k == n {
				return 0 if k == 0 else cols
			}
			return clamp((x0 + cols * k / n) &~ 15 - x0, 0, cols)
		}
		c0, c1 = cut(x0, cols, k, n), cut(x0, cols, k + 1, n)
	} else {
		r0, r1 = rows * k / n, rows * (k + 1) / n
	}
	if c1 <= c0 {
		return
	}
	src_x := x0 + max(-dx, 0) + c0
	dst_x := x0 + max(dx, 0) + c0
	stride := int(data.stride)
	for i in r0 ..< r1 {
		r := i if dy <= 0 else r0 + r1 - 1 - i
		src_y := y0 + max(-dy, 0) + r
		dst_y := y0 + max(dy, 0) + r
		src := rawptr(uintptr(data.pixel_data) + uintptr(src_y * stride + src_x * 4))
		dst := rawptr(uintptr(data.pixel_data) + uintptr(dst_y * stride + dst_x * 4))
		mem.copy(dst, src, (c1 - c0) * 4)
	}
}

// number_runs numbers the runs of consecutive draws sharing a clip, which
// render draws as one group under a clip that needs a mask.
@(private)
number_runs :: proc(c: ^Compositor, f: ^ui.Frame) {
	resize(&c.runs, len(f.draws))
	run := 0
	for d, i in f.draws {
		if i > 0 && d.clip != f.draws[i - 1].clip {
			run += 1
		}
		c.runs[i] = run
	}
}

// barrier draws nothing and has no clip: between two draws it keeps render
// from grouping them.
@(private)
barrier := ui.Draw{ui.IDENTITY, ui.NO_CLIP, ui.Fill{ui.Rect{}, ui.Color{}}}

// paint_band renders the draws of f that touch r into the part of target
// under r, through a view that shares target's pixels. picks are the
// indices of the draws that may touch r, in order; recs are f's draw
// records, whose bounds decide.
@(private)
paint_band :: proc(w: ^Worker, f: ^ui.Frame, target: ^bl.ImageCore, r: ui.Rect, recs: []Draw_Rec, picks: []int, runs: []int, bg: ui.Color) {
	sub := &w.sub
	clear(&sub.draws)
	clear(&sub.clips)
	sub.ops = f.ops
	shift := ui.translate(-r.x, -r.y)
	for cl in f.clips {
		append(&sub.clips, ui.Clip{cl.parent, cl.shape, ui.mul(cl.transform, shift)})
	}
	// Draws left out of the band can sit between two it keeps. Two kept draws
	// under one clip were grouped in the whole frame only if they were in one
	// run, so a barrier keeps them apart when they were not: the clip's edge
	// must cover them as it does in a whole render.
	last := -1
	for i in picks {
		if ui.rect_intersect(recs[i].bounds, r).w <= 0 {
			continue
		}
		d := f.draws[i]
		if last >= 0 && d.clip == f.draws[last].clip && runs[i] != runs[last] {
			append(&sub.draws, barrier)
		}
		append(&sub.draws, ui.Draw{ui.mul(d.transform, shift), d.clip, d.cmd})
		last = i
	}

	data: bl.ImageData
	if bl.image_get_data(target, &data) != 0 {
		return
	}
	px := rawptr(uintptr(data.pixel_data) + uintptr(int(r.y) * int(data.stride) + int(r.x) * 4))
	view: bl.ImageCore
	bl.image_init(&view)
	defer bl.image_destroy(&view)
	if bl.image_create_from_data(&view, i32(r.w), i32(r.h), .PRGB32, px, int(data.stride), .RW, nil, nil) != 0 {
		return
	}
	render(&w.r, sub, &view, bg)
}
