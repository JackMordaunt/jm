/*
A Wasm encoder, small enough to read: enough of the binary format to emit the
modules this suite needs and nothing more. It exists so a case is a function
of the bytes it drew and nothing else — no .wasm files beside the source, no
toolchain to install, and a shape the properties can draw rather than pick
from a fixed few.

The format is sections in a fixed order, each a byte of identity, its length,
and a vector of entries. What is here is types (1), functions (3), memory (5),
exports (7), code (10) and data (11); a module with no imports, no tables and
no start section needs no others.
*/
package wasm_fuzz

import "jm:wasm"

// Fn is one function a built module holds and exports.
Fn :: struct {
	// The name it is exported under. Names have to differ within a module.
	name:    string,
	params:  []wasm.Type,
	results: []wasm.Type,
	// The instructions, without the end byte that closes them.
	body:    []byte,
}

// Spec is a whole module.
Spec :: struct {
	funcs: []Fn,
	// Pages of linear memory, exported as "memory". Zero is no memory.
	pages: int,
	// Bytes written into the memory at offset zero. Ignored without pages.
	data:  []byte,
}

// Opcodes and type bytes, named where a number would be a riddle.
@(private)
LOCAL_GET :: 0x20
@(private)
I32_ADD :: 0x6a
@(private)
END :: 0x0b

// build encodes the module. Nothing here validates it: a Spec that asks for a
// body leaving the wrong types on the stack is encoded faithfully, and what
// the loader makes of it is the loader's business. That is a thing worth
// being able to ask for — drawn_module asks for it constantly, and
// drawn_wasm_is_sometimes_a_module checks that some of what it builds is
// refused and some is not.
build :: proc(spec: Spec, allocator := context.temp_allocator) -> []byte {
	out := make([dynamic]byte, allocator)
	// The magic and the version, which is all every module starts with.
	append(&out, 0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00)

	// One type per function, duplicates and all: an index into this section
	// is what the function section names.
	types := make([dynamic]byte, context.temp_allocator)
	write_uleb(&types, len(spec.funcs))
	for f in spec.funcs {
		append(&types, 0x60)
		write_uleb(&types, len(f.params))
		for p in f.params {
			append(&types, type_byte(p))
		}
		write_uleb(&types, len(f.results))
		for r in f.results {
			append(&types, type_byte(r))
		}
	}
	write_section(&out, 1, types[:])

	funcs := make([dynamic]byte, context.temp_allocator)
	write_uleb(&funcs, len(spec.funcs))
	for _, i in spec.funcs {
		write_uleb(&funcs, i)
	}
	write_section(&out, 3, funcs[:])

	if spec.pages > 0 {
		mems := make([dynamic]byte, context.temp_allocator)
		write_uleb(&mems, 1)
		// Limits with no maximum, then the minimum in pages.
		append(&mems, 0x00)
		write_uleb(&mems, spec.pages)
		write_section(&out, 5, mems[:])
	}

	exports := make([dynamic]byte, context.temp_allocator)
	write_uleb(&exports, len(spec.funcs) + (spec.pages > 0 ? 1 : 0))
	if spec.pages > 0 {
		write_name(&exports, "memory")
		// Kind 2 is a memory, and index 0 is the only one a module has here.
		append(&exports, 0x02)
		write_uleb(&exports, 0)
	}
	for f, i in spec.funcs {
		write_name(&exports, f.name)
		append(&exports, 0x00)
		write_uleb(&exports, i)
	}
	write_section(&out, 7, exports[:])

	codes := make([dynamic]byte, context.temp_allocator)
	write_uleb(&codes, len(spec.funcs))
	for f in spec.funcs {
		body := make([dynamic]byte, context.temp_allocator)
		// No locals: every one of these bodies works off its parameters.
		write_uleb(&body, 0)
		append(&body, ..f.body)
		append(&body, END)
		write_uleb(&codes, len(body))
		append(&codes, ..body[:])
	}
	write_section(&out, 10, codes[:])

	if spec.pages > 0 && len(spec.data) > 0 {
		data := make([dynamic]byte, context.temp_allocator)
		write_uleb(&data, 1)
		// Active segment, memory 0, at the offset i32.const 0.
		append(&data, 0x00, 0x41, 0x00, END)
		write_uleb(&data, len(spec.data))
		append(&data, ..spec.data)
		write_section(&out, 11, data[:])
	}
	return out[:]
}

// adder is the known-good module: add(i32, i32) -> i32, and nothing else.
adder :: proc(allocator := context.temp_allocator) -> []byte {
	body := []byte{LOCAL_GET, 0x00, LOCAL_GET, 0x01, I32_ADD}
	return build(
		{funcs = {{name = "add", params = {.I32, .I32}, results = {.I32}, body = body}}},
		allocator,
	)
}

// identity is id(T) -> T for one type: a function that hands its argument
// straight back, which is what round_trip needs to see a value survive the
// crossing and nothing else.
identity :: proc(type: wasm.Type, allocator := context.temp_allocator) -> []byte {
	body := []byte{LOCAL_GET, 0x00}
	return build({funcs = {{name = "id", params = {type}, results = {type}, body = body}}}, allocator)
}

// looper is count(i32) -> i32: it counts its argument down to zero and
// returns 42, so a drawn argument buys a drawn amount of work. It is the only
// module here that can run longer than the gas it is given.
//
//	(block (loop (br_if 1 (i32.eqz (local.get 0)))
//	  (local.set 0 (i32.sub (local.get 0) (i32.const 1))) (br 0)))
//	(i32.const 42)
looper :: proc(allocator := context.temp_allocator) -> []byte {
	body := []byte {
		0x02, 0x40, // block, no result
		0x03, 0x40, // loop, no result
		0x20, 0x00, // local.get 0
		0x45, // i32.eqz
		0x0d, 0x01, // br_if 1, out of the block
		0x20, 0x00, // local.get 0
		0x41, 0x01, // i32.const 1
		0x6b, // i32.sub
		0x21, 0x00, // local.set 0
		0x0c, 0x00, // br 0, back to the loop
		END, // end loop
		END, // end block
		0x41, 0x2a, // i32.const 42
	}
	return build(
		{funcs = {{name = "count", params = {.I32}, results = {.I32}, body = body}}},
		allocator,
	)
}

// consts is a body that leaves one zero of each type on the stack: the
// shortest way to satisfy any signature, whatever it asks to return.
consts :: proc(types: []wasm.Type, allocator := context.temp_allocator) -> []byte {
	out := make([dynamic]byte, allocator)
	for t in types {
		switch t {
		case .I32:
			append(&out, 0x41, 0x00)
		case .I64:
			append(&out, 0x42, 0x00)
		case .F32:
			append(&out, 0x43, 0x00, 0x00, 0x00, 0x00)
		case .F64:
			append(&out, 0x44, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)
		case .None, .V128, .Func_Ref, .Extern_Ref, .Exn_Ref, .Cont_Ref, .Unknown:
			append(&out, 0x41, 0x00)
		}
	}
	return out[:]
}

// type_byte is how a value type is spelled in the binary format. The types a
// Value cannot carry are spelled i32, because a signature naming one is not
// something this suite builds on purpose.
@(private)
type_byte :: proc(t: wasm.Type) -> byte {
	switch t {
	case .I32:
		return 0x7f
	case .I64:
		return 0x7e
	case .F32:
		return 0x7d
	case .F64:
		return 0x7c
	case .None, .V128, .Func_Ref, .Extern_Ref, .Exn_Ref, .Cont_Ref, .Unknown:
		return 0x7f
	}
	return 0x7f
}

// write_section writes one section: its identity, its length, then its payload.
@(private)
write_section :: proc(out: ^[dynamic]byte, id: byte, payload: []byte) {
	if len(payload) == 0 {
		return
	}
	append(out, id)
	write_uleb(out, len(payload))
	append(out, ..payload)
}

// write_name writes a string the way the format carries one: its length, then its
// bytes, with no terminator.
@(private)
write_name :: proc(out: ^[dynamic]byte, s: string) {
	write_uleb(out, len(s))
	append(out, ..transmute([]byte)s)
}

// write_uleb writes an unsigned LEB128, which is how the format spells every length
// and every index.
@(private)
write_uleb :: proc(out: ^[dynamic]byte, v: int) {
	n := u64(v)
	for {
		b := byte(n & 0x7f)
		n >>= 7
		if n != 0 {
			b |= 0x80
		}
		append(out, b)
		if n == 0 {
			return
		}
	}
}
