package material

import "core:testing"
import "jm:ui/ops"
import "jm:ui"

// The controls group's caller-owned state: a tab row's and a drawer's
// scroll are the caller's when it passes them, and the widget's own
// widget_data when it passes nil.

@(private = "file")
LABELS := [?]string{"Overview", "Specifications", "Reviews", "Accessories", "Support", "Warranty", "Downloads"}

@(private = "file")
ITEMS := [?]Nav_Item {
	{label = "Mail", headline = true},
	{label = "Inbox", icon = .Inbox},
	{label = "Outbox", icon = .Send},
	{label = "Favourites", icon = .Favorite},
	{label = "Trash", icon = .Delete},
}

@(private = "file")
State_Model :: struct {
	own:      bool,
	tab:      int,
	selected: int,
	tabs:     Tabs_Scroll,
	drawer:   Drawer_Scroll,
}

// bounds is the device-space bounding rect of the area tagged name.
@(private = "file")
bounds :: proc(p: ^ui.Probe, name: string) -> ops.Rect {
	h, ok := ui.probe_find(p, name)
	if !ok {
		return {}
	}
	return ops.transform_rect(h.transform, ops.shape_bounds(&p.scene, h.shape))
}

@(test)
test_tabs_scroll_state_is_the_callers_when_passed :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^State_Model)(user)
		col := ui.column_open(gtx)
		defer ui.close(&col)
		tabs(gtx, LABELS[:], &m.tab, width = 400, scrollable = true, scroll = m.own ? &m.tabs : nil)
	}
	// A caller's target places the row from the first frame.
	m := State_Model{own = true, tabs = {target = 100}}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, bounds(&p, "Overview").x, 52 - 100)
	// The wheel and a selection move the caller's state.
	testing.expect(t, ui.probe_scroll(&p, "Reviews", 1))
	testing.expect_value(t, m.tabs.target, 100 + ui.SCROLL_STEP)
	ui.probe_advance(&p, 120, 0.016)
	testing.expect_value(t, bounds(&p, "Overview").x, 52 - 100 - ui.SCROLL_STEP)

	// nil falls back to the row's own store, which starts unscrolled and
	// leaves the caller's alone.
	m.own = false
	saved := m.tabs.target
	ui.probe_advance(&p, 2, 0.016)
	testing.expect_value(t, bounds(&p, "Overview").x, 52)
	testing.expect(t, ui.probe_scroll(&p, "Reviews", 1))
	ui.probe_advance(&p, 120, 0.016)
	testing.expect_value(t, bounds(&p, "Overview").x, 52 - ui.SCROLL_STEP)
	testing.expect_value(t, m.tabs.target, saved)
}

@(test)
test_drawer_scroll_state_is_the_callers_when_passed :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^State_Model)(user)
		col := ui.column_open(gtx)
		defer ui.close(&col)
		navigation_drawer(gtx, ITEMS[:], &m.selected, width = 300, height = 150, scroll = m.own ? &m.drawer : nil)
	}
	m := State_Model{own = true, selected = 1, drawer = {offset = 40}}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	scrolled := bounds(&p, "Inbox").y
	testing.expect_value(t, m.drawer.offset, 40)
	// The wheel moves the caller's offset.
	testing.expect(t, ui.probe_scroll(&p, "Inbox", 1))
	ui.probe_frame(&p)
	testing.expect_value(t, m.drawer.offset, 40 + ui.SCROLL_STEP)

	// nil falls back to the drawer's own store, which starts at the top and
	// leaves the caller's alone.
	m.own = false
	ui.probe_advance(&p, 2, 0.016)
	testing.expect_value(t, bounds(&p, "Inbox").y, scrolled + 40)
	testing.expect(t, ui.probe_scroll(&p, "Inbox", 1))
	ui.probe_frame(&p)
	testing.expect_value(t, bounds(&p, "Inbox").y, scrolled + 40 - ui.SCROLL_STEP)
	testing.expect_value(t, m.drawer.offset, 40 + ui.SCROLL_STEP)
}
