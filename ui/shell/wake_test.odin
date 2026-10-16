package shell

import "core:testing"

import "vendor:sdl3"

// The shell's own event types are distinct, so a wake is never taken for
// a Dock reopen, whichever registered first. No window is needed: poll
// reads SDL's event queue, as in escape_test.odin, reopen_register needs
// no NSApp, and reopen_asked compares types without touching the window.
@(test)
test_wake_is_its_own_event_not_a_reopen :: proc(t: ^testing.T) {
	if !sdl3.Init({.EVENTS}) {
		testing.fail_now(t, "SDL's events subsystem would not start")
	}
	defer sdl3.Quit()
	got: Event_Log
	defer delete(got.events)

	wake_register()
	testing.expect(t, wake_event != 0, "wake has a registered type")
	testing.expect(t, wake_event >= u32(sdl3.EventType.USER), "wake's type is a registered one")
	testing.expect(t, pick_register(), "pick has a registered type")
	testing.expect(t, pick_event != wake_event, "pick's type is not wake's")
	when ODIN_OS == .Darwin {
		testing.expect(t, reopen_register(), "reopen has a registered type")
		testing.expect(t, reopen_event != wake_event, "reopen's type is not wake's")
		testing.expect(t, reopen_event != pick_event, "reopen's type is not pick's")
	}

	e: sdl3.Event
	e.type = sdl3.EventType(wake_event)
	testing.expect(t, woken(&e), "a wake is a wake")
	e.type = sdl3.EventType(pick_event)
	testing.expect(t, !woken(&e), "a pick's answer is not a wake")
	e.type = .KEY_DOWN
	testing.expect(t, !woken(&e), "a key is not a wake")
	when ODIN_OS == .Darwin {
		e.type = sdl3.EventType(reopen_event)
		testing.expect(t, !woken(&e), "a reopen is not a wake")
		testing.expect(t, reopen_asked(&e), "a reopen is a reopen")
		e.type = sdl3.EventType(wake_event)
		testing.expect(t, !reopen_asked(&e), "a wake is not a reopen")
	}

	wake()
	queued := sdl3.EventType(wake_event)
	testing.expect_value(t, sdl3.PeepEvents(nil, 0, .PEEKEVENT, queued, queued), 1)
	w: Window
	w.density = 1
	testing.expect(t, poll(&w, log_sink, &got), "a wake keeps the run going")
	testing.expect_value(t, len(got.events), 0)
	testing.expect_value(t, sdl3.PeepEvents(nil, 0, .PEEKEVENT, queued, queued), 0)
}
