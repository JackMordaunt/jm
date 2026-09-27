#+build !windows
package selfupdate

import "core:fmt"
import "core:strings"
import "core:sys/posix"

// reexec replaces this process with exe. It only returns on failure.
reexec :: proc(exe: string, args: []string) -> string {
	argv := make([]cstring, len(args) + 2)
	argv[0] = strings.clone_to_cstring(exe)
	for a, i in args {
		argv[i + 1] = strings.clone_to_cstring(a)
	}
	argv[len(args) + 1] = nil
	posix.execv(argv[0], raw_data(argv))
	return fmt.aprintf("cannot run %s: %v", exe, posix.errno())
}
