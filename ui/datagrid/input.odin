package datagrid

import "jm:ui"
import "jm:ui/ops"

// The grid's input areas, mixed into the grid's id. The body's area is
// the grid's own id, so the node a reader sees and the area that holds
// focus are one.
AREA_SCROLL :: 1 // the whole grid, for the wheel
AREA_VBAR   :: 2
AREA_HBAR   :: 3
AREA_HEADER :: 0x100 // + the column
AREA_RESIZE :: 0x10000 // + the column

// DRAG_SLOP is how far a press on a header travels before it moves the
// column instead of sorting by it.
DRAG_SLOP :: 4

// RESIZE_GRIP is the width of the strip at a header's right edge that
// drags its width.
RESIZE_GRIP :: 8

// handle_input applies last frame's input: the wheel and the bars, the
// headers and their edges, then the body's pointer and keys.
@(private)
handle_input :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Source,
	skin: ^Skin,
	id: ops.Area_Id,
	ev: ^Events,
) {
	wheel(gtx, g, id)
	geo := &g.geo
	g.scroll.y = ui.scroll_bar_handle(
		gtx,
		ui.id_mix(id, AREA_VBAR),
		.Vertical,
		{geo.size.x, geo.body.h},
		f32(geo.content),
		g.scroll.y,
	)
	g.scroll.x = ui.scroll_bar_handle(
		gtx,
		ui.id_mix(id, AREA_HBAR),
		.Horizontal,
		{geo.mid_w, geo.body.h},
		g.place.mid_w,
		g.scroll.x,
	)
	for pl in g.place.places {
		header_events(gtx, g, cols, src, id, pl.col, ev)
		resize_events(gtx, g, cols, src, skin, id, pl.col, ev)
	}
	body_events(gtx, g, cols, src, id, ev)
}

// wheel scrolls by the wheel: rows down and up, columns sideways with a
// horizontal wheel or Shift.
@(private)
wheel :: proc(gtx: ^ui.Ctx, g: ^Grid, id: ops.Area_Id) {
	for e in ui.events(gtx, ui.id_mix(id, AREA_SCROLL)) {
		if e.kind != .Scroll {
			continue
		}
		if .Shift in e.mods && e.scroll.x == 0 {
			g.scroll.x += e.scroll.y * ui.SCROLL_STEP
		} else {
			g.scroll.y += e.scroll.y * ui.SCROLL_STEP
			g.scroll.x += e.scroll.x * ui.SCROLL_STEP
		}
	}
	clamp_scroll(g)
}

// header_events is a header's press, travel and release: a click sorts
// by it (Shift adding it to the sort), a press that travels moves it.
@(private)
header_events :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Source,
	id: ops.Area_Id,
	col: int,
	ev: ^Events,
) {
	for e in ui.events(gtx, ui.id_mix(id, AREA_HEADER + u64(col))) {
		#partial switch e.kind {
		case .Enter:
			g.hover_head = col
		case .Leave:
			if g.hover_head == col {
				g.hover_head = -1
			}
		case .Press:
			if e.button == .Left {
				g.drag = {
					kind  = .Header,
					col   = col,
					x     = e.pos.x,
					shift = .Shift in e.mods,
				}
			}
		case .Move:
			if g.drag.col == col && (g.drag.kind == .Header || g.drag.kind == .Move) {
				g.drag.moved += e.travel.x
				g.drag.x = e.pos.x
				if abs(g.drag.moved) > DRAG_SLOP {
					g.drag.kind = .Move
				}
			}
		case .Release:
			header_release(g, cols, col, ev)
		case .Cancel:
			g.drag = {}
		}
	}
}

// header_release ends a press on header col: a click sorts, a move drops
// the column where the pointer let go.
@(private)
header_release :: proc(g: ^Grid, cols: []Column, col: int, ev: ^Events) {
	d := g.drag
	g.drag = {}
	if d.col != col {
		return
	}
	switch d.kind {
	case .Header:
		if !cols[col].no_sort {
			view_sort_cycle(&g.view, col, d.shift)
			g.cursor = {
				item = -1,
				col  = col,
			}
			ev.sorted, ev.view = true, true
		}
	case .Move:
		if to, ok := drop_index(g, col, d.x); ok {
			move_column(g.view.order[:], col, to)
			ev.view = true
		}
	case .None, .Resize, .Select:
	}
}

// drop_index is where in the view's order column col goes when dropped
// at x: before the first column of its own pin group whose middle lies
// past x, or after the group's last.
@(private)
drop_index :: proc(g: ^Grid, col: int, x: f32) -> (to: int, ok: bool) {
	at := place_of(&g.place, col)
	if at < 0 {
		return
	}
	pin := g.place.places[at].pin
	last := -1
	for pl in g.place.places {
		if pl.pin != pin {
			continue
		}
		if place_screen_x(g, pl) + pl.w / 2 > x {
			return order_index(g, pl.col), true
		}
		last = pl.col
	}
	return order_index(g, last) + 1, last >= 0
}

@(private)
order_index :: proc(g: ^Grid, col: int) -> int {
	for c, i in g.view.order {
		if c == col {
			return i
		}
	}
	return len(g.view.order)
}

// place_screen_x is where place pl starts in the grid's space this
// frame.
place_screen_x :: proc(g: ^Grid, pl: Place) -> f32 {
	switch pl.pin {
	case .Left:
		return pl.x
	case .Right:
		return g.geo.size.x - g.place.right_w + pl.x
	case .None:
	}
	return g.geo.mid_x + pl.x - g.scroll.x
}

// resize_events is a header edge's drag, which sets the column's width,
// and its double click, which fits the column to its widest cell.
@(private)
resize_events :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Source,
	skin: ^Skin,
	id: ops.Area_Id,
	col: int,
	ev: ^Events,
) {
	for e in ui.events(gtx, ui.id_mix(id, AREA_RESIZE + u64(col))) {
		#partial switch e.kind {
		case .Enter:
			g.hover_grip = col
		case .Leave:
			if g.hover_grip == col {
				g.hover_grip = -1
			}
		case .Press:
			if e.clicks >= 2 {
				g.view.cols[col].width = clamp_width(
					cols[col],
					fit_width(gtx, g, cols, src, skin, col),
				)
				g.drag = {}
				ev.view = true
				continue
			}
			at := place_of(&g.place, col)
			w := g.place.places[at].w if at >= 0 else DEFAULT_WIDTH
			g.drag = {
				kind  = .Resize,
				col   = col,
				start = w,
			}
		case .Move:
			if g.drag.kind == .Resize && g.drag.col == col {
				g.drag.moved += e.travel.x
				g.view.cols[col].width = clamp_width(cols[col], g.drag.start + g.drag.moved)
			}
		case .Release, .Cancel:
			if g.drag.kind == .Resize && g.drag.col == col {
				g.drag = {}
				ev.view = true
			}
		}
	}
}

// hit is the item and column under p, in the grid's space: item -1 over
// the header, -2 below the last row; col -1 past the last column.
hit :: proc(g: ^Grid, p: ops.Point) -> (item, col: int) {
	geo := &g.geo
	item, col = -2, -1
	if p.y < geo.body.y {
		item = -1
	} else {
		y := f64(p.y - geo.body.y + g.scroll.y)
		if y < geo.content {
			item = heights_at(&g.heights, y)
		}
	}
	for pl in g.place.places {
		x := place_screen_x(g, pl)
		in_mid := pl.pin != .None || (p.x >= geo.mid_x && p.x < geo.mid_x + geo.mid_w)
		if in_mid && p.x >= x && p.x < x + pl.w {
			col = pl.col
			if pl.pin != .None {
				break // a pinned column lies over the middle
			}
		}
	}
	return
}

// body_events is the body's input: focus, presses that select and
// activate, a sweep that extends, the pointer's row, and keys.
@(private)
body_events :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Source,
	id: ops.Area_Id,
	ev: ^Events,
) {
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Focus:
			g.focused = true
			if g.cursor.col < 0 && len(g.place.places) > 0 {
				g.cursor.col = g.place.places[0].col
			}
		case .Blur:
			g.focused = false
		case .Press:
			press(gtx, g, cols, src, e, ev)
		case .Move:
			item, _ := hit(g, e.pos)
			g.hover = item if item >= 0 else -1
			if g.drag.kind == .Select {
				sweep(g, src, e.pos, ev)
			}
		case .Release, .Cancel:
			if g.drag.kind == .Select {
				g.drag = {}
			}
		case .Leave:
			g.hover = -1
		case .Key:
			handle_key(gtx, g, cols, src, e, ev)
		}
	}
}

// press is a press in the body: the right button asks for a menu; on a
// group header it shuts or opens the group, on a failed row it retries;
// on a row it moves the cursor there and selects: alone, toggled with
// Cmd or Ctrl, as a range from the anchor with Shift. A double click
// activates the row.
@(private)
press :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, src: Source, e: ui.Event, ev: ^Events) {
	item, col := hit(g, e.pos)
	if item < 0 {
		return
	}
	if col < 0 && len(g.place.places) > 0 {
		col = g.place.places[len(g.place.places) - 1].col
	}
	it := item_at(g, src, item)
	switch {
	case it.group >= 0:
		g.cursor = {
			item = item,
			col  = col,
		}
		toggle_group(g, item)
		return
	case it.state == .Failed:
		pages_retry(&g.pages, item / g.pages.page_size, item / g.pages.page_size + 1)
		return
	case it.state != .Ready && it.state != .Stale:
		return
	}
	ref := Row_Ref{item, it.row, it.key, it.name}
	if e.button == .Right {
		if !selected(&g.sel, it.key) {
			selection_only(&g.sel, it.key, it.name)
			ev.selection = true
		}
		g.cursor = {item, col, it.key}
		ev.context_menu, ev.row, ev.at, ev.col = true, ref, e.pos, col
		return
	}
	if e.button != .Left {
		return
	}
	select_at(g, src, Cell_At{item, col, it.key}, it.name, e.mods)
	ev.selection = true
	g.drag = {
		kind = .Select,
	}
	if e.clicks >= 2 && e.mods == {} {
		ev.activated, ev.row = true, ref
	}
}

// select_at moves the cursor to at and selects its row by mods: Shift
// extends from the anchor, Cmd or Ctrl toggles, nothing selects it alone.
@(private)
select_at :: proc(g: ^Grid, src: Source, at: Cell_At, name: string, mods: ui.Mods) {
	g.cursor = at
	switch {
	case .Shift in mods:
		select_range(g, src, g.anchor.item, at.item)
	case ui.SHORTCUT in mods:
		selection_toggle(&g.sel, at.key, name)
		g.anchor = at
	case:
		selection_only(&g.sel, at.key, name)
		g.anchor = at
	}
}

// select_range makes the selection the anchor's base plus every row from
// item a to item b, in either order, that the grid holds; with no anchor
// (a < 0) the range is b alone.
@(private)
select_range :: proc(g: ^Grid, src: Source, a, b: int) {
	clear(&g.keys)
	clear(&g.names)
	start := a if a >= 0 else b
	for i in min(start, b) ..= max(start, b) {
		it := item_at(g, src, i)
		if it.group < 0 && (it.state == .Ready || it.state == .Stale) {
			append(&g.keys, it.key)
			append(&g.names, it.name)
		}
	}
	selection_range(&g.sel, g.keys[:], g.names[:])
}

// sweep extends a selection being swept with the pointer to the row
// under p.
@(private)
sweep :: proc(g: ^Grid, src: Source, p: ops.Point, ev: ^Events) {
	item, col := hit(g, p)
	if item < 0 || item == g.cursor.item {
		return
	}
	it := item_at(g, src, item)
	if it.group >= 0 || (it.state != .Ready && it.state != .Stale) {
		return
	}
	g.cursor = {item, col if col >= 0 else g.cursor.col, it.key}
	select_range(g, src, g.anchor.item, item)
	ev.selection = true
}

// toggle_group shuts the group whose header stands at item, or opens it.
@(private)
toggle_group :: proc(g: ^Grid, item: int) {
	it := g.order.items[item]
	if it >= 0 {
		return
	}
	name := group_name(&g.order, g.order.groups[-it - 1])
	if shut, ok := g.collapsed[name]; ok {
		g.collapsed[name] = !shut
		return
	}
	g.collapsed[clone_to(name, g.allocator)] = true
}
