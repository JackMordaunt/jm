package ui

import "core:fmt"
import "jm:ui/ops"
import "core:slice"
import "core:testing"
import "jm:ui/testutil"

@(private)
find_tag :: proc(o: ^ops.Scene, name: string) -> (ops.Area_Id, bool) {
	for op in o.ops {
		if g, ok := op.(ops.Tag); ok && g.name == name {
			return g.id, true
		}
	}
	return 0, false
}

@(private)
tag_names :: proc(o: ^ops.Scene) -> [dynamic]string {
	out := make([dynamic]string, context.temp_allocator)
	for op in o.ops {
		if g, ok := op.(ops.Tag); ok {
			append(&out, g.name)
		}
	}
	return out
}

@(private)
event_push :: proc(h: ^Harness, e: Event) {
	append(&h.router.events, e)
}

@(test)
test_label_records_run_at_baseline :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h)
	defer harness_destroy(&h)
	d := label(&h.gtx, "Hi", {9, 8, 7, 255})
	testing.expect(t, testutil.near(d.size.x, 2 * W) && testutil.near(d.size.y, 14))
	testing.expect(t, testutil.near(d.baseline, 0.8 * 14))
	g := h.scene.ops[0].(ops.Glyphs)
	testing.expect(t, testutil.near(g.origin.y, 0.8 * 14))
	testing.expect_value(t, g.color, ops.Color{9, 8, 7, 255})
	testing.expect_value(t, len(h.scene.runs[g.run].glyphs), 2)
	_, ok := find_tag(&h.scene, "Hi")
	testing.expect(t, ok)
}

@(test)
test_label_clamps_to_constraints :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {20, 10})
	defer harness_destroy(&h)
	d := label(&h.gtx, "a long line")
	testing.expect_value(t, d.size, ops.Size{20, 10})
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
	testing.expect_value(t, d.size, ops.Size{200, 50})
	// Row height 14: rows 0..3 intersect a 50px viewport.
	testing.expect_value(t, len(m.laid), 4)
	names := tag_names(&h.scene)
	testing.expect_value(t, len(names), 4)
	testing.expect_value(t, names[3], "item 3")
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Call), 1) // item 0 from its measuring macro
	ia := h.scene.ops[index_of(&h.scene, ops.Input_Area)].(ops.Input_Area)
	testing.expect_value(t, ia.kinds, ops.Event_Kinds{.Scroll})
	// Items have distinct ids though they share a call site.
	a, _ := find_tag(&h.scene, "item 1")
	b, _ := find_tag(&h.scene, "item 2")
	testing.expect(t, a != b)

	harness_frame(&h)
	clear(&m.laid)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, 700 / SCROLL_STEP}}) // wheel units, SCROLL_STEP px each
	item_list(&h, &s, &m)
	testing.expect_value(t, s.offset, 700)
	// Item 0 is always measured; then rows 50..53.
	testing.expect(t, slice.equal(m.laid[:], []int{0, 50, 51, 52, 53}))
	testing.expect_value(t, testutil.count_ops(h.scene.ops[:], ops.Call), 0)
	p := pushes(&h.scene)
	testing.expect_value(t, p[0], ops.Point{0, 0})

	clear(&h.router.events)
	harness_frame(&h)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, 1e6}})
	item_list(&h, &s, &m)
	testing.expect_value(t, s.offset, 100 * 14 - 50)
}

// The authoring density the package is for: no per-child boilerplate.

@(private)
item_list :: proc(h: ^Harness, s: ^List_State, m: ^List_Model) -> Dims {
	return list(&h.gtx, s, 100, list_item, m)
}

@(private = "file")
List_Drag_Model :: struct {
	state: List_State,
}

@(private = "file")
list_row :: proc(gtx: ^Ctx, i: int, user: rawptr) {
	r := widget_open(gtx, 1)
	if i == 0 {
		ops.tag(gtx.scene, r.id, "row 0", {0, 0, 200, 20})
	}
	widget_close(gtx, &r, {size = {200, 20}})
}

@(private = "file")
list_drag_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^List_Drag_Model)(user)
	list(gtx, &m.state, 50, list_row, drag_scroll = true)
}

@(test)
drag_scroll_moves_and_slings_a_list :: proc(t: ^testing.T) {
	m: List_Drag_Model
	p: Probe
	probe_init(&p, list_drag_view, &m, {200, 100})
	defer probe_destroy(&p)
	testing.expect(t, probe_drag(&p, "row 0", 0, -80, steps = 4)) // 1200 px/s
	testing.expect_value(t, m.state.offset, 80)
	for _ in 0 ..< 600 {
		probe_frame(&p)
	}
	want := 80 + 1200 / -SLING_DECAY
	testing.expectf(t, abs(m.state.offset - want) < 2, "glided to %v, want %v", m.state.offset, want)
}


// Items of two heights: a heading of 10 over each three rows of 30.
@(private = "file")
Mixed_Model :: struct {
	laid: [dynamic]int,
}

@(private = "file")
mixed_height :: proc(i: int, user: rawptr) -> f32 {
	return 10 if i % 4 == 0 else 30
}

@(private = "file")
mixed_item :: proc(gtx: ^Ctx, i: int, user: rawptr) {
	m := (^Mixed_Model)(user)
	append(&m.laid, i)
	r := widget_open(gtx, 1)
	h := mixed_height(i, nil)
	ops.tag(gtx.scene, r.id, fmt.tprintf("mixed %d", i), {0, 0, 200, h})
	widget_close(gtx, &r, {size = {200, h}})
}

@(private = "file")
mixed_list :: proc(h: ^Harness, s: ^List_State, m: ^Mixed_Model, count := 100) -> Dims {
	return list(&h.gtx, s, count, mixed_item, m, height_of = mixed_height)
}

@(test)
test_list_mixed_heights_lay_out_at_the_right_y :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)

	m: Mixed_Model
	m.laid = make([dynamic]int, context.temp_allocator)
	s: List_State
	d := mixed_list(&h, &s, &m)
	testing.expect_value(t, d.size, ops.Size{200, 100})
	// Tops 0, 10, 40, 70, 100: items 0..3 intersect 100px, item 4 starts at its foot.
	testing.expect(t, slice.equal(m.laid[:], []int{0, 1, 2, 3}))
	p := pushes(&h.scene)
	testing.expect_value(t, len(p), 4)
	testing.expect_value(t, p[0], ops.Point{0, 0})
	testing.expect_value(t, p[1], ops.Point{0, 10})
	testing.expect_value(t, p[2], ops.Point{0, 40})
	testing.expect_value(t, p[3], ops.Point{0, 70})
}

@(test)
test_list_mixed_heights_build_only_what_is_visible :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)

	m: Mixed_Model
	m.laid = make([dynamic]int, context.temp_allocator)
	s := List_State{offset = 125} // inside item 5, which spans 110..140
	mixed_list(&h, &s, &m)
	// Item 4 ends at 110, so 5 (110..140) is the first; 9 starts at 210, 10 at 240, past the foot at 225.
	testing.expect(t, slice.equal(m.laid[:], []int{5, 6, 7, 8, 9}), fmt.tprint(m.laid[:]))
	p := pushes(&h.scene)
	testing.expect_value(t, p[0], ops.Point{0, -15})
	testing.expect_value(t, p[1], ops.Point{0, 15})
	testing.expect_value(t, p[4], ops.Point{0, 85})
}

@(test)
test_list_mixed_heights_scroll_to_the_last_row_whole :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 100})
	defer harness_destroy(&h)

	m: Mixed_Model
	m.laid = make([dynamic]int, context.temp_allocator)
	s: List_State
	mixed_list(&h, &s, &m)
	ia := h.scene.ops[index_of(&h.scene, ops.Input_Area)].(ops.Input_Area)
	harness_frame(&h)
	clear(&m.laid)
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, 1e6}})
	mixed_list(&h, &s, &m)
	// 25 headings of 10 and 75 rows of 30: 2500 px.
	testing.expect_value(t, s.offset, 2500 - 100)
	testing.expect_value(t, m.laid[len(m.laid) - 1], 99)
	p := pushes(&h.scene)
	testing.expect_value(t, p[len(p) - 1], ops.Point{0, 70}) // the last row, 30px, ends at 100
}
