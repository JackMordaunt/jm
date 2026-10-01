package zstd

import "core:bytes"
import "core:io"
import "core:math/rand"
import "core:mem"
import "core:testing"

// The tests run under the runner's tracking allocator on purpose: zstd's
// tables go through context.allocator, so a context left unfreed fails the
// test. Fixtures and output buffers go on the temp allocator.

// noise is n bytes of seeded random data: incompressible, so a small patch
// between two noise buffers can only come from matching against the prefix.
noise :: proc(n: int, seed: u64) -> []byte {
	b := make([]byte, n, context.temp_allocator)
	state := rand.create_u64(seed)
	gen := rand.default_random_generator(&state)
	for &x in b {
		x = byte(rand.uint32(gen))
	}
	return b
}

// text is n bytes of repetitive, compressible data.
text :: proc(n: int) -> []byte {
	b := make([]byte, n, context.temp_allocator)
	line := "the quick brown fox jumps over the lazy dog 0123456789\n"
	for i in 0 ..< n {
		b[i] = line[i % len(line)]
	}
	return b
}

// edit is old with a region rewritten, bytes inserted and a tail dropped: the
// shifts a rebuilt binary shows.
edit :: proc(old: []byte) -> []byte {
	b: [dynamic]byte
	b.allocator = context.temp_allocator
	third := len(old) / 3
	append(&b, ..old[:third])
	append(&b, ..noise(4096, 99))
	append(&b, ..old[third:2 * third])
	patch := noise(512, 7)
	append(&b, ..patch)
	append(&b, ..old[2 * third + len(patch):len(old) - 1000])
	return b[:]
}

stream_compress :: proc(t: ^testing.T, src: []byte, opts := Options{}) -> []byte {
	r: bytes.Reader
	bytes.reader_init(&r, src)
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	testing.expect_value(t, compress_stream(bytes.buffer_to_stream(&out), bytes.reader_to_stream(&r), opts), nil)
	return bytes.buffer_to_bytes(&out)
}

stream_decompress :: proc(src: []byte, opts := Options{}) -> ([]byte, Error) {
	r: bytes.Reader
	bytes.reader_init(&r, src)
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	err := decompress_stream(bytes.buffer_to_stream(&out), bytes.reader_to_stream(&r), opts)
	return bytes.buffer_to_bytes(&out), err
}

make_patch :: proc(t: ^testing.T, old, new: []byte) -> []byte {
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	testing.expect_value(t, diff(bytes.buffer_to_stream(&out), old, new), nil)
	return bytes.buffer_to_bytes(&out)
}

apply_patch :: proc(old, p: []byte, window_log_max := 0) -> ([]byte, Error) {
	r: bytes.Reader
	bytes.reader_init(&r, p)
	out: bytes.Buffer
	bytes.buffer_init_allocator(&out, 0, 0, context.temp_allocator)
	err := patch(bytes.buffer_to_stream(&out), old, bytes.reader_to_stream(&r), window_log_max)
	return bytes.buffer_to_bytes(&out), err
}

@(test)
test_version :: proc(t: ^testing.T) {
	testing.expect_value(t, version(), "1.5.7")
	testing.expect_value(t, ZSTD_versionNumber(), VERSION_NUMBER)
}

@(test)
test_whole_buffer_round_trip :: proc(t: ^testing.T) {
	src := text(200_000)
	for level in ([]int{-5, 0, 1, 19, 22}) {
		buf := make([]byte, compress_bound(len(src)), context.temp_allocator)
		packed, err := compress(buf, src, {level = level})
		testing.expect_value(t, err, nil)
		testing.expectf(t, len(packed) < len(src) / 10, "level %d: %d bytes", level, len(packed))
		n, ok := content_size(packed)
		testing.expect(t, ok, "content size recorded")
		testing.expect_value(t, n, len(src))
		out := make([]byte, n, context.temp_allocator)
		plain, derr := decompress(out, packed)
		testing.expect_value(t, derr, nil)
		testing.expect(t, bytes.equal(plain, src), "round trip")
	}
}

@(test)
test_empty_input :: proc(t: ^testing.T) {
	buf: [64]byte
	packed, err := compress(buf[:], nil)
	testing.expect_value(t, err, nil)
	testing.expect(t, len(packed) > 0, "an empty input still makes a frame")
	out: [1]byte
	plain, derr := decompress(out[:], packed)
	testing.expect_value(t, derr, nil)
	testing.expect_value(t, len(plain), 0)

	streamed := stream_compress(t, nil)
	back, serr := stream_decompress(streamed)
	testing.expect_value(t, serr, nil)
	testing.expect_value(t, len(back), 0)
}

@(test)
test_stream_round_trip_crosses_chunks :: proc(t: ^testing.T) {
	src := make([]byte, 5 * CHUNK + 123, context.temp_allocator)
	copy(src, text(len(src)))
	copy(src[CHUNK:], noise(CHUNK, 1))
	packed := stream_compress(t, src, {level = 19, long = true})
	plain, err := stream_decompress(packed)
	testing.expect_value(t, err, nil)
	testing.expect(t, bytes.equal(plain, src), "round trip")
}

// A megabyte of text packs into far less than one read, so one read's input
// flushes as many CHUNKs of output, from a frame without the trailing
// checksum, as zstd's plain API and other producers write one.
@(test)
test_stream_expands_past_its_input :: proc(t: ^testing.T) {
	src := text(1_000_000)
	buf := make([]byte, compress_bound(len(src)), context.temp_allocator)
	n := ZSTD_compress(raw_data(buf), len(buf), raw_data(src), len(src), 19)
	testing.expect_value(t, check(n), nil)
	packed := buf[:n]
	testing.expectf(t, len(packed) < CHUNK, "packed is %d bytes", len(packed))
	plain, err := stream_decompress(packed)
	testing.expect_value(t, err, nil)
	testing.expect(t, bytes.equal(plain, src), "round trip")
}

@(test)
test_patch_round_trip :: proc(t: ^testing.T) {
	old := noise(1_000_000, 42)
	new := edit(old)
	p := make_patch(t, old, new)
	testing.expectf(t, len(p) < 16 * mem.Kilobyte, "patch is %d bytes", len(p))
	out, err := apply_patch(old, p)
	testing.expect_value(t, err, nil)
	testing.expect(t, bytes.equal(out, new), "patch reproduces new")
}

@(test)
test_patch_to_identical :: proc(t: ^testing.T) {
	old := noise(300_000, 3)
	p := make_patch(t, old, old)
	testing.expectf(t, len(p) < 1024, "patch is %d bytes", len(p))
	out, err := apply_patch(old, p)
	testing.expect_value(t, err, nil)
	testing.expect(t, bytes.equal(out, old), "patch reproduces old")
}

// Unrelated inputs make a patch as large as new. zstd takes input in 128 KiB
// blocks, so 360,000 bytes leaves a last block whose output overflows one
// CHUNK: the frame is still flushing after the input is all consumed.
@(test)
test_patch_between_unrelated_files :: proc(t: ^testing.T) {
	old := noise(100_000, 12)
	new := noise(360_000, 13)
	p := make_patch(t, old, new)
	testing.expectf(t, len(p) > 4 * CHUNK, "patch is %d bytes", len(p))
	out, err := apply_patch(old, p)
	testing.expect_value(t, err, nil)
	testing.expect(t, bytes.equal(out, new), "patch reproduces new")
}

@(test)
test_patch_from_empty_old :: proc(t: ^testing.T) {
	new := text(10_000)
	p := make_patch(t, nil, new)
	out, err := apply_patch(nil, p)
	testing.expect_value(t, err, nil)
	testing.expect(t, bytes.equal(out, new), "patch from nothing is compression")
}

@(test)
test_patch_on_wrong_old_fails :: proc(t: ^testing.T) {
	old := noise(200_000, 5)
	p := make_patch(t, old, edit(old))
	_, err := apply_patch(noise(200_000, 6), p)
	code, is_code := err.(Code)
	testing.expectf(
		t,
		is_code && (code == .checksum_wrong || code == .corruption_detected),
		"wrong base gave %v",
		err,
	)
}

@(test)
test_truncated_patch_fails :: proc(t: ^testing.T) {
	old := noise(200_000, 8)
	p := make_patch(t, old, edit(old))
	_, err := apply_patch(old, p[:len(p) / 2])
	testing.expect_value(t, err, Error(Code.srcSize_wrong))
}

@(test)
test_not_zstd_fails :: proc(t: ^testing.T) {
	_, err := stream_decompress(noise(1000, 9))
	testing.expect_value(t, err, Error(Code.prefix_unknown))
	_, empty_err := stream_decompress(nil)
	testing.expect_value(t, empty_err, Error(Code.srcSize_wrong))
}

@(test)
test_window_limit_refuses :: proc(t: ^testing.T) {
	old := noise(3_000_000, 10)
	p := make_patch(t, old, edit(old))
	_, err := apply_patch(old, p, window_log_max = 20)
	testing.expect_value(t, err, Error(Code.frameParameter_windowTooLarge))
}

@(test)
test_small_destination_fails :: proc(t: ^testing.T) {
	src := noise(10_000, 11)
	buf: [100]byte
	_, err := compress(buf[:], src)
	testing.expect_value(t, err, Error(Code.dstSize_tooSmall))
}

// failing_writer is a writer that refuses every write, to show a writer's error is
// returned as itself.
failing_writer :: proc(
	stream_data: rawptr,
	mode: io.Stream_Mode,
	p: []byte,
	offset: i64,
	whence: io.Seek_From,
) -> (
	i64,
	io.Error,
) {
	if mode == .Query {
		return io.query_utility({.Write, .Query})
	}
	return 0, .Short_Write
}

@(test)
test_writer_error_surfaces :: proc(t: ^testing.T) {
	src := text(1000)
	r: bytes.Reader
	bytes.reader_init(&r, src)
	w := io.Stream{procedure = failing_writer}
	err := compress_stream(w, bytes.reader_to_stream(&r))
	testing.expect_value(t, err, Error(io.Error.Short_Write))
}

@(test)
test_allocations_go_through_the_option :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	src := text(100_000)
	buf := make([]byte, compress_bound(len(src)), context.temp_allocator)
	_, err := compress(buf, src, {level = 19, allocator = mem.tracking_allocator(&track)})
	testing.expect_value(t, err, nil)
	testing.expect(t, track.total_allocation_count > 0, "zstd allocated through the option")
	testing.expect_value(t, len(track.allocation_map), 0)
}
