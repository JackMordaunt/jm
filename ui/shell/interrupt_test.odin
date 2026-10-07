#+build !windows
package shell

import "core:sync"
import "core:sys/posix"
import "core:testing"
import "core:time"

@(private = "file")
acted: i32

// A signal reaches the watcher, which acts on it once, and run's caller can
// tell the window was not what ended it. Stopping the watch puts back the
// handler that was there before, here the test runner's own.
@(test)
test_a_signal_reaches_the_watcher :: proc(t: ^testing.T) {
	before: posix.sigaction_t
	posix.sigaction(.SIGINT, nil, &before)

	saved := interrupt_action
	defer interrupt_action = saved
	sync.atomic_store(&acted, 0)
	interrupt_action = proc() {sync.atomic_add(&acted, 1)}

	testing.expect(t, interrupt_start(), "the watch starts")
	testing.expect(t, !interrupted(), "nothing caught yet")
	posix.raise(.SIGINT)
	deadline := time.tick_now()
	for sync.atomic_load(&acted) == 0 && time.tick_since(deadline) < 2 * time.Second {
		time.sleep(5 * time.Millisecond)
	}
	testing.expect_value(t, sync.atomic_load(&acted), 1)
	testing.expect(t, interrupted(), "the signal is reported")
	interrupt_stop()

	after: posix.sigaction_t
	posix.sigaction(.SIGINT, nil, &after)
	testing.expect(
		t,
		rawptr(after.sa_handler) == rawptr(before.sa_handler),
		"the previous handler is back",
	)
}
