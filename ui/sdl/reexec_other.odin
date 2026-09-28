#+build !windows
package sdl

import "core:fmt"
import "core:os"
import "core:strings"
import "core:sys/posix"

import "jm:ui/ipc"

// host_reexec replaces this host process with its executable as it is on
// disk now, with the same arguments: the way to pick up a host rebuilt
// while it ran (tools/hot-watch -host). The child is killed first, so it
// does not outlive the old image: the new one spawns its own. It returns
// only if the exec failed.
host_reexec :: proc(l: ^Host_Loop) {
	ipc.kill(&l.child)
	argv := make([]cstring, len(os.args) + 1, context.temp_allocator)
	for a, i in os.args {
		argv[i] = strings.clone_to_cstring(a, context.temp_allocator)
	}
	fmt.eprintfln("sdl: this host was rebuilt; restarting it")
	posix.execv(argv[0], raw_data(argv))
	fmt.eprintfln("sdl: restart failed: %v", posix.errno())
}
