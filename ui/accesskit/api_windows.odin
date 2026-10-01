#+build windows
package accesskit

foreign import lib "lib/accesskit.lib"

// Windows_Subclassing_Adapter speaks UI Automation by subclassing the
// window: it must be made before the window is first shown, on the
// window's thread, and it calls the activation handler there and the
// action handler there or elsewhere (accesskit.h 0.23.1, lines
// 3110-3124). It keeps window focus itself. An update returns queued
// events the caller raises.
Windows_Subclassing_Adapter :: struct {}
Windows_Queued_Events :: struct {}

@(default_calling_convention = "c", link_prefix = "accesskit_")
foreign lib {
	windows_subclassing_adapter_new :: proc(hwnd: rawptr, activation: Activation_Handler, activation_userdata: rawptr, action: Action_Handler, action_userdata: rawptr) -> ^Windows_Subclassing_Adapter ---
	windows_subclassing_adapter_free :: proc(adapter: ^Windows_Subclassing_Adapter) ---
	// Null when the adapter is not active; else the caller must raise it.
	windows_subclassing_adapter_update_if_active :: proc(adapter: ^Windows_Subclassing_Adapter, factory: Tree_Update_Factory, userdata: rawptr) -> ^Windows_Queued_Events ---
	// Frees the events as well.
	windows_queued_events_raise :: proc(events: ^Windows_Queued_Events) ---
}
