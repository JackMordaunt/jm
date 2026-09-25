/*
Package fuzz is the jm:wasm suite for jm:fuzz: the promises the bindings make,
checked against generated modules, damaged ones, and bytes that were never a
module at all.

	report := fuzz.run({seed = 1, iterations = 10_000})

jm:fuzz owns the machinery — seeding, budgets, shrinking, the corpus, the
deadline on a case. What lives here is what is true of jm:wasm and nothing
else:

	survives     any bytes load or fail, and a module that loads is coherent
	reusable     a Vm that was handed rubbish still runs a good module
	round_trip   a value handed to a function comes back as itself
	arity        an argument list that does not match the signature is refused
	bounds       bytes admits exactly the ranges inside the linear memory
	bounded      a metered call always comes back

bounds is the one that matters most: a guest chooses the pointers it hands
over, so `wasm.bytes` is the only thing between a hostile module and the rest
of the process, and the only way to know it holds is to keep drawing pointers
at the edges of the memory.

The suite builds its own modules rather than shipping .wasm files, so a case
is reproducible anywhere and a run needs no toolchain installed. build is a
small Wasm encoder; `just test` checks that what it emits is what jm:wasm
loads, or every property here would be testing the encoder's bugs instead.
*/
package wasm_fuzz

import "core:fmt"
import "core:math"

import harness "jm:fuzz"
import "jm:wasm"

// properties is package level because a Suite holds a slice, which has to
// outlive the call that hands the Suite back.
properties := []harness.Property(wasm.Vm) {
	{"survives", survives},
	{"reusable", reusable},
	{"round_trip", round_trip},
	{"arity", arity},
	{"bounds", bounds},
	{"bounded", bounded},
}

// suite is jm:wasm and its promises, ready for harness.run.
suite :: proc() -> harness.Suite(wasm.Vm) {
	return harness.Suite(wasm.Vm) {
		name = "wasm",
		setup = open,
		teardown = shut,
		cancel = stop,
		properties = properties,
	}
}

// CORPUS is where this suite's regressions live, relative to the repository
// root. A case that failed once is kept there and replayed on every run.
CORPUS :: "wasm/fuzz/corpus"

// GAS is the budget every case runs under. A guest is the one thing here that
// can run for ever, and metering is what stops it. The figure is a generous
// multiple of what any property here needs and far less than a run can wait
// for; the bounded property is where a budget is set deliberately small.
GAS :: 250_000.0

// PAGE is the Wasm page: the unit a linear memory is counted in.
PAGE :: 64 * 1024

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

// open gives each case its own runtime, metered and suspendable. Nothing is
// shared between cases, which is also what jm:wasm's one-thread rule wants:
// the only other thread here is the deadline, and all it does is set a flag.
open :: proc() -> (wasm.Vm, bool) {
	vm, err := wasm.open({gas = GAS, suspendable = true})
	return vm, err == nil
}

shut :: proc(vm: ^wasm.Vm) {
	wasm.close(vm)
}

// stop is what the deadline calls: a guest with no end runs until something
// interrupts it.
stop :: proc(vm: wasm.Vm) {
	wasm.interrupt(vm)
}

// survives hands jm:wasm whatever bytes were drawn. Any answer is allowed
// except an incoherent one: a load that failed must hand back nothing, and a
// module that loaded must report a memory of whole pages. Whatever it
// exports is then looked up and called, for the answer nobody checks — that
// it comes back at all.
survives :: proc(vm: wasm.Vm, src: ^harness.Source) -> (detail: string, ok: bool) {
	module := draw_wasm(src)
	mod, err := wasm.load(vm, module)
	if err != nil {
		if mod.handle != nil {
			return "a load that failed handed back a module anyway", false
		}
		return "", true
	}
	if view := wasm.memory(mod); len(view) % PAGE != 0 {
		return fmt.tprintf("memory is %d bytes, which is not whole pages", len(view)), false
	}
	name := harness.choice(src, EXPORTS)
	fn, ferr := wasm.find(mod, name)
	if ferr != nil {
		return "", true
	}
	_, _ = wasm.call(fn, ..drawn_args(src, fn))
	return "", true
}

// reusable is the promise that a failure is contained. Whatever a case fed
// the Vm — bytes that were never a module, one that trapped, one that ran out
// of gas — it still loads a good module afterwards and computes with it.
reusable :: proc(vm: wasm.Vm, src: ^harness.Source) -> (detail: string, ok: bool) {
	junk := draw_wasm(src)
	if mod, err := wasm.load(vm, junk); err == nil {
		if fn, ferr := wasm.find(mod, harness.choice(src, EXPORTS)); ferr == nil {
			_, _ = wasm.call(fn, ..drawn_args(src, fn))
		}
	}
	// The guest may have spent the whole budget on the way in, which is a
	// state a caller recovers from by setting a new one — so recovering from
	// it is part of what this property checks.
	wasm.set_gas(vm, GAS)

	mod, err := wasm.load(vm, adder())
	if err != nil {
		return fmt.tprintf("a good module stopped loading: %v", err), false
	}
	fn, ferr := wasm.find(mod, "add")
	if ferr != nil {
		return fmt.tprintf("add went missing: %v", ferr), false
	}
	a := i32(harness.integer_in(src, -1000, 1000))
	b := i32(harness.integer_in(src, -1000, 1000))
	out, cerr := wasm.call(fn, a, b)
	if cerr != nil {
		return fmt.tprintf("add(%d, %d): %v", a, b, cerr), false
	}
	if len(out) != 1 || out[0].(i32) != a + b {
		return fmt.tprintf("add(%d, %d) came back %v", a, b, out), false
	}
	return "", true
}

// round_trip hands one drawn value to a function that returns its argument
// unchanged. Whatever bits go in come out, which is what the slot a Value is
// written into has to promise for every type and every host.
round_trip :: proc(vm: wasm.Vm, src: ^harness.Source) -> (detail: string, ok: bool) {
	type := harness.choice(src, TYPES)
	mod, err := wasm.load(vm, identity(type))
	if err != nil {
		return fmt.tprintf("the identity module for %v did not load: %v", type, err), false
	}
	fn, ferr := wasm.find(mod, "id")
	if ferr != nil {
		return fmt.tprintf("id went missing: %v", ferr), false
	}
	v := drawn_value(src, type)
	out, cerr := wasm.call(fn, v)
	if cerr != nil {
		return fmt.tprintf("id(%v): %v", v, cerr), false
	}
	if len(out) != 1 {
		return fmt.tprintf("id(%v) returned %d values", v, len(out)), false
	}
	return same(v, out[0])
}

// arity is the check jm:wasm's call makes before the arguments reach wasm3,
// which is handed bare pointers and the signature that says how to read them.
// The property is what the check promises: the matching list is accepted, and
// a list of the wrong length or the wrong types is a Fail — never a trap, and
// never an answer.
arity :: proc(vm: wasm.Vm, src: ^harness.Source) -> (detail: string, ok: bool) {
	params := drawn_types(src, 0, 4)
	results := drawn_types(src, 0, 3)
	mod, err := wasm.load(vm, build({funcs = {{name = "f", params = params, results = results, body = consts(results)}}}))
	if err != nil {
		return fmt.tprintf("a module taking %v returning %v did not load: %v", params, results, err), false
	}
	fn, ferr := wasm.find(mod, "f")
	if ferr != nil {
		return fmt.tprintf("f went missing: %v", ferr), false
	}

	args := make([]wasm.Value, len(params), context.temp_allocator)
	for p, i in params {
		args[i] = drawn_value(src, p)
	}
	out, cerr := wasm.call(fn, ..args)
	if cerr != nil {
		return fmt.tprintf("a matching call of %v was refused: %v", params, cerr), false
	}
	if len(out) != len(results) {
		return fmt.tprintf("%v returned %d values", results, len(out)), false
	}
	for r, i in results {
		if got := wasm.ret_type(fn, i); got != r {
			return fmt.tprintf("result %d is %v, declared %v", i, got, r), false
		}
	}

	wrong, changed := mismatch(src, args, params)
	if !changed {
		return "", true
	}
	_, werr := wasm.call(fn, ..wrong)
	if werr == nil {
		return fmt.tprintf("a call of %d values against %v was accepted", len(wrong), params), false
	}
	if kind(werr) != .Fail {
		return fmt.tprintf("a mismatched call was refused with %v, wanted Fail", kind(werr)), false
	}
	return "", true
}

// bounds is the security property. A guest chooses the pointer, so bytes has
// to admit a range exactly when it lies inside the linear memory and refuse
// everything else, including the ranges that only overflow when the pointer
// and the size are added together.
bounds :: proc(vm: wasm.Vm, src: ^harness.Source) -> (detail: string, ok: bool) {
	pages := harness.integer_in(src, 1, 4)
	mod, err := wasm.load(vm, build({pages = pages}))
	if err != nil {
		return fmt.tprintf("a module with %d pages did not load: %v", pages, err), false
	}
	view := wasm.memory(mod)
	if len(view) != pages * PAGE {
		return fmt.tprintf("%d pages came back as %d bytes", pages, len(view)), false
	}

	ptr := drawn_pointer(src, len(view))
	size := drawn_size(src, len(view))
	got, admitted := wasm.bytes(mod, ptr, size)

	// The end of the range is never added up here either: this is the same
	// arithmetic bytes has to get right, so it is written the same way.
	inside := size >= 0 && int(ptr) <= len(view) && size <= len(view) - int(ptr)
	if admitted != inside {
		return fmt.tprintf(
				"[%d, %d+%d) in a %d byte memory was %s",
				ptr,
				ptr,
				size,
				len(view),
				admitted ? "admitted" : "refused",
			),
			false
	}
	if !admitted {
		return "", true
	}
	if len(got) != size {
		return fmt.tprintf("asked for %d bytes, got %d", size, len(got)), false
	}
	if size > 0 {
		lo := uintptr(raw_data(view))
		hi := lo + uintptr(len(view))
		start := uintptr(raw_data(got))
		if start < lo || start + uintptr(size) > hi {
			return fmt.tprintf("[%x, %x) is outside the memory [%x, %x)", start, start + uintptr(size), lo, hi), false
		}
	}
	return "", true
}

// bounded is why Opts.gas exists: under a budget every call comes back, with
// a result or with the budget spent. A suspendable runtime pauses instead of
// trapping when the gas runs out, which is why Suspended counts as coming
// back; jm:wasm's Opts.gas says so too.
bounded :: proc(vm: wasm.Vm, src: ^harness.Source) -> (detail: string, ok: bool) {
	mod, err := wasm.load(vm, looper())
	if err != nil {
		return fmt.tprintf("the loop module did not load: %v", err), false
	}
	fn, ferr := wasm.find(mod, "count")
	if ferr != nil {
		return fmt.tprintf("count went missing: %v", ferr), false
	}
	budget := f64(harness.integer_in(src, 1, 100_000))
	wasm.set_gas(vm, budget)

	n := i32(harness.integer_in(src, 0, 50_000_000))
	out, cerr := wasm.call(fn, n)
	switch kind(cerr) {
	case .Out_Of_Gas, .Suspended:
		// The budget stopped it, which is the whole point.
	case .Fail:
		if cerr != nil {
			return fmt.tprintf("count(%d) under %v gas: %v", n, budget, cerr), false
		}
		if len(out) != 1 || out[0].(i32) != 42 {
			return fmt.tprintf("count(%d) came back %v", n, out), false
		}
	case .Not_Found, .Trap, .Exit:
		return fmt.tprintf("count(%d) under %v gas: %v", n, budget, cerr), false
	}
	if used := wasm.gas_used(vm); used <= 0 {
		return fmt.tprintf("count(%d) spent %v gas", n, used), false
	}
	return "", true
}

// TYPES are the four types a Value can carry, and the only ones these
// properties build signatures from.
TYPES := []wasm.Type{.I32, .I64, .F32, .F64}

// EXPORTS are the names this suite's modules export, plus the names a real
// module would, so a lookup against drawn bytes sometimes finds something.
EXPORTS := []string{"add", "id", "count", "f", "memory", "_start", "main", ""}

// same reports whether a value came back as itself. A NaN is compared as a
// NaN rather than by its bits: what a NaN's payload survives is the engine's
// business, but a NaN going in and a number coming out is not.
@(private)
same :: proc(sent: wasm.Value, got: wasm.Value) -> (detail: string, ok: bool) {
	switch v in sent {
	case i32:
		if g, is := got.(i32); !is || g != v {
			return fmt.tprintf("i32 %d came back as %v", v, got), false
		}
	case i64:
		if g, is := got.(i64); !is || g != v {
			return fmt.tprintf("i64 %d came back as %v", v, got), false
		}
	case f32:
		g, is := got.(f32)
		if !is {
			return fmt.tprintf("f32 %v came back as %v", v, got), false
		}
		if math.is_nan(v) {
			if !math.is_nan(g) {
				return fmt.tprintf("a NaN came back as %v", g), false
			}
		} else if transmute(u32)g != transmute(u32)v {
			return fmt.tprintf("f32 %v came back as %v", v, g), false
		}
	case f64:
		g, is := got.(f64)
		if !is {
			return fmt.tprintf("f64 %v came back as %v", v, got), false
		}
		if math.is_nan(v) {
			if !math.is_nan(g) {
				return fmt.tprintf("a NaN came back as %v", g), false
			}
		} else if transmute(u64)g != transmute(u64)v {
			return fmt.tprintf("f64 %v came back as %v", v, g), false
		}
	case:
		return "nothing was sent", false
	}
	return "", true
}

// kind is the failure's kind, and Fail for no failure at all, so a switch can
// treat "came back clean" as one more case.
@(private)
kind :: proc(err: wasm.Error) -> wasm.Kind {
	if f, is := err.(wasm.Fault); is {
		return f.kind
	}
	return .Fail
}

// drawn_value draws one value of the given type, from jm:fuzz's generators so
// the edges — the overflows, the infinities, the NaN — come up often.
drawn_value :: proc(src: ^harness.Source, type: wasm.Type) -> wasm.Value {
	switch type {
	case .I32:
		return i32(harness.integer(src))
	case .I64:
		return harness.integer(src)
	case .F32:
		return f32(harness.real(src))
	case .F64:
		return harness.real(src)
	case .None, .V128, .Func_Ref, .Extern_Ref, .Exn_Ref, .Cont_Ref, .Unknown:
		return i32(0)
	}
	return i32(0)
}

// drawn_types draws a signature's worth of types, between lo and hi of them.
drawn_types :: proc(src: ^harness.Source, lo, hi: int) -> []wasm.Type {
	n := harness.integer_in(src, lo, hi)
	out := make([]wasm.Type, n, context.temp_allocator)
	for i in 0 ..< n {
		out[i] = harness.choice(src, TYPES)
	}
	return out
}

// drawn_args builds an argument list that matches what the function declares,
// so a call is refused for the module's reasons rather than the list's.
drawn_args :: proc(src: ^harness.Source, fn: wasm.Func) -> []wasm.Value {
	count, _ := wasm.arity(fn)
	out := make([]wasm.Value, count, context.temp_allocator)
	for i in 0 ..< count {
		out[i] = drawn_value(src, wasm.arg_type(fn, i))
	}
	return out
}

// mismatch breaks an argument list in one of the three ways a caller gets it
// wrong: one too few, one too many, or one of the right count with a type the
// function did not ask for. It reports false when the draw left the list
// matching after all, which a list of no arguments often does.
mismatch :: proc(
	src: ^harness.Source,
	args: []wasm.Value,
	params: []wasm.Type,
) -> (
	out: []wasm.Value,
	changed: bool,
) {
	switch harness.integer_in(src, 0, 3) {
	case 0:
		if len(args) == 0 {
			return nil, false
		}
		return args[:len(args) - 1], true
	case 1:
		longer := make([]wasm.Value, len(args) + 1, context.temp_allocator)
		copy(longer, args)
		longer[len(args)] = drawn_value(src, harness.choice(src, TYPES))
		return longer, true
	}
	if len(args) == 0 {
		return nil, false
	}
	i := harness.integer_in(src, 0, len(args))
	other := harness.choice(src, TYPES)
	if other == params[i] {
		return nil, false
	}
	retyped := make([]wasm.Value, len(args), context.temp_allocator)
	copy(retyped, args)
	retyped[i] = drawn_value(src, other)
	return retyped, true
}

// drawn_pointer draws a guest pointer, weighted to the edges of the memory:
// the last byte, one past the end, and the values that wrap when a size is
// added to them are where a bounds check is wrong if it is wrong anywhere.
drawn_pointer :: proc(src: ^harness.Source, size: int) -> u32 {
	edges := []u32 {
		0,
		1,
		u32(size - 1),
		u32(size),
		u32(size + 1),
		u32(size) / 2,
		max(u32),
		max(u32) - 1,
		max(u32) - u32(size),
		0x8000_0000,
	}
	if harness.boolean(src) {
		return harness.choice(src, edges)
	}
	return u32(harness.integer_in(src, 0, size + 2))
}

// drawn_size draws a length to go with the pointer, including the negative
// one a caller can pass and the huge one that overflows if it is added.
drawn_size :: proc(src: ^harness.Source, memory: int) -> int {
	edges := []int{0, 1, -1, memory, memory + 1, memory / 2, max(int), min(int), int(max(i32)) + 1}
	if harness.boolean(src) {
		return harness.choice(src, edges)
	}
	return harness.integer_in(src, 0, memory + 2)
}

// draw_wasm draws the bytes a property is handed: a module this suite built,
// one built from drawn signatures, one of those damaged, or bytes that were
// never a module at all.
draw_wasm :: proc(src: ^harness.Source) -> []byte {
	switch harness.integer_in(src, 0, 4) {
	case 0:
		return adder()
	case 1:
		return drawn_module(src)
	case 2:
		corpus := [][]byte{adder(), looper(), drawn_module(src)}
		out, _ := harness.damage(src, corpus, context.temp_allocator)
		return out
	}
	return harness.bytes(src, 512, context.temp_allocator)
}

// drawn_module builds a module from drawn signatures, so the loader meets
// shapes this suite did not think of: no functions, no memory, several
// results, a name that is empty.
drawn_module :: proc(src: ^harness.Source) -> []byte {
	n := harness.integer_in(src, 0, 4)
	funcs := make([]Fn, n, context.temp_allocator)
	for i in 0 ..< n {
		results := drawn_types(src, 0, 3)
		funcs[i] = Fn {
			name    = fmt.tprintf("%s%d", harness.choice(src, EXPORTS), i),
			params  = drawn_types(src, 0, 4),
			results = results,
			body    = consts(results),
		}
	}
	return build({funcs = funcs, pages = harness.integer_in(src, 0, 3)})
}
