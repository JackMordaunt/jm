package ui

import "jm:ui/ops"

// Requests are what a frame asks of the platform, beyond pixels: the
// clipboard written or read, a URL opened. A widget makes one during layout; the Router
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
	Open_Url,
}

// Clipboard_Write puts data on the clipboard as mime.
Clipboard_Write :: struct {
	mime, data: string,
}

// Clipboard_Read asks for the clipboard as mime, answered with a Paste.
Clipboard_Read :: struct {
	mime: string,
}

// Open_Url asks the platform to open url with the system's handler for
// its scheme: a browser for http and https, a mail client for mailto.
Open_Url :: struct {
	url: string,
}

// open_url asks the platform to open url once the frame is done, as a
// click on a link would. The ui learns nothing back: whether a handler
// exists is the platform's business. Each call is one request; url is
// copied.
open_url :: proc(gtx: ^Ctx, url: string) {
	r := gtx.router
	if r == nil || url == "" {
		return
	}
	append(&r.requests, Open_Url{clone_string(url, r.allocator)})
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

// persist asks the host to keep data across a hot-reload respawn: the
// next child's first frame reads it back with restored. The host keeps
// the latest, so call it when the state changes (or every frame, for a
// few bytes). data must live until the frame ends; gtx.allocator does.
// A loop with no host (ui/sdl's own, a probe) keeps nothing.
persist :: proc(gtx: ^Ctx, data: []byte) {
	gtx.persist = data
}

// restored is what the previous child persisted, on the first frame a
// respawned child runs, and nil on every other frame: an app parses it
// there and goes on from where the last build left off.
restored :: proc(gtx: ^Ctx) -> []byte {
	return gtx.restored
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

// focus_first moves keyboard focus, at the next route, to the first area
// that wants keys inside the focus scope named scope (ops.Focus_Scope) in
// the frame just laid out: a dialog's or menu's first control, whatever
// its id. With no such area focus stays where it is.
focus_first :: proc(gtx: ^Ctx, scope: ops.Area_Id) {
	r := gtx.router
	if r == nil {
		return
	}
	r.focus_into = scope
	r.into_asked = true
}

// focused is the area that holds keyboard focus, 0 for none: what a popup
// remembers as it opens, to give focus back as it closes.
focused :: proc(gtx: ^Ctx) -> ops.Area_Id {
	return gtx.router.focus if gtx.router != nil else 0
}

// focus_scope_open opens a focus scope named id over what is recorded
// until focus_scope_close (see ops.Focus_Scope): with trap, keyboard
// focus stays inside it while it is the newest trap.
focus_scope_open :: proc(gtx: ^Ctx, id: ops.Area_Id, trap := false) {
	ops.focus_scope(gtx.scene, id, trap)
}

// focus_scope_close closes the innermost focus scope.
focus_scope_close :: proc(gtx: ^Ctx) {
	ops.focus_scope_end(gtx.scene)
}

// focus_visible reports whether the focused area should show a focus
// indicator: the last input was a key rather than a pointer press. A
// design system reads it to draw its ring only for keyboard users.
focus_visible :: proc(gtx: ^Ctx) -> bool {
	return gtx.router != nil && gtx.router.keyboard
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
	case Open_Url:
		delete(v.url, r.allocator)
	}
}
