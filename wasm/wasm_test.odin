package wasm

import "core:strings"
import "core:testing"

// The modules the tests run are written out here as bytes rather than built by
// a toolchain, so the suite needs nothing installed and every byte under test
// is visible. Each one's source is the WAT above it.

// (module (func (export "add") (param i32 i32) (result i32)
//   (i32.add (local.get 0) (local.get 1))))
@(private)
ADD_WASM := []byte {
	0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x07, 0x01, 0x60,
	0x02, 0x7f, 0x7f, 0x01, 0x7f, 0x03, 0x02, 0x01, 0x00, 0x07, 0x07, 0x01,
	0x03, 0x61, 0x64, 0x64, 0x00, 0x00, 0x0a, 0x09, 0x01, 0x07, 0x00, 0x20,
	0x00, 0x20, 0x01, 0x6a, 0x0b,
}

// (module (memory (export "memory") 1) (data (i32.const 0) "hello")
//   (global (export "counter") (mut i32) (i32.const 7))
//   (func (export "store") (param i32 i32) (i32.store (local.get 0) (local.get 1)))
//   (func (export "load") (param i32) (result i32) (i32.load (local.get 0))))
@(private)
MEM_WASM := []byte {
	0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x0b, 0x02, 0x60,
	0x02, 0x7f, 0x7f, 0x00, 0x60, 0x01, 0x7f, 0x01, 0x7f, 0x03, 0x03, 0x02,
	0x00, 0x01, 0x05, 0x03, 0x01, 0x00, 0x01, 0x06, 0x06, 0x01, 0x7f, 0x01,
	0x41, 0x07, 0x0b, 0x07, 0x23, 0x04, 0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72,
	0x79, 0x02, 0x00, 0x07, 0x63, 0x6f, 0x75, 0x6e, 0x74, 0x65, 0x72, 0x03,
	0x00, 0x05, 0x73, 0x74, 0x6f, 0x72, 0x65, 0x00, 0x00, 0x04, 0x6c, 0x6f,
	0x61, 0x64, 0x00, 0x01, 0x0a, 0x13, 0x02, 0x09, 0x00, 0x20, 0x00, 0x20,
	0x01, 0x36, 0x02, 0x00, 0x0b, 0x07, 0x00, 0x20, 0x00, 0x28, 0x02, 0x00,
	0x0b, 0x0b, 0x0b, 0x01, 0x00, 0x41, 0x00, 0x0b, 0x05, 0x68, 0x65, 0x6c,
	0x6c, 0x6f,
}

// (module (memory 1)
//   (func (export "boom") unreachable)
//   (func (export "oob") (result i32) (i32.load (i32.const 0x100000)))
//   (func (export "divzero") (param i32 i32) (result i32)
//     (i32.div_s (local.get 0) (local.get 1))))
@(private)
TRAPS_WASM := []byte {
	0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x0e, 0x03, 0x60,
	0x00, 0x00, 0x60, 0x00, 0x01, 0x7f, 0x60, 0x02, 0x7f, 0x7f, 0x01, 0x7f,
	0x03, 0x04, 0x03, 0x00, 0x01, 0x02, 0x05, 0x03, 0x01, 0x00, 0x01, 0x07,
	0x18, 0x03, 0x04, 0x62, 0x6f, 0x6f, 0x6d, 0x00, 0x00, 0x03, 0x6f, 0x6f,
	0x62, 0x00, 0x01, 0x07, 0x64, 0x69, 0x76, 0x7a, 0x65, 0x72, 0x6f, 0x00,
	0x02, 0x0a, 0x17, 0x03, 0x03, 0x00, 0x00, 0x0b, 0x09, 0x00, 0x41, 0x80,
	0x80, 0x40, 0x28, 0x02, 0x00, 0x0b, 0x07, 0x00, 0x20, 0x00, 0x20, 0x01,
	0x6d, 0x0b,
}

// (module (import "host" "add1" (func (param i32) (result i32)))
//   (memory (export "memory") 1)
//   (func (export "call_host") (param i32) (result i32) (call 0 (local.get 0))))
@(private)
HOST_WASM := []byte {
	0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x06, 0x01, 0x60,
	0x01, 0x7f, 0x01, 0x7f, 0x02, 0x0d, 0x01, 0x04, 0x68, 0x6f, 0x73, 0x74,
	0x04, 0x61, 0x64, 0x64, 0x31, 0x00, 0x00, 0x03, 0x02, 0x01, 0x00, 0x05,
	0x03, 0x01, 0x00, 0x01, 0x07, 0x16, 0x02, 0x06, 0x6d, 0x65, 0x6d, 0x6f,
	0x72, 0x79, 0x02, 0x00, 0x09, 0x63, 0x61, 0x6c, 0x6c, 0x5f, 0x68, 0x6f,
	0x73, 0x74, 0x00, 0x01, 0x0a, 0x08, 0x01, 0x06, 0x00, 0x20, 0x00, 0x10,
	0x00, 0x0b,
}

// (module (import "wasi_snapshot_preview1" "proc_exit" (func (param i32)))
//   (memory (export "memory") 1)
//   (func (export "_start") (call 0 (i32.const 7))))
@(private)
WASI_WASM := []byte {
	0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x02, 0x60,
	0x01, 0x7f, 0x00, 0x60, 0x00, 0x00, 0x02, 0x24, 0x01, 0x16, 0x77, 0x61,
	0x73, 0x69, 0x5f, 0x73, 0x6e, 0x61, 0x70, 0x73, 0x68, 0x6f, 0x74, 0x5f,
	0x70, 0x72, 0x65, 0x76, 0x69, 0x65, 0x77, 0x31, 0x09, 0x70, 0x72, 0x6f,
	0x63, 0x5f, 0x65, 0x78, 0x69, 0x74, 0x00, 0x00, 0x03, 0x02, 0x01, 0x01,
	0x05, 0x03, 0x01, 0x00, 0x01, 0x07, 0x13, 0x02, 0x06, 0x6d, 0x65, 0x6d,
	0x6f, 0x72, 0x79, 0x02, 0x00, 0x06, 0x5f, 0x73, 0x74, 0x61, 0x72, 0x74,
	0x00, 0x01, 0x0a, 0x08, 0x01, 0x06, 0x00, 0x41, 0x07, 0x10, 0x00, 0x0b,
}

// (module (import "host" "sum" (func (param i32 i32) (result i32)))
//   (memory (export "memory") 1) (data (i32.const 16) "abc")
//   (func (export "read") (result i32) (call 0 (i32.const 16) (i32.const 3)))
//   (func (export "overrun") (result i32) (call 0 (i32.const 16) (i32.const 65536))))
@(private)
GUESTMEM_WASM := []byte {
	0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x0b, 0x02, 0x60,
	0x02, 0x7f, 0x7f, 0x01, 0x7f, 0x60, 0x00, 0x01, 0x7f, 0x02, 0x0c, 0x01,
	0x04, 0x68, 0x6f, 0x73, 0x74, 0x03, 0x73, 0x75, 0x6d, 0x00, 0x00, 0x03,
	0x03, 0x02, 0x01, 0x01, 0x05, 0x03, 0x01, 0x00, 0x01, 0x07, 0x1b, 0x03,
	0x06, 0x6d, 0x65, 0x6d, 0x6f, 0x72, 0x79, 0x02, 0x00, 0x04, 0x72, 0x65,
	0x61, 0x64, 0x00, 0x01, 0x07, 0x6f, 0x76, 0x65, 0x72, 0x72, 0x75, 0x6e,
	0x00, 0x02, 0x0a, 0x15, 0x02, 0x08, 0x00, 0x41, 0x10, 0x41, 0x03, 0x10,
	0x00, 0x0b, 0x0a, 0x00, 0x41, 0x10, 0x41, 0x80, 0x80, 0x04, 0x10, 0x00,
	0x0b, 0x0b, 0x09, 0x01, 0x00, 0x41, 0x10, 0x0b, 0x03, 0x61, 0x62, 0x63,
}

// (module (func (export "count") (param i32) (result i32)
//   (block (loop (br_if 1 (i32.eqz (local.get 0)))
//     (local.set 0 (i32.sub (local.get 0) (i32.const 1))) (br 0)))
//   (i32.const 42)))
@(private)
COUNT_WASM := []byte {
	0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00, 0x01, 0x06, 0x01, 0x60,
	0x01, 0x7f, 0x01, 0x7f, 0x03, 0x02, 0x01, 0x00, 0x07, 0x09, 0x01, 0x05,
	0x63, 0x6f, 0x75, 0x6e, 0x74, 0x00, 0x00, 0x0a, 0x1a, 0x01, 0x18, 0x00,
	0x02, 0x40, 0x03, 0x40, 0x20, 0x00, 0x45, 0x0d, 0x01, 0x20, 0x00, 0x41,
	0x01, 0x6b, 0x21, 0x00, 0x0c, 0x00, 0x0b, 0x0b, 0x41, 0x2a, 0x0b,
}

// VERSION is written down in wasm.odin rather than read out of the library,
// which is the sort of constant that goes stale the next time the vendored
// tree moves. The header is embedded at compile time so it cannot.
@(test)
version_matches_the_vendored_header :: proc(t: ^testing.T) {
	header := string(#load("vendor/wasm3.h"))
	macro := "#define M3_VERSION       "
	i := strings.index(header, macro)
	testing.expect(t, i >= 0, "wasm3.h must define M3_VERSION")
	rest := header[i + len(macro):]
	quoted := rest[:strings.index(rest, "\n")]
	testing.expect_value(t, strings.trim(quoted, "\" \r"), VERSION)
	testing.expect_value(t, version(), VERSION)
}

// vendor/m3_config.h leaves d_m3HasGasMetering on and says nothing about
// WASI, which the justfile's recipe turns on with -Dd_m3HasWASI. Both are
// compiled in or they are not, so this is how a build against some other
// archive is caught.
@(test)
the_archive_is_the_one_just_wasm_built :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := open(Opts{gas = 1e6})
	testing.expect_value(t, err, nil)
	defer close(&vm)

	// The recipe's -Dd_m3HasWASI is what puts the WASI imports in the
	// library; without it this module's proc_exit stays unresolved and the
	// call below fails rather than exiting.
	mod, lerr := load(vm, WASI_WASM, Load{wasi = true})
	testing.expect_value(t, lerr, nil)
	code, rerr := run(mod)
	testing.expect_value(t, rerr, nil)
	testing.expect_value(t, code, 7)

	testing.expect(t, gas_used(vm) > 0, "gas metering must be compiled in")
}

@(test)
add_round_trips :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := open()
	testing.expect_value(t, err, nil)
	defer close(&vm)

	mod, lerr := load(vm, ADD_WASM)
	testing.expect_value(t, lerr, nil)
	add, ferr := find(mod, "add")
	testing.expect_value(t, ferr, nil)

	args, rets := arity(add)
	testing.expect_value(t, args, 2)
	testing.expect_value(t, rets, 1)
	testing.expect_value(t, arg_type(add, 0), Type.I32)
	testing.expect_value(t, ret_type(add, 0), Type.I32)

	out, cerr := call(add, i32(19), i32(23))
	testing.expect_value(t, cerr, nil)
	testing.expect_value(t, len(out), 1)
	testing.expect_value(t, out[0].(i32), 42)
}

// Nothing below the wrapper checks an argument's type: m3_Call takes bare
// pointers and the signature says how to read them, so without this check a
// Value of the wrong type would be read as the declared one. The check is
// here, and these are the three ways a caller gets a list wrong.
@(test)
arguments_are_checked_against_the_signature :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := open()
	testing.expect_value(t, err, nil)
	defer close(&vm)
	mod, _ := load(vm, ADD_WASM)
	add, _ := find(mod, "add")

	_, few := call(add, i32(1))
	testing.expect_value(t, kind_of(few), Kind.Fail)
	_, wrong := call(add, i64(1), i32(2))
	testing.expect_value(t, kind_of(wrong), Kind.Fail)
	_, none := call(add, nil, i32(2))
	testing.expect_value(t, kind_of(none), Kind.Fail)
}

@(test)
a_missing_export_is_not_found :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := open()
	testing.expect_value(t, err, nil)
	defer close(&vm)
	mod, _ := load(vm, ADD_WASM)

	_, ferr := find(mod, "subtract")
	testing.expect_value(t, kind_of(ferr), Kind.Not_Found)
	_, gerr := global(mod, "nothing")
	testing.expect_value(t, kind_of(gerr), Kind.Not_Found)
}

// The view is the guest's own memory: what the host writes into it is what the
// guest loads, and the other way around.
@(test)
memory_is_shared_with_the_guest :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := open()
	testing.expect_value(t, err, nil)
	defer close(&vm)
	mod, lerr := load(vm, MEM_WASM)
	testing.expect_value(t, lerr, nil)

	view := memory(mod)
	testing.expect_value(t, len(view), 64 * 1024)
	testing.expect_value(t, string(view[:5]), "hello")

	// Host writes, guest reads.
	view[64] = 0xef
	view[65] = 0xbe
	view[66] = 0xad
	view[67] = 0xde
	load_fn, _ := find(mod, "load")
	out, cerr := call(load_fn, i32(64))
	testing.expect_value(t, cerr, nil)
	testing.expect_value(t, u32(out[0].(i32)), 0xdeadbeef)

	// Guest writes, host reads.
	store_fn, _ := find(mod, "store")
	_, serr := call(store_fn, i32(128), i32(0x01020304))
	testing.expect_value(t, serr, nil)
	at, ok := bytes(mod, 128, 4)
	testing.expect(t, ok)
	testing.expect_value(t, at[0], 0x04)
	testing.expect_value(t, at[3], 0x01)
}

// A pointer the guest chose is checked before it is used, which is the whole
// job of bytes.
@(test)
bytes_refuses_a_range_outside_the_memory :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := open()
	defer close(&vm)
	mod, _ := load(vm, MEM_WASM)

	_, ok := bytes(mod, 64 * 1024 - 4, 4)
	testing.expect(t, ok, "the last four bytes are inside the memory")
	_, past := bytes(mod, 64 * 1024 - 3, 4)
	testing.expect(t, !past, "a range running off the end is refused")
	_, wild := bytes(mod, 0xffff_fff0, 16)
	testing.expect(t, !wild, "a pointer past the memory is refused")
	_, negative := bytes(mod, 0, -1)
	testing.expect(t, !negative, "a negative size is refused")

	// A size near the top of the range makes ptr + size wrap back down into
	// the memory, so a check that adds them up admits it and then slices with
	// a negative length. jm:wasm/fuzz's bounds property found this; it
	// subtracts now, and this is the case it found.
	_, wrapped := bytes(mod, 8, max(int))
	testing.expect(t, !wrapped, "a size that overflows the addition is refused")
	_, huge := bytes(mod, 0, max(int) - 8)
	testing.expect(t, !huge, "so is one that does not overflow but is still too big")
}

@(test)
globals_read_and_write :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := open()
	defer close(&vm)
	mod, _ := load(vm, MEM_WASM)

	v, err := global(mod, "counter")
	testing.expect_value(t, err, nil)
	testing.expect_value(t, v.(i32), 7)

	testing.expect_value(t, set_global(mod, "counter", i32(9)), nil)
	v2, _ := global(mod, "counter")
	testing.expect_value(t, v2.(i32), 9)
}

// Every trap is the guest's fault and sorts as one, whatever wasm3 called
// it. One test per trap, so a platform where one of them faults instead of
// trapping names it (Windows did, under clang-cl).
@(private = "file")
trap_module :: proc(t: ^testing.T) -> (vm: Vm, mod: Module) {
	vm, _ = open()
	lerr: Error
	mod, lerr = load(vm, TRAPS_WASM)
	testing.expect_value(t, lerr, nil)
	return
}

@(test)
trap_unreachable :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, mod := trap_module(t)
	defer close(&vm)
	boom, _ := find(mod, "boom")
	_, berr := call(boom)
	testing.expect_value(t, kind_of(berr), Kind.Trap)
}

@(test)
trap_out_of_bounds :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, mod := trap_module(t)
	defer close(&vm)
	oob, _ := find(mod, "oob")
	_, oerr := call(oob)
	testing.expect_value(t, kind_of(oerr), Kind.Trap)
}

@(test)
trap_division_by_zero :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, mod := trap_module(t)
	defer close(&vm)
	div, _ := find(mod, "divzero")
	_, derr := call(div, i32(1), i32(0))
	testing.expect_value(t, kind_of(derr), Kind.Trap)
	// The text says which trap it was, so a log line is worth reading.
	if f, ok := derr.(Fault); ok {
		testing.expect(t, strings.contains(f.text, "divide"), f.text)
	}
}

// step is what add1_host adds, reached through the userdata link passes on.
@(private)
step := i32(1)

@(private)
add1_host :: proc "c" (
	rt: ^Runtime,
	ctx: ^Import_Context,
	sp: [^]u64,
	mem: rawptr,
) -> cstring {
	n := arg(sp, 1, 0, i32)
	by := (^i32)(ctx.userdata)^
	ret(sp, 0, n + by)
	return nil
}

@(private)
refuse_host :: proc "c" (
	rt: ^Runtime,
	ctx: ^Import_Context,
	sp: [^]u64,
	mem: rawptr,
) -> cstring {
	return "the host said no"
}

@(test)
a_host_function_is_called_back :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := open()
	defer close(&vm)
	mod, lerr := load(vm, HOST_WASM)
	testing.expect_value(t, lerr, nil)

	testing.expect_value(t, link(mod, "host", "add1", "i(i)", add1_host, &step), nil)
	fn, _ := find(mod, "call_host")
	out, cerr := call(fn, i32(41))
	testing.expect_value(t, cerr, nil)
	testing.expect_value(t, out[0].(i32), 42)
}

// A guest pointer is a number the guest chose, so a host function that reads
// guest memory checks it before it reads. host_bytes is that check, and this
// is both ways it goes: a range inside the memory is read, and one running off
// the end traps the guest instead.
@(private)
sum_host :: proc "c" (rt: ^Runtime, ctx: ^Import_Context, sp: [^]u64, mem: rawptr) -> cstring {
	ptr := arg(sp, 1, 0, u32)
	size := arg(sp, 1, 1, i32)
	bytes, ok := host_bytes(mem, ptr, int(size))
	if !ok {
		return "sum: the guest pointer is not inside its memory"
	}
	total: i32
	for b in bytes {
		total += i32(b)
	}
	ret(sp, 0, total)
	return nil
}

@(test)
a_host_function_reads_guest_memory :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := open()
	defer close(&vm)
	mod, lerr := load(vm, GUESTMEM_WASM)
	testing.expect_value(t, lerr, nil)
	testing.expect_value(t, link(mod, "host", "sum", "i(*i)", sum_host), nil)

	// "abc" was written into the module's data section at offset 16.
	fn, _ := find(mod, "read")
	out, cerr := call(fn)
	testing.expect_value(t, cerr, nil)
	testing.expect_value(t, out[0].(i32), 'a' + 'b' + 'c')

	// The same pointer with a length that runs off the end is refused, and
	// the refusal reaches the guest as a trap it cannot catch.
	over, _ := find(mod, "overrun")
	_, oerr := call(over)
	f, ok := oerr.(Fault)
	testing.expect(t, ok, "reading past the memory must not come back clean")
	testing.expect(t, strings.contains(f.text, "not inside its memory"), f.text)
}

// A host function that returns a string traps the guest with it, which is how
// a host refuses what it was asked to do.
@(test)
a_host_function_can_trap_the_guest :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := open()
	defer close(&vm)
	mod, _ := load(vm, HOST_WASM)

	testing.expect_value(t, link(mod, "host", "add1", "i(i)", refuse_host), nil)
	fn, _ := find(mod, "call_host")
	_, cerr := call(fn, i32(41))
	f, ok := cerr.(Fault)
	testing.expect(t, ok, "the guest must not come back clean")
	testing.expect(t, strings.contains(f.text, "the host said no"), f.text)
}

// An import nothing was linked to fails the call that reaches it rather than
// the load, which is what makes linking after load the right order.
@(test)
an_unlinked_import_fails_the_call :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := open()
	defer close(&vm)
	// The module loads with its import unresolved.
	mod, lerr := load(vm, HOST_WASM)
	testing.expect_value(t, lerr, nil)

	fn, ferr := find(mod, "call_host")
	testing.expect_value(t, ferr, nil)
	_, cerr := call(fn, i32(1))
	testing.expect_value(t, kind_of(cerr), Kind.Fail)
}

// A guest that exits asked to stop, and is not a failure.
@(test)
a_wasi_exit_is_a_status_not_a_failure :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, _ := open()
	defer close(&vm)
	mod, lerr := load(vm, WASI_WASM, Load{wasi = true, name = "exiter"})
	testing.expect_value(t, lerr, nil)

	code, rerr := run(mod, []string{"exiter"})
	testing.expect_value(t, rerr, nil)
	testing.expect_value(t, code, 7)
}

// Gas is what bounds a module that would otherwise run forever.
@(test)
gas_bounds_a_long_call :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := open(Opts{gas = 1000})
	testing.expect_value(t, err, nil)
	defer close(&vm)
	mod, _ := load(vm, COUNT_WASM)
	count, _ := find(mod, "count")

	_, cerr := call(count, i32(1_000_000))
	testing.expect_value(t, kind_of(cerr), Kind.Out_Of_Gas)
	testing.expect(t, gas_used(vm) > 0, "the budget was spent")

	// A fresh budget runs the same call to the end.
	set_gas(vm, 1e9)
	out, ok := call(count, i32(1000))
	testing.expect_value(t, ok, nil)
	testing.expect_value(t, out[0].(i32), 42)
}

// interrupt is the other bound: the call stops at a pause point and resume
// picks it up. The request is made before the call here so the test needs no
// second thread; from another thread it is the same call.
@(test)
interrupt_pauses_and_resume_finishes :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	vm, err := open(Opts{suspendable = true})
	testing.expect_value(t, err, nil)
	defer close(&vm)
	mod, lerr := load(vm, COUNT_WASM)
	testing.expect_value(t, lerr, nil)
	count, _ := find(mod, "count")

	interrupt(vm)
	_, cerr := call(count, i32(1000))
	testing.expect_value(t, kind_of(cerr), Kind.Suspended)
	testing.expect(t, suspended(vm), "the call is waiting to be resumed")

	testing.expect_value(t, resume(vm), nil)
	out, rerr := results(count)
	testing.expect_value(t, rerr, nil)
	testing.expect_value(t, out[0].(i32), 42)
}

// kind_of saves every expectation above from unwrapping the union first.
@(private)
kind_of :: proc(err: Error) -> Kind {
	if f, ok := err.(Fault); ok {
		return f.kind
	}
	return .Fail
}
