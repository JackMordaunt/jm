package datagrid

import "jm:ui"

// The keyboard: the grid is one Tab stop, and inside it a cursor walks
// the cells, the header row above the first row (item -1).
//
//	Arrows                 a cell at a time; Shift extends the range
//	Home, End              the row's first or last cell
//	Cmd/Ctrl+Home, End     the first or last row (Cmd+Up and Down too)
//	Page Up, Page Down     a view of rows
//	Enter                  activate the row; on a header, sort by it
//	Space                  select the row or not; on a header, sort
//	Shift+Enter            on a header, add it to the sort
//	Alt+Down               on a header, ask for its filter
//	Cmd/Ctrl+A             select every row
//	Cmd/Ctrl+C             copy the range, the selected rows or the cell
//	Cmd/Ctrl+Shift+C       the same with the column titles first
//	Escape                 select nothing

// handle_key applies one key: one that moves the cursor, else one that
// acts.
@(private)
handle_key :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, src: Source, e: ui.Event, ev: ^Events) {
	if !move_key(g, src, e, ev) {
		act_on_key(gtx, g, cols, src, e, ev)
	}
}

// move_key applies a key that moves the cursor and reports whether e was
// one. Cmd or Ctrl jumps to an end, Shift extends the range.
@(private)
move_key :: proc(g: ^Grid, src: Source, e: ui.Event, ev: ^Events) -> bool {
	jump := ui.SHORTCUT in e.mods || .Ctrl in e.mods
	extend := .Shift in e.mods
	#partial switch e.key {
	case .Up, .Down:
		vertical_key(g, src, e, jump, extend, ev)
	case .Left, .Right:
		step_col(g, -1 if e.key == .Left else 1, jump, extend)
	case .Home, .End:
		ends_key(g, src, e.key == .Home, jump, extend, ev)
	case .Page_Up, .Page_Down:
		rows := max(int(g.geo.body.h / max(g.geo.row_h, 1)) - 1, 1)
		move_to(g, src, g.cursor.item + (rows if e.key == .Page_Down else -rows), extend, ev)
	case:
		return false
	}
	return true
}

// vertical_key is Up or Down: a row, or with jump the first or last;
// Alt+Down on a header asks for its filter.
@(private)
vertical_key :: proc(g: ^Grid, src: Source, e: ui.Event, jump, extend: bool, ev: ^Events) {
	if e.key == .Up {
		move_to(g, src, 0 if jump else g.cursor.item - 1, extend, ev)
		return
	}
	if .Alt in e.mods && g.cursor.item < 0 {
		ev.filter_asked = g.cursor.col
		return
	}
	move_to(g, src, g.geo.items - 1 if jump else g.cursor.item + 1, extend, ev)
}

// ends_key is Home (home) or End: the row's first or last cell, or with
// jump the first or last row.
@(private)
ends_key :: proc(g: ^Grid, src: Source, home, jump, extend: bool, ev: ^Events) {
	if jump {
		move_to(g, src, 0 if home else g.geo.items - 1, extend, ev)
	} else {
		step_col(g, -1 if home else 1, true, extend)
	}
}

// act_on_key applies a key that acts rather than moves.
@(private)
act_on_key :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, src: Source, e: ui.Event, ev: ^Events) {
	cmd := ui.SHORTCUT in e.mods
	#partial switch e.key {
	case .Enter, .Space:
		enter(g, cols, src, e, ev)
	case .A:
		if cmd {
			select_all(g, src)
			ev.selection = true
		}
	case .C:
		if cmd {
			ev.copied = copy_cells(gtx, g, cols, src, .Shift in e.mods)
		}
	case .Escape:
		ev.selection = !selection_empty(&g.sel)
		selection_clear(&g.sel)
		g.anchor = g.cursor
	}
}

// enter is Enter or Space at the cursor: on a header it sorts, on a group
// it shuts or opens it, on a failed row it retries; on a row Enter
// activates and Space toggles its selection.
@(private)
enter :: proc(g: ^Grid, cols: []Column, src: Source, e: ui.Event, ev: ^Events) {
	c := g.cursor
	if c.item < 0 {
		if c.col >= 0 && !cols[c.col].no_sort {
			view_sort_cycle(&g.view, c.col, .Shift in e.mods)
			ev.sorted, ev.view = true, true
		}
		return
	}
	it := item_at(g, src, c.item)
	switch {
	case it.group >= 0:
		toggle_group(g, c.item)
	case it.state == .Failed:
		page := c.item / g.pages.page_size
		pages_retry(&g.pages, page, page + 1)
	case !has_row(it):
	case:
		enter_row(g, c, it, e.key == .Space, ev)
	}
}

// enter_row is Enter on a row, which activates it, or Space (space),
// which toggles its selection.
@(private)
enter_row :: proc(g: ^Grid, c: Cell_At, it: Item, space: bool, ev: ^Events) {
	if !space {
		ev.activated, ev.row = true, Row_Ref{c.item, it.row, it.key, it.name}
		return
	}
	selection_toggle(&g.sel, it.key, it.name)
	g.anchor = c
	ev.selection = true
}

// move_to moves the cursor to item (clamped: -1 is the header), keeping
// its column, and scrolls it into view; extend selects the rows from the
// anchor to it.
@(private)
move_to :: proc(g: ^Grid, src: Source, item: int, extend: bool, ev: ^Events) {
	to := clamp(item, -1, g.geo.items - 1)
	it := item_at(g, src, to)
	g.cursor.item, g.cursor.key = to, it.key
	switch {
	case !extend:
		g.anchor = g.cursor
		if to >= 0 && has_row(it) {
			selection_anchor(&g.sel, it.key)
		}
	case to >= 0:
		if g.anchor.item < 0 {
			g.anchor = g.cursor
			selection_anchor(&g.sel, it.key)
		}
		select_range(g, src, g.anchor.item, to)
		ev.selection = true
	}
	reveal(g)
}

// step_col moves the cursor a column left (dir -1) or right, or with all
// to the first or last column; extend keeps the anchor, so the range of
// cells grows.
@(private)
step_col :: proc(g: ^Grid, dir: int, all: bool, extend: bool) {
	n := len(g.place.places)
	if n == 0 {
		return
	}
	at := max(place_of(&g.place, g.cursor.col), 0)
	switch {
	case all:
		at = 0 if dir < 0 else n - 1
	case:
		at = clamp(at + dir, 0, n - 1)
	}
	g.cursor.col = g.place.places[at].col
	if !extend {
		g.anchor = g.cursor
	}
	reveal(g)
}

// reveal scrolls the least that shows the cursor's cell: its row down
// the body, its column across the middle (a pinned one always shows).
reveal :: proc(g: ^Grid) {
	geo := &g.geo
	if g.cursor.item >= 0 {
		top := f32(heights_top(&g.heights, g.cursor.item))
		h := f32(heights_of(&g.heights, g.cursor.item))
		if top < g.scroll.y {
			g.scroll.y = top
		} else if top + h > g.scroll.y + geo.body.h {
			g.scroll.y = top + h - geo.body.h
		}
	}
	if at := place_of(&g.place, g.cursor.col); at >= 0 {
		pl := g.place.places[at]
		if pl.pin == .None {
			if pl.x < g.scroll.x {
				g.scroll.x = pl.x
			} else if pl.x + pl.w > g.scroll.x + geo.mid_w {
				g.scroll.x = pl.x + pl.w - geo.mid_w
			}
		}
	}
	clamp_scroll(g)
}

// select_all selects every row: in a client grid, every row the filters
// and search keep; in a paged one, every row that matches, loaded or not
// (Selection.all), which a caller acting on it asks its source for.
select_all :: proc(g: ^Grid, src: Source) {
	if src.paged == nil {
		// Explicit, so the keys are there to act on and survive a filter.
		select_loaded(g, src)
		return
	}
	selection_all(&g.sel, g.match)
}

// select_loaded selects every row the grid holds, explicitly: in a client
// grid every row the filters and search keep, in a paged one the rows of
// the current query that have arrived. Unlike select_all it names its
// rows, so an action on them needs nothing more from the source.
select_loaded :: proc(g: ^Grid, src: Source) {
	selection_clear(&g.sel)
	clear(&g.keys)
	clear(&g.names)
	if src.paged == nil {
		for r in g.order.rows {
			append(&g.keys, source_key(src, r))
		}
	} else {
		for e in g.pages.entries {
			if e.query != g.pages.query || e.state != .Ready {
				continue
			}
			for r in e.rows {
				append(&g.keys, row_key(r.key))
				append(&g.names, r.key)
			}
		}
	}
	selection_range(&g.sel, g.keys[:], g.names[:])
}
