#+build windows
package shell

import ak "jm:ui/accesskit"
import sdl3 "vendor:sdl3"

// Windows: AccessKit's subclassing adapter over UI Automation, attached
// to the window's HWND before the window is shown (open makes it hidden;
// the loops show it after the bridge is up). It sees the window's own
// messages, so focus and place need no telling: accesskit-c 0.23.1's
// examples/sdl/hello_world.c updates neither on Windows.
Adapter :: ^ak.Windows_Subclassing_Adapter

adapter_open :: proc(b: ^Bridge) -> bool {
	hwnd := sdl3.GetPointerProperty(sdl3.GetWindowProperties(b.window), sdl3.PROP_WINDOW_WIN32_HWND_POINTER, nil)
	if hwnd == nil {
		return false
	}
	b.adapter = ak.windows_subclassing_adapter_new(hwnd, on_activate, b, on_action, b)
	return b.adapter != nil
}

adapter_close :: proc(b: ^Bridge) {
	if b.adapter != nil {
		ak.windows_subclassing_adapter_free(b.adapter)
		b.adapter = nil
	}
}

adapter_update :: proc(b: ^Bridge, factory: ak.Tree_Update_Factory) {
	if events := ak.windows_subclassing_adapter_update_if_active(b.adapter, factory, b); events != nil {
		ak.windows_queued_events_raise(events)
	}
}

adapter_window_focus :: proc(b: ^Bridge, focused: bool) {
	// The subclassing adapter sees the window's focus messages itself.
}

adapter_window_bounds :: proc(b: ^Bridge) {
	// Likewise its moves and sizes.
}
