package ui

import "core:math/rand"
import "jm:ui/ops"
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
		{kind = .Press, pos = {5, 6}, button = .Right, mods = {.Shift, .Ctrl}, clicks = 2},
		{kind = .Scroll, pos = {1, 2}, scroll = {0, -3.5}},
		{kind = .Key, key = .Enter, mods = {.Alt}},
		{kind = .Text, text = "héllo\nworld"},
		{kind = .Paste, text = "pasted", mime = TEXT_MIME},
		{kind = .Focus, area = 77},
	}
	host := Host_Stats{present_ms = 1.5, roundtrip_ms = 3.25, repaint_rects = 4, repaint_px = 12000, rss_bytes = 64 << 20}
	data := encode_input({800, 600}, 2, 1.0 / 60, events, host = host)

	size, density, dt, got, got_host, restore, ok := decode_input(data)
	testing.expect_value(t, len(restore), 0)
	testing.expect_value(t, got_host, host)
	testing.expect(t, ok)
	testing.expect_value(t, size, ops.Size{800, 600})
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
	size, density, dt, events, _, _, ok := decode_input(data, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, size, ops.Size{0, 0})
	testing.expect_value(t, density, f32(1))
	testing.expect_value(t, dt, f32(0))
	testing.expect_value(t, len(events), 0)
}

@(test)
test_encode_reply_round_trip :: proc(t: ^testing.T) {
	arena: virtual.Arena
	defer virtual.arena_destroy(&arena)
	context.allocator = virtual.arena_allocator(&arena)

	src: ops.Scene
	ops.init(&src)
	golden_scene(&src)
	ops_bytes := ops.encode(&src)

	data := encode_reply(true, 0.25, ops_bytes)
	dbg: Reply_Debug
	wants_frame, frame_after, got_ops, ok := decode_reply(data, &dbg)
	testing.expect(t, !dbg.flash && !dbg.full_frames)
	testing.expect(t, ok)
	testing.expect(t, wants_frame)
	keep := []ops.Rect{{10, 20, 30, 40}, {1, 2, 3, 4}}
	_, _, again, ok2 := decode_reply(encode_reply(false, 0, ops_bytes, full_frames = true, flash = true, keep_out = keep), &dbg)
	testing.expect(t, ok2 && dbg.full_frames && dbg.flash)
	testing.expect(t, slice.equal(reply_keep_out(&dbg), keep))
	testing.expect(t, slice.equal(again, ops_bytes)) // the rects sit before the sc, not in them
	testing.expect_value(t, frame_after, f32(0.25))
	testing.expect(t, slice.equal(got_ops, ops_bytes))

	dst: ops.Scene
	ops.init(&dst)
	testing.expect(t, ops.decode(got_ops, &dst))
	testing.expect_value(t, ops.dump(&dst), ops.dump(&src))
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
		_, _, _, _, _, _, _ = decode_input(b, context.temp_allocator)
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

@(test)
test_decode_input_reads_input_from_before_the_host_stats :: proc(t: ^testing.T) {
	full := encode_input({800, 600}, 1, 0.5, nil, context.temp_allocator, Host_Stats{present_ms = 2, rss_bytes = 1 << 20})
	// The same input as a host from before the stats sent it, from before
	// the resident memory, and from before the restore string (4 bytes
	// for its empty length).
	for cut, i in ([]int{len(full) - 28, len(full) - 12, len(full) - 4}) {
		size, _, dt, _, host, restore, ok := decode_input(full[:cut], context.temp_allocator)
		testing.expect(t, ok)
		testing.expect_value(t, size, ops.Size{800, 600})
		testing.expect_value(t, dt, f32(0.5))
		testing.expect_value(t, host.rss_bytes, i < 2 ? 0 : 1 << 20)
		testing.expect_value(t, host.present_ms, i == 0 ? 0 : 2) // the timings, when sent, still read
		testing.expect_value(t, len(restore), 0)
	}
	_, _, _, _, host, _, ok := decode_input(full, context.temp_allocator)
	testing.expect(t, ok && host.rss_bytes == 1 << 20 && host.present_ms == 2)
}

@(test)
test_reply_carries_cursor_and_requests :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	p := Reply_Platform{cursor = .Text}
	p.requests_buf[0] = Clipboard_Write{TEXT_MIME, "copied"}
	p.requests_buf[1] = Clipboard_Read{TEXT_MIME}
	p.requests_buf[2] = Open_Url{"https://example.com/a?b=c"}
	p.requests_n = 3
	sc_bytes := []byte{1, 2, 3}
	data := encode_reply(true, 0, sc_bytes, context.temp_allocator, platform = &p)
	got: Reply_Platform
	wants, _, rest, ok := decode_reply(data, nil, &got)
	testing.expect(t, ok && wants)
	testing.expect(t, slice.equal(rest, sc_bytes), "the scene bytes follow the platform block")
	testing.expect(t, got.changed)
	testing.expect_value(t, got.cursor, ops.Cursor.Text)
	reqs := reply_requests(&got)
	testing.expect_value(t, len(reqs), 3)
	if len(reqs) == 3 {
		testing.expect_value(t, reqs[0].(Clipboard_Write).data, "copied")
		testing.expect_value(t, reqs[1].(Clipboard_Read).mime, TEXT_MIME)
		testing.expect_value(t, reqs[2].(Open_Url).url, "https://example.com/a?b=c")
	}

	// A reply with nothing for the platform is the old layout, byte for byte.
	plain := encode_reply(false, 0, sc_bytes, context.temp_allocator)
	none: Reply_Platform
	_, _, _, ok = decode_reply(plain, nil, &none)
	testing.expect(t, ok)
	testing.expect(t, !none.changed && none.requests_n == 0)
	testing.expect_value(t, plain[0] & 8, 0)
}

@(test)
test_reply_with_an_unknown_request_is_rejected :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	// flags 8, frame_after 0, cursor Default, one request of kind 9.
	data := []byte{8, 0, 0, 0, 0, 0, 1, 9}
	_, _, _, ok := decode_reply(data)
	testing.expect(t, !ok)
}

@(test)
test_input_carries_what_the_last_child_persisted :: proc(t: ^testing.T) {
	data := encode_input({800, 600}, 1, 0, nil, context.temp_allocator, restore = transmute([]byte)string("page 3"))
	_, _, _, _, _, restore, ok := decode_input(data, context.temp_allocator)
	testing.expect(t, ok)
	testing.expect_value(t, string(restore), "page 3")
}

@(test)
test_reply_carries_what_the_child_persists :: proc(t: ^testing.T) {
	sc_bytes := []byte{1, 2, 3}
	data := encode_reply(true, 0.5, sc_bytes, context.temp_allocator, persist = transmute([]byte)string("count 4"), focus = 42)
	persist: []byte
	plat: Reply_Platform
	wants, after, got, ok := decode_reply(data, nil, &plat, &persist)
	testing.expect(t, ok && wants)
	testing.expect_value(t, after, f32(0.5))
	testing.expect_value(t, plat.focus, ops.Area_Id(42))
	testing.expect_value(t, string(persist), "count 4")
	testing.expect(t, slice.equal(got, sc_bytes))
	// A reply with nothing to persist leaves persist alone.
	persist = nil
	_, _, got, ok = decode_reply(encode_reply(false, 0, sc_bytes, context.temp_allocator), persist = &persist)
	testing.expect(t, ok && persist == nil)
	testing.expect(t, slice.equal(got, sc_bytes))
}
