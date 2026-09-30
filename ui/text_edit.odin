package ui

// Single-line text editing: the buffer and cursor a text input keeps,
// and the key and pointer edits any text input applies to it. The
// widgets that draw one live in the design systems (ui/material).

import "core:unicode/utf8"

// Text_State is a single-line text buffer and its cursor, a byte offset
// that always sits on a rune boundary. The caller owns it; text_destroy
// frees the buffer.
Text_State :: struct {
	buf:    [dynamic]u8,
	cursor: int,
}

// text_string views the buffer as a string; valid until the next edit.
text_string :: proc(s: ^Text_State) -> string {
	return string(s.buf[:])
}

// text_set replaces the buffer with str and puts the cursor at its end.
text_set :: proc(s: ^Text_State, str: string) {
	clear(&s.buf)
	append(&s.buf, str)
	s.cursor = len(s.buf)
}

// text_destroy frees the buffer.
text_destroy :: proc(s: ^Text_State) {
	delete(s.buf)
	s^ = {}
}

// text_key applies an editing key to s; true when the text changed.
// Exported for text inputs built outside this package.
text_key :: proc(s: ^Text_State, k: Key) -> bool {
	#partial switch k {
	case .Backspace:
		if s.cursor > 0 {
			_, n := utf8.decode_last_rune(s.buf[:s.cursor])
			remove_range(&s.buf, s.cursor - n, s.cursor)
			s.cursor -= n
			return true
		}
	case .Delete:
		if s.cursor < len(s.buf) {
			_, n := utf8.decode_rune(s.buf[s.cursor:])
			remove_range(&s.buf, s.cursor, s.cursor + n)
			return true
		}
	case .Left:
		if s.cursor > 0 {
			_, n := utf8.decode_last_rune(s.buf[:s.cursor])
			s.cursor -= n
		}
	case .Right:
		if s.cursor < len(s.buf) {
			_, n := utf8.decode_rune(s.buf[s.cursor:])
			s.cursor += n
		}
	case .Home:
		s.cursor = 0
	case .End:
		s.cursor = len(s.buf)
	}
	return false
}

// text_hit returns the rune boundary nearest x (in text space), from one
// shape of the whole line (see caret_at).
text_hit :: proc(gtx: ^Ctx, s: ^Text_State, size: f32, x: f32) -> int {
	str := string(s.buf[:])
	return caret_at(shape(gtx.shaper, gtx.font, size, str, gtx.allocator), str, x)
}
