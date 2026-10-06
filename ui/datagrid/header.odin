package datagrid

import "core:fmt"
import "jm:ui"
import "jm:ui/ops"

// The header: one cell per visible column over the body, fixed while the
// rows scroll and moved with the middle columns sideways. A header takes
// presses to sort and to be dragged to another place; its right edge
// takes a drag to resize and a double click to fit. A skin draws what is
// in it (header slot) over those areas, so a filter button it draws there
// takes its own presses.

@(private)
paint_header :: proc(pc: ^Painter) {
	g, o, st := pc.g, pc.gtx.scene, pc.st
	geo := &g.geo
	band := ops.Rect{0, 0, geo.size.x, geo.header_h}
	if ui.painted(st.header_bg) {
		ops.fill(o, band, st.header_bg)
	}
	hid := ui.id_mix(pc.id, 5)
	for r in regions(g) {
		if r.w <= 0 || r.lo >= r.hi {
			continue
		}
		ops.clip_push(o, ops.Rect{r.x, 0, r.w, geo.header_h})
		if r.pin != .None && ui.painted(st.header_bg) {
			ops.fill(o, ops.Rect{r.x, 0, r.w, geo.header_h}, st.header_bg)
		}
		for at in r.lo ..< r.hi {
			pl := g.place.places[at]
			paint_header_cell(pc, at, {r.shift + pl.x, 0, pl.w, geo.header_h}, hid)
		}
		// The grips after every header, so the one at a column's right
		// edge lies over the header to its right too.
		for at in r.lo ..< r.hi {
			pl := g.place.places[at]
			paint_grip(pc, pl.col, {r.shift + pl.x, 0, pl.w, geo.header_h})
		}
		ops.clip_pop(o)
	}
	paint_pin_edges(pc, band)
	if ui.painted(st.rule) {
		ops.fill(o, ops.Rect{0, geo.header_h - 1, geo.size.x, 1}, st.rule)
	}
	paint_move(pc)
	ops.semantic(o, hid, pc.id, {role = .Row, row_index = 1}, band)
}

// paint_header_cell draws column places[at]'s header in cell: its area,
// the skin's content or the title and marks, the rule at its right, and
// its resize grip; and declares it to readers.
@(private)
paint_header_cell :: proc(pc: ^Painter, at: int, cell: ops.Rect, row: ops.Area_Id) {
	g, o, st, gtx := pc.g, pc.gtx.scene, pc.st, pc.gtx
	col := g.place.places[at].col
	c := &pc.cols[col]
	aid := ui.id_mix(pc.id, AREA_HEADER + u64(col))
	ops.input_area(o, aid, cell, HEADER_KINDS, .Default if c.no_sort else .Pointer)
	rank := sort_rank(&g.view, col)
	desc := rank >= 0 && g.view.sort[rank].desc
	h := Header {
		grid     = g,
		col      = col,
		column   = c,
		size     = {cell.w, cell.h},
		rank     = rank,
		desc     = desc,
		filtered = view_filtered(&g.view, col),
		hovered  = g.hover_head == col,
		cursor   = g.cursor.item < 0 && g.cursor.col == col,
		key      = u64(aid),
	}
	if g.drag.kind == .Move && g.drag.col == col {
		ops.fill(o, cell, st.hover) // the column being moved, where it was
	}
	if pc.skin.header != nil {
		ops.transform_push(o, ops.translate(cell.x, cell.y))
		s := ui.sized_open(gtx, {min = h.size, max = h.size}, key = u64(ui.id_mix(aid, 1)))
		pc.skin.header(gtx, &h, pc.skin.user)
		ui.close(&s)
		ops.transform_pop(o)
	} else {
		paint_header_content(pc, &h, cell)
	}
	if h.cursor && g.focused && ui.painted(st.cursor) {
		ops.stroke(
			o,
			ops.Rect{cell.x + 1, cell.y + 1, cell.w - 2, cell.h - 2},
			st.cursor,
			{width = 2},
		)
	}
	if ui.painted(st.column_rule) {
		ops.fill(o, ops.Rect{cell.x + cell.w - 1, cell.y + 6, 1, cell.h - 12}, st.column_rule)
	}
	said := ui.frame_string(gtx, c.title)
	ops.tag(o, aid, said, cell)
	sort := ops.Sort_Order.None
	if rank >= 0 {
		sort = .Descending if desc else .Ascending
	}
	ops.semantic(
		o,
		aid,
		row,
		{role = .Column_Header, label = said, row_index = 1, col_index = i32(at) + 1, sort = sort},
		cell,
	)
}

// paint_header_content is a header without a skin's slot: the title, a
// triangle for its sort (with its rank in a sort of several), and a dot
// while it is filtered.
@(private)
paint_header_content :: proc(pc: ^Painter, h: ^Header, cell: ops.Rect) {
	g, st, gtx := pc.g, pc.st, pc.gtx
	mark: f32 = 14
	box := ops.Rect{cell.x + st.pad, cell.y, cell.w - 2 * st.pad - mark, cell.h}
	draw_line(gtx, &g.text, pc.head, h.column.title, box, h.column.align, st.header_fg)
	mx := cell.x + cell.w - st.pad - mark / 2
	my := cell.y + cell.h / 2
	if h.rank >= 0 {
		ink := st.active if ui.painted(st.active) else st.header_fg
		tri := []ops.Point{{mx - 4, my + 2}, {mx + 4, my + 2}, {mx, my - 3}}
		if h.desc {
			tri = []ops.Point{{mx - 4, my - 2}, {mx + 4, my - 2}, {mx, my + 3}}
		}
		ops.fill(gtx.scene, ui.polygon(gtx, tri), ink)
		if len(g.view.sort) > 1 {
			n := fmt.aprintf("%d", h.rank + 1, allocator = gtx.allocator)
			draw_line(gtx, &g.text, pc.body, n, {mx + 5, cell.y, mark, cell.h}, .Start, ink)
		}
	}
	if h.filtered {
		ink := st.active if ui.painted(st.active) else st.header_fg
		ops.fill(gtx.scene, ui.circle({mx - mark, my}, 2.5), ink)
	}
}

// paint_grip lays the resize grip at a header's right edge, lit while
// the pointer is on it or it is dragged.
@(private)
paint_grip :: proc(pc: ^Painter, col: int, cell: ops.Rect) {
	g, o := pc.g, pc.gtx.scene
	rid := ui.id_mix(pc.id, AREA_RESIZE + u64(col))
	grip := ops.Rect{cell.x + cell.w - RESIZE_GRIP / 2, cell.y, RESIZE_GRIP, cell.h}
	ops.input_area(o, rid, grip, HEADER_KINDS, .Resize_EW)
	if (g.hover_grip == col || (g.drag.kind == .Resize && g.drag.col == col)) &&
	   ui.painted(pc.st.handle) {
		ops.fill(o, ops.Rect{cell.x + cell.w - 2, cell.y, 2, cell.h}, pc.st.handle)
	}
	ops.tag(
		o,
		rid,
		fmt.aprintf("resize %s", pc.cols[col].title, allocator = pc.gtx.allocator),
		grip,
	)
}

// paint_move draws a column being moved: its title following the
// pointer, and a bar where it would land.
@(private)
paint_move :: proc(pc: ^Painter) {
	g, o, st := pc.g, pc.gtx.scene, pc.st
	if g.drag.kind != .Move {
		return
	}
	at := place_of(&g.place, g.drag.col)
	if at < 0 {
		return
	}
	pl := g.place.places[at]
	ghost := ops.Rect{g.drag.x - pl.w / 2, 0, pl.w, g.geo.header_h}
	ops.fill(o, ghost, ops.with_alpha(st.header_bg, 0.9))
	ops.stroke(o, ghost, st.handle, {width = 1})
	draw_line(
		pc.gtx,
		&g.text,
		pc.head,
		pc.cols[g.drag.col].title,
		{ghost.x + st.pad, 0, ghost.w - 2 * st.pad, ghost.h},
		.Start,
		st.header_fg,
	)
	if to, ok := drop_index(g, g.drag.col, g.drag.x); ok {
		x := drop_x(g, pl.pin, to)
		ops.fill(o, ops.Rect{x - 1, 0, 2, g.geo.size.y}, st.handle)
	}
}

// drop_x is where in the grid a column dropped at order index to would
// stand: the left edge of the column there, or the right edge of its
// group's last.
@(private)
drop_x :: proc(g: ^Grid, pin: Pin, to: int) -> f32 {
	end: f32
	for pl in g.place.places {
		if pl.pin != pin {
			continue
		}
		x := place_screen_x(g, pl)
		if order_index(g, pl.col) >= to {
			return x
		}
		end = x + pl.w
	}
	return end
}
