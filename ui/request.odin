package ui

import "jm:ui/ops"

// Requests are what a frame asks of the platform, beyond pixels: the
// clipboard written or read, a URL opened, the input method turned on at
// a caret or off. A widget makes one during layout; the Router
// queues it, and whatever runs the frame (ui/shell's loop, a host over the
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
	Text_Input,
	Pick_Path,
}

// Clipboard_Write puts data on the clipboard as mime.
Clipboard_Write :: struct {
	mime, data: string,
}

// Clipboard_Read asks for the clipboard as mime, answered with a Paste.
Clipboard_Read :: struct {
	mime: string,
}

// Pick_Path asks the platform's own dialog for a file to open, a folder,
// or where to save a file, for area, which is answered with a Picked
// event, or Pick_Failed when the dialog cannot be shown: pick_file,
// pick_folder and pick_save ask. start is the folder the dialog opens in;
// "" leaves it to the platform. A save also suggests name for the file
// and offers filters, the first of them chosen to begin with; an open
// leaves both empty.
Pick_Path :: struct {
	area:    ops.Area_Id,
	kind:    Pick_Kind,
	start:   string,
	name:    string,
	filters: []Pick_Filter,
}

// Pick_Kind is which dialog a Pick_Path opens. File and Folder keep the
// byte the wire once gave a bool folder.
Pick_Kind :: enum u8 {
	File,
	Folder,
	Save,
}

// Pick_Filter is one entry of a save dialog's file types, as SDL's
// DialogFileFilter (SDL_dialog.h): label is what the person reads ("PDF
// document"), and patterns "a semicolon-separated list of file
// extensions (for example, "doc;docx")", or a single "*" for any file.
Pick_Filter :: struct {
	label:    string,
	patterns: string,
}

// Open_Url asks the platform to open url with the system's handler for
// its scheme: a browser for http and https, a mail client for mailto.
Open_Url :: struct {
	url: string,
}

// Text_Input is what the focused area wants of the platform's input
// method: on, while an editable text area holds focus, else off. area is
// the area it is for; rect, in device pixels, is the text the method must
// not cover, a field or the caret's line, and caret the caret's x offset
// into rect, where a candidate window opens. kind tells an on-screen
// keyboard what to show, and Password turns composition off. The router
// queues one only when it differs from the last (text_input_update).
Text_Input :: struct {
	active: bool,
	area:   ops.Area_Id,
	rect:   ops.Rect,
	caret:  f32,
	kind:   Text_Input_Kind,
}

Text_Input_Kind :: enum u8 {
	Text,
	Number,
	Email,
	Url,
	Password,
}

// Caret_Ask is a text_caret call for the focused area, in its local space,
// kept by the router from layout until text_input_update.
@(private)
Caret_Ask :: struct {
	area:      ops.Area_Id,
	rect:      ops.Rect,
	caret:     f32,
	kind:      Text_Input_Kind,
	read_only: bool,
}

// text_caret tells the input method, during layout, where text area id
// has its caret: rect is the field (or, in a multi-line field, the caret's
// line) and caret_x the caret's x, both in the space id's input area was
// recorded in. Only the focused area's call counts; one that never calls
// it gets its whole area and a caret at its left edge. A read_only area
// turns the input method off.
text_caret :: proc(gtx: ^Ctx, id: ops.Area_Id, rect: ops.Rect, caret_x: f32, kind := Text_Input_Kind.Text, read_only := false) {
	r := gtx.router
	if r == nil || id == 0 || id != r.focus {
		return
	}
	r.caret_ask = {id, rect, caret_x, kind, read_only}
}

// text_input_update queues a Text_Input when what the focused area wants
// of the input method changed: call it once f, the frame just laid out,
// is flattened, before taking router_requests.
text_input_update :: proc(r: ^Router, f: ^Frame) {
	want: Text_Input
	h: Hit
	if r.focus != 0 && f != nil && refresh(f, r.focus, &h) && .Text in h.kinds {
		a := r.caret_ask
		switch {
		case a.area != r.focus:
			bounds := ops.transform_rect(h.transform, ops.shape_bounds(f.scene, h.shape))
			want = {active = true, area = r.focus, rect = bounds}
		case !a.read_only:
			rect := ops.transform_rect(h.transform, a.rect)
			caret := ops.apply(h.transform, {a.caret, a.rect.y}).x - rect.x
			want = {active = true, area = r.focus, rect = rect, caret = clamp(caret, 0, rect.w), kind = a.kind}
		}
	}
	r.caret_ask = {}
	if want != r.ime_sent {
		r.ime_sent = want
		append(&r.requests, want)
	}
}

// input_method is the input method as the router last asked the platform
// for it (Text_Input; off, zero, until a text area takes focus): what a
// lab or debug view shows. Its rect is in device pixels.
input_method :: proc(gtx: ^Ctx) -> Text_Input {
	return gtx.router.ime_sent if gtx.router != nil else {}
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

// pick_folder opens the platform's folder dialog once the frame is done.
// area receives a Picked event when the person chooses: the folder's
// path, or "" for a cancel, a frame or more later, since the dialog
// stays open as long as the person takes. When the platform cannot show
// the dialog at all, area receives Pick_Failed instead. start is copied.
pick_folder :: proc(gtx: ^Ctx, area: ops.Area_Id, start := "") {
	pick(gtx, area, .Folder, start)
}

// pick_file is pick_folder for a file to open.
pick_file :: proc(gtx: ^Ctx, area: ops.Area_Id, start := "") {
	pick(gtx, area, .File, start)
}

// pick_save is pick_folder for where to save a file: the dialog opens in
// start with suggested_name filled in, offering filters, the first
// chosen. Whether a file already at the path is replaced is the dialog's
// question: SDL 3.4 asks for overwrite confirmation on Windows
// (FOS_OVERWRITEPROMPT) and through zenity (--confirm-overwrite), macOS's
// NSSavePanel asks itself, and over the XDG portal the portal's backend
// decides. Every string is copied.
pick_save :: proc(
	gtx: ^Ctx,
	area: ops.Area_Id,
	suggested_name := "",
	start := "",
	filters: []Pick_Filter = nil,
) {
	pick(gtx, area, .Save, start, suggested_name, filters)
}

@(private)
pick :: proc(
	gtx: ^Ctx,
	area: ops.Area_Id,
	kind: Pick_Kind,
	start: string,
	name := "",
	filters: []Pick_Filter = nil,
) {
	r := gtx.router
	if r == nil || area == 0 {
		return
	}
	q := Pick_Path {
		area  = area,
		kind  = kind,
		start = clone_string(start, r.allocator),
		name  = clone_string(name, r.allocator),
	}
	if len(filters) > 0 {
		q.filters = make([]Pick_Filter, len(filters), r.allocator)
		for f, i in filters {
			q.filters[i] = {
				clone_string(f.label, r.allocator),
				clone_string(f.patterns, r.allocator),
			}
		}
	}
	append(&r.requests, q)
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
// A loop with no host (ui/shell's own, a probe) keeps nothing.
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
// focus stays inside it while it is the newest trap; with rove, it is one
// Tab stop whose members the arrow keys of that axis walk, off one end
// onto the other with wrap. Open and close it inside one widget or
// layer, round all of that widget's content: opened between the children
// of a row or column it does not hold them, since the container places
// its children later, outside the pair.
focus_scope_open :: proc(gtx: ^Ctx, id: ops.Area_Id, trap := false, rove := ops.Rove.None, wrap := false) {
	ops.focus_scope(gtx.scene, id, trap, rove, wrap)
}

// focus_scope_close closes the innermost focus scope. entry is the
// member Tab enters a roving scope at: the selected tab, the checked
// radio; 0 enters at the member that last held focus, else the first.
focus_scope_close :: proc(gtx: ^Ctx, entry: ops.Area_Id = 0) {
	ops.focus_scope_end(gtx.scene, entry)
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
	case Text_Input:
	case Pick_Path:
		delete(v.start, r.allocator)
		delete(v.name, r.allocator)
		for f in v.filters {
			delete(f.label, r.allocator)
			delete(f.patterns, r.allocator)
		}
		delete(v.filters, r.allocator)
	}
}
