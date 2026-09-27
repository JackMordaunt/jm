package ui

import "core:fmt"
import "core:slice"
import "core:testing"
import "jm:ui/testutil"

@(private)
find_tag :: proc(o: ^Ops, name: string) -> (Area_Id, bool) {
	for op in o.ops {
		if g, ok := op.(Tag); ok && g.name == name {
			return g.id, true
		}
	}
	return 0, false
}

@(private)
tag_names :: proc(o: ^Ops) -> [dynamic]string {
	out := make([dynamic]string, context.temp_allocator)
	for op in o.ops {
		if g, ok := op.(Tag); ok {
			append(&out, g.name)
		}
	}
	return out
}

@(private)
push_event :: proc(h: ^Harness, e: Event) {
	append(&h.router.events, e)
}

@(test)
test_label_records_run_at_baseline :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	d := label(&h.gtx, "Hi", {color = h.theme.success})
	testing.expect(t, near(d.size.x, 2 * W) && near(d.size.y, 14))
	testing.expect(t, near(d.baseline, 0.8 * 14))
	g := h.ops.ops[0].(Glyphs)
	testing.expect(t, near(g.origin.y, 0.8 * 14))
	testing.expect_value(t, g.color, h.theme.success)
	testing.expect_value(t, len(h.ops.runs[g.run].glyphs), 2)
	_, ok := find_tag(&h.ops, "Hi")
	testing.expect(t, ok)
}

@(test)
test_label_clamps_to_constraints :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {20, 10})
	defer harness_destroy(&h)
	d := label(&h.gtx, "a long line")
	testing.expect_value(t, d.size, Size{20, 10})
}

@(private)
save_ui :: proc(gtx: ^Ctx) -> bool {
	col := column(gtx, gap = 8); defer end(&col)
	label(gtx, "Name")
	return button(gtx, "Save")
}

@(test)
test_button_clicks_on_press_then_release :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	testing.expect(t, !save_ui(&h.gtx))
	area, ok := find_tag(&h.ops, "Save")
	testing.expect(t, ok)
	i := index_of(&h.ops, Input_Area)
	testing.expect(t, i >= 0)
	ia := h.ops.ops[i].(Input_Area)
	testing.expect_value(t, ia.id, area)
	testing.expect_value(t, ia.kinds, Event_Kinds{.Press, .Release, .Enter, .Leave, .Move})
	rr := ia.shape.(Round_Rect)
	testing.expect(t, near(rr.rect.w, 4 * W + 24) && near(rr.rect.h, 14 + 12))

	harness_frame(&h)
	push_event(&h, {kind = .Press, area = area, pos = {5, 5}})
	push_event(&h, {kind = .Release, area = area, pos = {5, 5}})
	testing.expect(t, save_ui(&h.gtx))
	again, _ := find_tag(&h.ops, "Save")
	testing.expect_value(t, again, area)

	clear(&h.router.events)
	harness_frame(&h)
	testing.expect(t, !save_ui(&h.gtx))
}

@(test)
test_button_hover_and_release_outside :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	go_button(&h)
	area, _ := find_tag(&h.ops, "Go")

	harness_frame(&h)
	push_event(&h, {kind = .Enter, area = area})
	push_event(&h, {kind = .Press, area = area, pos = {1, 1}})
	push_event(&h, {kind = .Release, area = area, pos = {-5, 1}})
	testing.expect(t, !go_button(&h))
	f := h.ops.ops[index_of(&h.ops, Fill)].(Fill)
	st := resolve_button(&h.theme, {})
	testing.expect_value(t, f.paint.(Color), st.hover)
}

@(test)
test_checkbox_toggles :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	on := false
	agree(&h, &on)
	area, ok := find_tag(&h.ops, "Agree")
	testing.expect(t, ok)
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Stroke), 1) // unchecked outline

	harness_frame(&h)
	push_event(&h, {kind = .Press, area = area, pos = {1, 1}})
	push_event(&h, {kind = .Release, area = area, pos = {1, 1}})
	testing.expect(t, agree(&h, &on))
	testing.expect(t, on)
	// Checked: accent fill and a stroked three-point path.
	s := h.ops.ops[index_of(&h.ops, Stroke)].(Stroke)
	ref := s.shape.(Path_Ref)
	testing.expect_value(t, len(h.ops.paths[ref.id].points), 3)
}

@(test)
test_slider_follows_press_and_drag :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	v: f32 = 0
	volume(&h, &v)
	area, ok := find_tag(&h.ops, "volume")
	testing.expect(t, ok)

	// Usable track is 118 - 18 = 100 wide, starting at x = 9.
	harness_frame(&h)
	push_event(&h, {kind = .Press, area = area, pos = {59, 9}})
	testing.expect(t, volume(&h, &v))
	testing.expect(t, near(v, 5))

	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Move, area = area, pos = {500, 9}})
	testing.expect(t, volume(&h, &v))
	testing.expect_value(t, v, 10)

	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Release, area = area, pos = {500, 9}})
	push_event(&h, {kind = .Move, area = area, pos = {9, 9}})
	testing.expect(t, !volume(&h, &v))
	testing.expect_value(t, v, 10)
}

@(test)
test_text_field_edits_at_cursor :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	s: Text_State
	defer text_destroy(&s)
	text_set(&s, "ac")
	s.cursor = 1
	name_field(&h, &s)
	area, ok := find_tag(&h.ops, "name")
	testing.expect(t, ok)

	harness_frame(&h)
	push_event(&h, {kind = .Focus, area = area})
	push_event(&h, {kind = .Text, area = area, text = "bé"})
	testing.expect(t, name_field(&h, &s))
	testing.expect_value(t, text_string(&s), "abéc")
	testing.expect_value(t, s.cursor, 4)
	// Focused: a 1px caret after "abé" (three runes), inside a clip.
	caret := false
	for op in h.ops.ops {
		if f, is_fill := op.(Fill); is_fill {
			if r, is_rect := f.shape.(Rect); is_rect && r.w == 1 {
				caret = near(r.x, 8 + 3 * W)
			}
		}
	}
	testing.expect(t, caret)
	testing.expect(t, index_of(&h.ops, Push_Clip) < index_of(&h.ops, Glyphs))

	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Key, area = area, key = .Backspace})
	push_event(&h, {kind = .Key, area = area, key = .Left})
	push_event(&h, {kind = .Key, area = area, key = .Delete})
	testing.expect(t, name_field(&h, &s))
	testing.expect_value(t, text_string(&s), "ac")
	testing.expect_value(t, s.cursor, 1)

	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Key, area = area, key = .End})
	push_event(&h, {kind = .Key, area = area, key = .Home})
	push_event(&h, {kind = .Key, area = area, key = .Right})
	push_event(&h, {kind = .Blur, area = area})
	testing.expect(t, !name_field(&h, &s))
	testing.expect_value(t, s.cursor, 1)

	// A press puts the cursor at the nearest rune boundary.
	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Press, area = area, pos = {8 + 1.9 * W, 5}})
	name_field(&h, &s)
	testing.expect_value(t, s.cursor, 2)
}

@(private)
List_Model :: struct {
	laid: [dynamic]int,
}

@(private)
list_item :: proc(gtx: ^Ctx, i: int, user: rawptr) {
	m := (^List_Model)(user)
	append(&m.laid, i)
	label(gtx, fmt.tprintf("item %d", i))
}

@(test)
test_list_lays_out_only_visible_rows :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 50})
	defer harness_destroy(&h)
	m: List_Model
	m.laid = make([dynamic]int, context.temp_allocator)
	s: List_State
	d := item_list(&h, &s, &m)
	testing.expect_value(t, d.size, Size{200, 50})
	// Row height 14: rows 0..3 intersect a 50px viewport.
	testing.expect_value(t, len(m.laid), 4)
	names := tag_names(&h.ops)
	testing.expect_value(t, len(names), 4)
	testing.expect_value(t, names[3], "item 3")
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Call), 1) // item 0 from its measuring macro
	ia := h.ops.ops[index_of(&h.ops, Input_Area)].(Input_Area)
	testing.expect_value(t, ia.kinds, Event_Kinds{.Scroll})
	// Items have distinct ids though they share a call site.
	a, _ := find_tag(&h.ops, "item 1")
	b, _ := find_tag(&h.ops, "item 2")
	testing.expect(t, a != b)

	harness_frame(&h)
	clear(&m.laid)
	push_event(&h, {kind = .Scroll, area = ia.id, scroll = {0, 700}})
	item_list(&h, &s, &m)
	testing.expect_value(t, s.offset, 700)
	// Item 0 is always measured; then rows 50..53.
	testing.expect(t, slice.equal(m.laid[:], []int{0, 50, 51, 52, 53}))
	testing.expect_value(t, testutil.count_ops(h.ops.ops[:], Call), 0)
	p := pushes(&h.ops)
	testing.expect_value(t, p[0], Point{0, 0})

	clear(&h.router.events)
	harness_frame(&h)
	push_event(&h, {kind = .Scroll, area = ia.id, scroll = {0, 1e6}})
	item_list(&h, &s, &m)
	testing.expect_value(t, s.offset, 100 * 14 - 50)
}

@(test)
test_divider_in_row_is_vertical :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 40})
	defer harness_destroy(&h)
	gtx := &h.gtx
	r := row(gtx)
	d := divider(gtx)
	end(&r)
	testing.expect_value(t, d.size, Size{1, 40})
	f := h.ops.ops[index_of(&h.ops, Fill)].(Fill)
	testing.expect_value(t, f.paint.(Color), h.theme.outline)
}

// The authoring density the package is for: no per-child boilerplate.
@(private)
Model :: struct {
	name:  Text_State,
	saved: bool,
}

@(private)
model_ui :: proc(gtx: ^Ctx, m: ^Model) {
	col := column(gtx, gap = 8); defer end(&col)
	label(gtx, "Name")
	text_field(gtx, &m.name)
	if button(gtx, "Save") {
		m.saved = true
	}
	if m.saved {
		label(gtx, "Saved", {color = gtx.theme.success})
	}
}

@(test)
test_sample_ui :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	m: Model
	defer text_destroy(&m.name)
	model_ui(&h.gtx, &m)
	save, _ := find_tag(&h.ops, "Save")
	p := pushes(&h.ops)
	testing.expect_value(t, len(p), 3)
	testing.expect_value(t, p[2].y, 14 + 8 + (14 + 8) + 8)

	harness_frame(&h)
	push_event(&h, {kind = .Press, area = save, pos = {2, 2}})
	push_event(&h, {kind = .Release, area = save, pos = {2, 2}})
	model_ui(&h.gtx, &m)
	testing.expect(t, m.saved)
	clear(&h.router.events)
	harness_frame(&h)
	model_ui(&h.gtx, &m)
	_, shown := find_tag(&h.ops, "Saved")
	testing.expect(t, shown)
}

// One call site per widget, so its id is the same every frame, as it is in
// a real ui proc.

@(private)
go_button :: proc(h: ^Harness) -> bool {
	return button(&h.gtx, "Go")
}

@(private)
agree :: proc(h: ^Harness, on: ^bool) -> bool {
	return checkbox(&h.gtx, "Agree", on)
}

@(private)
volume :: proc(h: ^Harness, v: ^f32) -> bool {
	return slider(&h.gtx, v, 0, 10, "volume", {width = 118, knob_size = 18})
}

@(private)
name_field :: proc(h: ^Harness, s: ^Text_State) -> bool {
	return text_field(&h.gtx, s, "name")
}

@(private)
item_list :: proc(h: ^Harness, s: ^List_State, m: ^List_Model) -> Dims {
	return list(&h.gtx, s, 100, list_item, m)
}
