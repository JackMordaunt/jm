package ui

import "core:fmt"
import "core:mem/virtual"
import "core:strings"

// A recording read as text, for a reader who cannot watch it: the
// timeline lists the frames where something happened, and a diff says
// what one frame changed. They are the scrubber's timeline and its
// stepping, as -timeline and -diff (render.headless_step).

// Input_Summary is a recorded frame's input as a reader wants it: its dt,
// its events as one line, positions in logical units, and whether they
// were pointer moves alone, which a timeline leaves out when nothing
// changed.
Input_Summary :: struct {
	dt:         f32,
	line:       string,
	moves_only: bool,
}

// INPUT_LINE_MAX caps an Input_Summary's line, in bytes.
INPUT_LINE_MAX :: 200

// input_summary decodes a recorded frame's input, an encode_input, into
// an Input_Summary, its line on allocator. A run of moves reads as one,
// with where it ended. ok is false for bytes that are not an input.
input_summary :: proc(payload: []byte, allocator := context.allocator) -> (summary: Input_Summary, ok: bool) {
	scratch: virtual.Arena
	if virtual.arena_init_growing(&scratch) != nil {
		return
	}
	defer virtual.arena_destroy(&scratch)
	_, density, dt, events, _, _, decoded := decode_input(payload, virtual.arena_allocator(&scratch))
	if !decoded {
		return
	}
	scale := density if density > 0 else 1
	sb := strings.builder_make(virtual.arena_allocator(&scratch))
	moves := 0
	summary.moves_only = len(events) > 0
	for event, ii in events {
		if event.kind != .Move {
			summary.moves_only = false
		} else {
			moves += 1
			if ii + 1 < len(events) && events[ii + 1].kind == .Move {
				continue
			}
		}
		if strings.builder_len(sb) > 0 {
			strings.write_string(&sb, "  ")
		}
		at := [2]f32{event.pos.x / scale, event.pos.y / scale}
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
		case .Text, .Paste, .Compose, .Picked, .Pick_Failed:
			fmt.sbprintf(&sb, "%v %q", event.kind, event.text)
		case:
			fmt.sbprintf(&sb, "%v", event.kind)
		}
	}
	line := strings.to_string(sb)
	if len(line) > INPUT_LINE_MAX {
		cut := INPUT_LINE_MAX
		for cut > 0 && (line[cut] & 0xC0) == 0x80 {
			cut -= 1 // not inside a UTF-8 sequence
		}
		line = strings.concatenate({line[:cut], "…"}, virtual.arena_allocator(&scratch))
	}
	summary.dt = dt
	summary.line = strings.clone(line, allocator)
	return summary, true
}

// Timeline_Frame is one replayed frame as a timeline keeps it.
Timeline_Frame :: struct {
	digest: u64,
	time:   f64, // seconds since the recording began: the frames' dt summed
	input:  Input_Summary,
}

// probe_replay_timeline runs every frame of a recording through probe,
// as probe_replay does, and returns each as a Timeline_Frame on
// allocator. ok is false when the data stops being a recording partway;
// the frames that ran are returned.
probe_replay_timeline :: proc(probe: ^Probe, data: []byte, allocator := context.allocator) -> (frames: []Timeline_Frame, ok: bool) {
	out := make([dynamic]Timeline_Frame, allocator)
	replay: Replay
	replay_open(&replay, data)
	time: f64
	ok = true
	for !replay_done(&replay) {
		payload, _ := replay_input(&replay)
		input, _ := input_summary(payload, allocator)
		if !probe_replay_step(probe, &replay) {
			ok = false
			break
		}
		time += f64(input.dt)
		append(&out, Timeline_Frame{frame_digest(probe_current(probe)), time, input})
	}
	return out[:], ok
}

// timeline_report is frames as text: a line of totals, then a line for
// each frame where something happened, numbered from 1: the picture
// changed, the digest differs from blessed (when given), or input other
// than pointer moves arrived, which changed nothing when the line does
// not say changed. A run of frames that changed with no other input, an
// animation or a hover following the pointer, is one line, its first
// and last frames joined by a dash. The first and last frames are always
// listed.
timeline_report :: proc(frames: []Timeline_Frame, blessed: []u64 = nil, allocator := context.allocator) -> string {
	sb := strings.builder_make(allocator)
	changes, differ := 0, 0
	for _, ii in frames {
		if timeline_changed(frames, ii) {
			changes += 1
		}
		if timeline_differs(frames, blessed, ii) {
			differ += 1
		}
	}
	total := frames[len(frames) - 1].time if len(frames) > 0 else 0
	fmt.sbprintf(&sb, "%d frame(s) over %.3f s; the picture changed on %d", len(frames), total, changes)
	if blessed != nil {
		fmt.sbprintf(&sb, "; %d differ from the blessed digests", differ)
		if len(blessed) != len(frames) {
			fmt.sbprintf(&sb, " (%d blessed)", len(blessed))
		}
	}
	strings.write_byte(&sb, '\n')
	last := len(frames) - 1
	for ii := 0; ii <= last; ii += 1 {
		frame := frames[ii]
		changed := timeline_changed(frames, ii)
		differs := timeline_differs(frames, blessed, ii)
		acted := frame.input.line != "" && !frame.input.moves_only
		if !(ii == 0 || ii == last || changed || differs || acted) {
			continue
		}
		if timeline_runs(frames, blessed, ii) {
			end := ii
			moved := false
			for end + 1 < last && timeline_runs(frames, blessed, end + 1) {
				end += 1
				moved ||= frames[end].input.moves_only
			}
			moved ||= frame.input.moves_only
			if end > ii {
				fmt.sbprintf(&sb, "%d-%d  %.3f-%.3f s  changed on all %d", ii + 1, end + 1, frame.time, frames[end].time, end - ii + 1)
				strings.write_string(&sb, ", the pointer moving\n" if moved else "\n")
				ii = end
				continue
			}
		}
		fmt.sbprintf(&sb, "%d  %.3f s", ii + 1, frame.time)
		if changed {
			strings.write_string(&sb, "  changed")
		}
		if differs {
			strings.write_string(&sb, "  differs")
		}
		if frame.input.line != "" {
			fmt.sbprintf(&sb, "  %s", frame.input.line)
		}
		strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// timeline_changed reports whether frame index shows another picture
// than the frame before it.
@(private = "file")
timeline_changed :: proc(frames: []Timeline_Frame, index: int) -> bool {
	return index > 0 && frames[index].digest != frames[index - 1].digest
}

// timeline_runs reports whether frame index can join a run: it changed,
// matches its blessed digest, and had no input but pointer moves.
@(private = "file")
timeline_runs :: proc(frames: []Timeline_Frame, blessed: []u64, index: int) -> bool {
	input := frames[index].input
	return timeline_changed(frames, index) && !timeline_differs(frames, blessed, index) && (input.line == "" || input.moves_only)
}

// timeline_differs reports whether frame index's digest is not the
// blessed one; false without blessed digests.
@(private = "file")
timeline_differs :: proc(frames: []Timeline_Frame, blessed: []u64, index: int) -> bool {
	return blessed != nil && (index >= len(blessed) || blessed[index] != frames[index].digest)
}

// probe_replay_diff runs a recording through probe up to frame (from 1)
// and returns what the frame before it showed and what it shows, as
// frame_picture text on allocator, with its input. Before frame 1 is the
// probe's own frame, the state the recording began from. ok is false
// when the recording stops being one, or ends, first.
probe_replay_diff :: proc(probe: ^Probe, data: []byte, frame: int, allocator := context.allocator) -> (before, after: string, input: Input_Summary, ok: bool) {
	if frame < 1 {
		return
	}
	replay: Replay
	replay_open(&replay, data)
	for replay.frames < frame - 1 {
		probe_replay_step(probe, &replay) or_return
	}
	payload := replay_input(&replay) or_return
	input = input_summary(payload, allocator) or_return
	before = frame_picture(probe_current(probe), allocator)
	probe_replay_step(probe, &replay) or_return
	after = frame_picture(probe_current(probe), allocator)
	return before, after, input, true
}

// DIFF_LINES_MAX caps how many changed lines picture_diff prints.
DIFF_LINES_MAX :: 200

// DIFF_TABLE_MAX bounds the cells picture_diff's line matching may use;
// past it, lines are matched by count, not order.
DIFF_TABLE_MAX :: 4_000_000

// picture_diff is the lines of before and after that differ, as text on
// allocator: a line of totals, then "- " for a line only before has and
// "+ " for one only after has, in order, at most DIFF_LINES_MAX of them.
// Lines are frame_picture's, so a draw that moved reads as one removed
// and one added.
picture_diff :: proc(before, after: string, allocator := context.allocator) -> string {
	scratch: virtual.Arena
	if virtual.arena_init_growing(&scratch) != nil {
		return ""
	}
	defer virtual.arena_destroy(&scratch)
	temp := virtual.arena_allocator(&scratch)
	old := strings.split_lines(strings.trim_right(before, "\n"), temp)
	new := strings.split_lines(strings.trim_right(after, "\n"), temp)
	// The lines both share at the ends need no matching.
	head := 0
	for head < len(old) && head < len(new) && old[head] == new[head] {
		head += 1
	}
	tail := 0
	for tail < len(old) - head && tail < len(new) - head && old[len(old) - 1 - tail] == new[len(new) - 1 - tail] {
		tail += 1
	}
	old = old[head:len(old) - tail]
	new = new[head:len(new) - tail]
	changes := make([dynamic]string, temp)
	if (len(old) + 1) * (len(new) + 1) <= DIFF_TABLE_MAX {
		diff_ordered(old, new, &changes, temp)
	} else {
		diff_counted(old, new, &changes, temp)
	}
	removed, added := 0, 0
	for line in changes {
		if line[0] == '-' {
			removed += 1
		} else {
			added += 1
		}
	}
	sb := strings.builder_make(allocator)
	if removed == 0 && added == 0 {
		strings.write_string(&sb, "the same picture\n")
		return strings.to_string(sb)
	}
	fmt.sbprintf(&sb, "%d line(s) removed, %d added\n", removed, added)
	for line, ii in changes {
		if ii == DIFF_LINES_MAX {
			fmt.sbprintf(&sb, "… %d more\n", len(changes) - ii)
			break
		}
		strings.write_string(&sb, line)
		strings.write_byte(&sb, '\n')
	}
	return strings.to_string(sb)
}

// diff_ordered appends to changes old's and new's lines that are in no
// longest common subsequence of the two, marked - and +, in order.
@(private = "file")
diff_ordered :: proc(old, new: []string, changes: ^[dynamic]string, allocator := context.allocator) {
	width := len(new) + 1
	// longest[ii * width + jj] is the longest common run of old[ii:] and new[jj:].
	longest := make([]i32, (len(old) + 1) * width, allocator)
	for ii := len(old) - 1; ii >= 0; ii -= 1 {
		for jj := len(new) - 1; jj >= 0; jj -= 1 {
			if old[ii] == new[jj] {
				longest[ii * width + jj] = longest[(ii + 1) * width + jj + 1] + 1
			} else {
				longest[ii * width + jj] = max(longest[(ii + 1) * width + jj], longest[ii * width + jj + 1])
			}
		}
	}
	ii, jj := 0, 0
	for ii < len(old) || jj < len(new) {
		switch {
		case ii < len(old) && jj < len(new) && old[ii] == new[jj]:
			ii += 1
			jj += 1
		case jj == len(new) || (ii < len(old) && longest[(ii + 1) * width + jj] >= longest[ii * width + jj + 1]):
			append(changes, strings.concatenate({"- ", old[ii]}, allocator))
			ii += 1
		case:
			append(changes, strings.concatenate({"+ ", new[jj]}, allocator))
			jj += 1
		}
	}
}

// diff_counted appends to changes the lines old has more of than new,
// marked -, then those new has more of, marked +: what changed, without
// where, for frames too big to match line by line.
@(private)
diff_counted :: proc(old, new: []string, changes: ^[dynamic]string, allocator := context.allocator) {
	counts := make(map[string]int, allocator)
	for line in old {
		counts[line] += 1
	}
	for line in new {
		counts[line] -= 1
	}
	for line in old {
		if counts[line] > 0 {
			append(changes, strings.concatenate({"- ", line}, allocator))
			counts[line] -= 1
		}
	}
	for line in new {
		if counts[line] < 0 {
			append(changes, strings.concatenate({"+ ", line}, allocator))
			counts[line] += 1
		}
	}
}
