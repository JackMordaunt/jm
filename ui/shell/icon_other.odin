#+build !windows
package shell

import sdl3 "vendor:sdl3"

// icon_present sets the window icon from s. The desktop scales it.
@(private)
icon_present :: proc(w: ^Window, s: ^sdl3.Surface) -> bool {
	return sdl3.SetWindowIcon(w.window, s)
}

@(private)
icon_release :: proc(_: ^Window) {}
