package fluent

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of the containers, driven through ui.Probe by their tags.

@(private = "file")
Containers_Model :: struct {
	tab:        int,
	vtab:       int,
	changes:    int,
	open:       bool,
	sel:        bool,
	card_hit:   bool,
	hits:       int,
	divider:    ui.Dims,
	vdivider:   ui.Dims,
	labelled:   ui.Dims,
}

@(private = "file")
TABS := [?]string{"Home", "Pages", "Documents"}
@(private = "file")
VTABS := [?]string{"Alpha", "Beta", "Gamma"}

@(private = "file")
containers :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Containers_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if tab_list(gtx, TABS[:], &m.tab) {
		m.changes += 1
	}
	tab_list(gtx, VTABS[:], &m.vtab, vertical = true, key = 1)
	if accordion_item(gtx, "Section", &m.open) {
		button(gtx, "Inside")
		button(gtx, "Below")
	}
	if card(gtx, .Filled, selected = &m.sel, clicked = &m.card_hit, name = "Card") {
		button(gtx, "In card")
	}
	if m.card_hit {
		m.hits += 1
	}
	m.divider = divider(gtx)
	m.labelled = divider(gtx, "Or", inset = true, key = 2)
	if ui.row(gtx, align = .Fill) {
		ui.spacer(gtx, 40)
		m.vdivider = divider(gtx, vertical = true, key = 3)
	}
	if toolbar(gtx, .Small) {
		toolbar_button(gtx, "Bold", .Text_Bold)
		toolbar_divider(gtx)
		toolbar_button(gtx, "Italic", .Text_Italic)
	}
}

// click_at presses and releases at pos over two frames, as probe_click
// does at a tag's centre.
@(private = "file")
click_at :: proc(p: ^ui.Probe, pos: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = pos})
	ui.router_push(&p.router, {kind = .Press, pos = pos, button = .Left})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Release, pos = pos, button = .Left})
	ui.probe_frame(p)
}

// focused_tag is the tag of the area holding keyboard focus.
@(private)
focused_tag :: proc(p: ^ui.Probe) -> string {
	for tg in ui.probe_current(p).tags {
		if tg.id == p.router.focus {
			return tg.name
		}
	}
	return ""
}

@(test)
test_tab_list_selects_by_click_and_enter_and_roves_by_arrows :: proc(t: ^testing.T) {
	m: Containers_Model
	p: ui.Probe
	ui.probe_init(&p, containers, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Pages"))
	testing.expect_value(t, m.tab, 1)
	testing.expect_value(t, m.changes, 1)
	// Right moves focus on from the focused tab, wrapping; the selection stays.
	ui.probe_key(&p, .Right)
	testing.expect_value(t, focused_tag(&p), "Documents")
	ui.probe_key(&p, .Right)
	testing.expect_value(t, focused_tag(&p), "Home")
	testing.expect_value(t, m.tab, 1)
	// Up and Down mean nothing to a horizontal list.
	ui.probe_key(&p, .Down)
	testing.expect_value(t, focused_tag(&p), "Home")
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.tab, 0)
	// One tab stop, entered at the selected tab.
	ui.probe_key(&p, .End)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, focused_tag(&p), "Alpha")
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, focused_tag(&p), "Home")
	// A horizontal medium tab is 44px tall (useTabStyles.styles.ts:64-90).
	testing.expect_value(t, ui.probe_bounds(&p, "Home").h, 44)
}

@(test)
test_vertical_tab_list_takes_up_and_down :: proc(t: ^testing.T) {
	m: Containers_Model
	p: ui.Probe
	ui.probe_init(&p, containers, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Alpha"))
	testing.expect_value(t, m.vtab, 0)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, focused_tag(&p), "Beta")
	ui.probe_key(&p, .Right) // Left and Right mean nothing to a vertical list
	testing.expect_value(t, focused_tag(&p), "Beta")
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.vtab, 1)
	ui.probe_key(&p, .Up)
	testing.expect_value(t, focused_tag(&p), "Alpha")
	testing.expect_value(t, ui.probe_bounds(&p, "Alpha").h, 32) // a vertical medium tab row
}

@(test)
test_accordion_lays_its_panel_out_only_while_open :: proc(t: ^testing.T) {
	m: Containers_Model
	p: ui.Probe
	ui.probe_init(&p, containers, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	_, inside := ui.probe_find(&p, "Inside")
	testing.expect(t, !inside)
	// A medium header is at least 44px tall and as wide as the column.
	hd := ui.probe_bounds(&p, "Section")
	testing.expect_value(t, hd.h, 44)
	testing.expect(t, hd.w >= 300)
	testing.expect(t, ui.probe_click(&p, "Section"))
	testing.expect(t, m.open)
	ui.probe_frame(&p)
	_, inside = ui.probe_find(&p, "Inside")
	testing.expect(t, inside)
	// The panel stacks its children below the header, one under the next.
	in_b, below := ui.probe_bounds(&p, "Inside"), ui.probe_bounds(&p, "Below")
	testing.expect(t, in_b.y >= hd.y + hd.h)
	testing.expect(t, below.y >= in_b.y + in_b.h)
	testing.expect_value(t, below.x, in_b.x)
	// Enter on the focused header closes it again.
	ui.probe_key(&p, .Enter)
	testing.expect(t, !m.open)
	ui.probe_frame(&p)
	_, inside = ui.probe_find(&p, "Inside")
	testing.expect(t, !inside)
}

@(test)
test_card_guard_lays_out_its_body_and_selects_on_click :: proc(t: ^testing.T) {
	m: Containers_Model
	p: ui.Probe
	ui.probe_init(&p, containers, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	_, ok := ui.probe_find(&p, "In card")
	testing.expect(t, ok)
	// The body sits inside the medium card's 12px padding.
	c := ui.probe_bounds(&p, "Card")
	b := ui.probe_bounds(&p, "In card")
	testing.expect_value(t, b.x - c.x, 12)
	testing.expect_value(t, b.y - c.y, 12)
	// The card is its content plus padding, so its centre is the button:
	// click in the padding instead, near the bottom-right corner.
	corner := ops.Point{c.x + c.w - 4, c.y + c.h - 4}
	click_at(&p, corner)
	testing.expect(t, m.sel)
	testing.expect_value(t, m.hits, 1)
	click_at(&p, corner)
	testing.expect(t, !m.sel)
}

@(test)
test_dividers_take_the_space_they_are_offered :: proc(t: ^testing.T) {
	m: Containers_Model
	p: ui.Probe
	ui.probe_init(&p, containers, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, m.divider.size, ops.Size{600, 1}) // the column's width, a thin line
	testing.expect_value(t, m.labelled.size, ops.Size{600, 16}) // a caption line box
	testing.expect_value(t, m.vdivider.size.x, 1) // a thin line the row's height, at least 20
	testing.expect(t, m.vdivider.size.y >= 20)
	_, tagged := ui.probe_find(&p, "Or")
	testing.expect(t, !tagged) // no input area: a divider takes no input
}

@(test)
test_toolbar_sizes_its_items :: proc(t: ^testing.T) {
	m: Containers_Model
	p: ui.Probe
	ui.probe_init(&p, containers, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	bold := ui.probe_bounds(&p, "Bold")
	testing.expect_value(t, bold.h, 24) // a small toolbar's items are small
	italic := ui.probe_bounds(&p, "Italic")
	// The divider between them is 1px with 12px either side.
	testing.expect_value(t, italic.x - (bold.x + bold.w), 25)
	testing.expect_value(t, toolbar_item_size(), Size.Medium) // none open now
}

// focus_strokes counts the scene's paints in the focus colour.
@(private = "file")
focus_strokes :: proc(p: ^ui.Probe) -> (n: int) {
	fc := color(.Stroke_Focus2)
	for op in p.scene.ops {
		#partial switch v in op {
		case ops.Fill:
			if c, ok := v.paint.(ops.Color); ok && c == fc {
				n += 1
			}
		case ops.Stroke:
			if c, ok := v.paint.(ops.Color); ok && c == fc {
				n += 1
			}
		}
	}
	return
}

@(test)
test_focus_outline_shows_for_keys_not_clicks :: proc(t: ^testing.T) {
	m: Containers_Model
	p: ui.Probe
	ui.probe_init(&p, containers, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, focus_strokes(&p), 0)
	// A click focuses the header, and Enter reaches it, but no outline shows.
	testing.expect(t, ui.probe_click(&p, "Section"))
	testing.expect(t, m.open)
	testing.expect_value(t, focus_strokes(&p), 0)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_strokes(&p), 0)
	// A key shows it on the focused header, and it stays.
	ui.probe_key(&p, .Enter)
	testing.expect(t, !m.open)
	testing.expect_value(t, focus_strokes(&p), 1)
	ui.probe_frame(&p)
	testing.expect_value(t, focus_strokes(&p), 1)
	// The next press hides it again, on the button it focuses.
	testing.expect(t, ui.probe_click(&p, "Bold"))
	testing.expect_value(t, focus_strokes(&p), 0)
	ui.probe_key(&p, .Tab)
	testing.expect(t, focus_strokes(&p) > 0)
}
