package datagrid

import "base:runtime"
import "core:fmt"
import "core:os"
import "core:strings"
import "core:testing"
import "core:time"

@(private = "file")
ROW_ASSERTION_TEST :: "-tests:datagrid.test_a_table_row_without_a_key_fails_at_once"
@(private = "file")
ROW_ASSERTION_MESSAGE :: "Memory_Table: row 1 has no key; give every row a unique key"
@(private = "file")
ROW_ASSERTION_MARKER :: "JM_DATAGRID_EXPECTED_ROW_ASSERTION_OBSERVED"

@(private = "file", thread_local)
row_assertion_forward: runtime.Assertion_Failure_Proc

@(private)
row_assertion_child_selected :: proc() -> bool {
	return len(os.args) == 2 && os.args[1] == ROW_ASSERTION_TEST
}

@(private)
observe_row_assertion :: proc(forward: runtime.Assertion_Failure_Proc) -> runtime.Assertion_Failure_Proc {
	row_assertion_forward = forward
	return row_assertion_observed
}

// Observe the exact assertion before the original testing handler traps.
// Merely returning from a test with an expected assertion is not proof that
// the assertion happened. The parent requires this marker and runner success.
@(private)
row_assertion_observed :: proc(prefix, message: string, loc: runtime.Source_Code_Location) -> ! {
	if message == ROW_ASSERTION_MESSAGE {fmt.println(ROW_ASSERTION_MARKER)}
	row_assertion_forward(prefix, message, loc)
}

when ODIN_OS != .Windows {
	@(private)
	wait_row_assertion_child :: proc(child: os.Process, timeout: time.Duration) -> (state: os.Process_State, err: os.Error, owned: bool) {
		state, err = os.process_wait(child, timeout)
		return state, err, !state.exited
	}

	@(private)
	close_row_assertion_child :: proc(_: os.Process) {}
}

@(private)
expect_row_assertion_child :: proc(t: ^testing.T) {
	self, err := os.get_executable_path(context.temp_allocator)
	if !testing.expectf(t, err == nil, "cannot find this test executable: %v", err) {return}
	// Windows process_start forwards this handle directly as stdout/stderr;
	// it must be inheritable before CreateProcess receives it.
	out, open_err := os.create_temp_file("", "jm-datagrid-assert-*", {.Inheritable})
	if !testing.expectf(t, open_err == nil, "cannot capture the assertion child: %v", open_err) {return}
	path := strings.clone(os.name(out), context.temp_allocator)
	defer {
		if out != nil {_ = os.close(out)}
		_ = os.remove(path)
	}
	// A file cannot keep a pipe reader waiting after the child has ended.
	child, start_err := os.process_start({command = {self, ROW_ASSERTION_TEST}, stdout = out, stderr = out})
	if !testing.expectf(t, start_err == nil, "cannot start the assertion child: %v", start_err) {return}
	state, wait_err, owned := wait_row_assertion_child(child, 30 * time.Second)
	defer if owned {close_row_assertion_child(child)}
	timed_out := wait_err == os.General_Error.Timeout
	if wait_err != nil && owned {
		kill_err := os.process_kill(child)
		reap_err: os.Error
		state, reap_err, owned = wait_row_assertion_child(child, 5 * time.Second)
		// A child may have exited between the failed wait and the kill.
		testing.expectf(t, kill_err == nil || reap_err == nil && state.exited,
			"cannot kill the row assertion child: %v", kill_err)
		testing.expectf(t, reap_err == nil, "cannot reap the row assertion child within 5 seconds: %v", reap_err)
	}
	_ = os.close(out)
	out = nil
	text, read_err := os.read_entire_file_from_path(path, context.temp_allocator)
	testing.expectf(t, !timed_out, "the row assertion child exceeded 30 seconds")
	testing.expectf(t, wait_err == nil, "cannot wait for the row assertion child: %v", wait_err)
	testing.expectf(t, read_err == nil, "cannot read the row assertion child: %v", read_err)
	said := string(text)
	completed := state.exited && state.success && state.exit_code == 0 &&
		strings.contains(said, ROW_ASSERTION_MARKER) &&
		strings.contains(said, "Finished 1 test") && strings.contains(said, "The test was successful.")
	testing.expectf(t, completed, "row assertion child did not observe the expected assertion and complete: exit %d, output:\n%s", state.exit_code, said)
}
