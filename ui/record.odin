package ui

import "core:os"
import "jm:ui/ipc"
import "jm:ui/ops"

// A recording is every frame's input, as the loop received it, so a
// session can be run again without the window: a bug seen live is
// replayed headless, then dumped, rendered or inspected at the frame it
// showed on. The hot-reload child and ui/shell's own loop both record when
// RECORD_ENV names a file; render.Headless's -replay step and
// probe_replay run one. The file is ipc frames, each an encode_input.
//
//	JM_UI_RECORD=build/session.rec just material-kitchen
//	material-kitchen-child -replay build/session.rec -dump

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

// probe_replay runs every frame of a recording through p: each input's
// size becomes the probe's, its dt the frame's, and its events are
// pushed and routed as the loop routed them. Pointer positions are
// recorded in device pixels and the probe lays out at density 1, so
// they are scaled by the recorded density. It returns how many frames
// ran, and false when the data stops being a recording partway (the
// frames before that have run).
probe_replay :: proc(p: ^Probe, data: []byte) -> (frames: int, ok: bool) {
	rest := data
	for len(rest) > 0 {
		payload, after, fok := ipc.frame_next(rest)
		if !fok {
			return frames, false
		}
		rest = after
		size, density, dt, events, _, _, dok := decode_input(payload, ops.frame_arena_allocator(&p.arena))
		if !dok {
			return frames, false
		}
		p.size = size
		for e in events {
			e := e
			if density != 0 && density != 1 {
				e.pos = {e.pos.x / density, e.pos.y / density}
			}
			router_push(&p.router, e)
		}
		probe_advance(p, 1, dt)
		frames += 1
	}
	return frames, true
}
