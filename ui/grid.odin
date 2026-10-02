package ui

import "core:slice"
import "jm:ui/ops"

// Grid lays children in rows across columns sized from their cells, as
// CSS grid sizes tracks: every cell is measured first, then each
// column takes its widest cell's width (or its fixed width), and the
// width left over is shared by the columns that grow. A table whose
// columns must fit their content is one of these.
//
//	g := grid_open(gtx, {{}, {grow = 1}}, column_gap = 8); defer close(&g)
//	label(gtx, "Name"); label(gtx, "Ada")    // row 1
//	label(gtx, "Role"); label(gtx, "Author") // row 2
//
// Children fill the columns left to right, a new row after the last
// column; grid_span gives the next child a row of its own across every
// column. Each cell is recorded into a macro and laid out before the
// columns are known, at its own width: it cannot stretch to its column,
// so its track's align places it across the column and the grid's align
// down its row, and a paint proc draws what spans whole cells or rows
// (fills, rules) from the resolved lines, under the cells.

// Track is one grid column's sizing. A track with width is exactly that
// wide and offers its cells that width. Any other takes its widest
// cell's width, bounded by min and max (max 0 is no bound); with grow it
// also takes a share of the width the columns leave over, in proportion
// to grow (CSS minmax(max-content, Nfr)), or, with collapse, it may
// shrink below its widest cell down to min when the width runs out
// (minmax(min, Nfr)), its cells clipped to it. A capped growing track
// keeps the share it is denied; nothing redistributes it. The shares
// follow CSS Grid Layout 1, 11.7 "Expand Flexible Tracks" and 11.7.1
// "Find the Size of an fr".
Track :: struct {
	width:    f32,
	grow:     f32,
	min, max: f32,
	collapse: bool,
	align:    Align, // Start, Center or End across the column
}

// Grid_Lines are a closed grid's resolved tracks, in its own space: each
// column's x and width, each row's y and height, whether a row is one
// spanning child (grid_span), and the grid's size.
Grid_Lines :: struct {
	col_x, col_w: []f32,
	row_y, row_h: []f32,
	spans:        []bool,
	size:         ops.Size,
}

// Grid_Paint draws under a grid's cells once its lines are known: row
// fills, rules, a hover, from lines. It may read events and lay input
// areas, as a box's paint does.
Grid_Paint :: proc(gtx: ^Ctx, id: ops.Area_Id, lines: Grid_Lines, user: rawptr)

Grid :: struct {
	gtx:   ^Ctx,
	index: int,
}

// grid_open opens a grid of columns, column_gap apart, rows row_gap
// apart, each cell placed down its row by align (Start, Center or End),
// and paint, when set, called with user under the cells.
grid_open :: proc(
	gtx: ^Ctx,
	columns: []Track,
	column_gap: f32 = 0,
	row_gap: f32 = 0,
	align := Align.Start,
	paint: Grid_Paint = nil,
	user: rawptr = nil,
	key: u64 = 0,
	loc := #caller_location,
) -> Grid {
	p := widget_open(gtx, key, loc)
	c := Container {
		kind       = .Grid,
		gap        = column_gap,
		line_gap   = row_gap,
		align      = align,
		deferred   = true,
		tracks     = slice.clone(columns, gtx.allocator),
		grid_paint = paint,
	}
	c.style.user = user
	return {gtx, container_push(gtx, c, p)}
}

// grid_span gives the innermost grid's next child a row of its own,
// across every column and offered the grid's whole width: a group
// heading in a table. Outside a grid it does nothing.
grid_span :: proc(gtx: ^Ctx) {
	if c := innermost(gtx.layout); c != nil && c.kind == .Grid {
		c.span_next = true
	}
}

// grid_child_constraints is what the grid's next cell is offered: its
// fixed width, else up to its track's max, else unbounded; a spanning
// child the grid's own width.
@(private)
grid_child_constraints :: proc(c: ^Container) -> Constraints {
	if c.span_next || len(c.tracks) == 0 {
		return {max = {c.cs.max.x, INF}}
	}
	t := c.tracks[c.column]
	switch {
	case t.width > 0:
		return {max = {t.width, INF}}
	case t.max > 0:
		return {max = {t.max, INF}}
	}
	return {max = {INF, INF}}
}

// grid_add records a closed cell and moves to the next column.
@(private)
grid_add :: proc(l: ^Layout, c: ^Container, k: Child) {
	k := k
	k.span = c.span_next
	if k.span {
		c.span_next = false
		c.column = 0
	} else if len(c.tracks) > 0 {
		c.column = (c.column + 1) % len(c.tracks)
	}
	c.count += 1
	append(&l.children, k)
}

// Grid_Cell is where a child sits: its row, and its column (-1 spanning).
@(private = "file")
Grid_Cell :: struct {
	row, col: int,
}

// grid_cells assigns each child its row and column and counts the rows.
@(private = "file")
grid_cells :: proc(kids: []Child, n: int, allocator := context.allocator) -> (cells: []Grid_Cell, rows: int) {
	cells = make([]Grid_Cell, len(kids), allocator)
	col := 0
	for k, i in kids {
		if k.span || n == 0 {
			if col > 0 {
				rows += 1
			}
			cells[i] = {rows, -1}
			rows += 1
			col = 0
			continue
		}
		cells[i] = {rows, col}
		col += 1
		if col == n {
			rows += 1
			col = 0
		}
	}
	if col > 0 {
		rows += 1
	}
	return
}

// resolve_tracks sizes each track from its widest cell, content[i], within
// avail (gaps already taken out), as CSS grid's track sizing does for
// these track kinds: bases first, then the space left over shared among
// growing tracks by their grow, a track whose base exceeds its share
// keeping its base and leaving the rest to the others.
resolve_tracks :: proc(tracks: []Track, content: []f32, avail: f32, allocator := context.allocator) -> []f32 {
	w := make([]f32, len(tracks), allocator)
	frozen := make([]bool, len(tracks), context.temp_allocator)
	for t, i in tracks {
		base := t.width
		if base <= 0 {
			base = t.collapse ? 0 : content[i]
			base = max(base, t.min)
			if t.max > 0 {
				base = min(base, max(t.max, t.min))
			}
		}
		w[i] = base
		frozen[i] = t.width > 0 || t.grow <= 0
	}
	if !is_finite(avail) {
		return w
	}
	// Find the size of one share: the space not held by frozen tracks
	// over the unfrozen grow; freeze any whose base exceeds its share,
	// and again until none does.
	share: f32
	for {
		held, grow: f32
		for t, i in tracks {
			if frozen[i] {
				held += w[i]
			} else {
				grow += t.grow
			}
		}
		if grow <= 0 {
			return w
		}
		share = max(avail - held, 0) / grow
		froze := false
		for t, i in tracks {
			if !frozen[i] && w[i] > share * t.grow {
				frozen[i] = true
				froze = true
			}
		}
		if !froze {
			break
		}
	}
	for t, i in tracks {
		if frozen[i] {
			continue
		}
		w[i] = share * t.grow
		if t.max > 0 {
			w[i] = min(w[i], max(t.max, t.min))
		}
	}
	return w
}

// grid_close resolves the columns and rows, paints under them and places
// every cell.
grid_close :: proc(g: ^Grid) {
	gtx := g.gtx
	if g.index < 0 {
		return
	}
	l := gtx.layout
	c := container_at(l, g.index)
	kids := children_of(l, c)
	n := len(c.tracks)
	cells, rows := grid_cells(kids, n, gtx.allocator)
	content := make([]f32, n, gtx.allocator)
	for k, i in kids {
		if col := cells[i].col; col >= 0 {
			content[col] = max(content[col], k.size.x)
		}
	}
	gaps := c.gap * f32(max(n - 1, 0))
	avail := is_finite(c.cs.max.x) ? c.cs.max.x : c.cs.min.x
	lines := Grid_Lines {
		col_w = resolve_tracks(c.tracks, content, avail - gaps, gtx.allocator),
		col_x = make([]f32, n, gtx.allocator),
		row_y = make([]f32, rows, gtx.allocator),
		row_h = make([]f32, rows, gtx.allocator),
		spans = make([]bool, rows, gtx.allocator),
	}
	x: f32
	for w, i in lines.col_w {
		lines.col_x[i] = x
		x += w + (i < n - 1 ? c.gap : 0)
	}
	width := x
	for k, i in kids {
		at := cells[i]
		lines.row_h[at.row] = max(lines.row_h[at.row], k.size.y)
		if at.col < 0 {
			lines.spans[at.row] = true
			width = max(width, k.size.x)
		}
	}
	y: f32
	for h, r in lines.row_h {
		lines.row_y[r] = y
		y += h + (r < rows - 1 ? c.line_gap : 0)
	}
	size := constrain(c.cs, {width, y})
	lines.size = size
	if c.grid_paint != nil {
		c.grid_paint(gtx, c.place.id, lines, c.style.user)
	}
	baseline := grid_place(gtx, c, kids, cells, lines)
	done := container_pop(gtx, g.index)
	cover_close(gtx, &done)
	widget_close(gtx, &done.place, {size, baseline})
	g.index = -1
}

// grid_place calls each cell's macro at its place in lines, clipping a
// cell wider than its column to it, and returns the first row's first
// baseline.
@(private = "file")
grid_place :: proc(gtx: ^Ctx, c: ^Container, kids: []Child, cells: []Grid_Cell, lines: Grid_Lines) -> (baseline: f32) {
	for k, i in kids {
		at := cells[i]
		x, w: f32 = 0, lines.size.x
		align := Align.Start
		if at.col >= 0 {
			x, w = lines.col_x[at.col], lines.col_w[at.col]
			align = c.tracks[at.col].align
		}
		h := lines.row_h[at.row]
		pos := ops.Point{x + place_across(align, w, k.size.x), lines.row_y[at.row] + place_across(c.align, h, k.size.y)}
		clipped := k.size.x > w + 1e-3
		if clipped {
			ops.clip_push(gtx.scene, ops.Rect{x, lines.row_y[at.row], w, h})
		}
		ops.transform_push(gtx.scene, ops.translate(pos.x, pos.y))
		ops.call(gtx.scene, k.macro)
		ops.transform_pop(gtx.scene)
		if clipped {
			ops.clip_pop(gtx.scene)
		}
		if baseline == 0 && k.baseline > 0 && at.row == 0 {
			baseline = k.baseline + pos.y
		}
	}
	return
}

// place_across is where a child size long starts in room: Center and End
// move it, anything else keeps it at the start. A child larger than room
// starts at the start.
@(private = "file")
place_across :: proc(a: Align, room, size: f32) -> f32 {
	free := max(room - size, 0)
	#partial switch a {
	case .Center:
		return free / 2
	case .End:
		return free
	}
	return 0
}
