#+build darwin
package shell

import "base:intrinsics"
import "core:testing"
import NS "core:sys/darwin/Foundation"

foreign import core_graphics "system:CoreGraphics.framework"

@(private = "file")
foreign core_graphics {
	CGEventCreateScrollWheelEvent2 :: proc "c" (source: rawptr, units: u32, wheel_count: u32, wheel1, wheel2, wheel3: i32) -> rawptr ---
	CFRelease :: proc "c" (cf: rawptr) ---
}

@(private = "file")
UNIT_PIXEL :: 0 // kCGScrollEventUnitPixel: a trackpad's continuous scroll

@(private = "file")
UNIT_LINE :: 1 // kCGScrollEventUnitLine: a wheel's notches

// scroll_event is a real NSEvent for a vertical scroll of amount units.
@(private = "file")
scroll_event :: proc(units: u32, amount: i32) -> (^NS.Event, rawptr) {
	cg := CGEventCreateScrollWheelEvent2(nil, units, 1, amount, 0, 0)
	return intrinsics.objc_send(^NS.Event, NS.Event, "eventWithCGEvent:", cg), cg
}

// The handler records each event with the value SDL will send for it, and
// a wheel event is matched to its record by that value: a trackpad's is
// precise, a wheel's is not, and one with no record counts as a wheel's.
@(test)
scroll_records_match_sdls_wheel_events :: proc(t: ^testing.T) {
	record_count = 0
	trackpad, cg1 := scroll_event(UNIT_PIXEL, 7)
	defer CFRelease(cg1)
	wheel, cg2 := scroll_event(UNIT_LINE, -2)
	defer CFRelease(cg2)
	testing.expect(t, bool(trackpad->hasPreciseScrollingDeltas()), "a pixel scroll is precise")
	testing.expect(t, !bool(wheel->hasPreciseScrollingDeltas()), "a line scroll is not")

	testing.expect(t, on_scroll(nil, trackpad) == trackpad, "the event passes on")
	testing.expect(t, on_scroll(nil, wheel) == wheel)
	testing.expect_value(t, record_count, 2)

	// What Cocoa_HandleMouseWheel would send for each.
	tx := f32(f64(trackpad->scrollingDeltaY()) * f64(f32(0.1)))
	wy := notch(f32(wheel->deltaY()))
	testing.expect(t, tx != 0 && wy != 0)
	testing.expect(t, wheel_precise(0, tx))
	testing.expect(t, !wheel_precise(0, wy))
	testing.expect(t, !wheel_precise(0, 0.5), "an event with no record is a wheel's")

	// A record SDL never sent an event for is skipped past, not matched.
	on_scroll(nil, wheel)
	on_scroll(nil, trackpad)
	testing.expect(t, wheel_precise(0, tx))
	testing.expect_value(t, record_count, 0)
}
