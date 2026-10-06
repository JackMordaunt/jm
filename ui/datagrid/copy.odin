package datagrid

import "core:fmt"
import "core:strings"
import "jm:ui"

// Copy and export. A copy goes to the clipboard as tab-separated text,
// which Sheets and Excel paste into cells; an export is CSV of the
// current view, every visible column but those marked no_export, in the
// current sort and filter, built a chunk a frame so a big one shows its
// progress and can be stopped.

// copy_cells puts on the clipboard, as TSV: the range of cells from the
// anchor to the cursor when it spans more than one; else the selected
// rows the grid holds, every column, when more than the cursor's own row
// is selected; else the cursor's cell, as a click then a copy means.
// header puts the columns' titles first. It returns the cells copied.
copy_cells :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, src: Source, header := false) -> int {
	rows, places := copy_range(g, src)
	text, n := copy_text(gtx, g, cols, src, rows, places, header)
	if len(rows) == 1 && len(places) == 1 && !header {
		// One cell pastes as text, not as a row of one.
		if it := item_at(g, src, rows[0]); has_row(it) {
			text = cell_text(gtx, src, cols, it, rows[0], places[0])
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
	src: Source,
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
		if it.group >= 0 || !has_row(it) {
			continue
		}
		clear(&fields)
		for p in places {
			append(&fields, cell_text(gtx, src, cols, it, item, p))
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
copy_range :: proc(g: ^Grid, src: Source) -> (rows: []int, places: []int) {
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
selected_range :: proc(g: ^Grid, src: Source) -> (rows: []int, places: []int) {
	out := make([dynamic]int, context.temp_allocator)
	cs := make([dynamic]int, context.temp_allocator)
	for pl in g.place.places {
		append(&cs, pl.col)
	}
	for i in 0 ..< g.geo.items {
		it := item_at(g, src, i)
		if it.group < 0 && it.state == .Ready && selected(&g.sel, it.key) {
			append(&out, i)
		}
	}
	return out[:], cs[:]
}

// Export is an export in progress or done: its text so far, how far it
// has got (rows written, the next item or offset), how many rows it
// expects (-1 when unknown), the columns it writes, and for a paged
// source the page size, the keyset cursor and an error that stopped it.
Export :: struct {
	active:  bool,
	done:    bool,
	text:    strings.Builder,
	written: int,
	next:    int,
	total:   int,
	cols:    [dynamic]int,
	limit:   int,
	after:   Cursor,
	keep:    [dynamic]u8, // what after points into
	error:   string,
	attempt: int,
}

// EXPORT_CHUNK is the rows a client export writes a frame; EXPORT_PAGE
// the rows a paged export asks for at once.
EXPORT_CHUNK :: 20_000
EXPORT_PAGE  :: 1000

// export_start begins exporting g's current view as CSV: the titles of
// the visible columns not marked no_export, then a chunk of rows a frame
// (export_step, which grid calls), Events.exported on the frame it ends.
export_start :: proc(g: ^Grid, cols: []Column, src: Source) {
	x := &g.export
	export_destroy(x)
	x.text = strings.builder_make(g.allocator)
	x.cols = make([dynamic]int, g.allocator)
	x.keep = make([dynamic]u8, g.allocator)
	for pl in g.place.places {
		if !cols[pl.col].no_export {
			append(&x.cols, pl.col)
		}
	}
	titles := make([dynamic]string, context.temp_allocator)
	for c in x.cols {
		append(&titles, cols[c].title)
	}
	write_record(&x.text, CSV, titles[:])
	x.active = true
	x.limit = EXPORT_PAGE
	x.total =
		len(g.order.rows) if src.paged == nil else (g.pages.count if g.pages.kind != .Unknown else -1)
}

// export_cancel stops an export; what it wrote is dropped.
export_cancel :: proc(g: ^Grid) {
	export_destroy(&g.export)
}

// export_destroy drops an export's text.
export_destroy :: proc(x: ^Export) {
	alloc := x.text.buf.allocator
	delete(x.after.values, alloc)
	delete(x.error, alloc)
	strings.builder_destroy(&x.text)
	delete(x.cols)
	delete(x.keep)
	x^ = {}
}

// export_progress is how far an export has got, in rows, and of how many
// (-1 when the source does not say).
export_progress :: proc(g: ^Grid) -> (written, total: int) {
	return g.export.written, g.export.total
}

// export_step writes the next chunk of an export.
@(private)
export_step :: proc(gtx: ^ui.Ctx, g: ^Grid, cols: []Column, src: Source, ev: ^Events) {
	x := &g.export
	if !x.active || x.done {
		return
	}
	if src.paged != nil {
		export_page(gtx, g, cols, src, ev)
		return
	}
	if export_rows(g, cols, src) {
		ev.exported = true
	}
}

// export_rows writes a client export's next EXPORT_CHUNK rows and reports
// whether that was the last of them.
@(private)
export_rows :: proc(g: ^Grid, cols: []Column, src: Source) -> bool {
	x := &g.export
	fields := make([dynamic]string, 0, len(x.cols), context.temp_allocator)
	end := min(x.next + EXPORT_CHUNK, len(g.order.rows))
	for r in g.order.rows[x.next:end] {
		clear(&fields)
		for c in x.cols {
			if cols[c].row_number {
				append(&fields, fmt.tprint(x.written + 1))
			} else {
				append(&fields, source_text(src, r, c))
			}
		}
		write_record(&x.text, CSV, fields[:])
		x.written += 1
	}
	x.next = end
	x.done = x.next >= len(g.order.rows)
	return x.done
}

// export_all writes a client grid's whole view as CSV now, into
// g.export.text, as export_start's frames would a chunk at a time: what
// a Copy CSV puts on the clipboard. A paged grid's rows are not in hand,
// so it does nothing and reports false; export_start streams them.
export_all :: proc(g: ^Grid, cols: []Column, src: Source) -> bool {
	if src.paged != nil {
		return false
	}
	export_start(g, cols, src)
	for !export_rows(g, cols, src) {
	}
	return true
}
