#+build !darwin
package shell

import "vendor:sdl3"

// Closing the window quits here, as a window's close button does on
// Windows and Linux; close_darwin.odin keeps the application for the Dock.

// close_window closes the window as Windows and Linux do: the application quits.
@(private)
close_window :: proc(w: ^Window) -> (kept: bool) {
	return false
}

@(private)
reopen_watch :: proc() {}

@(private)
reopened :: proc(w: ^Window, e: ^sdl3.Event) -> bool {
	return false
}
