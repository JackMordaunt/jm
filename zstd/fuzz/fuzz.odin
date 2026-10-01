/*
Package fuzz is the jm:zstd suite for jm:fuzz. zstd carries its own fuzz
harnesses (tests/fuzz in the 1.5.7 tarball); what is checked here is the
wrapper's stream loops and the promise a patch makes to jm:selfupdate.

	report := fuzz.run({seed = 1, iterations = 10_000})

	round_trip        compress_stream then decompress_stream is the identity
	patch_round_trip  patch(old, diff(old, new)) is new
	damaged_frame     a damaged frame is an error or its original bytes
	damaged_patch     a damaged patch is an error or new, never other bytes

damaged_patch is the one that matters: selfupdate hashes what a patch decodes
to, but a patch that could decode quietly to the wrong bytes would make that
hash the only guard rather than the second one.
*/
package zstd_fuzz

import "core:bytes"
import "core:fmt"

import harness "jm:fuzz"
import "jm:zstd"

// No subject: every case builds its own inputs.
Subject :: struct {}

// properties is package level because a Suite holds a slice, which has to
// outlive the call that hands the Suite back.
properties := []harness.Property(Subject) {
	{"round_trip", round_trip},
	{"patch_round_trip", patch_round_trip},
	{"damaged_frame", damaged_frame},
	{"damaged_patch", damaged_patch},
}

// suite is jm:zstd and its promises, ready for harness.run.
suite :: proc() -> harness.Suite(Subject) {
	return harness.Suite(Subject) {
		name = "zstd",
		setup = proc() -> (Subject, bool) {return {}, true},
		// No deadline: zstd has no way to interrupt a call in progress, so
		// there is nothing for cancel to do.
		properties = properties,
	}
}

// CORPUS is where this suite's regressions live, relative to the repository
// root.
CORPUS :: "zstd/fuzz/corpus"

// run checks the suite. It is the whole package from a caller's side.
run :: proc(opts := harness.Opts{}, allocator := context.allocator) -> harness.Report {
	return harness.run(suite(), opts, allocator)
}

LEVELS := []int{-5, 1, 3, 9}

// data draws input that is partly noise and partly repeats of itself, so
// both zstd's literal and match paths run.
data :: proc(src: ^harness.Source, max: int) -> []byte {
	out: [dynamic]byte
	out.allocator = context.temp_allocator
	for _ in 0 ..< harness.integer_in(src, 0, 8) {
		if len(out) > 0 && harness.boolean(src) {
			from := harness.integer_in(src, 0, len(out))
			n := harness.integer_in(src, 0, len(out) - from + 1)
			for i in 0 ..< n {
				append(&out, out[from + i])
			}
		} else {
			append(&out, ..harness.bytes(src, max / 8, context.temp_allocator))
		}
	}
	return out[:]
}

// edited is old with pieces replaced, inserted and dropped.
edited :: proc(src: ^harness.Source, old: []byte) -> []byte {
	out: [dynamic]byte
	out.allocator = context.temp_allocator
	at := 0
	for at < len(old) {
		n := harness.integer_in(src, 1, len(old) - at + 1)
		switch harness.integer_in(src, 0, 4) {
		case 0:
			append(&out, ..harness.bytes(src, 64, context.temp_allocator))
		case 1:
		case:
			append(&out, ..old[at:at + n])
		}
		at += n
	}
	return out[:]
}

pack :: proc(input: []byte, level: int) -> ([]byte, zstd.Error) {
	r: bytes.Reader
	bytes.reader_init(&r, input)
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	err := zstd.compress_stream(bytes.buffer_to_stream(&out), bytes.reader_to_stream(&r), {level = level})
	return bytes.buffer_to_bytes(&out), err
}

unpack :: proc(input: []byte, prefix: []byte = nil) -> ([]byte, zstd.Error) {
	r: bytes.Reader
	bytes.reader_init(&r, input)
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	err := zstd.decompress_stream(bytes.buffer_to_stream(&out), bytes.reader_to_stream(&r), {prefix = prefix})
	return bytes.buffer_to_bytes(&out), err
}

make_patch :: proc(old, new: []byte, level: int) -> ([]byte, zstd.Error) {
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	err := zstd.diff(bytes.buffer_to_stream(&out), old, new, level)
	return bytes.buffer_to_bytes(&out), err
}

round_trip :: proc(_: Subject, src: ^harness.Source) -> (detail: string, ok: bool) {
	input := data(src, 256 * 1024)
	level := harness.choice(src, LEVELS)
	packed, err := pack(input, level)
	if err != nil {
		return fmt.tprintf("compress at level %d: %v", level, err), false
	}
	out, uerr := unpack(packed)
	if uerr != nil {
		return fmt.tprintf("decompress of %d bytes: %v", len(input), uerr), false
	}
	if !bytes.equal(out, input) {
		return fmt.tprintf("%d bytes in, %d different bytes out", len(input), len(out)), false
	}
	return "", true
}

patch_round_trip :: proc(_: Subject, src: ^harness.Source) -> (detail: string, ok: bool) {
	old := data(src, 128 * 1024)
	new := edited(src, old)
	p, err := make_patch(old, new, harness.choice(src, LEVELS))
	if err != nil {
		return fmt.tprintf("diff: %v", err), false
	}
	out, perr := unpack(p, old)
	if perr != nil {
		return fmt.tprintf("patch of %d bytes to %d: %v", len(old), len(new), perr), false
	}
	if !bytes.equal(out, new) {
		return fmt.tprintf("patch gave %d bytes, wanted %d", len(out), len(new)), false
	}
	return "", true
}

damaged_frame :: proc(_: Subject, src: ^harness.Source) -> (detail: string, ok: bool) {
	input := data(src, 16 * 1024)
	packed, _ := pack(input, harness.choice(src, LEVELS))
	corpus := [][]byte{packed}
	broken, how := harness.damage(src, corpus[:], context.temp_allocator)
	out, err := unpack(broken)
	if how == .None && err != nil {
		return fmt.tprintf("an undamaged frame failed: %v", err), false
	}
	if err == nil && !bytes.equal(out, input) {
		return fmt.tprintf("%v damage decoded to other bytes without an error", how), false
	}
	return "", true
}

damaged_patch :: proc(_: Subject, src: ^harness.Source) -> (detail: string, ok: bool) {
	old := data(src, 16 * 1024)
	new := edited(src, old)
	a, _ := make_patch(old, new, 1)
	b, _ := make_patch(old, new, 9)
	corpus := [][]byte{a, b}
	broken, how := harness.damage(src, corpus[:], context.temp_allocator)
	out, err := unpack(broken, old)
	if how == .None && err != nil {
		return fmt.tprintf("an undamaged patch failed: %v", err), false
	}
	if err == nil && !bytes.equal(out, new) {
		return fmt.tprintf("%v damage decoded to other bytes without an error", how), false
	}
	return "", true
}
