// patch writes and applies jm:selfupdate binary patches, so a release
// workflow can publish the difference between a build and the ones that
// came before it.
//
//	patch make <old> <new> <out>     write the raw patch from old to new
//	patch apply <old> <patch> <out>  rebuild new from old and the patch
//	patch check <old> <patch> <new>  exit 0 when the patch rebuilds new
//
// make writes the raw form and prints the three sizes and the ratio; a
// release wraps it (`"JMPZ" + zlib`), which apply and check both read, so
// check is what verifies the published artifact. apply and check exit
// non-zero when the patch does not fit the old file or its result fails
// its own hash.
package main

import "core:fmt"
import "core:os"

import "jm:selfupdate"

main :: proc() {
	if len(os.args) != 5 || (os.args[1] != "make" && os.args[1] != "apply" && os.args[1] != "check") {
		fmt.eprintln("usage: patch make <old> <new> <out> | patch apply <old> <patch> <out> | patch check <old> <patch> <new>")
		os.exit(2)
	}
	a := must_read(os.args[2])
	b := must_read(os.args[3])
	switch os.args[1] {
	case "make":
		p := selfupdate.diff(a, b)
		if _, ok := selfupdate.apply(a, p); !ok {
			fmt.eprintln("patch: the patch does not reproduce the new file")
			os.exit(1)
		}
		must_write(os.args[4], p)
		fmt.printf("old %d  new %d  patch %d  (%.1f%% of new)\n", len(a), len(b), len(p), 100 * f64(len(p)) / f64(max(1, len(b))))
	case "apply":
		out, ok := selfupdate.apply(a, b)
		if !ok {
			fmt.eprintln("patch: does not apply to this old file")
			os.exit(1)
		}
		must_write(os.args[4], out)
		fmt.printf("wrote %s (%d bytes)\n", os.args[4], len(out))
	case "check":
		out, ok := selfupdate.apply(a, b)
		want := must_read(os.args[4])
		if !ok || string(out) != string(want) {
			fmt.eprintfln("patch: %s does not rebuild %s from %s", os.args[3], os.args[4], os.args[2])
			os.exit(1)
		}
		fmt.printf("ok %s rebuilds %s (%d bytes from a %d byte patch)\n", os.args[3], os.args[4], len(out), len(b))
	}
}

must_read :: proc(p: string) -> []byte {
	data, err := os.read_entire_file_from_path(p, context.allocator)
	if err != nil {
		fmt.eprintfln("patch: cannot read %s: %v", p, err)
		os.exit(1)
	}
	return data
}

must_write :: proc(p: string, data: []byte) {
	if err := os.write_entire_file(p, data); err != nil {
		fmt.eprintfln("patch: cannot write %s: %v", p, err)
		os.exit(1)
	}
}
