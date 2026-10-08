package export

import "core:encoding/cbor"
import "core:mem"
import "core:strconv"
import "core:strings"
import "jm:ui"
import "jm:ui/datagrid"

// A CSV export of a grid's view, over the grid rather than in it: the
// visible columns but those marked no_export, in the view's sort and
// filter, built a chunk a frame so a big one shows its progress and can
// be stopped. The view is fixed when the export starts: a sort or a
// filter changed meanwhile shows in the grid, not in the file. A table's
// export walks the order it began on; a remote's asks the grid's fetch
// for pages of the query it began on, each after the last so a keyset
// source gets the cursor every time.
//
//	export.start(&x, gtx, &g, cols, src)
//	if export.step(&x, gtx, cols, src) && x.error == "" { save(export.text(&x)) }

// Export is an export in progress or done: its text so far, how far it
// has got (rows written, the next place or offset), how many rows it
// expects (-1 when unknown), the columns it writes; for a table the order
// and the rows' version it began on, for a remote the query it began on,
// its sort columns and the keyset cursor; and an error that stopped it.
Export :: struct {
	active:    bool,
	done:      bool,
	text:      strings.Builder,
	written:   int,
	next:      int,
	total:     int,
	cols:      [dynamic]int,
	order:     [dynamic]int,
	version:   u64,
	query:     []u8, // cbor, so the view's slices need no deep copy
	sort_cols: [dynamic]int,
	after:     datagrid.Cursor,
	keep:      [dynamic]u8, // what after points into
	error:     string,
	allocator: mem.Allocator,
}

// CHUNK is the rows a table's export writes a frame; PAGE the rows a
// remote's asks for at once.
CHUNK :: 20_000
PAGE  :: 1000

// start begins exporting g's current view of src as CSV, in allocator,
// dropping what x held: the titles of the columns it writes now, the
// rows from the next step on.
start :: proc(
	x: ^Export,
	gtx: ^ui.Ctx,
	g: ^datagrid.Grid,
	cols: []datagrid.Column,
	src: datagrid.Rows,
	allocator := context.allocator,
) {
	destroy(x)
	x.allocator = allocator
	x.text = strings.builder_make(allocator)
	x.cols = make([dynamic]int, allocator)
	x.order = make([dynamic]int, allocator)
	x.sort_cols = make([dynamic]int, allocator)
	x.keep = make([dynamic]u8, allocator)
	titles := make([dynamic]string, context.temp_allocator)
	for col in datagrid.shown_columns(g) {
		if !cols[col].no_export {
			append(&x.cols, col)
			append(&titles, cols[col].title)
		}
	}
	datagrid.write_record(&x.text, datagrid.CSV, titles[:])
	n, kind, _ := datagrid.rows_count(src)
	x.total = n if kind != .Unknown else -1
	x.active = true
	switch r in src {
	case ^datagrid.Memory_Table:
		_, order, version := datagrid.memory_table_view(r)
		append(&x.order, ..order)
		x.version = version
	case ^datagrid.Remote_Rows:
		q := datagrid.page_query(gtx, g, cols)
		for s in q.sort {
			append(&x.sort_cols, datagrid.column_index(cols, s.column))
		}
		bytes, err := cbor.marshal_into_bytes(
			q,
			allocator = allocator,
			temp_allocator = context.temp_allocator,
		)
		if err != nil {
			stop(x, "the view could not be kept")
		}
		x.query = bytes
	case:
		x.done = true
	}
}

// step writes the export's next chunk, a table's now or a remote's page
// when it arrives, and reports whether this is the frame it ended. Call
// it every frame while the export runs.
step :: proc(x: ^Export, gtx: ^ui.Ctx, cols: []datagrid.Column, src: datagrid.Rows) -> bool {
	if !running(x) {
		return false
	}
	switch r in src {
	case ^datagrid.Memory_Table:
		table_step(x, cols, r)
	case ^datagrid.Remote_Rows:
		remote_step(x, gtx, cols, r)
	case:
		stop(x, "the rows went")
	}
	return x.done
}

// write_all writes a table's whole view as CSV now, as start and its steps
// would a chunk at a time: what a Copy CSV puts on the clipboard. A
// remote's rows are not in hand, so it does nothing and reports false.
write_all :: proc(
	x: ^Export,
	gtx: ^ui.Ctx,
	g: ^datagrid.Grid,
	cols: []datagrid.Column,
	src: datagrid.Rows,
	allocator := context.allocator,
) -> bool {
	t, ok := src.(^datagrid.Memory_Table)
	if !ok {
		return false
	}
	start(x, gtx, g, cols, src, allocator)
	for !x.done {
		table_step(x, cols, t)
	}
	return true
}

// running reports whether x has started and not ended.
running :: proc(x: ^Export) -> bool {
	return x.active && !x.done
}

// progress is how far x has got, in rows, and of how many (-1 when the
// source does not say).
progress :: proc(x: ^Export) -> (written, total: int) {
	return x.written, x.total
}

// text is the CSV x has written so far, x's own.
text :: proc(x: ^Export) -> string {
	return strings.to_string(x.text)
}

// cancel stops x; what it wrote is dropped.
cancel :: proc(x: ^Export) {
	destroy(x)
}

destroy :: proc(x: ^Export) {
	if x.allocator.procedure == nil {
		x^ = {}
		return
	}
	alloc := x.allocator
	strings.builder_destroy(&x.text)
	delete(x.cols)
	delete(x.order)
	delete(x.query, alloc)
	delete(x.sort_cols)
	delete(x.after.values, alloc)
	delete(x.keep)
	delete(x.error, alloc)
	x^ = {}
}

// stop ends x with error.
@(private)
stop :: proc(x: ^Export, error: string) {
	delete(x.error, x.allocator)
	x.error = strings.clone(error, x.allocator)
	x.done = true
}

// table_step writes the next CHUNK rows of the order the export began
// on. Rows changed under it (memory_table_changed) stop it: the order
// it holds points into the rows it began on.
@(private)
table_step :: proc(x: ^Export, cols: []datagrid.Column, t: ^datagrid.Memory_Table) {
	rows, _, version := datagrid.memory_table_view(t)
	if version != x.version {
		stop(x, "the rows changed while they were exported")
		return
	}
	fields := make([dynamic]string, 0, len(x.cols), context.temp_allocator)
	number: [24]u8 // a row number's text, written before the next is
	end := min(x.next + CHUNK, len(x.order))
	for row in x.order[x.next:end] {
		clear(&fields)
		for col in x.cols {
			if cols[col].row_number {
				append(&fields, strconv.write_int(number[:], i64(x.written + 1), 10))
			} else {
				append(&fields, datagrid.row_text(rows, row, col))
			}
		}
		datagrid.write_record(&x.text, datagrid.CSV, fields[:])
		x.written += 1
	}
	x.next = end
	x.done = x.next >= len(x.order)
}

// remote_step asks for the export's next page of the query it began on
// and writes it when it arrives. A short page is the end; an error stops
// the export with it.
@(private)
remote_step :: proc(x: ^Export, gtx: ^ui.Ctx, cols: []datagrid.Column, r: ^datagrid.Remote_Rows) {
	q: datagrid.Page_Query
	if cbor.unmarshal_from_bytes(
		   x.query,
		   &q,
		   allocator = gtx.allocator,
		   temp_allocator = gtx.allocator,
	   ) !=
	   nil {
		stop(x, "the view could not be read back")
		return
	}
	q.offset, q.limit, q.after = x.next, PAGE, x.after
	pg, st, _ := datagrid.remote_rows_fetch(r, gtx, q)
	switch {
	case pg == nil || st != .Ready:
		return
	case pg.error != "":
		stop(x, pg.error)
		return
	}
	write_page(x, gtx, cols, pg.rows)
	x.next += len(pg.rows)
	x.done = len(pg.rows) < PAGE
	if !x.done {
		keep_cursor(x, pg.rows[len(pg.rows) - 1])
	}
}

// write_page writes a page's rows to x, the export's columns of each.
@(private)
write_page :: proc(x: ^Export, gtx: ^ui.Ctx, cols: []datagrid.Column, rows: []datagrid.Page_Row) {
	fields := make([dynamic]string, 0, len(x.cols), gtx.allocator)
	number: [24]u8 // a row number's text, written before the next is
	for r in rows {
		clear(&fields)
		for col in x.cols {
			switch {
			case cols[col].row_number:
				append(&fields, strconv.write_int(number[:], i64(x.written + 1), 10))
			case col < len(r.cells):
				append(&fields, r.cells[col])
			case:
				append(&fields, "")
			}
		}
		datagrid.write_record(&x.text, datagrid.CSV, fields[:])
		x.written += 1
	}
}

// keep_cursor keeps the last row written as the next page's cursor: its
// key and its text in each sort column.
@(private)
keep_cursor :: proc(x: ^Export, r: datagrid.Page_Row) {
	clear(&x.keep)
	append(&x.keep, r.key)
	spans := make([dynamic][2]int, 0, len(x.sort_cols), context.temp_allocator)
	for col in x.sort_cols {
		lo := len(x.keep)
		if col >= 0 && col < len(r.cells) {
			append(&x.keep, r.cells[col])
		}
		append(&spans, [2]int{lo, len(x.keep)})
	}
	delete(x.after.values, x.allocator)
	x.after.key = string(x.keep[:len(r.key)])
	x.after.values = make([]string, len(spans), x.allocator)
	for s, ii in spans {
		x.after.values[ii] = string(x.keep[s[0]:s[1]])
	}
}
