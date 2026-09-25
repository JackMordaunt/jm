#+build !windows
package fuzz

import "core:strings"
import "core:testing"
import "core:time"

// These drive the real machinery — spawn, wait, kill, read back — with a
// shell standing in for the child, so every outcome can be asked for exactly
// rather than waited for. Unix only, for /bin/sh.

// stub_suite is never actually checked: with isolation the property runs
// in the child, and here the child is a shell script instead.
stub_properties := []Property(Nothing){{"stub", always_holds}}

stub_run :: proc(t: ^testing.T, script: string, timeout: time.Duration) -> Report {
	suite := Suite(Nothing) {
		name       = "stub",
		setup      = nothing_setup,
		properties = stub_properties,
	}
	command := []string{"/bin/sh", "-c", script}
	return run(
		suite,
		{
			seed = 1,
			iterations = 1,
			isolate = true,
			child_command = command,
			case_timeout = timeout,
			shrink = -1,
		},
	)
}

@(test)
a_child_that_exits_zero_held :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := stub_run(t, "exit 0", time.Second)
	testing.expect_value(t, r.iterations, 1)
	testing.expect_value(t, len(r.failures), 0)
}

@(test)
a_child_that_exits_failed_is_a_failure_with_its_detail :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := stub_run(t, `printf 'the thing went wrong' > "$JM_FUZZ_DETAIL"; exit 70`, time.Second)
	testing.expect_value(t, len(r.failures), 1)
	if len(r.failures) == 0 {
		return
	}
	testing.expect_value(t, r.failures[0].outcome, Outcome.Failed)
	testing.expect_value(t, r.failures[0].detail, "the thing went wrong")
}

@(test)
a_child_killed_by_a_signal_is_a_crash :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := stub_run(t, `echo "last words" >&2; kill -SEGV $$`, time.Second)
	testing.expect_value(t, len(r.failures), 1)
	if len(r.failures) == 0 {
		return
	}
	testing.expect_value(t, r.failures[0].outcome, Outcome.Crashed)
	// What the child managed to say before it died is the useful part.
	testing.expect(
		t,
		strings.contains(r.failures[0].detail, "last words"),
		"the child's output must reach the report",
	)
}

@(test)
a_child_that_will_not_finish_is_killed :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	started := time.now()
	r := stub_run(t, "sleep 30", 200 * time.Millisecond)
	elapsed := time.since(started)

	testing.expect_value(t, len(r.failures), 1)
	if len(r.failures) == 0 {
		return
	}
	testing.expect_value(t, r.failures[0].outcome, Outcome.Hung)
	testing.expect(t, r.failures[0].hung, "a hang must be marked as one")
	// The point of isolation: the deadline is kept by killing the child,
	// with no help at all from what it was running.
	testing.expect(t, elapsed < 10 * time.Second, "the run must not wait out a case that hangs")
}

@(test)
a_child_that_cannot_run_the_case_is_broken :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := stub_run(t, "exit 71", time.Second)
	testing.expect_value(t, len(r.failures), 1)
	if len(r.failures) == 0 {
		return
	}
	testing.expect_value(t, r.failures[0].outcome, Outcome.Broken)
}

// A child is handed its case in a file, and the harness has to put it
// there: a child that cannot read it back would test nothing at all.
@(test)
the_child_is_given_the_case :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	r := stub_run(
		t,
		`wc -c < "$JM_FUZZ_ENTROPY" | tr -d ' \n' > "$JM_FUZZ_DETAIL"; exit 70`,
		time.Second,
	)
	testing.expect_value(t, len(r.failures), 1)
	if len(r.failures) == 0 {
		return
	}
	// The default entropy size, written out for the child to draw from.
	testing.expect_value(t, r.failures[0].detail, "256")
}

// A run that cannot spawn children must say so rather than report a
// clean sweep of cases it never ran.
@(test)
a_run_that_cannot_spawn_says_so :: proc(t: ^testing.T) {
	context.allocator = context.temp_allocator
	suite := Suite(Nothing) {
		name       = "stub",
		setup      = nothing_setup,
		properties = stub_properties,
	}
	command := []string{"/nonexistent/jm-fuzz-no-such-binary"}
	r := run(
		suite,
		{seed = 1, iterations = 1, isolate = true, child_command = command, shrink = -1},
	)
	testing.expect_value(t, len(r.failures), 1)
	if len(r.failures) == 0 {
		return
	}
	testing.expect_value(t, r.failures[0].outcome, Outcome.Broken)
}
