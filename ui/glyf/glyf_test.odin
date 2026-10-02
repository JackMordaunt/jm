package glyf

import "core:os"
import "core:testing"

@(private = "file")
ASCII :: #directory + "/../shape/testdata/ascii.ttf"

// tables finds the tables glyf reads in a font file's table directory.
@(private = "file")
tables :: proc(data: []byte) -> Tables {
	r := Reader{data = data, pos = 4}
	count := int(read_u16(&r))
	t: Tables
	for i in 0 ..< count {
		e := Reader{data = data, pos = 12 + 16 * i}
		tag := read_u32(&e)
		_ = read_u32(&e)
		at, size := int(read_u32(&e)), int(read_u32(&e))
		if e.bad || at + size > len(data) {
			continue
		}
		b := data[at:at + size]
		switch tag {
		case 'h' << 24 | 'e' << 16 | 'a' << 8 | 'd':
			t.head = b
		case 'l' << 24 | 'o' << 16 | 'c' << 8 | 'a':
			t.loca = b
		case 'g' << 24 | 'l' << 16 | 'y' << 8 | 'f':
			t.glyf = b
		}
	}
	return t
}

@(test)
test_font_init_rejects_missing_tables :: proc(t: ^testing.T) {
	f: Font
	testing.expect(t, !font_init(&f, {}), "no tables")
	head := make([]byte, 54, context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect(t, !font_init(&f, {head = head, glyf = {0}}), "no units per em")
	head[18], head[19] = 0x03, 0xE8 // 1000 units per em
	loca := make([]byte, 4, context.temp_allocator)
	testing.expect(t, !font_init(&f, {head = head, loca = loca}), "no glyf")
	testing.expect(t, !font_init(&f, {head = head, glyf = {0}}), "no loca")
	testing.expect(t, font_init(&f, {head = head, loca = loca, glyf = {0}}), "one empty glyph")
}

// Every glyph of a static font decodes, and a glyf table cut short makes
// the glyphs past the cut fail rather than read out of bounds.
@(test)
test_outline_decodes_and_survives_truncation :: proc(t: ^testing.T) {
	data, err := os.read_entire_file(ASCII, context.allocator)
	testing.expect(t, err == nil, "read the fixture")
	defer delete(data)
	f: Font
	testing.expect(t, font_init(&f, tables(data)), "a TrueType font")
	testing.expect_value(t, f.axis_count, 0)
	s := new(Scratch)
	defer free(s)
	drawn := 0
	for g in 0 ..< f.glyph_count {
		o, ok := outline(&f, u16(g), {}, s)
		testing.expectf(t, ok, "glyph %d decodes", g)
		if len(o.ends) > 0 {
			drawn += 1
			testing.expect_value(t, int(o.ends[len(o.ends) - 1]) + 1, len(o.points))
		}
	}
	testing.expect(t, drawn > 20, "the fixture's letters have contours")
	_, ok := outline(&f, u16(f.glyph_count), {}, s)
	testing.expect(t, !ok, "a glyph past the last fails")

	whole := f.glyf
	for cut in ([]int{0, 1, 11, len(whole) / 2, len(whole) - 1}) {
		f.glyf = whole[:cut]
		for g in 0 ..< f.glyph_count {
			_, _ = outline(&f, u16(g), {}, s)
		}
	}
}

@(test)
test_read_points_and_deltas :: proc(t: ^testing.T) {
	out: [8]u16
	r := Reader{data = {0}}
	all, n := read_points(&r, out[:])
	testing.expect(t, all && n == 0 && !r.bad, "0 is every point")

	// 3 points in one byte run: 2, then +3, then +250, cumulative.
	r = Reader{data = {3, 0x02, 2, 3, 250}}
	all, n = read_points(&r, out[:])
	testing.expect(t, !all && !r.bad, "a list")
	testing.expect_value(t, n, 3)
	testing.expect_value(t, [3]u16{out[0], out[1], out[2]}, [3]u16{2, 5, 255})

	// More points than out holds fails instead of overrunning it.
	r = Reader{data = {9, 0x08, 1, 1, 1, 1, 1, 1, 1, 1, 1}}
	_, _ = read_points(&r, out[:])
	testing.expect(t, r.bad, "9 points into 8")

	// Two zero deltas, one word -300, two bytes 5 and -1.
	d: [5]f32
	r = Reader{data = {0x81, 0x40, 0xFE, 0xD4, 0x01, 5, 0xFF}}
	read_deltas(&r, d[:])
	testing.expect(t, !r.bad, "well-formed deltas")
	testing.expect_value(t, d, [5]f32{0, 0, -300, 5, -1})

	r = Reader{data = {0x03, 1}}
	read_deltas(&r, d[:])
	testing.expect(t, r.bad, "a run cut short")
}

@(test)
test_tuple_scalar :: proc(t: ^testing.T) {
	peak := []f32{1}
	none := []f32{0}
	testing.expect_value(t, tuple_scalar({0.5}, peak, none, none, false), 0.5)
	testing.expect_value(t, tuple_scalar({1}, peak, none, none, false), 1)
	testing.expect_value(t, tuple_scalar({-0.5}, peak, none, none, false), 0)
	testing.expect_value(t, tuple_scalar({0}, peak, none, none, false), 0)
	// An intermediate region [0.2, 0.8] peaking at 0.5.
	lo, mid, hi := []f32{0.2}, []f32{0.5}, []f32{0.8}
	testing.expect_value(t, tuple_scalar({0.5}, mid, lo, hi, true), 1)
	testing.expect(t, abs(tuple_scalar({0.35}, mid, lo, hi, true) - 0.5) < 1e-6, "halfway up")
	testing.expect_value(t, tuple_scalar({0.9}, mid, lo, hi, true), 0)
}

// An untouched point between two touched ones takes a delta interpolated
// by its original coordinate; one beyond both takes the nearer's.
@(test)
test_iup_contour :: proc(t: ^testing.T) {
	orig := []Point{{0, 0}, {50, 0}, {100, 0}, {150, 0}, {-50, 0}}
	tuple := []Point{{10, 0}, {}, {20, 0}, {}, {}}
	touched := []bool{true, false, true, false, false}
	iup_contour(orig, tuple, touched, 0, 4)
	testing.expect_value(t, tuple[1].x, 15)
	testing.expect_value(t, tuple[3].x, 20)
	testing.expect_value(t, tuple[4].x, 10)
	testing.expect_value(t, tuple[0].x, 10)

	one := []Point{{4, -2}, {}, {}}
	iup_contour(orig[:3], one, {true, false, false}, 0, 2)
	testing.expect_value(t, one[2], Point{4, -2})
}
