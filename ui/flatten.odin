package ui

import "jm:ui/ops"

// MAX_CALL_DEPTH bounds macro Call nesting in flatten. Each level is one
// native stack frame of flatten_range, so 64 is far below any stack limit;
// a deeper chain, or a macro that calls itself, trips an assert.
MAX_CALL_DEPTH :: 64

@(private = "file")
Flattener :: struct {
	scene:        ^ops.Scene,
	f:          ^Frame,
	using stacks: ^Flatten_Stacks, // f's, reused frame to frame
	transform:  ops.Affine,
	clip:       Clip_Id,
	layer:      i32, // 0 for the frame, then 1, 2, ... for each deferred macro in the order run
	viewport:   ops.Rect, // device space; zero leaves popups where they ask to be
	root:       ops.Affine, // what a root Defer runs under
}

// flatten turns the scene sc into f: every draw and hit carries its device
// transform and a clip reference. f is reset first and keeps a pointer to
// sc for its resources. viewport is the window in device pixels: a placed
// popup (ops.Placement) is kept inside it, and a zero viewport leaves
// popups where they ask to be. root is the transform a root Defer runs
// under: the host's scale from logical units to device pixels, the same
// one it pushes around the ui proc. Unbalanced push/pop, a Call to an
// unterminated or unknown macro, or calls nested deeper than
// MAX_CALL_DEPTH assert.
flatten :: proc(sc: ^ops.Scene, f: ^Frame, viewport := ops.Rect{}, root := ops.IDENTITY) {
	frame_reset(f)
	f.scene = sc
	st := Flattener {
		scene        = sc,
		f          = f,
		stacks     = &f.stacks,
		transform  = ops.IDENTITY,
		clip       = NO_CLIP,
		viewport   = viewport,
		root       = root,
	}
	flatten_range(&st, 0, len(sc.ops), 0)
	// Deferred macros run last, in the order met, so their draws and hits
	// sit above everything else; one deferred from inside another runs
	// after it. A covering one runs in the order of its container's end
	// instead, and one covering the window once nothing else is left;
	// a top one after all of those. Each starts unclipped.
	for i := 0; ; i += 1 {
		if i == len(st.deferred) {
			if len(st.held) == 0 {
				if len(st.top) == 0 {
					break
				}
				append(&st.deferred, ..st.top[:])
				clear(&st.top)
			} else {
				release_held(&st, 0, all = true)
			}
		}
		d := st.deferred[i]
		m := sc.macros[d.id]
		st.transform, st.clip = d.transform, NO_CLIP
		st.layer = i32(i + 1)
		flatten_range(&st, m.first, m.last, 1)
	}
	assert(len(st.transforms) == 0, "flatten: transform_push without transform_pop")
	assert(len(st.clips) == 0, "flatten: clip_push without clip_pop")
}

// flatten_range runs sc[lo:hi]. Pops may not reach below the stack depths
// seen on entry, and a range must leave both stacks as it found them.
@(private = "file")
flatten_range :: proc(st: ^Flattener, lo, hi: int, depth: int) {
	base_t, base_c := len(st.transforms), len(st.clips)
	sc := st.scene.ops[:]
	i := lo
	for i < hi {
		switch op in sc[i] {
		case ops.Push_Transform:
			append(&st.transforms, st.transform)
			st.transform = ops.mul(op.m, st.transform)
		case ops.Push_Sticky:
			append(&st.transforms, st.transform)
			st.transform = ops.mul(sticky_shift(st, op), st.transform)
		case ops.Pop_Transform:
			assert(len(st.transforms) > base_t, "flatten: transform_pop with nothing pushed")
			st.transform = pop(&st.transforms)
		case ops.Push_Clip:
			append(&st.clips, st.clip)
			append(&st.f.clips, Clip{parent = st.clip, shape = op.shape, transform = st.transform})
			st.clip = Clip_Id(len(st.f.clips) - 1)
		case ops.Pop_Clip:
			assert(len(st.clips) > base_c, "flatten: clip_pop with nothing pushed")
			st.clip = pop(&st.clips)
		case ops.Macro_Begin:
			assert(int(op.id) < len(st.scene.macros), "flatten: macro_open names an unknown macro")
			last := st.scene.macros[op.id].last
			// An unterminated macro swallows the rest of the range.
			i = hi if last < 0 else max(i, min(last, hi))
		case ops.Macro_End:
		// Only reached for a stray end; bodies are skipped past theirs.
		case ops.Call:
			assert(int(op.id) < len(st.scene.macros), "flatten: call names an unknown macro")
			m := st.scene.macros[op.id]
			assert(m.last >= 0, "flatten: call to an unterminated macro")
			assert(0 <= m.first && m.first <= m.last && m.last <= len(sc), "flatten: macro range out of bounds")
			assert(depth < MAX_CALL_DEPTH, "flatten: macro calls nested deeper than MAX_CALL_DEPTH")
			flatten_range(st, m.first, m.last, depth + 1)
		case ops.Defer:
			assert(int(op.id) < len(st.scene.macros), "flatten: defer names an unknown macro")
			m := st.scene.macros[op.id]
			assert(m.last >= 0, "flatten: defer of an unterminated macro")
			assert(0 <= m.first && m.first <= m.last && m.last <= len(sc), "flatten: macro range out of bounds")
			t := op.root ? st.root : st.transform
			if op.place.set {
				side: ops.Side
				shift: ops.Point
				t, side, shift = place(t, op.place, st.viewport)
				append(&st.f.placed, Placed{op.place.key, side, shift})
			}
			if op.top {
				append(&st.top, Deferred{op.id, t})
			} else if op.cover {
				append(&st.held, Covering{op.covers, {op.id, t}})
			} else {
				append(&st.deferred, Deferred{op.id, t})
			}
		case ops.Cover_End:
			release_held(st, op.id)
		case ops.Fill:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Stroke:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Glyphs:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Image:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Shadow:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Input_Area:
			append(
				&st.f.hits,
				Hit {
					area = op.id,
					kinds = op.kinds,
					shape = op.shape,
					transform = st.transform,
					clip = st.clip,
					order = len(st.f.hits),
					layer = st.layer,
					cursor = op.cursor,
					yields = op.yields,
					observes = op.observes,
				},
			)
		case ops.Tag:
			t := op
			if t.bounds != {} {
				t.bounds = ops.transform_rect(st.transform, t.bounds)
			}
			append(&st.f.tags, t)
		case ops.Debug_Box:
			r := ops.transform_rect(st.transform, ops.Rect{0, 0, op.size.x, op.size.y})
			append(&st.f.boxes, Layout_Box{op.id, r, op.min, op.max, op.depth, op.file, op.line, op.procedure, op.kind, st.clip, st.layer})
		case ops.Semantic:
			r := op.rect == {} ? ops.Rect{} : ops.transform_rect(st.transform, op.rect)
			append(&st.f.nodes, Semantic_Node{op.id, op.parent, op.semantics, r, st.layer, st.clip})
		case ops.Key_Interest:
			append(&st.f.keys, op)
		}
		i += 1
	}
	assert(len(st.transforms) == base_t, "flatten: transform_push without transform_pop")
	assert(len(st.clips) == base_c, "flatten: clip_push without clip_pop")
}

// sticky_shift is the translation a Push_Sticky resolves to: down by as
// much as puts the current origin s.top below the innermost clip's top
// edge, between 0 and s.room. Outside any clip nothing scrolls, so
// nothing moves.
@(private = "file")
sticky_shift :: proc(st: ^Flattener, s: ops.Push_Sticky) -> ops.Affine {
	if st.clip == NO_CLIP || st.transform.d == 0 {
		return ops.IDENTITY
	}
	c := st.f.clips[st.clip]
	top := ops.transform_rect(c.transform, ops.shape_bounds(st.scene, c.shape)).y
	origin := ops.apply(st.transform, {0, 0}).y
	dy := (top - origin) / f32(st.transform.d) + s.top
	return ops.translate(0, clamp(dy, 0, max(s.room, 0)))
}

// place is the transform a popup's macro runs under, and the side it
// chose. The popup opens on p.side unless that leaves it further outside
// viewport than the opposite side does; then it is shifted along both
// axes to lie inside, flush with viewport's start when larger than it.
// The popup's origin is placed in its anchor's own coordinates first and
// composed with t in f64, as a plain translate would be, so a popup that
// fits lands exactly where an unplaced one would; only a flip or a shift
// moves it. A zero viewport, or an anchor wholly outside it (a widget
// scrolled out of view), keeps p.side and shifts nothing.
@(private = "file")
place :: proc(t: ops.Affine, p: ops.Placement, viewport: ops.Rect) -> (ops.Affine, ops.Side, ops.Point) {
	origin :: proc(a: ops.Rect, size: ops.Size, gap: f32, side: ops.Side, align: ops.Side_Align) -> ops.Point {
		along :: proc(start, len, size: f32, align: ops.Side_Align) -> f32 {
			switch align {
			case .Center:
				return start + (len - size) / 2
			case .End:
				return start + len - size
			case .Start:
			}
			return start
		}
		switch side {
		case .Below:
			return {along(a.x, a.w, size.x, align), a.y + a.h + gap}
		case .Above:
			return {along(a.x, a.w, size.x, align), a.y - gap - size.y}
		case .After:
			return {a.x + a.w + gap, along(a.y, a.h, size.y, align)}
		case .Before:
			return {a.x - gap - size.x, along(a.y, a.h, size.y, align)}
		}
		return {}
	}
	// device is the popup's device rect with its local origin at o.
	device :: proc(t: ops.Affine, o: ops.Point, size: ops.Size) -> ops.Rect {
		return ops.transform_rect(ops.mul(ops.translate(o.x, o.y), t), {0, 0, size.x, size.y})
	}
	// overflow is how far r's main axis leaves the viewport.
	overflow :: proc(r: ops.Rect, side: ops.Side, v: ops.Rect) -> f32 {
		lo, hi, vlo, vhi := r.y, r.y + r.h, v.y, v.y + v.h
		if side == .After || side == .Before {
			lo, hi, vlo, vhi = r.x, r.x + r.w, v.x, v.x + v.w
		}
		return max(vlo - lo, 0) + max(hi - vhi, 0)
	}
	OPPOSITE := [ops.Side]ops.Side {
		.Below  = .Above,
		.Above  = .Below,
		.After  = .Before,
		.Before = .After,
	}
	side := p.side
	o := origin(p.anchor, p.size, p.gap, side, p.align)
	a := ops.transform_rect(t, p.anchor)
	v := viewport
	// Inclusive, so a zero-width or zero-height anchor (an edge or a point)
	// counts as visible when it lies within the viewport.
	visible := v.w > 0 && v.h > 0 && a.x <= v.x + v.w && a.x + a.w >= v.x && a.y <= v.y + v.h && a.y + a.h >= v.y
	if !visible {
		return ops.mul(ops.translate(o.x, o.y), t), side, {}
	}
	r := device(t, o, p.size)
	if out := overflow(r, side, v); out > 0 {
		flip := OPPOSITE[side]
		fo := origin(p.anchor, p.size, p.gap, flip, p.align)
		fr := device(t, fo, p.size)
		if overflow(fr, flip, v) < out {
			side, o, r = flip, fo, fr
		}
	}
	out := ops.mul(ops.translate(o.x, o.y), t)
	dx := max(min(r.x, v.x + v.w - r.w), v.x) - r.x
	dy := max(min(r.y, v.y + v.h - r.h), v.y) - r.y
	out.e += f64(dx)
	out.f += f64(dy)
	// The shift in the anchor's coordinates: the device shift through t's
	// inverse linear part.
	shift: ops.Point
	if inv, ok := ops.invert(t); ok {
		shift = {f32(inv.a * f64(dx) + inv.c * f64(dy)), f32(inv.b * f64(dx) + inv.d * f64(dy))}
	}
	return out, side, shift
}

// release_held moves the held Defers covering container id — every one,
// when all — into the run order, keeping the order they were met in.
@(private = "file")
release_held :: proc(st: ^Flattener, id: ops.Area_Id, all := false) {
	kept := 0
	for h in st.held {
		if all || h.covers == id {
			append(&st.deferred, h.deferred)
		} else {
			st.held[kept] = h
			kept += 1
		}
	}
	resize(&st.held, kept)
}
