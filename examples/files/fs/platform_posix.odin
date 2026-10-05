#+build darwin, linux
package files_fs

import "core:strings"
import "core:sys/posix"

// volume_of is the device path's filesystem is on.
volume_of :: proc(path: string) -> u64 {
	st: posix.stat_t
	if posix.lstat(strings.clone_to_cstring(path, context.temp_allocator), &st) != .OK {
		return 0
	}
	return u64(st.st_dev)
}
