#+build darwin
package shell

import "base:intrinsics"
import "core:log"
import NS "core:sys/darwin/Foundation"
import "vendor:sdl3"

// On macOS closing the window does not quit the application: Cmd+W, or the
// red button, hides the window, the application stays in the Dock, and a
// click on its icon brings the window back; Cmd+Q quits. SDL has no event
// for the click. AppKit tells the application delegate of it through
// applicationShouldHandleReopen:hasVisibleWindows: (NSApplicationDelegate),
// a method SDL's delegate, SDL3AppDelegate in SDL_cocoaevents.m, leaves out
// as of SDL 3.4.16, so reopen_watch adds it to the delegate's class, and it
// posts reopen_event for poll. Should a later SDL add the method itself,
// class_addMethod refuses, and reopen_watch says so.

@(private)
reopen_event: u32

@(private = "file")
watched: bool

// close_window closes the window as macOS does: hidden, and kept.
@(private)
close_window :: proc(w: ^Window) -> (kept: bool) {
	_ = sdl3.HideWindow(w.window)
	return true
}

// reopen_register registers reopen_event, once, and is whether there is one.
@(private)
reopen_register :: proc() -> bool {
	if reopen_event == 0 {
		reopen_event = register_event("reopen from the Dock")
	}
	return reopen_event != 0
}

// reopen_watch gives SDL's application delegate the reopen method, once.
@(private)
reopen_watch :: proc() {
	if watched || !reopen_register() {
		return
	}
	watched = true
	app := intrinsics.objc_send(^NS.Application, NS.Application, "sharedApplication")
	delegate := intrinsics.objc_send(NS.id, app, "delegate")
	if delegate == nil {
		log.warn("ui/shell: NSApp has no delegate; the window cannot be brought back from the Dock")
		return
	}
	added := NS.class_addMethod(
		NS.object_getClass(delegate),
		intrinsics.objc_find_selector("applicationShouldHandleReopen:hasVisibleWindows:"),
		auto_cast should_handle_reopen,
		"B@:@B",
	)
	if !added {
		log.warn("ui/shell: the application delegate already handles reopen; the window cannot be brought back from the Dock")
	}
}

// should_handle_reopen is the Dock icon clicked: with a window showing
// AppKit's own behaviour stands, else the hidden window is asked back.
@(private = "file")
should_handle_reopen :: proc "c" (self: NS.id, cmd: NS.SEL, app: NS.id, visible: NS.BOOL) -> NS.BOOL {
	if visible {
		return true
	}
	e: sdl3.Event
	e.type = sdl3.EventType(reopen_event)
	_ = sdl3.PushEvent(&e)
	return false
}

// reopen_asked is whether e is the Dock asking the hidden window back.
@(private)
reopen_asked :: proc(e: ^sdl3.Event) -> bool {
	return reopen_event != 0 && u32(e.type) == reopen_event
}

// reopened is whether e asks the hidden window back, shown and raised.
@(private)
reopened :: proc(w: ^Window, e: ^sdl3.Event) -> bool {
	if !reopen_asked(e) {
		return false
	}
	_ = sdl3.ShowWindow(w.window)
	_ = sdl3.RaiseWindow(w.window)
	return true
}
