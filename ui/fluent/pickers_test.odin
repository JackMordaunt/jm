package fluent

import "core:math"
import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/fluent/tokens"

// Behaviour of the pickers, driven through ui.Probe by their tags.

@(private = "file")
FRUIT := [?]string{"Apple", "Banana", "Cherry", "Date"}

@(private = "file")
PEOPLE := [?]string{"Ann", "Bob", "Cy"}

@(private = "file")
SWATCHES := [?]Swatch{{color = {255, 0, 0, 255}, name = "red"}, {color = {0, 128, 0, 255}, name = "green"}, {color = {0, 0, 255, 255}, name = "blue"}, {empty = true, name = "none"}}

@(private = "file")
Pickers_Model :: struct {
	fruit:    ui.Text_State,
	pick:     int,
	count:    f32,
	query:    ui.Text_State,
	people:   ui.Text_State,
	chosen:   [3]bool,
	swatch:   int,
	hsv:      Hsv,
	stars:    f32,
	halves:   f32,
	shown:    f32,
}

@(private = "file")
pickers :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Pickers_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	combobox(gtx, &m.fruit, FRUIT[:], &m.pick, "Fruit", width = 260)
	spin_button(gtx, &m.count, lo = 0, hi = 6, name = "Count", width = 160)
	search_box(gtx, &m.query, width = 260)
	tag_picker(gtx, &m.people, PEOPLE[:], m.chosen[:], "People", width = 300)
	swatch_picker(gtx, SWATCHES[:], &m.swatch)
	color_slider(gtx, &m.hsv, .Hue, 380)
	rating(gtx, &m.stars, hover = &m.shown)
	rating(gtx, &m.halves, half_steps = true, name = "half")
}

// drag presses at a, moves to b and releases there, a frame each; a
// click is drag(p, a, a).
@(private = "file")
drag :: proc(p: ^ui.Probe, a, b: ops.Point) {
	ui.router_push(&p.router, {kind = .Move, pos = a})
	ui.router_push(&p.router, {kind = .Press, pos = a, button = .Left})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Move, pos = b})
	ui.probe_frame(p)
	ui.router_push(&p.router, {kind = .Release, pos = b, button = .Left})
	ui.probe_frame(p)
}

@(private = "file")
present :: proc(p: ^ui.Probe, name: string) -> bool {
	_, ok := ui.probe_find(p, name)
	return ok
}

@(private = "file")
model_destroy :: proc(m: ^Pickers_Model) {
	ui.text_destroy(&m.fruit)
	ui.text_destroy(&m.query)
	ui.text_destroy(&m.people)
}

@(private = "file")
open_probe :: proc(p: ^ui.Probe, m: ^Pickers_Model) {
	ui.probe_init(p, pickers, m, {600, 1000}, allocator = context.temp_allocator)
}

@(test)
test_combobox_picks_by_click_and_by_keys :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	testing.expect(t, !present(&p, "Banana"))
	testing.expect(t, ui.probe_click(&p, "Fruit"))
	testing.expect(t, present(&p, "Banana")) // the listbox is open
	testing.expect(t, ui.probe_click(&p, "Banana"))
	ui.probe_frame(&p) // the frame after the click draws it closed
	testing.expect_value(t, m.pick, 1)
	testing.expect_value(t, ui.text_string(&m.fruit), "Banana")
	testing.expect(t, !present(&p, "Cherry")) // a pick closes it

	// The chevron toggles it; then Down moves the active option from the
	// selection and Enter picks it.
	f := ui.probe_bounds(&p, "Fruit")
	chevron := ops.Point{f.x + f.w - 16, f.y + f.h / 2}
	drag(&p, chevron, chevron)
	testing.expect(t, present(&p, "Cherry"))
	ui.probe_key(&p, .Down)
	ui.probe_key(&p, .Enter)
	ui.probe_frame(&p)
	testing.expect_value(t, m.pick, 2)
	testing.expect(t, !present(&p, "Cherry"))
	// Escape closes without picking.
	drag(&p, chevron, chevron)
	testing.expect(t, present(&p, "Apple"))
	ui.probe_key(&p, .Escape)
	ui.probe_frame(&p)
	testing.expect(t, !present(&p, "Apple"))
	testing.expect_value(t, m.pick, 2)
}

@(private = "file")
MANY := [?]string{"o0", "o1", "o2", "o3", "o4", "o5", "o6", "o7", "o8", "o9", "o10", "o11"}

@(private = "file")
Long_Model :: struct {
	text: ui.Text_State,
	pick: int,
}

@(private = "file")
long_combobox_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Long_Model)(user)
	combobox(gtx, &m.text, MANY[:], &m.pick, "Long", width = 260)
}

@(test)
test_listbox_scrolls_whole_rows_from_small_scrolls :: proc(t: ^testing.T) {
	m := Long_Model{pick = -1}
	p: ui.Probe
	ui.probe_init(&p, long_combobox_view, &m, {600, 1000}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer delete(m.text.buf)

	testing.expect(t, ui.probe_click(&p, "Long"))
	testing.expect(t, present(&p, "o0") && !present(&p, "o8"))
	// Ten trackpad-sized scrolls add up to two and a half rows: two rows.
	row_h := 2 * tok.SPACING_VERTICAL_SNUDGE + tok.LINE_HEIGHT_BASE300
	for _ in 0 ..< 10 {
		testing.expect(t, ui.probe_scroll(&p, "o4", row_h / 4 / ui.SCROLL_STEP))
	}
	testing.expect(t, !present(&p, "o1") && present(&p, "o2"))
	testing.expect(t, present(&p, "o9") && !present(&p, "o10"))
}

@(test)
test_combobox_filters_by_the_typed_text :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	testing.expect(t, ui.probe_click(&p, "Fruit"))
	ui.probe_key(&p, .Escape)
	ui.probe_type(&p, "err")
	testing.expect(t, present(&p, "Cherry"))
	testing.expect(t, !present(&p, "Apple"))
}

@(test)
test_spin_button_steps_and_clamps :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1, count = 5}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	testing.expect(t, ui.probe_click(&p, "increment"))
	testing.expect_value(t, m.count, 6)
	testing.expect(t, ui.probe_click(&p, "increment"))
	testing.expect_value(t, m.count, 6) // clamped at hi
	testing.expect(t, ui.probe_click(&p, "decrement"))
	testing.expect_value(t, m.count, 5)
	testing.expect(t, ui.probe_click(&p, "Count"))
	ui.probe_key(&p, .Up)
	testing.expect_value(t, m.count, 6)
	ui.probe_key(&p, .Home)
	testing.expect_value(t, m.count, 0)
	ui.probe_key(&p, .Down)
	testing.expect_value(t, m.count, 0) // clamped at lo
	// Typed text commits on Enter, clamped.
	ui.probe_type(&p, "9")
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.count, 6)
}

@(test)
test_search_box_clears_by_escape_and_dismiss :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	testing.expect(t, !present(&p, "dismiss"))
	testing.expect(t, ui.probe_click(&p, "Search"))
	ui.probe_type(&p, "abc")
	testing.expect_value(t, ui.text_string(&m.query), "abc")
	ui.probe_key(&p, .Escape)
	testing.expect_value(t, ui.text_string(&m.query), "")
	ui.probe_type(&p, "xy")
	testing.expect(t, present(&p, "dismiss")) // focused with text
	testing.expect(t, ui.probe_click(&p, "dismiss"))
	testing.expect_value(t, ui.text_string(&m.query), "")
}

@(test)
test_tag_picker_adds_from_the_list_and_removes :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1, chosen = {false, false, true}}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	// A tag's click dismisses it.
	testing.expect(t, ui.probe_click(&p, "Cy"))
	testing.expect(t, !m.chosen[2])
	// The list offers the unpicked options; a pick adds a tag and keeps it open.
	testing.expect(t, ui.probe_click(&p, "People"))
	testing.expect(t, ui.probe_click(&p, "Bob"))
	testing.expect(t, m.chosen[1])
	testing.expect(t, present(&p, "Ann"))
	// Close it, refocus, and Backspace in the empty text removes the last tag.
	testing.expect(t, ui.probe_click(&p, "People")) // the press outside the list closes it
	testing.expect(t, ui.probe_click(&p, "People"))
	ui.probe_key(&p, .Escape)
	ui.probe_key(&p, .Backspace)
	testing.expect(t, !m.chosen[1])
}

@(test)
test_swatch_selects_by_click_and_enter_and_roves_by_arrows :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	testing.expect(t, ui.probe_click(&p, "green"))
	testing.expect_value(t, m.swatch, 1)
	ui.probe_key(&p, .Right) // moves focus, not the selection (swatch-picker.json)
	testing.expect_value(t, ui.probe_focus_name(&p), "blue")
	testing.expect_value(t, m.swatch, 1)
	ui.probe_key(&p, .End)
	ui.probe_key(&p, .Right) // wraps
	testing.expect_value(t, ui.probe_focus_name(&p), "red")
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.swatch, 0)
	testing.expect_value(t, ui.probe_bounds(&p, "red").w, 28) // medium swatches
}

@(test)
test_color_slider_drag_sets_hue_and_hsv_round_trips :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1, hsv = {0, 1, 1, 1}}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	r := ui.probe_bounds(&p, "hue")
	testing.expect_value(t, r.w, 380)
	testing.expect_value(t, r.h, 32)
	start := ops.Point{r.x + 10, r.y + r.h / 2}
	mid := ops.Point{r.x + r.w / 2, r.y + r.h / 2} // half the run past the thumb's half
	drag(&p, start, mid)
	testing.expect_value(t, m.hsv.h, 180)

	for c in ([]Hsv{{210, 0.5, 0.8, 1}, {0, 1, 1, 1}, {120, 0.25, 0.4, 0.5}}) {
		back := rgb_to_hsv(hsv_to_rgb(c))
		testing.expectf(t, abs(back.h - c.h) < 1.5 && abs(back.s - c.s) < 0.01 && abs(back.v - c.v) < 0.01 && abs(back.a - c.a) < 0.01, "%v came back %v", c, back)
	}
	testing.expect_value(t, hsv_to_rgb({0, 1, 1, 1}), ops.Color{255, 0, 0, 255})
	testing.expect_value(t, rgb_to_hsv({128, 128, 128, 255}).s, 0)
}

@(test)
test_rating_click_sets_and_hover_previews :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1}
	p: ui.Probe
	open_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	testing.expect(t, ui.probe_click(&p, "rating 3"))
	testing.expect_value(t, m.stars, 3)
	five := ui.probe_bounds(&p, "rating 5")
	testing.expect_value(t, five.w, 28) // extra-large stars
	ui.probe_move(&p, five.x + five.w / 2, five.y + five.h / 2)
	ui.probe_frame(&p)
	testing.expect_value(t, m.shown, 5)
	testing.expect_value(t, m.stars, 3) // a preview, not a change
	ui.probe_move(&p, 590, 990) // off the stars
	ui.probe_frame(&p)
	testing.expect_value(t, m.shown, 3)

	// Half steps: the left half of the second star is 1.5.
	two := ui.probe_bounds(&p, "half 2")
	drag(&p, {two.x + 2, two.y + two.h / 2}, {two.x + 2, two.y + two.h / 2})
	testing.expect_value(t, m.halves, 1.5)
	testing.expect(t, math.abs(m.halves - 1.5) < 1e-6)
}

// BOTTOM_WINDOW is a short window whose last 40px holds a combobox.
@(private = "file")
BOTTOM_WINDOW :: ops.Size{600, 400}

@(private = "file")
bottom_combobox :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Pickers_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	ui.spacer(gtx, BOTTOM_WINDOW.y - 40)
	combobox(gtx, &m.fruit, FRUIT[:], &m.pick, "Fruit", width = 260)
}

@(test)
test_combobox_near_the_bottom_lists_above_itself :: proc(t: ^testing.T) {
	m := Pickers_Model{pick = -1, swatch = -1}
	p: ui.Probe
	ui.probe_init(&p, bottom_combobox, &m, BOTTOM_WINDOW, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	defer model_destroy(&m)

	testing.expect(t, ui.probe_click(&p, "Fruit"))
	ui.probe_frame(&p)
	field := ui.probe_bounds(&p, "Fruit")
	for name in FRUIT {
		r := ui.probe_bounds(&p, name)
		testing.expectf(t, r.h > 0 && r.y >= 0 && r.y + r.h <= BOTTOM_WINDOW.y, "%s at %v leaves the window", name, r)
		testing.expectf(t, r.y + r.h <= field.y, "%s at %v is not above the field at %v", name, r, field)
	}
	// A pick from the flipped list lands.
	testing.expect(t, ui.probe_click(&p, "Cherry"))
	ui.probe_frame(&p)
	testing.expect_value(t, m.pick, 2)
}

// A search box reports its area, as an input does, so a caller can move
// focus into it: the Finder's search, opened from a button.
@(test)
test_search_box_takes_focus_when_asked :: proc(t: ^testing.T) {
	Box :: struct {
		s:     ui.Text_State,
		ask:   bool,
		id:    ops.Area_Id,
		focus: bool,
	}
	b: Box
	defer ui.text_destroy(&b.s)
	p: ui.Probe
	ui.probe_init(&p, proc(gtx: ^ui.Ctx, user: rawptr) {
			b := (^Box)(user)
			e := search_box(gtx, &b.s, width = 200)
			b.id, b.focus = e.id, e.focused
			if b.ask {
				ui.focus_request(gtx, e.id)
			}
		}, &b, {400, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, b.id != 0, "the box reports its area")
	b.ask = true
	ui.probe_frame(&p)
	ui.probe_move(&p, 300, 150) // focus moves at the next route
	ui.probe_frame(&p)
	testing.expect(t, b.focus, "asked, it takes focus")
}
