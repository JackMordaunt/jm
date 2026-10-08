package ui

import "jm:ui/ops"

// Undo and redo for a text field: every edit text_replace and text_edit
// make is kept in the field's Text_State, so it outlives the field
// leaving the frame. A run of typing is one edit, as is a run of
// Backspace or of Delete, until the caret moves, the kind of edit
// changes, or TEXT_PAUSE passes; a paste, a cut or a replaced selection
// is an edit of its own. A secret field keeps none, so an old password
// is not held, and text_set clears it: what the program puts in a field
// is not the user's to undo.
//
// While the field has an edit to undo, text_claim_keys claims the undo
// shortcut, so an app's own undo (a key_interest of its own) gets the key
// only once the field's history has run out: the field's undo, then the
// app's.

// Text_History is a field's edits, oldest first: those before done are
// undone by text_undo, those from done on were undone and are done again
// by text_redo. Each edit's removed and inserted bytes sit in bytes, in
// the edits' order. length is the buffer's length after the last edit
// applied, to notice the buffer changed around the history.
Text_History :: struct {
	edits:  [dynamic]Text_Step,
	done:   int,
	bytes:  [dynamic]u8,
	open:   bool, // the last edit still takes a run of typing or deleting
	length: int,
}

// Text_Step is one edit: at the byte at, bytes[lo:mid] were removed and
// bytes[mid:hi] inserted; the caret and anchor before and after it; its
// kind; and when it was last added to.
Text_Step :: struct {
	at:      int,
	lo, mid: int,
	hi:      int,
	before:  [2]int,
	after:   [2]int,
	kind:    Text_Step_Kind,
	time:    f64,
}

// Text_Step_Kind is what made an edit: a run of these joins into one.
Text_Step_Kind :: enum u8 {
	Other,
	Typing,
	Backspace,
	Delete,
}

// TEXT_HISTORY_EDITS and TEXT_HISTORY_BYTES bound a field's history: the
// oldest edits go first, the newest always stays.
TEXT_HISTORY_EDITS :: 100
TEXT_HISTORY_BYTES :: 64 * 1024

// TEXT_PAUSE is the seconds of quiet that end a run of typing.
TEXT_PAUSE :: 1.0

// text_can_undo reports whether s has an edit to undo.
text_can_undo :: proc(s: ^Text_State) -> bool {
	return s.history.done > 0 && s.history.length == len(s.buf)
}

// text_can_redo reports whether s has an undone edit to do again.
text_can_redo :: proc(s: ^Text_State) -> bool {
	return s.history.done < len(s.history.edits) && s.history.length == len(s.buf)
}

// text_undo takes back s's last edit, restoring its text and the
// selection before it, and reports whether there was one. A buffer
// changed around the history (edited directly) drops the history.
text_undo :: proc(s: ^Text_State) -> bool {
	h := &s.history
	if !history_holds(s) || h.done == 0 {
		return false
	}
	e := h.edits[h.done - 1]
	if !history_swap(s, e.at, h.bytes[e.mid:e.hi], h.bytes[e.lo:e.mid]) {
		return false
	}
	s.cursor, s.anchor = e.before[0], e.before[1]
	h.done -= 1
	h.open = false
	return true
}

// text_redo does s's last undone edit again, leaving the selection as it
// left it, and reports whether there was one.
text_redo :: proc(s: ^Text_State) -> bool {
	h := &s.history
	if !history_holds(s) || h.done == len(h.edits) {
		return false
	}
	e := h.edits[h.done]
	if !history_swap(s, e.at, h.bytes[e.lo:e.mid], h.bytes[e.mid:e.hi]) {
		return false
	}
	s.cursor, s.anchor = e.after[0], e.after[1]
	h.done += 1
	h.open = false
	return true
}

// text_claim_keys claims, for the field's area id, the shortcuts it
// would act on now: undo while it has an edit to undo, redo while it has
// one to redo. Call it every frame the field is drawn; a shortcut it
// does not claim goes on to the app's own key_interest.
text_claim_keys :: proc(gtx: ^Ctx, s: ^Text_State, id: ops.Area_Id) {
	if text_can_undo(s) {
		key_interest(gtx, id, .Z, {SHORTCUT}, claim = true)
	}
	if text_can_redo(s) {
		key_interest(gtx, id, .Z, {SHORTCUT, .Shift}, claim = true)
		when ODIN_OS != .Darwin {
			key_interest(gtx, id, .Y, {SHORTCUT}, claim = true)
		}
	}
}

// history_clear drops every edit, keeping the memory.
@(private)
history_clear :: proc(s: ^Text_State) {
	h := &s.history
	clear(&h.edits)
	clear(&h.bytes)
	h.done, h.open, h.length = 0, false, len(s.buf)
}

@(private)
history_destroy :: proc(h: ^Text_History) {
	delete(h.edits)
	delete(h.bytes)
	h^ = {}
}

// history_holds reports whether s's history still describes its buffer,
// dropping it when it does not.
@(private = "file")
history_holds :: proc(s: ^Text_State) -> bool {
	if s.history.length != len(s.buf) {
		history_clear(s)
		return false
	}
	return true
}

// history_swap puts to in place of from at byte at, when from is there,
// and reports whether it was; when it is not, the history is dropped.
@(private = "file")
history_swap :: proc(s: ^Text_State, at: int, from, to: []u8) -> bool {
	if at + len(from) > len(s.buf) || string(s.buf[at:at + len(from)]) != string(from) {
		history_clear(s)
		return false
	}
	remove_range(&s.buf, at, at + len(from))
	inject_at_elems(&s.buf, at, ..to)
	s.history.length = len(s.buf)
	return true
}

// history_record keeps the edit about to put text in place of bytes lo to
// hi of s, made by kind at time now: added to the last edit when it
// continues a run, else an edit of its own, dropping what was undone.
@(private)
history_record :: proc(s: ^Text_State, lo, hi: int, text: string, kind: Text_Step_Kind, now: f64) {
	h := &s.history
	if h.length != len(s.buf) {
		history_clear(s)
	}
	if h.done < len(h.edits) {
		resize(&h.edits, h.done)
		resize(&h.bytes, h.edits[h.done - 1].hi if h.done > 0 else 0)
		h.open = false
	}
	if h.open && h.done > 0 && history_join(s, &h.edits[h.done - 1], lo, hi, text, kind, now) {
		return
	}
	before := [2]int{s.cursor, s.anchor}
	switch kind {
	case .Backspace:
		before = {hi, hi}
	case .Delete:
		before = {lo, lo}
	case .Other, .Typing:
	}
	start := len(h.bytes)
	append(&h.bytes, ..s.buf[lo:hi])
	append(&h.bytes, text)
	end := lo + len(text)
	append(
		&h.edits,
		Text_Step {
			at = lo,
			lo = start,
			mid = start + hi - lo,
			hi = len(h.bytes),
			before = before,
			after = {end, end},
			kind = kind,
			time = now,
		},
	)
	h.done = len(h.edits)
	h.open = kind != .Other
	history_trim(h)
}

// history_join adds the edit to e when it continues e's run: the same
// kind, soon enough, at the caret e left, and reports whether it did. e
// is the last edit, so its bytes end the block and can grow in place.
@(private = "file")
history_join :: proc(
	s: ^Text_State,
	e: ^Text_Step,
	lo, hi: int,
	text: string,
	kind: Text_Step_Kind,
	now: f64,
) -> bool {
	if kind != e.kind || now - e.time >= TEXT_PAUSE {
		return false
	}
	h := &s.history
	switch kind {
	case .Typing:
		if lo != hi || e.after != ([2]int{lo, lo}) {
			return false
		}
		append(&h.bytes, text)
		e.hi = len(h.bytes)
		e.after = {lo + len(text), lo + len(text)}
	case .Backspace:
		if text != "" || hi != e.at || e.after != ([2]int{e.at, e.at}) {
			return false
		}
		inject_at_elems(&h.bytes, e.lo, ..s.buf[lo:hi])
		e.mid += hi - lo
		e.hi += hi - lo
		e.at = lo
		e.after = {lo, lo}
	case .Delete:
		if text != "" || lo != e.at || e.after != ([2]int{e.at, e.at}) {
			return false
		}
		inject_at_elems(&h.bytes, e.mid, ..s.buf[lo:hi])
		e.mid += hi - lo
		e.hi += hi - lo
	case .Other:
		return false
	}
	e.time = now
	return true
}

// history_trim drops the oldest edits while h holds more than its bounds
// allow, never the newest.
@(private = "file")
history_trim :: proc(h: ^Text_History) {
	for len(h.edits) > 1 &&
	    (len(h.edits) > TEXT_HISTORY_EDITS || len(h.bytes) > TEXT_HISTORY_BYTES) {
		n := h.edits[0].hi
		remove_range(&h.bytes, 0, n)
		ordered_remove(&h.edits, 0)
		for &e in h.edits {
			e.lo -= n
			e.mid -= n
			e.hi -= n
		}
		h.done -= 1
	}
}
