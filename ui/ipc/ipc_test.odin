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
