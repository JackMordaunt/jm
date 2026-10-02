#+build linux, darwin, windows
package accesskit

import "core:c"

// Linux and macOS link the release's static archive; Windows its DLL
// through the import library beside it, so the DLL must sit next to the
// executable. Rust's msvc static libraries take the dynamic C runtime
// unless built with crt-static, and Odin links the static one, so the DLL
// sidesteps the mismatch rather than testing it. The adapters are in
// api_<os>.odin.
when ODIN_OS == .Windows {
	foreign import lib "lib/accesskit.lib"
} else when ODIN_OS == .Darwin {
	foreign import lib {"lib/libaccesskit.a", "system:AppKit.framework", "system:Foundation.framework"}
} else {
	foreign import lib "lib/libaccesskit.a"
}

// Opaque to us: the header declares them without a body, and makes and
// frees them (node_new, tree_update_free; an update takes its nodes).
Node :: struct {}
Tree_Update :: struct {}
Tree_Info :: struct {}

Tree_Id :: struct {
	bytes: [16]u8,
}

// Action_Request is what the assistive technology asks of a node. The
// request carries optional data after target_node (a value, a point, a
// selection) that this binding leaves to the header: the bridge reads
// action and target_node only.
Action_Request :: struct {
	action:      Action,
	target_tree: Tree_Id,
	target_node: Node_Id,
}

// An activation handler returns the whole tree, an action handler takes
// a request it must free (accesskit.h 0.23.1, line 1117: ownership of the
// request is transferred to the callback), a deactivation handler hears
// the assistive technology go away. Which thread calls them is the
// adapter's: another thread on Linux (line 2995), the window's for
// activation on Windows and possibly another for actions (lines
// 3117-3119), the main thread on macOS.
Tree_Update_Factory :: #type proc "c" (userdata: rawptr) -> ^Tree_Update
Activation_Handler :: #type proc "c" (userdata: rawptr) -> ^Tree_Update
Action_Handler :: #type proc "c" (request: ^Action_Request, userdata: rawptr)
Deactivation_Handler :: #type proc "c" (userdata: rawptr)

@(default_calling_convention = "c", link_prefix = "accesskit_")
foreign lib {
	node_new :: proc(role: Role) -> ^Node ---
	node_free :: proc(node: ^Node) ---
	node_set_role :: proc(node: ^Node, role: Role) ---
	node_set_label :: proc(node: ^Node, value: cstring) ---
	node_set_description :: proc(node: ^Node, value: cstring) ---
	node_set_value :: proc(node: ^Node, value: cstring) ---
	node_set_labelled_by :: proc(node: ^Node, length: c.size_t, values: [^]Node_Id) ---
	node_set_bounds :: proc(node: ^Node, value: Rect) ---
	node_set_toggled :: proc(node: ^Node, value: Toggled) ---
	node_set_selected :: proc(node: ^Node, value: bool) ---
	node_set_expanded :: proc(node: ^Node, value: bool) ---
	node_set_disabled :: proc(node: ^Node) ---
	node_set_read_only :: proc(node: ^Node) ---
	node_set_required :: proc(node: ^Node) ---
	node_set_invalid :: proc(node: ^Node, value: Invalid) ---
	node_set_busy :: proc(node: ^Node) ---
	node_set_modal :: proc(node: ^Node) ---
	node_set_hidden :: proc(node: ^Node) ---
	node_set_live :: proc(node: ^Node, value: Live) ---
	node_set_level :: proc(node: ^Node, value: c.size_t) ---
	node_push_child :: proc(node: ^Node, item: Node_Id) ---
	node_add_action :: proc(node: ^Node, action: Action) ---
	// The caller frees the string with string_free.
	node_debug :: proc(node: ^Node) -> cstring ---

	tree_update_with_focus :: proc(focus: Node_Id) -> ^Tree_Update ---
	tree_update_with_capacity_and_focus :: proc(capacity: c.size_t, focus: Node_Id) -> ^Tree_Update ---
	tree_update_free :: proc(update: ^Tree_Update) ---
	// The update takes the node: do not free it after.
	tree_update_push_node :: proc(update: ^Tree_Update, id: Node_Id, node: ^Node) ---
	// The update takes the tree info.
	tree_update_set_tree_info :: proc(update: ^Tree_Update, tree: ^Tree_Info) ---
	// The caller frees the string with string_free.
	tree_update_debug :: proc(update: ^Tree_Update) -> cstring ---
	tree_info_new :: proc(root: Node_Id) -> ^Tree_Info ---
	tree_info_free :: proc(tree: ^Tree_Info) ---
	string_free :: proc(s: cstring) ---
	action_request_free :: proc(request: ^Action_Request) ---
}
