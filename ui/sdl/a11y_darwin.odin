#+build darwin
package sdl

import ak "jm:ui/accesskit"
import sdl3 "vendor:sdl3"

// macOS: AccessKit's subclassing adapter over NSAccessibility, on the
// window's NSWindow. SDL3's window class is SDL3Window (SDL's
// src/video/cocoa/SDL_cocoawindow.m); it gets AccessKit's focus
// forwarder once per process, so the window's key view answers for it.
Adapter :: ^ak.Macos_Subclassing_Adapter

@(private = "file")
forwarder_added: bool

adapter_open :: proc(b: ^Bridge) -> bool {
	window := sdl3.GetPointerProperty(sdl3.GetWindowProperties(b.window), sdl3.PROP_WINDOW_COCOA_WINDOW_POINTER, nil)
	if window == nil {
		return false
	}
	if !forwarder_added {
		ak.macos_add_focus_forwarder_to_window_class("SDL3Window")
		forwarder_added = true
	}
	b.adapter = ak.macos_subclassing_adapter_for_window(window, on_activate, b, on_action, b)
	return b.adapter != nil
}

adapter_close :: proc(b: ^Bridge) {
	if b.adapter != nil {
		ak.macos_subclassing_adapter_free(b.adapter)
		b.adapter = nil
	}
}

adapter_update :: proc(b: ^Bridge, factory: ak.Tree_Update_Factory) {
	if events := ak.macos_subclassing_adapter_update_if_active(b.adapter, factory, b); events != nil {
		ak.macos_queued_events_raise(events)
	}
}

adapter_window_focus :: proc(b: ^Bridge, focused: bool) {
	if events := ak.macos_subclassing_adapter_update_view_focus_state(b.adapter, focused); events != nil {
		ak.macos_queued_events_raise(events)
	}
}

adapter_window_bounds :: proc(b: ^Bridge) {
	// NSAccessibility asks the view for its frame itself.
}
