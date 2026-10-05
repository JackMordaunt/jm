#+build linux
package shell

import ak "jm:ui/accesskit"
import sdl3 "vendor:sdl3"

// Linux: AccessKit's Unix adapter, AT-SPI2 over D-Bus. It needs no window
// handle, but is told the window's place and focus.
Adapter :: ^ak.Unix_Adapter

adapter_open :: proc(b: ^Bridge) -> bool {
	b.adapter = ak.unix_adapter_new(on_activate, b, on_action, b, on_deactivate, b)
	return b.adapter != nil
}

adapter_close :: proc(b: ^Bridge) {
	if b.adapter != nil {
		ak.unix_adapter_free(b.adapter)
		b.adapter = nil
	}
}

adapter_update :: proc(b: ^Bridge, factory: ak.Tree_Update_Factory) {
	ak.unix_adapter_update_if_active(b.adapter, factory, b)
}

adapter_window_focus :: proc(b: ^Bridge, focused: bool) {
	ak.unix_adapter_update_window_focus_state(b.adapter, focused)
}

// adapter_window_bounds gives the window's place on the screen, with
// and without its frame, so node bounds place on it.
adapter_window_bounds :: proc(b: ^Bridge) {
	x, y, w, h, top, left, bottom, right: i32
	sdl3.GetWindowPosition(b.window, &x, &y)
	sdl3.GetWindowSize(b.window, &w, &h)
	sdl3.GetWindowBordersSize(b.window, &top, &left, &bottom, &right)
	outer := ak.Rect{f64(x - left), f64(y - top), f64(x + w + right), f64(y + h + bottom)}
	inner := ak.Rect{f64(x), f64(y), f64(x + w), f64(y + h)}
	ak.unix_adapter_set_root_window_bounds(b.adapter, outer, inner)
}
