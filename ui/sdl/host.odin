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
// frame and stops trying until the next poll wakes it. Respawning the
// child on a rebuild is a host's caller's job, not run_host's, in this
// first version — see ui/child for the subprocess side.
package sdl

import "base:runtime"
import "core:fmt"

import "jm:ui"
import "jm:ui/ipc"
import "jm:ui/render"
import sdl3 "vendor:sdl3"

// Host_App describes a window and the child process that fills it. Unlike
// App, it carries no ui proc, theme or fonts: those belong to the child,
// over the wire, not to the host.
Host_App :: struct {
	title:         string,
	width, height: int, // initial size in logical units
	child:         []string, // argv to spawn the subprocess; child[0] is the executable
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
	ops:         ui.Ops, // ui.decode rebuilds this from each reply
	frame:       ui.Frame, // ui.flatten rebuilds this from ops each frame
	comp:        render.Compositor,
	events:      [dynamic]ui.Raw_Event, // this frame's batch, in context.temp_allocator
	n:           u64,
	last:        u64,
	in_frame:    bool,
	ctx:         runtime.Context, // for the event watch, which SDL calls without one
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
		if !poll(&l.w, host_sink, l, context.temp_allocator) {
			break
		}
		host_step(l)
		settle(&l.w)
		wait(&l.w, l.wants_frame, l.frame_after, l.shown)
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
	if !open(&l.w, App{title = app.title, width = app.width, height = app.height}) {
		return false
	}
	child, ok := ipc.spawn(app.child, app.dir)
	if !ok {
		fmt.eprintln("sdl: spawn:", app.child)
		close(&l.w)
		return false
	}
	l.child = child
	ui.ops_init(&l.ops)
	ui.frame_init(&l.frame)
	ui.flatten(&l.ops, &l.frame) // a valid, empty frame until the first reply
	render.compositor_init(&l.comp, int(app.threads))
	l.comp.damage.resize_in_place = true
	l.events = make([dynamic]ui.Raw_Event, context.temp_allocator)
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
	render.compositor_destroy(&l.comp)
	ui.frame_destroy(&l.frame)
	ui.ops_destroy(&l.ops)
	close(&l.w)
}

// host_step sends this frame's polled events to the child, decodes its
// reply, flattens and presents. A round trip that fails (the child died,
// or sent something ui/wire cannot parse) marks it dead: the window keeps
// showing its last good frame and host_step becomes a no-op.
@(private)
host_step :: proc(l: ^Host_Loop) {
	l.in_frame = true
	defer l.in_frame = false
	defer free_all(context.temp_allocator)
	if l.child_dead {
		l.wants_frame = false
		return
	}

	now := sdl3.GetTicksNS()
	dt := min(f32(now - l.last) / 1e9, MAX_DT)
	l.last = now

	w := &l.w
	logical := ui.Size{f32(w.size.x) / w.density, f32(w.size.y) / w.density}
	input := ui.encode_input(logical, w.density, dt, l.events[:], context.temp_allocator)
	clear(&l.events)

	if !ipc.write_frame(l.child.stdin, input) {
		l.child_dead = true
		l.wants_frame = false
		return
	}
	reply, rok := ipc.read_frame(l.child.stdout, context.temp_allocator)
	if !rok {
		l.child_dead = true
		l.wants_frame = false
		return
	}
	wants_frame, frame_after, ops_bytes, dok := ui.decode_reply(reply)
	if !dok || !ui.decode(ops_bytes, &l.ops) {
		l.child_dead = true
		l.wants_frame = false
		return
	}
	l.wants_frame, l.frame_after = wants_frame, frame_after
	ui.flatten(&l.ops, &l.frame)
	l.shown = present(w, &l.comp, &l.frame, l.app.clear)
	l.n += 1
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
