package primer

import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of PageHeader, PageLayout and SplitPageLayout through
// ui.Probe by tags.

@(private = "file")
tagged_box :: proc(gtx: ^ui.Ctx, name: string, size: ops.Size, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	sz := ui.constrain(gtx.constraints, size)
	ops.tag(gtx.scene, p.id, name, {0, 0, sz.x, sz.y})
	ui.widget_close(gtx, &p, {size = sz})
}

@(private = "file")
Page_Header_Model :: struct {
	title:      string,
	backs, ups: int,
}

@(private = "file")
page_header_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Page_Header_Model)(user)
	col := ui.column_open(gtx, align = .Fill)
	defer ui.close(&col)
	h := page_header_open(gtx, m.title, leading_visual = .Repo, has_border = true)
	if page_header_parent_link(&h, "Up") {
		m.ups += 1
	}
	page_header_slot_open(&h, .Actions)
	button(gtx, "Edit")
	button(gtx, "Delete", .Danger)
	page_header_slot_close(&h)
	page_header_slot_open(&h, .Leading_Action)
	if icon_button(gtx, .Arrow_Left, "Back", .Invisible) {
		m.backs += 1
	}
	page_header_slot_close(&h)
	page_header_slot_open(&h, .Description)
	tagged_box(gtx, "description", {200, 20})
	page_header_slot_close(&h)
	page_header_close(&h)
	tagged_box(gtx, "after", {10, 10})
}

@(test)
test_page_header_places_row_two_and_its_actions_by_the_css :: proc(t: ^testing.T) {
	m := Page_Header_Model{title = "Settings"}
	p: ui.Probe
	ui.probe_init(&p, page_header_view, &m, {1000, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	line := title_style(.Medium).line_height // 32.5
	back := ui.probe_bounds(&p, "Back")
	testing.expect_value(t, back.x, 0) // regular: the leading action shows, first
	testing.expect_value(t, back.y, (line - tok.CONTROL_MEDIUM_SIZE) / 2) // centred in one title line
	title := ui.probe_bounds(&p, "Settings")
	// after the leading action and its 8px, the 16px visual and 8px gap
	testing.expect_value(t, title.x, tok.CONTROL_MEDIUM_SIZE + 8 + BUTTON_ICON + 8)
	testing.expect_value(t, title.y, 0)
	del := ui.probe_bounds(&p, "Delete")
	testing.expect_value(t, del.x + del.w, 1000) // actions end-aligned
	edit := ui.probe_bounds(&p, "Edit")
	testing.expect_value(t, del.x - (edit.x + edit.w), tok.STACK_GAP_CONDENSED)
	testing.expect_value(t, ui.probe_bounds(&p, "Up"), ops.Rect{}) // the parent link shows only when narrow
	desc := ui.probe_bounds(&p, "description")
	testing.expect_value(t, desc.y, line + 8)
	// The border: 8px under the description, then 1px.
	testing.expect_value(t, ui.probe_bounds(&p, "after").y, desc.y + 20 + 8 + 1)
	testing.expect(t, ui.probe_click(&p, "Back"))
	testing.expect_value(t, m.backs, 1)
}

@(test)
test_page_header_at_narrow_widths_swaps_the_leading_action_for_the_parent_link :: proc(t: ^testing.T) {
	m := Page_Header_Model{title = "Settings"}
	p: ui.Probe
	ui.probe_init(&p, page_header_view, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, ui.probe_bounds(&p, "Back"), ops.Rect{})
	up := ui.probe_bounds(&p, "Up")
	testing.expect_value(t, up.y, 0)
	title := ui.probe_bounds(&p, "Settings")
	testing.expect_value(t, title.y, up.h + 8) // the context area, then 8px
	testing.expect_value(t, title.x, BUTTON_ICON + 8)
	testing.expect(t, ui.probe_click(&p, "Up"))
	testing.expect_value(t, m.ups, 1)
}

// A long title wraps beside the actions, which keep their width.
@(test)
test_page_header_title_wraps_beside_its_actions :: proc(t: ^testing.T) {
	m := Page_Header_Model{title = "A very long page title that cannot fit on one line beside its actions at this width"}
	p: ui.Probe
	ui.probe_init(&p, page_header_view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	title := ui.probe_bounds(&p, m.title)
	edit := ui.probe_bounds(&p, "Edit")
	testing.expect(t, title.h >= 2 * title_style(.Medium).line_height) // wrapped
	testing.expect(t, title.x + title.w <= edit.x - 8)
	testing.expect_value(t, ui.probe_bounds(&p, "Delete").x + ui.probe_bounds(&p, "Delete").w, 800)
}

@(private = "file")
Layout_Model :: struct {
	pane:     Pane,
	width:    f32,
	settled:  int,
	scroll:   ui.Scroll_Offset,
	tall:     f32,
}

@(private = "file")
page_layout_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Layout_Model)(user)
	sb := ui.scroll_box_open(gtx, offset = &m.scroll)
	defer ui.close(&sb)
	pane := m.pane
	pane.width = &m.width
	l := page_layout_open(gtx, pane = pane)
	page_layout_region_open(&l, .Header, divider = .Line)
	tagged_box(gtx, "header", {100, 30})
	page_layout_region_close(&l)
	page_layout_region_open(&l, .Pane) // before the content: placement is the layout's
	tagged_box(gtx, "pane", {50, 200})
	page_layout_region_close(&l)
	page_layout_region_open(&l, .Content)
	tagged_box(gtx, "content", {100, m.tall > 0 ? m.tall : 400})
	page_layout_region_close(&l)
	page_layout_region_open(&l, .Footer)
	tagged_box(gtx, "footer", {100, 20})
	page_layout_region_close(&l)
	if page_layout_close(&l) {
		m.settled += 1
	}
}

@(test)
test_page_layout_places_its_regions_at_regular_widths :: proc(t: ^testing.T) {
	m := Layout_Model{pane = {position = .End, divider = .Line}}
	p: ui.Probe
	ui.probe_init(&p, page_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// 1100 >= 1012: normal spacing is 24; the container is 1100 - 48.
	header := ui.probe_bounds(&p, "header")
	testing.expect_value(t, header, ops.Rect{24, 24, 1052, 30})
	row := f32(24 + 30 + 24 + 1 + 24) // header, rowGap, its line, rowGap
	content := ui.probe_bounds(&p, "content")
	pane := ui.probe_bounds(&p, "pane")
	testing.expect_value(t, pane.w, 296) // medium from 1012px
	testing.expect_value(t, pane.x, 24 + 1052 - 296) // at the end
	testing.expect_value(t, content.x, 24)
	testing.expect_value(t, content.w, 1052 - 296 - (24 + 1 + 24)) // the divider centred in two gaps
	testing.expect_value(t, content.y, row)
	testing.expect_value(t, pane.y, row)
	footer := ui.probe_bounds(&p, "footer")
	testing.expect_value(t, footer.y, row + 400 + 24) // the taller content, then rowGap
}

@(test)
test_page_layout_stacks_the_pane_at_narrow_widths :: proc(t: ^testing.T) {
	m := Layout_Model{pane = {position = .Start, divider = .Filled}}
	p: ui.Probe
	ui.probe_init(&p, page_layout_view, &m, {700, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// Below 1012px normal spacing is 16; below 768px the pane is full width.
	pane := ui.probe_bounds(&p, "pane")
	content := ui.probe_bounds(&p, "content")
	testing.expect_value(t, pane.w, 700 - 32)
	row := f32(16 + 30 + 16 + 1 + 16)
	testing.expect_value(t, pane.y, row) // start: above the content
	testing.expect_value(t, content.y, row + 200 + 16 + tok.BASE_SIZE_8 + 16) // rowGap, the 8px band, rowGap
	// The filled band runs past the root's padding to the page's edges.
	band := false
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if r, is_rect := f.shape.(ops.Rect); is_rect && r == (ops.Rect{0, row + 200 + 16, 700, tok.BASE_SIZE_8}) {
				band = true
			}
		}
	}
	testing.expect(t, band)
}

@(test)
test_a_resizable_pane_drags_steps_and_resets :: proc(t: ^testing.T) {
	m := Layout_Model{pane = {position = .Start, resizable = true}}
	p: ui.Probe
	ui.probe_init(&p, page_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	handle :: "Draggable pane splitter"
	testing.expect_value(t, m.width, 296) // a resizable medium pane starts at 296
	h := ui.probe_bounds(&p, handle)
	testing.expect_value(t, h.w, 5) // the 1px line and 2px each side
	testing.expect_value(t, h.x, 24 + 296 + 24 - 2)
	testing.expect(t, ui.probe_drag(&p, handle, 40, 0))
	testing.expect_value(t, m.width, 336)
	testing.expect_value(t, m.settled, 1) // saved once, on release
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "pane").w, 336)
	// Dragged far right, it stops at the window less 511px.
	ui.probe_drag(&p, handle, 1000, 0)
	testing.expect_value(t, m.width, 1100 - 511)
	// Far left, at the 256px floor.
	ui.probe_drag(&p, handle, -1000, 0)
	testing.expect_value(t, m.width, 256)
	// Arrows step 3px while it has focus.
	ui.probe_click(&p, handle)
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.width, 259)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, m.width, 256)
	// A double-click resets it.
	c, _ := ui.probe_center(&p, handle)
	ui.router_push(&p.router, {kind = .Press, pos = c, button = .Left, clicks = 2})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Release, pos = c, button = .Left})
	ui.probe_frame(&p)
	testing.expect_value(t, m.width, 296)
}

// A sticky pane stays pinned at the top of the page's scroll box, its
// offset below it, while the content scrolls past.
@(test)
test_a_sticky_pane_stays_in_view_while_the_page_scrolls :: proc(t: ^testing.T) {
	m := Layout_Model{pane = {position = .Start, sticky = true, offset_header = 10}, tall = 2000}
	p: ui.Probe
	ui.probe_init(&p, page_layout_view, &m, {1100, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	start := ui.probe_bounds(&p, "pane").y
	m.scroll.y = 800
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "pane").y, 10)
	testing.expect_value(t, ui.probe_bounds(&p, "content").y, start - 800)
}

@(private = "file")
Sidebar_Model :: struct {
	sidebar: Sidebar,
	width:   f32,
	settled: int,
	scroll:  ui.Scroll_Offset,
	tall:    f32, // the sidebar's content height; 0 means 100
	content: f32, // the content's height; 0 means 400
}

@(private = "file")
sidebar_layout_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Sidebar_Model)(user)
	sb := ui.scroll_box_open(gtx, offset = &m.scroll)
	defer ui.close(&sb)
	side := m.sidebar
	side.width = &m.width
	l := page_layout_open(gtx, sidebar = side)
	page_layout_region_open(&l, .Sidebar) // first: placement is the layout's
	tagged_box(gtx, "sidebar", {50, m.tall > 0 ? m.tall : 100})
	page_layout_region_close(&l)
	page_layout_region_open(&l, .Header, divider = .Line)
	tagged_box(gtx, "header", {100, 30})
	page_layout_region_close(&l)
	page_layout_region_open(&l, .Content)
	tagged_box(gtx, "content", {100, m.content > 0 ? m.content : 400})
	page_layout_region_close(&l)
	page_layout_region_open(&l, .Footer)
	tagged_box(gtx, "footer", {100, 20})
	page_layout_region_close(&l)
	if page_layout_close(&l) {
		m.settled += 1
	}
}

// filled reports whether the scene fills exactly r.
@(private = "file")
filled :: proc(p: ^ui.Probe, r: ops.Rect) -> bool {
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok {
			if got, is_rect := f.shape.(ops.Rect); is_rect && got == r {
				return true
			}
		}
	}
	return false
}

// SIDEBAR_STACK is the container's column at 1100px: the header, rowGap,
// its line, rowGap, the 400px content, rowGap, the footer.
@(private = "file")
SIDEBAR_STACK :: f32(30 + 24 + 1 + 24 + 400 + 24 + 20)

@(test)
test_a_sidebar_sits_at_the_start_beside_header_content_and_footer :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {position = .Start}}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// Medium is 296px from 1012px; no divider leaves columnGap after it.
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar"), ops.Rect{24, 24, 296, 100})
	x := f32(24 + 296 + 24)
	w := f32(1100 - 24) - x
	testing.expect_value(t, ui.probe_bounds(&p, "header"), ops.Rect{x, 24, w, 30})
	footer := ui.probe_bounds(&p, "footer")
	testing.expect_value(t, footer.x, x)
	testing.expect_value(t, footer.y, 24 + SIDEBAR_STACK - 20)
	testing.expect_value(t, ui.probe_bounds(&p, "content").w, w)
}

@(test)
test_a_sidebar_at_the_end_runs_its_divider_the_full_height :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {position = .End, divider = .Line}}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	side := ui.probe_bounds(&p, "sidebar")
	testing.expect_value(t, side, ops.Rect{1100 - 24 - 296, 24, 296, 100})
	// The line sits columnGap before the sidebar and columnGap after the
	// container, down the whole row though the sidebar is shorter.
	testing.expect(t, filled(&p, {side.x - 24 - 1, 24, 1, SIDEBAR_STACK}))
	testing.expect_value(t, ui.probe_bounds(&p, "header"), ops.Rect{24, 24, side.x - 24 - 1 - 24 - 24, 30})
}

@(test)
test_a_taller_sidebar_sets_the_rows_height :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {divider = .Line}, tall = 1000}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, filled(&p, {24 + 296 + 24, 24, 1, 1000}))
	testing.expect_value(t, ui.probe_bounds(&p, "footer").y, 24 + SIDEBAR_STACK - 20) // the column keeps its top
}

@(test)
test_sidebar_width_presets_follow_the_panes :: proc(t: ^testing.T) {
	Case :: struct {
		vw:     f32,
		preset: Pane_Width,
		want:   f32,
	}
	cases := [?]Case {
		{1100, .Small, 256},
		{1100, .Medium, 296},
		{1100, .Large, 320},
		{900, .Small, 240},
		{900, .Medium, 256},
		{900, .Large, 256},
		{600, .Medium, 256}, // below 768px an inline sidebar keeps its 768px width
	}
	for c in cases {
		m := Sidebar_Model{sidebar = {preset = c.preset}}
		p: ui.Probe
		ui.probe_init(&p, sidebar_layout_view, &m, {c.vw, 900}, allocator = context.temp_allocator)
		got := ui.probe_bounds(&p, "sidebar").w
		testing.expectf(t, got == c.want, "%v at %v: %v, want %v", c.preset, c.vw, got, c.want)
		ui.probe_destroy(&p)
	}
	free_all(context.temp_allocator)
}

@(test)
test_a_hidden_sidebar_takes_no_room :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {hidden = true}}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar"), ops.Rect{})
	testing.expect_value(t, ui.probe_bounds(&p, "header"), ops.Rect{24, 24, 1052, 30})
}

@(test)
test_a_resizable_sidebar_clamps_to_the_window_less_256 :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {resizable = true, label = "Sidebar splitter"}}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	handle :: "Sidebar splitter"
	testing.expect_value(t, m.width, 296)
	// Resizable draws a line; the handle reaches 2px past it, full height.
	testing.expect_value(t, ui.probe_bounds(&p, handle), ops.Rect{24 + 296 + 24 - 2, 24, 5, SIDEBAR_STACK})
	testing.expect(t, ui.probe_drag(&p, handle, 40, 0))
	testing.expect_value(t, m.width, 336)
	testing.expect_value(t, m.settled, 1)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar").w, 336)
	ui.probe_drag(&p, handle, 1000, 0)
	testing.expect_value(t, m.width, 1100 - 256) // not the pane's 511
	ui.probe_drag(&p, handle, -1000, 0)
	testing.expect_value(t, m.width, 256)
	ui.probe_click(&p, handle)
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.width, 259)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, m.width, 256)
}

// At the end, Left grows the sidebar and a drag left widens it; a custom
// max is capped to the window less 256px.
@(test)
test_an_end_sidebar_mirrors_its_keys_and_caps_a_custom_max :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {position = .End, resizable = true, preset = .Custom, custom = {200, 300, 2000}, label = "Sidebar splitter"}}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {1100, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	handle :: "Sidebar splitter"
	testing.expect_value(t, m.width, 300)
	ui.probe_click(&p, handle)
	ui.probe_key(&p, .Left)
	testing.expect_value(t, m.width, 303)
	ui.probe_drag(&p, handle, -10, 0)
	testing.expect_value(t, m.width, 313)
	ui.probe_drag(&p, handle, -2000, 0)
	testing.expect_value(t, m.width, 1100 - 256)
	ui.probe_drag(&p, handle, 2000, 0)
	testing.expect_value(t, m.width, 200)
}

// A sticky sidebar is the window's height, pinned at the top of the
// page's scroll box while the page scrolls; its overflow scrolls inside.
@(test)
test_a_sticky_sidebar_pins_at_the_top_at_the_windows_height :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {sticky = true, divider = .Line}, tall = 1000, content = 2000}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {1100, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar").y, 24)
	testing.expect(t, filled(&p, {24 + 296 + 24, 0, 1, 600})) // its divider is as tall, and moves with it
	m.scroll.y = 800
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar").y, 0)
	testing.expect_value(t, ui.probe_bounds(&p, "header").y, 24 - 800)
}

// Below 768px a fullscreen sidebar covers the window and leaves the
// container the whole row; the default variant stays inline, as the
// fullscreen one does from 768px.
@(test)
test_a_fullscreen_sidebar_covers_the_window_below_768 :: proc(t: ^testing.T) {
	m := Sidebar_Model{sidebar = {variant = .Fullscreen, divider = .Line}}
	p: ui.Probe
	ui.probe_init(&p, sidebar_layout_view, &m, {600, 900}, allocator = context.temp_allocator)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar"), ops.Rect{0, 0, 600, 100})
	testing.expect(t, filled(&p, {0, 0, 600, 900}))
	testing.expect_value(t, ui.probe_bounds(&p, "header"), ops.Rect{16, 16, 600 - 32, 30})

	m.sidebar.variant = .Default
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar"), ops.Rect{16, 16, 256, 100})
	testing.expect_value(t, ui.probe_bounds(&p, "header").x, 16 + 256 + 16 + 1 + 16) // its line stays
	ui.probe_destroy(&p)

	m.sidebar.variant = .Fullscreen
	ui.probe_init(&p, sidebar_layout_view, &m, {800, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "sidebar"), ops.Rect{16, 16, 256, 100})
}
