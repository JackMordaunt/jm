package ipc

import "core:os"
import "core:slice"
import "core:testing"
import "core:thread"

@(test)
test_frame_round_trip_over_a_real_pipe :: proc(t: ^testing.T) {
	r, w, err := os.pipe()
	testing.expect(t, err == nil)
	defer os.close(r)
	defer os.close(w)

	empty: []byte
	hi := transmute([]byte)string("hi")
	cases := [][]byte{empty, hi}
	for c in cases {
		testing.expect(t, write_frame(w, c))
		got, ok := read_frame(r, context.temp_allocator)
		testing.expect(t, ok)
		testing.expect(t, slice.equal(got, c))
	}
}

// A payload past the pipe's own buffer needs a writer draining it
// concurrently with the reader, or write_frame blocks forever: a single
// thread doing all its writes before any read is exactly that deadlock.
@(test)
test_frame_round_trip_past_the_pipes_own_buffer :: proc(t: ^testing.T) {
	r, w, err := os.pipe()
	testing.expect(t, err == nil)
	defer os.close(r)
	defer os.close(w)

	payload := make([]byte, 300_000, context.temp_allocator)
	for &b, i in payload {
		b = u8(i)
	}

	Writer :: struct {
		w:       ^os.File,
		payload: []byte,
		wrote:   bool,
	}
	writer := Writer{w, payload, false}
	th := thread.create_and_start_with_data(&writer, proc(data: rawptr) {
		wr := (^Writer)(data)
		wr.wrote = write_frame(wr.w, wr.payload)
	})
	got, ok := read_frame(r, context.temp_allocator)
	thread.join(th)
	thread.destroy(th)

	testing.expect(t, writer.wrote)
	testing.expect(t, ok)
	testing.expect(t, slice.equal(got, payload))
}

@(test)
test_read_frame_reports_eof_on_a_closed_pipe :: proc(t: ^testing.T) {
	r, w, err := os.pipe()
	testing.expect(t, err == nil)
	defer os.close(r)
	os.close(w) // nothing will ever arrive

	_, ok := read_frame(r, context.temp_allocator)
	testing.expect(t, !ok)
}

@(test)
test_write_frame_refuses_an_oversized_payload :: proc(t: ^testing.T) {
	r, w, err := os.pipe()
	testing.expect(t, err == nil)
	defer os.close(r)
	defer os.close(w)
	testing.expect(t, !write_frame(w, make([]byte, MAX_FRAME + 1, context.temp_allocator)))
}

// A zero Child has pid 0, and signalling pid 0 hits the whole process
// group: if kill ever forwards it, this test runner dies with the group.
@(test)
test_kill_on_a_zero_child_signals_nothing :: proc(t: ^testing.T) {
	c: Child
	kill(&c)
	kill(&c)
	testing.expect_value(t, c.process.pid, 0)
}

@(test)
test_frames_in_memory_split_as_written :: proc(t: ^testing.T) {
	buf := make([dynamic]byte, context.temp_allocator)
	frame_append(&buf, {1, 2, 3})
	frame_append(&buf, {})
	frame_append(&buf, {9})
	a, rest, ok := frame_next(buf[:])
	testing.expect(t, ok && slice.equal(a, []byte{1, 2, 3}))
	b, rest2, ok2 := frame_next(rest)
	testing.expect(t, ok2 && len(b) == 0)
	c, rest3, ok3 := frame_next(rest2)
	testing.expect(t, ok3 && slice.equal(c, []byte{9}) && len(rest3) == 0)
	_, _, ok4 := frame_next(rest3)
	testing.expect(t, !ok4)
	_, _, cut := frame_next(buf[:5]) // a frame cut short is not a frame
	testing.expect(t, !cut)
}
