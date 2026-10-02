/*
Package view is the file browser's ui, built from Fluent's own parts: a
toolbar with the folder's breadcrumb and a search box, a table of the
entries that sorts by its columns, and a details card for the selected
one. The folder's listing and every thumbnail are needs the application
answers; the ui holds the path, the selection, the sort and the search.
A double click on a folder goes into it, on a file asks the application
to open it.
*/
package files_view

import "core:fmt"
import "core:path/filepath"
import "core:slice"
import "core:strings"
import "core:time"

import "jm:ui"
import "jm:ui/fluent"
import "jm:ui/ops"

import "../../common"
import "../shapes"

THUMB :: 32 // in a row
PREVIEW :: 200 // in the details card
DETAILS :: 300
SIDEBAR :: 240
TOOLBAR_H :: 44
HISTORY :: 64 // folders remembered for back and forward
SEP :: filepath.SEPARATOR_STRING

Column :: enum u8 {
	Name,
	Size,
	Modified,
}

Model :: struct {
	theme:        fluent.Theme,
	scheme:       fluent.Scheme,
	path:         [common.MAX_PATH]u8, // the folder shown
	path_len:     int,
	// The folders visited, with the one shown at history_at: back and
	// forward walk it, and a new folder cuts off what was forward.
	history:      [HISTORY][common.MAX_PATH]u8,
	history_lens: [HISTORY]int,
	history_n:    int,
	history_at:   int,
	shown:        [common.MAX_PATH]u8, // the folder whose listing was drawn last; see listing_of
	shown_len:    int,
	waiting:      f64,
	list:         ui.List_State,
	selected:     [common.MAX_PATH]u8, // the entry selected, by path, so it survives a sort
	selected_len: int,
	search:       ui.Text_State,
	sort:         [Column]fluent.Sort_Direction,
	window:       ops.Size,
	// This frame's, for the rows: the listing, the entries in order after
	// the sort and the search, and the open table.
	listing:      ^shapes.Listing_Result,
	order:        []int,
	table:        fluent.Table,
}

model_init :: proc(m: ^Model, path: string) {
	m.sort[.Name] = .Ascending
	navigate(m, path)
}

model_destroy :: proc(m: ^Model) {
	ui.text_destroy(&m.search)
}

// navigate makes path the folder shown, from its top, with nothing
// selected and no search, and remembers it: what was forward is gone.
navigate :: proc(m: ^Model, path: string) {
	if m.history_n > 0 {
		m.history_n = m.history_at + 1
	}
	if m.history_n == HISTORY {
		copy(m.history[:], m.history[1:])
		copy(m.history_lens[:], m.history_lens[1:])
		m.history_n -= 1
	}
	m.history_lens[m.history_n] = copy(m.history[m.history_n][:], path)
	m.history_at = m.history_n
	m.history_n += 1
	show(m, path)
}

// show makes path the folder shown without touching the history.
@(private)
show :: proc(m: ^Model, path: string) {
	m.path_len = copy(m.path[:], path)
	m.list.offset = 0
	m.selected_len = 0
	ui.text_set(&m.search, "")
}

can_go_back :: proc(m: ^Model) -> bool {
	return m.history_at > 0
}

can_go_forward :: proc(m: ^Model) -> bool {
	return m.history_at + 1 < m.history_n
}

// go_back shows the folder visited before this one, as the mouse's back
// button, Alt with Left or the toolbar's button ask.
go_back :: proc(m: ^Model) {
	if can_go_back(m) {
		m.history_at -= 1
		show(m, string(m.history[m.history_at][:m.history_lens[m.history_at]]))
	}
}

go_forward :: proc(m: ^Model) {
	if can_go_forward(m) {
		m.history_at += 1
		show(m, string(m.history[m.history_at][:m.history_lens[m.history_at]]))
	}
}

path_of :: proc(m: ^Model) -> string {
	return string(m.path[:m.path_len])
}

selected_path :: proc(m: ^Model) -> string {
	return string(m.selected[:m.selected_len])
}

view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Model)(user)
	m.scheme = fluent.theme_scheme(m.theme)
	fluent.use(&m.scheme, fluent.mode_of(m.theme))
	fluent.use_fonts({0, 1, 2})
	s := &m.scheme
	m.window = gtx.constraints.max
	ops.fill(gtx.scene, ops.Rect{0, 0, m.window.x, m.window.y}, s[.Neutral_Background2])

	// Back and forward, from the mouse's side buttons or Alt with an
	// arrow, wherever the pointer is: keys the frame asks for app-wide.
	nav := ui.claim_id(gtx)
	ui.key_interest(gtx, nav, .Browser_Back)
	ui.key_interest(gtx, nav, .Browser_Forward)
	ui.key_interest(gtx, nav, .Left, {.Alt})
	ui.key_interest(gtx, nav, .Right, {.Alt})
	for e in ui.events(gtx, nav) {
		if e.kind != .Key {
			continue
		}
		#partial switch e.key {
		case .Browser_Back:
			go_back(m)
		case .Browser_Forward:
			go_forward(m)
		case .Left:
			go_back(m)
		case .Right:
			go_forward(m)
		}
	}

	outer := ui.column_open(gtx, align = .Fill)
	defer ui.close(&outer)
	toolbar(gtx, m)
	listing, have, loading := listing_of(gtx, m)
	m.listing = listing
	body := ui.row_open(gtx, align = .Fill)
	defer ui.close(&body)
	sidebar(gtx, m)
	{
		// The table's width is what the sidebar and the details card
		// leave, given so the first frame lays all three out exactly.
		table_w := max(m.window.x - SIDEBAR - DETAILS - 1, 200)
		pane := ui.sized_open(gtx, {min = {table_w, 0}, max = {table_w, ui.INF}})
		defer ui.close(&pane)
		col := ui.column_open(gtx, align = .Fill)
		defer ui.close(&col)
		status(gtx, m, listing, have)
		switch {
		case have && listing.error != "":
			pad := ui.inset_open(gtx, ui.pad_all(16))
			fluent.message_bar(gtx, .Error, "", listing.error)
			ui.close(&pad)
		case have:
			entries(gtx, m, listing)
		case loading:
			skeleton_rows(gtx, m)
		}
	}
	fluent.divider(gtx, vertical = true)
	details(gtx, m, listing if have else nil)
}

// toolbar is the top strip: up, the breadcrumb, and a search box at the
// end, on the Background 1 surface with a stroke under it.
@(private)
toolbar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	s := &m.scheme
	// The strip's surface, at its own height: a painted box would take
	// the height it is offered, which here is the window's.
	ops.fill(gtx.scene, ops.Rect{0, 0, m.window.x, TOOLBAR_H}, s[.Neutral_Background1])
	ops.fill(gtx.scene, ops.Rect{0, TOOLBAR_H - 1, m.window.x, 1}, s[.Neutral_Stroke2])
	strip := ui.sized_open(gtx, {min = {m.window.x, TOOLBAR_H}, max = {m.window.x, TOOLBAR_H}})
	defer ui.close(&strip)
	pad := ui.inset_open(gtx, {left = 8, right = 8, top = 6, bottom = 6})
	defer ui.close(&pad)
	tb := fluent.toolbar_open(gtx, .Small)
	defer fluent.toolbar_close(&tb)
	if fluent.toolbar_button(gtx, "", .Arrow_Left, name = "Back", state = .Live if can_go_back(m) else .Disabled) {
		go_back(m)
	}
	if fluent.toolbar_button(gtx, "", .Arrow_Right, name = "Forward", state = .Live if can_go_forward(m) else .Disabled) {
		go_forward(m)
	}
	if fluent.toolbar_button(gtx, "", .Arrow_Up, name = "Up", state = .Live if len(crumbs_of(path_of(m), context.temp_allocator)) > 1 else .Disabled) {
		up(m)
	}
	fluent.toolbar_divider(gtx)
	search_w: f32 = 240
	common.cell_open(gtx, max(m.window.x - 16 - 3 * 36 - 20 - search_w - 16, 100), .Start)
	crumbs := crumbs_of(path_of(m), gtx.allocator)
	if picked := fluent.breadcrumb(gtx, crumbs, .Small); picked >= 0 {
		navigate(m, crumb_path(crumbs, picked, gtx.allocator))
	}
	common.cell_close(gtx)
	common.cell_open(gtx, search_w + 16, .End)
	fluent.search_box(gtx, &m.search, "Search this folder", size = .Small, width = search_w, name = "Search")
	common.cell_close(gtx)
}

// status is the line over the table: how many entries, how many match,
// and what the application is doing.
@(private)
status :: proc(gtx: ^ui.Ctx, m: ^Model, listing: ^shapes.Listing_Result, have: bool) {
	s := &m.scheme
	pad := ui.inset_open(gtx, {left = 16, right = 16, top = 10, bottom = 6})
	defer ui.close(&pad)
	line: string
	if have && listing.error == "" {
		n := len(listing.entries)
		if ui.text_string(&m.search) != "" {
			line = fmt.tprintf("%d of %d items match", len(m.order), n)
		} else {
			line = fmt.tprintf("%d item%s", n, "" if n == 1 else "s")
		}
	}
	stats, status := ui.need(gtx, shapes.Stats{}, shapes.Stats_Result)
	if status == .Ready || status == .Stale {
		if stats.pending > 0 {
			line = fmt.tprintf("%s · %d thumbnail%s on the way", line, stats.pending, "" if stats.pending == 1 else "s")
		}
		line = fmt.tprintf("%s · %d open · %d folders read · %d thumbnails made · %d abandoned", line, stats.open, stats.listings, stats.thumbs, stats.cancelled)
	}
	fluent.text(gtx, line, s[.Neutral_Foreground3], .S200, selectable = false, truncate = true)
}

// listing_of is the listing to draw: the folder shown once it has
// arrived, and until then the last one drawn, which stays needed so it
// is not released under us. A wait is reported only once it has lasted
// common.LOADING_DELAY, with a frame asked for at the deadline.
@(private)
listing_of :: proc(gtx: ^ui.Ctx, m: ^Model) -> (listing: ^shapes.Listing_Result, ok: bool, loading: bool) {
	now, status := ui.need(gtx, shapes.Listing{path = path_of(m)}, shapes.Listing_Result)
	if status == .Ready || status == .Stale {
		m.shown_len = copy(m.shown[:], path_of(m))
		m.waiting = 0
		return now, true, false
	}
	if m.waiting == 0 {
		m.waiting = gtx.time
	}
	waited := gtx.time - m.waiting
	if waited < common.LOADING_DELAY {
		ui.request_frame(gtx, f32(common.LOADING_DELAY - waited))
	} else {
		loading = true
	}
	shown := string(m.shown[:m.shown_len])
	if shown != "" && shown != path_of(m) {
		last, lstatus := ui.need(gtx, shapes.Listing{path = shown}, shapes.Listing_Result)
		if lstatus == .Ready || lstatus == .Stale {
			return last, true, loading
		}
	}
	return nil, false, loading
}

// entries is the table: a header that sorts, and the rows that match
// the search, in a virtual list so a large folder costs only its
// visible rows.
@(private)
entries :: proc(gtx: ^ui.Ctx, m: ^Model, listing: ^shapes.Listing_Result) {
	s := &m.scheme
	m.order = ordered(m, listing, gtx.allocator)
	m.table = fluent.table_open(gtx, {0, 110, 130}, .Medium)
	defer fluent.table_close(&m.table)
	h := fluent.table_header_open(gtx, &m.table)
	for col in Column {
		before := m.sort[col]
		if fluent.table_header_cell(gtx, &h, COLUMN_NAMES[col], &m.sort[col], key = u64(col)) {
			for other in Column {
				if other != col {
					m.sort[other] = .None
				}
			}
			if before == .None {
				m.sort[col] = .Ascending
			}
		}
	}
	fluent.table_header_close(&h)
	if len(m.order) == 0 {
		pad := ui.inset_open(gtx, ui.pad_all(24))
		defer ui.close(&pad)
		fluent.text(gtx, "Nothing here" if ui.text_string(&m.search) == "" else "Nothing matches", s[.Neutral_Foreground3], selectable = false)
		return
	}
	ui.list(gtx, &m.list, len(m.order), row, m)
}

@(private)
COLUMN_NAMES := [Column]string{.Name = "Name", .Size = "Size", .Modified = "Modified"}


// ordered is the entries' indices after the search and the sort.
@(private)
ordered :: proc(m: ^Model, listing: ^shapes.Listing_Result, allocator := context.allocator) -> []int {
	query := strings.to_lower(ui.text_string(&m.search), allocator)
	out := make([dynamic]int, 0, len(listing.entries), allocator)
	for e, ii in listing.entries {
		if query == "" || strings.contains(strings.to_lower(e.name, allocator), query) {
			append(&out, ii)
		}
	}
	col, dir := Column.Name, fluent.Sort_Direction.Ascending
	for c in Column {
		if m.sort[c] != .None {
			col, dir = c, m.sort[c]
		}
	}
	Sorting :: struct {
		entries: []shapes.Entry,
		col:     Column,
		desc:    bool,
	}
	sorting := Sorting{listing.entries, col, dir == .Descending}
	context.user_ptr = &sorting
	slice.sort_by(out[:], proc(a, b: int) -> bool {
		so := (^Sorting)(context.user_ptr)
		x, y := so.entries[a], so.entries[b]
		if x.dir != y.dir {
			return x.dir // folders first, whatever the sort
		}
		less: bool
		switch so.col {
		case .Name:
			less = strings.compare(strings.to_lower(x.name, context.temp_allocator), strings.to_lower(y.name, context.temp_allocator)) < 0
		case .Size:
			less = x.size < y.size
		case .Modified:
			less = x.modified < y.modified
		}
		return less != so.desc
	})
	return out[:]
}

// row is one entry: its thumbnail or icon with its name, its size and
// its date, in a table row that selects on a click and acts on a
// double click.
@(private)
row :: proc(gtx: ^ui.Ctx, index: int, user: rawptr) {
	m := (^Model)(user)
	e := m.listing.entries[m.order[index]]
	sc := ui.scope_open(gtx, e.path)
	defer ui.scope_close(&sc)
	selected := e.path == selected_path(m)
	clicked, double := false, false
	r := fluent.table_row_open(gtx, &m.table, &selected, &clicked, .Neutral, name = e.name, double_clicked = &double)
	fluent.table_cell_layout(gtx, &r, e.name, media = media_of(gtx, e, THUMB))
	fluent.table_cell(gtx, &r, e.dir ? "" : size_text(e.size), color = m.scheme[.Neutral_Foreground3])
	fluent.table_cell(gtx, &r, date_text(e.modified), color = m.scheme[.Neutral_Foreground3])
	fluent.table_row_close(&r)
	if clicked {
		m.selected_len = copy(m.selected[:], e.path)
	}
	if double {
		act(gtx, m, e)
	}
}

// act enters a folder or opens a file, and tells the application it was
// visited, for the sidebar's Recent.
@(private)
act :: proc(gtx: ^ui.Ctx, m: ^Model, e: shapes.Entry) {
	visit(gtx, m, e.path, e.name, e.dir)
}

// visit is navigate or Open, as a Visited the application remembers
// for Recent, unless the place is a well-known one, which Recent never
// lists.
@(private)
visit :: proc(gtx: ^ui.Ctx, m: ^Model, path, name: string, dir: bool) {
	if dir {
		navigate(m, path)
	} else {
		ui.command(gtx, shapes.Open{path = path})
	}
	if !well_known(gtx, path) {
		ui.command(gtx, shapes.Visited{path = path, name = name, dir = dir})
	}
}

// well_known says whether path is one of the sidebar's Places.
@(private)
well_known :: proc(gtx: ^ui.Ctx, path: string) -> bool {
	places, status := ui.need(gtx, shapes.Places{}, shapes.Places_Result)
	if status != .Ready && status != .Stale {
		return false
	}
	for pl in places.items {
		if pl.path == path {
			return true
		}
	}
	return false
}

// sidebar is the nav on the left: the standard places, the folders
// pinned, with a row that pins or unpins the folder shown, and the
// places visited lately. Each list is a need the application keeps
// fresh from its store.
@(private)
sidebar :: proc(gtx: ^ui.Ctx, m: ^Model) {
	nav := fluent.nav_open(gtx, width = SIDEBAR)
	defer fluent.nav_close(&nav)
	current := path_of(m)
	fluent.nav_section_header(gtx, "Places")
	if places, status := ui.need(gtx, shapes.Places{}, shapes.Places_Result); status == .Ready || status == .Stale {
		for pl in places.items {
			sc := ui.scope_open(gtx, pl.path)
			ic: fluent.Icon = .Folder
			switch pl.name {
			case "Home":
				ic = .Home
			case "Pictures":
				ic = .Image
			}
			if fluent.nav_item(gtx, pl.name, pl.path, &current, ic) {
				visit(gtx, m, pl.path, pl.name, true)
			}
			ui.scope_close(&sc)
		}
	}
	fluent.nav_section_header(gtx, "Quick access")
	pinned := false
	if pins, status := ui.need(gtx, shapes.Pins{}, shapes.Pins_Result); status == .Ready || status == .Stale {
		for pl in pins.items {
			sc := ui.scope_open(gtx, pl.path)
			if pl.path == current {
				pinned = true
			}
			if fluent.nav_item(gtx, pl.name, pl.path, &current, .Star) {
				visit(gtx, m, pl.path, pl.name, true)
			}
			ui.scope_close(&sc)
		}
	}
	none: string
	if pinned {
		if fluent.nav_item(gtx, "Unpin this folder", "", &none, .Dismiss, key = 1) {
			ui.command(gtx, shapes.Unpin{path = current})
		}
	} else if fluent.nav_item(gtx, "Pin this folder", "", &none, .Add, key = 2) {
		ui.command(gtx, shapes.Pin{path = current, name = folder_name(current)})
	}
	// Recent is the snapshot the application took when the sidebar first
	// asked, less the well-known places, which have rows of their own.
	fluent.nav_section_header(gtx, "Recent")
	if recent, status := ui.need(gtx, shapes.Recent{}, shapes.Recent_Result); status == .Ready || status == .Stale {
		for pl in recent.items {
			if well_known(gtx, pl.path) {
				continue
			}
			sc := ui.scope_open(gtx, pl.path)
			if fluent.nav_item(gtx, pl.name, pl.path, &current, .Folder if pl.dir else .Document) {
				visit(gtx, m, pl.path, pl.name, pl.dir)
			}
			ui.scope_close(&sc)
		}
	}
}

// folder_name is what a folder is called in the sidebar: its last part,
// or the path itself at the root.
folder_name :: proc(path: string) -> string {
	crumbs := crumbs_of(path, context.temp_allocator)
	return crumbs[len(crumbs) - 1] if len(crumbs) > 0 else path
}

// media_of is the entry's picture at px, needed while the row is in
// view, or its icon until it comes.
@(private)
media_of :: proc(gtx: ^ui.Ctx, e: shapes.Entry, px: f32) -> fluent.Cell_Media {
	if e.image {
		if thumb, status := ui.need(gtx, shapes.Thumb{path = e.path, px = int(px)}, shapes.Thumb_Result); status == .Ready || status == .Stale {
			return {image = ops.add_image(gtx.scene, thumb.image), has_image = true, size = px}
		}
		return {icon = .Image, size = px}
	}
	return {icon = .Folder if e.dir else .Document, size = px}
}

// skeleton_rows stand in for a listing still on its way.
@(private)
skeleton_rows :: proc(gtx: ^ui.Ctx, m: ^Model) {
	pad := ui.inset_open(gtx, {left = 16, right = 16, top = 8, bottom = 8})
	defer ui.close(&pad)
	col := ui.column_open(gtx, gap = 12, align = .Fill)
	defer ui.close(&col)
	for ii in 0 ..< 6 {
		fluent.skeleton_item(gtx, 32, .Rectangle, key = u64(ii))
	}
}

// details is the card on the right: the selected entry's picture large,
// its name and facts, and a button that acts on it.
@(private)
details :: proc(gtx: ^ui.Ctx, m: ^Model, listing: ^shapes.Listing_Result) {
	s := &m.scheme
	pane := ui.sized_open(gtx, {min = {DETAILS, 0}, max = {DETAILS, ui.INF}})
	defer ui.close(&pane)
	pad := ui.inset_open(gtx, ui.pad_all(16))
	defer ui.close(&pad)
	e, have := selected_entry(m, listing)
	if !have {
		centred := ui.column_open(gtx, align = .Center)
		defer ui.close(&centred)
		ui.spacer(gtx, 48)
		fluent.text(gtx, "Select an item to see its details", s[.Neutral_Foreground3], .S200, selectable = false)
		return
	}
	// The card sits at the top of the pane at its content's height: a
	// painted box takes what it is offered, so it is offered no height.
	top := ui.column_open(gtx, align = .Fill)
	defer ui.close(&top)
	card := fluent.card_open(gtx, .Filled, .Medium)
	defer ui.close(&card)
	col := ui.column_open(gtx, gap = 12, align = .Center)
	defer ui.close(&col)
	preview(gtx, m, e)
	fluent.text(gtx, e.name, s[.Neutral_Foreground1], .S400, .Semibold, width = DETAILS - 64, truncate = true, selectable = false)
	facts := ui.column_open(gtx, gap = 4, align = .Fill)
	fact(gtx, m, "Kind", e.dir ? "Folder" : (e.image ? "Picture" : "File"))
	if !e.dir {
		fact(gtx, m, "Size", size_text(e.size))
	}
	fact(gtx, m, "Modified", date_text(e.modified))
	ui.close(&facts)
	if fluent.button(gtx, e.dir ? "Open folder" : "Open", .Primary, .Open, .Small, name = "Open") {
		act(gtx, m, e)
	}
}

@(private)
fact :: proc(gtx: ^ui.Ctx, m: ^Model, label, value: string) {
	s := &m.scheme
	r := ui.row_open(gtx, align = .Baseline)
	defer ui.close(&r)
	common.cell_open(gtx, 80, .Start)
	fluent.text(gtx, label, s[.Neutral_Foreground3], .S200, selectable = false)
	common.cell_close(gtx)
	common.cell_open(gtx, DETAILS - 64 - 80, .Start)
	fluent.text(gtx, value, s[.Neutral_Foreground1], .S200, selectable = false, truncate = true)
	common.cell_close(gtx)
}

// preview is the selected picture at PREVIEW, a need of its own, or
// the entry's icon large.
@(private)
preview :: proc(gtx: ^ui.Ctx, m: ^Model, e: shapes.Entry) {
	s := &m.scheme
	box := ui.sized_open(gtx, {min = {PREVIEW, PREVIEW}, max = {PREVIEW, PREVIEW}})
	defer ui.close(&box)
	if e.image {
		if thumb, status := ui.need(gtx, shapes.Thumb{path = e.path, px = PREVIEW}, shapes.Thumb_Result); status == .Ready || status == .Stale {
			id := ops.add_image(gtx.scene, thumb.image)
			ops.clip_push(gtx.scene, ops.Round_Rect{{0, 0, PREVIEW, PREVIEW}, 8})
			ops.image(gtx.scene, id, ops.Rect{0, 0, PREVIEW, PREVIEW})
			ops.clip_pop(gtx.scene)
			return
		}
		fluent.skeleton_item(gtx, PREVIEW, .Square)
		return
	}
	fluent.icon(gtx, e.dir ? .Folder : .Document, {(PREVIEW - 96) / 2, (PREVIEW - 96) / 2}, 96, s[.Neutral_Foreground3])
}

@(private)
selected_entry :: proc(m: ^Model, listing: ^shapes.Listing_Result) -> (e: shapes.Entry, ok: bool) {
	if listing == nil || m.selected_len == 0 {
		return
	}
	for entry in listing.entries {
		if entry.path == selected_path(m) {
			return entry, true
		}
	}
	return
}

// crumbs_of is the path as its components, the root first.
crumbs_of :: proc(path: string, allocator := context.allocator) -> []string {
	out := make([dynamic]string, allocator)
	if strings.has_prefix(path, SEP) {
		append(&out, SEP)
	}
	for part in strings.split(path, SEP, allocator) {
		if part != "" {
			append(&out, part)
		}
	}
	return out[:]
}

// crumb_path is the path down to crumb index.
crumb_path :: proc(crumbs: []string, index: int, allocator := context.allocator) -> string {
	b := strings.builder_make(allocator)
	for c, ii in crumbs[:index + 1] {
		if c == SEP {
			strings.write_string(&b, SEP)
			continue
		}
		if ii > 0 && crumbs[ii - 1] != SEP {
			strings.write_string(&b, SEP)
		}
		strings.write_string(&b, c)
	}
	return strings.to_string(b)
}

// up goes to the parent folder, if there is one.
up :: proc(m: ^Model) {
	crumbs := crumbs_of(path_of(m), context.temp_allocator)
	if len(crumbs) > 1 {
		navigate(m, crumb_path(crumbs, len(crumbs) - 2, context.temp_allocator))
	}
}


@(private)
size_text :: proc(size: i64) -> string {
	switch {
	case size >= 1 << 30:
		return fmt.tprintf("%.1f GB", f64(size) / (1 << 30))
	case size >= 1 << 20:
		return fmt.tprintf("%.1f MB", f64(size) / (1 << 20))
	case size >= 1 << 10:
		return fmt.tprintf("%d KB", size / (1 << 10))
	}
	return fmt.tprintf("%d B", size)
}

@(private)
date_text :: proc(unix: i64) -> string {
	year, month, day := time.date(time.unix(unix, 0))
	return fmt.tprintf("%04d-%02d-%02d", year, int(month), day)
}
