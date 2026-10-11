package game

import "jm:ui"

// Buttons is a set of pointer buttons.
Buttons :: bit_set[ui.Button]

// Input is what one tick of step sees: the keys and pointer buttons held,
// and those pressed and released since the tick before. A tap that starts
// and ends between two ticks is pressed and released but never held, so
// an action that must not miss one reads pressed. A key held across ticks
// is pressed in the first only; a platform's repeats are not presses.
//
// An action is a set of keys bound to it, any of which does it:
//
//	JUMP :: ui.Keys{.Space, .W, .Up}
//	if input.pressed & JUMP != {} { ... }
Input :: struct {
	tick:     u64, // the tick this is: 0 for the first
	held:     ui.Keys,
	pressed:  ui.Keys,
	released: ui.Keys,
	pointer:  [2]f32, // where the pointer last was, in the game's units
	buttons:  Buttons, // the pointer buttons held
	clicked:  Buttons, // pressed since the tick before
	unclicked: Buttons, // released since the tick before
}

// axis is -1 while any of minus is held, +1 for any of plus, and 0 for
// both or neither: a direction from two actions.
//
//	vel.x = SPEED * game.axis(input, {.Left, .A}, {.Right, .D})
axis :: proc(input: Input, minus, plus: ui.Keys) -> f32 {
	return f32(int(input.held & plus != {})) - f32(int(input.held & minus != {}))
}

// Input_Gather collects the frames' input between ticks: edges add up
// until a tick takes them, so a frame that runs no tick loses none, and a
// frame that runs several gives its edges to the first.
@(private)
Input_Gather :: struct {
	next: Input, // the next tick's input, as it stands
}

// gather_keys adds a frame's key state.
@(private)
gather_keys :: proc(gather: ^Input_Gather, keys: ui.Key_State) {
	gather.next.held = keys.held
	gather.next.pressed += keys.pressed
	gather.next.released += keys.released
}

// gather_pointer adds a pointer event, its pos in the game's units.
@(private)
gather_pointer :: proc(gather: ^Input_Gather, event: ui.Event) {
	#partial switch event.kind {
	case .Press:
		gather.next.buttons += {event.button}
		gather.next.clicked += {event.button}
	case .Release:
		gather.next.buttons -= {event.button}
		gather.next.unclicked += {event.button}
	case .Move:
	case:
		return
	}
	gather.next.pointer = {event.pos.x, event.pos.y}
}

// take_input returns the input for tick and clears the edges it carried.
@(private)
take_input :: proc(gather: ^Input_Gather, tick: u64) -> (input: Input) {
	input = gather.next
	input.tick = tick
	gather.next.pressed, gather.next.released = {}, {}
	gather.next.clicked, gather.next.unclicked = {}, {}
	return
}
