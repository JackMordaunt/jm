package fuzz

import "core:math"
import "core:strings"

/*
A case's randomness is a finite byte string, and every generator draws from
it. That one decision is what the rest of the package rests on: a case is a
pure function of its bytes, so it replays exactly, it can be written to disk
as a regression, and it can be shrunk by making the bytes simpler and running
it again.

Generators are written so that a zero byte asks for the simplest value they
can produce. Shrinking drives bytes towards zero, so the simplest failing
case is the one it converges on.
*/

// Source is the byte string a case draws its choices from. Draws past the end
// wrap to the start rather than failing, so a generator can always finish;
// wrapped says whether that happened, which means the case wanted more
// entropy than it was given.
Source :: struct {
	bytes:   []byte,
	pos:     int,
	wrapped: bool,
}

// source starts a case over the given bytes.
source :: proc(bytes: []byte) -> Source {
	return Source{bytes = bytes}
}

// byte_of draws one byte. An empty source draws zeroes for ever, which is the
// simplest case there is.
byte_of :: proc(s: ^Source) -> byte {
	if len(s.bytes) == 0 {
		s.wrapped = true
		return 0
	}
	if s.pos >= len(s.bytes) {
		s.pos = 0
		s.wrapped = true
	}
	b := s.bytes[s.pos]
	s.pos += 1
	return b
}

// u64_of draws eight bytes, most significant first.
u64_of :: proc(s: ^Source) -> u64 {
	v: u64
	for _ in 0 ..< 8 {
		v = v << 8 | u64(byte_of(s))
	}
	return v
}

// integer_in draws an integer in [lo, hi). It takes one byte for a small
// span, so the entropy goes further and each choice stays easy to shrink. A
// zero byte gives lo.
integer_in :: proc(s: ^Source, lo, hi: int) -> int {
	if hi <= lo + 1 {
		return lo
	}
	span := uint(hi - lo)
	if span <= 256 {
		return lo + int(uint(byte_of(s)) % span)
	}
	return lo + int(uint(u64_of(s)) % span)
}

// boolean draws a truth value. A zero byte gives false.
boolean :: proc(s: ^Source) -> bool {
	return byte_of(s) & 1 == 1
}

// choice draws one of items. A zero byte gives the first, so put the least
// interesting one there and shrinking will find it.
choice :: proc(s: ^Source, items: []$T) -> T {
	if len(items) == 0 {
		return {}
	}
	return items[integer_in(s, 0, len(items))]
}

// integer draws an i64, weighted towards the values that overflow, truncate
// or flip sign when a conversion somewhere is wrong.
integer :: proc(s: ^Source) -> i64 {
	edges := []i64 {
		0,
		1,
		-1,
		127,
		128,
		255,
		256,
		-128,
		-129,
		32767,
		32768,
		65535,
		65536,
		2147483647,
		2147483648,
		-2147483648,
		-2147483649,
		4294967295,
		4294967296,
		max(i64),
		min(i64),
		max(i64) - 1,
		min(i64) + 1,
	}
	if byte_of(s) < 160 {
		return choice(s, edges)
	}
	return i64(u64_of(s))
}

// real draws an f64, including the values with nowhere to go in some
// stores: SQLite, for one, turns a bound NaN into NULL. The infinities and
// the extremes of the range are here for the same reason.
real :: proc(s: ^Source) -> f64 {
	edges := []f64 {
		0,
		1,
		-1,
		0.5,
		-0.5,
		math.INF_F64,
		math.NEG_INF_F64,
		math.nan_f64(),
		max(f64),
		-max(f64),
		1e308,
		1e-308,
		2147483648,
	}
	if byte_of(s) < 160 {
		return choice(s, edges)
	}
	return transmute(f64)u64_of(s)
}

// bytes draws a blob of up to max bytes. A zero byte gives an empty one.
bytes :: proc(s: ^Source, max: int, allocator := context.allocator) -> []byte {
	n := integer_in(s, 0, max + 1)
	out := make([]byte, n, allocator)
	for i in 0 ..< n {
		out[i] = byte_of(s)
	}
	return out
}

// text assembles a string from pieces, up to max of them. Pass the fragments
// that break whatever is being fuzzed: quotes and comment markers for a SQL
// parser, separators and dots for a path one. A zero byte gives "".
text :: proc(s: ^Source, pieces: []string, max: int, allocator := context.allocator) -> string {
	n := integer_in(s, 0, max + 1)
	b := strings.builder_make(allocator)
	for _ in 0 ..< n {
		strings.write_string(&b, choice(s, pieces))
	}
	return strings.to_string(b)
}

// AWKWARD is text worth throwing at a parser built out of string
// concatenation: quotes, comment markers, separators, a NUL, bytes that are
// not valid UTF-8, and runes longer than one byte.
AWKWARD := []string {
	"",
	"a",
	" ",
	"'",
	`"`,
	"`",
	";",
	"--",
	"/*",
	"*/",
	"\\",
	"/",
	"..",
	"\n",
	"\r\n",
	"\t",
	"\x00",
	"%",
	"_",
	"?",
	"$1",
	":name",
	"é",
	"\U0001F600",
	"\xff\xfe",
	"\xc3\x28",
}
