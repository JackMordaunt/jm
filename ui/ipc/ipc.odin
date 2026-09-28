/*
Package ipc is the generic transport underneath the hot-reload host/
subprocess split: length-prefixed frames over a file (a pipe, in practice),
and spawning a child process wired up for exactly that. It knows nothing
about ui, Ops or Raw_Event — those are ui/wire's job — so it is exercised
by round-tripping frames through an OS pipe, not by anything ui-specific.

	c, ok := ipc.spawn({child_exe_path})
	ipc.write_frame(c.stdin, payload)          // host -> child
	reply, ok := ipc.read_frame(c.stdout, allocator) // child -> host
	...
	ipc.kill(&c)

A subprocess built with ui/child reads its request the same way, from its
own os.stdin, and replies on its own os.stdout.
*/
package ipc

import "core:encoding/endian"
import "core:os"
import "core:path/filepath"
import "core:slice"
import "core:strings"

// MAX_FRAME is the largest length a frame's prefix may claim: past this, a
// read is refused rather than trusting a corrupt or hostile length into an
// allocation. 64 MiB is far past any one frame this protocol sends.
MAX_FRAME :: 64 * 1024 * 1024

// write_frame writes payload as one length-prefixed frame: a little-endian
// u32 byte count, then the bytes, retrying short writes until the file is
// closed or errors. It reports whether the whole frame went out.
write_frame :: proc(f: ^os.File, payload: []byte) -> bool {
	if len(payload) > MAX_FRAME {
		return false
	}
	head: [4]byte
	endian.put_u32(head[:], .Little, u32(len(payload)))
	return write_all(f, head[:]) && write_all(f, payload)
}

// read_frame reads one length-prefixed frame written by write_frame, into
// a slice from allocator. False on EOF (the other end closed, whether
// between frames or mid-frame), a length over MAX_FRAME, or any other
// read error.
read_frame :: proc(f: ^os.File, allocator := context.allocator) -> (payload: []byte, ok: bool) {
	head: [4]byte
	if !read_all(f, head[:]) {
		return nil, false
	}
	n, _ := endian.get_u32(head[:], .Little)
	if n > MAX_FRAME {
		return nil, false
	}
	buf := make([]byte, n, allocator)
	if !read_all(f, buf) {
		return nil, false
	}
	return buf, true
}

@(private = "file")
write_all :: proc(f: ^os.File, data: []byte) -> bool {
	data := data
	for len(data) > 0 {
		n, err := os.write(f, data)
		if err != nil || n <= 0 {
			return false
		}
		data = data[n:]
	}
	return true
}

@(private = "file")
read_all :: proc(f: ^os.File, buf: []byte) -> bool {
	buf := buf
	for len(buf) > 0 {
		n, err := os.read(f, buf)
		if err != nil || n <= 0 {
			return false
		}
		buf = buf[n:]
	}
	return true
}

// Child is a spawned process wired for write_frame(c.stdin, ...) /
// read_frame(c.stdout, ...): its stdin and stdout are pipes this side
// holds the other end of. Its stderr is inherited, so a panic or an
// eprintln in the child reaches this process's own stderr.
Child :: struct {
	process: os.Process,
	stdin:   ^os.File, // write end; the child's stdin
	stdout:  ^os.File, // read end; the child's stdout
}

// spawn starts argv with stdin and stdout piped, stderr inherited. dir, if
// not "", is the child's working directory. argv[0] is resolved to an
// absolute path first if it names a path (contains a separator) rather
// than a bare command: ui/sdl/host_test.odin's own spawn call, run as
// build/test/ui-sdl.exe by odin test, saw a relative argv[0] that
// os.exists found fine still fail process_start on Windows with
// Not_Exist — resolving to an absolute path first sidesteps whatever
// that relative lookup was keying on.
spawn :: proc(argv: []string, dir: string = "") -> (c: Child, ok: bool) {
	in_r, in_w, err1 := os.pipe()
	if err1 != nil {
		return {}, false
	}
	out_r, out_w, err2 := os.pipe()
	if err2 != nil {
		os.close(in_r)
		os.close(in_w)
		return {}, false
	}

	argv := argv
	if len(argv) > 0 && strings.contains_any(argv[0], filepath.SEPARATOR_CHARS) && !filepath.is_abs(argv[0]) {
		if resolved, err := filepath.abs(argv[0], context.temp_allocator); err == nil {
			argv = slice.clone(argv, context.temp_allocator)
			argv[0] = resolved
		}
	}

	desc := os.Process_Desc {
		working_dir = dir,
		command     = argv,
		stdin       = in_r,
		stdout      = out_w,
		stderr      = os.stderr,
	}
	process, err3 := os.process_start(desc)
	// Whatever happens, the ends handed to the child are this side's to
	// close: keeping them open would stop the child's own close of its
	// stdin/stdout from ever reaching us as EOF.
	os.close(in_r)
	os.close(out_w)
	if err3 != nil {
		os.close(in_w)
		os.close(out_r)
		return {}, false
	}
	return {process = process, stdin = in_w, stdout = out_r}, true
}

// kill forces c's process to exit and closes the pipe ends this side held.
kill :: proc(c: ^Child) {
	// A zero Child (never spawned, or already killed or waited on) has pid
	// 0, and per kill(2) pid 0 signals every process in the caller's
	// process group, the caller included.
	if c.process.pid == 0 {
		return
	}
	_ = os.process_kill(c.process)
	_, _ = os.process_wait(c.process)
	os.close(c.stdin)
	os.close(c.stdout)
	c^ = {}
}

// wait blocks until c's process exits on its own, then closes the pipe
// ends this side held.
wait :: proc(c: ^Child) -> os.Process_State {
	state, _ := os.process_wait(c.process)
	os.close(c.stdin)
	os.close(c.stdout)
	c^ = {}
	return state
}
