package fuzz

import "core:os"
import "core:testing"

// classify is the whole of what the harness concludes from a child, so it is
// worth pinning on its own: everything else about isolation depends on it.
@(test)
classify_reads_the_child_correctly :: proc(t: ^testing.T) {
	held := os.Process_State {
		exited    = true,
		exit_code = 0,
		success   = true,
	}
	testing.expect_value(t, classify(held, nil, false), Outcome.Held)

	failed := os.Process_State {
		exited    = true,
		exit_code = EXIT_FAILED,
		success   = true,
	}
	testing.expect_value(t, classify(failed, nil, false), Outcome.Failed)

	broken := os.Process_State {
		exited    = true,
		exit_code = EXIT_BROKEN,
		success   = true,
	}
	testing.expect_value(t, classify(broken, nil, false), Outcome.Broken)

	// Any other exit is the child dying rather than reporting, whatever it
	// says about its own success.
	odd := os.Process_State {
		exited    = true,
		exit_code = 1,
		success   = false,
	}
	testing.expect_value(t, classify(odd, nil, false), Outcome.Crashed)

	signalled := os.Process_State {
		exited    = true,
		exit_code = 11,
		success   = false,
	}
	testing.expect_value(t, classify(signalled, nil, false), Outcome.Crashed)

	// A kill beats everything: the case was cut short, whatever it managed
	// to exit with on the way out.
	testing.expect_value(t, classify(held, nil, true), Outcome.Hung)
	testing.expect_value(t, classify(signalled, nil, true), Outcome.Hung)

	// A wait that failed says nothing about the case.
	testing.expect_value(t, classify({}, os.General_Error.Invalid_File, false), Outcome.Broken)
}
