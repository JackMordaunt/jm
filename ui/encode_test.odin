package ui

import "core:math/rand"
import "jm:ui/ops"
import "core:mem"
import "core:mem/virtual"
import "core:slice"
import "core:testing"

@(test)
test_encode_round_trip :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	src: ops.Scene
	ops.init(&src)
	golden_scene(&src)
	ops.add_font(&src, "mono.ttf")
	ops.tag(&src, 99, "quote \" and\nnewline")
	ops.defer_call(&src, 0) // golden_scene's first macro, run again on top
	append(&src.ops, ops.Debug_Box{7, {30, 20}, {0, 0}, {100, INF}, 2, "view.odin", 42, "view", "label"})
	append(&src.ops, nil) // a nil op survives too

	data := ops.encode(&src)
	testing.expect(t, len(data) > 5)
	testing.expect_value(t, string(data[:4]), "UIOP")
	testing.expect_value(t, data[4], ops.ENCODE_VERSION)

	dst: ops.Scene
	ops.init(&dst)
	ops.add_font(&dst, "stale.ttf") // decode replaces fonts and images
	testing.expect(t, ops.decode(data, &dst))
	testing.expect_value(t, len(dst.ops), len(src.ops))
	testing.expect_value(t, len(dst.paths), len(src.paths))
	testing.expect_value(t, len(dst.runs), len(src.runs))
	testing.expect_value(t, len(dst.macros), len(src.macros))
	testing.expect_value(t, len(dst.fonts), 2)
	testing.expect_value(t, len(dst.images), 1)
	testing.expect_value(t, dst.fonts[1].path, "mono.ttf")
	testing.expect_value(t, dst.images[0].path, "logo.png")
	testing.expect(t, slice.equal(dst.paths[0].verbs, src.paths[0].verbs))
	testing.expect(t, slice.equal(dst.paths[0].points, src.paths[0].points))
	testing.expect(t, slice.equal(dst.runs[0].glyphs, src.runs[0].glyphs))
	testing.expect_value(t, dst.runs[0].advance, src.runs[0].advance)
	testing.expect_value(t, dst.macros[0], src.macros[0])
	testing.expect_value(t, ops.dump(&dst), ops.dump(&src))

	// flatten(decode(encode(x))) == flatten(x)
	fs, fd: Frame
	frame_init(&fs)
	frame_init(&fd)
	flatten(&src, &fs)
	flatten(&dst, &fd)
	testing.expect_value(t, dump_frame(&fd), dump_frame(&fs))

	// Re-encoding the decoded sc gives the same bytes.
	testing.expect(t, slice.equal(ops.encode(&dst), data))
}

@(test)
test_decode_rejects_every_truncation :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	src: ops.Scene
	ops.init(&src)
	golden_scene(&src)
	data := ops.encode(&src)

	scratch: virtual.Arena
	defer virtual.arena_destroy(&scratch)
	dst: ops.Scene
	ops.init(&dst, virtual.arena_allocator(&scratch))
	for n in 0 ..< len(data) {
		testing.expectf(t, !ops.decode(data[:n], &dst), "prefix of %d/%d bytes decoded", n, len(data))
	}
	extra := make([]byte, len(data) + 1)
	copy(extra, data)
	testing.expect(t, !ops.decode(extra, &dst), "trailing byte accepted")
	testing.expect(t, ops.decode(data, &dst))
}

@(test)
test_decode_rejects_bad_header_and_tags :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	src: ops.Scene
	ops.init(&src)
	ops.clip_pop(&src)
	data := ops.encode(&src)
	dst: ops.Scene
	ops.init(&dst)
	testing.expect(t, ops.decode(data, &dst))

	bad := slice.clone(data)
	bad[0] = 'X'
	testing.expect(t, !ops.decode(bad, &dst), "bad magic accepted")
	bad = slice.clone(data)
	bad[4] = ops.ENCODE_VERSION + 1
	testing.expect(t, !ops.decode(bad, &dst), "bad version accepted")
	bad = slice.clone(data)
	bad[len(bad) - 1] = 200 // the one op's tag
	testing.expect(t, !ops.decode(bad, &dst), "bad op tag accepted")

	// A Call naming a macro that is not in the stream.
	clear(&src.ops)
	ops.call(&src, 3)
	testing.expect(t, !ops.decode(ops.encode(&src), &dst), "dangling call accepted")
}

@(test)
test_decode_survives_random_bytes :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	rand.reset(0x5eed)
	src: ops.Scene
	ops.init(&src)
	golden_scene(&src)
	valid := ops.encode(&src)

	scratch: virtual.Arena
	defer virtual.arena_destroy(&scratch)
	dst: ops.Scene
	ops.init(&dst, virtual.arena_allocator(&scratch))
	buf := make([]byte, 256)
	for i in 0 ..< 2000 {
		n := rand.int_max(len(buf))
		b := buf[:n]
		for &c in b {
			c = u8(rand.uint32())
		}
		if i % 2 == 1 && n >= 5 {
			// A valid header gets the noise past the magic check.
			copy(b, valid[:5])
		}
		testing.expectf(t, !ops.decode(b, &dst), "random %d-byte string decoded", n)
	}
	// Mutated valid streams must not crash; some may still decode.
	mutant := make([]byte, len(valid))
	for _ in 0 ..< 2000 {
		copy(mutant, valid)
		for _ in 0 ..< 1 + rand.int_max(4) {
			mutant[rand.int_max(len(mutant))] = u8(rand.uint32())
		}
		if ops.decode(mutant, &dst) {
			_ = ops.dump(&dst, virtual.arena_allocator(&scratch))
		}
	}
}

@(test)
test_decode_frees_the_frame_before :: proc(t: ^testing.T) {
	// A host decodes a frame a refresh; what one decode allocates (paths,
	// glyphs, strings) must not outlive the next, or memory climbs.
	src: ops.Scene
	ops.init(&src, context.temp_allocator)
	golden_scene(&src)
	ops.tag(&src, 99, "a tag")
	append(&src.ops, ops.Debug_Box{7, {30, 20}, {0, 0}, {100, INF}, 2, "view.odin", 42, "view", "label"})
	data := ops.encode(&src, context.temp_allocator)
	defer free_all(context.temp_allocator)

	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	dst: ops.Scene
	ops.init(&dst, mem.tracking_allocator(&track))
	testing.expect(t, ops.decode(data, &dst))
	after_one := track.current_memory_allocated
	used, reserved := dst.decoded.arena.total_used, dst.decoded.arena.total_reserved
	testing.expect(t, used > 0) // the decoded data is in the arena, where the heap does not see it
	for _ in 0 ..< 50 {
		testing.expect(t, ops.decode(data, &dst))
	}
	testing.expect_value(t, track.current_memory_allocated, after_one) // nothing piled up on the heap
	testing.expect_value(t, dst.decoded.arena.total_used, used) // each decode reused the last one's space
	testing.expect_value(t, dst.decoded.arena.total_reserved, reserved)
	ops.destroy(&dst)
	testing.expect_value(t, len(track.allocation_map), 0) // and destroy frees it all
}
