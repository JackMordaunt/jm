#+build windows
package sdl

import win "core:sys/windows"

// wait_for_compositor blocks until the desktop compositor has composed the
// frame just presented. During a resize that keeps Windows from showing the
// window at its next size before the frame drawn for this one is on screen.
@(private)
wait_for_compositor :: proc() {
	_ = win.DwmFlush()
}
