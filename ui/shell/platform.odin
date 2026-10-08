package shell

import "core:log"
import "core:strings"
import "jm:ui"
import "jm:ui/ops"
import "vendor:sdl3"

// What a frame asks of the platform beyond pixels (ui/request.odin): the
// pointer's cursor, the clipboard, URLs to open and the input method. A single-process App takes both
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
		case ui.Text_Input:
			apply_text_input(w, v)
		case ui.Pick_Path:
			show_pick(w, v)
		}
	}
}

// apply_text_input turns the input method on for the area v names, at its
// caret, or off. A composition in progress is dropped as focus leaves its
// area, as the field drops its preedit on Blur. SDL_SetTextInputArea takes
// window coordinates (SDL_keyboard.h), so v's device pixels are divided by
// the density.
@(private)
apply_text_input :: proc(w: ^Window, v: ui.Text_Input) {
	was := w.ime
	w.ime = v
	if w.composing && (!v.active || v.area != was.area) {
		_ = sdl3.ClearComposition(w.window)
		w.composing = false
	}
	if !v.active {
		_ = sdl3.StopTextInput(w.window)
		return
	}
	if !was.active || v.kind != was.kind {
		// The kind is a property SDL_StartTextInputWithProperties takes
		// (SDL_keyboard.h), so a new one starts text input again.
		_ = sdl3.StopTextInput(w.window)
		props := sdl3.CreateProperties()
		_ = sdl3.SetNumberProperty(props, sdl3.PROP_TEXTINPUT_TYPE_NUMBER, i64(input_type(v.kind)))
		_ = sdl3.StartTextInputWithProperties(w.window, props)
		sdl3.DestroyProperties(props)
	}
	density := w.density if w.density > 0 else 1
	rect := sdl3.Rect{i32(v.rect.x / density), i32(v.rect.y / density), i32(v.rect.w / density), i32(v.rect.h / density)}
	_ = sdl3.SetTextInputArea(w.window, &rect, i32(v.caret / density))
}

// input_type is SDL's SDL_TextInputType for a kind of text.
@(private)
input_type :: proc(kind: ui.Text_Input_Kind) -> sdl3.TextInputType {
	switch kind {
	case .Text, .Url:
		return .TEXT
	case .Number:
		return .NUMBER
	case .Email:
		return .TEXT_EMAIL
	case .Password:
		return .TEXT_PASSWORD_HIDDEN
	}
	return .TEXT
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
