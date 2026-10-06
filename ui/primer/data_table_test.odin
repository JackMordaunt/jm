package primer

import "core:slice"
import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/datagrid"
import "jm:ui/ops"

// The Primer data grid through ui.Probe by tags: its density's rows, a
// header's sort and filter panel, the toolbar's search, views and
// Columns menu, groups, hover, a loading source; and the pagination
// bar on its own.

@(private = "file")
People :: struct {
	g:       Data_Grid,
	rows:    [][3]string,
	loading: bool,
	toolbar: bool,
	ev:      datagrid.Events,
}

@(private = "file")
PEOPLE_COLS := []datagrid.Column {
	{id = "name", title = "Name", row_header = true},
	{id = "role", title = "Role", filter = .Set},
	{id = "count", title = "Count", kind = .Number, align = .End},
}

@(private = "file")
PEOPLE := [][3]string {
	{"Ada", "Engineer", "1"},
	{"Grace Hopper", "Admiral", "100"},
	{"Linus", "Engineer", "7"},
}

@(private = "file")
people_make :: proc(toolbar := true) -> ^People {
	m := new(People, context.temp_allocator)
	m.rows, m.toolbar = PEOPLE, toolbar
	data_grid_init(&m.g, PEOPLE_COLS)
	return m
}

@(private = "file")
people_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^People)(user)
	text :: proc(user: rawptr, row, col: int) -> string {
		return (^People)(user).rows[row][col]
	}
	src := datagrid.Source {
		user    = m,
		rows    = len(m.rows),
		text    = text,
		loading = m.loading,
	}
	m.ev = data_grid(gtx, &m.g, PEOPLE_COLS, src, "People", toolbar = m.toolbar)
}

@(private = "file")
people_open :: proc(p: ^ui.Probe, m: ^People, size := ops.Size{700, 400}) {
	ui.probe_init(p, people_view, m, size, allocator = context.temp_allocator)
}

@(private = "file")
people_close :: proc(p: ^ui.Probe, m: ^People) {
	ui.probe_destroy(p)
	data_grid_destroy(&m.g)
	free_all(context.temp_allocator)
}

@(test)
test_data_grid_rows_are_the_density_s_padding_tall :: proc(t: ^testing.T) {
	for c in ([?]struct {
			density: datagrid.Density,
			header:  f32,
			row:     f32,
		}{{.Normal, 38, 37}, {.Condensed, 30, 29}, {.Spacious, 46, 45}}) {
		m := people_make(toolbar = false)
		m.g.grid.density = c.density
		p: ui.Probe
		people_open(&p, m)
		ui.probe_frame(&p)
		said := ui.probe_semantics(&p, context.temp_allocator)
		// Normal: a 1px rule above and below the header's 8px, 20px line
		// and 8px; a row is its 8px, 20px, 8px and its 1px rule.
		at := []string{`row 3 at 0,`, ftoa(c.header + c.row), " 700x", ftoa(c.row)}
		want := strings.concatenate(at, context.temp_allocator)
		testing.expectf(t, strings.contains(said, want), "%v: want %q in %s", c.density, want, said)
		people_close(&p, m)
	}
}

@(private = "file")
ftoa :: proc(v: f32) -> string {
	b := strings.builder_make(context.temp_allocator)
	strings.write_int(&b, int(v))
	return strings.to_string(b)
}

@(test)
test_a_header_click_sorts_and_shows_its_octicon :: proc(t: ^testing.T) {
	m := people_make()
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	testing.expect(t, ui.probe_click(&p, "Count"))
	testing.expect_value(t, m.g.grid.view.sort[0], datagrid.Sort_Key{2, false})
	testing.expect(t, icon_drawn(&p, .Sort_Asc, color(.Fg_Color_Default)))
	ui.probe_click(&p, "Count")
	testing.expect(t, icon_drawn(&p, .Sort_Desc, color(.Fg_Color_Default)))
	first := datagrid.item_at(&m.g.grid, {rows = 3}, 0)
	testing.expect_value(t, first.row, 1) // Grace Hopper's 100 first
}

@(private = "file")
icon_drawn :: proc(p: ^ui.Probe, i: Icon, c: ops.Color) -> bool {
	paths, _ := icon_paths(i, BUTTON_ICON)
	path := paths[0]
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if pr, is_path := f.shape.(ops.Path_Ref); is_path {
				got := p.scene.paths[pr.id]
				col, solid := f.paint.(ops.Color)
				if solid && col == c && slice.equal(got.verbs, path.verbs) {
					return true
				}
			}
		}
	}
	return false
}

@(test)
test_a_header_filter_panel_lists_values_with_counts_and_filters :: proc(t: ^testing.T) {
	m := people_make()
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	testing.expect(t, ui.probe_click(&p, "Filter Role"))
	testing.expect(t, m.g.filter.open)
	testing.expect_value(t, len(m.g.filter.items), 2)
	testing.expect_value(t, m.g.filter.items[1].text, "Engineer") // natural order
	testing.expect_value(t, m.g.filter.items[1].description, "2") // its count
	ui.probe_type(&p, "adm") // the panel's field has focus
	ui.probe_frame(&p)
	testing.expect_value(t, len(m.g.filter.items), 1)
	ui.probe_key(&p, .Enter)
	testing.expect(t, datagrid.view_filtered(&m.g.grid.view, 1))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Grace Hopper"))
	testing.expect(t, !ui.probe_tagged(&p, "Ada"), "an Engineer, filtered out")
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.g.filter.open)
	testing.expect(t, ui.probe_click(&p, "Clear filters"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Ada"))
	testing.expect(t, !ui.probe_tagged(&p, "Clear filters"), "shown only while a filter is on")
}

@(test)
test_the_keyboard_opens_a_header_s_filter_panel :: proc(t: ^testing.T) {
	m := people_make()
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	ui.probe_click(&p, "Ada")
	ui.probe_key(&p, .Up) // onto the header
	ui.probe_key(&p, .Right)
	ui.probe_key(&p, .Down, {.Alt})
	ui.probe_frame(&p)
	testing.expect(t, m.g.filter.open && m.g.filter.col == 1)
}

@(test)
test_the_toolbar_search_finds_rows_and_counts_them :: proc(t: ^testing.T) {
	m := people_make()
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	testing.expect(t, ui.probe_tagged(&p, "3 rows"))
	ui.probe_click(&p, "Search People")
	ui.probe_type(&p, "hop")
	ui.probe_frame(&p)
	testing.expect_value(t, m.g.grid.view.search, "hop")
	testing.expect(t, ui.probe_tagged(&p, "1 row"))
	testing.expect(t, !ui.probe_tagged(&p, "Linus"))
	ui.probe_click(&p, "Grace Hopper")
	testing.expect(t, ui.probe_tagged(&p, "1 row · 1 selected"))
}

@(test)
test_a_saved_view_comes_back_from_the_views_menu :: proc(t: ^testing.T) {
	m := people_make()
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	datagrid.view_set_values(&m.g.grid.view, 1, {"Admiral"})
	data_grid_save_view(&m.g, "Admirals")
	datagrid.view_clear_filters(&m.g.grid.view)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Ada"))
	testing.expect(t, ui.probe_click(&p, "Views · Admirals"))
	testing.expect(t, ui.probe_click(&p, "Admirals"))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "Ada"), "the view's filter is back")
	testing.expect_value(t, m.g.applied, 0)
	data_grid_delete_view(&m.g, 0)
	testing.expect_value(t, len(m.g.views), 0)
	testing.expect_value(t, m.g.applied, -1)
}

@(test)
test_the_columns_menu_hides_a_column_and_downloads_csv :: proc(t: ^testing.T) {
	m := people_make()
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	testing.expect(t, ui.probe_click(&p, "Columns"))
	testing.expect(t, click_nth(&p, "Role", 1), "the menu's first Role, after the header's")
	testing.expect(t, m.g.grid.view.cols[1].hidden)
	// Count: its header, then Show, Pin to the left, Pin to the right.
	testing.expect(t, click_nth(&p, "Count", 3))
	testing.expect_value(t, m.g.grid.view.cols[2].pin, datagrid.Pin.Right)
	ui.probe_key(&p, .Escape)
	ui.probe_click(&p, "Columns")
	testing.expect(t, ui.probe_click(&p, "Download CSV"))
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	want := "Name,Count\r\nAda,1\r\nGrace Hopper,100\r\nLinus,7\r\n"
	testing.expect_value(t, strings.to_string(m.g.csv), want)
	testing.expect(t, ui.probe_tagged(&p, "Exported 3 rows"))
}

@(test)
test_a_group_shows_its_count_and_speaks_row_or_rows :: proc(t: ^testing.T) {
	m := people_make(toolbar = false)
	m.g.grid.view.group = 1
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	said := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(said, `"Admiral, 1 row"`), "one row is singular: %s", said)
	testing.expectf(t, strings.contains(said, `"Engineer, 2 rows"`), "two are plural: %s", said)
	testing.expect(t, ui.probe_click(&p, "Engineer, 2 rows"))
	testing.expect(t, !ui.probe_tagged(&p, "Ada"), "the group shut")
}

// A hovered body row fills with the transparent control hover.
@(test)
test_a_hovered_row_lights :: proc(t: ^testing.T) {
	m := people_make(toolbar = false)
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	lit :: proc(p: ^ui.Probe) -> int {
		n := 0
		for op in p.scene.ops {
			if f, ok := op.(ops.Fill); ok {
				if c, solid := f.paint.(ops.Color); solid && c == color(.Control_Transparent_Bg_Color_Hover) {
					n += 1
				}
			}
		}
		return n
	}
	before := lit(&p)
	c, _ := ui.probe_center(&p, "Linus")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_frame(&p)
	testing.expect_value(t, lit(&p), before + 1)
}

@(test)
test_a_loading_grid_draws_skeleton_bars_and_an_empty_one_says_so :: proc(t: ^testing.T) {
	m := people_make(toolbar = false)
	m.rows, m.loading = nil, true
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	bars := 0
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if c, solid := f.paint.(ops.Color); solid && c == color(.Skeleton_Loader_Bg_Color) {
				bars += 1
			}
		}
	}
	testing.expect(t, bars >= 3 * 9, "a view of skeleton rows, three bars each")
	m.loading = false
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "No rows"))
}

// A grid wider than its box keeps its columns and scrolls sideways.
@(test)
test_a_wide_grid_scrolls_rather_than_squeezes :: proc(t: ^testing.T) {
	m := people_make(toolbar = false)
	p: ui.Probe
	people_open(&p, m, {200, 400})
	defer people_close(&p, m)
	c, _ := ui.probe_center(&p, "Ada")
	ui.router_push(&p.router, {kind = .Scroll, pos = c, scroll = {1e6, 0}})
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	hundred := ui.probe_bounds(&p, "100")
	testing.expect(t, hundred.w > 0 && hundred.x + hundred.w <= 200, "scrolled to the last column")
	testing.expect(t, m.g.grid.scroll.x > 0)
}

@(private = "file")
Pager_Model :: struct {
	page:  int,
	pages: int,
}

@(test)
test_pagination_shows_ends_and_two_either_side :: proc(t: ^testing.T) {
	defer free_all(context.temp_allocator)
	got := page_numbers(9, 20, context.temp_allocator)
	testing.expect(t, slice.equal(got, []int{0, -1, 7, 8, 9, 10, 11, -2, 19}))
	got = page_numbers(0, 3, context.temp_allocator)
	testing.expect(t, slice.equal(got, []int{0, 1, 2}))
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Pager_Model)(user)
		if data_table_pagination(gtx, "People pages", &m.page, 200, 10) {
			m.pages += 1
		}
	}
	m: Pager_Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {900, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	ui.probe_click(&p, "Previous page") // disabled on the first page
	testing.expect_value(t, m.page, 0)
	testing.expect(t, ui.probe_click(&p, "Next page"))
	testing.expect_value(t, m.page, 1)
	testing.expect(t, ui.probe_click(&p, "Page 20"))
	testing.expect_value(t, m.page, 19)
	ui.probe_click(&p, "Next page") // disabled on the last
	testing.expect_value(t, m.page, 19)
	testing.expect_value(t, m.pages, 2)
	testing.expect(t, ui.probe_tagged(&p, "Page 1"))
	testing.expect(t, !ui.probe_tagged(&p, "Page 10")) // truncated
}

// click_nth clicks the nth area tagged name, from 0 in the order drawn:
// of two, 1 is the one drawn over the other, as a menu's item over a
// header of the same name.
@(private = "file")
click_nth :: proc(p: ^ui.Probe, name: string, n: int) -> bool {
	seen := 0
	for tag in ui.probe_current(p).tags {
		if tag.name != name {
			continue
		}
		if seen == n {
			ui.probe_click_at(p, {tag.bounds.x + tag.bounds.w / 2, tag.bounds.y + tag.bounds.h / 2})
			return true
		}
		seen += 1
	}
	return false
}

// The grid is one Tab stop: Tab from its rows leaves it, past the
// headers' filter buttons, and Shift+Tab goes back to the toolbar.
@(test)
test_the_grid_is_one_tab_stop :: proc(t: ^testing.T) {
	m := people_make()
	p: ui.Probe
	people_open(&p, m)
	defer people_close(&p, m)
	ui.probe_click(&p, "Ada")
	testing.expect(t, m.g.grid.focused)
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	testing.expect(t, !m.g.grid.focused)
	testing.expect_value(t, ui.probe_focus_name(&p), "Search People") // round again
	ui.probe_click(&p, "Ada")
	ui.probe_key(&p, .Tab, {.Shift})
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Columns")
}
