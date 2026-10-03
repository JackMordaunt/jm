package primer

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

@(private = "file")
Group_Model :: struct {
	hits:    [3]int,
	hovered: bool,
	width:   f32,
}

@(private = "file")
group_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Group_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	g := button_group_open(gtx, 3, "Formatting", toolbar = true)
	for name, i in ([]string{"Bold", "Italic", "Code"}) {
		st := Interaction.Hovered if m.hovered && i == 1 else .Live
		if button(gtx, name, group = &g, state = st, key = u64(i)) {
			m.hits[i] += 1
		}
	}
	button_group_close(&g)
	m.width = ui.last_widget(gtx).size.x
	one := button_group_open(gtx, 1, key = 9)
	icon_button(gtx, .Gear, "Settings", group = &one)
	button_group_close(&one)
}

@(test)
test_a_button_group_joins_its_buttons_one_border_apart :: proc(t: ^testing.T) {
	m: Group_Model
	p: ui.Probe
	ui.probe_init(&p, group_view, &m, {600, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Italic"))
	testing.expect_value(t, m.hits[1], 1)
	b, i, c := ui.probe_bounds(&p, "Bold"), ui.probe_bounds(&p, "Italic"), ui.probe_bounds(&p, "Code")
	testing.expect_value(t, i.x, b.x + b.w - 1) // each over the next by 1px
	testing.expect_value(t, c.x, i.x + i.w - 1)
}

@(test)
test_a_toolbar_group_moves_focus_by_arrows_and_wraps :: proc(t: ^testing.T) {
	m: Group_Model
	p: ui.Probe
	ui.probe_init(&p, group_view, &m, {600, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_click(&p, "Code")
	ui.probe_key(&p, .Right) // past the last: wraps to the first
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.hits[0], 1)
	ui.probe_key(&p, .Left) // before the first: wraps to the last
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.hits[2], 2) // the click and this Enter
	// One Tab stop: Tab leaves for the next group's button.
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, focus_name(&p), "Settings")
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, focus_name(&p), "Code")
}

@(test)
test_a_hovered_item_draws_its_border_again_above_its_neighbours :: proc(t: ^testing.T) {
	count_defers :: proc(p: ^ui.Probe) -> (n: int) {
		for op in p.scene.ops {
			if _, ok := op.(ops.Defer); ok {
				n += 1
			}
		}
		return
	}
	m: Group_Model
	p: ui.Probe
	ui.probe_init(&p, group_view, &m, {600, 300}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	before := count_defers(&p)
	m.hovered = true
	ui.probe_frame(&p)
	testing.expect_value(t, count_defers(&p), before + 1)
}
