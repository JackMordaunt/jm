// Host mode: run_host is run's counterpart for the subprocess split.
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
package shell

import "base:runtime"
import "jm:ui/ops"
import "core:fmt"
import "core:mem/virtual"
import "core:os"
import "core:slice"
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
	min_width, min_height: int, // the smallest the window may be made, in logical units; 0 for no limit
	child:         []string, // argv to spawn the subprocess; child[0] is the executable (or the fixed extra args, when watch names the executable instead — see watch)
	watch:         string, // "" uses child[0] as a fixed path. Otherwise, the path to a text file whose trimmed content replaces child[0], re-read every poll: what tools/hot-watch republishes on every successful build.
	dir:           string, // the child's working directory; "" is this process's own
	clear:         Color, // shown before the child's first reply arrives
	threads:       u32, // workers repainting changed regions; 0 or 1 repaints on the main thread
	no_accessibility: bool, // leave assistive technology unserved: no bridge is made
	// The application, here in the host: the child's frames send their
	// needs and commands over the wire, this dispatches them, and what is
	// put in its inbox goes to the child with the next input. See
	// ui/need.odin.
	data:          ui.Data_Host,
}

@(private)
Host_Loop :: struct {
	app:         Host_App,
	w:           Window,
	child:       ipc.Child,
	child_dead:  bool, // a round trip failed; stop trying until respawned
	child_path:  string, // the path last spawned; compared each poll to Host_App.watch's current content
	scene:         ops.Scene, // ui.decode rebuilds this from each reply
	frame:       ui.Frame, // ui.flatten rebuilds this from sc each frame
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
	saved:       [dynamic]u8, // what the child last asked to persist (ui.persist), for the next child
	restoring:   bool, // a child was just spawned with saved to give it: the next input carries it
	a11y:        Bridge, // what assistive technology reads of the child's frames
	// The child's needs, as its diffs left them: the host's own copies, so
	// a respawn can drop the old child's needs the application still
	// serves, which no later diff would name.
	needs:       map[ui.Need_Key]ui.Need,
}

// run_host_from_args is run_host with the child named by the one
// command-line argument, the main of every hot-reloaded example's host: a
// path ending .watch is the pointer file tools/hot-watch republishes, any
// other a fixed child executable. It exits with a usage line otherwise.
run_host_from_args :: proc(app: Host_App) {
	if len(os.args) != 2 {
		fmt.eprintfln("usage: %s <pointer-file.watch | child exe>", os.args[0])
		os.exit(2)
	}
	run_host(host_app_for(app, os.args[1:]))
}

// host_app_for is app with args[0] as its watch pointer file or its child.
@(private)
host_app_for :: proc(app: Host_App, args: []string) -> Host_App {
	app := app
	if strings.has_suffix(args[0], ".watch") {
		app.watch = args[0]
	} else {
		app.child = args[:1]
	}
	return app
}

// run_host opens the window, spawns app.child, and loops until the window
// is closed, Escape is pressed, or the process is sent SIGINT or SIGTERM.
// It reports failure to open or spawn on stderr and returns; the child, if
// it started, is killed first.
run_host :: proc(app: Host_App) {
	set_hints()
	interrupt_start()
	defer interrupt_stop()
	if !sdl3.Init({.VIDEO, .EVENTS}) {
		fmt.eprintln("shell: init:", sdl3.GetError())
		return
	}
	defer sdl3.Quit()
	scroll_watch_start()
	defer scroll_watch_stop()

	l := new(Host_Loop)
	defer free(l)
	if !host_loop_init(l, app) {
		return
	}
	defer host_loop_destroy(l)
	_ = sdl3.AddEventWatch(redraw_on_expose_host, l)
	defer sdl3.RemoveEventWatch(redraw_on_expose_host, l)

	for {
		bridge_take_actions(&l.a11y, &l.frame, host_sink, l)
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
	// The child first, so a watch whose first build has not landed yet
	// is waited for without a window sitting unresponsive meanwhile.
	path, pok := wait_for_child(&l.app, WATCH_WAIT, context.temp_allocator)
	if !pok {
		fmt.eprintln("shell: no child to spawn (check Host_App.child / watch)")
		return false
	}
	if !open(&l.w, App{title = app.title, width = app.width, height = app.height, min_width = app.min_width, min_height = app.min_height}) {
		return false
	}
	argv := child_argv(&l.app, path, context.temp_allocator)
	child, ok := ipc.spawn(argv, app.dir)
	if !ok {
		fmt.eprintln("shell: spawn:", argv)
		close(&l.w)
		return false
	}
	l.child = child
	l.child_path = strings.clone(path)
	ops.init(&l.scene)
	ui.frame_init(&l.frame)
	ui.flatten(&l.scene, &l.frame) // a valid, empty frame until the first reply
	render.compositor_init(&l.comp, int(app.threads))
	l.comp.damage.resize_in_place = true
	l.events = make([dynamic]ui.Raw_Event)
	l.saved = make([dynamic]u8)
	l.last = sdl3.GetTicksNS()
	if !app.no_accessibility && bridge_init(&l.a11y, l.w.window, app.title) {
		l.w.a11y = &l.a11y
	}
	sdl3.ShowWindow(l.w.window)
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
	bridge_destroy(&l.a11y)
	delete(l.child_path)
	delete(l.events)
	delete(l.saved)
	for _, n in l.needs {
		need_delete(n)
	}
	delete(l.needs)
	virtual.arena_destroy(&l.text)
	render.compositor_destroy(&l.comp)
	ui.frame_destroy(&l.frame)
	ops.destroy(&l.scene)
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

// WATCH_WAIT is how long a host waits for its watch pointer file to
// appear when the recipe starts it and hot-watch at once: the first
// build of the child has to land first (about 20 s for the kitchens on
// the machine this was written on), and two minutes leaves room for a
// slower one without hanging a recipe whose watcher never builds.
WATCH_WAIT :: 2 * time.Minute

// wait_for_child is resolve_child_path, retried every RESPAWN_POLL_S
// for up to timeout while app names a watch file that does not exist
// yet (the first build has not landed). A missing child list fails at
// once, as there is nothing to wait for.
@(private)
wait_for_child :: proc(app: ^Host_App, timeout: time.Duration, allocator := context.allocator) -> (string, bool) {
	path, ok := resolve_child_path(app, allocator)
	if ok || app.watch == "" {
		return path, ok
	}
	fmt.eprintfln("shell: waiting for %s", app.watch)
	deadline := time.time_add(time.now(), timeout)
	for !ok && time.diff(time.now(), deadline) > 0 {
		time.sleep(time.Duration(RESPAWN_POLL_S * f32(time.Second)))
		path, ok = resolve_child_path(app, allocator)
	}
	return path, ok
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
	// The new child's router starts with the input method off, so the
	// window's goes off with it, or a field focused before the rebuild
	// would leave it on with nothing to say where.
	apply_text_input(&l.w, {})
	// The new child asks again for what it shows; what the old one asked
	// for is let go, or the application would serve it for good.
	host_drop_needs(l)
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
	// The new child starts from the state the last one persisted.
	l.restoring = len(l.saved) > 0
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
	logical := ops.Size{f32(w.size.x) / w.density, f32(w.size.y) / w.density}
	shapes: []ui.Delivery
	if l.app.data.inbox != nil {
		shapes = ui.inbox_take(l.app.data.inbox, context.temp_allocator)
	}
	input := ui.encode_input(logical, w.density, dt, l.events[:], context.temp_allocator, l.host_stats, l.saved[:] if l.restoring else nil, shapes)
	l.restoring = false
	clear(&l.events)
	virtual.arena_free_all(&l.text) // encode_input copied every Text string

	trip_start := time.tick_now()
	if !ipc.write_frame(l.child.stdin, input) {
		fmt.eprintfln("shell: %s stopped reading input (exited?); showing its last frame", l.child_path)
		l.child_dead = true
		l.wants_frame = false
		return
	}
	reply, rok := ipc.read_frame(l.child.stdout, context.temp_allocator)
	if !rok {
		fmt.eprintfln("shell: %s sent no reply (exited or crashed?); showing its last frame", l.child_path)
		l.child_dead = true
		l.wants_frame = false
		return
	}
	roundtrip_ms := ui.ms(trip_start)
	dbg: ui.Reply_Debug
	plat: ui.Reply_Platform
	persist: []byte
	rd: ui.Reply_Data
	wants_frame, frame_after, ops_bytes, dok := ui.decode_reply(reply, &dbg, &plat, &persist, &rd)
	if persist != nil {
		// Kept here, not in the child, so it outlives the child.
		clear(&l.saved)
		append(&l.saved, ..persist)
	}
	if !dok || !ops.decode(ops_bytes, &l.scene) {
		// Say why: the window just freezes on its last frame otherwise, which
		// reads as a crash. A version mismatch is a host built before the
		// child's jm:ui changed its ops.
		if v, vok := ops.encoded_version(ops_bytes); dok && vok && v != ops.ENCODE_VERSION {
			fmt.eprintfln("shell: %s speaks sc version %d, this host %d: rebuild the host", l.child_path, v, ops.ENCODE_VERSION)
			if host_rebuilt(l) {
				host_reexec(l)
			}
		} else {
			fmt.eprintfln("shell: %s sent a reply this host cannot decode; showing its last frame", l.child_path)
		}
		l.child_dead = true
		l.wants_frame = false
		return
	}
	// The child's needs and commands go to the application here before
	// the frame renders, so a request does not wait on presenting it.
	ui.data_dispatch(&l.app.data, rd.added, rd.dropped, rd.commands)
	host_track_needs(l, rd.added, rd.dropped)
	ui.flatten(&l.scene, &l.frame, {0, 0, f32(w.size.x), f32(w.size.y)}, ops.scale(w.density, w.density))
	present_start := time.tick_now()
	l.shown, l.host_stats.repaint_rects, l.host_stats.repaint_px = present(w, &l.comp, &l.frame, l.app.clear, dbg.full_frames, dbg.flash, ui.reply_keep_out(&dbg))
	// Sent with the next input, for the child's debug tray.
	l.host_stats.present_ms, l.host_stats.roundtrip_ms = ui.ms(present_start), roundtrip_ms
	l.host_stats.rss_bytes = ui.process_rss()
	bridge_frame(&l.a11y, &l.frame, plat.focus)
	l.wants_frame, l.frame_after = wants_frame || flashing(w), frame_after
	// The cursor and clipboard the child asked for; a read's Paste goes
	// out with the next input, so a frame must follow to carry it.
	reqs := ui.reply_requests(&plat)
	for q in reqs {
		if _, reads := q.(ui.Clipboard_Read); reads {
			l.wants_frame, l.frame_after = true, 0
		}
	}
	apply_platform(w, plat.cursor, plat.changed, reqs, host_sink, l, virtual.arena_allocator(&l.text))
	// An answer already waiting wants a frame to carry it over.
	if l.app.data.inbox != nil && ui.inbox_pending(l.app.data.inbox) {
		l.wants_frame, l.frame_after = true, 0
	}
	l.n += 1
}

// host_track_needs applies a frame's need diff to l.needs.
@(private)
host_track_needs :: proc(l: ^Host_Loop, added, dropped: []ui.Need) {
	for n in added {
		if old, ok := l.needs[n.key]; ok {
			need_delete(old)
		}
		l.needs[n.key] = {key = n.key, kind = strings.clone(n.kind), query = slice.clone(n.query)}
	}
	for n in dropped {
		if old, ok := l.needs[n.key]; ok {
			need_delete(old)
			delete_key(&l.needs, n.key)
		}
	}
}

// host_drop_needs tells the application every need in l.needs is gone,
// and forgets them.
@(private)
host_drop_needs :: proc(l: ^Host_Loop) {
	if len(l.needs) == 0 {
		return
	}
	gone := make([dynamic]ui.Need, 0, len(l.needs), context.temp_allocator)
	for _, n in l.needs {
		append(&gone, n)
	}
	ui.data_dispatch(&l.app.data, nil, gone[:], nil)
	for n in gone {
		need_delete(n)
	}
	clear(&l.needs)
}

@(private)
need_delete :: proc(n: ui.Need) {
	delete(n.kind)
	delete(n.query)
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
