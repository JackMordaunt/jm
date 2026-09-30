package ui

// Single-line text editing: the buffer and cursor a text input keeps,
// and the key and pointer edits any text input applies to it. The
// widgets that draw one live in the design systems (ui/material).

import "core:unicode/utf8"
import "jm:ui/ops"

// Text_State is a text buffer and its cursor, a byte offset that always
// sits on a caret stop (a grapheme boundary, given text_key's graphemes). The caller owns it; text_destroy
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
//
// graphemes are s's caret stops, ascending and ending at len(s.buf), as
// text_graphemes gives them: arrows move a grapheme at a time and Delete
// and Backspace remove one, so a base and its combining marks go as a unit
// (test_text_key_moves_by_grapheme). Without them every rune is a stop.
// Movement is logical: Right goes toward the end of the text whichever
// way a run of it reads.
text_key :: proc(s: ^Text_State, k: Key, graphemes: []int = nil) -> bool {
	#partial switch k {
	case .Backspace:
		if s.cursor > 0 {
			at := stop_before(s, graphemes)
			remove_range(&s.buf, at, s.cursor)
			s.cursor = at
			return true
		}
	case .Delete:
		if s.cursor < len(s.buf) {
			remove_range(&s.buf, s.cursor, stop_after(s, graphemes))
			return true
		}
	case .Left:
		s.cursor = stop_before(s, graphemes)
	case .Right:
		s.cursor = stop_after(s, graphemes)
	case .Home:
		s.cursor = 0
	case .End:
		s.cursor = len(s.buf)
	}
	return false
}

// text_graphemes shapes s in font at size and returns its caret stops for
// text_key, into the frame allocator. Call it for each key: an edit moves
// every stop after it.
text_graphemes :: proc(gtx: ^Ctx, s: ^Text_State, font: ops.Font_Id, size: f32) -> []int {
	str := string(s.buf[:])
	st := shape_text(gtx.shaper, font, size, str, gtx.allocator)
	out := make([dynamic]int, 0, len(st.breaks) + 1, gtx.allocator)
	for b in st.breaks {
		if .Grapheme in b.kinds && b.at > 0 {
			append(&out, b.at)
		}
	}
	append(&out, len(str))
	return out[:]
}

// stop_before is the caret stop before s's cursor, 0 at the start.
@(private = "file")
stop_before :: proc(s: ^Text_State, graphemes: []int) -> int {
	if graphemes == nil {
		if s.cursor == 0 {
			return 0
		}
		_, n := utf8.decode_last_rune(s.buf[:s.cursor])
		return s.cursor - n
	}
	at := 0
	for g in graphemes {
		if g >= s.cursor {
			break
		}
		at = g
	}
	return at
}

// stop_after is the caret stop after s's cursor, the end at the end.
@(private = "file")
stop_after :: proc(s: ^Text_State, graphemes: []int) -> int {
	if graphemes == nil {
		if s.cursor >= len(s.buf) {
			return len(s.buf)
		}
		_, n := utf8.decode_rune(s.buf[s.cursor:])
		return s.cursor + n
	}
	for g in graphemes {
		if g > s.cursor {
			return min(g, len(s.buf))
		}
	}
	return len(s.buf)
}
