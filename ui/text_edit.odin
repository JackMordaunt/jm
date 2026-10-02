package ui

// Text editing: the buffer, caret and selection a text input keeps, and
// the key, text and paste edits any text input applies to it. The widgets
// that draw one live in the design systems (ui/material, ui/fluent).

import "core:unicode/utf8"
import "jm:ui/ops"

// Text_State is a text buffer, its caret and its selection. cursor is the
// caret, anchor the other end of the selection: equal when nothing is
// selected. Both are byte offsets on caret stops. The caller owns it;
// text_destroy frees the buffer.
Text_State :: struct {
	buf:    [dynamic]u8,
	cursor: int,
	anchor: int,
	drag:   Text_Drag, // the pointer gesture in progress, see text_follow_pointer
}

// Text_Drag is a press-and-drag on text: what unit a double or triple
// click selects by, and the span the press first selected, which the drag
// keeps selected as it extends either way.
Text_Drag :: struct {
	active: bool,
	unit:   enum u8 {
		Grapheme,
		Word,
		Line,
	},
	lo, hi: int,
}

// text_string views the buffer as a string; valid until the next edit.
text_string :: proc(s: ^Text_State) -> string {
	return string(s.buf[:])
}

// text_set replaces the buffer with str and puts the caret at its end,
// selecting nothing.
text_set :: proc(s: ^Text_State, str: string) {
	clear(&s.buf)
	append(&s.buf, str)
	s.cursor = len(s.buf)
	s.anchor = s.cursor
}

// text_destroy frees the buffer.
text_destroy :: proc(s: ^Text_State) {
	delete(s.buf)
	s^ = {}
}

// text_selection is the selected byte range, lo <= hi; empty when the
// caret is all there is.
text_selection :: proc(s: ^Text_State) -> (lo, hi: int) {
	return min(s.cursor, s.anchor), max(s.cursor, s.anchor)
}

// text_selected is the selected text; valid until the next edit.
text_selected :: proc(s: ^Text_State) -> string {
	lo, hi := text_selection(s)
	return string(s.buf[lo:hi])
}

// text_move puts the caret at i, extending the selection from its anchor
// when extend is set and dropping it otherwise.
text_move :: proc(s: ^Text_State, i: int, extend := false) {
	s.cursor = clamp(i, 0, len(s.buf))
	if !extend {
		s.anchor = s.cursor
	}
}

// text_select selects bytes lo to hi, the caret at hi.
text_select :: proc(s: ^Text_State, lo, hi: int) {
	s.anchor = clamp(lo, 0, len(s.buf))
	s.cursor = clamp(hi, 0, len(s.buf))
}

// text_clamp brings caret and anchor back inside the buffer, after the
// caller edited buf directly.
text_clamp :: proc(s: ^Text_State) {
	s.cursor = clamp(s.cursor, 0, len(s.buf))
	s.anchor = clamp(s.anchor, 0, len(s.buf))
}

// text_replace puts text in place of the selection (at the caret when
// nothing is selected) and leaves the caret after it.
text_replace :: proc(s: ^Text_State, text: string) {
	lo, hi := text_selection(s)
	remove_range(&s.buf, lo, hi)
	inject_at_elems(&s.buf, lo, ..transmute([]u8)text)
	s.cursor = lo + len(text)
	s.anchor = s.cursor
}

// Text_Stops are where a caret may stop in a text and where its words
// change, ascending. graphemes starts after 0 and ends at the text's
// length; words starts at 0 and ends at the length, and each span between
// two is a word or a run of spaces or punctuation (kb_text_shape's
// KBTS_BREAK_FLAG_WORD, its Unicode word segmentation).
Text_Stops :: struct {
	graphemes: []int,
	words:     []int,
}

// text_stops shapes s in font at size and returns its stops for
// text_edit, into the frame allocator. Take them afresh for each event:
// an edit moves every stop after it.
text_stops :: proc(gtx: ^Ctx, s: ^Text_State, font: ops.Font_Id, size: f32) -> Text_Stops {
	str := string(s.buf[:])
	st := shape_text(gtx.shaper, font, size, str, gtx.allocator)
	g := make([dynamic]int, 0, len(st.breaks) + 1, gtx.allocator)
	w := make([dynamic]int, 0, 8, gtx.allocator)
	append(&w, 0)
	for b in st.breaks {
		if b.at == 0 {
			continue
		}
		if .Grapheme in b.kinds {
			append(&g, b.at)
		}
		if .Word in b.kinds {
			append(&w, b.at)
		}
	}
	append(&g, len(str))
	if w[len(w) - 1] != len(str) {
		append(&w, len(str))
	}
	return {g[:], w[:]}
}

// text_edit applies e to s and reports whether the text changed. It
// takes Text and Paste (replacing the selection), and editing keys with
// the platform's modifiers (SHORTCUT, WORD_MOD, Shift):
//
//	Left, Right             a grapheme; with a selection, collapse to its side
//	WORD_MOD+Left, Right    a word (to its start; Right to the next word's
//	                        end on macOS, start elsewhere, as each OS does)
//	Home, End               the text's ends; SHORTCUT+Left, Right on macOS too
//	Shift+any move          extends the selection instead
//	Backspace, Delete       the selection, else a grapheme; WORD_MOD for a word
//	SHORTCUT+A              select all
//	SHORTCUT+C, X           copy, cut (clipboard_write)
//	SHORTCUT+V              paste: asks for the clipboard for area id, whose
//	                        Paste event a later frame passes back here
//
// A read-only s takes the moves, select all and copy, and nothing that
// would change it. Keys it does not know (Enter, Up, Down, Escape) are
// left to the widget, which handles them before or instead of calling
// this. Stops come from text_stops; without them every rune is a stop and
// words are not known, so word moves go by grapheme.
//
// The macOS rows follow Apple's "Mac keyboard shortcuts" (Option-Right:
// end of the next word; Command-Left/Right: start or end of the line);
// elsewhere Ctrl+Right goes to the start of the next word, as Windows and
// GTK text fields do.
text_edit :: proc(gtx: ^Ctx, s: ^Text_State, id: ops.Area_Id, e: Event, stops: Text_Stops, read_only := false) -> bool {
	text_clamp(s)
	#partial switch e.kind {
	case .Text:
		if read_only {
			return false
		}
		text_replace(s, e.text)
		return true
	case .Paste:
		if read_only || e.mime != TEXT_MIME {
			return false
		}
		text_replace(s, e.text)
		return true
	case .Key:
		return edit_key(gtx, s, id, e.key, e.mods, stops, read_only)
	}
	return false
}

@(private = "file")
edit_key :: proc(gtx: ^Ctx, s: ^Text_State, id: ops.Area_Id, k: Key, mods: Mods, stops: Text_Stops, read_only: bool) -> bool {
	extend := .Shift in mods
	chord := mods - {.Shift}
	lo, hi := text_selection(s)
	if chord == {SHORTCUT} {
		#partial switch k {
		case .A:
			text_select(s, 0, len(s.buf))
			return false
		case .C:
			if lo < hi {
				clipboard_write(gtx, string(s.buf[lo:hi]))
			}
			return false
		case .X:
			if lo < hi && !read_only {
				clipboard_write(gtx, string(s.buf[lo:hi]))
				text_replace(s, "")
				return true
			}
			return false
		case .V:
			if !read_only {
				clipboard_read(gtx, id)
			}
			return false
		}
		when ODIN_OS == .Darwin {
			// Cmd+arrows go to the ends of the line; this is one line.
			#partial switch k {
			case .Left, .Up:
				text_move(s, 0, extend)
				return false
			case .Right, .Down:
				text_move(s, len(s.buf), extend)
				return false
			case .Backspace:
				if read_only {
					return false
				}
				text_select(s, 0, hi)
				text_replace(s, "")
				return true
			}
		}
	}
	by_word := chord == {WORD_MOD} && len(stops.words) > 0
	#partial switch k {
	case .Left:
		switch {
		case by_word:
			text_move(s, word_before(s, stops.words), extend)
		case lo < hi && !extend:
			text_move(s, lo)
		case:
			text_move(s, stop_before(s, stops.graphemes), extend)
		}
	case .Right:
		switch {
		case by_word:
			text_move(s, word_after(s, stops.words), extend)
		case lo < hi && !extend:
			text_move(s, hi)
		case:
			text_move(s, stop_after(s, stops.graphemes), extend)
		}
	case .Home:
		text_move(s, 0, extend)
	case .End:
		text_move(s, len(s.buf), extend)
	case .Backspace:
		if read_only {
			return false
		}
		if lo == hi {
			text_select(s, word_before(s, stops.words) if by_word else stop_before(s, stops.graphemes), s.cursor)
		}
		if text_selection_empty(s) {
			return false
		}
		text_replace(s, "")
		return true
	case .Delete:
		if read_only {
			return false
		}
		if lo == hi {
			text_select(s, s.cursor, word_after(s, stops.words) if by_word else stop_after(s, stops.graphemes))
		}
		if text_selection_empty(s) {
			return false
		}
		text_replace(s, "")
		return true
	}
	return false
}

// text_edit_lines is text_edit for a multi-line field whose text is laid
// out as p: Enter inserts a newline, Up and Down move the caret to the
// line above or below at the same x (staying put on the first or last
// line), and Home and End go to the ends of the caret's line rather than
// the text's, each extending the selection with Shift as text_edit's
// moves do. Every other event is text_edit's. p must be s's text as it is
// before e; lay it out again after a change.
text_edit_lines :: proc(gtx: ^Ctx, s: ^Text_State, id: ops.Area_Id, e: Event, stops: Text_Stops, p: Paragraph, read_only := false) -> bool {
	if e.kind != .Key || len(p.lines) == 0 {
		return text_edit(gtx, s, id, e, stops, read_only)
	}
	text_clamp(s)
	extend := .Shift in e.mods
	#partial switch e.key {
	case .Enter:
		if read_only {
			return false
		}
		text_replace(s, "\n")
		return true
	case .Up, .Down:
		line, x := paragraph_caret(p, s.cursor)
		to := line + (e.key == .Up ? -1 : 1)
		if to >= 0 && to < len(p.lines) {
			text_move(s, paragraph_hit(p, {x, (f32(to) + 0.5) * p.pitch}), extend)
		}
		return false
	case .Home:
		text_move(s, p.lines[paragraph_line_of(p, s.cursor)].start, extend)
		return false
	case .End:
		text_move(s, paragraph_line_end(p, paragraph_line_of(p, s.cursor)), extend)
		return false
	}
	return text_edit(gtx, s, id, e, stops, read_only)
}

// text_scroll is the offset to scroll a view of length view by, along
// one axis, so a caret spanning at to at + extent shows: scroll as it
// was if the caret already shows, else moved just far enough, and never
// past either end of content. A single-line field passes its text's
// width and the caret's x; a multi-line one its text's height and the
// caret line's top.
text_scroll :: proc(scroll, content, at, extent, view: f32) -> f32 {
	s := clamp(scroll, at + extent - view, at)
	return clamp(s, 0, max(content - view, 0))
}

@(private = "file")
text_selection_empty :: proc(s: ^Text_State) -> bool {
	return s.cursor == s.anchor
}

// stop_before is the caret stop before s's cursor, 0 at the start; every
// rune is a stop when graphemes is nil.
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

// word_is is whether the span of words starting at words[i] is a word,
// not spaces or punctuation.
@(private = "file")
word_is :: proc(s: ^Text_State, words: []int, i: int) -> bool {
	if i + 1 >= len(words) || words[i] >= len(s.buf) {
		return false
	}
	r, _ := utf8.decode_rune(s.buf[words[i]:])
	return is_word_rune(r)
}

// word_before is the start of the word the caret is in or after: where
// every OS's word-left lands. 0 when no word precedes it.
@(private = "file")
word_before :: proc(s: ^Text_State, words: []int) -> int {
	#reverse for w, i in words {
		if w < s.cursor && word_is(s, words, i) {
			return w
		}
	}
	return 0
}

// word_after is where word-right lands: the end of the next word on
// macOS, the start of the word after it elsewhere; the end of the text
// when there is none.
@(private = "file")
word_after :: proc(s: ^Text_State, words: []int) -> int {
	for w, i in words {
		if w <= s.cursor {
			continue
		}
		when ODIN_OS == .Darwin {
			if i > 0 && word_is(s, words, i - 1) {
				return w
			}
		} else {
			if word_is(s, words, i) {
				return w
			}
		}
	}
	return len(s.buf)
}

// text_word_at is the word span of words holding byte offset i (a run of
// spaces or punctuation is a span too), for a double-click.
text_word_at :: proc(words: []int, i: int) -> (lo, hi: int) {
	for k in 0 ..< len(words) - 1 {
		if words[k] <= i && i < words[k + 1] {
			return words[k], words[k + 1]
		}
	}
	if len(words) >= 2 {
		return words[len(words) - 2], words[len(words) - 1]
	}
	return i, i
}

// text_follow_pointer applies a pointer event on s laid out as p, at pt in p's
// space (the widget maps its own coordinates, scroll included):
//
//	Press         the caret to the nearest stop; Shift extends the selection
//	double press  the word there (text_word_at), a run of spaces being one
//	triple press  the line: the paragraph between newlines in a textarea
//	Move          while pressed, extends the selection from the press, by
//	              the unit it selected: a drag after a double click grows
//	              whole words
//	Release       ends the drag
//
// Only the left button selects. Stops come from text_stops.
text_follow_pointer :: proc(s: ^Text_State, p: Paragraph, e: Event, pt: ops.Point, stops: Text_Stops) {
	text_clamp(s)
	#partial switch e.kind {
	case .Press:
		if e.button != .Left {
			return
		}
		i := paragraph_hit(p, pt)
		switch {
		case e.clicks >= 3:
			lo, hi := line_at(s, i)
			text_select(s, lo, hi)
			s.drag = {true, .Line, lo, hi}
		case e.clicks == 2:
			lo, hi := text_word_at(stops.words, i)
			text_select(s, lo, hi)
			s.drag = {true, .Word, lo, hi}
		case:
			text_move(s, i, .Shift in e.mods)
			s.drag = {true, .Grapheme, s.anchor, s.anchor}
		}
	case .Move:
		if !s.drag.active {
			return
		}
		i := paragraph_hit(p, pt)
		lo, hi := i, i
		switch s.drag.unit {
		case .Grapheme:
		case .Word:
			lo, hi = text_word_at(stops.words, i)
		case .Line:
			lo, hi = line_at(s, i)
		}
		// Keep what the press selected, and grow toward the pointer.
		if lo < s.drag.lo {
			text_select(s, s.drag.hi, lo)
		} else {
			text_select(s, s.drag.lo, max(hi, s.drag.hi))
		}
	case .Release:
		s.drag.active = false
	}
}

// line_at is the span between the newlines around byte offset i.
@(private = "file")
line_at :: proc(s: ^Text_State, i: int) -> (lo, hi: int) {
	lo, hi = i, i
	for lo > 0 && s.buf[lo - 1] != '\n' {
		lo -= 1
	}
	for hi < len(s.buf) && s.buf[hi] != '\n' {
		hi += 1
	}
	return
}
