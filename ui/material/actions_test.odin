package material

import "core:testing"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Behaviour of the actions group (button group, toolbar, FAB menu, bottom
// app bar), driven through ui.Probe by their tags.

// hittable reports whether an area tagged name takes input this frame:
// unlike a bare tag check, a disabled or hidden control does not count.
@(private = "file")
hittable :: proc(p: ^ui.Probe, name: string) -> bool {
	_, ok := ui.probe_find(p, name)
	return ok
}

// width_of is the hit width of the area tagged name in the current frame.
@(private = "file")
width_of :: proc(p: ^ui.Probe, name: string) -> f32 {
	h, ok := ui.probe_find(p, name)
	if !ok {
		return -1
	}
	return ui.shape_bounds(&p.ops, h.shape).w
}

@(private = "file")
Group_Model :: struct {
	sel:     [3]bool,
	multi:   [3]bool,
	days:    [5]bool,
	menu:    bool,
	acted:   int,
	clicked: int,
}

@(private = "file")
groups_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Group_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	LABELS := [?]string{"A", "B", "C"}
	button_group(gtx, LABELS[:], m.sel[:])
	MULTI := [?]string{"Bold", "Italic", "Strike"}
	DIS := [?]bool{false, false, true}
	button_group(gtx, MULTI[:], m.multi[:], connected = true, single = false, disabled = DIS[:])
	ACTS := [?]string{"Cancel", "Save"}
	if i := button_group(gtx, ACTS[:], nil); i >= 0 {
		m.acted = i
	}
	DAYS := [?]string{"Mon", "Tue", "Wed", "Thu", "Fri"}
	if i := button_group(gtx, DAYS[:], m.days[:], width = 200, overflow = &m.menu); i >= 0 {
		m.clicked = i
	}
}

@(test)
test_button_group_selects_toggles_and_overflows :: proc(t: ^testing.T) {
	m := Group_Model{acted = -1, clicked = -1}
	p: ui.Probe
	ui.probe_init(&p, groups_ui, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Single-select: a click selects only that child.
	testing.expect(t, ui.probe_click(&p, "A"))
	testing.expect(t, ui.probe_click(&p, "C"))
	testing.expect_value(t, m.sel, [3]bool{false, false, true})
	// Multi-select flips each; a disabled child takes no click.
	testing.expect(t, ui.probe_click(&p, "Bold"))
	testing.expect(t, ui.probe_click(&p, "Italic"))
	testing.expect(t, !ui.probe_click(&p, "Strike")) // tagged, but no input area
	testing.expect_value(t, m.multi, [3]bool{true, true, false})
	testing.expect(t, ui.probe_click(&p, "Bold"))
	testing.expect_value(t, m.multi, [3]bool{false, true, false})
	// Action children just report the click.
	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect_value(t, m.acted, 1)

	// 200dp fits two days and the overflow indicator; the rest are in its menu.
	testing.expect(t, hittable(&p, "Tue"))
	testing.expect(t, !hittable(&p, "Wed"))
	testing.expect(t, ui.probe_click(&p, "More options"))
	testing.expect(t, m.menu)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Thu"))
	testing.expect_value(t, m.clicked, 3)
	testing.expect_value(t, m.days, [5]bool{false, false, false, true, false})
	testing.expect(t, !m.menu)
}

@(test)
test_button_group_press_widens_into_neighbours :: proc(t: ^testing.T) {
	m := Group_Model{acted = -1, clicked = -1}
	p: ui.Probe
	ui.probe_init(&p, groups_ui, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p)
	a0, b0, c0 := width_of(&p, "A"), width_of(&p, "B"), width_of(&p, "C")

	// Hold B down until the width spring settles.
	at, _ := ui.probe_center(&p, "B")
	ui.router_push(&p.router, {kind = .Move, pos = at})
	ui.router_push(&p.router, {kind = .Press, pos = at})
	ui.probe_advance(&p, 60, 1.0 / 60)
	a1, b1, c1 := width_of(&p, "A"), width_of(&p, "B"), width_of(&p, "C")
	// A middle child takes half the ratio from each side, capped by what
	// each neighbour may give: the row's total stays put.
	grow := GROUP_EXPANDED_RATIO * b0 / 2
	testing.expectf(t, abs(b1 - (b0 + 2 * grow)) < 0.5, "pressed B %v, want %v", b1, b0 + 2 * grow)
	testing.expectf(t, abs(a1 - (a0 - grow)) < 0.5, "neighbour A %v, want %v", a1, a0 - grow)
	testing.expectf(t, abs((a1 + b1 + c1) - (a0 + b0 + c0)) < 0.5, "row %v, want %v", a1 + b1 + c1, a0 + b0 + c0)

	// Released, it springs back.
	ui.router_push(&p.router, {kind = .Release, pos = at})
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expectf(t, abs(width_of(&p, "B") - b0) < 0.5, "released B %v, want %v", width_of(&p, "B"), b0)
}

@(test)
test_toolbar_clicks_actions_fab_and_collapses :: proc(t: ^testing.T) {
	M :: struct {
		picked:   int,
		expanded: bool,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		col := ui.column_open(gtx, gap = 16)
		defer ui.close(&col)
		DOCKED := [?]Icon{.Undo, .Redo}
		if i := toolbar(gtx, DOCKED[:], .Docked, width = 300); i != -1 {
			m.picked = i
		}
		FLOAT := [?]Icon{.Format_Bold, .Format_Italic, .Palette}
		if i := toolbar(gtx, FLOAT[:], .Floating_Vibrant, expanded = m.expanded, trailing = 1, fab = .Edit); i != -1 {
			m.picked = i
		}
	}
	m := M{picked = -1, expanded = true}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {500, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Redo"))
	testing.expect_value(t, m.picked, 1)
	testing.expect(t, ui.probe_click(&p, "Palette"))
	testing.expect_value(t, m.picked, 2)
	testing.expect(t, ui.probe_click(&p, "Edit"))
	testing.expect_value(t, m.picked, TOOLBAR_FAB)

	// Collapsed with a FAB, the whole toolbar folds away; the FAB stays
	// and grows to medium.
	testing.expect(t, hittable(&p, "Format_Bold"))
	m.expanded = false
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, !hittable(&p, "Format_Bold"))
	testing.expect(t, !hittable(&p, "Palette"))
	testing.expect(t, hittable(&p, "Edit"))
	testing.expectf(t, abs(width_of(&p, "Edit") - tok.FAB_MEDIUM_CONTAINER_WIDTH) < 0.5, "collapsed FAB %v", width_of(&p, "Edit"))
}

@(test)
test_fab_menu_opens_staggers_and_picks :: proc(t: ^testing.T) {
	M :: struct {
		open:   bool,
		picked: int,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		in_ := ui.inset_open(gtx, {300, 400, 0, 0})
		defer ui.close(&in_)
		ITEMS := [?]Fab_Menu_Item{{"Mail", .Mail}, {"Chat", .Chat_Bubble}, {"Photo", .Photo}}
		if i := fab_menu(gtx, .Add, ITEMS[:], &m.open); i >= 0 {
			m.picked = i
		}
	}
	m := M{picked = -1}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {500, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Open actions menu"))
	testing.expect(t, m.open)
	// The count spring reveals items in list order, not all at once.
	ui.probe_advance(&p, 2, 1.0 / 60)
	testing.expect(t, !hittable(&p, "Photo"))
	ui.probe_advance(&p, 120, 1.0 / 60)
	testing.expect(t, hittable(&p, "Mail"))
	testing.expect(t, hittable(&p, "Photo"))
	testing.expect(t, hittable(&p, "Close menu"))

	testing.expect(t, ui.probe_click(&p, "Chat"))
	testing.expect_value(t, m.picked, 1)
	testing.expect(t, !m.open)
	ui.probe_advance(&p, 120, 1.0 / 60)
	testing.expect(t, !hittable(&p, "Mail"))
}

@(test)
test_bottom_app_bar_clicks_and_hides :: proc(t: ^testing.T) {
	M :: struct {
		picked: int,
		hide:   f32,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		col := ui.column_open(gtx, gap = 16)
		defer ui.close(&col)
		ACTIONS := [?]Icon{.Check, .Mic}
		if i := bottom_app_bar(gtx, ACTIONS[:], .Add, width = 400, height_offset = -m.hide); i != -1 {
			m.picked = i
		}
		FLEX := [?]Icon{.Search}
		if i := bottom_app_bar(gtx, FLEX[:], flexible = true, width = 400); i != -1 {
			m.picked = 10 + i
		}
	}
	m := M{picked = -1}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {500, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Mic"))
	testing.expect_value(t, m.picked, 1)
	testing.expect(t, ui.probe_click(&p, "Add"))
	testing.expect_value(t, m.picked, TOOLBAR_FAB)
	testing.expect(t, ui.probe_click(&p, "Search"))
	testing.expect_value(t, m.picked, 10)
	// Scrolled its full height away, the bar takes no space and no input.
	m.hide = 80
	ui.probe_frame(&p)
	testing.expect(t, !hittable(&p, "Mic"))
}
