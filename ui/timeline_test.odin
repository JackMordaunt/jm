package ui

import "core:strings"
import "core:testing"
import "jm:ui/ipc"
import "jm:ui/ops"

@(test)
an_input_summary_reads_a_run_of_moves_as_one :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Recorded at density 2: device points halve.
	payload := encode_input({100, 100}, 2, 0.25, {{kind = .Move, pos = {20, 20}}, {kind = .Move, pos = {40, 60}}, {kind = .Press, pos = {40, 60}}, {kind = .Key, key = .Enter}}, context.temp_allocator)
	summary, ok := input_summary(payload, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, summary.line, "Move×2 20,30  Press 20,30  Key Enter")
	testing.expect_value(t, summary.dt, f32(0.25))
	testing.expect(t, !summary.moves_only)

	moved, _ := input_summary(encode_input({100, 100}, 1, 0.25, {{kind = .Move, pos = {5, 5}}}, context.temp_allocator), context.temp_allocator)
	testing.expect(t, moved.moves_only)
	idle, _ := input_summary(encode_input({100, 100}, 1, 0.25, nil, context.temp_allocator), context.temp_allocator)
	testing.expect_value(t, idle.line, "")
	testing.expect(t, !idle.moves_only)
	_, ok = input_summary({1, 2, 3}, context.temp_allocator)
	testing.expect(t, !ok)
}

// Lamp_Model is a square lamp_view turns on with a press anywhere on it.
@(private = "file")
Lamp_Model :: struct {
	on: bool,
}

@(private = "file")
lamp_view :: proc(gtx: ^Ctx, user: rawptr) {
	model := (^Lamp_Model)(user)
	ops.fill(gtx.scene, ops.Rect{0, 0, 40, 40}, ops.Color{250, 200, 0, 255} if model.on else ops.Color{60, 60, 60, 255})
	ops.input_area(gtx.scene, 1, ops.Rect{0, 0, 40, 40}, {.Press})
	for event in events(gtx, 1) {
		if event.kind == .Press {
			model.on = true
		}
	}
}

// lamp_recording is six frames: idle, a move, a press outside the lamp,
// a press on it, idle, idle.
@(private = "file")
lamp_recording :: proc() -> []byte {
	data := make([dynamic]byte, context.temp_allocator)
	ipc.frame_append(&data, encode_input({100, 100}, 1, 0.5, nil, context.temp_allocator))
	ipc.frame_append(&data, encode_input({100, 100}, 1, 0.5, {{kind = .Move, pos = {80, 80}}}, context.temp_allocator))
	ipc.frame_append(&data, encode_input({100, 100}, 1, 0.5, {{kind = .Press, pos = {80, 80}}}, context.temp_allocator))
	ipc.frame_append(&data, encode_input({100, 100}, 1, 0.5, {{kind = .Move, pos = {10, 10}}, {kind = .Press, pos = {10, 10}}}, context.temp_allocator))
	ipc.frame_append(&data, encode_input({100, 100}, 1, 0.5, nil, context.temp_allocator))
	ipc.frame_append(&data, encode_input({100, 100}, 1, 0.5, nil, context.temp_allocator))
	return data[:]
}

@(test)
a_timeline_lists_the_frames_where_something_happened :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	model: Lamp_Model
	probe: Probe
	probe_init(&probe, lamp_view, &model, {100, 100})
	defer probe_destroy(&probe)
	frames, ok := probe_replay_timeline(&probe, lamp_recording(), context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, len(frames), 6)
	// The press outside changed nothing, and is listed so a reader sees
	// it did nothing; the move alone is not. The press on the lamp shows
	// the frame after it.
	want := "6 frame(s) over 3.000 s; the picture changed on 1\n" +
		"1  0.500 s\n" +
		"3  1.500 s  Press 80,80\n" +
		"4  2.000 s  Move 10,10  Press 10,10\n" +
		"5  2.500 s  changed\n" +
		"6  3.000 s\n"
	testing.expect_value(t, timeline_report(frames, nil, context.temp_allocator), want)

	// Blessed with frame 6 wrong, and one short of a seventh.
	blessed := make([]u64, 7, context.temp_allocator)
	for frame, ii in frames {
		blessed[ii] = frame.digest
	}
	blessed[5] = 1
	report := timeline_report(frames, blessed, context.temp_allocator)
	testing.expect(t, strings.has_prefix(report, "6 frame(s) over 3.000 s; the picture changed on 1; 1 differ from the blessed digests (7 blessed)\n"))
	testing.expect(t, strings.has_suffix(report, "6  3.000 s  differs\n"))
}

@(test)
a_diff_says_what_one_frame_changed :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	model: Lamp_Model
	probe: Probe
	probe_init(&probe, lamp_view, &model, {100, 100})
	defer probe_destroy(&probe)
	before, after, input, ok := probe_replay_diff(&probe, lamp_recording(), 5, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, input.line, "")
	diff := picture_diff(before, after, context.temp_allocator)
	lines := strings.split_lines(strings.trim_right(diff, "\n"), context.temp_allocator)
	if testing.expect_value(t, len(lines), 3) {
		testing.expect_value(t, lines[0], "1 line(s) removed, 1 added")
		testing.expect_value(t, lines[1], "-   draw clip=none [1 0 0 1 0 0] fill rect 0 0 40 40 #3c3c3c")
		testing.expect_value(t, lines[2], "+   draw clip=none [1 0 0 1 0 0] fill rect 0 0 40 40 #fac800")
	}

	_, _, _, ok = probe_replay_diff(&probe, lamp_recording(), 7, context.temp_allocator)
	testing.expect(t, !ok) // past the end
}

@(test)
picture_diff_keeps_order_and_names_a_same_picture :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	testing.expect_value(t, picture_diff("a\nb\n", "a\nb\n", context.temp_allocator), "the same picture\n")
	testing.expect_value(t, picture_diff("a\nb\nc\nd\n", "a\nx\nc\nd\ny\n", context.temp_allocator), "1 line(s) removed, 2 added\n- b\n+ x\n+ y\n")
	// Too big to match in order, the same lines come out by count.
	changes := make([dynamic]string, context.temp_allocator)
	diff_counted({"a", "b", "b", "c"}, {"b", "c", "d"}, &changes, context.temp_allocator)
	testing.expect_value(t, len(changes), 3)
	testing.expect_value(t, changes[0], "- a")
	testing.expect_value(t, changes[1], "- b")
	testing.expect_value(t, changes[2], "+ d")
}
