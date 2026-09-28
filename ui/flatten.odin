package ui

// MAX_CALL_DEPTH bounds macro Call nesting in flatten. Each level is one
// native stack frame of flatten_range, so 64 is far below any stack limit;
// a deeper chain, or a macro that calls itself, trips an assert.
MAX_CALL_DEPTH :: 64

@(private = "file")
Flattener :: struct {
	ops:        ^Ops,
	f:          ^Frame,
	transforms: [dynamic]Affine,
	clips:      [dynamic]Clip_Id,
	transform:  Affine,
	clip:       Clip_Id,
	deferred:   [dynamic]Deferred,
	layer:      i32, // 0 for the frame, then 1, 2, ... for each deferred macro in the order run
}

// Deferred is a Defer met during the pass: its macro and the transform to
// run it under once everything else is flattened.
@(private = "file")
Deferred :: struct {
	id:        Macro_Id,
	transform: Affine,
}

// flatten turns the scene ops into f: every draw and hit carries its device
// transform and a clip reference. f is reset first and keeps a pointer to
// ops for its resources. Unbalanced push/pop, a Call to an unterminated or
// unknown macro, or calls nested deeper than MAX_CALL_DEPTH assert.
flatten :: proc(ops: ^Ops, f: ^Frame) {
	frame_reset(f)
	f.ops = ops
	st := Flattener {
		ops        = ops,
		f          = f,
		transforms = make([dynamic]Affine, context.allocator),
		clips      = make([dynamic]Clip_Id, context.allocator),
		transform  = IDENTITY,
		clip       = NO_CLIP,
		deferred   = make([dynamic]Deferred, context.allocator),
	}
	flatten_range(&st, 0, len(ops.ops), 0)
	// Deferred macros run last, in the order met, so their draws and hits
	// sit above everything else; one deferred from inside another runs
	// after it. Each starts unclipped.
	for i := 0; i < len(st.deferred); i += 1 {
		d := st.deferred[i]
		m := ops.macros[d.id]
		st.transform, st.clip = d.transform, NO_CLIP
		st.layer = i32(i + 1)
		flatten_range(&st, m.first, m.last, 1)
	}
	delete(st.deferred)
	assert(len(st.transforms) == 0, "flatten: push_transform without pop_transform")
	assert(len(st.clips) == 0, "flatten: push_clip without pop_clip")
	delete(st.transforms)
	delete(st.clips)
}

// flatten_range runs ops[lo:hi]. Pops may not reach below the stack depths
// seen on entry, and a range must leave both stacks as it found them.
@(private = "file")
flatten_range :: proc(st: ^Flattener, lo, hi: int, depth: int) {
	base_t, base_c := len(st.transforms), len(st.clips)
	ops := st.ops.ops[:]
	i := lo
	for i < hi {
		switch op in ops[i] {
		case Push_Transform:
			append(&st.transforms, st.transform)
			st.transform = mul(op.m, st.transform)
		case Pop_Transform:
			assert(len(st.transforms) > base_t, "flatten: pop_transform with nothing pushed")
			st.transform = pop(&st.transforms)
		case Push_Clip:
			append(&st.clips, st.clip)
			append(&st.f.clips, Clip{parent = st.clip, shape = op.shape, transform = st.transform})
			st.clip = Clip_Id(len(st.f.clips) - 1)
		case Pop_Clip:
			assert(len(st.clips) > base_c, "flatten: pop_clip with nothing pushed")
			st.clip = pop(&st.clips)
		case Macro_Begin:
			assert(int(op.id) < len(st.ops.macros), "flatten: macro_begin names an unknown macro")
			last := st.ops.macros[op.id].last
			// An unterminated macro swallows the rest of the range.
			i = hi if last < 0 else max(i, min(last, hi))
		case Macro_End:
		// Only reached for a stray end; bodies are skipped past theirs.
		case Call:
			assert(int(op.id) < len(st.ops.macros), "flatten: call names an unknown macro")
			m := st.ops.macros[op.id]
			assert(m.last >= 0, "flatten: call to an unterminated macro")
			assert(0 <= m.first && m.first <= m.last && m.last <= len(ops), "flatten: macro range out of bounds")
			assert(depth < MAX_CALL_DEPTH, "flatten: macro calls nested deeper than MAX_CALL_DEPTH")
			flatten_range(st, m.first, m.last, depth + 1)
		case Defer:
			assert(int(op.id) < len(st.ops.macros), "flatten: defer names an unknown macro")
			m := st.ops.macros[op.id]
			assert(m.last >= 0, "flatten: defer of an unterminated macro")
			assert(0 <= m.first && m.first <= m.last && m.last <= len(ops), "flatten: macro range out of bounds")
			append(&st.deferred, Deferred{op.id, op.root ? IDENTITY : st.transform})
		case Fill:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case Stroke:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case Glyphs:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case Image:
			append(&st.f.draws, Draw{st.transform, st.clip, op})
		case Input_Area:
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
		case Tag:
			append(&st.f.tags, op)
		case Debug_Box:
			r := transform_rect(st.transform, Rect{0, 0, op.size.x, op.size.y})
			append(&st.f.boxes, Layout_Box{op.id, r, op.min, op.max, op.depth, op.file, op.line, op.procedure, st.clip, st.layer})
		}
		i += 1
	}
	assert(len(st.transforms) == base_t, "flatten: push_transform without pop_transform")
	assert(len(st.clips) == base_c, "flatten: push_clip without pop_clip")
}
