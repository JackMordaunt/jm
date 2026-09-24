/*
Package prelude is the first import of every script.

	main :: proc() {
		context = prelude.init()
		cfg := must(os.read_entire_file_from_path("cfg.json", context.allocator))
		if len(cfg) == 0 {
			die("empty config")
		}
	}

init picks the allocator and the logger, opens the audit log, and returns the
context the script should run under. finish runs at the end of the caller's
scope through @(deferred_none), writes the exit line, and reports allocator
issues when the debug allocator is in use.

Allocation policy: a growing virtual arena is context.allocator. Scripts never
free; the process exit reclaims everything. Set Options.debug (or ODIN_DEBUG,
or the environment variable ODIN_SCRIPT_DEBUG=1) to swap in the debug
allocator from jfm:debug, which reports overflow, double free, and write after
free at exit.

Logging: one logfmt line per record in <log_dir>/<name>/<name>.log, plus a
human line on stderr for warning and above. die appends one line to
<log_dir>/deaths.log so every failed run across every script is auditable
from a single file. log_dir defaults to os.user_log_dir()/odin, which the
doc comments in core/os/user.odin place at:

	Linux:   ~/.local/state/odin
	macOS:   ~/Library/Logs/odin
	Windows: %LOCALAPPDATA%\odin

Nothing in this package writes to stdout; stdout belongs to the script's data.
*/
package prelude

import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:mem/virtual"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:time"

import "jfm:debug"

Options :: struct {
	// Program name used in log paths and lines. Default: basename of os.args[0].
	name:          string,
	// Use the debug allocator. Default: ODIN_DEBUG or ODIN_SCRIPT_DEBUG=1.
	debug:         Maybe(bool),
	// Print the debug allocator report even when it found no issues.
	report_clean:  bool,
	// Root of the log tree. Default: os.user_log_dir()/odin.
	log_dir:       string,
	// Skip the log file and deaths.log entirely; stderr only.
	no_log_file:   bool,
	// Lowest level echoed to stderr. Default: Warning, or ODIN_LOG=debug|info|warning|error.
	console_level: Maybe(log.Level),
	// Lowest level written to the log file. Default: Debug.
	file_level:    Maybe(log.Level),
	// Rotate the log file to .1 when it exceeds this many bytes. Default: 8 MiB.
	max_log_bytes: i64,
}

DEFAULT_MAX_LOG_BYTES :: 8 * 1024 * 1024

State :: struct {
	name:          string,
	arena:         virtual.Arena,
	dbg:           debug.Allocator,
	debugging:     bool,
	report_clean:  bool,
	allocator:     mem.Allocator, // what the script runs under
	internals:     mem.Allocator, // heap; owns everything in this struct
	log_file:      ^os.File,
	log_path:      string,
	deaths_path:   string,
	console_level: log.Level,
	file_level:    log.Level,
	started:       time.Tick,
	initialised:   bool,
	finished:      bool,
}

state: State

// init prepares the allocator and logger and returns the context to run under.
// Call it once at the top of main as `context = prelude.init()`. finish runs
// automatically when the calling scope ends.
@(deferred_none=finish)
init :: proc(opts := Options{}, loc := #caller_location) -> runtime.Context {
	assert(!state.initialised, "prelude.init called twice", loc)
	state.initialised = true
	state.internals = runtime.heap_allocator()
	state.started = time.tick_now()
	state.report_clean = opts.report_clean

	name := opts.name
	if name == "" {
		name = default_name(state.internals)
	}
	state.name = strings.clone(name, state.internals)

	state.debugging = opts.debug.? or_else (ODIN_DEBUG || env_truthy("ODIN_SCRIPT_DEBUG"))
	if state.debugging {
		debug.init(&state.dbg, state.internals, state.internals)
		state.allocator = debug.allocator(&state.dbg)
	} else {
		if err := virtual.arena_init_growing(&state.arena); err != nil {
			// No arena: fall back to the heap rather than fail before main starts.
			state.allocator = state.internals
		} else {
			state.allocator = virtual.arena_allocator(&state.arena)
		}
	}

	state.console_level = opts.console_level.? or_else console_level_from_env()
	state.file_level = opts.file_level.? or_else log.Level.Debug

	if !opts.no_log_file {
		open_log_file(opts)
	}
	platform_init()

	ctx := context
	ctx.allocator = state.allocator
	ctx.logger = log.Logger {
		procedure    = logger_proc,
		data         = &state,
		lowest_level = min(state.console_level, state.file_level),
		options      = {},
	}

	context = ctx
	log.debugf("event=start pid=%d cwd=%q args=%q", os.get_pid(), cwd(), args_string())
	return ctx
}

// finish writes the exit line and tears down. It runs on scope exit via the
// deferred attribute on init; exit and die call it explicitly.
finish :: proc() {
	finish_with_code(0)
}

// exit ends the script with code, writing the exit line first.
exit :: proc(code: int) -> ! {
	finish_with_code(code)
	os.exit(code)
}

// die logs a fatal message to the script log, stderr, and deaths.log, then
// exits with code 1.
die :: proc(format: string, args: ..any, loc := #caller_location) -> ! {
	msg := fmt.tprintf(format, ..args)
	if state.initialised {
		log.log(.Fatal, msg, location = loc)
		record_death(msg, loc)
	} else {
		fmt.eprintf("%s: fatal: %s\n", default_name(context.temp_allocator), msg)
	}
	exit(1)
}

// must unwraps a (value, ok) or (value, err) pair, or checks a bare ok or
// err, and dies with the call site when the check fails.
//
//	f := must(os.open(path))
//	n := must(strconv.parse_int(s))
//	must(os.make_directory_all(dir))
must :: proc {
	must_ok,
	must_err,
	must_bool,
	must_error,
}

@(require_results)
must_ok :: proc(v: $T, ok: bool, loc := #caller_location) -> T {
	if !ok {
		die("must: check failed", loc = loc)
	}
	return v
}

@(require_results)
must_err :: proc(v: $T, err: $E, loc := #caller_location) -> T where !intrinsics.type_is_boolean(E) {
	if failed(err) {
		die("must: %v", err, loc = loc)
	}
	return v
}

must_bool :: proc(ok: bool, loc := #caller_location) {
	if !ok {
		die("must: check failed", loc = loc)
	}
}

must_error :: proc(err: $E, loc := #caller_location) where !intrinsics.type_is_boolean(E) {
	if failed(err) {
		die("must: %v", err, loc = loc)
	}
}

// failed reports whether an error value of any common shape is set: a union
// (nil when clear), an enum (zero when clear), or a string (empty when clear).
failed :: proc(err: $E) -> bool {
	when intrinsics.type_is_union(E) {
		return err != nil
	} else when intrinsics.type_is_enum(E) {
		return err != E(0)
	} else when intrinsics.type_is_string(E) {
		return len(err) > 0
	} else when intrinsics.type_is_pointer(E) {
		return err != nil
	} else {
		#panic("prelude.must: unsupported error type")
	}
}

// env returns the environment variable or def when unset or empty.
env :: proc(key: string, def := "", allocator := context.allocator) -> string {
	v, found := os.lookup_env(key, allocator)
	if !found || v == "" {
		return def
	}
	return v
}

// args returns the script arguments without the program name.
args :: proc() -> []string {
	if len(os.args) == 0 {
		return nil
	}
	return os.args[1:]
}

// name returns the program name init settled on.
name :: proc() -> string {
	return state.name
}

// log_path returns the script's log file path, or "" when logging to a file is off.
log_path :: proc() -> string {
	return state.log_path
}

// ---- internals ----------------------------------------------------------

finish_with_code :: proc(code: int) {
	if !state.initialised || state.finished {
		return
	}
	state.finished = true
	dur := time.tick_since(state.started)
	log.debugf("event=exit code=%d dur=%v", code, dur)
	if state.log_file != nil {
		os.flush(state.log_file)
		os.close(state.log_file)
		state.log_file = nil
	}
	if state.debugging {
		if debug.issue_count(&state.dbg) > 0 || state.report_clean {
			debug.report(&state.dbg)
		}
		debug.destroy(&state.dbg)
	}
}

default_name :: proc(allocator: mem.Allocator) -> string {
	if len(os.args) == 0 {
		return "odin-script"
	}
	stem := filepath.stem(os.args[0])
	return strings.clone(stem, allocator)
}

env_truthy :: proc(key: string) -> bool {
	v, found := os.lookup_env(key, context.temp_allocator)
	if !found {
		return false
	}
	switch strings.to_lower(v, context.temp_allocator) {
	case "1", "true", "yes", "on":
		return true
	}
	return false
}

console_level_from_env :: proc() -> log.Level {
	v, found := os.lookup_env("ODIN_LOG", context.temp_allocator)
	if !found {
		return .Warning
	}
	switch strings.to_lower(v, context.temp_allocator) {
	case "debug":
		return .Debug
	case "info":
		return .Info
	case "warn", "warning":
		return .Warning
	case "error":
		return .Error
	case "fatal":
		return .Fatal
	}
	return .Warning
}

open_log_file :: proc(opts: Options) {
	root := opts.log_dir
	if root == "" {
		base, err := os.user_log_dir(context.temp_allocator)
		if err != nil {
			fmt.eprintf("%s: warning: no log directory: %v\n", state.name, err)
			return
		}
		root = join(base, "odin")
	}
	dir := join(root, state.name)
	if err := os.make_directory_all(dir); err != nil && !(err == os.General_Error.Exist && os.is_dir(dir)) {
		fmt.eprintf("%s: warning: cannot create %s: %v\n", state.name, dir, err)
		return
	}
	file_name := strings.concatenate({state.name, ".log"}, context.temp_allocator)
	state.log_path = join(dir, file_name, state.internals)
	state.deaths_path = join(root, "deaths.log", state.internals)

	max_bytes := opts.max_log_bytes
	if max_bytes <= 0 {
		max_bytes = DEFAULT_MAX_LOG_BYTES
	}
	rotate(state.log_path, max_bytes)

	f, err := os.open(state.log_path, {.Write, .Append, .Create}, LOG_PERMISSIONS)
	if err != nil {
		fmt.eprintf("%s: warning: cannot open %s: %v\n", state.name, state.log_path, err)
		return
	}
	state.log_file = f
}

LOG_PERMISSIONS :: os.Permissions_Read_All + {.Write_User}

// rotate moves path to path.1 when it exceeds max_bytes. os.rename replaces an
// existing target on every platform (core:os uses MOVEFILE_REPLACE_EXISTING on
// Windows), so the previous .1 needs no separate removal.
rotate :: proc(path: string, max_bytes: i64) {
	info, err := os.stat(path, context.temp_allocator)
	if err != nil || info.size <= max_bytes {
		return
	}
	old := strings.concatenate({path, ".1"}, context.temp_allocator)
	os.rename(path, old)
}

record_death :: proc(msg: string, loc: runtime.Source_Code_Location) {
	if state.deaths_path == "" {
		return
	}
	f, err := os.open(state.deaths_path, {.Write, .Append, .Create}, LOG_PERMISSIONS)
	if err != nil {
		return
	}
	defer os.close(f)
	b := strings.builder_make(context.temp_allocator)
	write_logfmt_line(&b, .Fatal, msg, loc)
	os.write_string(f, strings.to_string(b))
}

logger_proc :: proc(data: rawptr, level: log.Level, text: string, options: log.Options, location := #caller_location) {
	st := (^State)(data)
	if st.log_file != nil && level >= st.file_level {
		b := strings.builder_make(context.temp_allocator)
		write_logfmt_line(&b, level, text, location)
		os.write_string(st.log_file, strings.to_string(b))
	}
	if level >= st.console_level {
		if level >= .Error {
			fmt.eprintf("%s: %s: %s:%d: %s\n", st.name, level_name(level), filepath.base(location.file_path), location.line, text)
		} else {
			fmt.eprintf("%s: %s: %s\n", st.name, level_name(level), text)
		}
	}
}

write_logfmt_line :: proc(b: ^strings.Builder, level: log.Level, text: string, loc: runtime.Source_Code_Location) {
	stamp, _ := time.time_to_rfc3339(time.now(), 0, false, context.temp_allocator)
	fmt.sbprintf(b, "t=%s lvl=%s prog=%s loc=%s:%d ", stamp, level_name(level), state.name, filepath.base(loc.file_path), loc.line)
	// Text that is already logfmt (event=... from this package) goes through as is.
	if strings.has_prefix(text, "event=") {
		strings.write_string(b, text)
	} else {
		strings.write_string(b, "msg=")
		write_quoted(b, text)
	}
	strings.write_byte(b, '\n')
}

write_quoted :: proc(b: ^strings.Builder, s: string) {
	strings.write_byte(b, '"')
	for c in s {
		switch c {
		case '"':
			strings.write_string(b, `\"`)
		case '\\':
			strings.write_string(b, `\\`)
		case '\n':
			strings.write_string(b, `\n`)
		case '\r':
			strings.write_string(b, `\r`)
		case '\t':
			strings.write_string(b, `\t`)
		case:
			strings.write_rune(b, c)
		}
	}
	strings.write_byte(b, '"')
}

level_name :: proc(level: log.Level) -> string {
	switch level {
	case .Debug:
		return "debug"
	case .Info:
		return "info"
	case .Warning:
		return "warning"
	case .Error:
		return "error"
	case .Fatal:
		return "fatal"
	}
	return "info"
}

cwd :: proc() -> string {
	dir, err := os.get_working_directory(context.temp_allocator)
	if err != nil {
		return ""
	}
	return dir
}

args_string :: proc() -> string {
	return strings.join(os.args, " ", context.temp_allocator)
}

join :: proc(a, b: string, allocator := context.temp_allocator) -> string {
	s, _ := filepath.join({a, b}, allocator)
	return s
}
