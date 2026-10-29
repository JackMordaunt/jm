#+build darwin
package shell

import "base:intrinsics"
import "core:fmt"
import "core:os"
import NS "core:sys/darwin/Foundation"
import "core:time"
import sdl3 "vendor:sdl3"

import "jm:ui/ops"

// AppKit needs the process's main thread, whereas odin test runs its tests
// on worker threads. This opt-in executable exercises the real shell without
// exporting private window state or injecting source into the package:
//
// odin run ui/shell -collection:jm=. -define:JM_UI_NATIVE_TITLE_TEST=true \
//     -- -AppleActionOnDoubleClick Maximize
//
// The preference arguments live only in NSArgumentDomain for this process.
// Leita's tools/macos/test_titlebar.py builds it with the normal SDL link flags
// and runs Maximize, Fill, Minimize and None in separate, bounded processes.
when #config(JM_UI_NATIVE_TITLE_TEST, false) {
	main :: proc() {
		native_title_test()
	}
}

// Keep helpers type-checked in ordinary shell builds too; only the opt-in
// main above executes them. The linker drops them from applications.
@(private = "file")
native_title_test :: proc() {
	assert(len(os.args) == 3, "pass -AppleActionOnDoubleClick Maximize, Fill, Minimize or None")
	preference := os.args[2]
	assert(sdl3.Init({.VIDEO}), "SDL video initialises on the main thread")
	defer sdl3.Quit()
	scroll_watch_start()
	defer scroll_watch_stop()

	w: Window
	assert(
		open(
			&w,
			{
				title = "Native title-bar regression",
				width = 900,
				height = 600,
				title_bar = .Unified,
			},
		),
	)
	defer close(&w)
	assert(
		w.title_on && w.cocoa_title_events != nil,
		"the native title bar and event monitor attach",
	)
	assert(sdl3.ShowWindow(w.window))
	native_title_settle(&w)
	native_title_layout(&w)
	fmt.println("PASS initial native button alignment and hit targets; display density", w.density)

	assert(sdl3.SetWindowSize(w.window, 640, 420))
	native_title_settle(&w)
	native_title_layout(&w)
	fmt.println("PASS resized native button alignment and client hit targets")

	// Leave drag regions published during fullscreen: an old frame must
	// not make the top of the fullscreen client draggable.
	native_title_publish(&w)
	assert(sdl3.SetWindowFullscreen(w.window, true))
	native_title_settle(&w)
	assert(title_metrics(&w).height == 0, "fullscreen reports no client title bar")
	point := sdl3.Point{300, 26}
	assert(
		title_mac_hit(w.window, &point, &w) == .NORMAL,
		"fullscreen ignores stale caption drags",
	)
	assert(sdl3.SetWindowFullscreen(w.window, false))
	native_title_settle(&w)
	native_title_layout(&w)
	fmt.println("PASS fullscreen clears caption drags and restores the native title bar")

	native_title_scaling(&w)
	fmt.println("PASS logical drag points at density 1, 1.5 and 2")
	native_title_publish(&w)
	native := cast(^NS.Window)w.cocoa_window
	intrinsics.objc_send(nil, native, "makeKeyAndOrderFront:", NS.id(nil))
	native_title_settle(&w)

	// Check routing through AppKit and SDL, rather than directly calling
	// the monitor: both the preserved responder chain and local monitor
	// registration must actually work.
	native_title_client_click(&w)
	defaults := NS.UserDefaults_standardUserDefaults()
	action := intrinsics.objc_send(
		^NS.String,
		defaults,
		"stringForKey:",
		NS.MakeConstantString("AppleActionOnDoubleClick"),
	)
	expected := Title_Mac_Action.Zoom
	if preference == "Minimize" {
		expected = .Minimize
	} else if preference == "None" {
		expected = .None
	}
	assert(
		title_mac_action(action) == expected,
		"Foundation uses the process-local preference override",
	)
	native_title_action(&w, expected)
	fmt.println(
		"PASS caption double-click follows",
		preference,
		"with the scroll monitor installed",
	)

	// Detach is idempotent and releases the per-window monitor. A second
	// attachment must still route exactly one action for a double-click.
	title_detach(&w)
	assert(
		!w.title_on && w.cocoa_title_events == nil && w.cocoa_window == nil,
		"detach releases native event state",
	)
	title_detach(&w)
	assert(title_attach(&w))
	native_title_layout(&w)
	native_title_publish(&w)
	native_title_action(&w, expected)
	fmt.println("PASS event monitor detach and reattach with one double-click action")

	native_title_drain()
	button := intrinsics.objc_send(^NS.View, native, "standardWindowButton:", NS.UInteger(0))
	intrinsics.objc_send(nil, button, "performClick:", NS.id(nil))
	requested := false
	e: sdl3.Event
	for sdl3.PollEvent(&e) {
		if e.type == .WINDOW_CLOSE_REQUESTED {
			requested = true
		}
	}
	assert(requested, "the native red button requests a shell close")
	assert(close_window(&w), "macOS keeps the app alive after close")
	assert(.HIDDEN in sdl3.GetWindowFlags(w.window))
	assert(sdl3.ShowWindow(w.window))
	native_title_settle(&w)
	native_title_layout(&w)
	fmt.println("PASS native close, hide and reopen")
}

@(private = "file")
native_title_action :: proc(w: ^Window, expected: Title_Mac_Action) {
	native := cast(^NS.Window)w.cocoa_window
	before := intrinsics.objc_send(NS.BOOL, native, "isZoomed")
	native_title_click(w, 300, 2)
	native_title_settle(w)
	switch expected {
	case .Zoom:
		assert(
			intrinsics.objc_send(NS.BOOL, native, "isZoomed") != before,
			"caption double-click zooms",
		)
	case .Minimize:
		assert(.MINIMIZED in sdl3.GetWindowFlags(w.window), "caption double-click minimises")
		assert(sdl3.RestoreWindow(w.window))
		native_title_settle(w)
	case .None:
		assert(
			intrinsics.objc_send(NS.BOOL, native, "isZoomed") == before,
			"No Action does not zoom",
		)
		assert(.MINIMIZED not_in sdl3.GetWindowFlags(w.window), "No Action does not minimise")
	}
}

@(private = "file")
native_title_settle :: proc(w: ^Window) {
	assert(sdl3.SyncWindow(w.window), "SDL completes pending native window operations")
	for _ in 0 ..< 20 {
		sdl3.PumpEvents()
		time.sleep(10 * time.Millisecond)
	}
}

@(private = "file")
native_title_drain :: proc() {
	e: sdl3.Event
	for sdl3.PollEvent(&e) {}
}

@(private = "file")
native_title_publish :: proc(w: ^Window) {
	title_set_drags(w, []ops.Rect{{100 * w.density, 0, 400 * w.density, 52 * w.density}})
}

@(private = "file")
native_title_scaling :: proc(w: ^Window) {
	density := w.density
	defer w.density = density
	for d in ([]f32{1, 1.5, 2}) {
		w.density = d
		native_title_publish(w)
		for point in ([]sdl3.Point{{100, 0}, {300, 26}, {499, 51}}) {
			p := point
			assert(title_mac_hit(w.window, &p, w) == .DRAGGABLE)
		}
		for point in ([]sdl3.Point{{30, 26}, {530, 26}, {300, 53}}) {
			p := point
			assert(title_mac_hit(w.window, &p, w) == .NORMAL)
		}
	}
}

@(private = "file")
native_title_layout :: proc(w: ^Window) {
	bar := title_metrics(w)
	assert(bar.height == 52 && bar.buttons.w > 0 && bar.buttons.w < 120)
	assert(
		!bar.drawn && title_button_pixels(w, 900, 600) == (ops.Rect{}),
		"native controls need no texture hole",
	)
	native := cast(^NS.Window)w.cocoa_window
	content := native->contentView()
	bounds := content->bounds()
	parent := intrinsics.objc_send(^NS.View, content, "superview")
	for kind in 0 ..< 3 {
		button := intrinsics.objc_send(
			^NS.View,
			native,
			"standardWindowButton:",
			NS.UInteger(kind),
		)
		assert(button != nil, "native traffic-light button exists")
		r := intrinsics.objc_send(
			NS.Rect,
			content,
			"convertRect:fromView:",
			button->bounds(),
			button,
		)
		assert(
			bounds.size.height - r.origin.y - r.size.height / 2 == 26,
			"native button aligns with the client toolbar",
		)
		p := NS.Point{r.origin.x + r.size.width / 2, r.origin.y + r.size.height / 2}
		p = parent->convertPointFromView(p, content)
		assert(
			intrinsics.objc_send(^NS.View, parent, "hitTest:", p) == button,
			"AppKit hit-tests the native button",
		)
	}
	for x in ([]NS.Float{100, bounds.size.width - 20}) {
		p := parent->convertPointFromView({x, bounds.size.height - 26}, content)
		assert(
			intrinsics.objc_send(^NS.View, parent, "hitTest:", p) == content,
			"native chrome does not intercept client tools",
		)
	}
	assert(
		intrinsics.objc_send(NS.id, content, "nextResponder") != nil,
		"SDL's responder chain remains installed",
	)
}

@(private = "file")
native_title_click :: proc(w: ^Window, x: NS.Float, clicks: NS.Integer) {
	native := cast(^NS.Window)w.cocoa_window
	bounds := native->contentView()->bounds()
	number := intrinsics.objc_send(NS.Integer, native, "windowNumber")
	app := intrinsics.objc_send(^NS.Application, NS.Application, "sharedApplication")
	for kind in ([]NS.UInteger{1, 2}) { 	// left down, left up
		event := intrinsics.objc_send(
			^NS.Event,
			NS.Event,
			"mouseEventWithType:location:modifierFlags:timestamp:windowNumber:context:eventNumber:clickCount:pressure:",
			kind,
			NS.Point{x, bounds.size.height - 26},
			NS.UInteger(0),
			f64(0),
			number,
			NS.id(nil),
			NS.Integer(0),
			clicks,
			f32(1),
		)
		intrinsics.objc_send(nil, app, "sendEvent:", event)
	}
}

@(private = "file")
native_title_client_click :: proc(w: ^Window) {
	native_title_drain()
	native := cast(^NS.Window)w.cocoa_window
	before := intrinsics.objc_send(NS.BOOL, native, "isZoomed")
	bounds := native->contentView()->bounds()
	native_title_click(w, bounds.size.width - 20, 2)
	pressed, released := false, false
	e: sdl3.Event
	for sdl3.PollEvent(&e) {
		if e.type == .MOUSE_BUTTON_DOWN && e.button.windowID == sdl3.GetWindowID(w.window) {
			pressed = true
		}
		if e.type == .MOUSE_BUTTON_UP && e.button.windowID == sdl3.GetWindowID(w.window) {
			released = true
		}
	}
	assert(pressed && released, "client tool clicks reach SDL through the responder chain")
	assert(
		intrinsics.objc_send(NS.BOOL, native, "isZoomed") == before,
		"a client double-click is not a caption action",
	)
	assert(.MINIMIZED not_in sdl3.GetWindowFlags(w.window))
	fmt.println("PASS client tool down/up routing and caption-action exclusion")
}
