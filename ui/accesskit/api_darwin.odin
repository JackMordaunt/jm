#+build darwin
package accesskit

foreign import lib {"lib/libaccesskit.a", "system:AppKit.framework", "system:Foundation.framework"}

// Macos_Subclassing_Adapter speaks NSAccessibility by subclassing the
// window's content view; its handlers run on the main thread (accesskit.h
// 0.23.1, lines 2741-2759). An update or a focus change returns queued
// events the caller raises (lines 2926-2947). The window class gets a
// focus forwarder once per process (lines 2950-2967), so the view under
// it answers for the window.
Macos_Subclassing_Adapter :: struct {}
Macos_Queued_Events :: struct {}

@(default_calling_convention = "c", link_prefix = "accesskit_")
foreign lib {
	macos_add_focus_forwarder_to_window_class :: proc(class_name: cstring) ---
	macos_subclassing_adapter_for_window :: proc(window: rawptr, activation: Activation_Handler, activation_userdata: rawptr, action: Action_Handler, action_userdata: rawptr) -> ^Macos_Subclassing_Adapter ---
	macos_subclassing_adapter_free :: proc(adapter: ^Macos_Subclassing_Adapter) ---
	// Null when the adapter is not active; else the caller must raise it
	// (lines 2926-2935).
	macos_subclassing_adapter_update_if_active :: proc(adapter: ^Macos_Subclassing_Adapter, factory: Tree_Update_Factory, userdata: rawptr) -> ^Macos_Queued_Events ---
	macos_subclassing_adapter_update_view_focus_state :: proc(adapter: ^Macos_Subclassing_Adapter, is_focused: bool) -> ^Macos_Queued_Events ---
	// Frees the events as well.
	macos_queued_events_raise :: proc(events: ^Macos_Queued_Events) ---
}
