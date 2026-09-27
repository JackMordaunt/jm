#+build windows
package selfupdate

import "core:fmt"
import "core:os"

// reexec runs the new exe with the same arguments and exits with its code.
// Windows has no execve, so this process stays as the parent until then;
// it holds the old file open, which is why `.old` is removed on the next
// run rather than now. It only returns on failure.
reexec :: proc(exe: string, args: []string) -> string {
	command := make([]string, len(args) + 1)
	command[0] = exe
	copy(command[1:], args)
	p, err := os.process_start({command = command, stdin = os.stdin, stdout = os.stdout, stderr = os.stderr})
	if err != nil {
		return fmt.aprintf("cannot run %s: %v", exe, err)
	}
	state, werr := os.process_wait(p)
	if werr != nil {
		return fmt.aprintf("cannot wait for %s: %v", exe, werr)
	}
	os.exit(state.exit_code)
}
