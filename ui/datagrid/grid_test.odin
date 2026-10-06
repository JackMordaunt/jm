package datagrid

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// The widget through ui.Probe: scrolling, the sticky header, sorting,
// resizing, moving and pinning columns, the keyboard, selection, copy,
// groups, and a paged source's skeletons, pages and needs.

@(private = "file")
Rigs :: struct {
	g:       Grid,
	skin:    Skin,
	rows:    [][4]string,
	ev:      Events,
	events:  [dynamic]Events,
	paged:   ^Paging,
	label:   string,
	loading: bool,
}

@(private = "file")
RIG_COLS := []Column {
	{id = "serial", title = "Serial", row_header = true},
	{id = "model", title = "Model", filter = .Set},
	{id = "site", title = "Site", filter = .Set},
	{id = "hash", title = "Hash", kind = .Number, align = .End, filter = .Range},
}

@(private = "file")
SITES := []string{"Norway", "Paraguay", "Wisconsin"}

@(private = "file")
rigs_make :: proc(n: int, paged: ^Paging = nil) -> ^Rigs {
	m := new(Rigs)
	m.rows = make([][4]string, n)
	for i in 0 ..< n {
		m.rows[i] = {
			fmt.aprintf("SN-%05d", i),
			fmt.aprintf("M%d", i % 4),
			SITES[i % 3],
			fmt.aprintf("%d", (i * 37) % 100),
		}
	}
	m.paged = paged
	grid_init(&m.g, RIG_COLS, paged)
	m.skin.style = DEFAULT_STYLE
	m.events = make([dynamic]Events)
	return m
}

@(private = "file")
rigs_free :: proc(m: ^Rigs) {
	grid_destroy(&m.g)
	for r in m.rows {
		delete(r[0])
		delete(r[1])
		delete(r[3]) // r[2] is one of SITES
	}
	delete(m.rows)
	delete(m.events)
	free(m)
}

@(private = "file")
rigs_source :: proc(m: ^Rigs) -> Source {
	text :: proc(user: rawptr, row, col: int) -> string {
		return (^Rigs)(user).rows[row][col]
	}
	return {user = m, rows = len(m.rows), text = text, paged = m.paged, loading = m.loading}
}

@(private = "file")
rigs_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Rigs)(user)
	m.ev = grid(gtx, &m.g, RIG_COLS, rigs_source(m), &m.skin, m.label if m.label != "" else "Rigs")
	append(&m.events, m.ev)
}

// saw reports whether any frame since the last clear did what want says.
@(private = "file")
saw :: proc(m: ^Rigs, want: proc(e: Events) -> bool) -> bool {
	for e in m.events {
		if want(e) {
			return true
		}
	}
	return false
}

// cells counts the grid cells in the frame's semantics.
@(private = "file")
cells :: proc(p: ^ui.Probe) -> int {
	n := 0
	for node in ui.probe_current(p).nodes {
		if node.semantics.role == .Grid_Cell {
			n += 1
		}
	}
	return n
}

@(private = "file")
open :: proc(p: ^ui.Probe, m: ^Rigs, size := ops.Size{600, 400}) {
	ui.probe_init(p, rigs_view, m, size)
}

@(test)
test_only_the_rows_in_view_are_laid_out :: proc(t: ^testing.T) {
	m := rigs_make(100_000)
	defer rigs_free(m)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	// 364px of body at 33px a row is 12 rows, and two of overscan.
	testing.expect_value(t, cells(&p), (12 + 2) * 4)
	testing.expect(t, ui.probe_tagged(&p, "SN-00000"))
	testing.expect(t, !ui.probe_tagged(&p, "SN-00020"))
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `grid "Rigs" rows 100001 cols 4`), said)
}

@(test)
test_the_wheel_scrolls_rows_under_a_sticky_header :: proc(t: ^testing.T) {
	m := rigs_make(100_000)
	defer rigs_free(m)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	head := ui.probe_bounds(&p, "Serial")
	ui.probe_scroll(&p, "SN-00003", 10) // 480px: row 14 at the top, 18px up
	testing.expect_value(t, m.g.scroll.y, 480)
	testing.expect(t, !ui.probe_tagged(&p, "SN-00011"))
	b := ui.probe_bounds(&p, "SN-00014")
	testing.expect_value(t, b.y, 36 + 14 * 33 - 480)
	testing.expect_value(t, ui.probe_bounds(&p, "Serial"), head) // the header stays
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `grid cell "SN-00014" row 16 col 1`), said)
	ui.probe_scroll(&p, "SN-00014", 1e7)
	testing.expect(t, ui.probe_tagged(&p, "SN-99999"), "scrolled to the last row")
}

@(test)
test_a_header_click_sorts_and_shift_adds_a_column :: proc(t: ^testing.T) {
	m := rigs_make(50)
	defer rigs_free(m)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_click(&p, "Hash"))
	testing.expect_value(t, len(m.g.view.sort), 1)
	testing.expect_value(t, m.g.view.sort[0], Sort_Key{3, false})
	first := m.rows[m.g.order.rows[0]][3]
	testing.expect_value(t, first, "0")
	ui.probe_click(&p, "Hash")
	testing.expect(t, m.g.view.sort[0].desc)
	testing.expect_value(t, m.rows[m.g.order.rows[0]][3], "99")
	// Shift adds the site as a second key.
	c, _ := ui.probe_center(&p, "Site")
	ui.router_push(&p.router, {kind = .Move, pos = c})
	ui.router_push(
		&p.router,
		{kind = .Press, pos = c, button = .Left, mods = {.Shift}, clicks = 1},
	)
	ui.router_push(&p.router, {kind = .Release, pos = c, button = .Left, mods = {.Shift}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, len(m.g.view.sort), 2)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(
		t,
		strings.contains(said, `column header "Hash" row 1 col 4 sorted descending`),
		said,
	)
	ui.probe_click(&p, "Hash") // a plain click on a descending column ends the sort
	testing.expect_value(t, len(m.g.view.sort), 0)
}

@(test)
test_a_header_edge_drags_its_width_and_a_double_click_fits_it :: proc(t: ^testing.T) {
	m := rigs_make(20)
	defer rigs_free(m)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	before := ui.probe_bounds(&p, "Model").w
	testing.expect(t, ui.probe_drag(&p, "resize Model", 60, 0))
	after := m.g.place.places[place_of(&m.g.place, 1)].w
	testing.expect(t, abs(after - (before + 60)) < 1, fmt.tprint(before, after))
	testing.expect(t, saw(m, proc(e: Events) -> bool {return e.view}))
	ui.probe_drag(&p, "resize Model", -1000, 0)
	testing.expect_value(t, m.g.place.places[place_of(&m.g.place, 1)].w, MIN_WIDTH)
	c, _ := ui.probe_center(&p, "resize Model")
	ui.probe_click_at(&p, c, clicks = 2)
	fit := m.g.view.cols[1].width
	testing.expect(t, fit > MIN_WIDTH && fit < before + 1, fmt.tprint(fit))
}

@(test)
test_a_header_dragged_sideways_moves_its_column :: proc(t: ^testing.T) {
	m := rigs_make(20)
	defer rigs_free(m)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	sort_before := len(m.g.view.sort)
	site := ui.probe_bounds(&p, "Site")
	serial, _ := ui.probe_center(&p, "Serial")
	testing.expect(t, ui.probe_drag(&p, "Serial", site.x + site.w - 4 - serial.x, 0))
	testing.expect(
		t,
		m.g.view.order[0] == 1 && m.g.view.order[1] == 2 && m.g.view.order[2] == 0,
		fmt.tprint(m.g.view.order),
	)
	testing.expect_value(t, len(m.g.view.sort), sort_before) // a move is not a click
}

@(test)
test_a_pinned_column_stays_while_the_rest_scroll_sideways :: proc(t: ^testing.T) {
	m := rigs_make(20)
	defer rigs_free(m)
	for &c in m.g.view.cols {
		c.width = 200
	}
	m.g.view.cols[0].pin = .Left
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	ui.router_push(&p.router, {kind = .Scroll, pos = {300, 100}, scroll = {1, 0}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, m.g.scroll.x, 48)
	testing.expect_value(t, ui.probe_bounds(&p, "Serial").x, 0)
	testing.expect_value(t, ui.probe_bounds(&p, "SN-00001").x, 0)
	testing.expect_value(t, ui.probe_bounds(&p, "Model").x, 200 - 48)
	ui.router_push(&p.router, {kind = .Scroll, pos = {300, 100}, scroll = {100, 0}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, m.g.scroll.x, 600 - 400) // the middle is 600 wide in a 400 view
	testing.expect(t, !ui.probe_tagged(&p, "M1"), "the first middle column scrolled out")
}

@(private = "file")
focus_on :: proc(p: ^ui.Probe, name: string) {
	ui.probe_click(p, name)
}

@(test)
test_the_keyboard_walks_cells_pages_and_ends :: proc(t: ^testing.T) {
	m := rigs_make(1000)
	defer rigs_free(m)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	focus_on(&p, "SN-00002")
	testing.expect(t, m.g.focused)
	testing.expect_value(t, m.g.cursor.item, 2)
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.g.cursor, Cell_At{3, 1, 3})
	ui.probe_key(&p, .End)
	testing.expect_value(t, m.g.cursor.col, 3)
	ui.probe_key(&p, .Home)
	testing.expect_value(t, m.g.cursor.col, 0)
	ui.probe_key(&p, .Page_Down)
	testing.expect_value(t, m.g.cursor.item, 3 + 10)
	ui.probe_key(&p, .End, {ui.SHORTCUT})
	testing.expect_value(t, m.g.cursor.item, 999)
	testing.expect(t, ui.probe_tagged(&p, "SN-00999"), "the last row scrolled into view")
	ui.probe_key(&p, .Home, {ui.SHORTCUT})
	testing.expect_value(t, m.g.cursor.item, 0)
	ui.probe_key(&p, .Up) // onto the header
	testing.expect_value(t, m.g.cursor.item, -1)
	ui.probe_key(&p, .Enter) // which sorts
	testing.expect_value(t, len(m.g.view.sort), 1)
	ui.probe_key(&p, .Down, {.Alt})
	testing.expect(t, saw(m, proc(e: Events) -> bool {return e.filter_asked == 0}))
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `active "Serial"`), said)
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Enter)
	testing.expect(t, saw(m, proc(e: Events) -> bool {return e.activated && e.row.item == 0}))
}

@(test)
test_clicks_select_alone_toggle_and_range_and_survive_a_sort :: proc(t: ^testing.T) {
	m := rigs_make(30)
	defer rigs_free(m)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	ui.probe_click(&p, "SN-00002")
	testing.expect(t, selected(&m.g.sel, 2))
	c, _ := ui.probe_center(&p, "SN-00005")
	ui.router_push(
		&p.router,
		{kind = .Press, pos = c, button = .Left, mods = {.Shift}, clicks = 1},
	)
	ui.router_push(&p.router, {kind = .Release, pos = c, button = .Left, mods = {.Shift}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, selection_count(&m.g.sel, 30), 4) // rows 2 to 5
	c, _ = ui.probe_center(&p, "SN-00008")
	ui.router_push(
		&p.router,
		{kind = .Press, pos = c, button = .Left, mods = {ui.SHORTCUT}, clicks = 1},
	)
	ui.router_push(&p.router, {kind = .Release, pos = c, button = .Left, mods = {ui.SHORTCUT}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, selection_count(&m.g.sel, 30), 5)
	ui.probe_key(&p, .Down, {.Shift})
	testing.expect(
		t,
		selected(&m.g.sel, 9) && selected(&m.g.sel, 2),
		"Shift+Down extends from the anchor",
	)
	ui.probe_key(&p, .Space)
	testing.expect(t, !selected(&m.g.sel, 9))
	view_sort_cycle(&m.g.view, 3, false)
	ui.probe_frame(&p)
	testing.expect(
		t,
		selected(&m.g.sel, 2) && selected(&m.g.sel, 8),
		"kept by key through the sort",
	)
	ui.probe_key(&p, .A, {ui.SHORTCUT})
	testing.expect_value(t, selection_count(&m.g.sel, 30), 30)
	ui.probe_key(&p, .Escape)
	testing.expect(t, selection_empty(&m.g.sel))
}

@(test)
test_copy_puts_cells_rows_or_a_range_on_the_clipboard_as_tsv :: proc(t: ^testing.T) {
	m := rigs_make(30)
	defer rigs_free(m)
	delete(m.rows[1][1])
	m.rows[1][1] = strings.clone("tab\there")
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	ui.probe_click(&p, "SN-00001")
	ui.probe_key(&p, .C, {ui.SHORTCUT})
	testing.expect_value(t, ui.probe_clipboard(&p), "SN-00001") // one cell, as text
	ui.probe_key(&p, .Right, {.Shift})
	ui.probe_key(&p, .Down, {.Shift})
	ui.probe_key(&p, .C, {ui.SHORTCUT})
	testing.expect_value(t, ui.probe_clipboard(&p), "SN-00001\t\"tab\there\"\nSN-00002\tM2\n")
	ui.probe_key(&p, .Right) // a single cell again, the two rows still selected
	ui.probe_key(&p, .C, {ui.SHORTCUT, .Shift})
	got := ui.probe_clipboard(&p)
	testing.expect(t, strings.has_prefix(got, "Serial\tModel\tSite\tHash\n"), got)
	testing.expect_value(t, strings.count(got, "\n"), 3) // the titles and two rows
	testing.expect(t, saw(m, proc(e: Events) -> bool {return e.copied == 8}))
}

@(test)
test_groups_head_their_rows_with_counts_and_shut :: proc(t: ^testing.T) {
	m := rigs_make(9)
	defer rigs_free(m)
	m.g.view.group = 2
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(
		t,
		strings.contains(said, `row "Norway, 3 rows" row 2 expandable expanded`),
		said,
	)
	testing.expect(t, ui.probe_click(&p, "Paraguay, 3 rows"))
	testing.expect(t, m.g.collapsed["Paraguay"])
	testing.expect_value(t, m.g.geo.items, 3 + 3 + 3) // three headers, Paraguay's rows gone
	testing.expect(t, !ui.probe_tagged(&p, "SN-00001")) // a Paraguay rig
}

@(test)
test_an_export_writes_the_view_as_csv :: proc(t: ^testing.T) {
	m := rigs_make(90_000)
	defer rigs_free(m)
	view_set_values(&m.g.view, 2, {"Norway"})
	m.g.view.cols[1].hidden = true
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	export_start(&m.g, RIG_COLS, rigs_source(m))
	ui.probe_frame(&p)
	w, total := export_progress(&m.g)
	testing.expect_value(t, w, EXPORT_CHUNK)
	testing.expect_value(t, total, 30_000)
	ui.probe_frame(&p)
	testing.expect(t, m.g.export.done)
	testing.expect(t, saw(m, proc(e: Events) -> bool {return e.exported}))
	text := strings.to_string(m.g.export.text)
	testing.expect(
		t,
		strings.has_prefix(
			text,
			"Serial,Site,Hash\r\nSN-00000,Norway,0\r\nSN-00003,Norway,11\r\n",
		),
		text[:60],
	)
	testing.expect_value(t, strings.count(text, "\r\n"), 30_001)
}

// A steady frame allocates nothing: no heap, no temp, with a hundred
// thousand rows, a sort and a filter in place.
@(test)
test_a_steady_frame_allocates_nothing :: proc(t: ^testing.T) {
	m := rigs_make(100_000)
	defer rigs_free(m)
	view_sort_cycle(&m.g.view, 3, false)
	view_set_values(&m.g.view, 2, {"Norway", "Wisconsin"})
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	focus_on(&p, "Serial") // the cursor's ring, the focus ring
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	spy := Spy {
		inner = context.allocator,
	}
	spy_t := Spy {
		inner = context.temp_allocator,
	}
	saved, saved_t := context.allocator, context.temp_allocator
	context.allocator = {spy_proc, &spy}
	context.temp_allocator = {spy_proc, &spy_t}
	clear(&m.events)
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	context.allocator, context.temp_allocator = saved, saved_t
	for i in 0 ..< min(spy.n, len(spy.at)) {
		testing.expectf(t, false, "heap allocator called at %v", spy.at[i])
	}
	for i in 0 ..< min(spy_t.n, len(spy_t.at)) {
		testing.expectf(t, false, "temp allocator called at %v", spy_t.at[i])
	}
	testing.expect(t, cells(&p) > 0)
}

// Spy records where allocations came from and passes them on.
@(private = "file")
Spy :: struct {
	inner: mem.Allocator,
	at:    [16]runtime.Source_Code_Location,
	n:     int,
}

@(private = "file")
spy_proc :: proc(
	data: rawptr,
	mode: mem.Allocator_Mode,
	size, alignment: int,
	old: rawptr,
	old_size: int,
	loc := #caller_location,
) -> (
	[]byte,
	mem.Allocator_Error,
) {
	s := (^Spy)(data)
	if mode != .Query_Features && mode != .Query_Info {
		if s.n < len(s.at) {
			s.at[s.n] = loc
		}
		s.n += 1
	}
	return s.inner.procedure(s.inner.data, mode, size, alignment, old, old_size, loc)
}

@(test)
test_a_loading_source_shows_skeletons_after_its_rows :: proc(t: ^testing.T) {
	m := rigs_make(3)
	defer rigs_free(m)
	m.loading = true
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	testing.expect(t, ui.probe_tagged(&p, "SN-00002"))
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(said, `row "" row 5 busy`), said) // item 3, after the rows
	testing.expect_value(t, cells(&p), 3 * 4)
	m.loading = false
	ui.probe_frame(&p)
	testing.expect_value(t, m.g.geo.items, 3)
	testing.expect_value(t, heights_total(&m.g.heights), 3 * 33)
}

@(test)
test_export_all_writes_the_view_at_once_and_reset_puts_columns_back :: proc(t: ^testing.T) {
	m := rigs_make(50_000)
	defer rigs_free(m)
	view_set_values(&m.g.view, 2, {"Paraguay"})
	m.g.view.cols[1].hidden = true
	move_column(m.g.view.order[:], 3, 0)
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	testing.expect(t, export_all(&m.g, RIG_COLS, rigs_source(m)))
	text := strings.to_string(m.g.export.text)
	testing.expect(
		t,
		strings.has_prefix(text, "Hash,Serial,Site\r\n37,SN-00001,Paraguay\r\n"),
		text[:50],
	)
	testing.expect_value(t, strings.count(text, "\r\n"), 16_668) // the titles and a third of the rows
	view_reset_columns(&m.g.view, RIG_COLS)
	testing.expect(t, !m.g.view.cols[1].hidden)
	testing.expect_value(t, m.g.view.order[0], 0)
	testing.expect(t, view_filtered(&m.g.view, 2), "the filter stays")
}

// A skin's slot lays out in the cell the grid gives it: a widget its
// header slot draws sits over the header, wherever the column stands.
@(test)
test_a_skin_slot_lays_out_in_its_cell :: proc(t: ^testing.T) {
	m := rigs_make(5)
	defer rigs_free(m)
	m.skin.header = proc(gtx: ^ui.Ctx, h: ^Header, user: rawptr) {
		p := ui.widget_open(gtx)
		name := ui.frame_string(gtx, strings.concatenate({"slot ", h.column.title}, gtx.allocator))
		ops.tag(gtx.scene, p.id, name, ops.Rect{0, 0, h.size.x, h.size.y})
		ui.widget_close(gtx, &p, {size = h.size})
	}
	p: ui.Probe
	open(&p, m)
	defer ui.probe_destroy(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "slot Site"), ui.probe_bounds(&p, "Site"))
	testing.expect(t, ui.probe_bounds(&p, "slot Site").x > 0)
}
