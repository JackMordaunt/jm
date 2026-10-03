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
	scope:      Scope_Ref, // the innermost focus scope open
	alpha:      f32, // the opacity draws are made at: the product of the pushes open
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
		alpha      = 1,
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
		st.transform, st.clip, st.scope, st.alpha = d.transform, NO_CLIP, d.scope, d.alpha
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
	base_t, base_c, base_s, base_a := len(st.transforms), len(st.clips), len(st.scopes), len(st.alphas)
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
				fit: Fit
				t, fit = place(t, op.place, st.viewport)
				append(&st.f.placed, Placed{op.place.key, fit.side, fit.align, fit.shift})
			}
			if op.top {
				append(&st.top, Deferred{op.id, t, st.scope, st.alpha})
			} else if op.cover {
				append(&st.held, Covering{op.covers, {op.id, t, st.scope, st.alpha}})
			} else {
				append(&st.deferred, Deferred{op.id, t, st.scope, st.alpha})
			}
		case ops.Cover_End:
			release_held(st, op.id)
		case ops.Fill:
			append(&st.f.draws, Draw{st.transform, st.clip, op, 1 - st.alpha})
		case ops.Stroke:
			append(&st.f.draws, Draw{st.transform, st.clip, op, 1 - st.alpha})
		case ops.Glyphs:
			append(&st.f.draws, Draw{st.transform, st.clip, op, 1 - st.alpha})
		case ops.Image:
			append(&st.f.draws, Draw{st.transform, st.clip, op, 1 - st.alpha})
		case ops.Shadow:
			append(&st.f.draws, Draw{st.transform, st.clip, op, 1 - st.alpha})
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
					scope = st.scope,
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
		case ops.Focus_Scope:
			append(&st.f.scopes, Focus_Scope_Node{op.id, st.scope, op.trap, op.rove, op.wrap, 0})
			append(&st.scopes, st.scope)
			st.scope = Scope_Ref(len(st.f.scopes))
		case ops.Focus_Scope_End:
			assert(len(st.scopes) > base_s, "flatten: focus_scope_end with no scope open")
			st.f.scopes[st.scope - 1].entry = op.entry
			st.scope = pop(&st.scopes)
		case ops.Push_Opacity:
			append(&st.alphas, st.alpha)
			st.alpha *= clamp(op.alpha, 0, 1)
		case ops.Pop_Opacity:
			assert(len(st.alphas) > base_a, "flatten: opacity_pop with nothing pushed")
			st.alpha = pop(&st.alphas)
		}
		i += 1
	}
	assert(len(st.transforms) == base_t, "flatten: transform_push without transform_pop")
	assert(len(st.clips) == base_c, "flatten: clip_push without clip_pop")
	assert(len(st.scopes) == base_s, "flatten: focus_scope without focus_scope_end")
	assert(len(st.alphas) == base_a, "flatten: opacity_push without opacity_pop")
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

// Fit is where place put a popup: the side and alignment it chose, and
// the shift that kept it in the viewport in the anchor's coordinates.
@(private = "file")
Fit :: struct {
	side:  ops.Side,
	align: ops.Side_Align,
	shift: ops.Point,
}

// place is the transform a popup's macro runs under, and where it put
// the popup: see ops.Placement for the rules. The popup's origin is
// placed in its anchor's own coordinates first and composed with t in
// f64, as a plain translate would be, so a popup that fits lands exactly
// where an unplaced one would; only a flip, a realignment or a shift
// moves it. A zero viewport, or an anchor wholly outside it (a widget
// scrolled out of view), keeps p.side and p.align and shifts nothing.
@(private = "file")
place :: proc(t: ops.Affine, p: ops.Placement, viewport: ops.Rect) -> (ops.Affine, Fit) {
	OPPOSITE := [ops.Side]ops.Side {
		.Below  = .Above,
		.Above  = .Below,
		.After  = .Before,
		.Before = .After,
	}
	side, align := p.side, p.align
	o := popup_origin(p, side, align)
	a := ops.transform_rect(t, p.anchor)
	v := viewport
	// Inclusive, so a zero-width or zero-height anchor (an edge or a point)
	// counts as visible when it lies within the viewport.
	visible := v.w > 0 && v.h > 0 && a.x <= v.x + v.w && a.x + a.w >= v.x && a.y <= v.y + v.h && a.y + a.h >= v.y
	if !visible {
		return ops.mul(ops.translate(o.x, o.y), t), {side, align, {}}
	}
	r := popup_device(t, o, p.size)
	ran_out := true
	if p.inside {
		// Inside the anchor there is no other side to try.
	} else if p.side_count == 0 {
		if out := overflow(r, side, v); out > 0 {
			flip := OPPOSITE[side]
			fo := popup_origin(p, flip, align)
			fr := popup_device(t, fo, p.size)
			if overflow(fr, flip, v) < out {
				side, o, r = flip, fo, fr
			}
		}
	} else {
		tried := 0
		for tried < int(p.side_count) && overflow(r, side, v) > 0 {
			side = p.sides[tried]
			tried += 1
			o = popup_origin(p, side, align)
			r = popup_device(t, o, p.size)
		}
		ran_out = tried == int(p.side_count)
	}
	for i in 0 ..< int(p.align_count) {
		past_left := r.x < v.x
		if !past_left && (align == .End || r.x + r.w <= v.x + v.w) {
			break
		}
		align = p.aligns[i]
		o = popup_origin(p, side, align)
		r = popup_device(t, o, p.size)
	}
	out := ops.mul(ops.translate(o.x, o.y), t)
	dx := max(min(r.x, v.x + v.w - r.w), v.x) - r.x
	y := max(min(r.y, v.y + v.h - r.h), v.y)
	if p.overhang && ran_out {
		y = max(r.y, v.y)
	}
	dy := y - r.y
	out.e += f64(dx)
	out.f += f64(dy)
	// The shift in the anchor's coordinates: the device shift through t's
	// inverse linear part.
	shift: ops.Point
	if inv, ok := ops.invert(t); ok {
		shift = {f32(inv.a * f64(dx) + inv.c * f64(dy)), f32(inv.b * f64(dx) + inv.d * f64(dy))}
	}
	return out, {side, align, shift}
}

// popup_origin is p's popup's top-left in the anchor's coordinates, on
// side with align (anchored-position.mjs:179-256 for each case).
@(private = "file")
popup_origin :: proc(p: ops.Placement, side: ops.Side, align: ops.Side_Align) -> ops.Point {
	along :: proc(start, length, size, nudge: f32, align: ops.Side_Align) -> f32 {
		switch align {
		case .Center:
			return start + (length - size) / 2 + nudge
		case .End:
			return start + length - size - nudge
		case .Start:
		}
		return start + nudge
	}
	a, size, gap := p.anchor, p.size, p.gap
	x := along(a.x, a.w, size.x, p.nudge, align)
	y := along(a.y, a.h, size.y, p.nudge, align)
	if p.inside {
		switch side {
		case .Below:
			return {x, a.y + a.h - gap - size.y}
		case .Above:
			return {x, a.y + gap}
		case .After:
			return {a.x + a.w - gap - size.x, y}
		case .Before:
			return {a.x + gap, y}
		}
	}
	switch side {
	case .Below:
		return {x, a.y + a.h + gap}
	case .Above:
		return {x, a.y - gap - size.y}
	case .After:
		return {a.x + a.w + gap, y}
	case .Before:
		return {a.x - gap - size.x, y}
	}
	return {}
}

// popup_device is a popup's device rect under t with its local origin at o.
@(private = "file")
popup_device :: proc(t: ops.Affine, o: ops.Point, size: ops.Size) -> ops.Rect {
	return ops.transform_rect(ops.mul(ops.translate(o.x, o.y), t), {0, 0, size.x, size.y})
}

// overflow is how far r leaves the viewport v along side's axis.
@(private = "file")
overflow :: proc(r: ops.Rect, side: ops.Side, v: ops.Rect) -> f32 {
	lo, hi, vlo, vhi := r.y, r.y + r.h, v.y, v.y + v.h
	if side == .After || side == .Before {
		lo, hi, vlo, vhi = r.x, r.x + r.w, v.x, v.x + v.w
	}
	return max(vlo - lo, 0) + max(hi - vhi, 0)
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
