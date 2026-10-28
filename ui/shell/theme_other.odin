#+build !windows
#+build !darwin
package shell

// title_theme does nothing where the desktop paints the caption. The
// icon still changes (icon.odin).
@(private)
title_theme :: proc(_: ^Window, _: bool, _: [3]u8) {}
