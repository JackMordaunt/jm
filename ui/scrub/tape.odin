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

import "core:fmt"
import "core:mem/virtual"
import "core:strings"

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

// INPUT_TEXT_MAX caps a Moment's input line, in bytes.
INPUT_TEXT_MAX :: 200

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
		dt, input := read_input(payload, keep)
		if !ui.probe_replay_step(&headless.p, &replay) {
			return false
		}
		time += f64(dt)
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
		append(&tape.moments, Moment{len(tape.pictures) - 1, time, dt, input, differs})
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

// read_input decodes a recorded frame's input from payload: its dt, and
// its events as a line on allocator, positions in logical units. A run
// of moves reads as one, with where it ended.
@(private)
read_input :: proc(payload: []byte, allocator := context.allocator) -> (dt: f32, text: string) {
	scratch: virtual.Arena
	if virtual.arena_init_growing(&scratch) != nil {
		return
	}
	defer virtual.arena_destroy(&scratch)
	_, density, dt_got, events, _, _, ok := ui.decode_input(payload, virtual.arena_allocator(&scratch))
	if !ok {
		return 0, ""
	}
	dt = dt_got
	scale := density if density > 0 else 1
	sb := strings.builder_make(virtual.arena_allocator(&scratch))
	moves := 0
	for event, ii in events {
		if event.kind == .Move {
			moves += 1
			following := ii + 1 < len(events) && events[ii + 1].kind == .Move
			if following {
				continue
			}
		}
		if strings.builder_len(sb) > 0 {
			strings.write_string(&sb, "  ")
		}
		at := ops.Point{event.pos.x / scale, event.pos.y / scale}
		#partial switch event.kind {
		case .Move:
			if moves > 1 {
				fmt.sbprintf(&sb, "Move×%d %.0f,%.0f", moves, at.x, at.y)
			} else {
				fmt.sbprintf(&sb, "Move %.0f,%.0f", at.x, at.y)
			}
			moves = 0
		case .Press, .Release:
			fmt.sbprintf(&sb, "%v %.0f,%.0f", event.kind, at.x, at.y)
		case .Scroll:
			fmt.sbprintf(&sb, "Scroll %.1f,%.1f", event.scroll.x, event.scroll.y)
		case .Key:
			fmt.sbprintf(&sb, "Key %v", event.key)
			if event.mods != {} {
				fmt.sbprintf(&sb, " %v", event.mods)
			}
		case .Text, .Paste, .Compose:
			fmt.sbprintf(&sb, "%v %q", event.kind, event.text)
		case:
			fmt.sbprintf(&sb, "%v", event.kind)
		}
	}
	line := strings.to_string(sb)
	if len(line) > INPUT_TEXT_MAX {
		cut := INPUT_TEXT_MAX
		for cut > 0 && (line[cut] & 0xC0) == 0x80 {
			cut -= 1 // not inside a UTF-8 sequence
		}
		line = strings.concatenate({line[:cut], "…"}, virtual.arena_allocator(&scratch))
	}
	return dt, strings.clone(line, allocator)
}
