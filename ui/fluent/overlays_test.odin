package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of the overlays, driven through ui.Probe by their tags.

@(private = "file")
Overlay_Model :: struct {
	menu, dialog: bool,
	cuts, copies: int,
	bold:         bool,
	saved:        int,
	tip_id:       ops.Area_Id,
}

@(private = "file")
WINDOW :: ops.Size{800, 600}

@(private = "file")
overlays :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Overlay_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		menu_button(gtx, "Edit", &m.menu)
		if menu(gtx, &m.menu) {
			if menu_item(gtx, "Cut", .Delete, "Ctrl+X") {
				m.cuts += 1
			}
			if menu_item(gtx, "Copy", .Copy, "Ctrl+C", persist = true) {
				m.copies += 1
			}
			menu_divider(gtx)
			menu_header(gtx, "Format")
			menu_item(gtx, "Bold", check = .Checkbox, checked = &m.bold)
			menu_item(gtx, "Paste", disabled = true)
		}
	}
	if button(gtx, "Open dialog") {
		m.dialog = true
	}
	if dialog(gtx, &m.dialog, WINDOW) {
		dialog_title(gtx, "Discard changes?")
		text_block(gtx, "Your edits will be lost.", .Body1, color(.Neutral_Foreground1))
		if dialog_actions(gtx) {
			if button(gtx, "Cancel") {
				m.dialog = false
			}
			if button(gtx, "Discard", .Primary) {
				m.saved += 1
				m.dialog = false
			}
		}
	}
	tip_anchor(gtx, m)
}

// tip_anchor is a plain 40px square that shows a tooltip, the way a
// component calls tooltip from inside its own widget.
@(private = "file")
tip_anchor :: proc(gtx: ^ui.Ctx, m: ^Overlay_Model) {
	p := ui.widget_open(gtx)
	area := ops.Rect{0, 0, 40, 40}
	c := control(gtx, p.id, area, .Live)
	ops.fill(gtx.scene, area, color(.Neutral_Background3))
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, "anchor")
	tooltip(gtx, p.id, c, "A helpful hint", {40, 40})
	ui.widget_close(gtx, &p, {size = {40, 40}})
}

@(test)
test_menu_opens_from_its_trigger_and_items_close_it :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	_, found := ui.probe_find(&p, "Cut")
	testing.expect(t, !found) // closed: no items laid out
	testing.expect(t, ui.probe_click(&p, "Edit"))
	testing.expect(t, m.menu)
	ui.probe_advance(&p, 30, 0.02) // through the enter motion
	_, found = ui.probe_find(&p, "Cut")
	testing.expect(t, found)
	// A persistent item acts and keeps the menu open; a plain one closes it.
	testing.expect(t, ui.probe_click(&p, "Copy"))
	testing.expect_value(t, m.copies, 1)
	testing.expect(t, m.menu)
	testing.expect(t, ui.probe_click(&p, "Bold"))
	testing.expect(t, m.bold)
	testing.expect(t, !m.menu)
	// Reopen: the frame that closed it caught nothing, so this click
	// reaches the trigger.
	testing.expect(t, ui.probe_click(&p, "Edit"))
	testing.expect(t, m.menu)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Cut"))
	testing.expect_value(t, m.cuts, 1)
	testing.expect(t, !m.menu)
	// A disabled item takes nothing; a press outside closes.
	testing.expect(t, ui.probe_click(&p, "Edit"))
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_click(&p, "Paste"))
	testing.expect(t, m.menu)
	ui.router_push(&p.router, {kind = .Press, pos = {700, 500}, button = .Left})
	ui.router_push(&p.router, {kind = .Release, pos = {700, 500}, button = .Left})
	ui.probe_frame(&p)
	testing.expect(t, !m.menu)
	// Escape on a focused item closes too.
	testing.expect(t, ui.probe_click(&p, "Edit"))
	ui.probe_frame(&p)
	cb := ui.probe_bounds(&p, "Copy")
	ui.router_push(&p.router, {kind = .Press, pos = {cb.x + 5, cb.y + 5}, button = .Left})
	ui.probe_frame(&p)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.menu)
}

@(test)
test_menu_items_measure_the_popover :: proc(t: ^testing.T) {
	m: Overlay_Model
	m.menu = true
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 2, 0.5)
	cut := ui.probe_bounds(&p, "Cut")
	bold := ui.probe_bounds(&p, "Bold")
	testing.expect_value(t, cut.h, 32)
	testing.expect_value(t, cut.w, bold.w) // every item the popover's width
	testing.expect(t, cut.w >= 138 - 10 && cut.w <= 300 - 10)
	testing.expect(t, cut.y >= 36) // below the trigger
}

@(test)
test_dialog_opens_and_its_actions_backdrop_and_escape_close_it :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	_, found := ui.probe_find(&p, "Discard")
	testing.expect(t, !found)
	testing.expect(t, ui.probe_click(&p, "Open dialog"))
	ui.probe_advance(&p, 20, 0.02)
	_, found = ui.probe_find(&p, "Discard")
	testing.expect(t, found)
	// Centred in the window, at most 600 wide: the end action sits
	// inside the right edge of a 600px surface centred in 800.
	b := ui.probe_bounds(&p, "Discard")
	testing.expectf(t, b.x > 400 && b.x + b.w <= 700 - 24, "discard at %v", b)
	c := ui.probe_bounds(&p, "Cancel")
	testing.expect(t, c.x + c.w + 8 == b.x) // DIALOG_GAP apart, hugging the end
	testing.expect(t, ui.probe_click(&p, "Discard"))
	testing.expect_value(t, m.saved, 1)
	testing.expect(t, !m.dialog)
	ui.probe_frame(&p)
	_, found = ui.probe_find(&p, "Discard")
	testing.expect(t, !found)
	// The backdrop closes a modal dialog.
	testing.expect(t, ui.probe_click(&p, "Open dialog"))
	ui.probe_advance(&p, 20, 0.02)
	ui.router_push(&p.router, {kind = .Press, pos = {20, 500}, button = .Left})
	ui.probe_frame(&p)
	testing.expect(t, !m.dialog)
	// Escape once the surface has focus: a press on its padding.
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Open dialog"))
	ui.probe_advance(&p, 20, 0.02)
	db := ui.probe_bounds(&p, "Discard")
	ui.router_push(&p.router, {kind = .Press, pos = {db.x + db.w + 10, db.y + 10}, button = .Left})
	ui.probe_frame(&p)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.dialog)
}

@(test)
test_tooltip_shows_after_the_delay_and_hides_after_leaving :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	a := ui.probe_bounds(&p, "anchor")
	ui.probe_move(&p, a.x + 10, a.y + 10)
	ui.probe_advance(&p, 2, 0.05) // 100ms in: not yet
	_, found := ui.probe_find(&p, "A helpful hint")
	testing.expect(t, !found)
	testing.expect(t, p.wants_frame) // waiting for the delay
	ui.probe_advance(&p, 4, 0.05) // past 250ms
	_, found = ui.probe_find(&p, "A helpful hint")
	testing.expect(t, found)
	tip := ui.probe_bounds(&p, "A helpful hint")
	testing.expect(t, tip.y + tip.h <= a.y) // above the anchor
	testing.expect(t, tip.w <= 240)
	// Leaving hides it after the hide delay, not at once.
	ui.probe_move(&p, 700, 500)
	ui.probe_advance(&p, 1, 0.1)
	_, found = ui.probe_find(&p, "A helpful hint")
	testing.expect(t, found)
	ui.probe_advance(&p, 4, 0.1)
	_, found = ui.probe_find(&p, "A helpful hint")
	testing.expect(t, !found)
}

@(test)
test_wrap_breaks_at_spaces_and_keeps_a_long_word :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	gtx := &ui.Ctx{scene = &p.scene, shaper = p.shaper, font = p.font, allocator = context.temp_allocator}
	st := style(.Body1)
	one := wrap(gtx, "short", st, 1000)
	testing.expect_value(t, len(one), 1)
	w := shape_style(gtx, "aaaa bbbb", st).width
	two := wrap(gtx, "aaaa bbbb cccc", st, w)
	testing.expect_value(t, len(two), 2)
	testing.expect(t, two[0].width <= w + 0.5)
	long := wrap(gtx, "supercalifragilistic word", st, 10)
	testing.expect_value(t, len(long), 2)
	// The overlong word stays whole on its own line, wider than the
	// width it was offered.
	testing.expect_value(t, long[0].width, shape_style(gtx, "supercalifragilistic", st).width)
	testing.expect_value(t, len(wrap(gtx, "", st, 100)), 0)
}

// inside_window reports whether r lies wholly inside a window of size w.
@(private = "file")
inside_window :: proc(r: ops.Rect, w: ops.Size) -> bool {
	return r.x >= 0 && r.y >= 0 && r.x + r.w <= w.x && r.y + r.h <= w.y
}

// bottom_menu is a menu button 40px from the window's bottom edge, too
// low for its menu to open below.
@(private = "file")
bottom_menu :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Overlay_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	ui.spacer(gtx, WINDOW.y - 40)
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	menu_button(gtx, "Edit", &m.menu)
	if menu(gtx, &m.menu) {
		menu_item(gtx, "Cut")
		menu_item(gtx, "Copy")
		menu_item(gtx, "Paste")
	}
}

@(test)
test_menu_near_the_bottom_opens_above_its_trigger :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	ui.probe_init(&p, bottom_menu, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Edit"))
	ui.probe_advance(&p, 30, 0.02) // through the enter motion
	trigger := ui.probe_bounds(&p, "Edit")
	for name in ([]string{"Cut", "Copy", "Paste"}) {
		r := ui.probe_bounds(&p, name)
		testing.expectf(t, r.h > 0 && inside_window(r, WINDOW), "%s at %v leaves the window", name, r)
		testing.expectf(t, r.y + r.h <= trigger.y, "%s at %v is not above the trigger at %v", name, r, trigger)
	}
	// The flipped menu still acts.
	testing.expect(t, ui.probe_click(&p, "Cut"))
	testing.expect(t, !m.menu)
}

// top_tip is the tooltip anchor flush with the window's top edge, where
// a tooltip asked above has no room.
@(private = "file")
top_tip :: proc(gtx: ^ui.Ctx, user: rawptr) {
	tip_anchor(gtx, (^Overlay_Model)(user))
}

@(test)
test_tooltip_at_the_top_opens_below_its_anchor :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	ui.probe_init(&p, top_tip, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	a := ui.probe_bounds(&p, "anchor")
	ui.probe_move(&p, a.x + 10, a.y + 10)
	ui.probe_advance(&p, 6, 0.05) // past the show delay
	tip := ui.probe_bounds(&p, "A helpful hint")
	testing.expect(t, tip.h > 0 && inside_window(tip, WINDOW))
	testing.expectf(t, tip.y >= a.y + a.h, "tooltip at %v is not below the anchor at %v", tip, a)
}

// drag_across presses just inside the left of the text tagged s, drags past
// its right end and releases.
@(private = "file")
drag_across :: proc(p: ^ui.Probe, s: string) {
	b := ui.probe_bounds(p, s)
	y := b.y + b.h / 2
	ui.router_push(&p.router, {kind = .Press, pos = {b.x + 1, y}, clicks = 1})
	ui.router_push(&p.router, {kind = .Move, pos = {b.x + b.w + 5, y}})
	ui.router_push(&p.router, {kind = .Release, pos = {b.x + b.w + 5, y}, clicks = 1})
	ui.probe_frame(p)
	ui.probe_frame(p)
}

@(test)
test_a_dialogs_text_block_selects_and_copies :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	ui.probe_init(&p, overlays, &m, WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Open dialog"))
	ui.probe_advance(&p, 40, 0.02)
	drag_across(&p, "Your edits will be lost.")
	ctx := ui.Ctx{layout = &p.layout}
	testing.expect_value(t, ui.label_selection(&ctx), "Your edits will be lost.")
	ui.probe_key(&p, .C, {ui.SHORTCUT})
	testing.expect_value(t, ui.probe_clipboard(&p), "Your edits will be lost.")
	testing.expect(t, m.dialog, "selecting in the dialog leaves it open")
}
