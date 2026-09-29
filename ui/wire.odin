package ui

// Wire messages between a host (owns the window, input and rendering) and
// a subprocess (owns the Model and the ui proc), the two halves of the
// hot-reload split: the host sends one Input per frame it wants run, the
// subprocess replies with one Reply. Transport (framing, the pipe itself)
// is ui/ipc's job; this is only the byte layout, so it is exercised by
// plain encode/decode round-trip tests with no process or pipe involved.
// Both reuse encode.odin's put_*/get_* helpers and its little-endian rule.
//
//	Input: f32 w, f32 h, f32 density, f32 dt, u32 n, n × Raw_Event
//	Raw_Event: u8 kind, f32 x, f32 y, u8 button, f32 sx, f32 sy, u8 key,
//	           u8 mods, str text
//	Reply: u8 wants_frame, f32 frame_after, then encode(ops)'s own bytes
//	       verbatim — Reply carries no length for them; the transport frame
//	       they arrived in already bounds where they end.

// encode_input serializes size, density, dt and events into a new byte
// slice, the host's half of one frame's round trip.
encode_input :: proc(size: Size, density, dt: f32, events: []Raw_Event, allocator := context.allocator, host: Host_Stats = {}) -> []byte {
	w := make([dynamic]byte, 0, 64, allocator)
	put_f32(&w, size.x)
	put_f32(&w, size.y)
	put_f32(&w, density)
	put_f32(&w, dt)
	put_u32(&w, u32(len(events)))
	for e in events {
		encode_raw_event(&w, e)
	}
	// What presenting the child's last frame cost the host, for its tray.
	put_f32(&w, host.present_ms)
	put_f32(&w, host.roundtrip_ms)
	put_u32(&w, u32(host.repaint_rects))
	put_u32(&w, u32(host.repaint_px))
	return w[:]
}

// decode_input is encode_input's inverse. Strings are allocated from
// allocator; every field is bounds-checked before it is read, the same
// rule encode.odin's decode follows, so garbage input fails ok rather
// than reading past the end (test_decode_input_survives_random_bytes
// throws 1000 random and near-random slices at it as a check).
decode_input :: proc(
	data: []byte,
	allocator := context.allocator,
) -> (
	size: Size,
	density, dt: f32,
	events: []Raw_Event,
	host: Host_Stats,
	ok: bool,
) {
	r := Reader {
		data      = data,
		allocator = allocator,
	}
	size.x = get_f32(&r) or_return
	size.y = get_f32(&r) or_return
	density = get_f32(&r) or_return
	dt = get_f32(&r) or_return
	n := get_count(&r, 1) or_return
	out := make([]Raw_Event, n, allocator)
	for &e in out {
		e = decode_raw_event(&r) or_return
	}
	host.present_ms = get_f32(&r) or_return
	host.roundtrip_ms = get_f32(&r) or_return
	host.repaint_rects = int(get_u32(&r) or_return)
	host.repaint_px = int(get_u32(&r) or_return)
	if r.pos != len(r.data) {
		return {}, 0, 0, nil, {}, false
	}
	return size, density, dt, out, host, true
}

@(private = "file")
encode_raw_event :: proc(w: ^[dynamic]byte, e: Raw_Event) {
	append(w, u8(e.kind))
	put_f32(w, e.pos.x)
	put_f32(w, e.pos.y)
	append(w, u8(e.button))
	put_f32(w, e.scroll.x)
	put_f32(w, e.scroll.y)
	append(w, u8(e.key))
	append(w, transmute(u8)e.mods)
	put_str(w, e.text)
}

@(private = "file")
decode_raw_event :: proc(r: ^Reader) -> (e: Raw_Event, ok: bool) {
	kind := get_u8(r) or_return
	if kind > u8(max(Event_Kind)) {
		return {}, false
	}
	e.kind = Event_Kind(kind)
	e.pos.x = get_f32(r) or_return
	e.pos.y = get_f32(r) or_return
	button := get_u8(r) or_return
	if button > u8(max(Button)) {
		return {}, false
	}
	e.button = Button(button)
	e.scroll.x = get_f32(r) or_return
	e.scroll.y = get_f32(r) or_return
	key := get_u8(r) or_return
	if key > u8(max(Key)) {
		return {}, false
	}
	e.key = Key(key)
	mods := get_u8(r) or_return
	if mods >= 1 << (uint(max(Mod)) + 1) {
		return {}, false
	}
	e.mods = transmute(Mods)mods
	e.text = get_str(r) or_return
	return e, true
}

// encode_reply serializes wants_frame, frame_after and ops_bytes (already
// ui.encode(ops)'s own output) into a new byte slice, the subprocess's
// half of one frame's round trip.
encode_reply :: proc(
	wants_frame: bool,
	frame_after: f32,
	ops_bytes: []byte,
	allocator := context.allocator,
	full_frames := false,
	flash := false,
	keep_out: []Rect = nil,
) -> []byte {
	w := make([dynamic]byte, 0, 5 + len(ops_bytes), allocator)
	// Bit 0: wants another frame. Bit 1: redraw it whole (the debug tray's
	// full frames), since the compositor runs in the host. Bit 2: flash
	// what it repaints, but not over keep_out, the debug panels, which
	// follow as a count and rects.
	append(&w, (u8(1) if wants_frame else 0) | (u8(2) if full_frames else 0) | (u8(4) if flash else 0))
	put_f32(&w, frame_after)
	if flash {
		append(&w, u8(min(len(keep_out), 255)))
		for r in keep_out[:min(len(keep_out), 255)] {
			put_rect(&w, r)
		}
	}
	append(&w, ..ops_bytes)
	return w[:]
}

// decode_reply is encode_reply's inverse: ops_bytes is a slice into data
// (not copied), meant for an immediate ui.decode.
// keep_out is read into its fixed buffer; the reply's flags and keep_out
// come back as Reply_Debug.
decode_reply :: proc(data: []byte, dbg: ^Reply_Debug = nil) -> (wants_frame: bool, frame_after: f32, ops_bytes: []byte, ok: bool) {
	r := Reader{data = data}
	flag := get_u8(&r) or_return
	if flag > 7 {
		return false, 0, nil, false
	}
	d: Reply_Debug
	wants_frame, d.full_frames, d.flash = flag & 1 != 0, flag & 2 != 0, flag & 4 != 0
	frame_after = get_f32(&r) or_return
	if d.flash {
		n := int(get_u8(&r) or_return)
		for i in 0 ..< n {
			rect := get_rect(&r) or_return
			if i < len(d.keep_out_buf) {
				d.keep_out_buf[i] = rect
				d.keep_out_n = i + 1
			}
		}
	}
	if dbg != nil {
		dbg^ = d
	}
	return wants_frame, frame_after, data[r.pos:], true
}

// Reply_Debug is what a reply asks of the host for the child's debug tray:
// full frames, the repaint flash, and where the flash must not draw.
Reply_Debug :: struct {
	full_frames:  bool,
	flash:        bool,
	keep_out_buf: [4]Rect,
	keep_out_n:   int,
}

// reply_keep_out is d's rects the flash must leave alone.
reply_keep_out :: proc(d: ^Reply_Debug) -> []Rect {
	return d.keep_out_buf[:d.keep_out_n]
}
