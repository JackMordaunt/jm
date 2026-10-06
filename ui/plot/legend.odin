package plot

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"

// Swatch is how a legend or tooltip keys a series: by the mark it draws.
Swatch :: enum u8 {
	Line, // a short stroke, for a line
	Rect, // a filled square, for bars and areas
	Box, // an outlined square, for a box plot
}

// Entry is one series in a legend.
@(private)
Entry :: struct {
	name:   string,
	slot:   int,
	swatch: Swatch,
}

// LEGEND_GAP is the room between legend entries, and below the legend.
@(private)
LEGEND_GAP :: 16

// SWATCH is a legend key's size.
@(private)
SWATCH :: 12

// legend draws the series' names along the top of the chart, wrapping
// onto more rows when they do not fit, and returns how tall it came to.
// Each entry is a toggle: a click, or Enter or Space while it has focus,
// hides or shows its series. The entries are one Tab stop, the arrow keys
// moving between them. A single series has no legend: the chart's title
// names it.
@(private)
legend :: proc(f: ^Frame, entries: []Entry) -> f32 {
	if len(entries) < 2 {
		return 0
	}
	gtx, s := f.gtx, f.style
	scope := ui.id_mix(f.place.id, 4)
	ui.focus_scope_open(gtx, scope, rove = .Horizontal, wrap = true)
	defer ui.focus_scope_close(gtx)
	x, y := f32(0), f32(0)
	row_h := max(f32(SWATCH), s.label_size * 1.4) + 6
	for e, i in entries {
		r := shape_fit(gtx, e.name, s.label_size, s.font, f.size.x - SWATCH - 8)
		w := SWATCH + 6 + r.width + 8
		if x > 0 && x + w > f.size.x {
			x, y = 0, y + row_h
		}
		box := ops.Rect{x - 4, y, w, row_h}
		legend_entry(f, e, i, r, box)
		x += w + LEGEND_GAP - 8
	}
	return y + row_h + LEGEND_GAP / 2
}

// legend_entry draws and listens to one entry in box.
@(private)
legend_entry :: proc(f: ^Frame, e: Entry, i: int, r: Run, box: ops.Rect) {
	gtx, s := f.gtx, f.style
	id := ui.id_mix(f.place.id, 0x1000 + u64(i))
	c := design.control(gtx, id, box, .Live)
	if c.clicked && !f.faded {
		f.hidden^ ~= {i}
	}
	on := shown(f, i)
	if c.hovered {
		ops.fill(gtx.scene, ops.Round_Rect{box, 4}, s.hover)
	}
	cy := box.y + box.h / 2
	draw_swatch(gtx, s, e.slot, e.swatch, {box.x + 4, cy - SWATCH / 2, SWATCH, SWATCH}, on)
	ink := s.text if on else s.muted
	tx := box.x + 4 + SWATCH + 6
	draw_run(gtx, r, {tx, cy - run_height(r) / 2}, ink)
	if !on {
		// Struck through, so hidden reads without colour.
		ops.fill(gtx.scene, ops.Rect{tx, cy, r.width, max(ui.pixel(gtx), 1)}, ink)
	}
	if !f.faded {
		ops.input_area(gtx.scene, id, box, design.CLICK_KINDS, .Pointer)
	}
	ops.tag(gtx.scene, id, e.name, box)
	ring := design.Focus_Ring {
		width  = s.focus_width,
		offset = 0,
		color  = s.focus,
	}
	design.paint_focus_visible_ring(gtx, c, box, design.corners_all(4), ring)
	states := ops.States{.Checked} if on else {}
	ui.part_semantics(gtx, &f.place, id, box, {role = .Checkbox, label = e.name, states = states})
}

// draw_swatch draws the key of series slot as kind in r: filled when on,
// outlined when its series is hidden.
@(private)
draw_swatch :: proc(
	gtx: ^ui.Ctx,
	s: ^Plot_Style,
	slot: int,
	kind: Swatch,
	r: ops.Rect,
	on := true,
) {
	lk := look(s, slot)
	if !on {
		ops.stroke(gtx.scene, ops.Round_Rect{grow(r, -1), 3}, lk.color, {width = 1.5})
		return
	}
	switch kind {
	case .Line:
		y := r.y + r.h / 2
		ops.stroke(
			gtx.scene,
			ui.line(gtx, {r.x, y}, {r.x + r.w, y}),
			lk.color,
			{width = s.line_width, cap = .Round},
		)
		draw_marker(gtx, lk.marker, {r.x + r.w / 2, y}, 3, lk.color, s.background)
	case .Rect:
		ops.fill(gtx.scene, ops.Round_Rect{r, 3}, lk.color)
	case .Box:
		ops.fill(gtx.scene, ops.Round_Rect{r, 3}, ops.with_alpha(lk.color, 0.25))
		ops.stroke(gtx.scene, ops.Round_Rect{grow(r, -0.75), 3}, lk.color, {width = 1.5})
	}
}

// draw_marker draws m of radius r at c in color, ringed in the surface colour
// ring so it reads where it crosses a line.
@(private)
draw_marker :: proc(gtx: ^ui.Ctx, m: Marker, c: ops.Point, r: f32, color, ring: ops.Color) {
	shape := marker_shape(gtx, m, c, r)
	ops.stroke(gtx.scene, shape, ring, {width = 4, join = .Round})
	ops.fill(gtx.scene, shape, color)
}

@(private)
marker_shape :: proc(gtx: ^ui.Ctx, m: Marker, c: ops.Point, r: f32) -> ops.Shape {
	switch m {
	case .Circle:
		return ui.circle(c, r)
	case .Square:
		k := r * 0.9
		return ops.Rect{c.x - k, c.y - k, 2 * k, 2 * k}
	case .Diamond:
		k := r * 1.25
		return ui.polygon(
			gtx,
			[]ops.Point{{c.x, c.y - k}, {c.x + k, c.y}, {c.x, c.y + k}, {c.x - k, c.y}},
		)
	case .Triangle:
		k := r * 1.3
		return ui.polygon(
			gtx,
			[]ops.Point {
				{c.x, c.y - k},
				{c.x + k * 0.87, c.y + k / 2},
				{c.x - k * 0.87, c.y + k / 2},
			},
		)
	}
	return ui.circle(c, r)
}
