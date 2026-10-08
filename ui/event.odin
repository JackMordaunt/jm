package ui

import "jm:ui/ops"

// Events, as widgets see them. Event_Kind and Event_Kinds are sc', since
// an Input_Area op says which kinds its area wants.

// Button, Key, Mod and Mods are ops', since a Key_Interest op names
// them; widgets spell them ui.Key and ui.Mods as before.
Button :: ops.Button
Key :: ops.Key
Mod :: ops.Mod
Mods :: ops.Mods

Event :: struct {
	kind:   ops.Event_Kind,
	area:   ops.Area_Id,
	pos:    ops.Point, // local to the area for pointer kinds
	travel: ops.Point, // pointer kinds: how far the pointer moved since the previous pointer event, in local units. Unlike differences of pos, it does not change when the area itself moves between frames, so a drag that moves its own widget adds it up without feeding back.
	button: Button,
	scroll: [2]f32,
	key:    Key, // Focus: the key that moved focus (Tab, an arrow), None for a press or request
	mods:   Mods,
	text:   string, // Text: the inserted UTF-8; Paste: the clipboard's bytes; Compose: the preedit
	mime:   string, // Paste: the type of text
	clicks: u8, // Press: 1 for a single click, 2 for a double, 3 a triple, as the OS counts them
	span:   [2]int, // Compose: the input method's caret (equal ends) or selection in text, byte offsets
	time:   f64, // seconds on the platform's monotonic clock when the device made it, for velocities; only differences mean anything, and 0 is unknown
}

// Raw_Event is what a platform (ui/shell, the probe) feeds the router: the
// same fields as Event but with pos in device pixels and, for a pointer
// or key event, no area: the router resolves it and converts pos to local
// space. A Focus carries the area to focus, as an assistive technology
// asks for one; the router focuses it as focus_request would. One pushed
// with time 0 takes the router's now.
Raw_Event :: struct {
	kind:   ops.Event_Kind,
	area:   ops.Area_Id, // Focus, Picked, Expand and Collapse: the area it is for
	pos:    ops.Point,
	button: Button,
	scroll: [2]f32,
	key:    Key,
	mods:   Mods,
	text:   string,
	mime:   string,
	clicks: u8,
	span:   [2]int,
	time:   f64,
}

// SHORTCUT is the platform's command modifier, Cmd on macOS and Ctrl
// elsewhere: copy is SHORTCUT+C. WORD_MOD moves and deletes by word with
// the arrows and Backspace: Option on macOS, Ctrl elsewhere. The child
// and its host run on one machine, so the build's OS is the right one.
when ODIN_OS == .Darwin {
	SHORTCUT :: Mod.Super
	WORD_MOD :: Mod.Alt
} else {
	SHORTCUT :: Mod.Ctrl
	WORD_MOD :: Mod.Ctrl
}
