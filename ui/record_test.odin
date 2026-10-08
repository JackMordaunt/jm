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
	// A folder of its own: one file shared by name was written by every run
	// on the machine at once.
	dir, _ := os.make_directory_temp("", "jm-record-*", context.temp_allocator)
	defer os.remove_all(dir)
	path, _ := os.join_path({dir, "record_test.rec"}, context.temp_allocator)
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

// Shape_Model is what shape_view saw of the one shape it needs.
@(private = "file")
Shape_Model :: struct {
	status: Status,
	asked:  int, // needs the data host was handed
}

@(private = "file")
shape_view :: proc(gtx: ^Ctx, user: rawptr) {
	model := (^Shape_Model)(user)
	_, model.status = need_raw(gtx, "thing", {1})
}

@(private = "file")
note_need :: proc(user: rawptr, need: Need, added: bool) {
	(^Shape_Model)(user).asked += 1
}

@(test)
a_replay_delivers_the_recorded_shapes_and_leaves_the_application_alone :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	model: Shape_Model
	inbox: Inbox
	inbox_init(&inbox)
	defer inbox_destroy(&inbox)
	host := Data_Host{user = &model, on_need = note_need, inbox = &inbox}
	probe: Probe
	probe_init(&probe, shape_view, &model, {100, 100}, data = &host)
	defer probe_destroy(&probe)
	asked := model.asked // the first frame's need went to the application
	testing.expect_value(t, asked, 1)

	shape := Delivery{need_key("thing", {1}), .Ready, {7}}
	recording := make([dynamic]byte, context.temp_allocator)
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, nil, context.temp_allocator, shapes = {shape}))
	// An answer the application gives now is not the recording's: a
	// replay does not take it.
	inbox_put(&inbox, need_key("thing", {1}), {9}, .Loading)
	frames, ok := probe_replay(&probe, recording[:])
	testing.expect(t, ok)
	testing.expect_value(t, frames, 1)
	testing.expect_value(t, model.status, Status.Ready) // not the Loading the application gave since
	testing.expect(t, inbox_pending(&inbox))
	testing.expect_value(t, model.asked, asked)
}

// Paste_Model counts the pastes paste_view's area received.
@(private = "file")
Paste_Model :: struct {
	pastes: int,
	text:   [8]u8, // the last paste's first bytes
	length: int, // the last paste's length
}

@(private = "file")
paste_view :: proc(gtx: ^Ctx, user: rawptr) {
	model := (^Paste_Model)(user)
	ops.input_area(gtx.scene, 1, ops.Rect{0, 0, 100, 100}, {.Press})
	for event in events(gtx, 1) {
		#partial switch event.kind {
		case .Press:
			clipboard_read(gtx, 1)
		case .Paste:
			model.pastes += 1
			model.length = copy(model.text[:], event.text)
		}
	}
}

@(test)
a_replay_takes_the_recorded_paste_not_its_own :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	model: Paste_Model
	probe: Probe
	probe_init(&probe, paste_view, &model, {100, 100})
	defer probe_destroy(&probe)
	// The press asks for the clipboard; the platform's answer came in
	// with the next frame's input, as a live loop records it.
	recording := make([dynamic]byte, context.temp_allocator)
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, {{kind = .Move, pos = {50, 50}}, {kind = .Press, pos = {50, 50}}}, context.temp_allocator))
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, {{kind = .Release, pos = {50, 50}}, {kind = .Paste, text = "hi", mime = TEXT_MIME}}, context.temp_allocator))
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, nil, context.temp_allocator))
	_, ok := probe_replay(&probe, recording[:])
	testing.expect(t, ok)
	testing.expect_value(t, model.pastes, 1)
	testing.expect_value(t, string(model.text[:model.length]), "hi")
}

// Colour_Model is the colour colour_view fills its square with and the
// id its area takes.
@(private = "file")
Colour_Model :: struct {
	colour: ops.Color,
	area:   ops.Area_Id,
}

@(private = "file")
colour_view :: proc(gtx: ^Ctx, user: rawptr) {
	model := (^Colour_Model)(user)
	ops.fill(gtx.scene, ops.Rect{10, 10, 20, 20}, model.colour)
	ops.input_area(gtx.scene, model.area, ops.Rect{10, 10, 20, 20}, {.Press})
	ops.semantic(gtx.scene, model.area, 0, {role = .Button, label = "Go"}, ops.Rect{10, 10, 20, 20})
	for event in events(gtx, model.area) {
		if event.kind == .Press {
			model.colour.g += 100
		}
	}
}

// colour_digests replays a_click_recording through colour_view from
// model and returns each frame's digest.
@(private = "file")
colour_digests :: proc(model: Colour_Model) -> []u64 {
	model := model
	probe: Probe
	probe_init(&probe, colour_view, &model, {100, 100})
	defer probe_destroy(&probe)
	digests, _ := probe_replay_digests(&probe, a_click_recording({20, 20}, 1, context.temp_allocator), context.temp_allocator)
	return digests
}

@(test)
a_digest_follows_what_a_frame_shows_not_its_ids :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	blessed := colour_digests({colour = {200, 0, 0, 255}, area = 1})
	testing.expect_value(t, len(blessed), 2)
	testing.expect(t, blessed[0] != blessed[1]) // the press turned it

	// Text and back, as -bless keeps them and -check reads them.
	kept, ok := digests_parse(digests_format(blessed, context.temp_allocator), context.temp_allocator)
	testing.expect(t, ok)
	_, same := digests_compare(kept, blessed)
	testing.expect(t, same)

	// Another id, as a moved line gives: the same picture.
	_, same = digests_compare(kept, colour_digests({colour = {200, 0, 0, 255}, area = 2}))
	testing.expect(t, same)

	// Another colour: every frame differs, the first named.
	mismatch, differs := digests_compare(kept, colour_digests({colour = {0, 0, 200, 255}, area = 1}))
	testing.expect(t, !differs)
	testing.expect_value(t, mismatch, Digest_Mismatch{first = 1, differ = 2, want = 2, got = 2})

	// A replay one frame short says so.
	mismatch, differs = digests_compare(kept, blessed[:1])
	testing.expect(t, !differs)
	testing.expect_value(t, mismatch, Digest_Mismatch{want = 2, got = 1})

	_, ok = digests_parse("1 00ff\n3 00ff\n", context.temp_allocator)
	testing.expect(t, !ok) // frame 2 is missing
}

@(test)
replay_to_stops_at_the_frame_asked_for :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	model: Replay_Model
	probe: Probe
	probe_init(&probe, replay_view, &model, {100, 100})
	defer probe_destroy(&probe)
	recording := a_click_recording({50, 50}, 1, context.temp_allocator)
	ran, ok := probe_replay_to(&probe, recording, 1)
	testing.expect(t, ok)
	testing.expect_value(t, ran, 1)
	testing.expect_value(t, model.clicks, 0) // pressed, not yet released
	ran, ok = probe_replay_to(&probe, recording, 5)
	testing.expect(t, ok)
	testing.expect_value(t, ran, 2) // all it has
	testing.expect_value(t, model.clicks, 1) // the release ran
}

// Stale_Model is what stale_view saw of the events aimed at its area.
@(private = "file")
Stale_Model :: struct {
	picked:  int,
	focused: int,
	frames:  int,
}

@(private = "file")
stale_view :: proc(gtx: ^Ctx, user: rawptr) {
	model := (^Stale_Model)(user)
	model.frames += 1
	ops.input_area(gtx.scene, 5, ops.Rect{0, 0, 50, 50}, {.Press, .Focus})
	for event in events(gtx, 5) {
		#partial switch event.kind {
		case .Picked:
			model.picked += 1
		case .Focus:
			model.focused += 1
		}
	}
}

@(test)
a_replay_drops_events_for_an_area_the_frame_no_longer_has :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// Recorded by a build whose widget took id 9: a moved line gives it 5.
	model: Stale_Model
	probe: Probe
	probe_init(&probe, stale_view, &model, {100, 100})
	defer probe_destroy(&probe)
	recording := make([dynamic]byte, context.temp_allocator)
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, {{kind = .Picked, area = 9, text = "/tmp/a"}, {kind = .Focus, area = 9}}, context.temp_allocator))
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, nil, context.temp_allocator))
	frames, ok := probe_replay(&probe, recording[:])
	testing.expect(t, ok)
	testing.expect_value(t, frames, 2)
	testing.expect_value(t, model.picked, 0)
	testing.expect_value(t, model.focused, 0)

	// The same events for the id it has now arrive.
	recording = make([dynamic]byte, context.temp_allocator)
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, {{kind = .Picked, area = 5, text = "/tmp/a"}, {kind = .Focus, area = 5}}, context.temp_allocator))
	ipc.frame_append(&recording, encode_input({100, 100}, 1, 1.0 / 60, nil, context.temp_allocator))
	_, ok = probe_replay(&probe, recording[:])
	testing.expect(t, ok)
	testing.expect_value(t, model.picked, 1)
	testing.expect_value(t, model.focused, 1)
}
