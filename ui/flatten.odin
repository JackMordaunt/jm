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
// sc for its resources. Unbalanced push/pop, a Call to an unterminated or
// unknown macro, or calls nested deeper than MAX_CALL_DEPTH assert.
flatten :: proc(sc: ^ops.Scene, f: ^Frame) {
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
			append(&st.deferred, Deferred{op.id, op.root ? ops.IDENTITY : st.transform})
		case ops.Fill:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Stroke:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Glyphs:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case ops.Image:
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
