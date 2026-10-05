/*
Package naming decides what a file or folder may be called: whether a
name is one the platform accepts, whether it is taken among its
siblings, and which free name "keep both" gives. The platform is an
argument, so every platform's rules are tested on any machine.
*/
package files_naming

import "core:fmt"
import "core:strings"

import "../files"

Platform :: enum u8 {
	Darwin,
	Linux,
	Windows,
}

HOST :: Platform.Darwin when ODIN_OS == .Darwin else (Platform.Windows when ODIN_OS == .Windows else Platform.Linux)

Validity :: enum u8 {
	Valid,
	Empty,
	Dots, // "." or ".."
	Separator, // holds a path separator
	Bad_Character, // a character the platform refuses in a name
	Reserved, // a Windows device name, with or without an extension
	Trailing_Dot_Or_Space, // Windows drops these, so the name would change
	Too_Long,
}

// validity answers "may an entry be called name on this platform?".
validity :: proc(name: string, on: Platform) -> Validity {
	switch {
	case name == "":
		return .Empty
	case len(name) > files.MAX_NAME:
		return .Too_Long
	case name == "." || name == "..":
		return .Dots
	}
	for r in name {
		if r == '/' || (on == .Windows && r == '\\') {
			return .Separator
		}
		if r == 0 {
			return .Bad_Character
		}
		if on == .Windows && (r < 32 || strings.contains_rune(`<>:"|?*`, r)) {
			return .Bad_Character
		}
	}
	if on != .Windows {
		return .Valid
	}
	last := name[len(name) - 1]
	if last == '.' || last == ' ' {
		return .Trailing_Dot_Or_Space
	}
	stem := name
	if dot := strings.index_byte(name, '.'); dot >= 0 {
		stem = name[:dot]
	}
	if reserved(strings.trim_right_space(stem)) {
		return .Reserved
	}
	return .Valid
}

@(private)
reserved :: proc(stem: string) -> bool {
	for device in ([]string{"CON", "PRN", "AUX", "NUL"}) {
		if strings.equal_fold(stem, device) {
			return true
		}
	}
	if len(stem) == 4 && (strings.equal_fold(stem[:3], "COM") || strings.equal_fold(stem[:3], "LPT")) {
		return stem[3] >= '1' && stem[3] <= '9'
	}
	return false
}

// same says whether two names name one entry on this platform: exactly
// on Linux, ignoring case on macOS and Windows, whose usual filesystems
// fold case.
same :: proc(a, b: string, on: Platform) -> bool {
	return a == b if on == .Linux else strings.equal_fold(a, b)
}

// taken says whether name names one of siblings.
taken :: proc(name: string, siblings: []string, on: Platform) -> bool {
	for s in siblings {
		if same(name, s, on) {
			return true
		}
	}
	return false
}

// free_name is wanted if it is not taken among siblings, else the first
// of "stem 2.ext", "stem 3.ext", … that is not, as the Finder and
// Explorer number copies. A folder's name has no extension. The name is
// written into buf, which must hold files.MAX_NAME bytes.
free_name :: proc(wanted: string, siblings: []string, on: Platform, dir: bool, buf: []u8) -> string {
	if !taken(wanted, siblings, on) {
		return string(buf[:copy(buf, wanted)])
	}
	stem, ext := wanted, ""
	if !dir {
		if dot := strings.last_index_byte(wanted, '.'); dot > 0 {
			stem, ext = wanted[:dot], wanted[dot:]
		}
	}
	for n := 2; ; n += 1 {
		name := fmt.bprintf(buf, "%s %d%s", stem, n, ext)
		if !taken(name, siblings, on) {
			return name
		}
	}
}
