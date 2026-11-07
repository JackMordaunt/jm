#+build windows
package datagrid

import "core:os"
import "core:time"
import win32 "core:sys/windows"

// os.process_wait closes a Windows handle even on a failed wait. Observe
// first without consuming it, so every live-child error can still be killed.
@(private)
wait_row_assertion_child :: proc(child: os.Process, timeout: time.Duration) -> (state: os.Process_State, err: os.Error, owned: bool) {
	switch win32.WaitForSingleObject(win32.HANDLE(child.handle), u32(timeout / time.Millisecond)) {
	case win32.WAIT_OBJECT_0:
		state, err = os.process_wait(child, 0) // known exited: harvest and close
		return state, err, err == os.General_Error.Timeout
	case win32.WAIT_TIMEOUT:
		return {}, os.General_Error.Timeout, true
	case:
		err = os.Platform_Error(win32.GetLastError())
		if err == nil {err = os.General_Error.Invalid_File}
		return {}, err, true
	}
}

@(private)
close_row_assertion_child :: proc(child: os.Process) {
	_ = win32.CloseHandle(win32.HANDLE(child.handle))
}
