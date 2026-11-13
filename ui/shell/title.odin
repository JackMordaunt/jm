package shell

import sdl3 "vendor:sdl3"

import "jm:ui/ops"

// TITLE_DRAG_CAP is how many drag rects a frame may publish. The hit
// test reads one slot while the shell writes the other; further rects
// are dropped.
@(private)
TITLE_DRAG_CAP :: 16

// TITLE_BUTTON_CAP is how many caption buttons a Drawn frame may publish.
@(private)
TITLE_BUTTON_CAP :: 4

// Title_Hit is where a client point lands in a unified title bar.
@(private)
Title_Hit :: enum u8 {
	Client,
	Caption,
	Top,
	Top_Left,
	Top_Right,
	Minimize,
	Maximize,
	Close,
}

// title_set_drags publishes drags, and the caption buttons a Drawn frame
// drew, for the hit test. The reader keeps the previous slot, so a hit
// test reentered while this copies still sees a whole frame. n == 0 is
// published too, which clears the last frame's rects. Both are device
// pixels.
@(private)
title_set_drags :: proc(w: ^Window, drags: []ops.Rect, buttons: []ops.Window_Button = nil) {
	slot := 1 - w.drag_read
	n := len(drags)
	if n > TITLE_DRAG_CAP {
		n = TITLE_DRAG_CAP
	}
	for i in 0 ..< n {
		w.drags[slot][i] = drags[i]
	}
	w.drag_n[slot] = n
	m := len(buttons)
	if m > TITLE_BUTTON_CAP {
		m = TITLE_BUTTON_CAP
	}
	for i in 0 ..< m {
		w.drawn[slot][i] = buttons[i]
	}
	w.drawn_n[slot] = m
	w.drag_read = slot
}

// title_hit reports where p, in client pixels, lands. drawn, the caption
// buttons a Drawn frame drew, wins over the platform's buttons; both win
// over the resize strip and over any drag rect underneath. border is the
// top resize strip; 0 (a maximized window) has none. An empty buttons
// rect draws no caption buttons. The outer edge of a rect is inside it.
@(private)
title_hit :: proc "contextless" (p: ops.Point, client: ops.Size, buttons: ops.Rect, border: f32, drags: []ops.Rect, rtl: bool, drawn: []ops.Window_Button = nil) -> Title_Hit {
	for b in drawn {
		if title_contains(b.rect, p) {
			switch b.button {
			case .None:
			case .Minimize:
				return .Minimize
			case .Maximize:
				return .Maximize
			case .Close:
				return .Close
			}
		}
	}
	if title_contains(buttons, p) {
		return title_button(buttons, p, rtl)
	}
	if border > 0 && p.y >= 0 && p.y < border {
		if p.x < border {
			return .Top_Left
		}
		if p.x >= client.x - border {
			return .Top_Right
		}
		return .Top
	}
	for r in drags {
		if title_contains(r, p) {
			return .Caption
		}
	}
	return .Client
}

// title_button_pixels is the platform's caption buttons in image pixels,
// clamped to the image: the hole Unified clears for them. Zero when the
// mode is not Unified, the title bar is off or the buttons are empty. A
// fractional edge rounds outward so the frame is not left a sliver.
@(private)
title_button_pixels :: proc "contextless" (w: ^Window, width, height: int) -> ops.Rect {
	if w == nil || !w.title_on || w.title_mode != .Unified || width <= 0 || height <= 0 {
		return {}
	}
	b := w.buttons_px
	if b.w <= 0 || b.h <= 0 {
		return {}
	}
	x0 := title_floor(b.x)
	y0 := title_floor(b.y)
	x1 := title_ceil(b.x + b.w)
	y1 := title_ceil(b.y + b.h)
	if x0 < 0 {
		x0 = 0
	}
	if y0 < 0 {
		y0 = 0
	}
	if x1 > width {
		x1 = width
	}
	if y1 > height {
		y1 = height
	}
	if x0 >= x1 || y0 >= y1 {
		return {}
	}
	return {f32(x0), f32(y0), f32(x1 - x0), f32(y1 - y0)}
}

@(private)
title_floor :: proc "contextless" (v: f32) -> int {
	n := int(v)
	if v < 0 && f32(n) != v {
		return n - 1
	}
	return n
}

@(private)
title_ceil :: proc "contextless" (v: f32) -> int {
	n := int(v)
	if f32(n) != v && v > 0 {
		return n + 1
	}
	return n
}

@(private)
title_contains :: proc "contextless" (r: ops.Rect, p: ops.Point) -> bool {
	return r.w > 0 && r.h > 0 && p.x >= r.x && p.y >= r.y && p.x <= r.x + r.w && p.y <= r.y + r.h
}

@(private)
title_button :: proc "contextless" (buttons: ops.Rect, p: ops.Point, rtl: bool) -> Title_Hit {
	span := buttons.w / 3
	if span <= 0 {
		return .Close
	}
	idx := int((p.x - buttons.x) / span)
	if idx < 0 {
		idx = 0
	}
	if idx > 2 {
		idx = 2
	}
	// LTR is minimize, maximize, close. RTL reverses the ends.
	if rtl {
		switch idx {
		case 0:
			return .Close
		case 1:
			return .Maximize
		case:
			return .Minimize
		}
	}
	switch idx {
	case 0:
		return .Minimize
	case 1:
		return .Maximize
	case:
		return .Close
	}
}

// title_sdl_hit classifies p, in client device pixels, for SDL's hit test
// where the shell draws the caption (not Windows or macOS, which answer
// their own messages). A drawn caption button is NORMAL, so the shell
// gets its clicks; then the window's edge, border pixels wide (0 when
// maximized: none), is a resize; then a drag rect moves the window; the
// rest is the client.
@(private)
title_sdl_hit :: proc "contextless" (p: ops.Point, client: ops.Size, border: f32, drags: []ops.Rect, drawn: []ops.Window_Button) -> sdl3.HitTestResult {
	for b in drawn {
		if b.button != .None && title_contains(b.rect, p) {
			return .NORMAL
		}
	}

	if border > 0 {
		left := p.x >= 0 && p.x < border
		right := p.x < client.x && p.x >= client.x - border
		top := p.y >= 0 && p.y < border
		bottom := p.y < client.y && p.y >= client.y - border
		switch {
		case top && left:
			return .RESIZE_TOPLEFT
		case top && right:
			return .RESIZE_TOPRIGHT
		case bottom && left:
			return .RESIZE_BOTTOMLEFT
		case bottom && right:
			return .RESIZE_BOTTOMRIGHT
		case top:
			return .RESIZE_TOP
		case bottom:
			return .RESIZE_BOTTOM
		case left:
			return .RESIZE_LEFT
		case right:
			return .RESIZE_RIGHT
		}
	}

	for r in drags {
		if title_contains(r, p) {
			return .DRAGGABLE
		}
	}
	return .NORMAL
}

// title_drawn_at is the caption button of the published Drawn frame under
// p, in device pixels; None when p is over none.
@(private)
title_drawn_at :: proc "contextless" (w: ^Window, p: ops.Point) -> ops.Caption_Button {
	slot := w.drag_read
	if slot != 0 && slot != 1 {
		slot = 0
	}
	n := min(max(w.drawn_n[slot], 0), TITLE_BUTTON_CAP)
	for b in w.drawn[slot][:n] {
		if b.button != .None && title_contains(b.rect, p) {
			return b.button
		}
	}
	return .None
}
