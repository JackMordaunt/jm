package ui

import "core:testing"
import "jm:ui/ipc"
import "jm:ui/ops"

// Keys_Model is what keys_view saw: the key state of the last frame, and
// the key events its focused area was sent.
@(private = "file")
Keys_Model :: struct {
	state:  Key_State,
	got:    [dynamic]Event,
	frames: int, // frames run with Right held
}

// keys_view is one focused area that asks for Key and Key_Up.
@(private = "file")
keys_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Keys_Model)(user)
	m.state = key_state(gtx)
	if key_held(gtx, .Right) {
		m.frames += 1
	}
	ops.input_area(gtx.scene, 1, ops.Rect{0, 0, 20, 20}, {.Key, .Key_Up})
	if gtx.frame == 0 {
		focus_request(gtx, 1)
	}
	for e in events(gtx, 1) {
		append(&m.got, e)
	}
}

@(private = "file")
start_keys_probe :: proc(p: ^Probe, m: ^Keys_Model) {
	m.got = make([dynamic]Event, context.temp_allocator)
	probe_init(p, keys_view, m, {100, 100})
	probe_frame(p) // the focus request lands
}

@(test)
a_held_key_stays_held_across_frames_until_let_go :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Keys_Model
	p: Probe
	start_keys_probe(&p, &m)
	defer probe_destroy(&p)

	probe_key_down(&p, .Right)
	testing.expect_value(t, m.state.pressed, Keys{.Right})
	for _ in 0 ..< 9 {
		probe_frame(&p)
		testing.expect_value(t, m.state.held, Keys{.Right})
		testing.expect_value(t, m.state.pressed, Keys{}) // pressed only in its first frame
	}
	testing.expect_value(t, m.frames, 10)

	probe_key_up(&p, .Right)
	testing.expect_value(t, m.state.held, Keys{})
	testing.expect_value(t, m.state.released, Keys{.Right})
	probe_frame(&p)
	testing.expect_value(t, m.state.released, Keys{})
	testing.expect_value(t, m.frames, 10)
}

@(test)
a_repeat_is_not_a_press :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Keys_Model
	p: Probe
	start_keys_probe(&p, &m)
	defer probe_destroy(&p)

	probe_key_down(&p, .A)
	probe_key_down(&p, .A) // the platform repeats a held key
	testing.expect_value(t, m.state.held, Keys{.A})
	testing.expect_value(t, m.state.pressed, Keys{})
	// The repeat still reaches the focused area, which a text field needs.
	keys := 0
	for e in m.got {
		if e.kind == .Key && e.key == .A {
			keys += 1
		}
	}
	testing.expect_value(t, keys, 2)
}

@(test)
a_tap_between_frames_is_pressed_and_released_but_never_held :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Keys_Model
	p: Probe
	start_keys_probe(&p, &m)
	defer probe_destroy(&p)

	probe_key(&p, .Space)
	testing.expect_value(t, m.state, Key_State{pressed = {.Space}, released = {.Space}})
	// The focused area hears both halves.
	testing.expect_value(t, len(m.got), 2)
	testing.expect_value(t, m.got[0].kind, ops.Event_Kind.Key)
	testing.expect_value(t, m.got[0].key, Key.Space)
	testing.expect_value(t, m.got[1].kind, ops.Event_Kind.Key_Up)
	testing.expect_value(t, m.got[1].key, Key.Space)
}

@(test)
a_modifier_key_is_held_but_never_routed :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Keys_Model
	p: Probe
	start_keys_probe(&p, &m)
	defer probe_destroy(&p)

	probe_key_down(&p, .Shift, {.Shift})
	testing.expect_value(t, m.state.held, Keys{.Shift})
	testing.expect_value(t, len(m.got), 0)
	testing.expect(t, !p.router.keyboard) // a modifier alone shows no focus ring
}

@(test)
letting_go_of_none_lets_go_of_every_key :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Keys_Model
	p: Probe
	start_keys_probe(&p, &m)
	defer probe_destroy(&p)

	probe_key_down(&p, .Left)
	probe_key_down(&p, .Up)
	clear(&m.got)
	probe_key_up(&p, .None) // the window lost focus
	testing.expect_value(t, m.state.held, Keys{})
	testing.expect_value(t, m.state.released, Keys{.Left, .Up})
	testing.expect_value(t, len(m.got), 0) // no area hears a Key_Up of None
}

@(test)
a_recording_replays_held_keys :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	buf := make([dynamic]byte, context.temp_allocator)
	ipc.frame_append(&buf, encode_input({100, 100}, 1, 0.25, {}, context.temp_allocator)) // the focus request lands
	ipc.frame_append(&buf, encode_input({100, 100}, 1, 0.25, {{kind = .Key, key = .Right}}, context.temp_allocator))
	ipc.frame_append(&buf, encode_input({100, 100}, 1, 0.25, {}, context.temp_allocator))
	ipc.frame_append(&buf, encode_input({100, 100}, 1, 0.25, {{kind = .Key_Up, key = .Right}}, context.temp_allocator))

	m: Keys_Model
	m.got = make([dynamic]Event, context.temp_allocator)
	p: Probe
	probe_init(&p, keys_view, &m, {100, 100})
	defer probe_destroy(&p)
	frames, ok := probe_replay(&p, buf[:])
	testing.expect(t, ok)
	testing.expect_value(t, frames, 4)
	testing.expect_value(t, m.frames, 2)
	testing.expect_value(t, m.state.released, Keys{.Right})
}
