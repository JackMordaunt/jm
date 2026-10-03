package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of action_list, driven through ui.Probe by tags.

@(private = "file")
List_Model :: struct {
	variant:   Action_List_Variant,
	role:      List_Role,
	focus:     List_Focus,
	selection: Selection_Variant,
	wrap:      bool,
	active:    int,
	activate:  bool,
	follow:    bool,
	hits:      [6]int,
	hovered:   int,
	key:       ui.Key,
	scroll:    ui.Scroll_Offset,
	view:      f32,
	width:     f32,
	moved:     bool,
}

@(private = "file")
LIST_NAMES := [6]string{"Alpha", "Beta", "Gamma", "Blocked", "Waiting", "Delta"}

@(private = "file")
list_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^List_Model)(user)
	col := ui.column_open(gtx, gap = 8, align = .Start)
	defer ui.close(&col)
	button(gtx, "Before")
	sized := ui.sized_open(gtx, {min = {m.width, 0}, max = {m.width > 0 ? m.width : ui.INF, ui.INF}})
	l := action_list_open(gtx, m.variant, m.selection, m.role, m.focus, m.wrap, typeahead = true, name = "Things", active = m.active, activate = m.activate, follow = m.follow, scroll = {&m.scroll, m.view, 0, LIST_SCROLL_END}, key = 1)
	for n, i in LIST_NAMES {
		if action_list_item(&l, n, leading = .Gear, trailing_text = i == 0 ? "12" : "", disabled = i == 3, loading = i == 4, size = i == 5 ? .Large : .Medium, selected = i == 1) {
			m.hits[i] += 1
		}
		if i == 2 {
			action_list_divider(&l)
		}
	}
	action_list_close(&l)
	ui.close(&sized)
	if l.hovered >= 0 {
		m.hovered = l.hovered
	}
	if l.key != .None {
		m.key = l.key
	}
	m.moved |= l.moved
	button(gtx, "After")
}

@(private = "file")
LIST_SCROLL_END :: tok.BASE_SIZE_8

@(private = "file")
list_probe :: proc(p: ^ui.Probe, m: ^List_Model) {
	ui.probe_init(p, list_view, m, {600, 800}, allocator = context.temp_allocator)
}

@(test)
test_action_list_rows_follow_the_css :: proc(t: ^testing.T) {
	m := List_Model{active = -1}
	p: ui.Probe
	list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	before := ui.probe_bounds(&p, "Before")
	alpha := ui.probe_bounds(&p, "Alpha")
	beta := ui.probe_bounds(&p, "Beta")
	gamma := ui.probe_bounds(&p, "Gamma")
	blocked := ui.probe_bounds(&p, "Blocked")
	delta := ui.probe_bounds(&p, "Delta")
	top := before.y + before.h + 8
	testing.expect_value(t, alpha.y, top + tok.BASE_SIZE_8) // inset: 8px above the first row
	testing.expect_value(t, alpha.x, tok.BASE_SIZE_8) // and 8px in from the side
	testing.expect_value(t, alpha.h, tok.CONTROL_MEDIUM_SIZE) // 6 + 20 + 6
	testing.expect_value(t, beta.y, alpha.y + alpha.h)
	testing.expect_value(t, delta.h, tok.CONTROL_LARGE_SIZE) // 10 + 20 + 10
	// A divider: 7px, the 1px rule, 8px.
	testing.expect_value(t, blocked.y, gamma.y + gamma.h + 7 + 1 + 8)
	// Unconstrained, the list hugs its widest item; every item takes its width.
	testing.expect_value(t, alpha.w, beta.w)
	testing.expectf(t, alpha.w < 200, "it hugs: %v of 600px", alpha.w)
	m.width = 400
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Alpha").w, 400 - 2 * tok.BASE_SIZE_8) // made 400 wide, it fills, less its insets
	m.variant = .Full
	ui.probe_frame(&p)
	full := ui.probe_bounds(&p, "Alpha")
	testing.expect_value(t, full.x, 0) // full: flush
	testing.expect_value(t, full.y, top)
}

@(test)
test_action_list_items_activate_by_click_and_keys_but_not_when_dead :: proc(t: ^testing.T) {
	m := List_Model{active = -1}
	p: ui.Probe
	list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Alpha"))
	testing.expect_value(t, m.hits[0], 1)
	ui.probe_key(&p, .Enter)
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.hits[0], 3)
	// A plain list: every item is its own tab stop.
	ui.probe_key(&p, .Tab)
	beta, _ := ui.probe_find(&p, "Beta")
	testing.expect_value(t, p.router.focus, beta.area)
	// Disabled and loading items ignore a click and Enter.
	for name, i in ([2]string{"Blocked", "Waiting"}) {
		testing.expect(t, ui.probe_click(&p, name))
		dead, _ := ui.probe_find(&p, name)
		testing.expect_value(t, p.router.focus, dead.area) // aria-disabled: still focusable
		ui.probe_key(&p, .Enter)
		ui.probe_key(&p, .Space)
		testing.expect_value(t, m.hits[3 + i], 0)
	}
}

@(test)
test_a_roving_list_is_one_tab_stop_and_arrows_move_focus :: proc(t: ^testing.T) {
	m := List_Model{role = .Menu, focus = .Roving, active = -1}
	p: ui.Probe
	list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	area :: proc(p: ^ui.Probe, name: string) -> ops.Area_Id {
		h, _ := ui.probe_find(p, name)
		return h.area
	}

	ui.probe_click(&p, "Before")
	ui.probe_frame(&p)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, area(&p, "Alpha")) // into the list at its tab stop
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, area(&p, "After")) // and out again: one stop
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, p.router.focus, area(&p, "Alpha"))
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Beta"))
	testing.expect(t, m.moved)
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Delta"))
	ui.probe_key(&p, .Down) // a list that does not wrap stops at the end
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Delta"))
	m.wrap = true
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Alpha"))
	ui.probe_key(&p, .Up)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Delta"))
	ui.probe_key(&p, .Page_Up) // Page keys jump to the ends (focus-zone.mjs:62-63)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Alpha"))
	// Disabled items are visited, as the focus zone takes them.
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Down)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Blocked"))
	// Type-ahead: the next item starting with the letter, cycling.
	ui.probe_key(&p, .B)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Beta")) // after Blocked, wrapping to the first B
	ui.probe_key(&p, .D)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, area(&p, "Delta"))
	// The list leaves Left, Right and Tab to its owner.
	ui.probe_key(&p, .Right)
	testing.expect_value(t, m.key, ui.Key.Right)
	// Focus only shows as the outline for the keyboard; Enter activates.
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.hits[5], 1)
}

@(test)
test_a_descendant_list_highlights_what_its_owner_names :: proc(t: ^testing.T) {
	m := List_Model{role = .Listbox, focus = .Descendant, active = 1, hovered = -1}
	p: ui.Probe
	list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// The highlight is the selected fill and the accent bar.
	bars := fills_of(&p, color(.Border_Color_Accent_Emphasis))
	testing.expect_value(t, bars, 1)
	// No item takes keys: focus stays with the owner.
	ui.probe_click(&p, "Before")
	ui.probe_click(&p, "Gamma")
	before, _ := ui.probe_find(&p, "Before")
	testing.expect_value(t, p.router.focus, before.area)
	testing.expect_value(t, m.hits[2], 1) // a click still activates
	// The pointer moving onto an item reports it.
	c, _ := ui.probe_center(&p, "Delta")
	ui.probe_move(&p, c.x, c.y)
	testing.expect_value(t, m.hovered, 5)
	// The owner's Enter activates the highlighted item, not a dead one.
	m.activate = true
	ui.probe_frame(&p)
	testing.expect_value(t, m.hits[1], 1)
	m.active = 3
	ui.probe_frame(&p)
	testing.expect_value(t, m.hits[3], 0)
}

@(test)
test_a_list_scrolls_the_moved_item_into_view_with_its_margin :: proc(t: ^testing.T) {
	m := List_Model{role = .Listbox, focus = .Descendant, active = 0, follow = true, view = 100}
	p: ui.Probe
	list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	before := ui.probe_bounds(&p, "Before")
	top := before.y + before.h + 8 // the list's top, which the test's view starts at
	testing.expect_value(t, m.scroll.y, 0) // Alpha shows
	m.active = 5
	ui.probe_frame(&p)
	delta := ui.probe_bounds(&p, "Delta")
	want := delta.y - top + delta.h + LIST_SCROLL_END - m.view
	testing.expect_value(t, m.scroll.y, want) // its bottom 8px above the view's
	m.active = 1
	ui.probe_frame(&p)
	beta := ui.probe_bounds(&p, "Beta")
	testing.expect_value(t, m.scroll.y, beta.y - top) // its top at the view's
}

@(test)
test_action_list_semantics_follow_the_role :: proc(t: ^testing.T) {
	m := List_Model{role = .Menu, focus = .Roving, selection = .Multiple, active = -1}
	p: ui.Probe
	list_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "menu \"Things\""), "%s", sem)
	testing.expectf(t, strings.contains(sem, "menu item checkbox \"Alpha 12\" at"), "the trailing text joins the name\n%s", sem)
	testing.expectf(t, strings.contains(sem, "menu item checkbox \"Beta\" checked"), "%s", sem)
	testing.expectf(t, strings.contains(sem, "menu item checkbox \"Blocked\" disabled"), "%s", sem)
	testing.expectf(t, strings.contains(sem, "menu item checkbox \"Waiting Loading\""), "%s", sem)
	m.role, m.selection = .Listbox, .Single
	ui.probe_frame(&p)
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "list box \"Things\""), "%s", sem)
	testing.expectf(t, strings.contains(sem, "option \"Beta\" selected"), "%s", sem)
	m.role, m.selection = .Menu, .Single
	ui.probe_frame(&p)
	sem = ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "menu item radio \"Beta\" checked"), "%s", sem)
	// A checkmark, not a checkbox, in a menu (Selection.tsx:40-52).
	m.selection = .Multiple
	ui.probe_frame(&p)
	testing.expect_value(t, fills_of(&p, color(.Control_Checked_Bg_Color_Rest)), 0)
	m.role = .Listbox
	ui.probe_frame(&p)
	testing.expect_value(t, fills_of(&p, color(.Control_Checked_Bg_Color_Rest)), 1)
}

@(test)
test_an_empty_list_is_its_padding :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx, align = .Start)
		defer ui.close(&col)
		l := action_list_open(gtx, key = 1)
		action_list_divider(&l) // a first divider draws nothing
		action_list_close(&l)
		ops.tag(gtx.scene, ui.last_widget(gtx).id, "List")
		h := ui.last_widget(gtx)
		ops.tag(gtx.scene, 99, "Size", {0, 0, h.size.x, h.size.y})
	}
	p: ui.Probe
	ui.probe_init(&p, view, nil, {300, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, ui.probe_bounds(&p, "Size").h, 2 * tok.BASE_SIZE_8)
	testing.expect_value(t, fills_of(&p, color(.Border_Color_Muted)), 0)
}


@(test)
test_a_danger_item_fills_red_on_hover_and_press_and_not_when_disabled :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		l := action_list_open(gtx, key = 1)
		action_list_item(&l, "Delete", leading = .Trash, variant = .Danger, state = (^Interaction)(user)^)
		action_list_close(&l)
	}
	forced := Interaction.Enabled
	p: ui.Probe
	ui.probe_init(&p, view, &forced, {300, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	hover, press := color(.Control_Danger_Bg_Color_Hover), color(.Control_Danger_Bg_Color_Active)
	testing.expect_value(t, fills_of(&p, hover) + fills_of(&p, press), 0)
	forced = .Hovered
	ui.probe_frame(&p)
	testing.expect_value(t, fills_of(&p, hover), 1)
	forced = .Pressed
	ui.probe_frame(&p)
	testing.expect_value(t, fills_of(&p, press), 1)
	forced = .Disabled
	ui.probe_frame(&p)
	testing.expect_value(t, fills_of(&p, hover) + fills_of(&p, press), 0)
}

@(test)
test_sub_items_sit_inside_their_parents_margin_and_indent :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		col := ui.column_open(gtx, align = .Start)
		defer ui.close(&col)
		sized := ui.sized_open(gtx, {min = {300, 0}, max = {300, ui.INF}})
		defer ui.close(&sized)
		l := action_list_open(gtx, key = 1)
		action_list_item(&l, "Parent", expanded = true)
		action_list_item(&l, "Leaf", link = true, active = true, depth = 1)
		action_list_close(&l)
	}
	p: ui.Probe
	ui.probe_init(&p, view, nil, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	parent, leaf := ui.probe_bounds(&p, "Parent"), ui.probe_bounds(&p, "Leaf")
	testing.expect_value(t, leaf.x, parent.x) // inside the parent's 8px margin
	testing.expect_value(t, leaf.w, parent.w)
	// The leaf's spacer shows: its text 8px further in than the parent's.
	xs: [2]f32
	n := 0
	for d in ui.probe_current(&p).draws {
		if g, ok := d.cmd.(ops.Glyphs); ok && n < 2 {
			xs[n] = ops.apply(d.transform, g.origin).x
			n += 1
		}
	}
	testing.expect_value(t, n, 2)
	testing.expect_value(t, xs[1] - xs[0], LIST_DEPTH_STEP)
	sem := ui.probe_semantics(&p, context.temp_allocator)
	testing.expectf(t, strings.contains(sem, "link \"Leaf\" current page"), "an active link is the current page\n%s", sem)
}
