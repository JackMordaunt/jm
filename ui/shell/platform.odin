package shell

import "core:log"
import "core:strings"
import "jm:ui"
import "jm:ui/ops"
import "vendor:sdl3"

// What a frame asks of the platform beyond pixels (ui/request.odin): the
// pointer's cursor, the clipboard and URLs to open. A single-process App takes both
// from its own Router; a host takes them from the child's Reply. Either
// way they come here once the frame is done.

// apply_platform shows cursor, when changed is set, and carries out
// requests: a clipboard write goes to the system clipboard, and a read is
// answered at once with a Paste pushed through sink for the next frame,
// its text in allocator, which must last until sink's events are used.
// A URL goes to SDL_OpenURL, the system's handler for its scheme.
@(private)
apply_platform :: proc(w: ^Window, cursor: ops.Cursor, changed: bool, requests: []ui.Request, sink: Event_Sink, user: rawptr, allocator := context.temp_allocator) {
	if changed {
		show_cursor(w, cursor)
	}
	for q in requests {
		switch v in q {
		case ui.Clipboard_Write:
			// Only text is wired up: SDL3's SetClipboardData would carry other
			// MIME types, but nothing asks for one yet.
			if v.mime == ui.TEXT_MIME {
				text := strings.clone_to_cstring(v.data, context.temp_allocator)
				_ = sdl3.SetClipboardText(text)
			}
		case ui.Clipboard_Read:
			text: string
			if v.mime == ui.TEXT_MIME {
				if raw := sdl3.GetClipboardText(); raw != nil {
					text = strings.clone_from_cstring(cstring(raw), allocator)
					sdl3.free(raw)
				}
			}
			// Answered even when empty, so the askers stop waiting.
			sink(user, {kind = .Paste, text = text, mime = strings.clone(v.mime, allocator)})
		case ui.Open_Url:
			if !sdl3.OpenURL(strings.clone_to_cstring(v.url, context.temp_allocator)) {
				log.warnf("ui/shell: cannot open %q: %s", v.url, sdl3.GetError())
			}
		}
	}
}

// show_cursor sets the system cursor for c, making each SDL cursor once.
@(private)
show_cursor :: proc(w: ^Window, c: ops.Cursor) {
	if c == w.cursor_shown && w.cursor_set {
		return
	}
	w.cursor_shown, w.cursor_set = c, true
	if c == .None {
		_ = sdl3.HideCursor()
		return
	}
	_ = sdl3.ShowCursor()
	if w.cursors[c] == nil {
		w.cursors[c] = sdl3.CreateSystemCursor(system_cursor(c))
	}
	if w.cursors[c] != nil {
		_ = sdl3.SetCursor(w.cursors[c])
	}
}

// destroy_cursors frees the cursors show_cursor made.
@(private)
destroy_cursors :: proc(w: ^Window) {
	for &c in w.cursors {
		if c != nil {
			sdl3.DestroyCursor(c)
			c = nil
		}
	}
}

// system_cursor is SDL's cursor for c; None is hidden, not a cursor.
@(private)
system_cursor :: proc(c: ops.Cursor) -> sdl3.SystemCursor {
	switch c {
	case .Default, .None:
		return .DEFAULT
	case .Text:
		return .TEXT
	case .Pointer:
		return .POINTER
	case .Grab, .Grabbing, .Move:
		// SDL3's SystemCursor (vendor:sdl3 sdl3_mouse.odin) has no
		// hand-grab cursors; the four-way move arrow is its nearest.
		return .MOVE
	case .Resize_EW:
		return .EW_RESIZE
	case .Resize_NS:
		return .NS_RESIZE
	case .Resize_NESW:
		return .NESW_RESIZE
	case .Resize_NWSE:
		return .NWSE_RESIZE
	case .Not_Allowed:
		return .NOT_ALLOWED
	case .Crosshair:
		return .CROSSHAIR
	case .Wait:
		return .WAIT
	case .Progress:
		return .PROGRESS
	}
	return .DEFAULT
}
