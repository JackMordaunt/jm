// mkpatch writes the optional files jm:selfupdate looks for beside a release
// asset: the asset compressed with zstd, and a patch to it from each earlier
// build given. CI runs it after the build and before sha256sums.txt is
// written and signed, so the signature covers what it makes.
//
//	mkpatch -new build/tool-linux-amd64 -out dist \
//	    -old prev/v1.2.0/tool-linux-amd64 -old prev/v1.1.0/tool-linux-amd64
//
// It writes dist/tool-linux-amd64.zst and, per -old, the patch named for
// that build's sha256, printing one line per file. A patch is skipped when
// it is no smaller than half the compressed asset, since then it saves
// little over the next route, and when the old build is the new one. Old
// builds must be the published files, not rebuilds: builds are not
// reproducible, and a patch applies only to the exact bytes it was made from.
package main

import "core:bytes"
import "core:crypto/hash"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:path/filepath"

import "jm:selfupdate"
import "jm:zstd"

USAGE :: "usage: mkpatch -new <asset> -out <dir> [-old <earlier asset>]..."

main :: proc() {
	new_path, out_dir: string
	olds: [dynamic]string
	args := os.args[1:]
	for i := 0; i < len(args); i += 1 {
		flag := args[i]
		if flag != "-new" && flag != "-out" && flag != "-old" {
			fmt.eprintfln("mkpatch: unknown flag %s\n%s", flag, USAGE)
			os.exit(2)
		}
		i += 1
		if i >= len(args) {
			fmt.eprintfln("mkpatch: %s needs a value\n%s", flag, USAGE)
			os.exit(2)
		}
		switch flag {
		case "-new":
			new_path = args[i]
		case "-out":
			out_dir = args[i]
		case "-old":
			append(&olds, args[i])
		}
	}
	if new_path == "" || out_dir == "" {
		fmt.eprintln(USAGE)
		os.exit(2)
	}
	if !make_files(new_path, olds[:], out_dir) {
		os.exit(1)
	}
}

// make_files writes the compressed asset and the patches, reporting each
// file or failure on the standard streams.
make_files :: proc(new_path: string, olds: []string, out_dir: string) -> bool {
	new, err := os.read_entire_file(new_path, context.allocator)
	if err != nil {
		fmt.eprintfln("mkpatch: cannot read %s: %v", new_path, err)
		return false
	}
	defer delete(new)
	asset := filepath.base(new_path)
	if mk_err := os.make_directory_all(out_dir); mk_err != nil && mk_err != .Exist {
		fmt.eprintfln("mkpatch: cannot create %s: %v", out_dir, mk_err)
		return false
	}

	buf := make([]byte, zstd.compress_bound(len(new)))
	defer delete(buf)
	packed, zerr := zstd.compress(buf, new, {level = zstd.DIFF_LEVEL})
	if zerr != nil {
		fmt.eprintfln("mkpatch: cannot compress %s: %v", new_path, zerr)
		return false
	}
	zst := fmt.tprintf("%s%s", asset, selfupdate.ZST_EXT)
	if !write(out_dir, zst, packed) {
		return false
	}
	fmt.printfln("%s  %d bytes, from %d", zst, len(packed), len(new))

	new_hex := sha256_hex(new)
	ok := true
	for old_path in olds {
		ok = make_patch(new, new_hex, asset, old_path, out_dir, len(packed)) && ok
	}
	return ok
}

// make_patch writes the patch from the build at old_path to new, unless it
// would not pay for itself.
make_patch :: proc(new: []byte, new_hex, asset, old_path, out_dir: string, packed_len: int) -> bool {
	old, err := os.read_entire_file(old_path, context.allocator)
	if err != nil {
		fmt.eprintfln("mkpatch: cannot read %s: %v", old_path, err)
		return false
	}
	defer delete(old)
	old_hex := sha256_hex(old)
	if old_hex == new_hex {
		fmt.printfln("skip %s: the same build as %s", old_path, asset)
		return true
	}
	out: bytes.Buffer
	defer bytes.buffer_destroy(&out)
	if derr := zstd.diff(bytes.buffer_to_stream(&out), old, new); derr != nil {
		fmt.eprintfln("mkpatch: cannot diff %s: %v", old_path, derr)
		return false
	}
	p := bytes.buffer_to_bytes(&out)
	if 2 * len(p) >= packed_len {
		fmt.printfln("skip %s: patch of %d bytes against %d compressed", old_path, len(p), packed_len)
		return true
	}
	name_buf: [selfupdate.PATH_CAP]byte
	name := selfupdate.patch_name(name_buf[:], asset, old_hex)
	if !write(out_dir, name, p) {
		return false
	}
	fmt.printfln("%s  %d bytes, from %s", name, len(p), old_path)
	return true
}

write :: proc(dir, name: string, data: []byte) -> bool {
	p, _ := filepath.join({dir, name}, context.temp_allocator)
	if err := os.write_entire_file(p, data); err != nil {
		fmt.eprintfln("mkpatch: cannot write %s: %v", p, err)
		return false
	}
	return true
}

sha256_hex :: proc(data: []byte) -> string {
	digest := hash.hash_bytes(.SHA256, data, context.temp_allocator)
	return string(hex.encode(digest, context.temp_allocator))
}
