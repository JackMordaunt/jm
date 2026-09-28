package ui

import "core:os"
import "core:strings"

// Debug_Flag is a switch for inspecting a UI, set on Ctx.debug.
Debug_Flag :: enum u8 {
	// Reveal shows what hides until it is used, such as an idle scroll
	// bar, as though it were in use: for a screenshot or a headless
	// render that must show every part. Layout, input and animation are
	// unchanged; only whether the part is drawn differs.
	Reveal,
	// Bounds outlines every widget's box, so a layout bug (a child past
	// its parent, a gap from the wrong side) shows in one screenshot.
	Bounds,
}

Debug_Flags :: bit_set[Debug_Flag;u8]

// DEBUG_ENV is the environment variable that sets debug flags for a whole
// app, as a comma-separated list of flag names in lower case:
// JM_UI_DEBUG=reveal,bounds. The hot-reload child, the SDL host loop and
// render.snapshot read it through debug_from_env.
DEBUG_ENV :: "JM_UI_DEBUG"

// debug_from_env is the debug flags JM_UI_DEBUG names; an unknown name is
// ignored, so a typo turns nothing on rather than failing the app.
debug_from_env :: proc() -> (flags: Debug_Flags) {
	// The buffer holds the name, NUL-terminated for getenv, then the value.
	buf: [256]u8
	v := os.get_env(buf[:], DEBUG_ENV)
	for name in strings.split_iterator(&v, ",") {
		for f in Debug_Flag {
			if strings.equal_fold(strings.trim_space(name), debug_flag_name(f)) {
				flags += {f}
			}
		}
	}
	return
}

// debug_flag_name is f as JM_UI_DEBUG spells it.
debug_flag_name :: proc(f: Debug_Flag) -> string {
	switch f {
	case .Reveal:
		return "reveal"
	case .Bounds:
		return "bounds"
	}
	return ""
}

// revealing reports whether a part that hides until used should draw
// now anyway. Every such part asks it at the point where it decides to
// hide, so one grep finds them all.
revealing :: proc(gtx: ^Ctx) -> bool {
	return .Reveal in gtx.debug
}
