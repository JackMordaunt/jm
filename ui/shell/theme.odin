package shell

import "jm:ui"

// apply_themes carries out every Window_Theme and Window_Title_Bar in
// requests. The last of each wins. Call it before present, so the frame's caption matches.
@(private)
apply_themes :: proc(w: ^Window, requests: []ui.Request) {
	for q in requests {
		#partial switch v in q {
		case ui.Window_Theme:
			apply_window_theme(w, v.dark, v.caption)
		case ui.Window_Title_Bar:
			apply_title_bar(w, v.mode)
		}
	}
}

// apply_window_theme sets the caption and the icon for a dark or light
// window. A repeat of the same appearance does nothing.
@(private)
apply_window_theme :: proc(w: ^Window, dark: bool, caption: [3]u8) {
	if w == nil || (w.theme_set && w.theme_dark == dark && w.theme_caption == caption) {
		return
	}
	w.theme_set = true
	w.theme_dark = dark
	w.theme_caption = caption
	title_theme(w, dark, caption)
	icon_apply(w, dark)
}

// apply_title_bar switches who draws the caption: detach the old mode, set
// the new, attach it, and fall back to .System when that fails. The mode
// the window already has is left alone. A frame follows, since the caption
// the ui drew was for the old mode.
//
// Best effort on Windows: Unified needs a window created transparent
// (App.title_bar == .Unified at open), so on one that was not it becomes
// Drawn. macOS has Unified only; Drawn there is the system caption.
@(private)
apply_title_bar :: proc(w: ^Window, mode: ui.Title_Bar_Mode) {
	if w == nil || w.window == nil {
		return
	}
	mode := mode
	if mode == .Unified && !title_can_unify(w) {
		mode = .Drawn
	}
	if mode == w.title_mode {
		return
	}
	title_detach(w)
	w.title_mode = mode
	if !title_attach(w) {
		w.title_mode = .System
	}
	wake()
}
