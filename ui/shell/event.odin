package shell

import "core:log"
import "core:sync"
import "vendor:sdl3"

// The shell posts events of its own to SDL's queue: a wake, a Dock reopen
// (close_darwin.odin), a path pick's answer (pick.odin). Each is a type of
// its own from register_event, never a bare .USER: SDL_RegisterEvents
// returns SDL_EVENT_USER plus a count that starts at 0 (SDL_events.c at
// the revision the justfile pins, read 2026-10-16), so the first type
// registered is .USER itself, and an event pushed as .USER is taken for
// whatever registered first. Until 2026-10-16 wake pushed .USER and
// reopen registered first, so every wake showed and raised the window,
// which on macOS activates the application (Cocoa_RaiseWindow calls
// activateIgnoringOtherApps:, seen under lldb), and an app that woke the
// shell on each progress delivery stole focus continuously.

// register_event reserves one SDL event type for what, or 0 when SDL has
// none left, which it logs. SDL's count of registered types is one
// process-wide atomic that only SDL_RegisterEvents touches, so SDL_Quit
// does not reset it (same source), any thread may register, before or
// after SDL_Init, and no two calls ever share a type.
@(private)
register_event :: proc(what: string) -> u32 {
	type := sdl3.RegisterEvents(1)
	if type == 0 {
		log.warnf("ui/shell: no SDL event type left for %s", what)
	}
	return type
}

// wake_event is the type wake pushes, registered by wake_register; 0
// until then, or when SDL had none left, and a wake then does nothing.
@(private)
wake_event: u32

@(private = "file")
wake_once: sync.Once

// wake_register registers wake's event type, once per process. run calls
// it before its loop, and wake itself calls it, so a wake from any thread
// before the window opens still has a type to push.
@(private)
wake_register :: proc() {
	sync.once_do(&wake_once, proc() {
		wake_event = register_event("wake")
	})
}

// wake runs a frame soon, as input would. Any thread may call it, for
// instance when work the ui shows has finished. Before sdl3.Init the push
// fails and the wake is lost, as any event would be: SDL_PeepEvents
// refuses while the queue is inactive ("The event system has been shut
// down", same source).
wake :: proc() {
	wake_register()
	if wake_event == 0 {
		return
	}
	e: sdl3.Event
	e.type = sdl3.EventType(wake_event)
	_ = sdl3.PushEvent(&e)
}

// woken is whether e is a wake: a frame request, and nothing else.
@(private)
woken :: proc(e: ^sdl3.Event) -> bool {
	return wake_event != 0 && u32(e.type) == wake_event
}
