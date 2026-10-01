#+build linux
package sdl

import "base:runtime"
import "core:strings"
import "core:sync"
import "jm:ui"
import ak "jm:ui/accesskit"
import "jm:ui/ops"
import sdl3 "vendor:sdl3"

// Bridge gives a window's semantics to assistive technology through
// AccessKit's Unix adapter (AT-SPI2): after each frame the loop takes a
// snapshot of the frame's nodes and, when it differs from the last one
// pushed, hands the adapter a tree update; the adapter asks for the whole
// tree through the activation handler when a reader connects, and sends
// the reader's requests (focus this, click that) to the action handler
// (accesskit.h 0.23.1, lines 1113-1121). It calls those on its own thread
// (line 2995), so the snapshot it reads and the actions it leaves are
// under a mutex, and an action wakes the loop, which turns it into input
// before its next frame.
Bridge :: struct {
	adapter: ^ak.Unix_Adapter,
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
	b.adapter = ak.unix_adapter_new(on_activate, b, on_action, b, on_deactivate, b)
	if b.adapter == nil {
		bridge_destroy(b)
		return false
	}
	bridge_window_bounds(b)
	return true
}

bridge_destroy :: proc(b: ^Bridge) {
	if b.adapter != nil {
		ak.unix_adapter_free(b.adapter)
	}
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
		ak.unix_adapter_update_if_active(b.adapter, build_tree, b)
	} else if focus_moved {
		ak.unix_adapter_update_if_active(b.adapter, build_focus, b)
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
// keyboard focus; a reader follows the focused window.
bridge_window_focus :: proc(b: ^Bridge, focused: bool) {
	if b != nil && b.adapter != nil {
		ak.unix_adapter_update_window_focus_state(b.adapter, focused)
	}
}

// bridge_window_bounds tells the adapter where the window is on the
// screen, with and without its frame, so node bounds place on it.
bridge_window_bounds :: proc(b: ^Bridge) {
	if b == nil || b.adapter == nil {
		return
	}
	x, y, w, h, top, left, bottom, right: i32
	sdl3.GetWindowPosition(b.window, &x, &y)
	sdl3.GetWindowSize(b.window, &w, &h)
	sdl3.GetWindowBordersSize(b.window, &top, &left, &bottom, &right)
	outer := ak.Rect{f64(x - left), f64(y - top), f64(x + w + right), f64(y + h + bottom)}
	inner := ak.Rect{f64(x), f64(y), f64(x + w), f64(y + h)}
	ak.unix_adapter_set_root_window_bounds(b.adapter, outer, inner)
}

// The adapter's callbacks: on its thread for activation, action and
// deactivation; on the loop's for the factories update_if_active runs.

@(private = "file")
build_tree :: proc "c" (userdata: rawptr) -> ^ak.Tree_Update {
	context = runtime.default_context()
	b := (^Bridge)(userdata)
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	return ak.tree_update(&b.tree)
}

@(private = "file")
build_focus :: proc "c" (userdata: rawptr) -> ^ak.Tree_Update {
	b := (^Bridge)(userdata)
	sync.mutex_lock(&b.mu)
	defer sync.mutex_unlock(&b.mu)
	return ak.tree_update_with_focus(b.tree.focus)
}

@(private = "file")
on_activate :: proc "c" (userdata: rawptr) -> ^ak.Tree_Update {
	return build_tree(userdata)
}

@(private = "file")
on_action :: proc "c" (request: ^ak.Action_Request, userdata: rawptr) {
	context = runtime.default_context()
	b := (^Bridge)(userdata)
	sync.mutex_lock(&b.mu)
	append(&b.actions, Pending_Action{request.action, request.target_node})
	sync.mutex_unlock(&b.mu)
	ak.action_request_free(request)
	wake()
}

@(private = "file")
on_deactivate :: proc "c" (userdata: rawptr) {
	// The tree stays as it is: the next reader asks for it afresh.
}
