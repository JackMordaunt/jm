package ui

import "core:math/rand"
import "core:mem/virtual"
import "core:slice"
import "core:testing"

@(test)
test_encode_input_round_trip :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	events := []Raw_Event {
		{kind = .Move, pos = {12, 34}},
		{kind = .Press, pos = {5, 6}, button = .Right, mods = {.Shift, .Ctrl}},
		{kind = .Scroll, pos = {1, 2}, scroll = {0, -3.5}},
		{kind = .Key, key = .Enter, mods = {.Alt}},
		{kind = .Text, text = "héllo\nworld"},
	}
	host := Host_Stats{present_ms = 1.5, roundtrip_ms = 3.25, repaint_rects = 4, repaint_px = 12000}
	data := encode_input({800, 600}, 2, 1.0 / 60, events, host = host)

	size, density, dt, got, got_host, ok := decode_input(data)
	testing.expect_value(t, got_host, host)
	testing.expect(t, ok)
	testing.expect_value(t, size, Size{800, 600})
	testing.expect_value(t, density, f32(2))
	testing.expect_value(t, dt, f32(1.0 / 60))
	testing.expect_value(t, len(got), len(events))
	for e, i in events {
		testing.expect_value(t, got[i], e)
	}

	// Re-encoding the decoded events gives the same bytes.
	testing.expect(t, slice.equal(encode_input(size, density, dt, got, host = got_host), data))
}

@(test)
test_encode_input_no_events :: proc(t: ^testing.T) {
	data := encode_input({0, 0}, 1, 0, nil, context.temp_allocator)
	size, density, dt, events, _, ok := decode_input(data, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, size, Size{0, 0})
	testing.expect_value(t, density, f32(1))
	testing.expect_value(t, dt, f32(0))
	testing.expect_value(t, len(events), 0)
}

@(test)
test_encode_reply_round_trip :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	src: Ops
	ops_init(&src)
	golden_scene(&src)
	ops_bytes := encode(&src)

	data := encode_reply(true, 0.25, ops_bytes)
	dbg: Reply_Debug
	wants_frame, frame_after, got_ops, ok := decode_reply(data, &dbg)
	testing.expect(t, !dbg.flash && !dbg.full_frames)
	testing.expect(t, ok)
	testing.expect(t, wants_frame)
	keep := []Rect{{10, 20, 30, 40}, {1, 2, 3, 4}}
	_, _, again, ok2 := decode_reply(encode_reply(false, 0, ops_bytes, full_frames = true, flash = true, keep_out = keep), &dbg)
	testing.expect(t, ok2 && dbg.full_frames && dbg.flash)
	testing.expect(t, slice.equal(reply_keep_out(&dbg), keep))
	testing.expect(t, slice.equal(again, ops_bytes)) // the rects sit before the ops, not in them
	testing.expect_value(t, frame_after, f32(0.25))
	testing.expect(t, slice.equal(got_ops, ops_bytes))

	dst: Ops
	ops_init(&dst)
	testing.expect(t, decode(got_ops, &dst))
	testing.expect_value(t, dump(&dst), dump(&src))
}

@(test)
test_decode_input_survives_random_bytes :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)
	rand.reset(0x5eed)
	valid := encode_input({800, 600}, 1, 1.0 / 60, []Raw_Event{{kind = .Text, text = "hi"}})

	buf := make([]byte, 128)
	for i in 0 ..< 1000 {
		n := rand.int_max(len(buf))
		b := buf[:n]
		for &c in b {
			c = u8(rand.uint32())
		}
		if i % 2 == 1 && n >= 16 {
			copy(b, valid[:16])
		}
		_, _, _, _, _, _ = decode_input(b, context.temp_allocator)
		free_all(context.temp_allocator)
	}
}

@(test)
test_decode_reply_survives_random_bytes :: proc(t: ^testing.T) {
	rand.reset(0xf00d)
	buf := make([]byte, 64, context.temp_allocator)
	for _ in 0 ..< 1000 {
		n := rand.int_max(len(buf))
		b := buf[:n]
		for &c in b {
			c = u8(rand.uint32())
		}
		_, _, _, _ = decode_reply(b)
	}
}
