#+build darwin
package shell

import "base:intrinsics"
import NS "core:sys/darwin/Foundation"

// A trackpad's scroll on macOS is in points: the content should move as
// far as the fingers did, and after they lift, as far as the momentum
// events AppKit sends carry it, which is where its friction comes from.
// SDL hides which events those are. It hands every scroll on as a wheel
// event, a trackpad's divided by ten (SDL_cocoamouse.m, Cocoa_HandleMouseWheel),
// with nothing to tell it from a wheel's notch. So a local event monitor
// sees each scroll event first and records whether its deltas are
// precise, with the value SDL will make of it; poll matches each wheel
// event to its record by that value.

// PRECISE_POINTS undoes SDL's scaling: points per unit of a precise
// wheel event.
PRECISE_POINTS :: f32(10)

@(private = "file")
MAX_RECORDS :: 64

@(private = "file")
Scroll_Record :: struct {
	x, y:    f32, // the wheel event SDL will send for it
	precise: bool,
}

@(private = "file")
records: [MAX_RECORDS]Scroll_Record

@(private)
record_start, record_count: int

@(private = "file")
monitor: rawptr

foreign import libSystem "system:System"

@(private = "file")
foreign libSystem {
	_NSConcreteGlobalBlock: intrinsics.objc_class
}

// The monitor's handler is a block that returns the event it is given:
// returning nil would swallow every scroll. Foundation's block helpers
// make only blocks that return nothing, so this one is built by hand, a
// global block that is never copied or freed.
@(private = "file")
Block_Descriptor :: struct {
	reserved: uint,
	size:     uint,
}

@(private = "file")
Block_Literal :: struct {
	isa:        ^intrinsics.objc_class,
	flags:      u32,
	reserved:   u32,
	invoke:     proc "c" (block: rawptr, event: ^NS.Event) -> ^NS.Event,
	descriptor: ^Block_Descriptor,
}

@(private = "file")
BLOCK_IS_GLOBAL :: 1 << 28

@(private = "file")
NSEventMaskScrollWheel :: u64(1) << 22

@(private = "file")
descriptor := Block_Descriptor{size = size_of(Block_Literal)}

@(private = "file")
handler: Block_Literal

// scroll_watch_start installs the monitor; SDL must be initialised, so
// NSApp exists.
scroll_watch_start :: proc() {
	if monitor != nil {
		return
	}
	handler = {isa = &_NSConcreteGlobalBlock, flags = BLOCK_IS_GLOBAL, invoke = on_scroll, descriptor = &descriptor}
	monitor = intrinsics.objc_send(rawptr, NS.Event, "addLocalMonitorForEventsMatchingMask:handler:", NSEventMaskScrollWheel, &handler)
}

scroll_watch_stop :: proc() {
	if monitor == nil {
		return
	}
	intrinsics.objc_send(nil, NS.Event, "removeMonitor:", monitor)
	monitor = nil
	record_count = 0
}

// on_scroll records what SDL will make of the event, as Cocoa_HandleMouseWheel
// computes it, and passes the event on untouched. An event SDL will drop,
// with no delta, is not recorded.
@(private)
on_scroll :: proc "c" (block: rawptr, event: ^NS.Event) -> ^NS.Event {
	r: Scroll_Record
	r.precise = bool(event->hasPreciseScrollingDeltas())
	if r.precise {
		r.x = f32(-f64(event->scrollingDeltaX()) * f64(f32(0.1)))
		r.y = f32(f64(event->scrollingDeltaY()) * f64(f32(0.1)))
	} else {
		r.x = notch(-f32(event->deltaX()))
		r.y = notch(f32(event->deltaY()))
	}
	if r.x == 0 && r.y == 0 {
		return event
	}
	if record_count == MAX_RECORDS {
		record_start = (record_start + 1) % MAX_RECORDS
		record_count -= 1
	}
	records[(record_start + record_count) % MAX_RECORDS] = r
	record_count += 1
	return event
}

// notch rounds a wheel's delta away from zero, as SDL does.
@(private)
notch :: proc "contextless" (v: f32) -> f32 {
	if v > 0 {
		return f32(int(v)) + (0 if f32(int(v)) == v else 1)
	}
	if v < 0 {
		return f32(int(v)) - (0 if f32(int(v)) == v else 1)
	}
	return 0
}

// wheel_precise says whether the wheel event SDL sent with x and y came
// from a precise device, a trackpad or a Magic Mouse: the oldest record
// with its value, dropping any older, which SDL must have dropped too.
// An event with no record is taken for a wheel's.
wheel_precise :: proc(x, y: f32) -> bool {
	for record_count > 0 {
		r := records[record_start]
		record_start = (record_start + 1) % MAX_RECORDS
		record_count -= 1
		if near(r.x, x) && near(r.y, y) {
			return r.precise
		}
	}
	return false
}

@(private = "file")
near :: proc(a, b: f32) -> bool {
	d := a - b
	return d * d <= 1e-10 * max(1, a * a)
}
