#+build linux
package accesskit

foreign import lib "lib/libaccesskit.a"

// Unix_Adapter speaks AT-SPI2 over D-Bus. Its handlers run on its own
// thread (accesskit.h 0.23.1, line 2995).
Unix_Adapter :: struct {}

@(default_calling_convention = "c", link_prefix = "accesskit_")
foreign lib {
	unix_adapter_new :: proc(activation: Activation_Handler, activation_userdata: rawptr, action: Action_Handler, action_userdata: rawptr, deactivation: Deactivation_Handler, deactivation_userdata: rawptr) -> ^Unix_Adapter ---
	unix_adapter_free :: proc(adapter: ^Unix_Adapter) ---
	unix_adapter_set_root_window_bounds :: proc(adapter: ^Unix_Adapter, outer, inner: Rect) ---
	// The header (0.23.1, the Unix adapter section) names it: the update
	// is built and pushed only while the adapter is active, that is while
	// an assistive technology has asked for the tree.
	unix_adapter_update_if_active :: proc(adapter: ^Unix_Adapter, factory: Tree_Update_Factory, userdata: rawptr) ---
	unix_adapter_update_window_focus_state :: proc(adapter: ^Unix_Adapter, is_focused: bool) ---
}
