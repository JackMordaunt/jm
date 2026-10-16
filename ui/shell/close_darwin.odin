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

@(private = "file")
reopen_event: u32

// close_window closes the window as macOS does: hidden, and kept.
@(private)
close_window :: proc(w: ^Window) -> (kept: bool) {
	_ = sdl3.HideWindow(w.window)
	return true
}

// reopen_watch gives SDL's application delegate the reopen method, once.
@(private)
reopen_watch :: proc() {
	if reopen_event != 0 {
		return
	}
	reopen_event = sdl3.RegisterEvents(1)
	if reopen_event == 0 {
		log.warn("ui/shell: no event type left for reopen; the window cannot be brought back from the Dock")
		return
	}
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

// reopened is whether e asks the hidden window back, shown and raised.
@(private)
reopened :: proc(w: ^Window, e: ^sdl3.Event) -> bool {
	if reopen_event == 0 || u32(e.type) != reopen_event {
		return false
	}
	_ = sdl3.ShowWindow(w.window)
	_ = sdl3.RaiseWindow(w.window)
	return true
}
