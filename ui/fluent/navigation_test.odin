package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of the navigation group, driven through ui.Probe by tags.

@(private = "file")
Nav_Model :: struct {
	selected:    string,
	reports:     bool,
	drawer_open: bool,
	crumb:       int,
	docs:        bool,
	checked:     bool,
	small:       bool,
	collapsed:   bool,
}

@(private = "file")
CRUMBS := [?]string{"Home", "Bravo", "Charlie", "Delta", "Echo", "Foxtrot", "Golf", "Hotel"}

@(private = "file")
WINDOW :: ops.Size{900, 700}

@(private = "file")
navigation :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Nav_Model)(user)
	r := ui.row_open(gtx, align = .Start)
	defer ui.close(&r)
	if nav(gtx, density = m.small ? .Small : .Medium, collapsed = m.collapsed) {
		if nav_header(gtx) {
			hamburger(gtx)
		}
		if nav_body(gtx) {
			nav_section_header(gtx, "Pages")
			nav_item(gtx, "Dashboard", "dashboard", &m.selected, .Home)
			if nav_category(gtx, "Reports", &m.reports, .Document) {
				nav_sub_item(gtx, "Sales", "sales", &m.selected)
				nav_sub_item(gtx, "Costs", "costs", &m.selected)
			}
		}
	}
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if i := breadcrumb(gtx, CRUMBS[:]); i >= 0 {
		m.crumb = i
	}
	if tree(gtx) {
		if tree_item(gtx, "Docs", &m.docs, checked = &m.checked) {
			tree_item(gtx, "Readme", level = 2)
		}
		tree_item(gtx, "Notes", size = .Small, key = 1)
	}
	if button(gtx, "Open drawer") {
		m.drawer_open = true
	}
	if drawer(gtx, &m.drawer_open, WINDOW) {
		if drawer_header(gtx) {
			drawer_header_title(gtx, "Settings", &m.drawer_open)
		}
		if drawer_body(gtx) {
			base_label(gtx, "Body text", .Body1, color(.Neutral_Foreground1))
		}
	}
}

@(test)
test_nav_selects_items_and_opens_categories :: proc(t: ^testing.T) {
	m := Nav_Model{crumb = -1}
	p: ui.Probe
	ui.probe_init(&p, navigation, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Dashboard"))
	testing.expect_value(t, m.selected, "dashboard")
	// The sub-items lay out only while the category is open.
	testing.expect(t, !ui.probe_tagged(&p, "Sales"))
	testing.expect(t, ui.probe_click(&p, "Reports"))
	testing.expect(t, m.reports)
	testing.expect(t, ui.probe_tagged(&p, "Sales"))
	testing.expect(t, ui.probe_click(&p, "Sales"))
	testing.expect_value(t, m.selected, "sales")
	testing.expect(t, ui.probe_click(&p, "Reports"))
	testing.expect(t, !m.reports)
	testing.expect(t, !ui.probe_tagged(&p, "Sales"))
	// Rows: spacingVerticalMNudge (10px) above and below a 20px line at
	// medium, spacingVerticalXS (4px) at small; 260px wide less the body
	// padding (MNudge 10 at the start, XS 4 at the end), and the body's
	// padding is the only padding: the row starts 10px in from the
	// drawer's edge, the hamburger 14px.
	row := ui.probe_bounds(&p, "Dashboard")
	testing.expect_value(t, row.h, 40)
	testing.expect_value(t, row.w, 260 - 10 - 4)
	testing.expect_value(t, row.x, 10)
	testing.expect_value(t, ui.probe_bounds(&p, "Navigation").x, 14)
	m.small = true
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Dashboard").h, 28)
}

// Collapsed, an inline nav is a rail: 52px wide, each row its icon alone
// and still the destination its tag names, the section heading gone;
// expanded again it is the drawer it was.
@(test)
test_nav_collapses_to_a_rail :: proc(t: ^testing.T) {
	m := Nav_Model{crumb = -1}
	p: ui.Probe
	ui.probe_init(&p, navigation, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_tagged(&p, "Pages"))
	m.collapsed = true
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	row := ui.probe_bounds(&p, "Dashboard")
	testing.expect_value(t, row.w, 52 - 10 - 4)
	testing.expect_value(t, row.h, 40)
	testing.expect_value(t, ui.probe_bounds(&p, "Navigation").w, 32)
	testing.expect(t, !ui.probe_tagged(&p, "Pages"))
	testing.expect(t, ui.probe_click(&p, "Dashboard"))
	testing.expect_value(t, m.selected, "dashboard")
	// A category row is its icon too, and still opens.
	testing.expect_value(t, ui.probe_bounds(&p, "Reports").w, 52 - 10 - 4)
	testing.expect(t, ui.probe_click(&p, "Reports"))
	testing.expect(t, m.reports)

	m.collapsed = false
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Dashboard").w, 260 - 10 - 4)
	testing.expect(t, ui.probe_tagged(&p, "Pages"))
}

@(test)
test_drawer_opens_and_closes_by_its_button_and_escape :: proc(t: ^testing.T) {
	m := Nav_Model{crumb = -1}
	p: ui.Probe
	ui.probe_init(&p, navigation, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, !ui.probe_tagged(&p, "Settings"))
	testing.expect(t, ui.probe_click(&p, "Open drawer"))
	ui.probe_advance(&p, 30, 0.016) // past the small drawer's DURATION_GENTLE
	testing.expect(t, ui.probe_tagged(&p, "Settings"))
	// Small: 320px wide, pinned to the start edge.
	close := ui.probe_bounds(&p, "Close")
	testing.expect(t, close.x + close.w <= 320)
	testing.expect(t, close.x > 200)
	testing.expect(t, ui.probe_click(&p, "Close"))
	testing.expect(t, !m.drawer_open)
	ui.probe_advance(&p, 30, 0.016)
	testing.expect(t, !ui.probe_tagged(&p, "Settings"))

	// Escape once the surface has focus.
	m.drawer_open = true
	ui.probe_advance(&p, 30, 0.016)
	ui.router_push(&p.router, {kind = .Move, pos = {100, 600}})
	ui.router_push(&p.router, {kind = .Press, pos = {100, 600}, button = .Left})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Release, pos = {100, 600}, button = .Left})
	ui.probe_frame(&p)
	testing.expect(t, m.drawer_open) // a press on the surface is not the backdrop
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.drawer_open)

	// A press on the backdrop closes a modal drawer.
	m.drawer_open = true
	ui.probe_advance(&p, 30, 0.016)
	ui.router_push(&p.router, {kind = .Move, pos = {700, 400}})
	ui.router_push(&p.router, {kind = .Press, pos = {700, 400}, button = .Left})
	ui.probe_frame(&p)
	testing.expect(t, !m.drawer_open)
}

@(test)
test_breadcrumb_reports_clicks_and_overflows :: proc(t: ^testing.T) {
	m := Nav_Model{crumb = -1}
	p: ui.Probe
	ui.probe_init(&p, navigation, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Eight items over the maximum of six: the first stays, Bravo and
	// Charlie collapse into the overflow button, Delta to Hotel follow.
	testing.expect(t, ui.probe_tagged(&p, "Home"))
	testing.expect(t, !ui.probe_tagged(&p, "Bravo"))
	testing.expect(t, !ui.probe_tagged(&p, "Charlie"))
	testing.expect(t, ui.probe_tagged(&p, "More items"))
	testing.expect(t, ui.probe_tagged(&p, "Delta"))
	testing.expect(t, ui.probe_click(&p, "Delta"))
	testing.expect_value(t, m.crumb, 3)
	testing.expect_value(t, ui.probe_bounds(&p, "Delta").h, 32) // medium
	// The current item, the last, takes no input.
	testing.expect(t, ui.probe_tagged(&p, "Hotel"))
	testing.expect(t, !ui.probe_click(&p, "Hotel"))
	// The overflow menu lists the hidden run and reports its index.
	testing.expect(t, ui.probe_click(&p, "More items"))
	testing.expect(t, ui.probe_tagged(&p, "Bravo"))
	testing.expect(t, ui.probe_click(&p, "Charlie"))
	testing.expect_value(t, m.crumb, 2)
}

@(test)
test_tree_item_expands_and_collapses :: proc(t: ^testing.T) {
	m := Nav_Model{crumb = -1}
	p: ui.Probe
	ui.probe_init(&p, navigation, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, !ui.probe_tagged(&p, "Readme"))
	testing.expect(t, ui.probe_click(&p, "Docs"))
	testing.expect(t, m.docs)
	testing.expect(t, ui.probe_tagged(&p, "Readme"))
	// A child one level down is indented one spacingHorizontalXXL step
	// past its parent's row (a leaf pads level steps).
	testing.expect_value(t, ui.probe_bounds(&p, "Docs").h, 32)
	testing.expect_value(t, ui.probe_bounds(&p, "Notes").h, 24)
	// Left closes the focused branch, Right opens it.
	ui.probe_key(&p, .Left)
	testing.expect(t, !m.docs)
	testing.expect(t, !ui.probe_tagged(&p, "Readme"))
	ui.probe_key(&p, .Right)
	testing.expect(t, m.docs)
	testing.expect(t, ui.probe_click(&p, "Docs"))
	testing.expect(t, !m.docs)
}

@(test)
test_nav_is_one_tab_stop_its_arrows_walk :: proc(t: ^testing.T) {
	m := Nav_Model{crumb = -1}
	p: ui.Probe
	ui.probe_init(&p, navigation, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Dashboard"))
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Reports")
	ui.probe_key(&p, .Enter) // a category opens on Enter (nav.json)
	ui.probe_frame(&p)
	testing.expect(t, m.reports)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Sales")
	ui.probe_key(&p, .End)
	testing.expect_value(t, ui.probe_focus_name(&p), "Costs")
	ui.probe_key(&p, .Down) // wraps to the nav's first row, the header's hamburger
	testing.expect_value(t, ui.probe_focus_name(&p), "Navigation")
	// One tab stop, entered at the selected row.
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "Home") // the breadcrumb's first crumb
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, ui.probe_focus_name(&p), "Dashboard")
}

@(test)
test_tree_is_one_tab_stop_its_arrows_walk_visible_rows :: proc(t: ^testing.T) {
	m := Nav_Model{crumb = -1}
	p: ui.Probe
	ui.probe_init(&p, navigation, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Docs")) // opens the branch
	testing.expect(t, m.docs)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Readme") // past the row's own selector
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Notes")
	ui.probe_key(&p, .Down)
	testing.expect_value(t, ui.probe_focus_name(&p), "Notes") // no wrap
	ui.probe_key(&p, .Home)
	testing.expect_value(t, ui.probe_focus_name(&p), "Docs")
	ui.probe_key(&p, .End)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "Open drawer")
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, ui.probe_focus_name(&p), "Notes") // back where focus left the tree
}
