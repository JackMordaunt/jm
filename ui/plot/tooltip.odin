package plot

import "core:strings"
import "jm:ui"
import "jm:ui/ops"

// TIP_ROWS is the most rows a tooltip lists; the rest are counted in a
// last "and n more" row.
TIP_ROWS :: 12

// Tip_Row is one series in a tooltip: its key, its value and its name.
@(private)
Tip_Row :: struct {
	slot:  int,
	value: Label,
	name:  string,
	focus: bool, // the series the keyboard is on
	plain: bool, // no key: a total, or a detail of the row above
}

// Tip is a tooltip's text: a heading (the point's x, the category) and a
// row per series.
@(private)
Tip :: struct {
	heading: Label,
	rows:    [TIP_ROWS]Tip_Row,
	n:       int,
	more:    int,
}

@(private)
tip_add :: proc(t: ^Tip, row: Tip_Row) {
	if t.n >= TIP_ROWS {
		t.more += 1
		return
	}
	t.rows[t.n] = row
	t.n += 1
}

// Tip_Runs is a tooltip's text, shaped.
@(private)
Tip_Runs :: struct {
	heading:      Run,
	values:       [TIP_ROWS + 1]Run,
	names:        [TIP_ROWS + 1]Run,
	value_w, row: f32,
	size:         ops.Size,
}

// TIP_PAD is the room inside a tooltip's edge.
@(private)
TIP_PAD :: 10

// tooltip draws t over the rest of the frame beside anchor, on the side
// with room: values first and strong, the series' names after them, each
// keyed with a short stroke of its colour.
@(private)
tooltip :: proc(f: ^Frame, t: ^Tip, anchor: ops.Rect) {
	gtx, s := f.gtx, f.style
	k := tip_shape(f, t)
	key := ui.id_mix(f.place.id, 5)
	o := ui.popup_open(gtx, anchor, key, side = .After, align = .Center, gap = 14)
	ui.overlay_semantics(gtx, &o, {role = .Tooltip, label = ui.frame_string(gtx, label_text(&t.heading)), description = tip_text(gtx, t)}, id = key)
	box := ops.Rect{0, 0, k.size.x, k.size.y}
	ts := s.tooltip
	if ts.shadow[3] > 0 {
		ops.shadow(gtx.scene, {box.x, box.y + 2, box.w, box.h}, ts.radius, 12, ts.shadow)
	}
	ops.fill(gtx.scene, ops.Round_Rect{box, ts.radius}, ts.background)
	ops.stroke(gtx.scene, ops.Round_Rect{grow(box, -0.5), ts.radius}, ts.border, {width = 1})
	y := f32(TIP_PAD)
	draw_run(gtx, k.heading, {TIP_PAD, y}, ts.muted)
	y += run_height(k.heading) + 6
	for i in 0 ..< t.n + (1 if t.more > 0 else 0) {
		x := f32(TIP_PAD)
		if i < t.n && !t.rows[i].plain {
			r := t.rows[i]
			lk := look(s, r.slot)
			cy := y + k.row / 2
			ops.stroke(gtx.scene, ui.line(gtx, {x, cy}, {x + 12, cy}), lk.color, {width = 3 if r.focus else 2, cap = .Round})
		}
		x += 18
		draw_run(gtx, k.values[i], {x, y + (k.row - run_height(k.values[i])) / 2}, ts.text)
		draw_run(gtx, k.names[i], {x + k.value_w + 8, y + (k.row - run_height(k.names[i])) / 2}, ts.muted)
		y += k.row
	}
	ui.popup_close(&o, k.size)
}

// tip_shape shapes t's text and works out how big the tooltip is.
@(private)
tip_shape :: proc(f: ^Frame, t: ^Tip) -> (k: Tip_Runs) {
	gtx, s := f.gtx, f.style
	k.heading = shape_run(gtx, label_text(&t.heading), s.tick_size, s.font)
	k.row = s.label_size * 1.6
	names_w: f32
	for i in 0 ..< t.n {
		r := &t.rows[i]
		k.values[i] = shape_run(gtx, label_text(&r.value), s.label_size, s.font_strong)
		k.names[i] = shape_fit(gtx, r.name, s.label_size, s.font, 220)
		k.value_w = max(k.value_w, k.values[i].width)
		names_w = max(names_w, k.names[i].width)
	}
	if t.more > 0 {
		more: Label
		write_count(&more, "and ", t.more, " more")
		k.values[t.n] = shape_run(gtx, label_text(&more), s.label_size, s.font)
	}
	rows := t.n + (1 if t.more > 0 else 0)
	k.size.x = max(18 + k.value_w + 8 + names_w, k.heading.width) + 2 * TIP_PAD
	k.size.y = 2 * TIP_PAD + run_height(k.heading) + 6 + f32(rows) * k.row
	return
}

// tip_text is t's rows as one line for a screen reader, on the frame
// allocator: "134 PH/s Norway; 86.0 PH/s Paraguay".
@(private)
tip_text :: proc(gtx: ^ui.Ctx, t: ^Tip) -> string {
	b := strings.builder_make(gtx.allocator)
	for i in 0 ..< t.n {
		if i > 0 {
			strings.write_string(&b, "; ")
		}
		strings.write_string(&b, label_text(&t.rows[i].value))
		strings.write_string(&b, " ")
		strings.write_string(&b, t.rows[i].name)
	}
	return strings.to_string(b)
}

// write_count writes before, n, after.
@(private)
write_count :: proc(l: ^Label, before: string, n: int, after: string) {
	put_text(l, before)
	digits: [24]u8
	b := strings.builder_from_bytes(digits[:])
	strings.write_int(&b, n)
	put_text(l, strings.to_string(b))
	put_text(l, after)
}
