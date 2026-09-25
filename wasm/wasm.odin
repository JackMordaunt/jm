/*
Package wasm runs WebAssembly. The interpreter is wasm3, vendored and linked
statically, so a built script needs no system library and no shared object at
runtime. The README's WebAssembly section records the version and what the
build turns on.

	vm := must(wasm.open())
	defer wasm.close(&vm)

	mod := must(wasm.load(vm, must(path.read("add.wasm"))))
	add := must(wasm.find(mod, "add"))
	out := must(wasm.call(add, i32(19), i32(23)))
	fmt.println(out[0].(i32))  // 42

A module is loaded in three steps because each needs the one before it:
load instantiates it, link fills in the imports it declares, and start runs
its start section. A module with no imports and no start section needs only
the first, which is why the example above stops there. For a WASI command,
run is the whole of it: it calls `_start` and reports the exit status.

Values crossing the boundary are i32, i64, f32 and f64, the four types Wasm
computes with. Anything else a signature can name — a v128, a reference — can
be read back as a type but not carried as a Value.

Guest memory is the guest's, not a copy: memory hands back a view into the
module's linear memory, so a call that grows it invalidates what was handed
out. Take the view again after every call, and clone what has to outlive one.

Nothing here bounds how long a call runs on its own. Opts.gas arms wasm3's
gas metering, which traps with Out_Of_Gas when the budget is spent, and
Opts.suspendable lets another thread stop a call with interrupt and pick it up
again with resume. A module that loops forever with neither set never returns.

Threads: one at a time, for the whole package. vendor/m3_config.h says as much
about loading - the arena a memory comes from "is shared by every runtime in
the process and is not itself locked" - and a separate runtime per thread is
not enough either: eight threads each opening their own environment and
runtime and calling their own copy of a two-instruction module produced
spurious traps, a stack overflow and an out of bounds access, around five
times in sixteen hundred calls. That was measured in C with none of this
package involved, so a Vm and everything from it belongs to one thread, and
two Vms on two threads buy nothing. interrupt is the one exception: it sets a flag on the runtime
and nothing else, which is what makes it safe to call from elsewhere. This is
the opposite of jm:sqlite3, where a connection per worker is safe by
construction; a module that has to run under jm:flow runs in a worker of its
own with everything else kept off wasm3.
*/
package wasm

import "core:c"
import "core:fmt"
import "core:mem"
import "core:strings"

// Kind sorts a failure by what the caller can do about it. Trap and
// Out_Of_Gas are the guest's fault, Not_Found and Fail are the host's, Exit is
// not a failure at all: the guest asked to stop.
Kind :: enum {
	// A malformed module, a missing import, a bad signature, a type the
	// wrapper cannot carry: everything that is not one of the below.
	Fail,
	// No export of that name in the module.
	Not_Found,
	// The guest faulted: out of bounds, divide by zero, unreachable, a stack
	// overflow. The module is done; the runtime can still load another.
	Trap,
	// The gas budget ran out mid-call. Set a new limit to run again.
	Out_Of_Gas,
	// The guest called exit or proc_exit. Fault.code is the status it asked
	// for, and run reports it rather than failing.
	Exit,
	// interrupt stopped the call at a pause point. resume continues it.
	Suspended,
}

// Fault is a failed call: what kind of failure it was and what wasm3 said
// about it, which names the import or the function rather than restating the
// kind. The text is cloned, so it outlives the next call.
Fault :: struct {
	kind: Kind,
	text: string,
	// The status the guest exited with, when kind is Exit.
	code: int,
}

// Error is nil when a call succeeded, so `or_return` and prelude.must both
// work on it.
Error :: union {
	Fault,
}

// Type is the type of a value, a parameter or a result. Only I32, I64, F32
// and F64 can be carried as a Value.
Type :: Value_Type

// Value is one argument or result. The type has to match what the function
// declares: passing an i64 where it wants an i32 is a Fail, not a conversion.
Value :: union {
	i32,
	i64,
	f32,
	f64,
}

// Vm is an environment and the runtime that executes in it.
Vm :: struct {
	env:       ^Environment,
	rt:        ^Runtime,
	allocator: mem.Allocator,
}

// Module is one loaded module. The runtime owns it and frees it, so there is
// nothing to close; it is valid until the Vm it came from is closed.
Module :: struct {
	handle:    ^Module_Handle,
	rt:        ^Runtime,
	allocator: mem.Allocator,
}

// Func is one exported function, valid for as long as its runtime.
Func :: struct {
	handle:    ^Function_Handle,
	rt:        ^Runtime,
	allocator: mem.Allocator,
}

// Opts tunes the runtime a Vm executes in.
Opts :: struct {
	// The Wasm value stack, in bytes. A deep recursion needs a bigger one and
	// gets Trap when it runs out. Zero means STACK.
	stack:       int,
	// A gas budget for the whole runtime. Above zero it arms wasm3's metering
	// before anything compiles, and a call that spends it traps with
	// Out_Of_Gas — or, in a suspendable runtime, pauses as if interrupt had
	// been called, which is what vendor/wasm3.h says m3_SetGasLimit does
	// there. The unit is wasm3's, from ewasm's metering design: a counting
	// loop measured here spent 631,000 gas over ten million iterations, so a
	// budget buys roughly sixteen thousand iterations per gas.
	gas:         f64,
	// Let interrupt pause a call. Only code compiled into a suspendable
	// runtime carries the checks that pause, so this has to be set here
	// rather than before the call that needs it.
	suspendable: bool,
	// Skip the type validation pre-pass, which trusts the module to be
	// well-typed. Faster to compile and unsafe for anything not built here.
	no_validate: bool,
}

// Load tunes how a module is instantiated.
Load :: struct {
	// The name the module is known by in a backtrace. Defaults to "module".
	name:    string,
	// Link the WASI preview 1 imports, which is what a module compiled as a
	// command needs before run can call its `_start`. The state behind them
	// is one static in vendor/m3_api_wasi.c, reached through
	// m3_GetWasiContext, so one runtime at a time can hold a WASI module.
	wasi:    bool,
	// Compile every function now instead of on first call, which reports a
	// bad body as a load failure rather than a call failure.
	compile: bool,
}

// STACK is the default Wasm value stack: 64 KiB, enough for the recursion an
// ordinary module does.
STACK :: 64 * 1024

// open makes a runtime to load modules into.
open :: proc(opts := Opts{}, allocator := context.allocator) -> (vm: Vm, err: Error) {
	env := m3_NewEnvironment()
	if env == nil {
		return {}, Fault{kind = .Fail, text = strings.clone("out of memory", allocator)}
	}
	stack := opts.stack > 0 ? opts.stack : STACK
	rt := m3_NewRuntime(env, u32(stack), nil)
	if rt == nil {
		m3_FreeEnvironment(env)
		return {}, Fault{kind = .Fail, text = strings.clone("out of memory", allocator)}
	}
	if opts.no_validate {
		m3_SetValidation(rt, false)
	}
	// Both of these instrument the code the compiler emits, and compilation is
	// lazy, so they have to be set before anything is loaded rather than
	// before the call that wants them.
	if opts.suspendable {
		m3_SetSuspendable(rt, true)
	}
	if opts.gas > 0 {
		m3_SetGasLimit(rt, opts.gas)
	}
	return Vm{env = env, rt = rt, allocator = allocator}, nil
}

// close frees the runtime, every module in it and their memories, and zeroes
// vm. Every Module and Func from it dangles afterwards.
close :: proc(vm: ^Vm) {
	if vm == nil {
		return
	}
	if vm.rt != nil {
		m3_FreeRuntime(vm.rt)
	}
	if vm.env != nil {
		m3_FreeEnvironment(vm.env)
	}
	vm^ = {}
}

// load parses wasm and instantiates it in vm. The bytes are cloned into the
// Vm's allocator, because wasm3 parses lazily and the module keeps pointing
// into them for as long as it lives.
//
// Imports are not resolved here. A module that imports a host function still
// loads; the call that needs it is what fails, unless Load.compile asked for
// the whole module to be compiled now.
load :: proc(vm: Vm, wasm: []byte, opts := Load{}) -> (mod: Module, err: Error) {
	if len(wasm) == 0 {
		return {}, Fault{kind = .Fail, text = strings.clone("empty module", vm.allocator)}
	}
	bytes := make([]byte, len(wasm), vm.allocator)
	copy(bytes, wasm)

	handle: ^Module_Handle
	if res := m3_ParseModule(vm.env, &handle, raw_data(bytes), u32(len(bytes))); res != nil {
		return {}, fault(vm.rt, res, vm.allocator)
	}
	name := strings.clone_to_cstring(opts.name != "" ? opts.name : "module", vm.allocator)
	m3_SetModuleName(handle, name)

	// m3_LoadModule takes the module whether or not it succeeds, so there is
	// nothing to free on this path: the runtime holds it either way.
	if res := m3_LoadModule(vm.rt, handle); res != nil {
		return {}, fault(vm.rt, res, vm.allocator)
	}
	mod = Module {
		handle    = handle,
		rt        = vm.rt,
		allocator = vm.allocator,
	}
	if opts.wasi {
		if res := m3_LinkWASI(handle); res != nil {
			return {}, fault(vm.rt, res, vm.allocator)
		}
	}
	if opts.compile {
		if res := m3_CompileModule(handle); res != nil {
			return {}, fault(vm.rt, res, vm.allocator)
		}
	}
	return mod, nil
}

// start runs the module's start section, the code a module asks to have run
// before anything else. A module without one succeeds here having done
// nothing. Link the imports first: the start function may call them.
start :: proc(mod: Module) -> Error {
	if res := m3_RunStart(mod.handle); res != nil {
		return fault(mod.rt, res, mod.allocator)
	}
	return nil
}

// run calls `_start`, which is the entry point of a module compiled as a WASI
// command, and reports the status it exited with. args becomes the guest's
// argv, argv[0] included, and its stdin, stdout and stderr are this process's.
// The module has to have been loaded with Load.wasi set.
//
// A guest that exits is not a failure: the status comes back as code with a
// nil error. A guest that traps is, and code is then zero.
run :: proc(mod: Module, args: []string = nil) -> (code: int, err: Error) {
	fn := find(mod, "_start") or_return

	// The context is process-wide, and wasm3 reads argv during the call, so
	// the strings have to outlive it: they are cloned into the module's
	// allocator rather than a temporary one.
	ctx := m3_GetWasiContext()
	argv: []cstring
	if len(args) > 0 {
		argv = make([]cstring, len(args), mod.allocator)
		for a, i in args {
			argv[i] = strings.clone_to_cstring(a, mod.allocator)
		}
	}
	ctx.exit_code = 0
	ctx.argc = u32(len(argv))
	ctx.argv = raw_data(argv)

	res := m3_Call(fn.handle, 0, nil)
	if res == nil {
		return 0, nil
	}
	err = fault(mod.rt, res, mod.allocator)
	if f, ok := err.(Fault); ok && f.kind == .Exit {
		return f.code, nil
	}
	return 0, err
}

// find looks up an exported function by name. Only this module's exports are
// searched, which is what naming a module's export means.
find :: proc(mod: Module, name: string) -> (fn: Func, err: Error) {
	handle: ^Function_Handle
	cname := strings.clone_to_cstring(name, context.temp_allocator)
	if res := m3_FindFunctionIn(&handle, mod.handle, cname); res != nil {
		return {}, fault(mod.rt, res, mod.allocator)
	}
	return Func{handle = handle, rt = mod.rt, allocator = mod.allocator}, nil
}

// call runs the function with args bound to its parameters in order and
// returns its results. Passing a different count or a different type than the
// function declares is a Fail, caught here rather than handed to wasm3, which
// would read the argument as whatever the signature said.
call :: proc(
	fn: Func,
	args: ..Value,
	allocator := context.allocator,
) -> (
	out: []Value,
	err: Error,
) {
	argc := int(m3_GetArgCount(fn.handle))
	if argc != len(args) {
		return nil, Fault {
			kind = .Fail,
			text = fmt.aprintf(
				"%s takes %d arguments, got %d",
				m3_GetFunctionName(fn.handle),
				argc,
				len(args),
				allocator = allocator,
			),
		}
	}
	// One 64-bit slot per argument, written through a pointer of the argument's
	// own type so wasm3 reads the bytes back where it put them, big-endian
	// hosts included.
	slots := make([]u64, max(argc, 1), context.temp_allocator)
	ptrs := make([]rawptr, max(argc, 1), context.temp_allocator)
	for arg, i in args {
		want := m3_GetArgType(fn.handle, u32(i))
		got: Type
		switch v in arg {
		case i32:
			got = .I32
			(^i32)(&slots[i])^ = v
		case i64:
			got = .I64
			(^i64)(&slots[i])^ = v
		case f32:
			got = .F32
			(^f32)(&slots[i])^ = v
		case f64:
			got = .F64
			(^f64)(&slots[i])^ = v
		case:
			got = .None
		}
		if got != want {
			return nil, Fault {
				kind = .Fail,
				text = fmt.aprintf(
					"argument %d is %v, function takes %v",
					i,
					got,
					want,
					allocator = allocator,
				),
			}
		}
		ptrs[i] = &slots[i]
	}
	if res := m3_Call(fn.handle, u32(argc), raw_data(ptrs)); res != nil {
		return nil, fault(fn.rt, res, allocator)
	}
	return results(fn, allocator)
}

// results reads back what the last call to fn returned. call ends with it;
// the other caller is resume, which finishes a call interrupt had paused.
results :: proc(fn: Func, allocator := context.allocator) -> (out: []Value, err: Error) {
	retc := int(m3_GetRetCount(fn.handle))
	if retc == 0 {
		return nil, nil
	}
	slots := make([]u64, retc, context.temp_allocator)
	ptrs := make([]rawptr, retc, context.temp_allocator)
	for i in 0 ..< retc {
		ptrs[i] = &slots[i]
	}
	if res := m3_GetResults(fn.handle, u32(retc), raw_data(ptrs)); res != nil {
		return nil, fault(fn.rt, res, allocator)
	}
	out = make([]Value, retc, allocator)
	for i in 0 ..< retc {
		type := m3_GetRetType(fn.handle, u32(i))
		switch type {
		case .I32:
			out[i] = (^i32)(&slots[i])^
		case .I64:
			out[i] = (^i64)(&slots[i])^
		case .F32:
			out[i] = (^f32)(&slots[i])^
		case .F64:
			out[i] = (^f64)(&slots[i])^
		case .None, .V128, .Func_Ref, .Extern_Ref, .Exn_Ref, .Cont_Ref, .Unknown:
			return nil, Fault {
				kind = .Fail,
				text = fmt.aprintf(
					"result %d is %v, which is not a Value",
					i,
					type,
					allocator = allocator,
				),
			}
		}
	}
	return out, nil
}

// arity is how many arguments the function takes and how many results it
// returns. Wasm functions can return more than one.
arity :: proc(fn: Func) -> (args: int, rets: int) {
	return int(m3_GetArgCount(fn.handle)), int(m3_GetRetCount(fn.handle))
}

// arg_type is the type of the function's argument at index.
arg_type :: proc(fn: Func, index: int) -> Type {
	return m3_GetArgType(fn.handle, u32(index))
}

// ret_type is the type of the function's result at index.
ret_type :: proc(fn: Func, index: int) -> Type {
	return m3_GetRetType(fn.handle, u32(index))
}

// memory is a view of the module's linear memory, the address space a guest
// pointer indexes into. It is the guest's own memory, not a copy: writing to
// the slice is what handing the guest a buffer means, and any call that grows
// the memory can move it, so take the view again afterwards.
//
// A module that declares no memory gets nil.
memory :: proc(mod: Module, index := 0) -> []byte {
	size: c.size_t
	p := m3_GetMemory(mod.handle, &size, u32(index))
	if p == nil || size == 0 {
		return nil
	}
	return p[:size]
}

// bytes is the guest's memory from ptr for size bytes, or false when that
// range is not inside it. This is the bounds check to make on a pointer a
// guest handed over, since the guest chose the number.
//
// The end of the range is never computed: `ptr + size` is where a bounds
// check goes wrong, because a size near the top of the range wraps it back
// down into the memory it was supposed to be outside of. What is left of the
// memory after ptr is subtracted instead, which cannot wrap. jm:wasm/fuzz's
// bounds property is what found that, and is what keeps it found.
bytes :: proc(mod: Module, ptr: u32, size: int, index := 0) -> ([]byte, bool) {
	view := memory(mod, index)
	start := int(ptr)
	if size < 0 || start > len(view) || size > len(view) - start {
		return nil, false
	}
	return view[start:][:size], true
}

// global reads the module's exported global.
global :: proc(mod: Module, name: string) -> (value: Value, err: Error) {
	g := m3_FindGlobal(mod.handle, strings.clone_to_cstring(name, context.temp_allocator))
	if g == nil {
		return nil, Fault {
			kind = .Not_Found,
			text = fmt.aprintf("no global named %s", name, allocator = mod.allocator),
		}
	}
	tagged: Tagged
	if res := m3_GetGlobal(g, &tagged); res != nil {
		return nil, fault(mod.rt, res, mod.allocator)
	}
	switch tagged.type {
	case .I32:
		return i32(tagged.value.i32_), nil
	case .I64:
		return i64(tagged.value.i64_), nil
	case .F32:
		return tagged.value.f32_, nil
	case .F64:
		return tagged.value.f64_, nil
	case .None, .V128, .Func_Ref, .Extern_Ref, .Exn_Ref, .Cont_Ref, .Unknown:
		return nil, Fault {
			kind = .Fail,
			text = fmt.aprintf(
				"global %s is %v, which is not a Value",
				name,
				tagged.type,
				allocator = mod.allocator,
			),
		}
	}
	return nil, nil
}

// set_global writes the module's exported global, which has to be mutable and
// to already hold the type being written.
set_global :: proc(mod: Module, name: string, value: Value) -> Error {
	g := m3_FindGlobal(mod.handle, strings.clone_to_cstring(name, context.temp_allocator))
	if g == nil {
		return Fault {
			kind = .Not_Found,
			text = fmt.aprintf("no global named %s", name, allocator = mod.allocator),
		}
	}
	tagged: Tagged
	switch v in value {
	case i32:
		tagged.type = .I32
		tagged.value.i32_ = u32(v)
	case i64:
		tagged.type = .I64
		tagged.value.i64_ = u64(v)
	case f32:
		tagged.type = .F32
		tagged.value.f32_ = v
	case f64:
		tagged.type = .F64
		tagged.value.f64_ = v
	case:
		return Fault {
			kind = .Fail,
			text = strings.clone("no value to set the global to", mod.allocator),
		}
	}
	if res := m3_SetGlobal(g, &tagged); res != nil {
		return fault(mod.rt, res, mod.allocator)
	}
	return nil
}

// Host is a function the guest imports from this process. Arguments and
// results live in sp: the result slots come first, the arguments after, one
// 64-bit slot each whatever the declared type, which is what arg and ret
// index into. mem is the base of the caller's linear memory, and a guest
// pointer is an offset into it; host_bytes turns one into a slice.
//
// It runs on the calling thread with no Odin context, so a body that needs
// one sets `context = runtime.default_context()` first. Returning nil is
// success; returning a string traps the guest with it, which no Wasm can
// catch.
Host :: Raw_Call

// link binds fn to the import the module declares as module_name.func_name.
// Link every import before the call that reaches it; an import still missing
// then fails that call rather than the load.
//
// signature spells the C-level shape of the function as wasm3 writes it:
// results, then the arguments in parentheses. 'v' is void, 'i' is i32, 'I' is
// i64, 'f' is f32, 'F' is f64 and '*' is a guest pointer, an i32 by another
// name. `log(ptr, len)` returning nothing is "v(*i)"; `hash(i64) -> i32` is
// "i(I)".
link :: proc(
	mod: Module,
	module_name: string,
	func_name: string,
	signature: string,
	fn: Host,
	userdata: rawptr = nil,
) -> Error {
	m := strings.clone_to_cstring(module_name, context.temp_allocator)
	f := strings.clone_to_cstring(func_name, context.temp_allocator)
	s := strings.clone_to_cstring(signature, context.temp_allocator)
	if res := m3_LinkRawFunctionEx(mod.handle, m, f, s, fn, userdata); res != nil {
		return fault(mod.rt, res, mod.allocator)
	}
	return nil
}

// arg reads a host function's argument at index as T. rets is how many
// results the function returns, because those slots come first.
arg :: proc "contextless" (sp: [^]u64, rets: int, index: int, $T: typeid) -> T {
	return (^T)(&sp[rets + index])^
}

// ret writes a host function's result at index.
ret :: proc "contextless" (sp: [^]u64, index: int, value: $T) {
	(^T)(&sp[index])^ = value
}

// host_bytes is bytes for a host function, which is handed the memory it was
// called from rather than a module. The same rule holds: a pointer the guest
// chose is checked before it is used.
host_bytes :: proc "contextless" (mem: rawptr, ptr: u32, size: int) -> ([]byte, bool) {
	if mem == nil {
		return nil, false
	}
	n := int(m3_GetMemorySizeAt(mem))
	start := int(ptr)
	// Subtracting rather than adding, for the reason bytes gives.
	if size < 0 || start > n || size > n - start {
		return nil, false
	}
	base := ([^]u8)(mem)
	return base[start:][:size], true
}

// gas_used is how much of the budget the runtime has spent. It can exceed the
// limit by the cost of the stretch of code that ran out: vendor/wasm3.h's
// m3_SetGasLimit records that a segment is charged in full before any of it
// runs.
gas_used :: proc(vm: Vm) -> f64 {
	return m3_GetGasUsed(vm.rt)
}

// set_gas re-arms the runtime with a full budget of gas, which is how a
// module that trapped with Out_Of_Gas is given more. Code already compiled is
// not instrumented by this: a runtime that has to be metered is opened with
// Opts.gas set.
set_gas :: proc(vm: Vm, gas: f64) {
	m3_SetGasLimit(vm.rt, gas)
}

// interrupt asks the running call to pause, and is the one call here meant to
// be made from another thread. The pause takes effect at the next loop back
// edge or function entry, and the call comes back as a Fault with kind
// Suspended; resume picks it up from there. The Vm has to have been opened
// with Opts.suspendable, since only code compiled that way pauses.
//
// It exists because nothing else bounds how long a call runs. A guest that
// loops forever keeps call busy until it is interrupted or runs out of gas.
// It is safe from another thread where nothing else in this package is,
// because all it does is set a flag the running call reads.
interrupt :: proc(vm: Vm) {
	m3_RequestSuspend(vm.rt)
}

// suspended reports whether a call is paused, waiting for resume.
suspended :: proc(vm: Vm) -> bool {
	return m3_IsSuspended(vm.rt)
}

// resume continues the paused call. It returns when the call finishes or is
// paused again; read what it returned with results, on the Func the paused
// call was made through.
resume :: proc(vm: Vm) -> Error {
	if res := m3_ResumeRuntime(vm.rt); res != nil {
		return fault(vm.rt, res, vm.allocator)
	}
	return nil
}

// version is the wasm3 version compiled in, such as "0.9.1".
version :: proc() -> string {
	return VERSION
}

// VERSION is what the vendored wasm3.h declares. The tests check it against
// the header, so the two cannot drift apart unnoticed.
VERSION :: "0.9.1"

// fault builds the error for a result wasm3 returned: its kind from which
// constant it is, and its text from the result plus whatever detail the
// runtime recorded alongside it.
@(private)
fault :: proc(rt: ^Runtime, res: cstring, allocator: mem.Allocator) -> Error {
	kind := classify(res)
	text := string(res)
	info: Error_Info
	if rt != nil {
		// This clears the recorded info, so the next failure cannot report the
		// one before it.
		m3_GetErrorInfo(rt, &info)
	}
	// The detail only belongs to this result when it is the one the runtime
	// recorded; a stale message would name the wrong thing.
	if info.result == res && info.message != nil && len(string(info.message)) > 0 {
		text = fmt.aprintf("%s: %s", text, info.message, allocator = allocator)
	} else {
		text = strings.clone(text, allocator)
	}
	code := 0
	if kind == .Exit {
		code = int(m3_GetWasiContext().exit_code)
	}
	return Fault{kind = kind, text = text, code = code}
}

// classify sorts a result by identity. wasm3 returns the pointer to one of
// these constants, so this is a comparison of pointers, not of messages.
@(private)
classify :: proc(res: cstring) -> Kind {
	switch res {
	case m3Err_functionLookupFailed, m3Err_globalLookupFailed:
		return .Not_Found
	case m3Err_trapOutOfGas:
		return .Out_Of_Gas
	case m3Err_trapExit, m3Err_trapWasiExit:
		return .Exit
	case m3Err_continuationSuspended:
		return .Suspended
	case m3Err_trapOutOfBoundsMemoryAccess,
	     m3Err_trapDivisionByZero,
	     m3Err_trapIntegerOverflow,
	     m3Err_trapIntegerConversion,
	     m3Err_trapIndirectCallTypeMismatch,
	     m3Err_trapTableIndexOutOfRange,
	     m3Err_trapTableElementIsNull,
	     m3Err_trapNullReference,
	     m3Err_trapUnreachable,
	     m3Err_trapStackOverflow,
	     m3Err_trapUncaughtException,
	     m3Err_trapAbort:
		return .Trap
	}
	return .Fail
}
