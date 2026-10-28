#+build darwin
package shell

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"
import sdl3 "vendor:sdl3"

@(objc_class="NSAppearance")
Appearance :: struct { using _: NS.Object }

// title_theme sets the window's appearance, which paints the title bar
// and its traffic lights. caption is the page colour on Windows; AppKit
// paints its own bar from the appearance.
@(private)
title_theme :: proc(w: ^Window, dark: bool, _: [3]u8) {
	if w == nil || w.window == nil {
		return
	}
	raw := sdl3.GetPointerProperty(sdl3.GetWindowProperties(w.window), sdl3.PROP_WINDOW_COCOA_WINDOW_POINTER, nil)
	name := appearance_name(dark)
	if raw == nil || name == nil {
		return
	}
	appearance := intrinsics.objc_send(^Appearance, Appearance, "appearanceNamed:", name)
	if appearance == nil {
		return
	}
	intrinsics.objc_send(nil, cast(^NS.Window)raw, "setAppearance:", appearance)
}

@(private)
appearance_name :: proc(dark: bool) -> ^NS.String {
	if dark {
		return NS.MakeConstantString("NSAppearanceNameDarkAqua")
	}
	return NS.MakeConstantString("NSAppearanceNameAqua")
}
