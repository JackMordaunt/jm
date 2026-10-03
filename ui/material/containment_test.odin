package material

import "core:testing"
import "jm:ui/ops"
import "jm:ui"

// Behaviour of the containment group — cards, list items, menus,
// dialogs, snackbars — driven through ui.Probe.

@(private = "file")
Rows :: struct {
	card_hit:  bool,
	card_hits: int,
	checked:   bool,
	expanded:  bool,
	plain:     int, // clicks returned by a .None row
	clicks:    int, // clicks returned by a .Click row
	moved:     int,
	action:    int,
}

@(private = "file")
rows :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Rows)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	{
		c := card_open(gtx, .Filled, clickable = true, clicked = &m.card_hit, key = 1)
		ui.spacer(gtx, 40)
		ui.close(&c)
		if m.card_hit {
			m.card_hits += 1
		}
	}
	list_item(gtx, {headline = "Multi", selection = .Multi, checked = &m.checked}, 300, key = 2)
	list_item(gtx, {headline = "Expand", kind = .Expanded, expanded = &m.expanded}, 300, key = 3)
	if list_item(gtx, {headline = "Plain", selection = .None}, 300, key = 4) {
		m.plain += 1
	}
	if list_item(gtx, {headline = "Click"}, 300, key = 5) {
		m.clicks += 1
	}
	list_item(gtx, {headline = "Reorder", kind = .Reorder, moved = &m.moved}, 300, key = 6)
	ACTIONS := [?]Icon{.Archive, .Delete}
	list_item(gtx, {headline = "Reveal", kind = .Reveal, actions = ACTIONS[:], action = &m.action}, 300, key = 7)
}

@(private = "file")
drag :: proc(p: ^ui.Probe, name: string, d: ops.Point) {
	c, ok := ui.probe_center(p, name)
	assert(ok)
	ui.router_push(&p.router, {kind = .Move, pos = c})
	ui.router_push(&p.router, {kind = .Press, pos = c, button = .Left})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Move, pos = c + d / 2})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Move, pos = c + d})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Release, pos = c + d, button = .Left})
	ui.probe_frame(p)
}

@(test)
test_list_item_selection_modes :: proc(t: ^testing.T) {
	m := Rows{action = -1}
	p: ui.Probe
	ui.probe_init(&p, rows, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Multi"))
	testing.expect(t, m.checked)
	testing.expect(t, ui.probe_click(&p, "Multi"))
	testing.expect(t, !m.checked)
	testing.expect(t, ui.probe_click(&p, "Expand"))
	testing.expect(t, m.expanded)
	// An informational row takes no input; a click row reports its click.
	testing.expect(t, !ui.probe_click(&p, "Plain"))
	testing.expect_value(t, m.plain, 0)
	testing.expect(t, ui.probe_click(&p, "Click"))
	testing.expect_value(t, m.clicks, 1)
}

@(test)
test_clickable_card_reports_its_click :: proc(t: ^testing.T) {
	m := Rows{action = -1}
	p: ui.Probe
	ui.probe_init(&p, rows, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.router_push(&p.router, {kind = .Move, pos = {30, 30}})
	ui.router_push(&p.router, {kind = .Press, pos = {30, 30}, button = .Left})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Release, pos = {30, 30}, button = .Left})
	ui.probe_frame(&p)
	testing.expect_value(t, m.card_hits, 1)
}

@(test)
test_reorder_row_moves_by_drag_and_by_key :: proc(t: ^testing.T) {
	m := Rows{action = -1}
	p: ui.Probe
	ui.probe_init(&p, rows, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Up 1.4 rows: a move of one, and no click.
	drag(&p, "Reorder", {0, -1.4 * 56})
	testing.expect_value(t, m.moved, -1)
	m.moved = 0
	// Focus by a click (which moves nothing), then Down.
	testing.expect(t, ui.probe_click(&p, "Reorder"))
	testing.expect_value(t, m.moved, 0)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, m.moved, 1)
}

@(test)
test_reveal_row_uncovers_its_actions :: proc(t: ^testing.T) {
	m := Rows{action = -1}
	p: ui.Probe
	ui.probe_init(&p, rows, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Closed, the actions take no clicks.
	testing.expect(t, !ui.probe_click(&p, "Reveal action 1"))
	drag(&p, "Reveal", {-120, 0})
	ui.probe_advance(&p, 60, 1.0 / 60) // let the snap spring settle
	testing.expect(t, ui.probe_click(&p, "Reveal action 1"))
	testing.expect_value(t, m.action, 1)
	// Choosing an action closes the row again.
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, !ui.probe_click(&p, "Reveal action 1"))
}

@(test)
test_reveal_row_follows_the_pointer_while_dragged :: proc(t: ^testing.T) {
	m := Rows{action = -1}
	p: ui.Probe
	ui.probe_init(&p, rows, &m, {400, 900}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// Held 30 dp left, before any release, the row has slid by 30: its
	// pressable part, all that is still over the row, is 30 narrower.
	before, ok := ui.probe_find(&p, "Reveal")
	testing.expect(t, ok)
	c, _ := ui.probe_center(&p, "Reveal")
	ui.router_push(&p.router, {kind = .Move, pos = c})
	ui.router_push(&p.router, {kind = .Press, pos = c, button = .Left})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Move, pos = c + {-30, 0}})
	ui.probe_frame(&p)
	held, _ := ui.probe_find(&p, "Reveal")
	testing.expect_value(t, held.shape.(ops.Rect).w, before.shape.(ops.Rect).w - 30)
}

@(private = "file")
Menus :: struct {
	open, dialog: bool,
	picked:       int,
	under:        int,
	timer:        f32,
	closed:       bool,
}

@(private = "file")
menus :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Menus)(user)
	r := ui.row_open(gtx, gap = 8)
	defer ui.close(&r)
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		if button(gtx, "Open") {
			m.open = true
		}
		ITEMS := [?]Menu_Item {
			{label = "Sort by", heading = true},
			{label = "Name", selected = true, selected_icon = .Check},
			{label = "Size", selected_icon = .Check, divider = true},
			{label = "Delete", leading = .Delete},
		}
		if i := menu(gtx, &m.open, ITEMS[:], style = .Vibrant, grouped = true); i >= 0 {
			m.picked = i
		}
	}
	if button(gtx, "Under") {
		m.under += 1
	}
	ACTIONS := [?]string{"OK"}
	dialog(gtx, &m.dialog, {400, 400}, "Title", "Body", ACTIONS[:])
	if m.timer >= 0 {
		_, closed := snackbar(gtx, "Saved", timer = &m.timer)
		m.closed = m.closed || closed
	}
}

@(test)
test_grouped_menu_picks_and_closing_frees_the_page :: proc(t: ^testing.T) {
	m := Menus{picked = -1, timer = -1}
	p: ui.Probe
	ui.probe_init(&p, menus, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Open"))
	testing.expect(t, m.open)
	ui.probe_advance(&p, 30, 1.0 / 60)
	// A group label is not an item.
	testing.expect(t, !ui.probe_click(&p, "Sort by"))
	testing.expect(t, ui.probe_click(&p, "Delete"))
	testing.expect_value(t, m.picked, 3)
	testing.expect(t, !m.open)
	// The menu fades out, but takes no input while it does.
	testing.expect(t, ui.probe_click(&p, "Under"))
	testing.expect_value(t, m.under, 1)
	testing.expect(t, !ui.probe_click(&p, "Name"))
}

@(test)
test_dialog_closes_on_escape_once_focused :: proc(t: ^testing.T) {
	m := Menus{picked = -1, timer = -1, dialog = true}
	p: ui.Probe
	ui.probe_init(&p, menus, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p)
	// A press on the dialog's own surface focuses it and keeps it open.
	c, _ := ui.probe_center(&p, "OK")
	at := ops.Point{200, c.y - 40}
	ui.router_push(&p.router, {kind = .Press, pos = at, button = .Left})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Release, pos = at, button = .Left})
	ui.probe_frame(&p)
	testing.expect(t, m.dialog)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.dialog)
}

@(test)
test_snackbar_timer_dismisses_after_short :: proc(t: ^testing.T) {
	m := Menus{picked = -1}
	p: ui.Probe
	ui.probe_init(&p, menus, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 3, 1)
	testing.expect(t, !m.closed)
	ui.probe_advance(&p, 2, 1)
	testing.expect(t, m.closed)
}
