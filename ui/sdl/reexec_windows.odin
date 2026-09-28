#+build windows
package sdl

import "core:fmt"

// host_reexec is not done on Windows, where hot-watch does not rebuild a
// running host either; it asks for a manual restart.
host_reexec :: proc(l: ^Host_Loop) {
	fmt.eprintln("sdl: rebuild and restart the host")
}
