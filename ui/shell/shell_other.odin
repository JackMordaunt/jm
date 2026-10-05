#+build !windows
package shell

// wait_for_compositor does nothing here. Stale frames during a resize were
// measured, and fixed, on Windows only; another system may need its own.
@(private)
wait_for_compositor :: proc() {}
