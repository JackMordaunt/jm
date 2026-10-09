package shell

import "base:runtime"
import "core:path/filepath"
import "core:strings"
import "jm:ui"
import "jm:ui/ops"
import "vendor:sdl3"

// A path pick (ui.pick_folder, ui.pick_file, ui.pick_save) opens the
// platform's own dialog through SDL's ShowOpenFolderDialog,
// ShowOpenFileDialog or ShowSaveFileDialog, whichever backend SDL has for
// the platform. SDL may call back on another thread (SDL_dialog.h: "the
// callback may be invoked from the same thread or from a different
// thread"), so the answer is posted as an SDL event of the shell's own
// type, which poll turns into a Picked event for the area that asked, or
// a Pick_Failed when SDL could not show the dialog.

// Pick_Wait is a pick in flight: the area to answer, the filters SDL
// reads until it calls back (SDL_dialog.h: the list "must remain valid at
// least until the callback is invoked"), and, once answered, the path or
// why there is none. It is the shell's from show_pick until poll
// delivers it, all of it in the default allocator, since the callback's
// thread has no other.
@(private)
Pick_Wait :: struct {
	area:    ops.Area_Id,
	filters: []sdl3.DialogFileFilter,
	path:    string,
	failed:  bool,
	reason:  string,
}

// pick_event is the SDL event type an answered pick is posted as,
// registered at the first pick; 0 until then.
@(private)
pick_event: u32

// show_pick opens the dialog q asks for, over w's window. A pick that
// cannot even be posted is failed at once through sink, its reason in
// allocator.
@(private)
show_pick :: proc(
	w: ^Window,
	q: ui.Pick_Path,
	sink: Event_Sink,
	user: rawptr,
	allocator := context.temp_allocator,
) {
	if pick_event == 0 {
		pick_event = sdl3.RegisterEvents(1)
		if pick_event == 0 {
			sink(
				user,
				{
					kind = .Pick_Failed,
					area = q.area,
					text = strings.clone(
						"no SDL event type left for a file dialog's answer",
						allocator,
					),
				},
			)
			return
		}
	}
	a := runtime.default_allocator()
	wait := new(Pick_Wait, a)
	wait.area = q.area
	// A save starts at its suggested name inside start: ShowSaveFileDialog
	// takes both as its one default_location, a path to a file.
	location := q.start
	if q.kind == .Save && q.name != "" {
		location =
			q.name if q.start == "" else (filepath.join({q.start, q.name}, context.temp_allocator) or_else q.name)
	}
	start: cstring = nil
	if location != "" {
		start = strings.clone_to_cstring(location, context.temp_allocator)
	}
	switch q.kind {
	case .Folder:
		sdl3.ShowOpenFolderDialog(post_pick, wait, w.window, start, false)
	case .File:
		sdl3.ShowOpenFileDialog(post_pick, wait, w.window, nil, 0, start, false)
	case .Save:
		if len(q.filters) > 0 {
			wait.filters = make([]sdl3.DialogFileFilter, len(q.filters), a)
			for f, i in q.filters {
				wait.filters[i] = {
					strings.clone_to_cstring(f.label, a),
					strings.clone_to_cstring(f.patterns, a),
				}
			}
		}
		sdl3.ShowSaveFileDialog(
			post_pick,
			wait,
			w.window,
			raw_data(wait.filters),
			i32(len(wait.filters)),
			start,
		)
	}
}

// post_pick takes SDL's answer to a dialog, on any thread: the first path
// chosen, none for a cancel, or a failure with SDL's error when files is
// nil, posted to the event loop.
@(private)
post_pick :: proc "c" (user: rawptr, files: [^]cstring, filter: i32) {
	context = runtime.default_context()
	a := runtime.default_allocator()
	wait := (^Pick_Wait)(user)
	if files == nil {
		wait.failed = true
		wait.reason = strings.clone_from_cstring(sdl3.GetError(), a)
	} else if files[0] != nil {
		wait.path = strings.clone_from_cstring(files[0], a)
	}
	e: sdl3.Event
	e.type = sdl3.EventType(pick_event)
	e.user.data1 = wait
	if !sdl3.PushEvent(&e) {
		free_wait(wait)
	}
}

// take_pick turns a posted answer into the Picked or Pick_Failed event for
// its area, its text in allocator, and frees the wait.
@(private)
take_pick :: proc(e: ^sdl3.Event, allocator := context.allocator) -> ui.Raw_Event {
	wait := (^Pick_Wait)(e.user.data1)
	out := ui.Raw_Event {
		kind = .Picked,
		area = wait.area,
	}
	if wait.failed {
		out.kind = .Pick_Failed
		out.text = strings.clone(wait.reason, allocator)
	} else {
		out.text = strings.clone(wait.path, allocator)
	}
	free_wait(wait)
	return out
}

// free_wait frees a wait and all it holds, from the default allocator.
@(private)
free_wait :: proc(wait: ^Pick_Wait) {
	a := runtime.default_allocator()
	for f in wait.filters {
		delete(f.name, a)
		delete(f.pattern, a)
	}
	delete(wait.filters, a)
	delete(wait.path, a)
	delete(wait.reason, a)
	free(wait, a)
}
