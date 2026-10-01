package ui

import "jm:ui/ops"

// Wire messages between a host (owns the window, input and rendering) and
// a subprocess (owns the Model and the ui proc), the two halves of the
// hot-reload split: the host sends one Input per frame it wants run, the
// subprocess replies with one Reply. Transport (framing, the pipe itself)
// is ui/ipc's job; this is only the byte layout, so it is exercised by
// plain encode/decode round-trip tests with no process or pipe involved.
// Both reuse encode.odin's put_*/get_* helpers and its little-endian rule.
//
//	Input: f32 w, f32 h, f32 density, f32 dt, u32 n, n × Raw_Event,
//	       [host stats], str restore (what the last child persisted,
//	       sent once to a respawned child; "" otherwise)
//	Raw_Event: u8 kind, f32 x, f32 y, u8 button, f32 sx, f32 sy, u8 key,
//	           u8 mods, str text, str mime, u8 clicks
//	Reply: u8 flags, f32 frame_after, [debug block], [platform block], then
//	       encode(sc)'s own bytes verbatim — Reply carries no length for
//	       them; the transport frame they arrived in already bounds where
//	       they end. Flags: 1 wants a frame, 2 full frames, 4 flash (a count
//	       and rects follow), 8 platform (u8 cursor, u8 n, n × request:
//	       u8 1 str mime str data for a clipboard write, u8 2 str mime for a
//	       read), 16 persist (str data the host keeps for the next child).
//	       The platform block is written only when the cursor changed or a
//	       request is pending, so most replies are as before.

// encode_input serializes size, density, dt and events into a new byte
// slice, the host's half of one frame's round trip.
encode_input :: proc(size: ops.Size, density, dt: f32, events: []Raw_Event, allocator := context.allocator, host: Host_Stats = {}, restore: []byte = nil) -> []byte {
	w := make([dynamic]byte, 0, 64, allocator)
	ops.put_f32(&w, size.x)
	ops.put_f32(&w, size.y)
	ops.put_f32(&w, density)
	ops.put_f32(&w, dt)
	ops.put_u32(&w, u32(len(events)))
	for e in events {
		encode_raw_event(&w, e)
	}
	// What presenting the child's last frame cost the host, for its tray.
	// Trailing and optional: a reader from before a field reads the rest.
	ops.put_f32(&w, host.present_ms)
	ops.put_f32(&w, host.roundtrip_ms)
	ops.put_u32(&w, u32(host.repaint_rects))
	ops.put_u32(&w, u32(host.repaint_px))
	ops.put_u64(&w, u64(max(host.rss_bytes, 0)))
	ops.put_str(&w, string(restore))
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
	size: ops.Size,
	density, dt: f32,
	events: []Raw_Event,
	host: Host_Stats,
	restore: []byte,
	ok: bool,
) {
	r := ops.Reader {
		data      = data,
		allocator = allocator,
	}
	size.x = ops.get_f32(&r) or_return
	size.y = ops.get_f32(&r) or_return
	density = ops.get_f32(&r) or_return
	dt = ops.get_f32(&r) or_return
	n := ops.get_count(&r, 1) or_return
	out := make([]Raw_Event, n, allocator)
	for &e in out {
		e = decode_raw_event(&r) or_return
	}
	// The host's stats are trailing and optional, so a child and a host
	// built either side of a new field still talk: each is read only if
	// the input still has bytes.
	if r.pos < len(r.data) {
		host.present_ms = ops.get_f32(&r) or_return
		host.roundtrip_ms = ops.get_f32(&r) or_return
		host.repaint_rects = int(ops.get_u32(&r) or_return)
		host.repaint_px = int(ops.get_u32(&r) or_return)
	}
	if r.pos < len(r.data) {
		host.rss_bytes = int(ops.get_u64(&r) or_return)
	}
	if r.pos < len(r.data) {
		s := ops.get_str(&r) or_return
		if len(s) > 0 {
			restore = transmute([]byte)s
		}
	}
	if r.pos != len(r.data) {
		return {}, 0, 0, nil, {}, nil, false
	}
	return size, density, dt, out, host, restore, true
}

@(private = "file")
encode_raw_event :: proc(w: ^[dynamic]byte, e: Raw_Event) {
	append(w, u8(e.kind))
	ops.put_f32(w, e.pos.x)
	ops.put_f32(w, e.pos.y)
	append(w, u8(e.button))
	ops.put_f32(w, e.scroll.x)
	ops.put_f32(w, e.scroll.y)
	append(w, u8(e.key))
	append(w, transmute(u8)e.mods)
	ops.put_str(w, e.text)
	ops.put_str(w, e.mime)
	append(w, e.clicks)
}

@(private = "file")
decode_raw_event :: proc(r: ^ops.Reader) -> (e: Raw_Event, ok: bool) {
	kind := ops.get_u8(r) or_return
	if kind > u8(max(ops.Event_Kind)) {
		return {}, false
	}
	e.kind = ops.Event_Kind(kind)
	e.pos.x = ops.get_f32(r) or_return
	e.pos.y = ops.get_f32(r) or_return
	button := ops.get_u8(r) or_return
	if button > u8(max(Button)) {
		return {}, false
	}
	e.button = Button(button)
	e.scroll.x = ops.get_f32(r) or_return
	e.scroll.y = ops.get_f32(r) or_return
	key := ops.get_u8(r) or_return
	if key > u8(max(Key)) {
		return {}, false
	}
	e.key = Key(key)
	mods := ops.get_u8(r) or_return
	if mods >= 1 << (uint(max(Mod)) + 1) {
		return {}, false
	}
	e.mods = transmute(Mods)mods
	e.text = ops.get_str(r) or_return
	e.mime = ops.get_str(r) or_return
	e.clicks = ops.get_u8(r) or_return
	return e, true
}

// encode_reply serializes wants_frame, frame_after and ops_bytes (already
// ui.encode(sc)'s own output) into a new byte slice, the subprocess's
// half of one frame's round trip.
encode_reply :: proc(
	wants_frame: bool,
	frame_after: f32,
	ops_bytes: []byte,
	allocator := context.allocator,
	full_frames := false,
	flash := false,
	keep_out: []ops.Rect = nil,
	platform: ^Reply_Platform = nil,
	persist: []byte = nil,
) -> []byte {
	w := make([dynamic]byte, 0, 5 + len(ops_bytes), allocator)
	// Bit 0: wants another frame. Bit 1: redraw it whole (the debug tray's
	// full frames), since the compositor runs in the host. Bit 2: flash
	// what it repaints, but not over keep_out, the debug panels, which
	// follow as a count and rects. Bit 4: persist bytes follow.
	append(&w, (u8(1) if wants_frame else 0) | (u8(2) if full_frames else 0) | (u8(4) if flash else 0) | (u8(8) if platform != nil else 0) | (u8(16) if persist != nil else 0))
	ops.put_f32(&w, frame_after)
	if flash {
		append(&w, u8(min(len(keep_out), 255)))
		for r in keep_out[:min(len(keep_out), 255)] {
			ops.put_rect(&w, r)
		}
	}
	if platform != nil {
		append(&w, u8(platform.cursor))
		reqs := reply_requests(platform)
		append(&w, u8(len(reqs)))
		for q in reqs {
			switch v in q {
			case Clipboard_Write:
				append(&w, 1)
				ops.put_str(&w, v.mime)
				ops.put_str(&w, v.data)
			case Clipboard_Read:
				append(&w, 2)
				ops.put_str(&w, v.mime)
			case Open_Url:
				append(&w, 3)
				ops.put_str(&w, v.url)
			}
		}
	}
	if persist != nil {
		ops.put_str(&w, string(persist))
	}
	append(&w, ..ops_bytes)
	return w[:]
}

// decode_reply is encode_reply's inverse: ops_bytes is a slice into data
// (not copied), meant for an immediate ui.decode, and so is what the
// child asked to persist, left in persist^ when it is given (nil when the
// reply carries none): the host copies it before data goes.
// keep_out is read into its fixed buffer; the reply's flags and keep_out
// come back as Reply_Debug.
decode_reply :: proc(data: []byte, dbg: ^Reply_Debug = nil, platform: ^Reply_Platform = nil, persist: ^[]byte = nil) -> (wants_frame: bool, frame_after: f32, ops_bytes: []byte, ok: bool) {
	r := ops.Reader {
		data      = data,
		allocator = context.temp_allocator,
	}
	flag := ops.get_u8(&r) or_return
	if flag > 31 {
		return false, 0, nil, false
	}
	d: Reply_Debug
	wants_frame, d.full_frames, d.flash = flag & 1 != 0, flag & 2 != 0, flag & 4 != 0
	frame_after = ops.get_f32(&r) or_return
	if d.flash {
		n := int(ops.get_u8(&r) or_return)
		for i in 0 ..< n {
			rect := ops.get_rect(&r) or_return
			if i < len(d.keep_out_buf) {
				d.keep_out_buf[i] = rect
				d.keep_out_n = i + 1
			}
		}
	}
	if dbg != nil {
		dbg^ = d
	}
	p: Reply_Platform
	if flag & 8 != 0 {
		c := ops.get_u8(&r) or_return
		if c > u8(max(ops.Cursor)) {
			return false, 0, nil, false
		}
		p.cursor = ops.Cursor(c)
		p.changed = true
		n := int(ops.get_u8(&r) or_return)
		for _ in 0 ..< n {
			q: Request
			switch ops.get_u8(&r) or_return {
			case 1:
				mime := ops.get_str(&r) or_return
				data := ops.get_str(&r) or_return
				q = Clipboard_Write{mime, data}
			case 2:
				q = Clipboard_Read{ops.get_str(&r) or_return}
			case 3:
				q = Open_Url{ops.get_str(&r) or_return}
			case:
				return false, 0, nil, false
			}
			if p.requests_n < len(p.requests_buf) {
				p.requests_buf[p.requests_n] = q
				p.requests_n += 1
			}
		}
	}
	if platform != nil {
		platform^ = p
	}
	if flag & 16 != 0 {
		n := ops.get_count(&r, 1) or_return
		start := r.pos
		_ = ops.take(&r, n) or_return
		if persist != nil {
			persist^ = data[start:start + n]
		}
	}
	return wants_frame, frame_after, data[r.pos:], true
}

// Reply_Platform is what a reply asks of the host's platform: the cursor,
// when changed is set, and the frame's requests (request.odin). Strings in
// the requests are in the temp allocator.
Reply_Platform :: struct {
	cursor:       ops.Cursor,
	changed:      bool,
	requests_buf: [4]Request,
	requests_n:   int,
}

// reply_requests is p's requests, in the order the child made them.
reply_requests :: proc(p: ^Reply_Platform) -> []Request {
	return p.requests_buf[:p.requests_n]
}

// Reply_Debug is what a reply asks of the host for the child's debug tray:
// full frames, the repaint flash, and where the flash must not draw.
Reply_Debug :: struct {
	full_frames:  bool,
	flash:        bool,
	keep_out_buf: [4]ops.Rect,
	keep_out_n:   int,
}

// reply_keep_out is d's rects the flash must leave alone.
reply_keep_out :: proc(d: ^Reply_Debug) -> []ops.Rect {
	return d.keep_out_buf[:d.keep_out_n]
}
