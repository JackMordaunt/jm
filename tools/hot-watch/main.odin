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
	if len(os.args) != 3 {
		fmt.eprintln("usage: hot-watch <source-dir> <pointer-file>")
		os.exit(2)
	}
	src_dir := os.args[1]
	pointer := os.args[2]
	root, rerr := os.getwd(context.allocator)
	if rerr != nil {
		fmt.eprintln("hot-watch: getwd:", rerr)
		os.exit(1)
	}
	out_dir := filepath.dir(pointer)
	os.make_directory(out_dir) // ignore: usually already exists
	base := filepath.base(strings.trim_right(src_dir, "/\\"))
	exe_suffix := ".exe" when ODIN_OS == .Windows else ""

	fmt.printfln("hot-watch: watching %s for .odin changes", src_dir)
	last: time.Time
	for {
		mt, ok := newest_odin_mtime(src_dir)
		if ok && time.diff(last, mt) > 0 {
			last = mt
			out := fmt.tprintf("%s/%s-%d%s", out_dir, base, time.to_unix_nanoseconds(time.now()), exe_suffix)
			fmt.printfln("hot-watch: building %s -> %s", src_dir, out)
			cmd := fmt.tprintf("odin build %s -collection:jm=%s -out:%s", src_dir, root, out)
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
