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
	transforms: [dynamic]ops.Affine,
	clips:      [dynamic]Clip_Id,
	transform:  ops.Affine,
	clip:       Clip_Id,
	deferred:   [dynamic]Deferred,
	layer:      i32, // 0 for the frame, then 1, 2, ... for each deferred macro in the order run
	viewport:   ops.Rect, // device space; zero leaves popups where they ask to be
}

// Deferred is a Defer met during the pass: its macro and the transform to
// run it under once everything else is flattened.
@(private = "file")
Deferred :: struct {
	id:        ops.Macro_Id,
	transform: ops.Affine,
}

// flatten turns the scene sc into f: every draw and hit carries its device
// transform and a clip reference. f is reset first and keeps a pointer to
// sc for its resources. viewport is the window in device pixels: a placed
// popup (ops.Placement) is kept inside it, and a zero viewport leaves
// popups where they ask to be. Unbalanced push/pop, a Call to an
// unterminated or unknown macro, or calls nested deeper than
// MAX_CALL_DEPTH assert.
flatten :: proc(sc: ^ops.Scene, f: ^Frame, viewport := ops.Rect{}) {
	frame_reset(f)
	f.scene = sc
	st := Flattener {
		scene        = sc,
		f          = f,
		transforms = make([dynamic]ops.Affine, context.allocator),
		clips      = make([dynamic]Clip_Id, context.allocator),
		transform  = ops.IDENTITY,
		clip       = NO_CLIP,
		deferred   = make([dynamic]Deferred, context.allocator),
		viewport   = viewport,
	}
	flatten_range(&st, 0, len(sc.ops), 0)
	// Deferred macros run last, in the order met, so their draws and hits
	// sit above everything else; one deferred from inside another runs
	// after it. Each starts unclipped.
	for i := 0; i < len(st.deferred); i += 1 {
		d := st.deferred[i]
		m := sc.macros[d.id]
		st.transform, st.clip = d.transform, NO_CLIP
		st.layer = i32(i + 1)
		flatten_range(&st, m.first, m.last, 1)
	}
	delete(st.deferred)
	assert(len(st.transforms) == 0, "flatten: transform_push without transform_pop")
	assert(len(st.clips) == 0, "flatten: clip_push without clip_pop")
	delete(st.transforms)
	delete(st.clips)
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
			t := op.root ? ops.IDENTITY : st.transform
			if op.place.set {
				side: ops.Side
				shift: ops.Point
				t, side, shift = place(t, op.place, st.viewport)
				append(&st.f.placed, Placed{op.place.key, side, shift})
			}
			append(&st.deferred, Deferred{op.id, t})
		case ops.Fill:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Stroke:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Glyphs:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Image:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Shadow:
		// Not drawn yet: Frame has no draw for it.
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
				},
			)
		case ops.Tag:
			append(&st.f.tags, op)
		case ops.Debug_Box:
			r := ops.transform_rect(st.transform, ops.Rect{0, 0, op.size.x, op.size.y})
			append(&st.f.boxes, Layout_Box{op.id, r, op.min, op.max, op.depth, op.file, op.line, op.procedure, op.kind, st.clip, st.layer})
		}
		i += 1
	}
	assert(len(st.transforms) == base_t, "flatten: transform_push without transform_pop")
	assert(len(st.clips) == base_c, "flatten: clip_push without clip_pop")
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
