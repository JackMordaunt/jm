#+build darwin
package ui

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

@(private = "file", objc_class = "NSWorkspace")
Workspace :: struct {
	using _: NS.Object,
}

// reduce_motion_preferred is whether the user asked the system for less
// motion: NSWorkspace's accessibilityDisplayShouldReduceMotion, read each
// call so a change applies on the next frame.
reduce_motion_preferred :: proc() -> bool {
	ws := intrinsics.objc_send(^Workspace, Workspace, "sharedWorkspace")
	return bool(intrinsics.objc_send(NS.BOOL, ws, "accessibilityDisplayShouldReduceMotion"))
}
