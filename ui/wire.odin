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
//	       sent once to a respawned child; "" otherwise), [shapes: u32 n,
//	       n × (u64 key, u8 status, str data), written only when there
//	       are any: what the host delivers for the child's needs]
//	Raw_Event: u8 kind, f32 x, f32 y, u8 button, f32 sx, f32 sy, u8 key,
//	           u8 mods, str text, str mime, u8 clicks, u64 area, and for a
//	           Compose only u32 lo, u32 hi (its span)
//	Reply: u8 flags, f32 frame_after, u64 focus (the focused area, 0 for
//	       none: what the host tells assistive technology), [debug block],
//	       [platform block], [persist], then
//	       encode(sc)'s own bytes verbatim — Reply carries no length for
//	       them; the transport frame they arrived in already bounds where
//	       they end. Flags: 1 wants a frame, 2 full frames, 4 flash (a count
//	       and rects follow), 8 platform (u8 cursor, u8 n, n × request:
//	       u8 1 str mime str data for a clipboard write, u8 2 str mime for a
//	       read, u8 3 str url, u8 4 u8 active u64 area rect f32 caret u8 kind
//	       for a Text_Input), 16 persist (str data the host keeps for the next child),
//	       32 needs (u32 n, n × need, u32 m, m × need: what the frame began
//	       to need and what it stopped needing; a need is u64 key, str kind,
//	       str query), 64 commands (u32 n, n × str kind, str data).
//	       The platform block is written only when the cursor changed or a
//	       request is pending, so most replies are as before; the needs and
//	       commands blocks likewise only when there is something to say.

// encode_input serializes size, density, dt and events into a new byte
// slice, the host's half of one frame's round trip.
encode_input :: proc(size: ops.Size, density, dt: f32, events: []Raw_Event, allocator := context.allocator, host: Host_Stats = {}, restore: []byte = nil, shapes: []Delivery = nil) -> []byte {
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
	// Shapes for the child's needs, only when there are any: a child from
	// before the block reads an input without one as it always did.
	if len(shapes) > 0 {
		ops.put_u32(&w, u32(len(shapes)))
		for d in shapes {
			ops.put_u64(&w, u64(d.key))
			append(&w, u8(d.status))
			ops.put_str(&w, string(d.data))
		}
	}
	return w[:]
}

// decode_input is encode_input's inverse. Strings are allocated from
// allocator; every field is bounds-checked before it is read, the same
// rule encode.odin's decode follows, so garbage input fails ok rather
// than reading past the end (test_decode_input_survives_random_bytes
// throws 1000 random and near-random slices at it as a check). The
// shapes the host delivered, if any, are left in shapes^ when it is
// given, their data slices into data.
decode_input :: proc(
	data: []byte,
	allocator := context.allocator,
	shapes: ^[]Delivery = nil,
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
	if shapes != nil {
		shapes^ = nil
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
	if r.pos < len(r.data) {
		count := ops.get_count(&r, 10) or_return
		got := make([]Delivery, count, allocator)
		for &d in got {
			d.key = Need_Key(ops.get_u64(&r) or_return)
			status := ops.get_u8(&r) or_return
			if status > u8(max(Status)) {
				return {}, 0, 0, nil, {}, nil, false
			}
			d.status = Status(status)
			s := ops.get_str(&r) or_return
			if len(s) > 0 {
				d.data = transmute([]byte)s
			}
		}
		if shapes != nil {
			shapes^ = got
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
	ops.put_u64(w, u64(e.area))
	if e.kind == .Compose {
		ops.put_u32(w, u32(e.span[0]))
		ops.put_u32(w, u32(e.span[1]))
	}
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
	e.area = ops.Area_Id(ops.get_u64(r) or_return)
	if e.kind == .Compose {
		e.span[0] = int(ops.get_u32(r) or_return)
		e.span[1] = int(ops.get_u32(r) or_return)
	}
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
	focus: ops.Area_Id = 0,
	data: ^Reply_Data = nil,
) -> []byte {
	w := make([dynamic]byte, 0, 5 + len(ops_bytes), allocator)
	// Bit 0: wants another frame. Bit 1: redraw it whole (the debug tray's
	// full frames), since the compositor runs in the host. Bit 2: flash
	// what it repaints, but not over keep_out, the debug panels, which
	// follow as a count and rects. Bit 4: persist bytes follow. Bit 5:
	// needs that began and ended follow. Bit 6: commands follow.
	needs := data != nil && (len(data.added) > 0 || len(data.dropped) > 0)
	commands := data != nil && len(data.commands) > 0
	append(&w, (u8(1) if wants_frame else 0) | (u8(2) if full_frames else 0) | (u8(4) if flash else 0) | (u8(8) if platform != nil else 0) | (u8(16) if persist != nil else 0) | (u8(32) if needs else 0) | (u8(64) if commands else 0))
	ops.put_f32(&w, frame_after)
	ops.put_u64(&w, u64(focus))
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
			case Text_Input:
				append(&w, 4)
				append(&w, u8(v.active))
				ops.put_u64(&w, u64(v.area))
				ops.put_rect(&w, v.rect)
				ops.put_f32(&w, v.caret)
				append(&w, u8(v.kind))
			case Pick_Path:
				append(&w, 5)
				ops.put_u64(&w, u64(v.area))
				append(&w, u8(v.folder))
				ops.put_str(&w, v.start)
			}
		}
	}
	if persist != nil {
		ops.put_str(&w, string(persist))
	}
	if needs {
		encode_needs(&w, data.added)
		encode_needs(&w, data.dropped)
	}
	if commands {
		ops.put_u32(&w, u32(len(data.commands)))
		for c in data.commands {
			ops.put_str(&w, c.kind)
			ops.put_str(&w, string(c.data))
		}
	}
	append(&w, ..ops_bytes)
	return w[:]
}

@(private = "file")
encode_needs :: proc(w: ^[dynamic]byte, needs: []Need) {
	ops.put_u32(w, u32(len(needs)))
	for n in needs {
		ops.put_u64(w, u64(n.key))
		ops.put_str(w, n.kind)
		ops.put_str(w, string(n.query))
	}
}

@(private = "file")
decode_needs :: proc(r: ^ops.Reader) -> (needs: []Need, ok: bool) {
	n := ops.get_count(r, 10) or_return
	needs = make([]Need, n, r.allocator)
	for &need in needs {
		need.key = Need_Key(ops.get_u64(r) or_return)
		need.kind = ops.get_str(r) or_return
		need.query = transmute([]byte)(ops.get_str(r) or_return)
	}
	return needs, true
}

// decode_reply is encode_reply's inverse: ops_bytes is a slice into data
// (not copied), meant for an immediate ui.decode, and so is what the
// child asked to persist, left in persist^ when it is given (nil when the
// reply carries none): the host copies it before data goes. The needs and
// commands are left in out^ when it is given, their strings in the temp
// allocator. keep_out is read into its fixed buffer; the reply's flags and
// keep_out come back as Reply_Debug.
decode_reply :: proc(data: []byte, dbg: ^Reply_Debug = nil, platform: ^Reply_Platform = nil, persist: ^[]byte = nil, out: ^Reply_Data = nil) -> (wants_frame: bool, frame_after: f32, ops_bytes: []byte, ok: bool) {
	r := ops.Reader {
		data      = data,
		allocator = context.temp_allocator,
	}
	flag := ops.get_u8(&r) or_return
	if flag > 127 {
		return false, 0, nil, false
	}
	d: Reply_Debug
	wants_frame, d.full_frames, d.flash = flag & 1 != 0, flag & 2 != 0, flag & 4 != 0
	frame_after = ops.get_f32(&r) or_return
	focus := ops.Area_Id(ops.get_u64(&r) or_return)
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
	p.focus = focus
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
			case 4:
				ti: Text_Input
				ti.active = (ops.get_u8(&r) or_return) != 0
				ti.area = ops.Area_Id(ops.get_u64(&r) or_return)
				ti.rect = ops.get_rect(&r) or_return
				ti.caret = ops.get_f32(&r) or_return
				kind := ops.get_u8(&r) or_return
				if kind > u8(max(Text_Input_Kind)) {
					return false, 0, nil, false
				}
				ti.kind = Text_Input_Kind(kind)
				q = ti
			case 5:
				area := ops.Area_Id(ops.get_u64(&r) or_return)
				folder := ops.get_u8(&r) or_return
				q = Pick_Path{area, folder != 0, ops.get_str(&r) or_return}
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
	rd: Reply_Data
	if flag & 32 != 0 {
		rd.added = decode_needs(&r) or_return
		rd.dropped = decode_needs(&r) or_return
	}
	if flag & 64 != 0 {
		n := ops.get_count(&r, 2) or_return
		rd.commands = make([]Command, n, r.allocator)
		for &c in rd.commands {
			c.kind = ops.get_str(&r) or_return
			c.data = transmute([]byte)(ops.get_str(&r) or_return)
		}
	}
	if out != nil {
		out^ = rd
	}
	return wants_frame, frame_after, data[r.pos:], true
}

// Reply_Data is the data half of a reply: the needs the frame began and
// stopped having, and the commands it asked the application to process.
// A host starts the added, cancels the dropped and passes the commands on
// (see need.odin). Strings are in the temp allocator.
Reply_Data :: struct {
	added:    []Need,
	dropped:  []Need,
	commands: []Command,
}

// Reply_Platform is what a reply asks of the host's platform: the cursor,
// when changed is set, and the frame's requests (request.odin). Strings in
// the requests are in the temp allocator.
Reply_Platform :: struct {
	cursor:       ops.Cursor,
	changed:      bool,
	requests_buf: [8]Request, // room for one of each kind a frame makes, and more
	requests_n:   int,
	focus:        ops.Area_Id, // the child's focused area, every reply
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
