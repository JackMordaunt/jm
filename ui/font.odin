package ui

// default_font is a path an app can try for a sans-serif font without
// hardcoding one itself: one guess per ODIN_OS (currently Arial on
// Windows, San Francisco on macOS, Liberation Sans on Linux), not
// necessarily what any given install actually has — OS versions and,
// on Linux, distros vary, and neither the path nor the guess itself is
// checked against any of them. Check the path (or fall back) before
// relying on it.
//
// It lives in core ui, not ui/shell, so ui/child (which never links SDL) can
// use it too; ui/shell.default_font is this, kept as an alias for callers
// already spelling it that way.
default_font :: proc() -> string {
	when ODIN_OS == .Windows {
		return "C:/Windows/Fonts/arial.ttf"
	} else when ODIN_OS == .Darwin {
		return "/System/Library/Fonts/SFNS.ttf"
	} else {
		return "/usr/share/fonts/liberation/LiberationSans-Regular.ttf"
	}
}
