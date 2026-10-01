package ui

import "core:os"
import "jm:ui/ipc"
import "jm:ui/ops"
import "core:testing"

// replay_view is one button, whose clicks it counts.
@(private = "file")
Replay_Model :: struct {
	clicks: int,
	dt:     f32, // the last frame's dt
}

@(private = "file")
replay_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Replay_Model)(user)
	m.dt = gtx.dt
	ops.input_area(gtx.scene, 1, ops.Rect{40, 40, 20, 20}, {.Press, .Release})
	ops.tag(gtx.scene, 1, "Go")
	for e in events(gtx, 1) {
		if e.kind == .Release {
			m.clicks += 1
		}
	}
}

// a_click_recording is the two inputs a click takes, at density, as a
// loop would have recorded them: the press at device point at, then the
// release.
@(private = "file")
a_click_recording :: proc(at: ops.Point, density: f32, allocator := context.allocator) -> []byte {
	buf := make([dynamic]byte, allocator)
	ipc.frame_append(&buf, encode_input({100, 100}, density, 0.25, {{kind = .Move, pos = at}, {kind = .Press, pos = at}}, allocator))
	ipc.frame_append(&buf, encode_input({100, 100}, density, 0.5, {{kind = .Release, pos = at}}, allocator))
	return buf[:]
}

@(test)
replay_runs_a_recording_through_the_probe :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	m: Replay_Model
	p: Probe
	probe_init(&p, replay_view, &m, {10, 10}) // the recording brings its own size
	defer probe_destroy(&p)
	// Recorded at density 2: the device point 100,100 is the button's
	// middle, 50,50, at the density 1 the probe lays out at.
	frames, ok := probe_replay(&p, a_click_recording({100, 100}, 2, context.temp_allocator))
	testing.expect(t, ok)
	testing.expect_value(t, frames, 2)
	testing.expect_value(t, m.clicks, 1)
	testing.expect_value(t, m.dt, f32(0.5)) // each frame ran at its recorded dt
	testing.expect_value(t, p.size, ops.Size{100, 100})
	testing.expect_value(t, p.dt, f32(1.0 / 60)) // and the probe's own dt is back

	// A recording cut off mid-frame runs what is whole, then says so.
	data := a_click_recording({100, 100}, 2, context.temp_allocator)
	frames, ok = probe_replay(&p, data[:len(data) - 3])
	testing.expect(t, !ok)
	testing.expect_value(t, frames, 1)
}

@(test)
a_recorder_writes_what_replay_reads :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	path := "build/test/record_test.rec"
	defer os.remove(path)
	r: Recorder
	recorder_write(&r, {1}) // a zero recorder records nothing, and does not mind
	testing.expect(t, recorder_open(&r, path))
	recorder_write(&r, encode_input({100, 100}, 1, 1.0 / 60, {{kind = .Move, pos = {50, 50}}, {kind = .Press, pos = {50, 50}}}, context.temp_allocator))
	recorder_write(&r, encode_input({100, 100}, 1, 1.0 / 60, {{kind = .Release, pos = {50, 50}}}, context.temp_allocator))
	testing.expect_value(t, r.frames, 2)
	recorder_close(&r)
	testing.expect(t, r.f == nil)

	data, err := os.read_entire_file(path, context.temp_allocator)
	testing.expect(t, err == nil)
	m: Replay_Model
	p: Probe
	probe_init(&p, replay_view, &m, {100, 100})
	defer probe_destroy(&p)
	frames, ok := probe_replay(&p, data)
	testing.expect(t, ok)
	testing.expect_value(t, frames, 2)
	testing.expect_value(t, m.clicks, 1)
}
