package fuzz

import "core:fmt"
import "core:unicode/utf8"

/*
Damage takes input a parser accepts and breaks it: a byte changed, a file
cut short, trailing rubbish, two records spliced together, or bytes that were
never an input at all. A parser that is going to read past its input, or
trust a length it was handed, tends to do it on one of these.

The corpus is the caller's: well-formed inputs for whatever is being fuzzed.
Damage knows nothing about the format, which is why the same four kinds work
on a SQL statement and a tar archive.
*/

// Damage is one way a well-formed input gets broken.
Damage :: enum {
	// Left as it was. A parser must still accept its own corpus.
	None,
	// One byte somewhere is a different byte.
	Flip,
	// Cut off at a random point, as a truncated download is.
	Truncate,
	// Valid, then rubbish after the end.
	Append,
	// The front of one corpus entry and the back of another.
	Splice,
	// No corpus at all: bytes that were never a valid input.
	Noise,
}

// damage draws one corpus entry and one way of breaking it, and returns the
// result with the kind that was chosen, so a failure can say which it was. A
// zero source gives the corpus entry back unharmed.
damage :: proc(
	s: ^Source,
	corpus: [][]byte,
	allocator := context.allocator,
) -> (
	out: []byte,
	how: Damage,
) {
	how = Damage(integer_in(s, 0, len(Damage)))
	if len(corpus) == 0 {
		how = .Noise
	}
	switch how {
	case .None:
		return clone_bytes(choice(s, corpus), allocator), how
	case .Flip:
		src := choice(s, corpus)
		if len(src) == 0 {
			return clone_bytes(src, allocator), .None
		}
		b := clone_bytes(src, allocator)
		b[integer_in(s, 0, len(b))] = byte_of(s)
		return b, how
	case .Truncate:
		src := choice(s, corpus)
		return clone_bytes(src[:integer_in(s, 0, len(src) + 1)], allocator), how
	case .Append:
		src := choice(s, corpus)
		tail := bytes(s, 32, allocator)
		b := make([]byte, len(src) + len(tail), allocator)
		copy(b, src)
		copy(b[len(src):], tail)
		return b, how
	case .Splice:
		a := choice(s, corpus)
		c := choice(s, corpus)
		at := integer_in(s, 0, len(a) + 1)
		from := integer_in(s, 0, len(c) + 1)
		b := make([]byte, at + (len(c) - from), allocator)
		copy(b, a[:at])
		copy(b[at:], c[from:])
		return b, how
	case .Noise:
		return bytes(s, 128, allocator), how
	}
	return bytes(s, 128, allocator), .Noise
}

// damage_text is damage over strings, for a parser that reads text.
damage_text :: proc(
	s: ^Source,
	corpus: []string,
	allocator := context.allocator,
) -> (
	out: string,
	how: Damage,
) {
	raw := make([][]byte, len(corpus), context.temp_allocator)
	for c, i in corpus {
		raw[i] = transmute([]byte)c
	}
	b, kind := damage(s, raw, allocator)
	return string(b), kind
}

// clone_bytes copies a slice, including an empty one, so the result is always
// the caller's to keep.
@(private)
clone_bytes :: proc(b: []byte, allocator := context.allocator) -> []byte {
	out := make([]byte, len(b), allocator)
	copy(out, b)
	return out
}

// show renders a value for a failure report: printable text as itself,
// anything else as hex, so a case can be read and retyped.
show :: proc {
	show_bytes,
	show_string,
}

show_bytes :: proc(b: []byte, allocator := context.temp_allocator) -> string {
	if printable(b) {
		return fmt.aprintf("%d bytes %q", len(b), string(b), allocator = allocator)
	}
	return fmt.aprintf("%d bytes %02x", len(b), b, allocator = allocator)
}

show_string :: proc(s: string, allocator := context.temp_allocator) -> string {
	return show_bytes(transmute([]byte)s, allocator)
}

// printable reports whether a run of bytes is worth showing as text.
@(private)
printable :: proc(b: []byte) -> bool {
	if !utf8.valid_string(string(b)) {
		return false
	}
	for c in b {
		if c < 0x20 && c != '\n' && c != '\t' && c != '\r' {
			return false
		}
	}
	return true
}
