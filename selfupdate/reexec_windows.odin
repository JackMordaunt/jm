#+build windows
package selfupdate

import "core:os"

ARGV_CAP :: 64

// reexec runs the new exe with the same arguments and exits with its code.
// Windows has no execve, so this process stays as the parent until then;
// it holds the old file open, which is why `.old` is removed on the next
// run rather than now. It only returns on failure, with the reason in r.
reexec :: proc(exe: string, args: []string, r: ^Result) {
	if len(args) + 1 > ARGV_CAP {
		failf(r, .Failed, "more than %d arguments", ARGV_CAP - 1)
		return
	}
	command: [ARGV_CAP]string
	command[0] = exe
	copy(command[1:], args)
	p, err := os.process_start({command = command[:len(args) + 1], stdin = os.stdin, stdout = os.stdout, stderr = os.stderr})
	if err != nil {
		failf(r, .Failed, "cannot run %s: %v", exe, err)
		return
	}
	state, werr := os.process_wait(p)
	if werr != nil {
		failf(r, .Failed, "cannot wait for %s: %v", exe, werr)
		return
	}
	os.exit(state.exit_code)
}
