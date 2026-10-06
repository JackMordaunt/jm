package plot

import "jm:ui"
import "jm:ui/ops"

// Run is a line of text shaped for a chart: measured before it is placed,
// as axis labels must be to keep clear of each other.
Run :: struct {
	run:             ops.Glyph_Run,
	width:           f32,
	ascent, descent: f32,
}

// shape_run shapes s at size in font, into the frame allocator.
shape_run :: proc(gtx: ^ui.Ctx, s: string, size: f32, font: ops.Font_Id) -> Run {
	run := ui.shape(gtx.shaper, font, size, s, gtx.allocator)
	m := ui.metrics(gtx.shaper, font, size)
	return {run, run.advance, m.ascent, m.descent}
}

// run_height is r's line box: its ascent and descent.
run_height :: proc(r: Run) -> f32 {
	return r.ascent + r.descent
}

// draw_run draws r with its line box's top-left at pos.
draw_run :: proc(gtx: ^ui.Ctx, r: Run, pos: ops.Point, color: ops.Color) {
	if len(r.run.glyphs) == 0 || color[3] == 0 {
		return
	}
	ops.glyphs(gtx.scene, ops.add_run(gtx.scene, r.run), {pos.x, pos.y + r.ascent}, color)
}

// shape_fit shapes s at size in font, cut short with an ellipsis where it
// is wider than width: the longest prefix, at a character boundary, that
// fits with the ellipsis after it.
shape_fit :: proc(gtx: ^ui.Ctx, s: string, size: f32, font: ops.Font_Id, width: f32) -> Run {
	r := shape_run(gtx, s, size, font)
	if r.width <= width || width <= 0 {
		return r
	}
	buf: [LABEL_MAX + len(ui.ELLIPSIS)]u8
	lo, hi := 0, min(len(s), LABEL_MAX)
	best := shape_run(gtx, ui.ELLIPSIS, size, font)
	for lo < hi {
		mid := char_start(s, (lo + hi + 1) / 2)
		if mid <= lo {
			break
		}
		n := copy(buf[:], s[:mid])
		n += copy(buf[n:], ui.ELLIPSIS)
		cand := shape_run(gtx, string(buf[:n]), size, font)
		if cand.width <= width {
			lo, best = mid, cand
		} else {
			hi = mid - 1
		}
	}
	return best
}

// char_start is i moved back to the start of the UTF-8 character it falls
// in.
@(private)
char_start :: proc(s: string, i: int) -> int {
	j := min(i, len(s))
	for j > 0 && j < len(s) && s[j] & 0xC0 == 0x80 {
		j -= 1
	}
	return j
}

// hairline fills a horizontal line one device pixel tall across [x0, x1]
// at y, snapped to the pixel row y falls in, so a gridline is crisp at any
// density rather than smeared across two rows. It assumes the chart's
// origin falls on a device pixel, as layout in whole units at a whole
// density places it.
hairline :: proc(gtx: ^ui.Ctx, x0, x1, y: f32, color: ops.Color) {
	px := ui.pixel(gtx)
	ops.fill(gtx.scene, ops.Rect{x0, snap(y, px), x1 - x0, px}, color)
}

// vline is hairline down: [y0, y1] at x.
vline :: proc(gtx: ^ui.Ctx, x, y0, y1: f32, color: ops.Color) {
	px := ui.pixel(gtx)
	ops.fill(gtx.scene, ops.Rect{snap(x, px), y0, px, y1 - y0}, color)
}

// snap is v moved down onto the device pixel grid of pitch px.
snap :: proc(v, px: f32) -> f32 {
	return f32(i64(v / px - (0.5 if v < 0 else 0))) * px
}
