package ui

import "core:mem"
import "core:unicode/utf8"

// A secret field, a password's, edits its real text but shows a bullet for
// each character, never lets the text be copied or cut, and tells a
// screen reader only that it holds that many characters. The editing is
// text_edit's on the real Text_State with secret set; the showing goes
// through a view, a Text_State of bullets whose caret and selection mirror
// the real one's, so a widget lays out, hit-tests and paints the view
// exactly as it would plain text and maps what the pointer did back.

// SECRET_BULLET is what a secret field shows for each character: U+25CF,
// BLACK CIRCLE: U+2022 BULLET, in SF Pro at Primer's 14px, drew as dots
// too small and close to count (an Ergon sign-in render, 2026-10-06).
SECRET_BULLET :: "●"

// secret_view is s as it shows: a bullet per rune of s, with its caret,
// anchor and drag at the same character, in allocator.
secret_view :: proc(s: ^Text_State, allocator: mem.Allocator) -> Text_State {
	text_clamp(s)
	n := utf8.rune_count(s.buf[:])
	v := Text_State {
		buf = make([dynamic]u8, 0, n * len(SECRET_BULLET), allocator),
	}
	for _ in 0 ..< n {
		append(&v.buf, SECRET_BULLET)
	}
	v.cursor = secret_shown(s, s.cursor)
	v.anchor = secret_shown(s, s.anchor)
	v.drag = s.drag
	v.drag.lo = secret_shown(s, s.drag.lo)
	v.drag.hi = secret_shown(s, s.drag.hi)
	return v
}

// secret_apply moves s's caret, anchor and drag to where v's are: what a
// pointer did to the view, done to the text.
secret_apply :: proc(s: ^Text_State, v: ^Text_State) {
	s.cursor = secret_real(s, v.cursor)
	s.anchor = secret_real(s, v.anchor)
	s.drag = v.drag
	s.drag.lo = secret_real(s, v.drag.lo)
	s.drag.hi = secret_real(s, v.drag.hi)
}

// secret_stops are a secret field's caret stops: every rune, and no word
// but the whole, so a word move cannot tell where the text has spaces.
secret_stops :: proc(gtx: ^Ctx, s: ^Text_State) -> Text_Stops {
	g := make([dynamic]int, 0, len(s.buf), gtx.allocator)
	for i in 1 ..= len(s.buf) {
		if i == len(s.buf) || utf8.rune_start(s.buf[i]) {
			append(&g, i)
		}
	}
	w := make([]int, 2, gtx.allocator)
	w[1] = len(s.buf)
	return {g[:], w}
}

// secret_shown is byte offset i of s's text as the view's offset.
@(private)
secret_shown :: proc(s: ^Text_State, i: int) -> int {
	return utf8.rune_count(s.buf[:clamp(i, 0, len(s.buf))]) * len(SECRET_BULLET)
}

// secret_real is the view's byte offset i as s's text's, at the start of
// the rune whose bullet i falls in.
@(private)
secret_real :: proc(s: ^Text_State, i: int) -> int {
	want := max(i, 0) / len(SECRET_BULLET)
	at, n := 0, 0
	for at < len(s.buf) && n < want {
		_, size := utf8.decode_rune(s.buf[at:])
		at += size
		n += 1
	}
	return at
}
