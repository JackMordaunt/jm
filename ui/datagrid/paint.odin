package datagrid

import "core:fmt"
import "jm:ui"
import "jm:ui/ops"

// Painting a frame: the body's rows in three regions (the middle columns,
// scrolled sideways, then the pinned left and right over them), the
// header over the body, the bars, the outline. Only the rows in view and
// the middle columns in view are drawn. Every row and cell drawn is a
// semantic node placed among all the rows by its index, so a reader hears
// "row 4,812 of 20,000" of a grid that drew forty.

// BODY_KINDS is what the body's area asks for: the grid takes focus and
// keys there, and the pointer's presses and travel.
BODY_KINDS :: ops.Event_Kinds {
	.Press,
	.Release,
	.Move,
	.Enter,
	.Leave,
	.Key,
	.Focus,
	.Blur,
	.Cancel,
}

// HEADER_KINDS is what a header's area asks for.
HEADER_KINDS :: ops.Event_Kinds{.Press, .Release, .Move, .Enter, .Leave, .Cancel}

// Painter is what painting a frame reads, gathered once.
@(private)
Painter :: struct {
	gtx:   ^ui.Ctx,
	g:     ^Grid,
	cols:  []Column,
	src:   Source,
	skin:  ^Skin,
	st:    ^Style,
	id:    ops.Area_Id,
	body:  Text_Style,
	bold:  Text_Style,
	head:  Text_Style,
	range: Range, // the cells from the anchor to the cursor, when more than one
}

// Range is a block of cells: items and places, inclusive.
@(private)
Range :: struct {
	on:               bool,
	item_lo, item_hi: int,
	at_lo, at_hi:     int,
}

// Region is one band of columns: its pin, where it shows and how wide,
// its places [lo, hi), and the x its places' x are measured from.
@(private)
Region :: struct {
	pin:    Pin,
	x, w:   f32,
	lo, hi: int,
	shift:  f32,
}

@(private)
regions :: proc(g: ^Grid) -> [3]Region {
	geo := &g.geo
	p := &g.place
	right_x := geo.size.x - p.right_w
	return {
		{.None, geo.mid_x, geo.mid_w, geo.mid_lo, geo.mid_hi, geo.mid_x - g.scroll.x},
		{.Left, 0, p.left_w, 0, p.mid_first, 0},
		{.Right, right_x, p.right_w, p.right_first, len(p.places), right_x},
	}
}

@(private)
paint :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Source,
	skin: ^Skin,
	id: ops.Area_Id,
	label: string,
) {
	st := &skin.style
	font := st.font if st.font != 0 else gtx.font
	head := st.header_font if st.header_font != 0 else font
	hsize := st.header_size if st.header_size > 0 else st.text_size
	pc := Painter {
		gtx  = gtx,
		g    = g,
		cols = cols,
		src  = src,
		skin = skin,
		st   = st,
		id   = id,
		body = text_style(gtx, &g.text, font, st.text_size),
		bold = text_style(gtx, &g.text, head, st.text_size),
		head = text_style(gtx, &g.text, head, hsize),
	}
	pc.range = cell_range(g)
	geo := &g.geo
	o := gtx.scene
	whole := ops.Rect{0, 0, geo.size.x, geo.size.y}
	ops.input_area(o, ui.id_mix(id, AREA_SCROLL), whole, {.Scroll})
	ops.input_area(o, id, geo.body, BODY_KINDS)
	paint_body(&pc)
	// The rounded corners clip the header and the foot, each inside a
	// rect clip of its own band: a draw reaching into the body from
	// outside its regions, or under a clip of any shape but a rect, would
	// keep the compositor from moving the rows' pixels.
	bottom := geo.body.y + geo.body.h
	ops.clip_push(o, ops.Rect{0, 0, geo.size.x, geo.body.y})
	ops.clip_push(o, ops.Round_Rect{whole, st.radius})
	paint_header(&pc)
	ops.clip_pop(o)
	ops.clip_pop(o)
	ops.clip_push(o, ops.Rect{0, bottom, geo.size.x, geo.size.y - bottom})
	ops.clip_push(o, ops.Round_Rect{whole, st.radius})
	paint_foot(&pc)
	ops.clip_pop(o)
	ops.clip_pop(o)
	paint_outline(&pc)
	grid_semantics(&pc, label)
}

// cell_range is the block of cells from the anchor to the cursor, on
// when it spans more than one cell.
@(private)
cell_range :: proc(g: ^Grid) -> (r: Range) {
	a, c := g.anchor, g.cursor
	if a.item < 0 || c.item < 0 || (a.item == c.item && a.col == c.col) {
		return
	}
	pa, pcur := place_of(&g.place, a.col), place_of(&g.place, c.col)
	if pa < 0 || pcur < 0 {
		return
	}
	return {true, min(a.item, c.item), max(a.item, c.item), min(pa, pcur), max(pa, pcur)}
}

// paint_body draws the rows in view region by region, then declares
// them to readers. A compositor moves the pixels under a rect clip whose
// content scrolled when nothing else drawn over them changed
// (render.find_scrolls; test_compose_meeting_regions_both_scroll), so each
// region is one rect clip holding everything drawn over its rows that is
// not the same in every frame (the bars, the pinned edges' shade, the
// focus ring's sides, a failed page's message), while the
// background under them is one solid fill and the outline's sides lie
// outside them, each under a clip of its own.
@(private)
paint_body :: proc(pc: ^Painter) {
	g, o := pc.g, pc.gtx.scene
	geo := &g.geo
	if ui.painted(pc.st.bg) {
		ops.fill(o, geo.body, pc.st.bg)
	}
	rs := regions(g)
	lead, trail := edge_regions(rs)
	edge := edge_width(pc.st)
	for r, i in rs {
		if !region_shows(r) {
			continue
		}
		x0, x1 := max(r.x, edge), min(r.x + r.w, geo.size.x - edge)
		ops.clip_push(o, ops.Rect{x0, geo.body.y, max(x1 - x0, 0), geo.body.h})
		for item in geo.first ..< geo.last {
			paint_region_row(pc, r, i, item)
		}
		paint_region_over(pc, r, i == lead, i == trail)
		ops.clip_pop(o)
	}
	paint_side(pc, 0)
	paint_side(pc, geo.size.x - edge)
	if geo.items == 0 {
		ops.clip_push(o, geo.body)
		paint_empty(pc)
		ops.clip_pop(o)
	}
	for item in geo.first ..< geo.last {
		row_semantics(pc, item)
	}
}

// edge_width is the outline's width, which the rows stop short of.
@(private)
edge_width :: proc(st: ^Style) -> f32 {
	return 1 if ui.painted(st.border) else 0
}

// region_shows reports whether r has columns and room.
@(private)
region_shows :: proc(r: Region) -> bool {
	return r.w > 0 && r.lo < r.hi
}

// edge_regions is which of rs show at the grid's left and right edges,
// -1 when none shows: rs is the middle, then the left, then the right.
@(private)
edge_regions :: proc(rs: [3]Region) -> (lead, trail: int) {
	lead, trail = -1, -1
	for i in ([3]int{2, 0, 1}) {
		if region_shows(rs[i]) {
			lead = i
		}
	}
	for i in ([3]int{1, 0, 2}) {
		if region_shows(rs[i]) {
			trail = i
		}
	}
	return
}

// paint_region_over draws what lies over region r's rows: in the
// middle, the pinned groups' shade and the sideways bar; at the grid's
// left edge (lead) and right edge (trail), the focus ring's side, and
// at the right the rows' bar.
@(private)
paint_region_over :: proc(pc: ^Painter, r: Region, lead, trail: bool) {
	geo := &pc.g.geo
	edge := edge_width(pc.st)
	if r.pin == .None {
		paint_pin_edges(pc, geo.body)
		paint_hbar(pc)
	}
	ring := ring_shows(pc)
	if lead && ring {
		ops.fill(pc.gtx.scene, ops.Rect{edge, geo.body.y, 2, geo.body.h}, pc.st.focus)
	}
	if trail {
		paint_vbar(pc)
		if ring {
			x := geo.size.x - edge - 2
			ops.fill(pc.gtx.scene, ops.Rect{x, geo.body.y, 2, geo.body.h}, pc.st.focus)
		}
	}
}

// paint_side draws the outline's side at x down the body, under a clip
// of its own width, so it reaches none of the rows' pixels.
@(private)
paint_side :: proc(pc: ^Painter, x: f32) {
	st, o, body := pc.st, pc.gtx.scene, pc.g.geo.body
	w := edge_width(st)
	if w <= 0 {
		return
	}
	side := ops.Rect{x, body.y, w, body.h}
	ops.clip_push(o, side)
	ops.fill(o, side, st.border)
	ops.clip_pop(o)
}

// ring_shows reports whether the grid shows its focus ring.
@(private)
ring_shows :: proc(pc: ^Painter) -> bool {
	return pc.g.focused && ui.focus_visible(pc.gtx) && ui.painted(pc.st.focus)
}

// paint_foot fills the band under the body that the bottom corners
// round.
@(private)
paint_foot :: proc(pc: ^Painter) {
	geo := &pc.g.geo
	top := geo.body.y + geo.body.h
	if ui.painted(pc.st.bg) && top < geo.size.y {
		ops.fill(pc.gtx.scene, ops.Rect{0, top, geo.size.x, geo.size.y - top}, pc.st.bg)
	}
}

// row_box is item's band across the grid's width, in the grid's space.
@(private)
row_box :: proc(g: ^Grid, item: int) -> ops.Rect {
	y := g.geo.body.y + f32(heights_top(&g.heights, item)) - g.scroll.y
	return {0, y, g.geo.size.x, f32(heights_of(&g.heights, item))}
}

// row_id is the semantic node of the row at item, by its key when it
// has one so the node follows the row.
@(private)
row_id :: proc(pc: ^Painter, it: Item, item: int) -> ops.Area_Id {
	base := ui.id_mix(pc.id, 6)
	if has_row(it) {
		return ui.id_mix(base, u64(it.key))
	}
	return ui.id_mix(base, 1 << 63 | u64(item))
}

// region_width is the width of the columns pinned at pin.
@(private)
region_width :: proc(g: ^Grid, pin: Pin) -> f32 {
	switch pin {
	case .Left:
		return g.place.left_w
	case .Right:
		return g.place.right_w
	case .None:
	}
	return g.place.mid_w
}

// paint_region_row draws item's part of region r (index ri): its fills,
// its cells and the rule under it, or its slice of a row that spans the
// grid. It draws in the row's own space, moved into place by a
// transform, so a scroll changes only transforms: the compositor then
// moves the pixels it has instead of painting them again.
@(private)
paint_region_row :: proc(pc: ^Painter, r: Region, ri, item: int) {
	g, o, st := pc.g, pc.gtx.scene, pc.st
	box := row_box(g, item)
	it := item_at(g, pc.src, item)
	band := ops.Rect{0, 0, region_width(g, r.pin), box.h}
	ops.transform_push(o, ops.translate(r.shift, box.y))
	defer ops.transform_pop(o)
	if it.state == .Failed {
		paint_span(pc, r, ri, it, item, band)
		return
	}
	paint_row_fills(pc, it, item, band)
	rid := row_id(pc, it, item)
	for at in r.lo ..< r.hi {
		pl := g.place.places[at]
		paint_cell(pc, it, item, at, {pl.x, 0, pl.w, box.h}, rid)
	}
	if ui.painted(st.rule) {
		ops.fill(o, ops.Rect{band.x, band.h - 1, band.w, 1}, st.rule)
	}
}

// paint_row_fills fills a row's band: every other row's zebra, the
// pointer's row, a selected row.
@(private)
paint_row_fills :: proc(pc: ^Painter, it: Item, item: int, band: ops.Rect) {
	g, o, st := pc.g, pc.gtx.scene, pc.st
	if ui.painted(st.zebra) && item % 2 == 1 {
		ops.fill(o, band, st.zebra)
	}
	if !has_row(it) {
		return
	}
	if g.hover == item {
		ops.fill(o, band, st.hover)
	}
	if selected(&g.sel, it.key) && ui.painted(st.selected) {
		ops.fill(o, band, st.selected)
	}
}

// paint_span draws region r's slice of a row that spans the grid, a
// failed page's message, band being the region's
// part of the row. Each region draws the whole row in the grid's space
// and its clip keeps its slice, so the slices meet as one row that does
// not scroll sideways.
@(private)
paint_span :: proc(pc: ^Painter, r: Region, ri: int, it: Item, item: int, band: ops.Rect) {
	o := pc.gtx.scene
	ops.transform_push(o, ops.translate(-r.shift, 0))
	defer ops.transform_pop(o)
	box := ops.Rect{0, 0, pc.g.geo.size.x, band.h}
	paint_failed(pc, it.error, box, ri, item)
}

// paint_cell draws one cell: a skeleton while its page loads, else the
// skin's drawing or its text cut to fit, the range's tint and the
// cursor's outline; and declares it to readers.
@(private)
paint_cell :: proc(pc: ^Painter, it: Item, item, at: int, cell: ops.Rect, rid: ops.Area_Id) {
	g, o, st := pc.g, pc.gtx.scene, pc.st
	col := g.place.places[at].col
	if ui.painted(st.column_rule) {
		ops.fill(o, ops.Rect{cell.x + cell.w - 1, cell.y, 1, cell.h}, st.column_rule)
	}
	if !has_row(it) {
		if it.state != .Failed {
			paint_skeleton(pc, cell, item, at)
		}
		return
	}
	paint_range(pc, item, at, cell)
	text := cell_text(pc.gtx, pc.src, pc.cols, it, item, col)
	is_cursor := g.cursor.item == item && g.cursor.col == col
	sel := selected(&g.sel, it.key)
	fg := cell_ink(st, it.state, sel)
	if !skin_cell(pc, it, item, col, text, cell, sel, is_cursor, fg) {
		ts := pc.bold if pc.cols[col].row_header else pc.body
		box := ops.Rect{cell.x + st.pad, cell.y, cell.w - 2 * st.pad, cell.h}
		draw_line(pc.gtx, &g.text, ts, text, box, pc.cols[col].align, fg)
	}
	if is_cursor {
		paint_cursor_ring(pc, cell)
	}
	cell_semantics(pc, rid, item, at, col, text, sel, cell)
}

// cell_ink is a cell's text colour: the selected text colour on a
// selected row where the style has one, dimmed on a stale row.
@(private)
cell_ink :: proc(st: ^Style, state: Row_State, sel: bool) -> ops.Color {
	fg := st.fg
	if sel && ui.painted(st.selected_fg) {
		fg = st.selected_fg
	}
	if state == .Stale {
		fg = scale_alpha(fg, st.stale_alpha if st.stale_alpha > 0 else 0.5)
	}
	return fg
}

// paint_cursor_ring outlines the keyboard's cell while the grid has
// focus.
@(private)
paint_cursor_ring :: proc(pc: ^Painter, cell: ops.Rect) {
	if !pc.g.focused || !ui.painted(pc.st.cursor) {
		return
	}
	ring := ops.Rect{cell.x + 1, cell.y + 1, cell.w - 2, cell.h - 2}
	ops.stroke(pc.gtx.scene, ring, pc.st.cursor, {width = 2})
}

// cell_semantics declares a cell to readers, placed among all the rows
// and the visible columns, and tags it with its text.
@(private)
cell_semantics :: proc(
	pc: ^Painter,
	rid: ops.Area_Id,
	item, at, col: int,
	text: string,
	sel: bool,
	cell: ops.Rect,
) {
	o := pc.gtx.scene
	cid := ui.id_mix(rid, u64(col) + 1)
	said := ui.frame_string(pc.gtx, text)
	sem := ops.Semantics {
		role      = .Grid_Cell,
		label     = said,
		row_index = i32(item) + 2,
		col_index = i32(at) + 1,
		states    = ops.States{.Selected} if sel else {},
	}
	ops.semantic(o, cid, rid, sem, cell)
	if said != "" {
		ops.tag(o, cid, said, cell)
	}
}

// skin_cell lets the skin draw a cell, in its own box, and reports
// whether it did.
@(private)
skin_cell :: proc(
	pc: ^Painter,
	it: Item,
	item, col: int,
	text: string,
	cell: ops.Rect,
	sel, is_cursor: bool,
	fg: ops.Color,
) -> bool {
	if pc.skin.cell == nil {
		return false
	}
	gtx := pc.gtx
	c := Cell {
		grid     = pc.g,
		col      = col,
		column   = &pc.cols[col],
		row      = it.row,
		item     = item,
		key      = it.key,
		text     = text,
		size     = {cell.w, cell.h},
		state    = it.state,
		selected = sel,
		hovered  = pc.g.hover == item,
		cursor   = is_cursor,
		fg       = fg,
	}
	s := slot_open(gtx, c.size, ui.id_mix(ui.id_mix(pc.id, 7), u64(item) << 16 | u64(col)))
	drew := pc.skin.cell(gtx, &c, pc.skin.cell_user)
	slot_close(gtx, &s, {cell.x, cell.y})
	return drew
}

// paint_range tints a cell in the block of cells from the anchor to the
// cursor and draws the block's edge where the cell has one, so the block
// shows over the rows it selects, which share its tint.
@(private)
paint_range :: proc(pc: ^Painter, item, at: int, cell: ops.Rect) {
	rg := pc.range
	if !rg.on || item < rg.item_lo || item > rg.item_hi || at < rg.at_lo || at > rg.at_hi {
		return
	}
	// Above the row's rule, which the row draws after its cells.
	inner := ops.Rect{cell.x, cell.y, cell.w, cell.h - 1}
	ops.fill(pc.gtx.scene, inner, pc.st.selected)
	if ui.painted(pc.st.cursor) {
		paint_range_edges(pc, item, at, inner)
	}
}

// paint_range_edges draws the sides of the range's block that cell, inside
// it at item and place at, lies on.
@(private)
paint_range_edges :: proc(pc: ^Painter, item, at: int, cell: ops.Rect) {
	rg, o, ink := pc.range, pc.gtx.scene, pc.st.cursor
	if item == rg.item_lo {
		ops.fill(o, ops.Rect{cell.x, cell.y, cell.w, 1}, ink)
	}
	if item == rg.item_hi {
		ops.fill(o, ops.Rect{cell.x, cell.y + cell.h - 1, cell.w, 1}, ink)
	}
	if at == rg.at_lo {
		ops.fill(o, ops.Rect{cell.x, cell.y, 1, cell.h + 1}, ink)
	}
	if at == rg.at_hi {
		ops.fill(o, ops.Rect{cell.x + cell.w - 1, cell.y, 1, cell.h + 1}, ink)
	}
}

// slot_open starts a skin's slot: what it lays out, in exactly size, is
// recorded rather than placed in the grid's box, for slot_close to draw
// where the grid puts it, under the grid's own transforms and clips.
@(private)
slot_open :: proc(gtx: ^ui.Ctx, size: ops.Size, key: ops.Area_Id) -> ui.Recording {
	return ui.record_open(gtx, ui.exact(size), u64(key))
}

// slot_close draws the slot s recorded at at, in the current space.
@(private)
slot_close :: proc(gtx: ^ui.Ctx, s: ^ui.Recording, at: ops.Point) {
	m, _ := ui.record_close(s)
	ops.transform_push(gtx.scene, ops.translate(at.x, at.y))
	ops.call(gtx.scene, m)
	ops.transform_pop(gtx.scene)
}

// SKELETON_WIDTHS are a loading cell's bar, as a share of its width,
// cycling down the rows and across the columns.
@(rodata)
SKELETON_WIDTHS := [5]f32{0.85, 0.65, 0.8, 0.55, 0.75}

@(private)
paint_skeleton :: proc(pc: ^Painter, cell: ops.Rect, item, at: int) {
	st := pc.st
	if !ui.painted(st.skeleton) {
		return
	}
	h := min(pc.body.height * 0.75, cell.h - 8)
	w := (cell.w - 2 * st.pad) * SKELETON_WIDTHS[(item + at) % len(SKELETON_WIDTHS)]
	bar := ops.Rect{cell.x + st.pad, cell.y + (cell.h - h) / 2, max(w, 0), h}
	ops.fill(pc.gtx.scene, ops.Round_Rect{bar, h / 2}, st.skeleton)
}

// row_semantics declares the row at item to readers, with what a reader
// hears for a failed page.
@(private)
row_semantics :: proc(pc: ^Painter, item: int) {
	g := pc.g
	it := item_at(g, pc.src, item)
	box := row_box(g, item)
	rid := row_id(pc, it, item)
	label := ""
	states: ops.States
	switch {
	case it.state == .Failed:
		label = it.error
	case has_row(it):
		states = ops.States{.Selected} if selected(&g.sel, it.key) else {}
	case:
		states = {.Busy}
	}
	sem := ops.Semantics {
		role      = .Row,
		label     = label,
		row_index = i32(item) + 2,
		states    = states,
	}
	ops.semantic(pc.gtx.scene, rid, pc.id, sem, box)
}

// paint_failed draws a failed page's message across row item of it, the
// skin's slot keyed apart for each row and each region ri that draws its
// slice: every row of a failed page draws one.
@(private)
paint_failed :: proc(pc: ^Painter, err: string, box: ops.Rect, ri, item: int) {
	gtx, st := pc.gtx, pc.st
	if pc.skin.failed != nil {
		size := ops.Size{box.w, box.h}
		key := ui.id_mix(ui.id_mix(pc.id, 10), u64(item) << 2 | u64(ri))
		s := slot_open(gtx, size, key)
		drew := pc.skin.failed(gtx, size, err, pc.skin.user)
		slot_close(gtx, &s, {box.x, box.y})
		if drew {
			return
		}
	}
	msg := fmt.aprintf(
		"Couldn't load these rows: %s. Click or press Enter to retry.",
		err,
		allocator = gtx.allocator,
	)
	line := ops.Rect{box.x + st.pad, box.y, box.w - 2 * st.pad, box.h}
	draw_line(gtx, &pc.g.text, pc.body, msg, line, .Start, st.error_fg)
	if ui.painted(st.rule) {
		ops.fill(gtx.scene, ops.Rect{box.x, box.y + box.h - 1, box.w, 1}, st.rule)
	}
}

// paint_empty draws a grid with no rows: the skin's empty state, or a
// line saying so.
@(private)
paint_empty :: proc(pc: ^Painter) {
	gtx, g := pc.gtx, pc.g
	body := g.geo.body
	if pc.src.paged != nil && g.pages.kind != .Exact {
		return // not known to be empty yet
	}
	if pc.skin.empty != nil {
		s := slot_open(gtx, {body.w, body.h}, ui.id_mix(pc.id, 9))
		pc.skin.empty(gtx, {body.w, body.h}, pc.skin.user)
		slot_close(gtx, &s, {body.x, body.y})
		return
	}
	msg := "No rows match" if view_filters_active(&g.view) else "No rows"
	draw_line(
		gtx,
		&g.text,
		pc.body,
		msg,
		{body.x, body.y, body.w, min(body.h, 80)},
		.Center,
		pc.st.muted,
	)
}

// paint_pin_edges shades the edge of a pinned group where scrolled
// columns pass under it.
@(private)
paint_pin_edges :: proc(pc: ^Painter, band: ops.Rect) {
	g, st, o := pc.g, pc.st, pc.gtx.scene
	if !ui.painted(st.pin_shadow) {
		return
	}
	clear := st.pin_shadow
	clear.a = 0
	if g.place.left_w > 0 && g.scroll.x > 0 {
		x := g.place.left_w
		ops.fill(
			o,
			ops.Rect{x, band.y, 6, band.h},
			ops.Linear_Gradient{{x, 0}, {x + 6, 0}, fade_stops(pc.gtx, st.pin_shadow, clear)},
		)
	}
	if g.place.right_w > 0 && g.scroll.x < g.place.mid_w - g.geo.mid_w - 0.5 {
		x := g.geo.size.x - g.place.right_w
		ops.fill(
			o,
			ops.Rect{x - 6, band.y, 6, band.h},
			ops.Linear_Gradient{{x, 0}, {x - 6, 0}, fade_stops(pc.gtx, st.pin_shadow, clear)},
		)
	}
}

// fade_stops is a gradient's stops from a to b, in the frame.
@(private)
fade_stops :: proc(gtx: ^ui.Ctx, a, b: ops.Color) -> []ops.Gradient_Stop {
	s := make([]ops.Gradient_Stop, 2, gtx.allocator)
	s[0], s[1] = {0, a}, {1, b}
	return s
}

// paint_vbar draws the rows' scroll bar at the grid's right edge.
@(private)
paint_vbar :: proc(pc: ^Painter) {
	g, gtx := pc.g, pc.gtx
	geo := &g.geo
	id := ui.id_mix(pc.id, AREA_VBAR)
	size := ops.Size{geo.size.x, geo.body.h}
	ops.transform_push(gtx.scene, ops.translate(0, geo.body.y))
	ui.scroll_bar_paint(gtx, id, .Vertical, size, f32(geo.content), g.scroll.y)
	ops.transform_pop(gtx.scene)
}

// paint_hbar draws the middle columns' scroll bar along the bottom of
// the middle.
@(private)
paint_hbar :: proc(pc: ^Painter) {
	g, gtx := pc.g, pc.gtx
	geo := &g.geo
	id := ui.id_mix(pc.id, AREA_HBAR)
	size := ops.Size{geo.mid_w, geo.body.h}
	ops.transform_push(gtx.scene, ops.translate(geo.mid_x, geo.body.y))
	ui.scroll_bar_paint(gtx, id, .Horizontal, size, g.place.mid_w, g.scroll.x)
	ops.transform_pop(gtx.scene)
}

// paint_outline strokes the grid's edge, in the focus colour too while
// it has focus by the keyboard: around the header and the foot here,
// the body's sides beside the rows (paint_side).
@(private)
paint_outline :: proc(pc: ^Painter) {
	st, geo, o := pc.st, &pc.g.geo, pc.gtx.scene
	bottom := geo.body.y + geo.body.h
	bands := [2]ops.Rect {
		{0, 0, geo.size.x, geo.body.y},
		{0, bottom, geo.size.x, geo.size.y - bottom},
	}
	edge := ops.Round_Rect{{0.5, 0.5, geo.size.x - 1, geo.size.y - 1}, st.radius}
	ring := ops.Round_Rect{{2, 2, geo.size.x - 4, geo.size.y - 4}, max(st.radius - 1, 0)}
	for band in bands {
		if band.h <= 0 {
			continue
		}
		ops.clip_push(o, band)
		if ui.painted(st.border) {
			ops.stroke(o, edge, st.border, {width = 1})
		}
		if ring_shows(pc) {
			ops.stroke(o, ring, st.focus, {width = 2})
		}
		ops.clip_pop(o)
	}
}

// grid_semantics declares the grid: its rows counted with the header
// (unknown while a paged count is), its visible columns, and the cell
// the keyboard is on as the active descendant.
@(private)
grid_semantics :: proc(pc: ^Painter, label: string) {
	g := pc.g
	rows := i32(g.geo.items) + 1
	if pc.src.paged != nil && g.pages.kind == .Unknown {
		rows = -1
	}
	active: ops.Area_Id
	c := g.cursor
	if c.item < 0 {
		active = ui.id_mix(pc.id, AREA_HEADER + u64(max(c.col, 0)))
	} else if c.col >= 0 && c.item >= g.geo.first && c.item < g.geo.last {
		it := item_at(g, pc.src, c.item)
		active = ui.id_mix(row_id(pc, it, c.item), u64(c.col) + 1)
	}
	ui.container_semantics(
		pc.gtx,
		{
			role = .Grid,
			label = ui.frame_string(pc.gtx, label),
			row_count = rows,
			col_count = i32(len(g.place.places)),
			active_descendant = active,
		},
	)
}
