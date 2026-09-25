package wasm_fuzz

import "core:testing"

import harness "jm:fuzz"
import "jm:wasm"

// A short run on fixed seeds, so `just test` catches a regression without
// waiting for a long fuzz run.
@(test)
properties_hold :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	for seed in ([]u64{1, 3, 7, 99}) {
		report := run({seed = seed, iterations = 150})
		testing.expect_value(t, report.iterations, 150)
		for f in report.failures {
			testing.expectf(
				t,
				false,
				"%s failed at case %d (replay: jm-fuzz wasm -seed=%d): %s",
				f.property,
				f.iteration,
				f.seed,
				f.detail,
			)
		}
	}
}

@(test)
suite_is_complete :: proc(t: ^testing.T) {
	s := suite()
	testing.expect_value(t, s.name, "wasm")
	testing.expect(t, s.setup != nil, "a case needs a runtime")
	testing.expect(t, s.teardown != nil, "a case must give it back")
	testing.expect(t, s.cancel != nil, "a guest with no end has to be interruptible")
	testing.expect(t, len(s.properties) == 6, "every property must be registered")
	for p in s.properties {
		testing.expect(t, p.name != "", "a property needs a name to be saved under")
		testing.expect(t, p.check != nil, "a property needs a body")
	}
}

// The modules this suite builds have to be ones jm:wasm loads and runs, or
// every property built on them is testing the encoder's bugs instead.
@(test)
built_modules_are_well_formed :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := wasm.open()
	testing.expect_value(t, err, nil)
	defer wasm.close(&vm)

	add_mod, aerr := wasm.load(vm, adder())
	testing.expect_value(t, aerr, nil)
	add, afind := wasm.find(add_mod, "add")
	testing.expect_value(t, afind, nil)
	sum, acall := wasm.call(add, i32(2), i32(3))
	testing.expect_value(t, acall, nil)
	testing.expect_value(t, sum[0].(i32), 5)

	count_mod, cerr := wasm.load(vm, looper())
	testing.expect_value(t, cerr, nil)
	count, cfind := wasm.find(count_mod, "count")
	testing.expect_value(t, cfind, nil)
	out, ccall := wasm.call(count, i32(10))
	testing.expect_value(t, ccall, nil)
	testing.expect_value(t, out[0].(i32), 42)

	// A memory of the size that was asked for, and the data written into it.
	mem_mod, merr := wasm.load(vm, build({pages = 2, data = transmute([]byte)string("hello")}))
	testing.expect_value(t, merr, nil)
	view := wasm.memory(mem_mod)
	testing.expect_value(t, len(view), 2 * PAGE)
	testing.expect_value(t, string(view[:5]), "hello")
}

// Every type a Value carries has to make the crossing, or round_trip is only
// ever checking the one the generator happened to draw.
@(test)
identity_holds_for_every_type :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	sent := []wasm.Value{i32(-7), i64(1 << 40), f32(0.25), f64(1e300)}
	for type, i in TYPES {
		vm, err := wasm.open()
		testing.expect_value(t, err, nil)
		defer wasm.close(&vm)

		mod, lerr := wasm.load(vm, identity(type))
		testing.expectf(t, lerr == nil, "identity(%v): %v", type, lerr)
		fn, ferr := wasm.find(mod, "id")
		testing.expect_value(t, ferr, nil)
		testing.expect_value(t, wasm.arg_type(fn, 0), type)

		out, cerr := wasm.call(fn, sent[i])
		testing.expectf(t, cerr == nil, "id(%v): %v", sent[i], cerr)
		detail, ok := same(sent[i], out[0])
		testing.expectf(t, ok, "%s", detail)
	}
}

// A signature of several results is what makes consts worth having: the
// arity property draws them, so a module returning three values has to arrive
// as one, values and all.
@(test)
a_built_signature_is_the_one_that_arrives :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := wasm.open()
	defer wasm.close(&vm)

	params := []wasm.Type{.I64, .F32}
	results := []wasm.Type{.F64, .I32, .I64}
	mod, err := wasm.load(
		vm,
		build({funcs = {{name = "f", params = params, results = results, body = consts(results)}}}),
	)
	testing.expect_value(t, err, nil)
	fn, ferr := wasm.find(mod, "f")
	testing.expect_value(t, ferr, nil)

	args, rets := wasm.arity(fn)
	testing.expect_value(t, args, len(params))
	testing.expect_value(t, rets, len(results))
	for p, i in params {
		testing.expect_value(t, wasm.arg_type(fn, i), p)
	}
	for r, i in results {
		testing.expect_value(t, wasm.ret_type(fn, i), r)
	}
	out, cerr := wasm.call(fn, i64(1), f32(2))
	testing.expect_value(t, cerr, nil)
	testing.expect_value(t, len(out), 3)
	// consts leaves a zero of each type, in the order the signature names.
	testing.expect_value(t, out[0].(f64), 0)
	testing.expect_value(t, out[1].(i32), 0)
	testing.expect_value(t, out[2].(i64), 0)
}

// bounds is only worth anything if the pointers it draws really do fall
// outside the memory, so check the generator rather than trusting it.
@(test)
drawn_pointers_reach_past_the_memory :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	entropy := make([]byte, 4096, context.temp_allocator)
	for i in 0 ..< len(entropy) {
		entropy[i] = byte(i * 7 + i / 251)
	}
	src := harness.source(entropy)

	size := 2 * PAGE
	inside, outside, negative := 0, 0, 0
	for _ in 0 ..< 400 {
		ptr := drawn_pointer(&src, size)
		if int(ptr) < size {
			inside += 1
		} else {
			outside += 1
		}
		if drawn_size(&src, size) < 0 {
			negative += 1
		}
	}
	testing.expect(t, inside > 0, "a pointer inside the memory has to come up")
	testing.expect(t, outside > 0, "a pointer past the end is the whole point")
	testing.expect(t, negative > 0, "a negative size is a caller's mistake worth drawing")
}

// The bytes a case is handed have to include real modules as well as noise,
// or survives is only ever checking that garbage is rejected.
@(test)
drawn_wasm_is_sometimes_a_module :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	entropy := make([]byte, 4096, context.temp_allocator)
	for i in 0 ..< len(entropy) {
		entropy[i] = byte(i * 13 + i / 97)
	}
	src := harness.source(entropy)

	vm, _ := wasm.open()
	defer wasm.close(&vm)

	loaded, refused := 0, 0
	for _ in 0 ..< 200 {
		if _, err := wasm.load(vm, draw_wasm(&src)); err == nil {
			loaded += 1
		} else {
			refused += 1
		}
	}
	testing.expect(t, loaded > 0, "a module the loader accepts has to come up")
	testing.expect(t, refused > 0, "so does one it does not")
}
