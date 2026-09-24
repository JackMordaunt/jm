/*
odin-run compiles a single-file Odin script once and runs the cached binary
on every call after that, so a script behaves like an interpreted one.

	#!/usr/bin/env odin-run
	package main
	...

	odin-run script.odin [args...]     compile if stale, then run
	odin-run -clean                    remove every cached binary

The cache key covers the script's bytes and path, every .odin file in the
collection (path, size, modification time), the odin binary itself, the
target, and the build flags. Binaries live under the user cache directory in
odin-run/<key>/.

Environment:
	ODIN                 odin binary; default: "odin" on PATH
	ODIN_RUN_COLLECTION  root of the jm collection; default: baked in at install
	ODIN_RUN_FLAGS       extra build flags, split on spaces, such as "-debug"
	ODIN_RUN_VERBOSE=1   print the build command and cache path to stderr (exactly "1")
*/
package main

import "core:fmt"
import "core:hash/xxhash"
import "core:os"
import "core:path/filepath"
import "core:strings"

import "jm:sh"

// The collection root baked in by `just install`; ODIN_RUN_COLLECTION wins.
JM_COLLECTION :: #config(JM_COLLECTION, "")

EXE :: ".exe" when ODIN_OS == .Windows else ""

main :: proc() {
	args := os.args[1:]
	if len(args) > 0 && args[0] == "--" {
		args = args[1:]
	}
	if len(args) == 0 || args[0] == "-h" || args[0] == "--help" {
		fmt.eprintln("usage: odin-run <script.odin> [args...] | odin-run -clean")
		os.exit(2)
	}
	if args[0] == "-clean" {
		root := cache_root()
		if err := os.remove_all(root); err != nil && err != os.General_Error.Not_Exist {
			fail("cannot remove %s: %v", root, err)
		}
		return
	}

	script := args[0]
	script_args := args[1:]
	verbose_flag, _ := os.lookup_env("ODIN_RUN_VERBOSE", context.temp_allocator)
	verbose := verbose_flag == "1"

	source, rerr := os.read_entire_file_from_path(script, context.allocator)
	if rerr != nil {
		fail("cannot read %s: %v", script, rerr)
	}
	abs_script, _ := filepath.abs(script)
	collection := collection_root()
	odin := odin_binary()
	flags := build_flags()

	key := cache_key(source, abs_script, collection, odin, flags)
	dir, _ := filepath.join({cache_root(), key})
	stem := filepath.stem(script)
	bin, _ := filepath.join({dir, strings.concatenate({stem, EXE})})

	if !os.is_file(bin) {
		if err := os.make_directory_all(dir); err != nil && err != os.General_Error.Exist {
			fail("cannot create %s: %v", dir, err)
		}
		argv := make([dynamic]string)
		append(&argv, odin, "build", abs_script, "-file")
		if collection != "" {
			append(&argv, strings.concatenate({"-collection:jm=", collection}))
		}
		append(&argv, strings.concatenate({"-out:", bin}))
		append(&argv, ..flags)
		if verbose {
			fmt.eprintln("odin-run: build:", strings.join(argv[:], " "))
		}
		code, ok := sh.exec_run(argv[:])
		if !ok {
			os.remove_all(dir)
			os.exit(code if code > 0 else 1)
		}
		copy_runtime_libraries(dir, odin)
	}
	if verbose {
		fmt.eprintln("odin-run: binary:", bin)
	}

	run := make([dynamic]string)
	append(&run, bin)
	append(&run, ..script_args)
	code, _ := sh.exec_run(run[:])
	os.exit(code)
}

cache_key :: proc(source: []byte, abs_script, collection, odin: string, flags: []string) -> string {
	b := strings.builder_make()
	strings.write_string(&b, abs_script)
	strings.write_byte(&b, 0)
	strings.write_string(&b, string(source))
	strings.write_byte(&b, 0)
	strings.write_string(&b, ODIN_OS_STRING)
	strings.write_string(&b, ODIN_ARCH_STRING)
	for f in flags {
		strings.write_string(&b, f)
		strings.write_byte(&b, 0)
	}
	write_stat(&b, odin)
	if collection != "" {
		w := os.walker_create(collection)
		defer os.walker_destroy(&w)
		for info in os.walker_walk(&w) {
			if info.type == .Directory && (info.name == ".git" || info.name == "build") {
				os.walker_skip_dir(&w)
				continue
			}
			if info.type == .Regular && filepath.ext(info.name) == ".odin" {
				strings.write_string(&b, info.fullpath)
				fmt.sbprintf(&b, ":%d:%d\x00", info.size, info.modification_time._nsec)
			}
		}
	}
	digest := xxhash.XXH3_64_default(b.buf[:])
	return fmt.aprintf("%016x", digest)
}

write_stat :: proc(b: ^strings.Builder, path: string) {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil {
		strings.write_string(b, path)
		return
	}
	fmt.sbprintf(b, "%s:%d:%d\x00", info.fullpath, info.size, info.modification_time._nsec)
}

cache_root :: proc() -> string {
	base, err := os.user_cache_dir(context.allocator)
	if err != nil {
		base, _ = os.temp_directory(context.allocator)
	}
	root, _ := filepath.join({base, "odin-run"})
	return root
}

collection_root :: proc() -> string {
	if v, found := os.lookup_env("ODIN_RUN_COLLECTION", context.allocator); found && v != "" {
		return v
	}
	return JM_COLLECTION
}

odin_binary :: proc() -> string {
	if v, found := os.lookup_env("ODIN", context.allocator); found && v != "" {
		return v
	}
	if p, found := sh.which("odin"); found {
		return p
	}
	fail("odin not found on PATH; set ODIN")
}

build_flags :: proc() -> []string {
	flags := make([dynamic]string)
	append(&flags, "-vet", "-strict-style")
	extra, found := os.lookup_env("ODIN_RUN_FLAGS", context.allocator)
	if found {
		append(&flags, ..strings.fields(extra))
	}
	optimised := true
	for f in flags {
		if f == "-debug" || strings.has_prefix(f, "-o:") {
			optimised = false
		}
	}
	if optimised {
		append(&flags, "-o:speed")
	}
	return flags[:]
}

// copy_runtime_libraries puts the DLLs a Windows binary needs beside it. The
// Windows branch of the foreign import in vendor/curl/curl.odin links
// lib/libcurl.lib, an import library, so libcurl.dll must be on the search path.
copy_runtime_libraries :: proc(dir, odin: string) {
	when ODIN_OS == .Windows {
		root, found := os.lookup_env("ODIN_ROOT", context.allocator)
		if !found || root == "" {
			root = filepath.dir(odin)
		}
		dll, _ := filepath.join({root, "vendor", "curl", "lib", "libcurl.dll"})
		if os.is_file(dll) {
			dest, _ := filepath.join({dir, "libcurl.dll"})
			os.copy_file(dest, dll)
		}
	}
}

fail :: proc(format: string, args: ..any) -> ! {
	fmt.eprint("odin-run: ")
	fmt.eprintfln(format, ..args)
	os.exit(1)
}
