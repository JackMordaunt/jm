/*
hot-watch rebuilds a jm:ui subprocess child whenever its .odin source
changes, and republishes wherever the new build landed through a pointer
file: ui/sdl.run_host's Host_App.watch re-reads exactly that file every
poll. Every build goes to its own timestamped path under the pointer
file's directory, never overwriting one that might still be running (see
ui/sdl/host.odin for the one running exe this was tested against, on
Windows) — sidestepping whatever that turns out to mean for a build
writing to the same path instead.

	hot-watch examples/hot-architecture/child build/debug/hot-architecture.watch
	hot-watch examples/material-kitchen/child build/debug/material-kitchen.watch ui ui/material

Any further directories are watched too (each flat, like the source
dir), so a child rebuilds when a jm:ui package it imports changes, not
only when its own main.odin does.

-host SRC OUT also rebuilds the host, SRC, to OUT whenever one of those
further directories changes, before the child: a host built before a
change to jm:ui's sc encoding cannot read the new child, and on seeing
that, ui/sdl's host restarts itself from OUT. It builds beside OUT and
renames over it, so the running host's image is untouched. Not on
Windows, which will not rename over a running executable.

	hot-watch examples/material-kitchen/child build/debug/material-kitchen.watch -host examples/material-kitchen/host build/debug/material-kitchen-host ui ui/material

-release builds the child, and the host, with -o:speed instead of -debug.

Run from the repo root, same as `just`: it passes that as -collection:jm
to the odin build it shells out to.
*/
package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "jm:sh"

POLL :: 400 * time.Millisecond

main :: proc() {
	if len(os.args) < 3 {
		fmt.eprintln("usage: hot-watch <source-dir> <pointer-file> [-release] [-host <host-dir> <host-out>] [extra-dir...]")
		os.exit(2)
	}
	src_dir := os.args[1]
	pointer := os.args[2]
	dirs := make([dynamic]string)
	append(&dirs, src_dir)
	host_src, host_out: string
	opt := "-debug"
	rest := os.args[3:]
	for i := 0; i < len(rest); i += 1 {
		if rest[i] == "-host" && i + 2 < len(rest) {
			host_src, host_out = rest[i + 1], rest[i + 2]
			i += 2
			continue
		}
		if rest[i] == "-release" {
			opt = "-o:speed"
			continue
		}
		append(&dirs, rest[i])
	}
	root, rerr := os.getwd(context.allocator)
	if rerr != nil {
		fmt.eprintln("hot-watch: getwd:", rerr)
		os.exit(1)
	}
	out_dir := filepath.dir(pointer)
	os.make_directory(out_dir) // ignore: usually already exists
	// examples/x/child builds as x-child, not a bare child shared by every
	// example.
	trimmed := strings.trim_right(src_dir, "/\\")
	base := filepath.base(trimmed)
	if parent := filepath.base(filepath.dir(trimmed)); parent != "." && parent != "" {
		base = fmt.aprintf("%s-%s", parent, base)
	}
	// Blend2D is C++: on unix a child that renders needs libstdc++, as the
	// justfile's cxx_link passes, and as that variable, only off Windows.
	link := "" when ODIN_OS == .Windows else ` -extra-linker-flags:"-lstdc++"`
	exe_suffix := ".exe" when ODIN_OS == .Windows else ""

	fmt.printfln("hot-watch: watching %v for .odin changes", dirs[:])
	last, last_shared: time.Time
	for {
		mt, shared: time.Time
		ok := false
		for d, i in dirs {
			dmt, dok := newest_odin_mtime(d)
			if !dok {
				continue
			}
			if !ok || time.diff(mt, dmt) > 0 {
				mt, ok = dmt, true
			}
			if i > 0 && time.diff(shared, dmt) > 0 {
				shared = dmt // the newest change outside the child's own dir
			}
		}
		if ok && time.diff(last, mt) > 0 {
			if host_src != "" && time.diff(last_shared, shared) > 0 && last_shared != {} {
				build_host(host_src, host_out, root, opt, link)
			}
			last, last_shared = mt, shared
			out := fmt.tprintf("%s/%s-%d%s", out_dir, base, time.to_unix_nanoseconds(time.now()), exe_suffix)
			fmt.printfln("hot-watch: building %s -> %s", src_dir, out)
			cmd := fmt.tprintf("odin build %s %s -collection:jm=%s%s -out:%s", src_dir, opt, root, link, out)
			code, sok := sh.run(cmd)
			if !sok {
				fmt.eprintfln("hot-watch: build failed (exit %d)", code)
			} else if werr := os.write_entire_file(pointer, out); werr != nil {
				fmt.eprintln("hot-watch: pointer write:", werr)
			} else {
				fmt.printfln("hot-watch: ready: %s", out)
			}
		}
		time.sleep(POLL)
	}
}

// build_host rebuilds the host in src to out, beside it then renamed over
// it, so a host running from out keeps its image until it restarts.
build_host :: proc(src, out, root, opt, link: string) {
	when ODIN_OS == .Windows {
		fmt.eprintln("hot-watch: -host: Windows cannot replace a running host; rebuild it by hand")
	} else {
		tmp := fmt.tprintf("%s.new", out)
		fmt.printfln("hot-watch: building host %s -> %s", src, out)
		code, ok := sh.run(fmt.tprintf("odin build %s %s -collection:jm=%s%s -out:%s", src, opt, root, link, tmp))
		if !ok {
			fmt.eprintfln("hot-watch: host build failed (exit %d)", code)
			return
		}
		if err := os.rename(tmp, out); err != nil {
			fmt.eprintln("hot-watch: host rename:", err)
		}
	}
}

// newest_odin_mtime is the latest modification time among dir's own
// .odin files — not a recursive walk: examples/hot-counter/child and
// examples/hot-architecture/child, the two this was built against, are
// each one flat directory.
newest_odin_mtime :: proc(dir: string) -> (mt: time.Time, ok: bool) {
	f, err := os.open(dir)
	if err != nil {
		return {}, false
	}
	defer os.close(f)
	entries, derr := os.read_dir(f, -1, context.temp_allocator)
	if derr != nil {
		return {}, false
	}
	found := false
	for e in entries {
		if e.type != .Regular || !strings.has_suffix(e.name, ".odin") {
			continue
		}
		if !found || time.diff(mt, e.modification_time) > 0 {
			mt = e.modification_time
			found = true
		}
	}
	return mt, found
}
