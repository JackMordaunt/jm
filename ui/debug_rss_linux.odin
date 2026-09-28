#+build linux
package ui

import "core:os"
import "core:strconv"
import "core:strings"
import "core:sys/posix"

// process_rss is this process's resident memory in bytes: /proc/self/statm's
// resident pages, or -1 when it cannot be read.
process_rss :: proc() -> int {
	buf: [128]u8
	f, err := os.open("/proc/self/statm")
	if err != nil {
		return -1
	}
	defer os.close(f)
	n, rerr := os.read(f, buf[:])
	if rerr != nil || n <= 0 {
		return -1
	}
	fields := strings.fields(string(buf[:n]), context.temp_allocator)
	if len(fields) < 2 {
		return -1
	}
	pages, ok := strconv.parse_int(fields[1])
	if !ok {
		return -1
	}
	return pages * int(posix.sysconf(._PAGESIZE))
}
