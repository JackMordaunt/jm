#+build !linux
package sdl

import "jm:ui"
import "jm:ui/ops"
import sdl3 "vendor:sdl3"

// Bridge is the Linux one's stand-in where no AccessKit adapter is wired
// yet (see a11y_linux.odin): it connects nothing, and every call on it
// does nothing.
Bridge :: struct {
	window: ^sdl3.Window,
}

bridge_init :: proc(b: ^Bridge, window: ^sdl3.Window, title: string) -> bool {
	b.window = window
	return false
}

bridge_destroy :: proc(b: ^Bridge) {
	b^ = {}
}

bridge_frame :: proc(b: ^Bridge, f: ^ui.Frame, focus: ops.Area_Id, density: f32) {
}

bridge_take_actions :: proc(b: ^Bridge, f: ^ui.Frame, sink: Event_Sink, user: rawptr) {
}

bridge_window_focus :: proc(b: ^Bridge, focused: bool) {
}

bridge_window_bounds :: proc(b: ^Bridge) {
}
