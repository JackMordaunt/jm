package game

import "core:os"

import "jm:ui"
import "jm:ui/ops"

// A tape is a run of a game: the World as it started and the Input of
// every tick after. step is deterministic over the World and the Input,
// so a tape replays the run exactly, World byte for World byte, with no
// window, no frames and no clock: a bug seen live is run again headless
// and stopped at the tick it showed on.
//
// The file is TAPE_MAGIC, a u8 TAPE_VERSION, the u64 seed, the f64 dt,
// the u32 size of the World and its bytes, then entries. An entry is a
// u64 tick and that tick's Input, written only for a tick whose Input
// differs from the one before with its edges cleared: a tick between two
// entries got that Input, so a held key costs nothing until it changes.
// The last entry has the tick count and TAPE_END for its Input's place:
// a tape cut short (the process died) replays up to its last entry.
//
// An Input entry is held, pressed and released keys as their bit sets'
// bytes, the f32 pointer x and y, and the buttons held, clicked and
// unclicked as a byte each.

TAPE_MAGIC :: "JMGT"

// TAPE_VERSION changes with the layout, or with the numbering of ui.Key.
TAPE_VERSION :: u8(1)

@(private)
TAPE_ENTRY :: u8(1)

@(private)
TAPE_END :: u8(2)

// Tape_Writer records ticks to a file as they run.
Tape_Writer :: struct {
	file:  ^os.File,
	last:  Input, // the last Input written, edges cleared: what an unwritten tick repeats
	ticks: u64, // ticks recorded
	buf:   [dynamic]byte,
}

// tape_writer_open starts a tape at path, replacing any file there, with
// world as it is now: call it after init and before the first tick.
tape_writer_open :: proc(writer: ^Tape_Writer, path: string, world: ^$W, seed: u64, dt: f64) -> bool {
	return tape_writer_open_bytes(writer, path, ([^]byte)(world)[:size_of(W)], seed, dt)
}

@(private)
tape_writer_open_bytes :: proc(writer: ^Tape_Writer, path: string, world: []byte, seed: u64, dt: f64) -> bool {
	file, err := os.open(path, {.Write, .Create, .Trunc})
	if err != nil {
		return false
	}
	writer^ = {
		file = file,
		buf  = make([dynamic]byte),
	}
	append(&writer.buf, TAPE_MAGIC)
	append(&writer.buf, TAPE_VERSION)
	ops.put_u64(&writer.buf, seed)
	ops.put_f64(&writer.buf, dt)
	ops.put_u32(&writer.buf, u32(len(world)))
	append(&writer.buf, ..world)
	tape_flush(writer)
	return true
}

// tape_write records the Input one tick ran with. A closed or zero
// writer records nothing, so a runner calls it unconditionally.
tape_write :: proc(writer: ^Tape_Writer, input: Input) {
	if writer.file == nil {
		return
	}
	writer.ticks += 1
	if input_repeats(writer.last, input) {
		return
	}
	writer.last = without_edges(input)
	ops.put_u64(&writer.buf, input.tick)
	append(&writer.buf, TAPE_ENTRY)
	put_input(&writer.buf, input)
	tape_flush(writer)
}

// tape_writer_close ends the tape with its tick count and closes it.
tape_writer_close :: proc(writer: ^Tape_Writer) {
	if writer.file == nil {
		return
	}
	ops.put_u64(&writer.buf, writer.ticks)
	append(&writer.buf, TAPE_END)
	tape_flush(writer)
	os.close(writer.file)
	delete(writer.buf)
	writer^ = {}
}

@(private)
tape_flush :: proc(writer: ^Tape_Writer) {
	os.write(writer.file, writer.buf[:])
	clear(&writer.buf)
}

// Tape is a tape read back: its header, and a cursor over its ticks.
Tape :: struct {
	seed:   u64,
	dt:     f64,
	world:  []byte, // the World as the tape began, in data
	ticks:  u64, // ticks on the tape: its count, or for a tape cut short, its last entry's tick and one
	reader: ops.Reader,
	input:  Input, // the Input a tick with no entry gets: the last entry's, edges cleared
	next:   u64, // the tick the next entry is for; ticks when there is none
	entry:  Input, // the next entry's Input
	tick:   u64, // the next tick tape_next gives
}

// tape_open reads data's header and readies tape to give its ticks.
// data must outlive tape.
tape_open :: proc(tape: ^Tape, data: []byte) -> (ok: bool) {
	tape^ = {
		reader = {data = data},
	}
	reader := &tape.reader
	if len(data) < len(TAPE_MAGIC) + 1 || string(data[:len(TAPE_MAGIC)]) != TAPE_MAGIC {
		return false
	}
	reader.pos = len(TAPE_MAGIC)
	if (ops.get_u8(reader) or_return) != TAPE_VERSION {
		return false
	}
	tape.seed = ops.get_u64(reader) or_return
	tape.dt = ops.get_f64(reader) or_return
	size := int(ops.get_u32(reader) or_return)
	if size > len(data) - reader.pos {
		return false
	}
	tape.world = data[reader.pos:][:size]
	reader.pos += size
	tape.ticks = tape_scan(tape^)
	tape_read_entry(tape)
	return true
}

// tape_next gives the next tick's Input, false past the tape's end.
tape_next :: proc(tape: ^Tape) -> (input: Input, ok: bool) {
	if tape.tick >= tape.ticks {
		return {}, false
	}
	if tape.tick == tape.next {
		input = tape.entry
		tape.input = without_edges(tape.entry)
		tape_read_entry(tape)
	} else {
		input = tape.input
	}
	input.tick = tape.tick
	tape.tick += 1
	return input, true
}

// tape_read_entry reads the next entry's tick and Input into tape, or
// marks the tape as having none.
@(private)
tape_read_entry :: proc(tape: ^Tape) {
	tape.next = tape.ticks
	reader := tape.reader
	tick, ok := ops.get_u64(&reader)
	kind, kind_ok := ops.get_u8(&reader)
	if !ok || !kind_ok || kind != TAPE_ENTRY {
		return
	}
	input, input_ok := get_input(&reader)
	if !input_ok {
		return
	}
	tape.reader = reader
	tape.next = tick
	tape.entry = input
}

// tape_scan counts a tape's ticks from the reader on: the end entry's
// count, or for a tape cut short, one past its last whole entry.
@(private)
tape_scan :: proc(tape: Tape) -> (ticks: u64) {
	reader := tape.reader
	for {
		tick := ops.get_u64(&reader) or_break
		kind := ops.get_u8(&reader) or_break
		if kind == TAPE_END {
			return tick
		}
		if kind != TAPE_ENTRY {
			break
		}
		_ = get_input(&reader) or_break
		ticks = tick + 1
	}
	return
}

// tape_replay runs the tape in data over world: world becomes the World
// the tape began with, then steps through up to until of its ticks. It
// returns the ticks run; ok is false when data is not a tape of a World
// of W's size.
tape_replay :: proc(game: Game($W), world: ^W, data: []byte, until := max(u64)) -> (ticks: u64, ok: bool) {
	tape: Tape
	tape_open(&tape, data) or_return
	if len(tape.world) != size_of(W) {
		return 0, false
	}
	world^ = (^W)(raw_data(tape.world))^
	for ticks < until {
		input := tape_next(&tape) or_break
		game.step(world, input)
		ticks += 1
	}
	return ticks, true
}

// input_repeats reports whether next is what a tick after last gets
// unwritten: last's state with no edges.
@(private)
input_repeats :: proc(last, next: Input) -> bool {
	next := next
	next.tick = 0
	return next == last
}

// without_edges is input as the ticks after it hold it: what is held
// stays held, nothing is pressed or released again, and the tick is 0.
@(private)
without_edges :: proc(input: Input) -> Input {
	input := input
	input.tick = 0
	input.pressed, input.released = {}, {}
	input.clicked, input.unclicked = {}, {}
	return input
}

@(private)
put_input :: proc(buf: ^[dynamic]byte, input: Input) {
	for keys in ([]ui.Keys{input.held, input.pressed, input.released}) {
		bytes := transmute([size_of(ui.Keys)]u8)keys
		append(buf, ..bytes[:])
	}
	ops.put_f32(buf, input.pointer.x)
	ops.put_f32(buf, input.pointer.y)
	append(buf, transmute(u8)input.buttons, transmute(u8)input.clicked, transmute(u8)input.unclicked)
}

@(private)
get_input :: proc(reader: ^ops.Reader) -> (input: Input, ok: bool) {
	keys: [3]ui.Keys
	for &set in keys {
		if len(reader.data) - reader.pos < size_of(ui.Keys) {
			return {}, false
		}
		bytes: [size_of(ui.Keys)]u8
		copy(bytes[:], reader.data[reader.pos:][:size_of(ui.Keys)])
		set = transmute(ui.Keys)bytes
		reader.pos += size_of(ui.Keys)
	}
	input.held, input.pressed, input.released = keys[0], keys[1], keys[2]
	input.pointer.x = ops.get_f32(reader) or_return
	input.pointer.y = ops.get_f32(reader) or_return
	input.buttons = transmute(Buttons)(ops.get_u8(reader) or_return)
	input.clicked = transmute(Buttons)(ops.get_u8(reader) or_return)
	input.unclicked = transmute(Buttons)(ops.get_u8(reader) or_return)
	return input, true
}
