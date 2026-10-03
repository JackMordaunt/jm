package primer

import "core:testing"
import "jm:ui"
import tok "jm:ui/primer/tokens"

// Behaviour of action_bar, driven through ui.Probe by tags.

@(private = "file")
Bar_Model :: struct {
	width: f32,
	hits:  [5]int,
	size:  Button_Size,
}

@(private = "file")
bar_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Bar_Model)(user)
	col := ui.column_open(gtx, gap = 8, align = .Start)
	defer ui.close(&col)
	button(gtx, "Before")
	band := ui.sized_open(gtx, {min = {m.width, 0}, max = {m.width, ui.INF}})
	b := action_bar_open(gtx, "Tools", m.size)
	if action_bar_icon_button(&b, .Bold, "Bold") {
		m.hits[0] += 1
	}
	if action_bar_icon_button(&b, .Italic, "Italic") {
		m.hits[1] += 1
	}
	action_bar_divider(&b)
	action_bar_group_open(&b)
	if action_bar_icon_button(&b, .List_Unordered, "Bullets") {
		m.hits[2] += 1
	}
	if action_bar_icon_button(&b, .List_Ordered, "Numbers") {
		m.hits[3] += 1
	}
	action_bar_group_close(&b)
	if action_bar_button(&b, "Mention", .Mention) {
		m.hits[4] += 1
	}
	action_bar_close(&b)
	ui.close(&band)
	button(gtx, "After")
}

@(private = "file")
bar_probe :: proc(p: ^ui.Probe, m: ^Bar_Model) {
	ui.probe_init(p, bar_view, m, {800, 600}, allocator = context.temp_allocator)
}

@(test)
test_an_action_bar_sits_at_its_end_with_8px_between_items :: proc(t: ^testing.T) {
	m := Bar_Model{width = 600, size = .Medium}
	p: ui.Probe
	bar_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	bold, italic := ui.probe_bounds(&p, "Bold"), ui.probe_bounds(&p, "Italic")
	mention := ui.probe_bounds(&p, "Mention")
	testing.expect_value(t, bold.h, tok.CONTROL_MEDIUM_SIZE)
	testing.expect_value(t, italic.x, bold.x + bold.w + tok.STACK_GAP_CONDENSED)
	testing.expect_value(t, mention.x + mention.w, 600 - tok.BASE_SIZE_16) // at the end, 16px in
	testing.expect(t, !ui.probe_tagged(&p, "More items"))
	m.size = .Small
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Bold").h, tok.CONTROL_SMALL_SIZE)
}

@(test)
test_an_action_bar_moves_what_does_not_fit_into_its_more_menu :: proc(t: ^testing.T) {
	m := Bar_Model{width = 200, size = .Medium}
	p: ui.Probe
	bar_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p)

	testing.expect(t, ui.probe_tagged(&p, "More items"))
	testing.expect(t, ui.probe_tagged(&p, "Bold") && ui.probe_tagged(&p, "Italic"))
	// The group goes as one: neither of its items shows.
	testing.expect(t, !ui.probe_tagged(&p, "Bullets") && !ui.probe_tagged(&p, "Numbers") && !ui.probe_tagged(&p, "Mention"))
	more := ui.probe_bounds(&p, "More items")
	testing.expect(t, more.x + more.w <= 200 - tok.BASE_SIZE_16)
	// The menu lists them, and choosing one reports it from its own call.
	testing.expect(t, ui.probe_click(&p, "More items"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Numbers"))
	testing.expect(t, ui.probe_click(&p, "Numbers"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.hits[3], 1)
	// The More button's width comes out of the row: at 152px (120 inside)
	// Italic would fit without it, but not beside it.
	m.width = 152
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	more = ui.probe_bounds(&p, "More items")
	testing.expect(t, ui.probe_tagged(&p, "Bold") && ui.probe_tagged(&p, "More items") && more.w > 0)
	testing.expect(t, !ui.probe_tagged(&p, "Italic"))
	testing.expect(t, more.x + more.w <= 152 - tok.BASE_SIZE_16)
	// Wide again, the More button goes.
	m.width = 600
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_tagged(&p, "More items"))
	testing.expect(t, ui.probe_tagged(&p, "Mention"))
}

@(test)
test_an_action_bar_is_one_tab_stop_with_arrows_that_wrap :: proc(t: ^testing.T) {
	m := Bar_Model{width = 200, size = .Medium}
	p: ui.Probe
	bar_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_frame(&p)

	ui.probe_click(&p, "Before")
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "Bold")
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, ui.probe_focus_name(&p), "After") // past the toolbar in one stop
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, ui.probe_focus_name(&p), "Bold")
	ui.probe_key(&p, .Right)
	ui.probe_key(&p, .Right) // a key straight after a move still lands
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "More items")
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "Bold") // wraps
	ui.probe_key(&p, .End)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_focus_name(&p), "More items")
	ui.probe_key(&p, .Home)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.hits[1], 1) // Enter on Italic
}
