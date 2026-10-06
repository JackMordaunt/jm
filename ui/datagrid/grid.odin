package datagrid

import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"
import "jm:ui"
import "jm:ui/ops"

// Grid is a data grid's state, the caller's to keep for the grid's life
// (grid_init, grid_destroy): the user's view of the columns and query,
// the selection, the keyboard's cell, the scroll, and what the grid
// keeps to draw fast (the client order, the row heights, the page cache,
// the shaped text). Everything the user arranges is in view, which a
// saved view is made of; the rest is the grid's own.
Grid :: struct {
	view:       View,
	sel:        Selection,
	density:    Density,
	fit:        Fit,
	anchor_on:  Query_Anchor, // where the scroll goes when the query changes
	scroll:     [2]f32, // the middle columns' sideways scroll and the rows'
	cursor:     Cell_At, // the keyboard's cell; item -1 is the header
	anchor:     Cell_At, // where a range of cells starts: the cursor before a Shift move
	focused:    bool,
	hover:      int, // the item under the pointer, -1 for none
	hover_head: int, // the column whose header is under the pointer, -1 for none
	hover_grip: int, // the column whose resize grip is, -1 for none
	drag:       Drag,
	export:     Export,
	collapsed:  map[string]bool, // the groups shut
	filter_at:  int, // the column whose filter a skin shows open, -1 for none
	// What the grid keeps to draw.
	order:      Order,
	heights:    Heights,
	place:      Placement,
	pages:      Pages,
	text:       Text_Cache,
	built:      u64, // what order and heights were built for
	match:      u64, // the view's match hash, as of the last frame
	query:      u64, // its order hash
	measured:   u64, // what the Auto widths were measured for
	ids:        [dynamic]string, // the columns' ids as last drawn, to notice them change
	visible:    [dynamic]int, // scratch: the visible columns, for a query
	keys:       [dynamic]Row_Key, // scratch: a range's keys
	names:      [dynamic]string, // and their strings
	geo:        Geometry,
	allocator:  mem.Allocator,
}

// Cell_At is a cell by its place in the order and its column: item is
// where the row stands now, key the row it was, so the cell follows its
// row through a sort.
Cell_At :: struct {
	item: int,
	col:  int,
	key:  Row_Key,
}

// Query_Anchor is where the rows scroll when the query changes: back to
// the top, or to keep the keyboard's row where it was on screen.
Query_Anchor :: enum u8 {
	Top,
	Cursor,
}

// Drag is a pointer gesture in progress: a column edge being dragged, a
// column being moved, or a range of rows being swept.
Drag :: struct {
	kind:  Drag_Kind,
	col:   int,
	start: f32, // the dragged column's width at the press
	moved: f32, // how far the pointer has gone, in x
	x:     f32, // the pointer, in the grid's space
	shift: bool,
}

Drag_Kind :: enum u8 {
	None,
	Header, // pressed on a header: a click, or a move once it travels
	Move,
	Resize,
	Select,
}

// Geometry is where this frame's parts lie, in the grid's space: its
// size, the header's height, the body under it, the middle columns' view
// (from mid_x, mid_w wide), the item count, the items in view, how tall
// the rows are in all and one row.
Geometry :: struct {
	size:     ops.Size,
	header_h: f32,
	body:     ops.Rect,
	mid_x:    f32,
	mid_w:    f32,
	items:    int,
	first:    int,
	last:     int,
	content:  f64,
	row_h:    f32,
	mid_lo:   int, // the middle places in view, [mid_lo, mid_hi)
	mid_hi:   int,
}

// Events is what a frame of the grid did that its caller may act on.
// activated is Enter or a double click on a row (row says which);
// context_menu a right click (at, in the grid's space, and col say
// where); view says the view changed (a sort, a filter, a width, an
// order, a pin), when a caller that keeps it persists it; selection that
// the selection changed; copied that many cells went to the clipboard;
// filter_asked the column whose filter the keyboard asked for (Alt+Down
// on its header), -1 for none; exported that an export finished, its
// text in Grid.export.
Events :: struct {
	activated:    bool,
	context_menu: bool,
	row:          Row_Ref,
	at:           ops.Point,
	col:          int,
	view:         bool,
	sorted:       bool,
	filtered:     bool,
	selection:    bool,
	copied:       int,
	filter_asked: int,
	exported:     bool,
}

// Row_Ref names a row: where it stands, its client index (-1 for a
// paged row), its key and a paged row's own key string.
Row_Ref :: struct {
	item: int,
	row:  int,
	key:  Row_Key,
	name: string,
}

// grid_init readies g for columns, the source's paging settings when it
// is paged. allocator holds everything g keeps.
grid_init :: proc(
	g: ^Grid,
	columns: []Column,
	paged: ^Paging = nil,
	allocator := context.allocator,
) {
	g.allocator = allocator
	view_init(&g.view, columns, allocator)
	selection_init(&g.sel, allocator)
	text_cache_init(&g.text, allocator)
	g.collapsed = make(map[string]bool, allocator)
	g.order.rows = make([dynamic]int, allocator)
	g.place.places = make([dynamic]Place, allocator)
	g.visible = make([dynamic]int, allocator)
	g.ids = make([dynamic]string, allocator)
	for c in columns {
		append(&g.ids, clone_to(c.id, allocator))
	}
	g.keys = make([dynamic]Row_Key, allocator)
	g.names = make([dynamic]string, allocator)
	g.hover, g.filter_at, g.hover_head, g.hover_grip = -1, -1, -1, -1
	g.cursor = {
		item = 0,
		col  = -1,
	}
	g.export.text.buf.allocator = allocator
	if paged != nil {
		pages_init(&g.pages, paged^, allocator)
	}
}

grid_destroy :: proc(g: ^Grid) {
	context.allocator = g.allocator
	view_destroy(&g.view)
	selection_destroy(&g.sel)
	text_cache_destroy(&g.text, g.allocator)
	for k in g.collapsed {
		delete(k, g.allocator)
	}
	delete(g.collapsed)
	order_destroy(&g.order)
	heights_destroy(&g.heights)
	placement_destroy(&g.place)
	if g.pages.entries != nil {
		pages_destroy(&g.pages)
	}
	export_destroy(&g.export)
	for id in g.ids {
		delete(id, g.allocator)
	}
	delete(g.ids)
	delete(g.visible)
	delete(g.keys)
	delete(g.names)
	g^ = {}
}

// grid is a data grid of columns over src's rows, dressed by skin, label
// naming it to assistive technology. It fills the room it is offered, a
// sticky header over virtualised rows; with no bound on its height it is
// twenty rows tall. Call it every frame with the same g; it returns what
// the frame did (Events).
grid :: proc(
	gtx: ^ui.Ctx,
	g: ^Grid,
	columns: []Column,
	src: Source,
	skin: ^Skin,
	label := "",
	key: u64 = 0,
	loc := #caller_location,
) -> (
	ev: Events,
) {
	ev.filter_asked, ev.col = -1, -1
	sync_columns(g, columns)
	size := grid_size(gtx, g, skin)
	box := ui.sized_open(gtx, {min = size, max = size}, key, loc)
	defer ui.close(&box)
	id := ui.container_id(gtx)
	update_query(g, columns, src, skin, &ev)
	measure(gtx, g, columns, src, skin)
	geometry(g, columns, src, skin, size)
	handle_input(gtx, g, columns, src, skin, id, &ev)
	// What the input changed (a sort, a filter, a group shut) shows now,
	// not a frame late.
	update_query(g, columns, src, skin, &ev)
	geometry(g, columns, src, skin, size)
	if src.paged != nil && want_pages(gtx, g, columns, src) {
		// The pages that came moved the count: the rows are laid out
		// again, so this frame draws them where the next one will.
		geometry(g, columns, src, skin, size)
	}
	export_step(gtx, g, columns, src, &ev)
	paint(gtx, g, columns, src, skin, id, label)
	return
}

// grid_size is what the grid takes: the room offered, or twenty rows
// where the height is unbounded and 640 where the width is.
@(private)
grid_size :: proc(gtx: ^ui.Ctx, g: ^Grid, skin: ^Skin) -> ops.Size {
	cs := gtx.constraints
	w := cs.max.x if ui.is_finite(cs.max.x) else max(cs.min.x, 640)
	h := cs.max.y
	if !ui.is_finite(h) {
		h = max(cs.min.y, skin.style.header_height + 20 * row_height(&skin.style, g.density))
	}
	return {w, h}
}

// sync_columns keeps the view when the caller's columns change between
// builds (one added, one dropped, the order changed): the view is written
// out against the old columns and read back against the new, as a saved
// view from another build is.
@(private)
sync_columns :: proc(g: ^Grid, columns: []Column) {
	same := len(g.ids) == len(columns)
	for c, i in columns {
		if !same || g.ids[i] != c.id {
			same = false
			break
		}
	}
	if same {
		return
	}
	if len(g.ids) > 0 {
		old := make([]Column, len(g.ids), context.temp_allocator)
		for id, i in g.ids {
			old[i].id = id
		}
		b := strings.builder_make(context.temp_allocator)
		view_encode(&b, &g.view, old, "")
		view_decode(&g.view, columns, strings.to_string(b), context.temp_allocator)
	} else {
		view_reset(&g.view, columns)
	}
	for id in g.ids {
		delete(id, g.allocator)
	}
	clear(&g.ids)
	for c in columns {
		append(&g.ids, clone_to(c.id, g.allocator))
	}
	g.built, g.measured = 0, 0
}

// update_query hashes the view's query and, when it or the data changed,
// rebuilds the client order or starts the paged query over, keeping the
// selection by key and the scroll by the anchor policy.
@(private)
update_query :: proc(g: ^Grid, cols: []Column, src: Source, skin: ^Skin, ev: ^Events) {
	q := view_query(&g.view, cols, &g.visible)
	match, query := match_hash(q), order_hash(q)
	changed := query != g.query
	if match != g.match && g.sel.all {
		keep_selection(g, src, match)
		ev.selection = true
	}
	g.match, g.query = match, query
	if src.paged != nil {
		if pages_query(&g.pages, query) {
			changed = true
		}
		g.geo.items = max(g.pages.count, 0)
	} else {
		built := ui.fnv_u64(ui.fnv_u64(query, src.version), u64(src.rows))
		built = ui.fnv_u64(ui.fnv_u64(built, collapsed_hash(g)), u64(src.loading))
		if built != g.built {
			g.built = built
			order_build(&g.order, src, q, g.collapsed)
			size_rows(g, src, skin)
		}
		g.geo.items = len(g.order.items)
	}
	if changed {
		anchor_scroll(g, src)
	}
}

// collapsed_hash names which groups are shut, so shutting one rebuilds.
@(private)
collapsed_hash :: proc(g: ^Grid) -> u64 {
	h: u64
	for k, shut in g.collapsed {
		if shut {
			h ~= fnv_str(ui.FNV_OFFSET, k)
		}
	}
	return h
}

// keep_selection turns a select-all made under another match into the
// rows it covered: for a client grid every row the old order held, for a
// paged one the rows loaded.
@(private)
keep_selection :: proc(g: ^Grid, src: Source, match: u64) {
	clear(&g.keys)
	clear(&g.names)
	if src.paged != nil {
		for e in g.pages.entries {
			for r in e.rows {
				append(&g.keys, row_key(r.key))
				append(&g.names, r.key)
			}
		}
	} else {
		for r in g.order.rows {
			append(&g.keys, source_key(src, r))
		}
	}
	selection_settle(&g.sel, match, g.keys[:], g.names[:])
}

// anchor_scroll follows the policy for a new query: the rows scroll back
// to the top, the keyboard's row to the first; or the keyboard's row is
// found again and kept where it was on screen. A cursor on the header,
// which sorted, stays there.
@(private)
anchor_scroll :: proc(g: ^Grid, src: Source) {
	g.anchor = {
		item = -1,
		col  = g.cursor.col,
	}
	if g.cursor.item < 0 {
		g.scroll.y = 0 if g.anchor_on == .Top else g.scroll.y
		return
	}
	if g.anchor_on == .Cursor && src.paged == nil {
		if at := item_of_key(g, src, g.cursor.key); at >= 0 {
			screen := f32(heights_top(&g.heights, g.cursor.item)) - g.scroll.y
			g.cursor.item = at
			g.scroll.y = f32(heights_top(&g.heights, at)) - screen
			return
		}
	}
	g.scroll.y = 0
	g.cursor.item = 0
	g.cursor.key = item_at(g, src, 0).key
}

// item_of_key is where the row keyed key stands in a client order, -1
// when it is not there.
@(private)
item_of_key :: proc(g: ^Grid, src: Source, key: Row_Key) -> int {
	for it, i in g.order.items {
		if it >= 0 && source_key(src, it) == key {
			return i
		}
	}
	return -1
}

// size_rows sizes the rows: uniform at the density, or per item when
// rows are grouped (a header has its own height) or the source gives
// each row its own.
@(private)
size_rows :: proc(g: ^Grid, src: Source, skin: ^Skin) {
	rh := f64(row_height(&skin.style, g.density))
	if g.view.group < 0 && src.height == nil {
		heights_set_uniform(&g.heights, len(g.order.items), rh)
		return
	}
	Ctx :: struct {
		g:    ^Grid,
		src:  Source,
		row:  f64,
		head: f64,
	}
	c := Ctx{g, src, rh, f64(group_height(&skin.style, g.density))}
	heights_build(&g.heights, len(g.order.items), proc(user: rawptr, i: int) -> f64 {
			c := (^Ctx)(user)
			it := c.g.order.items[i]
			if it < 0 {
				return c.head
			}
			if c.src.height != nil {
				return f64(c.src.height(c.src.user, it))
			}
			return c.row
		}, &c)
}

// geometry lays out this frame's parts: the columns, the regions, the
// heights in paged mode, and the items in view.
@(private)
geometry :: proc(g: ^Grid, cols: []Column, src: Source, skin: ^Skin, size: ops.Size) {
	geo := &g.geo
	geo.size = size
	geo.header_h = skin.style.header_height
	geo.body = {0, geo.header_h, size.x, max(size.y - geo.header_h - foot_height(skin), 0)}
	geo.row_h = row_height(&skin.style, g.density)
	switch {
	case src.paged != nil:
		geo.items = max(g.pages.count, 0)
		heights_set_uniform(&g.heights, geo.items, f64(geo.row_h))
	case src.loading:
		// A view of skeletons after the rows there are.
		geo.items = len(g.order.items) + int(geo.body.h / max(geo.row_h, 1)) + 1
		heights_set_uniform(&g.heights, geo.items, f64(geo.row_h))
	}
	place_columns(&g.place, cols, g.view.cols[:], g.view.order[:], size.x, g.fit)
	geo.mid_x = g.place.left_w
	geo.mid_w = max(size.x - g.place.left_w - g.place.right_w, 0)
	geo.content = heights_total(&g.heights)
	clamp_scroll(g)
	geo.mid_lo, geo.mid_hi = mid_visible(&g.place, g.scroll.x, geo.mid_w)
	geo.first, geo.last = 0, 0
	if geo.items > 0 {
		geo.first = heights_at(&g.heights, f64(g.scroll.y))
		end := heights_at(&g.heights, f64(g.scroll.y + geo.body.h))
		geo.last = min(end + 1 + OVERSCAN, geo.items)
		geo.first = max(geo.first - OVERSCAN, 0)
	}
}

// foot_height is the band under the body that the bottom corners
// round, or that the outline's bottom edge takes: the rows end above it.
@(private)
foot_height :: proc(skin: ^Skin) -> f32 {
	st := &skin.style
	edge: f32 = 1 if ui.painted(st.border) else 0
	return math.ceil(max(st.radius, edge))
}

// OVERSCAN is how many rows past the view either way are laid out: the
// keyboard's next row is then already in the frame, and a reader can step
// onto it.
OVERSCAN :: 2

// clamp_scroll keeps the scroll within the content.
@(private)
clamp_scroll :: proc(g: ^Grid) {
	geo := &g.geo
	g.scroll.y = clamp(g.scroll.y, 0, max(f32(geo.content) - geo.body.h, 0))
	g.scroll.x = clamp(g.scroll.x, 0, max(g.place.mid_w - geo.mid_w, 0))
}

// Item is what stands at one place in the order: a client row (row), a
// paged row (page_row), or a group header (group >= 0), with what it
// shows, its key and a paged row's key string.
Item :: struct {
	state:    Row_State,
	row:      int,
	page_row: ^Page_Row,
	group:    int,
	key:      Row_Key,
	name:     string,
	error:    string,
}

// item_at is what stands at place i in the current order.
item_at :: proc(g: ^Grid, src: Source, i: int) -> (it: Item) {
	it.row, it.group = -1, -1
	if i < 0 || i >= g.geo.items {
		return
	}
	if src.paged == nil {
		if i >= len(g.order.items) {
			it.state = .Loading // a skeleton while src is loading
			return
		}
		r := g.order.items[i]
		if r < 0 {
			it.group, it.state = -r - 1, .Ready
			return
		}
		it.row, it.state, it.key = r, .Ready, source_key(src, r)
		return
	}
	pr, st, page := pages_row(&g.pages, i)
	it.state = st
	if pr != nil {
		it.page_row, it.key, it.name = pr, row_key(pr.key), pr.key
	}
	if st == .Failed && page != nil {
		it.error = page.error
	}
	return
}

// cell_text is column col of it as shown; a row number column shows its
// place.
cell_text :: proc(gtx: ^ui.Ctx, src: Source, cols: []Column, it: Item, item, col: int) -> string {
	if cols[col].row_number {
		return fmt.aprintf("%d", item + 1, allocator = gtx.allocator)
	}
	if it.page_row != nil {
		return it.page_row.cells[col] if col < len(it.page_row.cells) else ""
	}
	if it.row >= 0 {
		return source_text(src, it.row, col)
	}
	return ""
}

// selected_rows is the keys of the selected rows the grid holds, in the
// current order, and their strings: every client row selected, the
// loaded paged rows selected. A paged select-all reaches rows never
// loaded, which only the source can list (Selection.all says so).
selected_rows :: proc(
	g: ^Grid,
	src: Source,
	allocator := context.allocator,
) -> (
	keys: []Row_Key,
	names: []string,
) {
	ks := make([dynamic]Row_Key, allocator)
	ns := make([dynamic]string, allocator)
	for i in 0 ..< g.geo.items {
		it := item_at(g, src, i)
		if it.group < 0 &&
		   it.state != .Missing &&
		   it.state != .Loading &&
		   it.state != .Failed &&
		   selected(&g.sel, it.key) {
			append(&ks, it.key)
			append(&ns, it.name)
		}
	}
	return ks[:], ns[:]
}
