#+build !windows
#+build !darwin
package shell

import "core:log"
import sdl3 "vendor:sdl3"

import "jm:ui"
import "jm:ui/ops"

// TITLE_OTHER_HEIGHT is the caption height the shell reports, in points.
// The frame draws its own bar at whatever height it likes.
@(private)
TITLE_OTHER_HEIGHT :: f32(32)

// TITLE_OTHER_BUTTON is one caption button's width in points: jm:ui/windows
// BUTTON_WIDTH.
@(private)
TITLE_OTHER_BUTTON :: f32(46)

// TITLE_OTHER_BORDER is the resize edge in points.
@(private)
TITLE_OTHER_BORDER :: f32(5)

// title_attach makes the window borderless and has SDL's hit test move and
// resize it, so the frame draws the caption, buttons included. Unified
// and Drawn are the same here: both draw the buttons.
@(private)
title_attach :: proc(w: ^Window) -> bool {
	if (w.title_mode != .Unified && w.title_mode != .Drawn) || w.window == nil {
		return true
	}
	if !sdl3.SetWindowBordered(w.window, false) {
		log.warnf("ui/shell: cannot drop the system caption: %s", sdl3.GetError())
		return false
	}
	if !sdl3.SetWindowHitTest(w.window, title_other_hit, w) {
		log.warnf("ui/shell: cannot hit-test the drawn caption: %s", sdl3.GetError())
		_ = sdl3.SetWindowBordered(w.window, true)
		return false
	}
	w.title_on = true
	return true
}

// title_detach gives the window its system caption back.
@(private)
title_detach :: proc(w: ^Window) {
	if !w.title_on {
		return
	}
	w.title_on = false
	if w.window != nil {
		_ = sdl3.SetWindowHitTest(w.window, nil, nil)
		_ = sdl3.SetWindowBordered(w.window, true)
	}
	w.caption_hover, w.caption_pressed = .None, .None
}

@(private)
title_other_hit :: proc "c" (_: ^sdl3.Window, area: ^sdl3.Point, data: rawptr) -> sdl3.HitTestResult {
	w := cast(^Window)data
	if w == nil || !w.title_on || area == nil {
		return .NORMAL
	}
	d := w.density if w.density > 0 else 1
	border := TITLE_OTHER_BORDER * d
	if .MAXIMIZED in sdl3.GetWindowFlags(w.window) || .FULLSCREEN in sdl3.GetWindowFlags(w.window) {
		border = 0
	}
	slot := w.drag_read
	if slot != 0 && slot != 1 {
		slot = 0
	}
	n := min(max(w.drag_n[slot], 0), TITLE_DRAG_CAP)
	m := min(max(w.drawn_n[slot], 0), TITLE_BUTTON_CAP)
	return title_sdl_hit(
		{f32(area.x) * d, f32(area.y) * d},
		{f32(w.size.x), f32(w.size.y)},
		border,
		w.drags[slot][:n],
		w.drawn[slot][:m],
	)
}

// title_metrics is the caption in window points. Zero when the mode is
// System or the window is fullscreen.
@(private)
title_metrics :: proc(w: ^Window) -> ui.Title_Bar {
	if !w.title_on || w.window == nil {
		return {}
	}
	flags := sdl3.GetWindowFlags(w.window)
	if .FULLSCREEN in flags {
		return {}
	}
	d := w.density if w.density > 0 else 1
	bw := 3 * TITLE_OTHER_BUTTON
	return {
		height = TITLE_OTHER_HEIGHT,
		buttons = {f32(w.size.x) / d - bw, 0, bw, TITLE_OTHER_HEIGHT},
		maximized = .MAXIMIZED in flags,
		active = .INPUT_FOCUS in flags,
		drawn = true,
		hover = w.caption_hover,
		pressed = w.caption_pressed if w.caption_pressed == w.caption_hover else .None,
	}
}

// title_caption_event follows the pointer over the drawn caption buttons
// and performs one released over the button it was pressed on. It returns
// true for a press or release the buttons took, which the ui must not see:
// a press on Close would otherwise also click what is beneath it. Motion
// is never taken.
@(private)
title_caption_event :: proc(w: ^Window, e: ^sdl3.Event) -> bool {
	if !w.title_on {
		return false
	}
	d := w.density if w.density > 0 else 1
	set :: proc(w: ^Window, hover, pressed: ops.Caption_Button) {
		if w.caption_hover != hover || w.caption_pressed != pressed {
			w.caption_hover, w.caption_pressed = hover, pressed
		}
	}
	#partial switch e.type {
	case .MOUSE_MOTION:
		over := title_drawn_at(w, {e.motion.x * d, e.motion.y * d})
		set(w, over, w.caption_pressed)
	case .WINDOW_MOUSE_LEAVE:
		set(w, .None, .None)
	case .MOUSE_BUTTON_DOWN:
		if e.button.button != sdl3.BUTTON_LEFT {
			return false
		}
		over := title_drawn_at(w, {e.button.x * d, e.button.y * d})
		if over == .None {
			return false
		}
		set(w, over, over)
		return true
	case .MOUSE_BUTTON_UP:
		if e.button.button != sdl3.BUTTON_LEFT || w.caption_pressed == .None {
			return false
		}
		held := w.caption_pressed
		over := title_drawn_at(w, {e.button.x * d, e.button.y * d})
		set(w, over, .None)
		if over == held {
			title_caption_perform(w, held)
		}
		return true
	}
	return false
}

// title_caption_perform does what button does, as the system's would. Close
// asks as the window's own close request does.
@(private)
title_caption_perform :: proc(w: ^Window, button: ops.Caption_Button) {
	switch button {
	case .None:
	case .Minimize:
		_ = sdl3.MinimizeWindow(w.window)
	case .Maximize:
		if .MAXIMIZED in sdl3.GetWindowFlags(w.window) {
			_ = sdl3.RestoreWindow(w.window)
		} else {
			_ = sdl3.MaximizeWindow(w.window)
		}
	case .Close:
		ev: sdl3.Event
		ev.type = .WINDOW_CLOSE_REQUESTED
		ev.window.windowID = sdl3.GetWindowID(w.window)
		_ = sdl3.PushEvent(&ev)
	}
}

// title_can_unify is whether a running window can take .Unified.
@(private)
title_can_unify :: proc(_: ^Window) -> bool {
	return true
}
