package material

import "core:math"
import "jm:ui/ops"
import "core:testing"
import "jm:ui"
import "jm:ui/testutil"

// Behaviour of the surfaces group: search, sheets, the drag handle, the
// date and time pickers and the carousel, driven through ui.Probe.

@(private = "file")
has :: proc(p: ^ui.Probe, name: string) -> bool {
	for n in ui.probe_names(p) {
		if n == name {
			return true
		}
	}
	return false
}

// press_at, move_to and release_at push one raw pointer event at device
// point pt and run a frame.
@(private = "file")
press_at :: proc(p: ^ui.Probe, pt: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = pt})
	ui.router_push(&p.router, {kind = .Press, pos = pt})
	ui.probe_frame(p)
}

@(private = "file")
move_to :: proc(p: ^ui.Probe, pt: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = pt})
	ui.probe_frame(p)
}

@(private = "file")
release_at :: proc(p: ^ui.Probe, pt: ops.Point) {
	ui.router_push(&p.router, {kind = .Release, pos = pt})
	ui.probe_frame(p)
}

@(private = "file")
Search_Model :: struct {
	q:              ui.Text_State,
	open, searched: bool,
	view:           Search_View,
}

@(private = "file")
search_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Search_Model)(user)
	S := [?]string{"Material", "Motion", "Shape"}
	search_bar(gtx, &m.q, "Find", suggestions = S[:], view = m.view, expanded = &m.open, window = {600, 500}, submitted = &m.searched)
}

@(test)
test_search_bar_owned_expansion_escape_and_submit :: proc(t: ^testing.T) {
	m := Search_Model{view = .Docked_With_Gap}
	defer ui.text_destroy(&m.q)
	p: ui.Probe
	ui.probe_init(&p, search_ui, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Find"))
	testing.expect(t, m.open)
	ui.probe_advance(&p, 30, 1.0 / 60)
	testing.expect(t, has(&p, "Shape"))
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
	ui.probe_advance(&p, 30, 1.0 / 60)
	testing.expect(t, !has(&p, "Shape"))

	testing.expect(t, ui.probe_click(&p, "Find"))
	ui.probe_type(&p, "Mo")
	ui.probe_key(&p, .Enter)
	testing.expect(t, m.searched)
	testing.expect(t, !m.open)
	testing.expect_value(t, ui.text_string(&m.q), "Mo")
}

@(test)
test_full_screen_search_opens_over_the_window_and_backs_out :: proc(t: ^testing.T) {
	m := Search_Model{view = .Full_Screen}
	defer ui.text_destroy(&m.q)
	p: ui.Probe
	ui.probe_init(&p, search_ui, &m, {600, 500}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Find"))
	ui.probe_advance(&p, 90, 1.0 / 60)
	// Settled, the view covers the window: its last row is far below the bar.
	c, ok := ui.probe_center(&p, "Shape")
	testing.expect(t, ok)
	testing.expect(t, c.y > 150)
	testing.expect(t, ui.probe_click(&p, "search back"))
	testing.expect(t, !m.open)
	// Picking a row fills the field and collapses.
	ui.probe_advance(&p, 90, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "Find"))
	ui.probe_advance(&p, 90, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "Motion"))
	testing.expect(t, !m.open)
	testing.expect_value(t, ui.text_string(&m.q), "Motion")
}

@(private = "file")
Sheet_Model :: struct {
	open:  bool,
	value: Sheet_Value,
	under: int,
	side:  bool,
}

@(private = "file")
sheet_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Sheet_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	if button(gtx, "Under") {
		m.under += 1
	}
	sh := bottom_sheet_open(gtx, &m.open, {400, 600}, value = &m.value)
	if sh.visible {
		button(gtx, "Inside")
	}
	sheet_close(&sh)
	ss := side_sheet_open(gtx, &m.side, {400, 600}, width = 300)
	if ss.visible {
		button(gtx, "Side inside")
	}
	sheet_close(&ss)
}

@(test)
test_bottom_sheet_scrim_handle_and_drag_close_it :: proc(t: ^testing.T) {
	m := Sheet_Model{open = true}
	p: ui.Probe
	ui.probe_init(&p, sheet_ui, &m, {400, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, has(&p, "Inside"))
	// A short sheet's partial anchor is its full height.
	testing.expect_value(t, m.value, Sheet_Value.Partially_Expanded)

	// The scrim takes a click meant for the page and closes the sheet,
	// which then slides away.
	testing.expect(t, ui.probe_click(&p, "Under"))
	testing.expect_value(t, m.under, 0)
	testing.expect(t, !m.open)
	testing.expect_value(t, m.value, Sheet_Value.Hidden)
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, !has(&p, "Inside"))
	testing.expect(t, ui.probe_click(&p, "Under"))
	testing.expect_value(t, m.under, 1)

	// The handle's click cycles: Partially_Expanded expands, Expanded hides.
	m.open = true
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "drag handle"))
	testing.expect_value(t, m.value, Sheet_Value.Expanded)
	testing.expect(t, ui.probe_click(&p, "drag handle"))
	testing.expect(t, !m.open)

	// A drag down past the positional threshold dismisses it.
	m.open = true
	ui.probe_advance(&p, 60, 1.0 / 60)
	c, ok := ui.probe_center(&p, "drag handle")
	testing.expect(t, ok)
	press_at(&p, c)
	move_to(&p, c + {0, 30})
	testing.expect(t, m.open) // still following the pointer
	move_to(&p, c + {0, 90})
	release_at(&p, c + {0, 90})
	testing.expect(t, !m.open)
}

@(test)
test_bottom_sheet_flick_dismisses_and_a_held_drag_does_not :: proc(t: ^testing.T) {
	m := Sheet_Model{open = true}
	p: ui.Probe
	ui.probe_init(&p, sheet_ui, &m, {400, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 60, 1.0 / 60)
	c, ok := ui.probe_center(&p, "drag handle")
	testing.expect(t, ok)

	// 30 dp down at 10 a frame, short of the 56 dp threshold, held for
	// half a second, then let go: the pointer stopped, so the sheet stays.
	press_at(&p, c)
	for i in 1 ..= 3 {
		move_to(&p, c + {0, 10 * f32(i)})
	}
	ui.probe_advance(&p, 30, 1.0 / 60)
	release_at(&p, c + {0, 30})
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, m.open)
	testing.expect_value(t, m.value, Sheet_Value.Partially_Expanded)

	// The same 30 dp let go while moving (600 dp/s) is a flick: it hides.
	press_at(&p, c)
	for i in 1 ..= 3 {
		move_to(&p, c + {0, 10 * f32(i)})
	}
	release_at(&p, c + {0, 30})
	testing.expect(t, !m.open)
}

@(test)
test_side_sheet_closes_on_escape_and_scrim :: proc(t: ^testing.T) {
	m := Sheet_Model{side = true}
	p: ui.Probe
	ui.probe_init(&p, sheet_ui, &m, {400, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, has(&p, "Side inside"))
	testing.expect(t, ui.probe_click(&p, "sheet"))
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.side)
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, !has(&p, "Side inside"))

	m.side = true
	ui.probe_advance(&p, 60, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "Under"))
	testing.expect(t, !m.side)
	testing.expect_value(t, m.under, 0)
}

@(test)
test_drag_handle_reports_the_pull_from_its_grab :: proc(t: ^testing.T) {
	M :: struct {
		pane: f32,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		r := ui.row_open(gtx)
		defer ui.close(&r)
		ui.spacer(gtx, m.pane)
		m.pane += drag_handle(gtx)
	}
	m: M
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	c, ok := ui.probe_center(&p, "drag_handle")
	testing.expect(t, ok)
	press_at(&p, c)
	move_to(&p, c + {30, 0})
	testing.expect_value(t, m.pane, 30)
	ui.probe_frame(&p) // no move: the handle, now drawn at 30, stays put
	testing.expect_value(t, m.pane, 30)
	move_to(&p, c + {50, 0})
	testing.expect_value(t, m.pane, 50)
	release_at(&p, c + {50, 0})

	// A drag with a move every frame: each is routed against a frame that
	// drew the handle one move behind, which must not count that move twice.
	c, ok = ui.probe_center(&p, "drag_handle")
	press_at(&p, c)
	for i in 1 ..= 5 {
		move_to(&p, c + {f32(10 * i), 0})
		testing.expect_value(t, m.pane, 50 + f32(10 * i))
	}
	release_at(&p, c + {50, 0})
}

@(private = "file")
Date_Model :: struct {
	start, end, view: Date,
	mode:             Date_Mode,
	input:            ui.Text_State,
	ranged:           bool,
}

@(private = "file")
date_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Date_Model)(user)
	date_picker(gtx, &m.start, &m.view, {2026, 9, 28}, range_end = m.ranged ? &m.end : nil, mode = &m.mode, input = &m.input)
}

@(test)
test_date_range_takes_two_clicks_and_restarts_before_its_start :: proc(t: ^testing.T) {
	m := Date_Model{view = {2026, 9, 1}, ranged = true}
	p: ui.Probe
	ui.probe_init(&p, date_ui, &m, {400, 700}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "2026-09-03"))
	testing.expect_value(t, m.start, Date{2026, 9, 3})
	testing.expect_value(t, m.end, Date{})
	testing.expect(t, ui.probe_click(&p, "2026-09-07"))
	testing.expect_value(t, m.end, Date{2026, 9, 7})
	testing.expect(t, ui.probe_click(&p, "2026-09-01"))
	testing.expect_value(t, m.start, Date{2026, 9, 1})
	testing.expect_value(t, m.end, Date{})
}

@(test)
test_date_picker_year_menu_and_input_mode :: proc(t: ^testing.T) {
	m := Date_Model{view = {2026, 9, 1}}
	defer ui.text_destroy(&m.input)
	p: ui.Probe
	ui.probe_init(&p, date_ui, &m, {400, 700}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	// The year menu opens a few years before the shown one; a pick shows it.
	testing.expect(t, ui.probe_click(&p, "year menu"))
	testing.expect(t, has(&p, "year 2026"))
	testing.expect(t, !has(&p, "2026-09-01")) // the grid gives way to the years
	testing.expect(t, ui.probe_click(&p, "year 2030"))
	testing.expect_value(t, m.view.year, 2030)
	ui.probe_frame(&p) // the grid returns the frame after the pick
	testing.expect(t, has(&p, "2030-09-01"))

	// Input mode: digits, slashes implied, a complete valid date selects.
	testing.expect(t, ui.probe_click(&p, "date mode"))
	testing.expect_value(t, m.mode, Date_Mode.Input)
	ui.probe_advance(&p, 30, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "date input"))
	ui.probe_type(&p, "12x2520261")
	testing.expect_value(t, ui.text_string(&m.input), "12252026")
	testing.expect_value(t, m.start, Date{2026, 12, 25})
	testing.expect_value(t, m.view, Date{2026, 12, 1})
	// An impossible date selects nothing.
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_type(&p, "312026")
	testing.expect_value(t, ui.text_string(&m.input), "12312026")
	testing.expect_value(t, m.start, Date{2026, 12, 31})
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_key(&p, .Backspace)
	ui.probe_type(&p, "322026") // 12/32/2026
	testing.expect_value(t, m.start, Date{2026, 12, 31})
}

@(private = "file")
Time_Model :: struct {
	t:    Time,
	em:   bool,
	mode: Time_Mode,
}

@(private = "file")
time_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Time_Model)(user)
	time_picker(gtx, &m.t, &m.em, mode = m.mode)
}

@(test)
test_time_picker_selectors_period_and_dial :: proc(t: ^testing.T) {
	m := Time_Model{t = {9, 41}}
	p: ui.Probe
	ui.probe_init(&p, time_ui, &m, {400, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "minute"))
	testing.expect(t, m.em)
	testing.expect(t, ui.probe_click(&p, "hour"))
	testing.expect(t, !m.em)
	testing.expect(t, ui.probe_click(&p, "PM"))
	testing.expect_value(t, m.t.hour, 21)
	testing.expect(t, ui.probe_click(&p, "PM")) // the current half: no change
	testing.expect_value(t, m.t.hour, 21)
	testing.expect(t, ui.probe_click(&p, "AM"))
	testing.expect_value(t, m.t.hour, 9)

	// A tap on the dial at 3 o'clock picks 3 and moves on to minutes.
	c, ok := ui.probe_center(&p, "clock dial")
	testing.expect(t, ok)
	R := tok_dial_ring()
	press_at(&p, c + {R, 0})
	release_at(&p, c + {R, 0})
	testing.expect_value(t, m.t.hour, 3)
	testing.expect(t, m.em)
	// A tap at 7 minutes snaps to 5; a drag there keeps the whole minute.
	a := f32(7) / 60 * 2 * math.PI
	at := c + R * ops.Point{math.sin(a), -math.cos(a)}
	press_at(&p, at)
	release_at(&p, at)
	testing.expect_value(t, m.t.minute, 5)
	press_at(&p, c + {0, -R})
	move_to(&p, at)
	release_at(&p, at)
	testing.expect_value(t, m.t.minute, 7)
}

// tok_dial_ring is the outer ring's radius the dial places numbers on.
@(private = "file")
tok_dial_ring :: proc() -> f32 {
	return TIME_OUTER_RING * 256
}

@(test)
test_time_input_fields_take_digits :: proc(t: ^testing.T) {
	m := Time_Model{t = {9, 41}, mode = .Input}
	p: ui.Probe
	ui.probe_init(&p, time_ui, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "minute"))
	testing.expect(t, m.em)
	ui.probe_type(&p, "37")
	testing.expect_value(t, m.t.minute, 37)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, m.t.minute, 36)
	testing.expect(t, ui.probe_click(&p, "hour"))
	ui.probe_type(&p, "11")
	testing.expect_value(t, m.t.hour, 11)
	ui.probe_click(&p, "PM")
	testing.expect_value(t, m.t.hour, 23)
}

@(test)
test_carousel_keylines_fill_the_width :: proc(t: ^testing.T) {
	for w in ([?]f32{360, 400, 560, 720}) {
		k := carousel_keylines(.Multi_Browse, w, 186, 8, CAROUSEL_MIN_SMALL, CAROUSEL_MAX_SMALL)
		// Every keyline after the leaving one is on screen: they fill w.
		sum: f32
		for i in 1 ..< k.count {
			sum += k.sizes[i] + (i > 1 ? 8 : 0)
		}
		testing.expectf(t, abs(sum - w) < 0.01, "width %v: keylines sum to %v", w, sum)
		testing.expect(t, k.small >= CAROUSEL_MIN_SMALL && k.small <= CAROUSEL_MAX_SMALL)
	}
	h := carousel_keylines(.Hero_Start, 400, 300, 8, CAROUSEL_MIN_SMALL, CAROUSEL_MAX_SMALL)
	testing.expect_value(t, h.large + 8 + h.small, 400)
	// Too narrow for a hero's peek: full screen.
	f := carousel_keylines(.Hero_Start, 80, 300, 0, CAROUSEL_MIN_SMALL, CAROUSEL_MAX_SMALL)
	testing.expect_value(t, f.large, 80)
	// An item's mask is continuous as the position crosses a whole item.
	k := carousel_keylines(.Multi_Browse, 400, 186, 8, CAROUSEL_MIN_SMALL, CAROUSEL_MAX_SMALL)
	a, _ := carousel_item_rect(k, 0.9999, 1, 7, 8, 100)
	b, _ := carousel_item_rect(k, 1, 1, 7, 8, 100)
	testing.expect(t, abs(a.x - b.x) < 0.1 && abs(a.w - b.w) < 0.1)
}

@(test)
test_carousel_steps_by_key_and_reports_clicks :: proc(t: ^testing.T) {
	M :: struct {
		hit: int,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		items := [?]Carousel_Item{{"A", {}, {}}, {"B", {}, {}}, {"C", {}, {}}, {"D", {}, {}}, {"E", {}, {}}}
		if i := carousel(gtx, items[:], 400, 200, item_spacing = 8); i >= 0 {
			m.hit = i
		}
	}
	m := M{hit = -1}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	c, ok := ui.probe_center(&p, "carousel")
	testing.expect(t, ok)
	left := ops.Point{c.x - 190, c.y}
	press_at(&p, left)
	release_at(&p, left)
	testing.expect_value(t, m.hit, 0)
	ui.probe_key(&p, .Right)
	ui.probe_advance(&p, 60, 1.0 / 60)
	press_at(&p, left)
	release_at(&p, left)
	testing.expect_value(t, m.hit, 1)
	// A scroll of most of an item moves it on; resting, it snaps to the
	// next whole item, so the leftmost is the next one.
	k := carousel_keylines(.Multi_Browse, 400, 186, 8, CAROUSEL_MIN_SMALL, CAROUSEL_MAX_SMALL)
	ui.probe_scroll(&p, "carousel", 0.8 * (k.large + 8))
	ui.probe_advance(&p, 120, 1.0 / 60)
	m.hit = -1
	press_at(&p, left)
	release_at(&p, left)
	testing.expect_value(t, m.hit, 2)
}

@(test)
test_carousel_follows_a_drag_which_is_not_a_click :: proc(t: ^testing.T) {
	M :: struct {
		hit:   int,
		state: Carousel_State,
	}
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		m := (^M)(user)
		items := [?]Carousel_Item{{"A", {}, {}}, {"B", {}, {}}, {"C", {}, {}}, {"D", {}, {}}, {"E", {}, {}}}
		if i := carousel(gtx, items[:], 400, 200, item_spacing = 8, state = &m.state); i >= 0 {
			m.hit = i
		}
	}
	m := M{hit = -1}
	p: ui.Probe
	ui.probe_init(&p, view, &m, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	k := carousel_keylines(.Multi_Browse, 400, 186, 8, CAROUSEL_MIN_SMALL, CAROUSEL_MAX_SMALL)
	pitch := k.large + 8
	// Dragged left by half an item, held: it has scrolled half an item.
	c, _ := ui.probe_center(&p, "carousel")
	c.x += 20
	press_at(&p, c)
	move_to(&p, c - {pitch / 4, 0})
	move_to(&p, c - {pitch / 2, 0})
	testing.expect(t, testutil.near(m.state.position, 0.5))
	// Letting go there, over an item, is not a click on it.
	testing.expect(t, carousel_hit(k, 0.5, 5, c.x - pitch / 2, 8) >= 0)
	release_at(&p, c - {pitch / 2, 0})
	testing.expect_value(t, m.hit, -1)
	// A press that stays within the slop is.
	press_at(&p, c)
	move_to(&p, c + {CAROUSEL_SLOP / 2, 0})
	release_at(&p, c + {CAROUSEL_SLOP / 2, 0})
	testing.expect(t, m.hit >= 0)
}

@(private = "file")
Guard_Model :: struct {
	open: bool,
}

@(private = "file")
guard_ui :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Guard_Model)(user)
	if card(gtx, .Filled, key = 1) {
		button(gtx, "In card")
	}
	if bottom_sheet(gtx, &m.open, {400, 600}, key = 2) {
		button(gtx, "Inside")
	}
	button(gtx, "After") // laid out on the page, not in the card or the sheet
}

@(test)
test_container_guards_close_themselves_and_gate_on_visibility :: proc(t: ^testing.T) {
	m: Guard_Model
	p: ui.Probe
	ui.probe_init(&p, guard_ui, &m, {400, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	_, in_card := ui.probe_find(&p, "In card")
	testing.expect(t, in_card)
	_, inside := ui.probe_find(&p, "Inside")
	testing.expect(t, !inside) // a closed sheet lays out no content
	_, after := ui.probe_find(&p, "After")
	testing.expect(t, after)
	m.open = true
	ui.probe_frame(&p)
	ui.probe_frame(&p)
	_, inside = ui.probe_find(&p, "Inside")
	testing.expect(t, inside) // an open one does
}
