#+build linux, darwin, windows
package sdl

import "base:runtime"
import "core:strings"
import "core:sync"
import "jm:ui"
import ak "jm:ui/accesskit"
import "jm:ui/ops"
import sdl3 "vendor:sdl3"

// The three platform halves are the same four procs over their Adapter.

// Bridge gives a window's semantics to assistive technology through
// AccessKit: after each frame the loop takes a snapshot of the frame's
// nodes and, when it differs from the last one pushed, hands the adapter
// a tree update; the adapter asks for the whole tree through the
// activation handler when a reader connects, and sends the reader's
// requests (focus this, click that) to the action handler (accesskit.h
// 0.23.1, lines 1113-1121). The adapter may call those on another thread
// (line 2995 for Linux, 3117-3119 for Windows), so the snapshot it reads
// and the actions it leaves are under a mutex, and an action wakes the
// loop, which turns it into input before its next frame. The platform's
// adapter is in a11y_<os>.odin: adapter_open, adapter_close,
// adapter_update, adapter_window_focus and adapter_window_bounds.
Bridge :: struct {
	adapter: Adapter, // the platform's, nil without one
	window:  ^sdl3.Window, // the loop's, borrowed for its bounds
	title:   string,
	mu:      sync.Mutex, // guards tree and actions
	tree:    ak.Snapshot, // the tree as last pushed; the adapter's thread builds from it
	next:    ak.Snapshot, // the frame thread's scratch, swapped in when it differs
	actions: [dynamic]Pending_Action, // the reader's requests, until the loop takes them
}

// Pending_Action is one request from the reader: what, of which node.
Pending_Action :: struct {
	action: ak.Action,
	target: ak.Node_Id,
}

// bridge_init connects window's semantics to the platform under title,
// the window node's label. It reports false when the adapter could not be
// made; the loop then runs without one.
bridge_init :: proc(b: ^Bridge, window: ^sdl3.Window, title: string) -> bool {
	b.window = window
	b.title = strings.clone(title)
	ak.snapshot_init(&b.tree)
	ak.snapshot_init(&b.next)
	b.actions = make([dynamic]Pending_Action)
	if !adapter_open(b) {
		bridge_destroy(b)
		return false
	}
	bridge_window_bounds(b)
	return true
}

bridge_destroy :: proc(b: ^Bridge) {
	adapter_close(b)
	ak.snapshot_destroy(&b.tree)
	ak.snapshot_destroy(&b.next)
	delete(b.actions)
	delete(b.title)
	b^ = {}
}

// bridge_frame gives the adapter f, just presented at density, with focus
// the focused area: a changed tree pushes the whole snapshot, a changed
// focus alone pushes only that, the same frame pushes nothing.
bridge_frame :: proc(b: ^Bridge, f: ^ui.Frame, focus: ops.Area_Id, density: f32) {
	if b.adapter == nil {
		return
	}
	ak.snapshot_take(&b.next, f, focus, b.title, 1 / density)
	sync.mutex_lock(&b.mu)
	same := ak.snapshot_equal(&b.tree, &b.next)
	focus_moved := b.tree.focus != b.next.focus
	if !same {
		b.tree, b.next = b.next, b.tree
	} else if focus_moved {
		b.tree.focus = b.next.focus
	}
	sync.mutex_unlock(&b.mu)
	// Outside the lock: the factory runs on this thread and takes it.
	if !same {
		adapter_update(b, build_tree)
	} else if focus_moved {
		adapter_update(b, build_focus)
	}
}

// bridge_take_actions turns the reader's requests since the last call
// into input through sink: a focus request names its area, a click is a
// press and release at the node's middle, as the pointer would make it,
// read from f, the frame the nodes came from.
bridge_take_actions :: proc(b: ^Bridge, f: ^ui.Frame, sink: Event_Sink, user: rawptr) {
	if b.adapter == nil {
		return
	}
	taken: [16]Pending_Action
	n := 0
	sync.mutex_lock(&b.mu)
	n = min(len(b.actions), len(taken))
	copy(taken[:n], b.actions[:n])
	clear(&b.actions)
	sync.mutex_unlock(&b.mu)
	for a in taken[:n] {
		#partial switch a.action {
		case .Focus:
			sink(user, {kind = .Focus, area = ops.Area_Id(a.target)})
		case .Click:
			for node in f.nodes {
				if ak.Node_Id(node.id) != a.target {
					continue
				}
				at := ops.Point{node.rect.x + node.rect.w / 2, node.rect.y + node.rect.h / 2}
				sink(user, {kind = .Move, pos = at})
				sink(user, {kind = .Press, pos = at, button = .Left, clicks = 1})
				sink(user, {kind = .Release, pos = at, button = .Left, clicks = 1})
				break
			}
		}
	}
}

// bridge_window_focus tells the adapter the window gained or lost
// keyboard focus, where the adapter does not watch that itself.
bridge_window_focus :: proc(b: ^Bridge, focused: bool) {
	if b != nil && b.adapter != nil {
		adapter_window_focus(b, focused)
	}
}

// bridge_window_bounds tells the adapter where the window is on the
// screen, where the adapter does not watch that itself.
bridge_window_bounds :: proc(b: ^Bridge) {
	if b != nil && b.adapter != nil {
		adapter_window_bounds(b)
	}
}

// The adapter's callbacks: on its thread for activation, action and
// deactivation; on the loop's for the factories update_if_active runs.

@(private)
build_tree :: proc "c" (userdata: rawptr) -> ^ak.Tree_Update {
	context = runtime.default_context()
	b := (^Bridge)(userdata)
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	return ak.tree_update(&b.tree)
}

@(private)
build_focus :: proc "c" (userdata: rawptr) -> ^ak.Tree_Update {
	b := (^Bridge)(userdata)
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	return ak.tree_update_with_focus(b.tree.focus)
}

@(private)
on_activate :: proc "c" (userdata: rawptr) -> ^ak.Tree_Update {
	return build_tree(userdata)
}

@(private)
on_action :: proc "c" (request: ^ak.Action_Request, userdata: rawptr) {
	context = runtime.default_context()
	b := (^Bridge)(userdata)
	sync.mutex_lock(&b.mu)
	append(&b.actions, Pending_Action{request.action, request.target_node})
	sync.mutex_unlock(&b.mu)
	ak.action_request_free(request)
	wake()
}

@(private)
on_deactivate :: proc "c" (userdata: rawptr) {
	// The tree stays as it is: the next reader asks for it afresh.
}
