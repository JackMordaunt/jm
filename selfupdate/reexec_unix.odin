#+build !windows
package selfupdate

import "core:mem"
import "core:strings"
import "core:sys/posix"

ARGV_CAP :: 64

// reexec replaces this process with exe. It only returns on failure, with
// the reason in r. The C strings are built in a stack arena.
reexec :: proc(exe: string, args: []string, r: ^Result) {
	if len(args) + 2 > ARGV_CAP {
		failf(r, .Failed, "more than %d arguments", ARGV_CAP - 2)
		return
	}
	buf: [2 * PATH_CAP]byte
	arena: mem.Arena
	mem.arena_init(&arena, buf[:])
	alloc := mem.arena_allocator(&arena)
	argv: [ARGV_CAP]cstring
	c, err := strings.clone_to_cstring(exe, alloc)
	if err != nil {
		failf(r, .Failed, "arguments longer than %d bytes", len(buf))
		return
	}
	argv[0] = c
	for a, i in args {
		c, err = strings.clone_to_cstring(a, alloc)
		if err != nil {
			failf(r, .Failed, "arguments longer than %d bytes", len(buf))
			return
		}
		argv[i + 1] = c
	}
	argv[len(args) + 1] = nil
	posix.execv(argv[0], &argv[0])
	failf(r, .Failed, "cannot run %s: %v", exe, posix.errno())
}
