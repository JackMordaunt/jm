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
	ops.add_font(&src, "mono.ttf", 600)
	ops.tag(&src, 99, "quote \" and\nnewline")
	ops.defer_call(&src, 0) // golden_scene's first macro, run again on top
	// and once more as a popup, which carries its placement on the wire
	ops.defer_place(&src, 0, {key = 5, anchor = {1, 2, 3, 4}, size = {10, 20}, side = .Above, align = .End, gap = 2, nudge = 3, inside = true, overhang = true, side_count = 2, sides = {.After, .Before, .Below, .Above}, align_count = 1, aligns = {.Center, .End}})
	append(&src.ops, ops.Debug_Box{7, {30, 20}, {0, 0}, {100, INF}, 2, "view.odin", 42, "view", "label"})
	ops.shadow(&src, {4, 6, 30, 20}, 5, 8, {0, 0, 0, 60})
	ops.semantic(&src, 7, 3, {role = .Checkbox, label = "Dark", labelled_by = 9, value = "on", description = "the scheme", states = {.Checked, .Disabled}}, {4, 6, 30, 20})
	ops.semantic(&src, 8, 0, {role = .Heading, label = "Fruit", level = 3}, {0, 0, 30, 20})
	ops.semantic(&src, 9, 0, {role = .Region, label = "Saved"}, {0, 0, 30, 20})
	ops.key_interest(&src, 7, .Escape, {.Ctrl}, {.Shift}, topmost = true)
	ops.outside_area(&src, 7, ops.Rect{1, 2, 3, 4})
	ops.sticky_push(&src, 12, 300)
	ops.fill(&src, ops.Rect{0, 0, 5, 5}, ops.Color{9, 9, 9, 255})
	ops.transform_pop(&src)
	ops.focus_scope(&src, 8, trap = true)
	ops.focus_scope_end(&src)
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
	testing.expect_value(t, dst.fonts[1].weight, 600)
	testing.expect_value(t, dst.images[0].path, "logo.png")
	testing.expect(t, slice.equal(dst.paths[0].verbs, src.paths[0].verbs))
	testing.expect(t, slice.equal(dst.paths[0].points, src.paths[0].points))
	testing.expect(t, slice.equal(dst.runs[0].glyphs, src.runs[0].glyphs))
	testing.expect_value(t, dst.runs[0].advance, src.runs[0].advance)
	testing.expect_value(t, dst.macros[0], src.macros[0])
	testing.expect_value(t, ops.dump(&dst), ops.dump(&src))

	// flatten(decode(encode(x))) == flatten(x), the popup placed the same
	fs, fd: Frame
	frame_init(&fs)
	frame_init(&fd)
	flatten(&src, &fs, {0, 0, 200, 100})
	flatten(&dst, &fd, {0, 0, 200, 100})
	testing.expect_value(t, dump_frame(&fd), dump_frame(&fs))
	testing.expect_value(t, len(fd.placed), 1)
	testing.expect_value(t, fd.placed[0], fs.placed[0])

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
	used, reserved := ops.frame_arena_used(&dst.decoded), ops.frame_arena_reserved(&dst.decoded)
	testing.expect(t, used > 0) // the decoded data is in the arena, where the heap does not see it
	for _ in 0 ..< 50 {
		testing.expect(t, ops.decode(data, &dst))
	}
	testing.expect_value(t, track.current_memory_allocated, after_one) // nothing piled up on the heap
	testing.expect_value(t, ops.frame_arena_used(&dst.decoded), used) // each decode reused the last one's space
	testing.expect_value(t, ops.frame_arena_reserved(&dst.decoded), reserved)
	ops.destroy(&dst)
	testing.expect_value(t, len(track.allocation_map), 0) // and destroy frees it all
}
