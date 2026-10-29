#+build darwin
package shell

import "base:intrinsics"
import "core:log"
import NS "core:sys/darwin/Foundation"
import sdl3 "vendor:sdl3"

import "jm:ui"
import "jm:ui/ops"

// The native buttons and the client's toolbar share a 52-point strip.
@(private)
TITLE_MAC_HEIGHT :: f32(52)

@(private)
title_attach :: proc(w: ^Window) -> bool {
	if w.title_mode != .Unified || w.window == nil {
		return true
	}
	raw := sdl3.GetPointerProperty(sdl3.GetWindowProperties(w.window), sdl3.PROP_WINDOW_COCOA_WINDOW_POINTER, nil)
	if raw == nil || !sdl3.SetWindowHitTest(w.window, title_mac_hit, w) {
		log.warn("ui/shell: could not attach the unified macOS title bar")
		return false
	}
	if !title_mac_watch(w) {
		_ = sdl3.SetWindowHitTest(w.window, nil, nil)
		return false
	}
	w.cocoa_window = raw
	w.title_on = true
	_ = title_metrics(w)
	return true
}

@(private)
title_detach :: proc(w: ^Window) {
	if w.title_on {
		_ = sdl3.SetWindowHitTest(w.window, nil, nil)
	}
	title_mac_unwatch(w)
	w.title_on = false
	w.cocoa_window = nil
}

// AppKit lays the title bar out again on resize and when returning from
// fullscreen. Size the native buttons' container to the toolbar each time;
// the native buttons keep their targets, hover groups and accessibility.
// No toolbar is installed: an NSToolbar would intercept the client's tools.
@(private)
title_metrics :: proc(w: ^Window) -> ui.Title_Bar {
	if !w.title_on || w.cocoa_window == nil || .FULLSCREEN in sdl3.GetWindowFlags(w.window) {
		return {}
	}
	native := cast(^NS.Window)w.cocoa_window
	style := intrinsics.objc_send(NS.WindowStyleMask, native, "styleMask")
	if .FullScreen in style {
		return {}
	}
	content := native->contentView()
	if content == nil {
		return {}
	}
	if .FullSizeContentView not_in style {
		// SDL keeps its event listener in the content view's responder chain.
		// AppKit rewrites that chain when the style changes, so detach and
		// restore it just as SDL's own SetWindowStyle does.
		responder := intrinsics.objc_send(NS.id, content, "nextResponder")
		intrinsics.objc_send(nil, content, "setNextResponder:", NS.id(nil))
		intrinsics.objc_send(nil, native, "setStyleMask:", style + {.FullSizeContentView})
		intrinsics.objc_send(nil, content, "setNextResponder:", responder)
		intrinsics.objc_send(nil, native, "setTitleVisibility:", NS.Integer(1)) // NSWindowTitleHidden
		intrinsics.objc_send(nil, native, "setTitlebarAppearsTransparent:", NS.BOOL(true))
	}
	bounds := content->bounds()
	right: f32
	for kind in 0 ..< 3 { // NSWindowCloseButton, NSWindowMiniaturizeButton, NSWindowZoomButton
		button := intrinsics.objc_send(^NS.View, native, "standardWindowButton:", NS.UInteger(kind))
		if button == nil {
			continue
		}
		parent := intrinsics.objc_send(^NS.View, button, "superview")
		container := intrinsics.objc_send(^NS.View, parent, "superview")
		if parent == nil || container == nil {
			continue
		}
		frame := intrinsics.objc_send(NS.Rect, container, "frame")
		if frame.size.height != NS.Float(TITLE_MAC_HEIGHT) {
			frame.origin.y += frame.size.height - NS.Float(TITLE_MAC_HEIGHT)
			frame.size.height = NS.Float(TITLE_MAC_HEIGHT)
			intrinsics.objc_send(nil, container, "setFrame:", frame)
		}
		frame = intrinsics.objc_send(NS.Rect, button, "frame")
		// Convert through the content view: the native title view is flipped
		// on some systems, while SDL's content view is bottom-up.
		r := intrinsics.objc_send(NS.Rect, content, "convertRect:fromView:", button->bounds(), button)
		delta := bounds.size.height - NS.Float(TITLE_MAC_HEIGHT) / 2 - (r.origin.y + r.size.height / 2)
		if parent->isFlipped() {
			frame.origin.y -= delta
		} else {
			frame.origin.y += delta
		}
		if delta != 0 {
			intrinsics.objc_send(nil, button, "setFrame:", frame)
		}
		r = intrinsics.objc_send(NS.Rect, content, "convertRect:fromView:", button->bounds(), button)
		right = max(right, f32(r.origin.x + r.size.width))
	}
	return {
		height = TITLE_MAC_HEIGHT,
		buttons = {0, 0, right, TITLE_MAC_HEIGHT},
		maximized = bool(intrinsics.objc_send(NS.BOOL, native, "isZoomed")),
		active = bool(intrinsics.objc_send(NS.BOOL, native, "isKeyWindow")),
	}
}

// SDL asks in window points; the frame's published drag rects are pixels.
// Its Cocoa backend hands these regions to AppKit's background dragging,
// retaining native dragging. The event monitor below handles double-clicks.
@(private)
title_mac_hit :: proc "c" (_: ^sdl3.Window, area: ^sdl3.Point, data: rawptr) -> sdl3.HitTestResult {
	w := cast(^Window)data
	if w == nil || !w.title_on || area == nil || .FULLSCREEN in sdl3.GetWindowFlags(w.window) {
		return .NORMAL
	}
	return title_mac_drag(w, area)
}

@(private)
title_mac_drag :: proc "contextless" (w: ^Window, area: ^sdl3.Point) -> sdl3.HitTestResult {
	d := w.density if w.density > 0 else 1
	p := ops.Point{f32(area.x) * d, f32(area.y) * d}
	slot := w.drag_read
	for r in w.drags[slot][:w.drag_n[slot]] {
		if title_contains(r, p) {
			return .DRAGGABLE
		}
	}
	return .NORMAL
}

// SDL background dragging consumes the click without performing the title
// bar's double-click action. A local monitor handles only double-clicks in
// published drag regions, leaving native buttons and client controls alone.
@(private)
Title_Mac_Block :: struct {
	isa: ^intrinsics.objc_class,
	flags: u32,
	reserved: u32,
	invoke: proc "c" (block: ^Title_Mac_Block, event: ^NS.Event) -> ^NS.Event,
	descriptor: ^Title_Mac_Descriptor,
	window: ^Window,
	monitor: rawptr,
}

@(private)
Title_Mac_Descriptor :: struct {
	reserved: uint,
	size: uint,
}

@(private)
title_mac_descriptor := Title_Mac_Descriptor{size = size_of(Title_Mac_Block)}

@(private)
title_mac_watch :: proc(w: ^Window) -> bool {
	block := new(Title_Mac_Block)
	block^ = {isa = &_NSConcreteGlobalBlock, flags = 1 << 28, invoke = title_mac_event, descriptor = &title_mac_descriptor, window = w}
	block.monitor = intrinsics.objc_send(rawptr, NS.Event, "addLocalMonitorForEventsMatchingMask:handler:", u64(1) << 2, block)
	if block.monitor == nil {
		free(block)
		log.warn("ui/shell: could not watch title-bar double-clicks")
		return false
	}
	w.cocoa_title_events = block
	return true
}

@(private)
title_mac_unwatch :: proc(w: ^Window) {
	block := cast(^Title_Mac_Block)w.cocoa_title_events
	if block != nil {
		intrinsics.objc_send(nil, NS.Event, "removeMonitor:", block.monitor)
		free(block)
		w.cocoa_title_events = nil
	}
}

@(private)
title_mac_event :: proc "c" (block: ^Title_Mac_Block, event: ^NS.Event) -> ^NS.Event {
	w := block.window
	if !w.title_on || event->clickCount() != 2 || intrinsics.objc_send(rawptr, event, "window") != w.cocoa_window || .FULLSCREEN in sdl3.GetWindowFlags(w.window) {
		return event
	}
	native := cast(^NS.Window)w.cocoa_window
	content := native->contentView()
	location := event->locationInWindow()
	point := sdl3.Point{i32(location.x), i32(content->bounds().size.height - location.y)}
	if title_mac_drag(w, &point) != .DRAGGABLE {
		return event
	}
	defaults := NS.UserDefaults_standardUserDefaults()
	action := intrinsics.objc_send(^NS.String, defaults, "stringForKey:", NS.MakeConstantString("AppleActionOnDoubleClick"))
	selected := title_mac_action(action)
	if action == nil && intrinsics.objc_send(NS.BOOL, defaults, "boolForKey:", NS.MakeConstantString("AppleMiniaturizeOnDoubleClick")) {
		selected = .Minimize
	}
	switch selected {
	case .Minimize:
		intrinsics.objc_send(nil, native, "performMiniaturize:", NS.id(nil))
	case .Zoom:
		// SDL has no document-specific standard frame: Zoom fills the work
		// area, which is also the Fill preference's result for this window.
		intrinsics.objc_send(nil, native, "performZoom:", NS.id(nil))
	case .None:
	}
	return nil
}

@(private)
Title_Mac_Action :: enum { None, Minimize, Zoom }

@(private)
title_mac_action :: proc "contextless" (action: ^NS.String) -> Title_Mac_Action {
	if action == nil {
		return .Zoom
	}
	if intrinsics.objc_send(NS.BOOL, action, "isEqualToString:", NS.MakeConstantString("Minimize")) {
		return .Minimize
	}
	if intrinsics.objc_send(NS.BOOL, action, "isEqualToString:", NS.MakeConstantString("Maximize")) || intrinsics.objc_send(NS.BOOL, action, "isEqualToString:", NS.MakeConstantString("Fill")) {
		return .Zoom
	}
	return .None
}
