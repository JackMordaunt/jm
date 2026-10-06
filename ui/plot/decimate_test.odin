package plot

import "core:math"
import "core:slice"
import "core:testing"
import "jm:ui/ops"

@(test)
test_decimation_keeps_every_column_extreme :: proc(t: ^testing.T) {
	n := 10_000
	line: Polyline
	line.points = make([dynamic]ops.Point, context.temp_allocator)
	line.starts = make([dynamic]int, context.temp_allocator)
	r := Reducer {
		out = &line,
	}
	lo, hi: [100]f32
	for c in 0 ..< 100 {
		lo[c], hi[c] = max(f32), min(f32)
	}
	for i in 0 ..< n {
		x := f32(i) / f32(n) * 100
		y := f32(math.sin(f64(i) * 0.37) * 50 + f64(i % 97))
		if i == 5000 {
			y = 1000 // a spike one point wide
		}
		reduce_push(&r, {x, y}, i)
		c := int(x)
		lo[c], hi[c] = min(lo[c], y), max(hi[c], y)
	}
	reduce_flush(&r)
	testing.expectf(
		t,
		len(line.points) <= 4 * 100,
		"%d points kept for 100 columns",
		len(line.points),
	)
	for c in 0 ..< 100 {
		testing.expectf(
			t,
			column_keeps(line.points[:], c, lo[c], hi[c]),
			"column %d lost an extreme",
			c,
		)
	}
}

// column_keeps reports whether points keep both lo and hi in column c.
@(private = "file")
column_keeps :: proc(points: []ops.Point, c: int, lo, hi: f32) -> bool {
	found_lo, found_hi := false, false
	for p in points {
		if int(p.x) == c {
			found_lo ||= p.y == lo
			found_hi ||= p.y == hi
		}
	}
	return found_lo && found_hi
}

@(test)
test_decimation_lifts_the_pen_at_gaps_and_steps :: proc(t: ^testing.T) {
	line: Polyline
	line.points = make([dynamic]ops.Point, context.temp_allocator)
	line.starts = make([dynamic]int, context.temp_allocator)
	line.step = .After
	r := Reducer {
		out = &line,
	}
	reduce_push(&r, {0, 10}, 0)
	reduce_push(&r, {10, 20}, 1)
	reduce_break(&r)
	reduce_push(&r, {30, 5}, 3)
	reduce_flush(&r)
	testing.expect_value(t, len(line.starts), 2)
	testing.expect(
		t,
		slice.equal(polyline_run(&line, 0), []ops.Point{{0, 10}, {10, 10}, {10, 20}}),
		"a step after turns level first",
	)
	testing.expect(
		t,
		slice.equal(polyline_run(&line, 1), []ops.Point{{30, 5}}),
		"a gap starts a run",
	)
}

@(test)
test_check_palette_measures_what_the_dataviz_validator_does :: proc(t: ^testing.T) {
	// The dataviz skill's reference palette: its validator reports the
	// worst adjacent CVD ΔE as 9.1 and normal-vision ΔE as 19.6 on #fcfcfb.
	hexes := [?]u32 {
		0x2a78d6ff,
		0xeb6834ff,
		0x1baf7aff,
		0xeda100ff,
		0xe87ba4ff,
		0x008300ff,
		0x4a3aa7ff,
		0xe34948ff,
	}
	colors: [len(hexes)]ops.Color
	for h, i in hexes {
		colors[i] = ops.rgba(h)
	}
	r := check_palette(colors[:], ops.rgba(0xfcfcfbff))
	testing.expectf(t, abs(r.adjacent_cvd - 9.1) < 0.05, "adjacent CVD ΔE %v", r.adjacent_cvd)
	testing.expectf(
		t,
		abs(r.adjacent_normal - 19.6) < 0.05,
		"adjacent normal ΔE %v",
		r.adjacent_normal,
	)
	testing.expect(
		t,
		r.adjacent_cvd >= CVD_TARGET && r.adjacent_normal >= NORMAL_FLOOR,
		"it clears the gates it was chosen by",
	)
	testing.expect(t, r.min_chroma >= CHROMA_FLOOR, "and none of its hues reads as grey")
	// Its yellow, aqua and magenta sit under 3:1 on the light surface, which
	// its documentation answers with visible labels or a table.
	testing.expect(
		t,
		r.min_contrast < CONTRAST_MIN,
		"the validator reports its light slots under 3:1",
	)
	// A red next to a green of the same lightness is what CVD collapses.
	bad := []ops.Color{ops.rgba(0xc0392bff), ops.rgba(0x6b8e23ff)}
	testing.expect(
		t,
		check_palette(bad, ops.rgba(0xffffffff)).adjacent_cvd < CVD_FLOOR,
		"red beside olive passes",
	)
}
