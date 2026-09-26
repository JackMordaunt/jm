#+build windows
package sh

import "core:os"
import "core:slice"
import "core:strings"

// STDIN_FLAGS opens the spooled stdin inheritable: CreateProcess hands the
// child this very handle, and without the flag the child's reads fail with
// "The handle is invalid".
STDIN_FLAGS :: os.File_Flags{.Read, .Inheritable}

shell_argv :: proc(cmd: string, shell: Shell, allocator := context.allocator) -> []string {
	switch shell {
	case .Pwsh:
		exe := "pwsh"
		if _, found := which("pwsh", allocator); !found {
			exe = "powershell"
		}
		return slice.clone([]string{exe, "-NoProfile", "-Command", cmd}, allocator)
	case .Sh:
		return slice.clone([]string{"sh", "-c", cmd}, allocator)
	case .Default, .Cmd:
		comspec, found := os.lookup_env("COMSPEC", allocator)
		if !found || comspec == "" {
			comspec = "cmd.exe"
		}
		return slice.clone([]string{comspec, "/C", cmd}, allocator)
	}
	return slice.clone([]string{"cmd.exe", "/C", cmd}, allocator)
}

executable_extensions :: proc(allocator := context.temp_allocator) -> []string {
	pathext, found := os.lookup_env("PATHEXT", allocator)
	if !found || pathext == "" {
		pathext = ".COM;.EXE;.BAT;.CMD"
	}
	exts := make([dynamic]string, allocator)
	append(&exts, "")
	for ext in strings.split_iterator(&pathext, ";") {
		if ext != "" {
			append(&exts, ext)
		}
	}
	return exts[:]
}

// quote makes s safe as one argument for cmd.exe and the C runtime parser.
quote :: proc(s: string, allocator := context.allocator) -> string {
	if s != "" && strings.index_any(s, " \t\n\"&|<>^%()") < 0 {
		return strings.clone(s, allocator)
	}
	b := strings.builder_make(allocator)
	strings.write_byte(&b, '"')
	backslashes := 0
	for c in s {
		switch c {
		case '\\':
			backslashes += 1
			continue
		case '"':
			for _ in 0 ..< backslashes * 2 + 1 {
				strings.write_byte(&b, '\\')
			}
			strings.write_byte(&b, '"')
		case:
			for _ in 0 ..< backslashes {
				strings.write_byte(&b, '\\')
			}
			strings.write_rune(&b, c)
		}
		backslashes = 0
	}
	for _ in 0 ..< backslashes * 2 {
		strings.write_byte(&b, '\\')
	}
	strings.write_byte(&b, '"')
	return strings.to_string(b)
}
