#+build linux
package ui

import "core:sys/linux"
import "core:sys/posix"

// process_rss is this process's resident memory in bytes: /proc/self/statm's
// resident pages, or -1 when it cannot be read. It runs every frame, so it
// reads through raw syscalls and parses by hand: nothing here allocates.
process_rss :: proc() -> int {
	fd, err := linux.open("/proc/self/statm", {})
	if err != .NONE {
		return -1
	}
	defer linux.close(fd)
	buf: [128]u8
	n, rerr := linux.read(fd, buf[:])
	if rerr != .NONE || n <= 0 {
		return -1
	}
	// proc(5): statm is "size resident shared text lib data dt"; resident
	// is the second field.
	s := buf[:n]
	i := 0
	for i < len(s) && s[i] != ' ' {
		i += 1
	}
	for i < len(s) && s[i] == ' ' {
		i += 1
	}
	if i == len(s) || s[i] < '0' || s[i] > '9' {
		return -1
	}
	pages := 0
	for i < len(s) && s[i] >= '0' && s[i] <= '9' {
		pages = pages * 10 + int(s[i] - '0')
		i += 1
	}
	return pages * int(posix.sysconf(._PAGESIZE))
}
