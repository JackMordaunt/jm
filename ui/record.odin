package ui

import "core:fmt"
import "core:os"
import "core:strconv"
import "core:strings"
import "jm:ui/ipc"
import "jm:ui/ops"

// A recording is every frame's input, as the loop received it, so a
// session can be run again without the window: a bug seen live is
// replayed headless, then dumped, rendered or inspected at the frame it
// showed on. The hot-reload child and ui/shell's own loop both record when
// RECORD_ENV names a file; render.Headless's -replay step and
// probe_replay run one. The file is ipc frames, each an encode_input
// carrying the frame's events, size, density and dt, and the shapes the
// application answered before it, so a replay needs no application.
//
//	JM_UI_RECORD=build/session.rec just material-kitchen
//	material-kitchen-child -replay build/session.rec -dump
//
// A recording is also a regression test. Each replayed frame has a
// digest of what it shows (frame_digest); -bless keeps a recording's
// digests beside it, and -check replays it again and names the first
// frame that no longer shows the same. -replay-to stops at a frame, to
// look at it. -timeline lists the frames where something happened and
// -diff says what one frame changed, both as text (timeline.odin).

// RECORD_ENV is the environment variable naming the file a frame loop
// appends its inputs to; unset, nothing is recorded.
RECORD_ENV :: "JM_UI_RECORD"

// Recorder is an open recording file. A zero Recorder records nothing,
// so a loop calls recorder_write unconditionally.
Recorder :: struct {
	f:      ^os.File,
	frames: int, // inputs written so far
}

// recorder_from_env opens the file RECORD_ENV names, if set, truncating
// it: a session's recording starts with the session. It returns whether
// one is open; an unset variable is the usual false, a file that cannot
// be opened is the other.
recorder_from_env :: proc(r: ^Recorder) -> bool {
	buf: [512]u8
	path := os.get_env(buf[:], RECORD_ENV)
	if path == "" {
		return false
	}
	return recorder_open(r, path)
}

// recorder_open opens path for recording, truncating it.
recorder_open :: proc(r: ^Recorder, path: string) -> bool {
	f, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil {
		return false
	}
	r^ = {f = f}
	return true
}

// recorder_write appends one frame's input (an encode_input) to r, if r
// is open. A write that fails closes r: the recording stops rather than
// going on with a hole.
recorder_write :: proc(r: ^Recorder, input: []byte) {
	if r.f == nil {
		return
	}
	if !ipc.write_frame(r.f, input) {
		recorder_close(r)
		return
	}
	r.frames += 1
}

// recorder_close closes r's file, if open.
recorder_close :: proc(r: ^Recorder) {
	if r.f != nil {
		os.close(r.f)
		r.f = nil
	}
}

// Replay is a recording being run a frame at a time: what of it is left,
// and how many of its frames have run.
Replay :: struct {
	rest:   []byte,
	frames: int,
}

// replay_open starts a replay of data, a recording. data must outlive
// replay.
replay_open :: proc(replay: ^Replay, data: []byte) {
	replay^ = {rest = data}
}

// replay_done reports whether every frame of replay has run.
replay_done :: proc(replay: ^Replay) -> bool {
	return len(replay.rest) == 0
}

// replay_input is the input of replay's next frame, an encode_input for
// decode_input, without running it: what a tool shows beside the frame.
replay_input :: proc(replay: ^Replay) -> (payload: []byte, ok: bool) {
	payload, _, ok = ipc.frame_next(replay.rest)
	return
}

// probe_replay_step runs replay's next recorded frame through probe: its size
// becomes the probe's, its dt the frame's, its events are pushed and
// routed as the loop routed them, its shapes delivered and its restore
// given. Pointer positions are recorded in device pixels and the probe
// lays out at density 1, so they are scaled by the recorded density.
// While it runs, the probe is replaying: the recording carries the platform's
// answers (a clipboard read's Paste) and the application's shapes, so the
// probe gives neither and its Data_Host is left alone. It is false, with
// nothing run, when replay is done or its data stops being a recording.
probe_replay_step :: proc(probe: ^Probe, replay: ^Replay) -> bool {
	payload, after, fok := ipc.frame_next(replay.rest)
	if !fok {
		return false
	}
	shapes: []Delivery
	size, density, dt, events, _, restore, dok := decode_input(payload, ops.frame_arena_allocator(&probe.arena), &shapes)
	if !dok {
		return false
	}
	replay.rest = after
	probe.size = size
	for &event in events {
		if density != 0 && density != 1 {
			event.pos = {event.pos.x / density, event.pos.y / density}
		}
		router_push(&probe.router, event)
	}
	for shape in shapes {
		inbox_put(&probe.inbox, shape.key, shape.data, shape.status)
	}
	if restore != nil {
		probe_restore(probe, restore)
	}
	probe.replaying = true
	defer probe.replaying = false
	probe_advance(probe, 1, dt)
	replay.frames += 1
	return true
}

// probe_replay runs every frame of a recording through probe, a
// probe_replay_step each. It returns how many frames ran, and false when
// the data stops being a recording partway (the frames before that have
// run).
probe_replay :: proc(probe: ^Probe, data: []byte) -> (frames: int, ok: bool) {
	replay: Replay
	replay_open(&replay, data)
	for !replay_done(&replay) {
		if !probe_replay_step(probe, &replay) {
			return replay.frames, false
		}
	}
	return replay.frames, true
}

// probe_replay_to runs a recording's frames through probe until frames of
// them have run, or the recording ends first: the frame it stops at is
// probe_current, to dump, render or inspect. It returns how many ran,
// and false when the data stops being a recording first.
probe_replay_to :: proc(probe: ^Probe, data: []byte, frames: int) -> (ran: int, ok: bool) {
	replay: Replay
	replay_open(&replay, data)
	for replay.frames < frames && !replay_done(&replay) {
		if !probe_replay_step(probe, &replay) {
			return replay.frames, false
		}
	}
	return replay.frames, true
}

// probe_replay_digests runs every frame of a recording through probe, as
// probe_replay does, and returns each frame's frame_digest, in order, on
// allocator. ok is false when the data stops being a recording partway;
// digests then hold the frames that ran.
probe_replay_digests :: proc(probe: ^Probe, data: []byte, allocator := context.allocator) -> (digests: []u64, ok: bool) {
	out := make([dynamic]u64, allocator)
	replay: Replay
	replay_open(&replay, data)
	ok = true
	for !replay_done(&replay) {
		if !probe_replay_step(probe, &replay) {
			ok = false
			break
		}
		append(&out, frame_digest(probe_current(probe)))
	}
	return out[:], ok
}

// frame_picture is what frame shows, as text on allocator, a line each:
// its draws and clips as dump_frame prints them but named by content
// (write_frame_draws), and its semantic tree without the nodes' ids.
// Area ids hash the call site's file and line, so an edit that moves a
// line, or a build in another folder, changes them while the frame looks
// and reads the same; they are left out, and indices are, so one draw
// added changes one line. frame_digest hashes it and -diff compares two
// of it.
frame_picture :: proc(frame: ^Frame, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	write_frame_draws(&sb, frame, by_content = true)
	write_frame_clips(&sb, frame, by_content = true)
	strings.write_string(&sb, "semantics\n")
	for node in frame.nodes {
		semantics := node.semantics
		// Whether it points at another node, not which one's id.
		semantics.labelled_by = 1 if semantics.labelled_by != 0 else 0
		semantics.active_descendant = 1 if semantics.active_descendant != 0 else 0
		fmt.sbprintf(&sb, "  node layer=%d ", node.layer)
		ops.write_rect(&sb, node.rect)
		strings.write_byte(&sb, ' ')
		ops.write_semantics(&sb, semantics)
		strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// frame_digest is a hash of what frame shows: of its frame_picture, so
// it changes only when the picture or what a screen reader says does.
frame_digest :: proc(frame: ^Frame) -> u64 {
	picture := frame_picture(frame)
	defer delete(picture)
	return fnv_bytes(FNV_OFFSET, transmute([]u8)picture)
}

// DIGESTS_EXT is what -bless appends to a recording's path to name the
// file its digests are kept in.
DIGESTS_EXT :: ".digests"

// digests_format writes digests a line each, the frame's number from 1
// and its digest in hex: text, so a changed recording diffs by frame.
digests_format :: proc(digests: []u64, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	for digest, ii in digests {
		fmt.sbprintf(&sb, "%d %016x\n", ii + 1, digest)
	}
	return strings.to_string(sb)
}

// digests_parse reads digests_format's text back. ok is false for a line
// that is not a frame's number, in order, and a hex digest.
digests_parse :: proc(text: string, allocator := context.allocator) -> (digests: []u64, ok: bool) {
	out := make([dynamic]u64, allocator)
	rest := text
	for line in strings.split_lines_iterator(&rest) {
		if line == "" {
			continue
		}
		number, _, hex := strings.partition(line, " ")
		frame, frame_ok := strconv.parse_int(number, 10)
		digest, digest_ok := strconv.parse_u64(hex, 16)
		if !frame_ok || !digest_ok || frame != len(out) + 1 {
			delete(out)
			return nil, false
		}
		append(&out, digest)
	}
	return out[:], true
}

// Digest_Mismatch is how a replay's digests differ from the blessed
// ones: the first frame that shows something else (1-based; 0 when
// every frame both have agrees), how many of the frames both have
// differ, and the frame counts, which differ when the recording or the
// replay changed length.
Digest_Mismatch :: struct {
	first:      int,
	differ:     int,
	want, got:  int,
}

// digests_compare compares a replay's digests, got, with the blessed
// ones, want. same is true when they are the same frames.
digests_compare :: proc(want, got: []u64) -> (mismatch: Digest_Mismatch, same: bool) {
	mismatch.want, mismatch.got = len(want), len(got)
	for ii in 0 ..< min(len(want), len(got)) {
		if want[ii] != got[ii] {
			if mismatch.first == 0 {
				mismatch.first = ii + 1
			}
			mismatch.differ += 1
		}
	}
	return mismatch, mismatch.differ == 0 && mismatch.want == mismatch.got
}

// digest_mismatch_report says how a check failed, in a line or two that
// name the frame to look at with -replay-to.
digest_mismatch_report :: proc(mismatch: Digest_Mismatch, path: string, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	if mismatch.differ > 0 {
		fmt.sbprintf(&sb, "%s: %d of %d frame(s) differ, the first frame %d; look at it with -replay-to %s %d\n", path, mismatch.differ, min(mismatch.want, mismatch.got), mismatch.first, path, mismatch.first)
	}
	if mismatch.want != mismatch.got {
		fmt.sbprintf(&sb, "%s: blessed %d frame(s), replayed %d\n", path, mismatch.want, mismatch.got)
	}
	return strings.to_string(sb)
}
