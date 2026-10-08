package shell

import "base:runtime"
import "core:strings"
import "jm:ui"
import "jm:ui/ops"
import "vendor:sdl3"

// A path pick (ui.pick_folder, ui.pick_file) opens the platform's own dialog through
// SDL's ShowOpenFolderDialog or ShowOpenFileDialog, whichever backend SDL
// has for the platform. SDL may call back on another thread
// (SDL_dialog.h: "the callback may be invoked from the same thread or
// from a different thread"), so the answer is posted as an SDL event of
// the shell's own type, which poll turns into a Picked event for the
// area that asked.

// Pick_Wait is a pick in flight: the area to answer and, once answered,
// the path. It is the shell's from show_pick until poll delivers it.
@(private)
Pick_Wait :: struct {
	area: ops.Area_Id,
	path: string,
}

// pick_event is the SDL event type an answered pick is posted as,
// registered at the first pick; 0 until then.
@(private)
pick_event: u32

// show_pick opens the dialog q asks for, over w's window.
@(private)
show_pick :: proc(w: ^Window, q: ui.Pick_Path) {
	if pick_event == 0 {
		pick_event = sdl3.RegisterEvents(1)
		if pick_event == 0 {
			return
		}
	}
	wait := new(Pick_Wait, runtime.default_allocator())
	wait.area = q.area
	start: cstring = nil
	if q.start != "" {
		start = strings.clone_to_cstring(q.start, context.temp_allocator)
	}
	if q.folder {
		sdl3.ShowOpenFolderDialog(post_pick, wait, w.window, start, false)
	} else {
		sdl3.ShowOpenFileDialog(post_pick, wait, w.window, nil, 0, start, false)
	}
}

// post_pick takes SDL's answer to a dialog, on any thread: the first path
// chosen, or none for a cancel or an error, posted to the event loop.
@(private)
post_pick :: proc "c" (user: rawptr, files: [^]cstring, filter: i32) {
	context = runtime.default_context()
	wait := (^Pick_Wait)(user)
	if files != nil && files[0] != nil {
		wait.path = strings.clone_from_cstring(files[0], runtime.default_allocator())
	}
	e: sdl3.Event
	e.type = sdl3.EventType(pick_event)
	e.user.data1 = wait
	if !sdl3.PushEvent(&e) {
		delete(wait.path, runtime.default_allocator())
		free(wait, runtime.default_allocator())
	}
}

// take_pick turns a posted answer into the Picked event for its area,
// its text in allocator, and frees the wait.
@(private)
take_pick :: proc(e: ^sdl3.Event, allocator := context.allocator) -> ui.Raw_Event {
	wait := (^Pick_Wait)(e.user.data1)
	out := ui.Raw_Event{kind = .Picked, area = wait.area, text = strings.clone(wait.path, allocator)}
	delete(wait.path, runtime.default_allocator())
	free(wait, runtime.default_allocator())
	return out
}
