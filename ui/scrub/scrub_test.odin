package scrub

import "core:testing"
import "jm:ui"
import "jm:ui/ipc"
import "jm:ui/ops"

// Square is the colour square_view fills with, which each press turns.
@(private = "file")
Square :: struct {
	colour: ops.Color,
}

@(private = "file")
square_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	square := (^Square)(user)
	ops.fill(gtx.scene, ops.Rect{0, 0, 50, 50}, square.colour)
	ops.input_area(gtx.scene, 1, ops.Rect{0, 0, 50, 50}, {.Press})
	for event in ui.events(gtx, 1) {
		if event.kind == .Press {
			square.colour.g += 60
		}
	}
}

// a_recording is four frames: still, a press, still, still.
@(private = "file")
a_recording :: proc() -> []byte {
	data := make([dynamic]byte, context.temp_allocator)
	ipc.frame_append(&data, ui.encode_input({100, 80}, 1, 0.5, nil, context.temp_allocator))
	ipc.frame_append(&data, ui.encode_input({100, 80}, 1, 0.25, {{kind = .Move, pos = {10, 10}}, {kind = .Press, pos = {10, 10}}}, context.temp_allocator))
	ipc.frame_append(&data, ui.encode_input({100, 80}, 1, 0.25, {{kind = .Release, pos = {10, 10}}}, context.temp_allocator))
	ipc.frame_append(&data, ui.encode_input({100, 80}, 1, 0.25, nil, context.temp_allocator))
	return data[:]
}

@(test)
a_tape_keeps_each_picture_once_and_marks_what_differs :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	square := Square{{200, 0, 0, 255}}
	tape: Tape
	defer tape_destroy(&tape)
	testing.expect(t, tape_record(&tape, {ui = square_view, user = &square}, a_recording()))
	testing.expect_value(t, len(tape.moments), 4)
	// The press shows on the frame after it: red, red, green, green.
	testing.expect_value(t, len(tape.pictures), 2)
	testing.expect_value(t, tape.moments[1].picture, 0)
	testing.expect_value(t, tape.moments[2].picture, 1)
	testing.expect_value(t, tape.moments[3].time, f64(1.25))
	testing.expect_value(t, tape.moments[1].input, "Move 10,10  Press 10,10")
	testing.expect_value(t, tape.pictures[0].size, ops.Size{100, 80})
	testing.expect(t, !tape.blessed)

	testing.expect_value(t, tape_change_after(&tape, 0), 2)
	testing.expect_value(t, tape_change_after(&tape, 2), 3) // none after: the end
	testing.expect_value(t, tape_change_before(&tape, 3), 2)
	testing.expect_value(t, tape_change_before(&tape, 2), 0)

	// Blessed with the first two frames' digests swapped in: those two
	// differ, and a fourth is missing.
	digests := make([]u64, 3, context.temp_allocator)
	again := Square{{200, 0, 0, 255}}
	probe: ui.Probe
	ui.probe_init(&probe, square_view, &again, {100, 80})
	got, _ := ui.probe_replay_digests(&probe, a_recording(), context.temp_allocator)
	ui.probe_destroy(&probe)
	digests[0], digests[1], digests[2] = got[2], got[1], got[2]
	square = {{200, 0, 0, 255}}
	marked: Tape
	defer tape_destroy(&marked)
	testing.expect(t, tape_record(&marked, {ui = square_view, user = &square}, a_recording(), digests))
	testing.expect(t, marked.blessed)
	testing.expect_value(t, marked.differ, 2)
	testing.expect(t, marked.moments[0].differs)
	testing.expect(t, !marked.moments[1].differs)
	testing.expect(t, marked.moments[3].differs)
}

@(test)
the_scrubber_seeks_within_the_tape_and_plays_at_the_recorded_pace :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	square := Square{{200, 0, 0, 255}}
	tape: Tape
	defer tape_destroy(&tape)
	testing.expect(t, tape_record(&tape, {ui = square_view, user = &square}, a_recording()))
	scrubber: Scrubber
	scrubber_init(&scrubber, &tape, "a.rec")
	defer scrubber_destroy(&scrubber)
	probe: ui.Probe
	ui.probe_init(&probe, view, &scrubber, {900, 600})
	defer ui.probe_destroy(&probe)

	ui.probe_key(&probe, .End)
	testing.expect_value(t, scrubber.at, 3)
	ui.probe_key(&probe, .Right) // past the end stays there
	testing.expect_value(t, scrubber.at, 3)
	ui.probe_key(&probe, .Left, {.Shift})
	testing.expect_value(t, scrubber.at, 2)
	ui.probe_key(&probe, .Home)
	testing.expect_value(t, scrubber.at, 0)
	// The picture shown is the moment's: the recorded red square.
	testing.expect_value(t, scrubber.shown, 0)

	// Space plays: 0.25 s on, frame 1 (0.75 s) is reached, not frame 2.
	ui.probe_key(&probe, .Space)
	testing.expect(t, scrubber.playing)
	ui.probe_advance(&probe, 1, 0.25)
	testing.expect_value(t, scrubber.at, 1)
	ui.probe_advance(&probe, 4, 0.25)
	testing.expect_value(t, scrubber.at, 3)
	testing.expect(t, !scrubber.playing) // stopped at the end
	testing.expect_value(t, scrubber.shown, 1)
}
