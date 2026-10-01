package material

import "core:testing"
import "jm:ui/ops"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Behaviour of the navigation group (navigation.odin, app_bar.odin),
// driven through ui.Probe by the components' tags.

@(private = "file")
ITEMS := [?]Nav_Item {
	{label = "Mail", icon = .Mail},
	{label = "Chat", icon = .Chat_Bubble},
	{label = "Rooms", icon = .Home},
}

@(private = "file")
Nav_Model :: struct {
	selected: int,
	open:     bool,
	modal:    bool,
	variant:  Drawer_Kind,
	clicked:  int,
	result:   App_Bar_Result,
	tab:      int,
	sizes:    [3]ops.Size,
}

// bounds is the device-space bounding rect of the area tagged name.
@(private = "file")
bounds :: proc(p: ^ui.Probe, name: string) -> (ops.Rect, bool) {
	h, ok := ui.probe_find(p, name)
	if !ok {
		return {}, false
	}
	return ops.transform_rect(h.transform, ops.shape_bounds(&p.scene, h.shape)), true
}

// click_at presses and releases at pt, as probe_click does at a tag.
@(private = "file")
click_at :: proc(p: ^ui.Probe, pt: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = pt})
	ui.router_push(&p.router, {kind = .Press, pos = pt, button = .Left})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Release, pos = pt, button = .Left})
	ui.probe_frame(p)
}

@(private = "file")
tagged :: proc(p: ^ui.Probe, name: string) -> bool {
	_, ok := ui.probe_find(p, name)
	return ok
}

@(test)
test_rail_expands_on_its_spring_and_selects :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		r := ui.row_open(gtx)
		defer ui.close(&r)
		navigation_rail(gtx, ITEMS[:], &m.selected, .Edit, true, &m.open, modal = m.modal, height = 500)
	}
	m: Nav_Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	r, ok := bounds(&p, "Mail")
	testing.expect(t, ok)
	testing.expect_value(t, r.w, tok.NAVIGATION_RAIL_COLLAPSED_CONTAINER_WIDTH)
	testing.expect_value(t, r.h, tok.NAVIGATION_RAIL_BASELINE_ITEM_CONTAINER_HEIGHT)

	testing.expect(t, ui.probe_click(&p, "Expand navigation"))
	testing.expect(t, m.open)
	// Mid-flight the rail is between its widths; settled, it hugs its
	// widest item, floored at the expanded minimum, and rows are 56dp.
	ui.probe_advance(&p, 3, 0.016)
	r, _ = bounds(&p, "Mail")
	testing.expect(t, r.w > tok.NAVIGATION_RAIL_COLLAPSED_CONTAINER_WIDTH && r.w < tok.NAVIGATION_RAIL_EXPANDED_CONTAINER_WIDTH_MINIMUM)
	ui.probe_advance(&p, 120, 0.016)
	r, _ = bounds(&p, "Mail")
	testing.expect_value(t, r.w, tok.NAVIGATION_RAIL_EXPANDED_CONTAINER_WIDTH_MINIMUM)
	testing.expect_value(t, r.h, tok.NAVIGATION_RAIL_HORIZONTAL_ITEM_ACTIVE_INDICATOR_HEIGHT)

	testing.expect(t, ui.probe_click(&p, "Rooms"))
	testing.expect_value(t, m.selected, 2)
	testing.expect(t, ui.probe_click(&p, "Collapse navigation"))
	testing.expect(t, !m.open)
}

@(test)
test_modal_rail_collapses_on_scrim_and_escape :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		r := ui.row_open(gtx)
		defer ui.close(&r)
		navigation_rail(gtx, ITEMS[:], &m.selected, menu = true, expanded = &m.open, modal = true, height = 500)
		ui.spacer(gtx, 0)
		if button(gtx, "Under") {
			m.clicked += 1
		}
	}
	m := Nav_Model{open = true}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 60, 0.016)

	// The modal rail takes only its collapsed width in the layout; the
	// expanded rail and its scrim float over the button beside it.
	under, _ := bounds(&p, "Under")
	testing.expect_value(t, under.x, tok.NAVIGATION_RAIL_COLLAPSED_CONTAINER_WIDTH)
	click_at(&p, {600, 300})
	testing.expect(t, !m.open)
	testing.expect_value(t, m.clicked, 0)

	m.open = true
	ui.probe_advance(&p, 60, 0.016)
	testing.expect(t, ui.probe_click(&p, "Chat"))
	testing.expect_value(t, m.selected, 1)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
}

@(test)
test_drawer_variants_open_close_and_select :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		r := ui.row_open(gtx)
		defer ui.close(&r)
		if navigation_drawer(gtx, ITEMS[:], &m.selected, width = 300, height = 400, variant = m.variant, open = &m.open) {
			m.clicked += 1
		}
		if button(gtx, "Beside") {
			m.clicked += 100
		}
	}
	m := Nav_Model{variant = .Dismissible, open = true}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Dismissible: laid out beside the content while open...
	beside, _ := bounds(&p, "Beside")
	testing.expect_value(t, beside.x, 300)
	testing.expect(t, ui.probe_click(&p, "Chat"))
	testing.expect_value(t, m.selected, 1)
	testing.expect_value(t, m.clicked, 1)
	// ...and, closed, slides out and gives the width back.
	m.open = false
	ui.probe_advance(&p, 120, 0.016)
	beside, _ = bounds(&p, "Beside")
	testing.expect_value(t, beside.x, 0)
	testing.expect(t, !tagged(&p, "Chat"))

	// Modal: over the content; a press on the scrim closes it and does not
	// reach the content.
	m.variant, m.open, m.clicked = .Modal, true, 0
	ui.probe_advance(&p, 120, 0.016)
	beside, _ = bounds(&p, "Beside")
	testing.expect_value(t, beside.x, 0)
	click_at(&p, {600, 300})
	testing.expect(t, !m.open)
	testing.expect_value(t, m.clicked, 0)
	// Escape on a focused item closes it too.
	m.open = true
	ui.probe_advance(&p, 120, 0.016)
	testing.expect(t, ui.probe_click(&p, "Rooms"))
	testing.expect_value(t, m.selected, 2)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
}

@(test)
test_modal_drawer_covers_popups_its_content_raises :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		// The drawer comes first, as in a scaffold; the content after it
		// raises a popup of its own, as a FAB menu or a snackbar does.
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		if navigation_drawer(gtx, ITEMS[:], &m.selected, 300, variant = .Modal, open = &m.open) {
			m.open = false
		}
		o := ui.overlay_open(gtx, {500, 250})
		defer ui.close(&o)
		if button(gtx, "Popup") {
			m.clicked += 1
		}
	}
	m := Nav_Model{open = true}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 120, 0.016)

	// A press on the popup lands on the scrim: the drawer closes and the
	// popup never hears it.
	popup, ok := bounds(&p, "Popup")
	testing.expect(t, ok)
	click_at(&p, {popup.x + popup.w / 2, popup.y + popup.h / 2})
	testing.expect(t, !m.open)
	testing.expect_value(t, m.clicked, 0)
	// Closed, the popup takes presses again.
	ui.probe_advance(&p, 120, 0.016)
	testing.expect(t, ui.probe_click(&p, "Popup"))
	testing.expect_value(t, m.clicked, 1)

	// Picking a destination closes it.
	m.open = true
	ui.probe_advance(&p, 120, 0.016)
	testing.expect(t, ui.probe_click(&p, "Rooms"))
	testing.expect_value(t, m.selected, 2)
	testing.expect(t, !m.open)
}

@(test)
test_flexible_bar_goes_horizontal_and_centres :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		col := ui.column_open(gtx)
		defer ui.close(&col)
		navigation_bar(gtx, ITEMS[:], &m.selected, 800, flexible = true, arrangement = .Centered)
	}
	m: Nav_Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {800, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Three items fill 60% of the width, 20% padding each side.
	first, _ := bounds(&p, "Mail")
	last, _ := bounds(&p, "Rooms")
	testing.expect_value(t, first.x, 160)
	testing.expect_value(t, last.x + last.w, 640)
	testing.expect_value(t, first.h, tok.NAVIGATION_BAR_CONTAINER_HEIGHT)
	testing.expect(t, ui.probe_click(&p, "Rooms"))
	testing.expect_value(t, m.selected, 2)
}

@(test)
test_scrollable_tabs_scroll_and_centre_the_selection :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		LABELS := [?]string{"Overview", "Specifications", "Reviews", "Accessories", "Support", "Warranty", "Downloads"}
		col := ui.column_open(gtx)
		defer ui.close(&col)
		tabs(gtx, LABELS[:], &m.tab, width = 400, scrollable = true)
	}
	m: Nav_Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	first, _ := bounds(&p, "Overview")
	testing.expect_value(t, first.x, 52) // the edge padding
	testing.expect(t, first.w >= 90)
	// Selecting a tab near the edge scrolls it to the row's centre.
	testing.expect(t, ui.probe_click(&p, "Reviews"))
	testing.expect_value(t, m.tab, 2)
	ui.probe_advance(&p, 120, 0.016)
	r, _ := bounds(&p, "Reviews")
	testing.expect(t, abs(r.x + r.w / 2 - 200) < 1)
	// The wheel scrolls too.
	before, _ := bounds(&p, "Overview")
	testing.expect(t, ui.probe_scroll(&p, "Reviews", -1))
	ui.probe_advance(&p, 120, 0.016)
	after, _ := bounds(&p, "Overview")
	testing.expect_value(t, after.x, before.x + ui.SCROLL_STEP)
}

@(test)
test_app_bar_reports_navigation_and_search :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		col := ui.column_open(gtx)
		defer ui.close(&col)
		ACTIONS := [?]Icon{.More_Vert}
		if res := top_app_bar(gtx, "Title", .Medium_Flexible, .Arrow_Back, ACTIONS[:], subtitle = "Sub", width = 400); res.navigation {
			m.clicked += 1
		}
		if res := top_app_bar(gtx, "Search mail", .Search, .None, width = 400, key = 1); res.search {
			m.clicked += 10
		}
	}
	m: Nav_Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	bar, _ := bounds(&p, "navigation")
	testing.expect_value(t, bar.x, tok.APP_BAR_LEADING_SPACE)
	testing.expect(t, ui.probe_click(&p, "navigation"))
	testing.expect_value(t, m.clicked, 1)
	testing.expect(t, ui.probe_click(&p, "Search mail"))
	testing.expect_value(t, m.clicked, 11)
	// A flexible bar with a subtitle takes its taller height; the search
	// bar sits under it.
	field, _ := bounds(&p, "Search mail")
	testing.expect_value(t, field.y, tok.APP_BAR_MEDIUM_FLEXIBLE_LARGE_CONTAINER_HEIGHT + (tok.APP_BAR_SMALL_CONTAINER_HEIGHT - tok.SEARCH_BAR_CONTAINER_HEIGHT) / 2)
}

@(test)
test_badge_sizes_follow_their_label :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^Nav_Model)(user)
		m.sizes = {badge_size(gtx, " "), badge_size(gtx, "3"), badge_size(gtx, "999+")}
	}
	m: Nav_Model
	p: ui.Probe
	ui.probe_init(&p, view, &m, {100, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, m.sizes[0], ops.Size{tok.BADGE_SIZE, tok.BADGE_SIZE})
	testing.expect_value(t, m.sizes[1], ops.Size{tok.BADGE_LARGE_SIZE, tok.BADGE_LARGE_SIZE})
	testing.expect(t, m.sizes[2].x > tok.BADGE_LARGE_SIZE && m.sizes[2].y == tok.BADGE_LARGE_SIZE)
}
