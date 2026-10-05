#+build !darwin
package shell

// Elsewhere SDL's wheel events are taken as they come: what a precise
// touchpad sends there is not known to be in points.

PRECISE_POINTS :: f32(10)

scroll_watch_start :: proc() {}

scroll_watch_stop :: proc() {}

wheel_precise :: proc(x, y: f32) -> bool {
	return false
}
