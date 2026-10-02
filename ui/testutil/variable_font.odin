package testutil

import "core:os"
import "core:slice"
import "jm:ui/glyf"

// ASCII_FONT is a static TrueType font the repo carries: Liberation Sans
// cut to ASCII, under the OFL beside it.
ASCII_FONT :: #directory + "/../shape/testdata/ascii.ttf"

// SFNS is macOS's system UI font, a variable font with a wght axis
// (wdth, opsz and GRAD besides); absent on other systems.
SFNS :: "/System/Library/Fonts/SFNS.ttf"

// VARIABLE_STRETCH is how much wider the variable_font fixture draws at
// wght 900 than at 400, as a fraction of each glyph's width and advance.
VARIABLE_STRETCH :: 0.25

// variable_font writes to dst ASCII_FONT made variable: a wght axis from
// 100 to 900, default 400, along which each simple glyph and its advance
// stretch rightwards, by VARIABLE_STRETCH at 900 ('gvar' and 'HVAR').
// It lets a test of variable fonts run where SFNS is absent, and it is
// made when the test runs, so how it varies is read here rather than
// hidden in a binary. False when the fixture does not read or dst does
// not write.
variable_font :: proc(dst: string) -> bool {
	data, err := os.read_entire_file(ASCII_FONT, context.allocator)
	if err != nil {
		return false
	}
	defer delete(data)
	tables := make(map[u32][]byte)
	defer delete(tables)
	count := int(be16(data, 4))
	for i in 0 ..< count {
		rec := 12 + 16 * i
		at, size := int(be32(data, rec + 8)), int(be32(data, rec + 12))
		tables[be32(data, rec)] = data[at:at + size]
	}
	f: glyf.Font
	t := glyf.Tables {
		head = tables[tag("head")],
		loca = tables[tag("loca")],
		glyf = tables[tag("glyf")],
	}
	if !glyf.font_init(&f, t) {
		return false
	}
	advances := make([]i16, f.glyph_count)
	defer delete(advances)
	metrics := int(be16(tables[tag("hhea")], 34))
	hmtx := tables[tag("hmtx")]
	for &a, g in advances {
		a = i16(be16(hmtx, 4 * min(g, metrics - 1)))
	}
	fvar := fvar_table()
	defer delete(fvar)
	gvar := gvar_table(&f, advances)
	defer delete(gvar)
	hvar := hvar_table(advances)
	defer delete(hvar)
	tables[tag("fvar")], tables[tag("gvar")], tables[tag("HVAR")] = fvar[:], gvar[:], hvar[:]
	out := sfnt(tables)
	defer delete(out)
	return os.write_entire_file(dst, out[:]) == nil
}

@(private = "file")
fvar_table :: proc() -> [dynamic]byte {
	b: [dynamic]byte
	put16(&b, 1, 0, 16, 2, 1, 20, 0, 8)
	put32(&b, tag("wght"), 100 << 16, 400 << 16, 900 << 16)
	put16(&b, 0, 256)
	return b
}

// gvar_table gives each simple glyph one tuple at wght 900 that moves
// every point right by VARIABLE_STRETCH of its distance from the glyph's
// left edge, and the advance phantom point by that much of the advance.
@(private = "file")
gvar_table :: proc(f: ^glyf.Font, advances: []i16) -> [dynamic]byte {
	s := new(glyf.Scratch)
	defer free(s)
	data: [dynamic]byte
	defer delete(data)
	offsets := make([]u32, f.glyph_count + 1)
	defer delete(offsets)
	for g in 0 ..< f.glyph_count {
		offsets[g] = u32(len(data))
		o, ok := glyf.outline(f, u16(g), {}, s)
		composite := len(o.points) > 0 && simple_count(f, g) != len(o.points)
		if !ok || len(o.points) == 0 || composite {
			continue
		}
		left := o.points[0].x
		for p in o.points {
			left = min(left, p.x)
		}
		dx := make([]i16, len(o.points) + 4)
		defer delete(dx)
		for p, i in o.points {
			dx[i] = i16((p.x - left) * VARIABLE_STRETCH + 0.5)
		}
		dx[len(o.points) + 1] = i16(f32(advances[g]) * VARIABLE_STRETCH + 0.5)
		put16(&data, 1, 10, 0, 0x8000 | 0x2000, 0x4000) // one tuple, its size patched below
		start := len(data)
		append(&data, 0) // every point
		for i := 0; i < len(dx); i += 64 {
			run := dx[i:min(i + 64, len(dx))]
			append(&data, byte(0x40 | (len(run) - 1)))
			for d in run {
				put16(&data, u16(d))
			}
		}
		for i := 0; i < len(dx); i += 64 {
			append(&data, byte(0x80 | (min(64, len(dx) - i) - 1)))
		}
		size := len(data) - start
		data[start - 6], data[start - 5] = byte(size >> 8), byte(size)
		if len(data) % 2 == 1 {
			append(&data, 0)
		}
	}
	offsets[f.glyph_count] = u32(len(data))
	b: [dynamic]byte
	header := 20 + 4 * len(offsets)
	put16(&b, 1, 0, 1, 0)
	put32(&b, u32(header))
	put16(&b, u16(f.glyph_count), 1)
	put32(&b, u32(header))
	for o in offsets {
		put32(&b, o)
	}
	append(&b, ..data[:])
	return b
}

// simple_count is how many points glyph g's own record holds, or -1 for
// a composite, so gvar_table varies simple glyphs only.
@(private = "file")
simple_count :: proc(f: ^glyf.Font, g: int) -> int {
	start := int(be32(f.loca, 4 * g)) if f.loca_long else 2 * int(be16(f.loca, 2 * g))
	contours := i16(be16(f.glyf, start))
	if contours <= 0 {
		return -1
	}
	return int(be16(f.glyf, start + 10 + 2 * (int(contours) - 1))) + 1
}

// hvar_table widens each advance by VARIABLE_STRETCH at wght 900, glyph
// ids indexing the deltas directly.
@(private = "file")
hvar_table :: proc(advances: []i16) -> [dynamic]byte {
	b: [dynamic]byte
	put16(&b, 1, 0)
	put32(&b, 20, 0, 0, 0)
	put16(&b, 1) // item variation store, at 20
	put32(&b, 12)
	put16(&b, 1)
	put32(&b, 22)
	put16(&b, 1, 1, 0, 0x4000, 0x4000) // one region: 0 to wght 900
	put16(&b, u16(len(advances)), 1, 1, 0)
	for a in advances {
		put16(&b, u16(i16(f32(a) * VARIABLE_STRETCH + 0.5)))
	}
	return b
}

// sfnt lays tables out as a TrueType file: a directory sorted by tag, each
// table 4-byte aligned with its checksum.
@(private = "file")
sfnt :: proc(tables: map[u32][]byte) -> [dynamic]byte {
	tags := make([]u32, len(tables))
	defer delete(tags)
	i := 0
	for t in tables {
		tags[i] = t
		i += 1
	}
	slice.sort(tags)
	n := len(tags)
	log2 := 0
	for 1 << u32(log2 + 1) <= n {
		log2 += 1
	}
	b: [dynamic]byte
	put32(&b, 0x00010000)
	put16(&b, u16(n), u16(16 << u32(log2)), u16(log2), u16(16 * n - (16 << u32(log2))))
	at := 12 + 16 * n
	for t in tags {
		data := tables[t]
		put32(&b, t, checksum(data), u32(at), u32(len(data)))
		at += (len(data) + 3) &~ 3
	}
	for t in tags {
		append(&b, ..tables[t])
		for len(b) % 4 != 0 {
			append(&b, 0)
		}
	}
	return b
}

@(private = "file")
checksum :: proc(data: []byte) -> u32 {
	sum: u32
	for i := 0; i < len(data); i += 4 {
		word: u32
		for k in 0 ..< 4 {
			word <<= 8
			if i + k < len(data) {
				word |= u32(data[i + k])
			}
		}
		sum += word
	}
	return sum
}

@(private = "file")
tag :: proc(s: string) -> u32 {
	return u32(s[0]) << 24 | u32(s[1]) << 16 | u32(s[2]) << 8 | u32(s[3])
}

@(private = "file")
be16 :: proc(b: []byte, at: int) -> u16 {
	return u16(b[at]) << 8 | u16(b[at + 1])
}

@(private = "file")
be32 :: proc(b: []byte, at: int) -> u32 {
	return u32(be16(b, at)) << 16 | u32(be16(b, at + 2))
}

@(private = "file")
put16 :: proc(b: ^[dynamic]byte, vs: ..u16) {
	for v in vs {
		append(b, byte(v >> 8), byte(v))
	}
}

@(private = "file")
put32 :: proc(b: ^[dynamic]byte, vs: ..u32) {
	for v in vs {
		append(b, byte(v >> 24), byte(v >> 16), byte(v >> 8), byte(v))
	}
}
