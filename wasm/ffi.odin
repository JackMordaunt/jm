/*
The raw C API: the subset of wasm3.h the wrapper needs, under the C names,
exported so a caller that needs an interface the wrapper does not cover can
reach for it. The wrapper in wasm.odin is what scripts should use. The
declarations track the vendored header, wasm3.h 0.9.1.

The interpreter is the source tree under vendor/, compiled into lib/ by the
justfile's `wasm` recipe, which is also where the compile-time options and the
reason for each are written down. The archive path below is relative to this
directory, which is what puts lib/ here rather than in build/; the README's
WebAssembly section records that and what `just check` does without it.

M3Result is the C API's error type: a `const char *` that is null on success
and otherwise points at one of the m3Err_ constants below. Two failures are
told apart by the pointer, not by the text, which is why those constants are
imported rather than their messages copied.
*/
package wasm

import "core:c"

when ODIN_OS == .Windows {
	// wasm3's WASI random_get calls SystemFunction036 (RtlGenRandom).
	@(extra_linker_flags = "advapi32.lib")
	foreign import lib "lib/wasm3.lib"
} else {
	@(extra_linker_flags = "-lm")
	foreign import lib "lib/wasm3.a"
}

// Environment is M3Environment: the parsed-module cache a runtime is made
// from. wasm3 owns the memory.
Environment :: struct {}

// Runtime is M3Runtime: one execution context, holding the value stack, the
// loaded modules and their linear memories. wasm3 owns the memory.
Runtime :: struct {}

// Module_Handle is M3Module. m3_LoadModule hands it to the runtime, which
// frees it; a module that was never loaded is freed with m3_FreeModule.
Module_Handle :: struct {}

// Function_Handle is M3Function, one exported function. It is valid for as
// long as the runtime that owns it.
Function_Handle :: struct {}

// Global_Handle is M3Global, one exported global.
Global_Handle :: struct {}

// Value_Type is M3ValueType. Everything past F64 is a type the wrapper can
// name in a signature but cannot carry as a Value.
Value_Type :: enum c.int {
	None       = 0,
	I32        = 1,
	I64        = 2,
	F32        = 3,
	F64        = 4,
	V128       = 5,
	Func_Ref   = 6,
	Extern_Ref = 7,
	Exn_Ref    = 8,
	Cont_Ref   = 9,
	Unknown    = 10,
}

// Tagged is M3TaggedValue, how a global is read and written. vendor/wasm3.h
// declares it as an M3ValueType followed by a union of u32, u64, f32, f64 and
// a pointer, which the compiler lays out as eight bytes at offset eight; the
// assertion below is what keeps this declaration honest if that ever changes.
Tagged :: struct {
	type:  Value_Type,
	value: struct #raw_union {
		i32_: u32,
		i64_: u64,
		f32_: f32,
		f64_: f64,
		ref:  rawptr,
	},
}

// The layout above is a claim about a C struct, and a wrong one would write a
// global's value into the wrong half of it. The compiler checks it here.
#assert(size_of(Tagged) == 16)
#assert(offset_of(Tagged, value) == 8)

// Error_Info is M3ErrorInfo: the result that failed, plus where it happened.
// message carries the detail the result string alone does not, such as the
// name of the import that was missing.
Error_Info :: struct {
	result:   cstring,
	runtime:  ^Runtime,
	module:   ^Module_Handle,
	function: ^Function_Handle,
	file:     cstring,
	line:     u32,
	message:  cstring,
}

// Import_Context is M3ImportContext, the second argument a host function is
// called with: whatever userdata was linked with it, and the function itself.
Import_Context :: struct {
	userdata: rawptr,
	function: ^Function_Handle,
}

// Raw_Call is M3RawCall, the C type of a host function. Arguments and results
// live in sp: the result slots come first, the arguments after, one 64-bit
// slot each whatever the declared type, which is what vendor/wasm3.h's
// m3ApiReturnType and m3ApiGetArg macros walk. Returning nil is success;
// returning a string traps the call with it.
Raw_Call :: #type proc "c" (rt: ^Runtime, ctx: ^Import_Context, sp: [^]u64, mem: rawptr) -> cstring

// Wasi_Context is m3_wasi_context_t: the process-wide WASI state. The argv it
// points at belongs to the caller and has to outlive the call.
Wasi_Context :: struct {
	exit_code: i32,
	argc:      u32,
	argv:      [^]cstring,
}

// The result constants the wrapper classifies by. Each is one global in the
// library — vendor/wasm3.h declares them with d_m3ErrorConst and m3_core.c
// defines them once — so wasm3 hands back the pointer to the one it means and
// identity is the test; the text is for the reader.
foreign lib {
	m3Err_functionLookupFailed: cstring
	m3Err_globalLookupFailed: cstring
	m3Err_trapOutOfBoundsMemoryAccess: cstring
	m3Err_trapDivisionByZero: cstring
	m3Err_trapIntegerOverflow: cstring
	m3Err_trapIntegerConversion: cstring
	m3Err_trapIndirectCallTypeMismatch: cstring
	m3Err_trapTableIndexOutOfRange: cstring
	m3Err_trapTableElementIsNull: cstring
	m3Err_trapNullReference: cstring
	m3Err_trapUnreachable: cstring
	m3Err_trapStackOverflow: cstring
	m3Err_trapUncaughtException: cstring
	m3Err_trapAbort: cstring
	m3Err_trapExit: cstring
	m3Err_trapWasiExit: cstring
	m3Err_trapOutOfGas: cstring
	m3Err_continuationSuspended: cstring
}

@(default_calling_convention = "c")
foreign lib {
	m3_NewEnvironment  :: proc() -> ^Environment ---
	m3_FreeEnvironment :: proc(env: ^Environment) ---

	m3_NewRuntime    :: proc(env: ^Environment, stack_bytes: u32, userdata: rawptr) -> ^Runtime ---
	m3_FreeRuntime   :: proc(rt: ^Runtime) ---
	m3_GetUserData   :: proc(rt: ^Runtime) -> rawptr ---
	m3_SetValidation :: proc(rt: ^Runtime, enable: bool) ---

	m3_SetGasLimit :: proc(rt: ^Runtime, gas: f64) ---
	m3_GetGasLimit :: proc(rt: ^Runtime) -> f64 ---
	m3_GetGasUsed  :: proc(rt: ^Runtime) -> f64 ---

	m3_ParseModule   :: proc(env: ^Environment, mod: ^^Module_Handle, bytes: [^]u8, n: u32) -> cstring ---
	m3_FreeModule    :: proc(mod: ^Module_Handle) ---
	m3_LoadModule    :: proc(rt: ^Runtime, mod: ^Module_Handle) -> cstring ---
	m3_CompileModule :: proc(mod: ^Module_Handle) -> cstring ---
	m3_RunStart      :: proc(mod: ^Module_Handle) -> cstring ---
	m3_SetModuleName :: proc(mod: ^Module_Handle, name: cstring) ---
	m3_GetModuleName :: proc(mod: ^Module_Handle) -> cstring ---

	m3_GetMemory       :: proc(mod: ^Module_Handle, size: ^c.size_t, index: u32) -> [^]u8 ---
	m3_GetMemorySize   :: proc(mod: ^Module_Handle, index: u32) -> c.size_t ---
	m3_GetMemorySizeAt :: proc(mem: rawptr) -> c.size_t ---

	m3_LinkRawFunctionEx :: proc(
		mod: ^Module_Handle,
		mod_name, fn_name, sig: cstring,
		fn: Raw_Call,
		user: rawptr,
	) -> cstring ---
	m3_LinkGlobal        :: proc(mod: ^Module_Handle, mod_name, global_name: cstring, value: ^Tagged) -> cstring ---

	m3_FindGlobal    :: proc(mod: ^Module_Handle, name: cstring) -> ^Global_Handle ---
	m3_GetGlobal     :: proc(g: ^Global_Handle, value: ^Tagged) -> cstring ---
	m3_SetGlobal     :: proc(g: ^Global_Handle, value: ^Tagged) -> cstring ---
	m3_GetGlobalType :: proc(g: ^Global_Handle) -> Value_Type ---

	m3_FindFunctionIn  :: proc(fn: ^^Function_Handle, mod: ^Module_Handle, name: cstring) -> cstring ---
	m3_FindFunction    :: proc(fn: ^^Function_Handle, rt: ^Runtime, name: cstring) -> cstring ---
	m3_GetFunctionName :: proc(fn: ^Function_Handle) -> cstring ---
	m3_GetArgCount     :: proc(fn: ^Function_Handle) -> u32 ---
	m3_GetRetCount     :: proc(fn: ^Function_Handle) -> u32 ---
	m3_GetArgType      :: proc(fn: ^Function_Handle, index: u32) -> Value_Type ---
	m3_GetRetType      :: proc(fn: ^Function_Handle, index: u32) -> Value_Type ---
	m3_Call            :: proc(fn: ^Function_Handle, argc: u32, argptrs: [^]rawptr) -> cstring ---
	m3_GetResults      :: proc(fn: ^Function_Handle, retc: u32, retptrs: [^]rawptr) -> cstring ---

	m3_SetSuspendable :: proc(rt: ^Runtime, suspendable: bool) ---
	m3_RequestSuspend :: proc(rt: ^Runtime) ---
	m3_IsSuspended    :: proc(rt: ^Runtime) -> bool ---
	m3_ResumeRuntime  :: proc(rt: ^Runtime) -> cstring ---

	m3_GetErrorInfo   :: proc(rt: ^Runtime, info: ^Error_Info) ---
	m3_ResetErrorInfo :: proc(rt: ^Runtime) ---

	m3_LinkWASI       :: proc(mod: ^Module_Handle) -> cstring ---
	m3_GetWasiContext :: proc() -> ^Wasi_Context ---
}
