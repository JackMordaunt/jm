package ui

import "jm:ui/ops"

// Events, as widgets see them. Event_Kind and Event_Kinds are sc', since
// an Input_Area op says which kinds its area wants.

Button :: enum u8 {
	Left,
	Right,
	Middle,
}

Key :: enum u8 {
	None,
	Enter,
	Escape,
	Tab,
	Backspace,
	Delete,
	Left,
	Right,
	Up,
	Down,
	Home,
	End,
	Page_Up,
	Page_Down,
	Space,
	A, B, C, D, E, F, G, H, I, J, K, L, M,
	N, O, P, Q, R, S, T, U, V, W, X, Y, Z,
	N0, N1, N2, N3, N4, N5, N6, N7, N8, N9,
	F11, // DEBUG_TOGGLE_KEY: the frame loops take it before routing
}

Mod :: enum u8 {
	Shift,
	Ctrl,
	Alt,
	Super,
}

Mods :: bit_set[Mod;u8]

Event :: struct {
	kind:   ops.Event_Kind,
	area:   ops.Area_Id,
	pos:    ops.Point, // local to the area for pointer kinds
	travel: ops.Point, // pointer kinds: how far the pointer moved since the previous pointer event, in local units. Unlike differences of pos, it does not change when the area itself moves between frames, so a drag that moves its own widget adds it up without feeding back.
	button: Button,
	scroll: [2]f32,
	key:    Key,
	mods:   Mods,
	text:   string, // Text kind: the inserted UTF-8
}

// Raw_Event is what a platform (ui/sdl, the probe) feeds the router: the
// same fields as Event but with pos in device pixels and no area. The router
// resolves the area and converts pos to local space.
Raw_Event :: struct {
	kind:   ops.Event_Kind,
	pos:    ops.Point,
	button: Button,
	scroll: [2]f32,
	key:    Key,
	mods:   Mods,
	text:   string,
}
