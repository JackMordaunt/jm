#+build !windows
package sh

import "core:slice"
import "core:strings"

shell_argv :: proc(cmd: string, shell: Shell, allocator := context.allocator) -> []string {
	switch shell {
	case .Pwsh:
		return slice.clone([]string{"pwsh", "-NoProfile", "-Command", cmd}, allocator)
	case .Default, .Sh, .Cmd:
		return slice.clone([]string{"/bin/sh", "-c", cmd}, allocator)
	}
	return slice.clone([]string{"/bin/sh", "-c", cmd}, allocator)
}

executable_extensions :: proc(allocator := context.temp_allocator) -> []string {
	return slice.clone([]string{""}, allocator)
}

// quote makes s safe as one word in a sh command line.
quote :: proc(s: string, allocator := context.allocator) -> string {
	if s != "" && strings.index_any(s, " \t\n'\"\\$`!*?[]{}()<>|&;#~") < 0 {
		return strings.clone(s, allocator)
	}
	b := strings.builder_make(allocator)
	strings.write_byte(&b, '\'')
	for c in s {
		if c == '\'' {
			strings.write_string(&b, `'\''`)
		} else {
			strings.write_rune(&b, c)
		}
	}
	strings.write_byte(&b, '\'')
	return strings.to_string(b)
}
