package shell

import "jm:ui"

// apply_themes carries out every Window_Theme in requests. The last one
// wins. Call it before present, so the frame's caption matches.
@(private)
apply_themes :: proc(w: ^Window, requests: []ui.Request) {
	for q in requests {
		if v, ok := q.(ui.Window_Theme); ok {
			apply_window_theme(w, v.dark, v.caption)
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
