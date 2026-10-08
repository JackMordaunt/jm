package datagrid

import "core:strings"
import "jm:ui"

// Copy: the cells a copy takes go to the clipboard as tab-separated
// text, which Sheets and Excel paste into cells. An export of the whole
// view is not the grid's: jm:ui/datagrid/export writes one over it.

// copy_cells puts on the clipboard, as TSV: the range of cells from the
// anchor to the cursor when it spans more than one; else the selected
// rows the grid holds, every column, when more than the cursor's own row
// is selected; else the cursor's cell, as a click then a copy means.
// header puts the columns' titles first. It returns the cells copied.
copy_cells :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, src: Rows, header := false) -> int {
	rows, places := copy_range(g, src)
	text, n := copy_text(gtx, g, cols, src, rows, places, header)
	if len(rows) == 1 && len(places) == 1 && !header {
		// One cell pastes as text, not as a row of one.
		if it := item_at(g, src, rows[0]); has_row(it) {
			text = cell_text(gtx, cols, it, rows[0], places[0])
		}
	}
	if n > 0 {
		ui.clipboard_write(gtx, text)
	}
	return n
}

// copy_text is the cells of rows (items) and places (columns) as TSV, the
// columns' titles first with header, and how many cells it holds.
@(private)
copy_text :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	cols: []Column,
	src: Rows,
	rows, places: []int,
	header: bool,
) -> (
	text: string,
	n: int,
) {
	b := strings.builder_make(gtx.allocator)
	fields := make([dynamic]string, gtx.allocator)
	if header {
		for p in places {
			append(&fields, cols[p].title)
		}
		write_record(&b, TSV, fields[:])
	}
	for item in rows {
		it := item_at(g, src, item)
		if !has_row(it) {
			continue
		}
		clear(&fields)
		for p in places {
			append(&fields, cell_text(gtx, cols, it, item, p))
		}
		write_record(&b, TSV, fields[:])
		n += len(fields)
	}
	return strings.to_string(b), n
}

// copy_range is the rows and columns a copy takes, in display order: the
// block from the anchor to the cursor, else the selected rows, else the
// cursor's cell.
@(private)
copy_range :: proc(g: ^Grid, src: Rows) -> (rows: []int, places: []int) {
	a, c := g.anchor, g.cursor
	switch {
	case is_block(a, c):
		return block_range(g, a, c)
	case more_than_cursor(&g.sel, c.key):
		return selected_range(g, src)
	}
	out := make([dynamic]int, context.temp_allocator)
	cs := make([dynamic]int, context.temp_allocator)
	if c.item >= 0 && c.col >= 0 {
		append(&out, c.item)
		append(&cs, c.col)
	}
	return out[:], cs[:]
}

// is_block reports whether cells a and c, both in rows, span more than
// one cell.
@(private)
is_block :: proc(a, c: Cell_At) -> bool {
	return a.item >= 0 && c.item >= 0 && (a.item != c.item || a.col != c.col)
}

// more_than_cursor reports whether s selects rows besides the cursor's,
// keyed key.
@(private)
more_than_cursor :: proc(s: ^Selection, key: Row_Key) -> bool {
	only_cursor := !s.all && len(s.keys) == 1 && selected(s, key)
	return !selection_empty(s) && !only_cursor
}

// block_range is the rows and columns of the block from cell a to cell c.
@(private)
block_range :: proc(g: ^Grid, a, c: Cell_At) -> (rows: []int, places: []int) {
	out := make([dynamic]int, context.temp_allocator)
	cs := make([dynamic]int, context.temp_allocator)
	pa, pc := max(place_of(&g.place, a.col), 0), max(place_of(&g.place, c.col), 0)
	for i in min(pa, pc) ..= max(pa, pc) {
		append(&cs, g.place.places[i].col)
	}
	for i in min(a.item, c.item) ..= max(a.item, c.item) {
		append(&out, i)
	}
	return out[:], cs[:]
}

// selected_range is the selected rows the grid holds, every column.
@(private)
selected_range :: proc(g: ^Grid, src: Rows) -> (rows: []int, places: []int) {
	out := make([dynamic]int, context.temp_allocator)
	cs := make([dynamic]int, context.temp_allocator)
	for pl in g.place.places {
		append(&cs, pl.col)
	}
	for i in 0 ..< g.geo.items {
		it := item_at(g, src, i)
		if it.state == .Ready && selected(&g.sel, it.key) {

			append(&out, i)
		}
	}
	return out[:], cs[:]
}
