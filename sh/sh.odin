/*
Package sh runs external commands tersely.

Two entry styles. A shell string goes through the platform shell, so pipes,
globs and redirects work:

	rev  := must(sh.out("git rev-parse HEAD"))
	files := must(sh.lines("ls *.odin"))
	if !sh.ok("test -d build") { ... }
	sh.run("just build")   // inherits the terminal; returns the exit code

An argv slice bypasses the shell, so arguments need no quoting:

	r := sh.exec({"git", "log", "-1", "--format=%s", subject})
	if !r.ok { die("%s", sh.error(r)) }

The shell is /bin/sh on Unix and cmd.exe on Windows unless Opts.shell says
otherwise. Cmd's quoting differs from sh; scripts that must run on both
either use the argv form or ask for Shell.Pwsh, which behaves the same on all
three wherever PowerShell 7 is installed.
*/
package sh

import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

Result :: struct {
	// The command as the caller gave it; a joined argv for the exec forms.
	cmd:       string,
	stdout:    string,
	stderr:    string,
	// Exit code, or the signal number when the process was killed on Unix.
	code:      int,
	// Started, exited normally, and returned 0.
	ok:        bool,
	// Set when the process could not be started at all.
	err:       os.Error,
	// Set when the process ran past Opts.timeout and was killed; what it
	// wrote before then is kept.
	timed_out: bool,
}

Shell :: enum {
	Default, // sh on Unix, cmd.exe on Windows
	Sh,
	Cmd,
	Pwsh,
}

Opts :: struct {
	// Working directory; "" keeps the current one.
	dir:     string,
	// Full environment as KEY=VALUE; nil inherits the parent's.
	env:     []string,
	// Fed to the child's stdin; "" closes stdin.
	stdin:   string,
	shell:   Shell,
	// How long the child may run before it is killed; 0 is no limit. Only
	// the capturing forms honour it.
	timeout: time.Duration,
}

// capture runs cmd through the shell and returns everything it produced.
capture :: proc(cmd: string, opts := Opts{}, allocator := context.allocator) -> Result {
	argv := shell_argv(cmd, opts.shell, context.temp_allocator)
	r := exec(argv, opts, allocator)
	r.cmd = cmd
	return r
}

// out runs cmd and returns its stdout with trailing whitespace removed.
out :: proc(
	cmd: string,
	opts := Opts{},
	allocator := context.allocator,
) -> (
	s: string,
	success: bool,
) {
	r := capture(cmd, opts, allocator)
	return strings.trim_right_space(r.stdout), r.ok
}

// lines runs cmd and returns its stdout split into lines, without a trailing
// empty line.
lines :: proc(
	cmd: string,
	opts := Opts{},
	allocator := context.allocator,
) -> (
	result: []string,
	success: bool,
) {
	r := capture(cmd, opts, allocator)
	return split_lines(r.stdout, allocator), r.ok
}

// ok runs cmd and reports whether it exited with 0. Output is discarded.
ok :: proc(cmd: string, opts := Opts{}) -> bool {
	return capture(cmd, opts, context.temp_allocator).ok
}

// run runs cmd with the terminal attached, so the user sees its output live.
run :: proc(cmd: string, opts := Opts{}) -> (code: int, success: bool) {
	argv := shell_argv(cmd, opts.shell, context.temp_allocator)
	return exec_run(argv, opts)
}

// exec runs argv directly and captures stdout and stderr.
exec :: proc(argv: []string, opts := Opts{}, allocator := context.allocator) -> (r: Result) {
	r.cmd = strings.join(argv, " ", allocator)
	desc := os.Process_Desc {
		working_dir = opts.dir,
		command     = argv,
		env         = opts.env,
	}
	stdin, stdin_path := stdin_file(opts.stdin)
	defer cleanup_stdin(stdin, stdin_path)
	desc.stdin = stdin

	state, stdout, stderr, timed_out, err := capture_process(desc, opts.timeout, allocator)
	if err != nil {
		r.err = err
		r.code = -1
		r.stderr = os.error_string(err)
		return
	}
	r.stdout = string(stdout)
	r.stderr = string(stderr)
	r.code = state.exit_code
	r.timed_out = timed_out
	r.ok = !timed_out && state.exited && state.success && state.exit_code == 0
	return
}

// capture_process runs the process with both streams captured, as
// os.process_exec does, and kills it when it runs past the timeout. What
// the child wrote before then is returned with the state.
capture_process :: proc(
	desc: os.Process_Desc,
	timeout: time.Duration,
	allocator := context.allocator,
) -> (
	state: os.Process_State,
	stdout, stderr: []byte,
	timed_out: bool,
	err: os.Error,
) {
	stdout_r, stdout_w := os.pipe() or_return
	defer os.close(stdout_r)
	stderr_r, stderr_w := os.pipe() or_return
	defer os.close(stderr_r)

	process: os.Process
	{
		// The write ends are closed on this side whatever happens, so the
		// read ends see EOF once the child is done.
		defer os.close(stdout_w)
		defer os.close(stderr_w)
		child := desc
		child.stdout = stdout_w
		child.stderr = stderr_w
		process = os.process_start(child) or_return
	}

	out := make([dynamic]byte, allocator)
	errs := make([dynamic]byte, allocator)
	buf: [4096]u8 = ---
	started := time.now()
	stdout_done, stderr_done := false, false
	for err == nil && (!stdout_done || !stderr_done) {
		moved := false
		if !stdout_done {
			has_data, herr := os.pipe_has_data(stdout_r)
			err = herr
			n := 0
			if err == nil && has_data {
				n, err = os.read(stdout_r, buf[:])
				moved = n > 0
			}
			switch err {
			case nil:
				append(&out, ..buf[:n])
			case .EOF, .Broken_Pipe:
				stdout_done = true
				err = nil
			}
		}
		if err == nil && !stderr_done {
			has_data, herr := os.pipe_has_data(stderr_r)
			err = herr
			n := 0
			if err == nil && has_data {
				n, err = os.read(stderr_r, buf[:])
				moved = moved || n > 0
			}
			switch err {
			case nil:
				append(&errs, ..buf[:n])
			case .EOF, .Broken_Pipe:
				stderr_done = true
				err = nil
			}
		}
		if timeout > 0 && time.since(started) > timeout {
			_ = os.process_kill(process)
			timed_out = true
			break
		}
		if !moved {
			// Nothing to read yet: yield rather than spin.
			time.sleep(time.Millisecond)
		}
	}
	stdout, stderr = out[:], errs[:]
	if err != nil {
		state, _ = os.process_wait(process, timeout = 0)
		if !state.exited {
			_ = os.process_kill(process)
			state, _ = os.process_wait(process)
		}
		return
	}
	state, err = os.process_wait(process)
	return
}

// exec_run runs argv with the terminal attached.
exec_run :: proc(argv: []string, opts := Opts{}) -> (code: int, success: bool) {
	desc := os.Process_Desc {
		working_dir = opts.dir,
		command     = argv,
		env         = opts.env,
		stdout      = os.stdout,
		stderr      = os.stderr,
		stdin       = os.stdin,
	}
	if opts.stdin != "" {
		stdin, stdin_path := stdin_file(opts.stdin)
		defer cleanup_stdin(stdin, stdin_path)
		desc.stdin = stdin
		return wait(desc)
	}
	return wait(desc)
}

// which finds name on PATH the way the shell would, honouring PATHEXT on
// Windows. A name containing a separator is checked as given.
which :: proc(name: string, allocator := context.allocator) -> (path: string, found: bool) {
	if strings.contains_any(name, filepath.SEPARATOR_CHARS) {
		if os.is_file(name) {
			return strings.clone(name, allocator), true
		}
		return "", false
	}
	path_env, has_path := os.lookup_env("PATH", context.temp_allocator)
	if !has_path {
		return "", false
	}
	for dir in strings.split_iterator(&path_env, LIST_SEPARATOR) {
		if dir == "" {
			continue
		}
		for ext in executable_extensions() {
			file := strings.concatenate({name, ext}, context.temp_allocator)
			candidate, _ := filepath.join({dir, file}, context.temp_allocator)
			if os.is_file(candidate) {
				return strings.clone(candidate, allocator), true
			}
		}
	}
	return "", false
}

// error renders a failed Result as one message: the command, the exit code,
// and whatever it wrote to stderr.
error :: proc(r: Result, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	if r.err != nil {
		strings.write_string(&b, "cannot start: ")
		strings.write_string(&b, r.cmd)
		strings.write_string(&b, ": ")
		strings.write_string(&b, os.error_string(r.err))
		return strings.to_string(b)
	}
	strings.write_string(&b, "command failed (exit ")
	strings.write_int(&b, r.code)
	strings.write_string(&b, "): ")
	strings.write_string(&b, r.cmd)
	stderr := strings.trim_right_space(r.stderr)
	if stderr != "" {
		strings.write_byte(&b, '\n')
		strings.write_string(&b, stderr)
	}
	return strings.to_string(b)
}

// ---- internals ----------------------------------------------------------

LIST_SEPARATOR :: ";" when ODIN_OS == .Windows else ":"

wait :: proc(desc: os.Process_Desc) -> (code: int, success: bool) {
	p, err := os.process_start(desc)
	if err != nil {
		return -1, false
	}
	state, werr := os.process_wait(p)
	if werr != nil {
		return -1, false
	}
	return state.exit_code, state.exited && state.success && state.exit_code == 0
}

// stdin_file spools text into a temp file and returns it opened for reading,
// so the child can consume more than a pipe buffer without deadlock.
stdin_file :: proc(text: string) -> (f: ^os.File, path: string) {
	if text == "" {
		return nil, ""
	}
	tmp, err := os.create_temp_file("", "sh-stdin-*", STDIN_FLAGS)
	if err != nil {
		return nil, ""
	}
	if _, werr := os.write_string(tmp, text); werr != nil {
		os.close(tmp)
		return nil, ""
	}
	if _, serr := os.seek(tmp, 0, .Start); serr != nil {
		os.close(tmp)
		return nil, ""
	}
	return tmp, strings.clone(os.name(tmp), context.temp_allocator)
}

cleanup_stdin :: proc(f: ^os.File, path: string) {
	if f == nil {
		return
	}
	os.close(f)
	if path != "" {
		os.remove(path)
	}
}

split_lines :: proc(s: string, allocator := context.allocator) -> []string {
	trimmed := strings.trim_right(s, "\r\n")
	if trimmed == "" {
		return nil
	}
	parts, _ := strings.split_lines(trimmed, allocator)
	for &p in parts {
		p = strings.trim_right(p, "\r")
	}
	return parts
}
