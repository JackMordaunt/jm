package main

import "core:strings"

// Word is an identifier or keyword in a statement: a bare word, or the
// inside of a "quoted", [bracketed] or `backticked` name.
Word :: struct {
	text:   string,
	quoted: bool,
}

// scan reads sql as SQLite's tokenizer would, far enough to find its words:
// string literals, comments and numbers are skipped, so a keyword inside a
// literal is not a word. more reports anything after a top-level semicolon,
// which is a second statement.
scan :: proc(sql: string, allocator := context.allocator) -> (words: []Word, more: bool) {
	out := make([dynamic]Word, allocator)
	ended := false
	i := 0
	for i < len(sql) {
		c := sql[i]
		start := i
		switch {
		case c == ' ' || c == '\t' || c == '\n' || c == '\r' || c == '\f':
			i += 1
			continue
		case c == '-' && i + 1 < len(sql) && sql[i + 1] == '-':
			i = skip_to(sql, i + 2, "\n")
			continue
		case c == '/' && i + 1 < len(sql) && sql[i + 1] == '*':
			i = skip_to(sql, i + 2, "*/")
			continue
		case c == ';':
			ended = true
			i += 1
			continue
		case c == '\'':
			i = skip_quoted(sql, i, '\'')
		case c == '"' || c == '`':
			i = skip_quoted(sql, i, c)
			append(&out, Word{text = sql[start + 1:max(start + 1, i - 1)], quoted = true})
		case c == '[':
			i = skip_to(sql, i + 1, "]")
			append(&out, Word{text = sql[start + 1:max(start + 1, i - 1)], quoted = true})
		case is_word_byte(c) && !(c >= '0' && c <= '9'):
			for i < len(sql) && is_word_byte(sql[i]) {
				i += 1
			}
			append(&out, Word{text = sql[start:i]})
		case c >= '0' && c <= '9':
			for i < len(sql) && (is_word_byte(sql[i]) || sql[i] == '.') {
				i += 1
			}
		case:
			i += 1
		}
		if ended {
			more = true
		}
	}
	return out[:], more
}

// is_compound reports whether words hold a compound operator. SQLite types
// a compound SELECT's columns from its leftmost arm alone.
is_compound :: proc(words: []Word) -> bool {
	for w in words {
		if w.quoted {
			continue
		}
		if strings.equal_fold(w.text, "union") ||
		   strings.equal_fold(w.text, "intersect") ||
		   strings.equal_fold(w.text, "except") {
			return true
		}
	}
	return false
}

// mentions reports whether words name name, quoted or not, as SQLite's
// case-insensitive identifiers would.
mentions :: proc(words: []Word, name: string) -> bool {
	for w in words {
		if strings.equal_fold(w.text, name) {
			return true
		}
	}
	return false
}

@(private = "file")
is_word_byte :: proc(c: u8) -> bool {
	return(
		c == '_' ||
		c == '$' ||
		c >= 0x80 ||
		(c >= 'a' && c <= 'z') ||
		(c >= 'A' && c <= 'Z') ||
		(c >= '0' && c <= '9') \
	)
}

// skip_quoted returns the index past the literal opening at i, where a
// doubled quote stands for one.
@(private = "file")
skip_quoted :: proc(sql: string, i: int, quote: u8) -> int {
	j := i + 1
	for j < len(sql) {
		if sql[j] == quote {
			if j + 1 < len(sql) && sql[j + 1] == quote {
				j += 2
				continue
			}
			return j + 1
		}
		j += 1
	}
	return len(sql)
}

@(private = "file")
skip_to :: proc(sql: string, from: int, end: string) -> int {
	k := strings.index(sql[from:], end)
	if k < 0 {
		return len(sql)
	}
	return from + k + len(end)
}
