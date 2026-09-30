package ui

import "jm:ui/ops"

// Requests are what a frame asks of the platform, beyond pixels: the
// clipboard written or read. A widget makes one during layout; the Router
// queues it, and whatever runs the frame (ui/sdl's loop, a host over the
// wire, the probe) drains the queue once the frame is done, with
// router_requests then router_requests_clear. Gio calls these commands.
//
// A read is answered by an event, not a return value: the platform reads
// the clipboard and pushes a Paste Raw_Event, which the next route
// delivers to every area that asked, whether or not the pointer or focus
// is on it. So paste works from a shortcut, a menu or a button alike, and
// a platform whose clipboard answers late (Gio's Wayland driver reads the
// offer's pipe on a goroutine, app/os_wayland.go) answers a frame or two
// later instead of blocking the frame.
//
// Focus is also requested, but the router grants it itself at the next
// route: it never leaves the process.

// TEXT_MIME is the type of plain UTF-8 text on the clipboard.
TEXT_MIME :: "text/plain;charset=utf-8"

Request :: union {
	Clipboard_Write,
	Clipboard_Read,
}

// Clipboard_Write puts data on the clipboard as mime.
Clipboard_Write :: struct {
	mime, data: string,
}

// Clipboard_Read asks for the clipboard as mime, answered with a Paste.
Clipboard_Read :: struct {
	mime: string,
}

// clipboard_write puts text on the clipboard once the frame is done. The
// frame's last write wins. text is copied.
clipboard_write :: proc(gtx: ^Ctx, text: string, mime := TEXT_MIME) {
	r := gtx.router
	if r == nil {
		return
	}
	for &q, i in r.requests {
		if w, ok := q.(Clipboard_Write); ok {
			free_request(r, w)
			ordered_remove(&r.requests, i)
			break
		}
	}
	append(&r.requests, Clipboard_Write{clone_string(mime, r.allocator), clone_string(text, r.allocator)})
}

// clipboard_read asks for the clipboard's text for area, which receives
// it as a Paste event in a later frame. Several areas may ask in one
// frame; each receives the same Paste.
clipboard_read :: proc(gtx: ^Ctx, area: ops.Area_Id, mime := TEXT_MIME) {
	r := gtx.router
	if r == nil || area == 0 {
		return
	}
	for a in r.readers {
		if a == area {
			return
		}
	}
	append(&r.readers, area)
	for q in r.requests {
		if _, ok := q.(Clipboard_Read); ok {
			return
		}
	}
	append(&r.requests, Clipboard_Read{clone_string(mime, r.allocator)})
}

// focus_request moves keyboard focus to area at the next route, sending
// Blur and Focus as a press would; 0 clears focus. An area missing from
// the frame just laid out keeps the focus where it is.
focus_request :: proc(gtx: ^Ctx, area: ops.Area_Id) {
	r := gtx.router
	if r == nil {
		return
	}
	r.focus_next = area
	r.focus_asked = true
}

// router_requests is what the frames since the last router_requests_clear
// asked of the platform, in the order asked. Valid until that clear.
router_requests :: proc(r: ^Router) -> []Request {
	return r.requests[:]
}

// router_requests_clear forgets the requests router_requests returned,
// once the platform has carried them out.
router_requests_clear :: proc(r: ^Router) {
	for q in r.requests {
		free_request(r, q)
	}
	clear(&r.requests)
}

// router_cursor is the pointer's look as of the last route: the cursor of
// the grabbing area during a drag, else of the top-most area under the
// pointer, else Default.
router_cursor :: proc(r: ^Router) -> ops.Cursor {
	return r.cursor
}

@(private = "file")
free_request :: proc(r: ^Router, q: Request) {
	switch v in q {
	case Clipboard_Write:
		delete(v.mime, r.allocator)
		delete(v.data, r.allocator)
	case Clipboard_Read:
		delete(v.mime, r.allocator)
	}
}
