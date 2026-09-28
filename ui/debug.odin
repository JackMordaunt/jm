package ui

import "core:os"

// Debug_Flag is a switch for inspecting a UI, set on Ctx.debug.
Debug_Flag :: enum u8 {
	// Reveal shows what hides until it is used, such as an idle scroll
	// bar, as though it were in use: for a screenshot or a headless
	// render that must show every part. Layout, input and animation are
	// unchanged; only whether the part is drawn differs.
	Reveal,
}

Debug_Flags :: bit_set[Debug_Flag;u8]

// DEBUG_REVEAL_ENV is the environment variable that sets .Reveal for a
// whole app: JM_UI_REVEAL=1, read by the hot-reload child, the SDL host
// loop and render.snapshot through debug_from_env.
DEBUG_REVEAL_ENV :: "JM_UI_REVEAL"

// debug_from_env is the debug flags the environment asks for: .Reveal
// when JM_UI_REVEAL is set to anything but empty or 0.
debug_from_env :: proc() -> Debug_Flags {
	// The buffer holds the name, NUL-terminated for getenv, then the value.
	buf: [64]u8
	v := os.get_env(buf[:], DEBUG_REVEAL_ENV)
	if v == "" || v == "0" {
		return {}
	}
	return {.Reveal}
}

// revealing reports whether a part that hides until used should draw
// now anyway. Every such part asks it at the point where it decides to
// hide, so one grep finds them all.
revealing :: proc(gtx: ^Ctx) -> bool {
	return .Reveal in gtx.debug
}
