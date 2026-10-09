package shell

import "core:testing"

import "vendor:sdl3"

import "jm:ui"

@(private = "file")
Key_Log :: struct {
	keys: [dynamic]ui.Key,
}

@(private = "file")
log_sink :: proc(user: rawptr, e: ui.Raw_Event) {
	s := (^Key_Log)(user)
	if e.kind == .Key {
		append(&s.keys, e.key)
	}
}

@(private = "file")
push_escape :: proc() {
	e: sdl3.Event
	e.type = .KEY_DOWN
	e.key.key = sdl3.K_ESCAPE
	_ = sdl3.PushEvent(&e)
}

// drain empties SDL's queue. A poll that returns early stops the next
// PollEvent short: in this test, written 2026-10-09 against the vendored
// SDL3, a key pushed after it was queued (PeepEvents saw it) but the next
// poll got nothing until the queue was drained. The window's loop polls
// again every frame, so only a test that polls twice sees this.
@(private = "file")
drain :: proc() {
	e: sdl3.Event
	for sdl3.PollEvent(&e) {}
}

// Escape ends the run, as it always has, unless the app keeps it, when it
// reaches the ui as a key like any other. No window is needed: poll reads
// SDL's event queue, and this test opens only the events subsystem.
@(test)
test_escape_closes_unless_the_app_keeps_it :: proc(t: ^testing.T) {
	if !sdl3.Init({.EVENTS}) {
		testing.fail_now(t, "SDL's events subsystem would not start")
	}
	defer sdl3.Quit()
	keys: Key_Log
	defer delete(keys.keys)

	w: Window
	w.density = 1
	push_escape()
	testing.expect(t, !poll(&w, log_sink, &keys), "Escape ends the run by default")
	testing.expect_value(t, len(keys.keys), 0)
	drain()

	w.keep_escape = true
	push_escape()
	testing.expect(t, poll(&w, log_sink, &keys), "a kept Escape does not")
	testing.expect_value(t, len(keys.keys), 1)
	if len(keys.keys) == 1 {
		testing.expect_value(t, keys.keys[0], ui.Key.Escape)
	}
}
