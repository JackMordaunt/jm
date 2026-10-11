package shell

import "core:testing"

import "vendor:sdl3"

import "jm:ui"

// Event_Log is every event poll sank into log_sink, for the tests that
// push SDL events and read what reached the ui.
@(private)
Event_Log :: struct {
	events: [dynamic]ui.Raw_Event,
}

@(private)
log_sink :: proc(user: rawptr, e: ui.Raw_Event) {
	s := (^Event_Log)(user)
	append(&s.events, e)
}

@(private = "file")
push_key :: proc(type: sdl3.EventType, k: sdl3.Keycode) {
	e: sdl3.Event
	e.type = type
	e.key.key = k
	_ = sdl3.PushEvent(&e)
}

// A key let go reaches the ui as a Key_Up, the modifiers and function keys
// as keys of their own, and a window that loses focus lets go of every
// key, whose releases it will never see. No window is needed, as in
// escape_test.odin.
@(test)
test_keys_come_up_and_focus_loss_lets_go_of_them :: proc(t: ^testing.T) {
	if !sdl3.Init({.EVENTS}) {
		testing.fail_now(t, "SDL's events subsystem would not start")
	}
	defer sdl3.Quit()
	got: Event_Log
	defer delete(got.events)

	w: Window
	w.density = 1
	push_key(.KEY_DOWN, sdl3.K_LSHIFT)
	push_key(.KEY_DOWN, sdl3.K_F5)
	push_key(.KEY_UP, sdl3.K_F5)
	focus: sdl3.Event
	focus.type = .WINDOW_FOCUS_LOST
	_ = sdl3.PushEvent(&focus)
	testing.expect(t, poll(&w, log_sink, &got))

	want := []ui.Raw_Event{{kind = .Key, key = .Shift}, {kind = .Key, key = .F5}, {kind = .Key_Up, key = .F5}, {kind = .Key_Up, key = .None}}
	testing.expect_value(t, len(got.events), len(want))
	for e, ii in got.events[:min(len(got.events), len(want))] {
		testing.expect_value(t, e.kind, want[ii].kind)
		testing.expect_value(t, e.key, want[ii].key)
	}
}
