// Host mode: run_host is sdl.run's counterpart for the subprocess split.
// It owns the window exactly as run does — the same Window, resize, vsync,
// live-resize-redraw and present machinery — but instead of calling a ui
// proc directly, it round-trips one ui/wire Input to a spawned child's
// stdin each frame and reads back one Reply from its stdout. The child
// owns the Model, the ui proc, Router and Layout; run_host owns none of
// that, so it never routes input itself and needs no Router or Layout.
//
// A crash, a hang, or a rebuild-in-progress subprocess never reaches this
// loop: a failed round trip just leaves the window showing its last good
// frame and stops trying. When Host_App.watch names a pointer file,
// run_host re-reads it every poll and respawns whenever its content (the
// child's own path) changes — this is the "hot" of hot reload.
//
// One anecdote, not a documented guarantee, is the reason this is an
// indirection rather than a fixed path: os.chtimes on this session's own
// running hot-counter-child.exe, once, on this Windows machine, returned
// Permission_Denied. tools/hot-watch (or any other builder) avoids
// finding out the hard way whether a build would hit the same thing, by
// writing each new build to its own path and republishing the pointer
// rather than touching the path the running child was started from. It
// polls for that at least every RESPAWN_POLL_S seconds even with an idle
// child,
// so a rebuild is never left waiting on the next real input event to be
// seen.
package sdl

import "base:runtime"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:strings"
import "core:time"

import "jm:ui"
import "jm:ui/ipc"
import "jm:ui/render"
import sdl3 "vendor:sdl3"

// RESPAWN_POLL_S bounds how long an idle host can go without checking
// Host_App.watch for a rebuild.
@(private)
RESPAWN_POLL_S :: f32(0.5)

// Host_App describes a window and the child process that fills it. Unlike
// App, it carries no ui proc, theme or fonts: those belong to the child,
// over the wire, not to the host.
Host_App :: struct {
	title:         string,
	width, height: int, // initial size in logical units
	child:         []string, // argv to spawn the subprocess; child[0] is the executable (or the fixed extra args, when watch names the executable instead — see watch)
	watch:         string, // "" uses child[0] as a fixed path. Otherwise, the path to a text file whose trimmed content replaces child[0], re-read every poll: what tools/hot-watch republishes on every successful build.
	dir:           string, // the child's working directory; "" is this process's own
	clear:         Color, // shown before the child's first reply arrives
	threads:       u32, // workers repainting changed regions; 0 or 1 repaints on the main thread
}

@(private)
Host_Loop :: struct {
	app:         Host_App,
	w:           Window,
	child:       ipc.Child,
	child_dead:  bool, // a round trip failed; stop trying until respawned
	child_path:  string, // the path last spawned; compared each poll to Host_App.watch's current content
	ops:         ui.Ops, // ui.decode rebuilds this from each reply
	frame:       ui.Frame, // ui.flatten rebuilds this from ops each frame
	comp:        render.Compositor,
	// This frame's batch. Both outlive host_step's free_all of
	// context.temp_allocator: events is on the heap, and the Text strings
	// in it are in text, which is reset only once they are encoded. Both
	// used to live in the temp allocator, so a frame's free_all left the
	// array pointing at memory the next temp allocation (every poll reads
	// the watch file into it) scribbled over — the watch-only segfault in
	// encode_input.
	events:      [dynamic]ui.Raw_Event,
	text:        virtual.Arena,
	n:           u64,
	last:        u64,
	in_frame:    bool,
	ctx:         runtime.Context, // for the event watch, which SDL calls without one
	started:     time.Time, // when this host process began, to tell whether its executable was rebuilt since
	host_stats:  ui.Host_Stats, // what the last frame cost here, sent to the child with the next input
	wants_frame: bool,
	frame_after: f32,
	shown:       bool,
}

// run_host opens the window, spawns app.child, and loops until the window
// is closed or Escape is pressed. It reports failure to open or spawn on
// stderr and returns; the child, if it started, is killed first.
run_host :: proc(app: Host_App) {
	if !sdl3.Init({.VIDEO, .EVENTS}) {
		fmt.eprintln("sdl: init:", sdl3.GetError())
		return
	}
	defer sdl3.Quit()

	l := new(Host_Loop)
	defer free(l)
	if !host_loop_init(l, app) {
		return
	}
	defer host_loop_destroy(l)
	_ = sdl3.AddEventWatch(redraw_on_expose_host, l)
	defer sdl3.RemoveEventWatch(redraw_on_expose_host, l)

	for {
		if !poll(&l.w, host_sink, l, virtual.arena_allocator(&l.text)) {
			break
		}
		host_step(l)
		settle(&l.w)
		after := RESPAWN_POLL_S
		if l.wants_frame {
			after = min(after, l.frame_after)
		}
		wait(&l.w, true, after, l.shown)
	}
}

@(private)
host_sink :: proc(user: rawptr, e: ui.Raw_Event) {
	l := (^Host_Loop)(user)
	append(&l.events, e)
}

@(private)
host_loop_init :: proc(l: ^Host_Loop, app: Host_App) -> bool {
	l.app = app
	l.ctx = context
	l.started = time.now()
	if !open(&l.w, App{title = app.title, width = app.width, height = app.height}) {
		return false
	}
	path, pok := resolve_child_path(&l.app, context.temp_allocator)
	if !pok {
		fmt.eprintln("sdl: no child to spawn (check Host_App.child / watch)")
		close(&l.w)
		return false
	}
	argv := child_argv(&l.app, path, context.temp_allocator)
	child, ok := ipc.spawn(argv, app.dir)
	if !ok {
		fmt.eprintln("sdl: spawn:", argv)
		close(&l.w)
		return false
	}
	l.child = child
	l.child_path = strings.clone(path)
	ui.ops_init(&l.ops)
	ui.frame_init(&l.frame)
	ui.flatten(&l.ops, &l.frame) // a valid, empty frame until the first reply
	render.compositor_init(&l.comp, int(app.threads))
	l.comp.damage.resize_in_place = true
	l.events = make([dynamic]ui.Raw_Event)
	l.last = sdl3.GetTicksNS()
	return true
}

@(private)
host_loop_destroy :: proc(l: ^Host_Loop) {
	// Called whether the child is still running or already gone (host_step
	// sets child_dead on the first failed round trip and never retries).
	// ipc.kill's own os.process_kill/wait/close calls return errors, all
	// discarded here on purpose: by this point in shutdown there is
	// nothing left to do about one, whatever it turns out to mean in the
	// already-gone case.
	ipc.kill(&l.child)
	delete(l.child_path)
	delete(l.events)
	virtual.arena_destroy(&l.text)
	render.compositor_destroy(&l.comp)
	ui.frame_destroy(&l.frame)
	ui.ops_destroy(&l.ops)
	close(&l.w)
}

// resolve_child_path is the path to spawn: app.child[0] fixed, or, when
// app.watch names a pointer file, that file's trimmed content. False
// means nothing to spawn — app.child is empty with no watch set, the
// pointer file is empty, or it could not be read at all: the caller
// keeps whatever path it already had and tries again next poll.
@(private)
resolve_child_path :: proc(app: ^Host_App, allocator := context.allocator) -> (string, bool) {
	if app.watch == "" {
		if len(app.child) == 0 {
			return "", false
		}
		return app.child[0], true
	}
	data, err := os.read_entire_file(app.watch, allocator)
	if err != nil {
		return "", false
	}
	path := strings.trim_space(string(data))
	return path, path != ""
}

// child_argv is path, app.child's own extra arguments (app.child[1:], or
// all of app.child when watch is unset and child[0] already is path).
@(private)
child_argv :: proc(app: ^Host_App, path: string, allocator := context.allocator) -> []string {
	extra := app.child[1:] if len(app.child) > 1 else app.child[:0]
	argv := make([]string, 1 + len(extra), allocator)
	argv[0] = path
	copy(argv[1:], extra)
	return argv
}

// host_maybe_respawn kills and replaces l.child when resolve_child_path no
// longer matches l.child_path — a rebuild landed, whether l.child was
// still running or already dead. The old child's Router, Layout and Model
// go with it; the new one starts cold, same as if the host itself had
// just opened.
@(private)
host_maybe_respawn :: proc(l: ^Host_Loop) {
	path, ok := resolve_child_path(&l.app, context.temp_allocator)
	if !ok || path == l.child_path {
		return
	}
	ipc.kill(&l.child)
	argv := child_argv(&l.app, path, context.temp_allocator)
	child, sok := ipc.spawn(argv, l.app.dir)
	delete(l.child_path)
	l.child_path = strings.clone(path)
	if !sok {
		l.child_dead = true
		return
	}
	l.child = child
	l.child_dead = false
}

// host_step sends this frame's polled events to the child, decodes its
// reply, flattens and presents. A round trip that fails (the child died,
// or sent something ui/wire cannot parse) marks it dead: the window keeps
// showing its last good frame until resolve_child_path names something new.
@(private)
host_step :: proc(l: ^Host_Loop) {
	l.in_frame = true
	defer l.in_frame = false
	defer free_all(context.temp_allocator)
	host_maybe_respawn(l)
	if l.child_dead {
		clear(&l.events) // nobody to send them to
		virtual.arena_free_all(&l.text)
		l.wants_frame = false
		return
	}

	now := sdl3.GetTicksNS()
	dt := min(f32(now - l.last) / 1e9, MAX_DT)
	l.last = now

	w := &l.w
	logical := ui.Size{f32(w.size.x) / w.density, f32(w.size.y) / w.density}
	input := ui.encode_input(logical, w.density, dt, l.events[:], context.temp_allocator, l.host_stats)
	clear(&l.events)
	virtual.arena_free_all(&l.text) // encode_input copied every Text string

	trip_start := time.tick_now()
	if !ipc.write_frame(l.child.stdin, input) {
		fmt.eprintfln("sdl: %s stopped reading input (exited?); showing its last frame", l.child_path)
		l.child_dead = true
		l.wants_frame = false
		return
	}
	reply, rok := ipc.read_frame(l.child.stdout, context.temp_allocator)
	if !rok {
		fmt.eprintfln("sdl: %s sent no reply (exited or crashed?); showing its last frame", l.child_path)
		l.child_dead = true
		l.wants_frame = false
		return
	}
	roundtrip_ms := ui.ms(trip_start)
	dbg: ui.Reply_Debug
	wants_frame, frame_after, ops_bytes, dok := ui.decode_reply(reply, &dbg)
	if !dok || !ui.decode(ops_bytes, &l.ops) {
		// Say why: the window just freezes on its last frame otherwise, which
		// reads as a crash. A version mismatch is a host built before the
		// child's jm:ui changed its ops.
		if v, vok := ui.encoded_version(ops_bytes); dok && vok && v != ui.ENCODE_VERSION {
			fmt.eprintfln("sdl: %s speaks ops version %d, this host %d: rebuild the host", l.child_path, v, ui.ENCODE_VERSION)
			if host_rebuilt(l) {
				host_reexec(l)
			}
		} else {
			fmt.eprintfln("sdl: %s sent a reply this host cannot decode; showing its last frame", l.child_path)
		}
		l.child_dead = true
		l.wants_frame = false
		return
	}
	ui.flatten(&l.ops, &l.frame)
	present_start := time.tick_now()
	l.shown, l.host_stats.repaint_rects, l.host_stats.repaint_px = present(w, &l.comp, &l.frame, l.app.clear, dbg.full_frames, dbg.flash, ui.reply_keep_out(&dbg))
	// Sent with the next input, for the child's debug tray.
	l.host_stats.present_ms, l.host_stats.roundtrip_ms = ui.ms(present_start), roundtrip_ms
	l.host_stats.rss_bytes = ui.process_rss()
	l.wants_frame, l.frame_after = wants_frame || flashing(w), frame_after
	l.n += 1
}

// host_rebuilt reports whether this host's executable on disk is newer
// than the process running it: tools/hot-watch -host rebuilt it.
@(private)
host_rebuilt :: proc(l: ^Host_Loop) -> bool {
	fi, err := os.stat(os.args[0], context.temp_allocator)
	if err != nil {
		return false
	}
	return time.diff(l.started, fi.modification_time) > 0
}

// redraw_on_expose_host is redraw_on_expose for a Host_Loop, sharing its
// resize_for_new_size body: the same keep-drawing-through-a-live-resize
// behaviour, one round trip at a time.
@(private)
redraw_on_expose_host :: proc "c" (userdata: rawptr, e: ^sdl3.Event) -> bool {
	l := (^Host_Loop)(userdata)
	if e.type != .WINDOW_EXPOSED || l.in_frame {
		return true
	}
	context = l.ctx
	if resize_for_new_size(&l.w) {
		host_step(l)
	}
	return true
}
