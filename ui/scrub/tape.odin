// Package scrub plays a recording back in a window, a frame at a time,
// forwards and backwards: the scrubber. A recording (ui.RECORD_ENV) is
// replayed once, headless, through the application that made it, and
// each picture it showed is kept; the window then moves over those
// pictures freely, since going back needs no rewind of the application.
//
//	JM_UI_RECORD=build/session.rec just material-kitchen
//	material-kitchen-child -scrub build/session.rec
//
// Left and Right step a frame, with Shift to the next or last frame whose
// picture changed; Home and End go to the ends; Space plays at the
// recorded pace. The timeline marks every change, and in red every frame
// whose digest differs from the recording's blessed ones (-bless), the
// frames -check would name. The pointer over the picture inspects what
// is under it in that frame: the widget, its source line and its box.
package scrub

import "core:mem/virtual"

import "jm:ui"
import "jm:ui/ops"
import "jm:ui/render"

// App is what the scrubber needs of an application to replay it: the ui
// proc and its state as it was when the recording began, and its fonts.
App :: struct {
	ui:        proc(gtx: ^ui.Ctx, user: rawptr),
	user:      rawptr,
	fonts:     []ops.Font_Ref,
	fallbacks: []ops.Font_Id,
	title:     string, // the window's; "" names it after the recording
}

// Picture is one picture a replay showed: its scene, encoded as ops.encode
// writes it, and the size it was laid out at.
Picture :: struct {
	scene: []byte,
	size:  ops.Size,
}

// Moment is one recorded frame as a Tape keeps it.
Moment :: struct {
	picture: int, // the picture it showed, in Tape.pictures
	time:    f64, // seconds since the recording began: the frames' dt summed
	dt:      f32,
	input:   string, // its events, as a line of text
	differs: bool, // its digest is not the blessed one
}

// Tape is a recording replayed once: every frame, and each distinct
// picture once, so a run of frames that showed the same costs one.
Tape :: struct {
	pictures: [dynamic]Picture,
	moments: [dynamic]Moment,
	blessed: bool, // there were blessed digests to compare with
	differ:  int, // frames whose digest differs from the blessed one
	arena:   virtual.Arena, // pictures' bytes and moments' text
}

// tape_record replays data, a recording, through app headlessly and keeps
// it in tape. blessed, when not nil, is the recording's blessed digests
// (ui.digests_parse); a frame whose digest differs is marked. It returns
// false, keeping the frames before, when the data stops being a
// recording partway; tape holds what it kept either way, for
// tape_destroy.
tape_record :: proc(tape: ^Tape, app: App, data: []byte, blessed: []u64 = nil) -> bool {
	tape^ = {}
	if virtual.arena_init_growing(&tape.arena) != nil {
		return false
	}
	keep := virtual.arena_allocator(&tape.arena)
	tape.pictures = make([dynamic]Picture, keep)
	tape.moments = make([dynamic]Moment, keep)
	tape.blessed = blessed != nil

	// Boxes, so a kept picture can be inspected; it draws nothing, so the
	// digests are the ones -bless and -check see.
	headless: render.Headless
	render.headless_init(&headless, app.ui, app.user, {800, 600}, app.fonts, {.Boxes}, fallbacks = app.fallbacks)
	defer render.headless_destroy(&headless)

	replay: ui.Replay
	ui.replay_open(&replay, data)
	time: f64
	last: u64
	for !ui.replay_done(&replay) {
		payload, _ := ui.replay_input(&replay)
		input, _ := ui.input_summary(payload, keep)
		if !ui.probe_replay_step(&headless.p, &replay) {
			return false
		}
		time += f64(input.dt)
		frame := ui.probe_current(&headless.p)
		digest := ui.frame_digest(frame)
		if len(tape.pictures) == 0 || digest != last {
			append(&tape.pictures, Picture{ops.encode(&headless.p.scene, keep), headless.p.size})
			last = digest
		}
		ii := len(tape.moments)
		differs := blessed != nil && (ii >= len(blessed) || blessed[ii] != digest)
		if differs {
			tape.differ += 1
		}
		append(&tape.moments, Moment{len(tape.pictures) - 1, time, input.dt, input.line, differs})
	}
	return true
}

// tape_destroy frees everything tape keeps.
tape_destroy :: proc(tape: ^Tape) {
	virtual.arena_destroy(&tape.arena)
	tape^ = {}
}

// tape_changes reports whether moment index showed another picture than
// the one before it.
tape_changes :: proc(tape: ^Tape, index: int) -> bool {
	return index > 0 && tape.moments[index].picture != tape.moments[index - 1].picture
}

// tape_change_after is the first moment after index that shows another
// picture, or the last moment when none does.
tape_change_after :: proc(tape: ^Tape, index: int) -> int {
	for ii in index + 1 ..< len(tape.moments) {
		if tape_changes(tape, ii) {
			return ii
		}
	}
	return len(tape.moments) - 1
}

// tape_change_before is the last moment before index that shows another
// picture than the one before it, or 0 when none does.
tape_change_before :: proc(tape: ^Tape, index: int) -> int {
	for ii := index - 1; ii > 0; ii -= 1 {
		if tape_changes(tape, ii) {
			return ii
		}
	}
	return 0
}
