#+build !darwin
package ui

// reduce_motion_preferred is whether the user asked the system for less
// motion. Only macOS's setting is read so far; elsewhere it is false.
reduce_motion_preferred :: proc() -> bool {
	return false
}
