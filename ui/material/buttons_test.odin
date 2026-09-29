package material

import "core:testing"
import "jm:ui"

// Behaviour of the buttons group, driven through ui.Probe by their tags.

@(private = "file")
Buttons_Model :: struct {
	liked, texted, starred: bool,
	open:                   bool,
	saves:                  int,
	expanded:               bool,
	days:                   [3]bool,
	clicks:                 int,
}

@(private = "file")
buttons :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Buttons_Model)(user)
	col := ui.column(gtx, gap = 16)
	defer ui.end(&col)
	button(gtx, "Like", .Tonal, .Favorite, checked = &m.liked)
	button(gtx, "Plain", .Text, checked = &m.texted)
	icon_button(gtx, .Star, .Filled, &m.starred, tooltip = "Star", size = .Large, width = .Wide, shape = .Square)
	if c, _ := split_button(gtx, "Save", &m.open, size = .Medium); c {
		m.saves += 1
	}
	split_button(gtx, "Send", &m.open, trailing_enabled = false, menu_label = "Send options", key = 1)
	LABELS := [?]string{"Day", "Week", "Month"}
	segmented_button(gtx, LABELS[:], m.days[:])
	if extended_fab(gtx, .Edit, "Compose", expanded = m.expanded) {
		m.clicks += 1
	}
	if button(gtx, "Tiny", size = .X_Small) {
		m.clicks += 10
	}
}

@(private = "file")
hit_rect :: proc(p: ^ui.Probe, name: string) -> ui.Rect {
	h, ok := ui.probe_find(p, name)
	if !ok {
		return {}
	}
	return ui.transform_rect(h.transform, ui.shape_bounds(&p.ops, h.shape))
}

@(test)
test_toggle_buttons_flip_their_checked_state :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 1000}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Like"))
	testing.expect(t, m.liked)
	testing.expect(t, ui.probe_click(&p, "Like"))
	testing.expect(t, !m.liked)
	// Text has no toggle: the click lands but checked stays put.
	testing.expect(t, ui.probe_click(&p, "Plain"))
	testing.expect(t, !m.texted)
	// An icon toggle is tagged by its tooltip and flips on click, then on
	// Enter once focused.
	testing.expect(t, ui.probe_click(&p, "Star"))
	testing.expect(t, m.starred)
	ui.probe_key(&p, .Enter)
	testing.expect(t, !m.starred)
}

@(test)
test_split_button_halves_act_apart :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 1000}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect_value(t, m.saves, 1)
	testing.expect(t, !m.open)
	testing.expect(t, ui.probe_click(&p, "More options"))
	testing.expect(t, m.open)
	testing.expect_value(t, m.saves, 1)
	// A disabled trailing half registers nothing to click; its leading
	// half still does.
	testing.expect(t, !ui.probe_click(&p, "Send options"))
	testing.expect(t, ui.probe_click(&p, "Send"))
	testing.expect(t, m.open)
}

@(test)
test_segmented_button_selects_one :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 1000}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Week"))
	testing.expect_value(t, m.days, [3]bool{false, true, false})
	testing.expect(t, ui.probe_click(&p, "Month"))
	testing.expect_value(t, m.days, [3]bool{false, false, true})
}

@(test)
test_extended_fab_springs_to_its_collapsed_square :: proc(t: ^testing.T) {
	m := Buttons_Model{expanded = true}
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 1000}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	wide := hit_rect(&p, "Compose").w
	testing.expect(t, wide > tok_fab_width())
	m.expanded = false
	ui.probe_advance(&p, 1, 1.0 / 60)
	mid := hit_rect(&p, "Compose").w
	testing.expect(t, mid < wide && mid > tok_fab_width()) // moving, not snapped
	ui.probe_advance(&p, 120, 1.0 / 60)
	testing.expect_value(t, hit_rect(&p, "Compose").w, tok_fab_width())
	testing.expect(t, ui.probe_click(&p, "Compose"))
	testing.expect_value(t, m.clicks, 1)
}

@(private = "file")
tok_fab_width :: proc() -> f32 {
	box, _, _ := fab_metrics(.Regular)
	return box.x
}

@(test)
test_small_buttons_take_a_48dp_touch_target :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 1000}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	r := hit_rect(&p, "Tiny")
	testing.expect_value(t, r.h, MIN_TOUCH)
	// A press 6dp below the 32dp container still lands.
	y := r.y + r.h / 2 + 16 + 6
	x := r.x + r.w / 2
	ui.probe_move(&p, x, y)
	ui.router_push(&p.router, {kind = .Press, pos = {x, y}})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Release, pos = {x, y}})
	ui.probe_frame(&p)
	testing.expect_value(t, m.clicks, 10)
}

// ellipse_fills counts the ellipse fills in p's last frame: a ripple is
// the only ellipse the buttons page paints.
@(private = "file")
ellipse_fills :: proc(p: ^ui.Probe) -> (n: int) {
	for op in p.ops.ops {
		if f, ok := op.(ui.Fill); ok {
			if _, e := f.shape.(ui.Ellipse); e {
				n += 1
			}
		}
	}
	return
}

@(test)
test_a_press_starts_a_ripple_that_fades_out :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	ui.probe_init(&p, buttons, &m, {600, 1000}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect_value(t, ellipse_fills(&p), 0)
	testing.expect(t, ui.probe_click(&p, "Tiny"))
	testing.expect_value(t, ellipse_fills(&p), 1) // still expanding a frame after release
	ui.probe_advance(&p, 60, 1.0 / 60) // a second: past RIPPLE_DURATION
	testing.expect_value(t, ellipse_fills(&p), 0)
}
