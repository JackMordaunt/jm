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
	d := label(&h.gtx, "Hi", {color = h.theme.success})
	testing.expect(t, near(d.size.x, 2 * W) && near(d.size.y, 14))
	testing.expect(t, near(d.baseline, 0.8 * 14))
	g := h.scene.ops[0].(ops.Glyphs)
	testing.expect(t, near(g.origin.y, 0.8 * 14))
	testing.expect_value(t, g.color, h.theme.success)
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
	event_push(&h, {kind = .Scroll, area = ia.id, scroll = {0, 700}})
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

@(test)
test_divider_in_row_is_vertical :: proc(t: ^testing.T) {
	h: Harness
	harness_init(&h, {200, 40})
	defer harness_destroy(&h)
	gtx := &h.gtx
	r := row_open(gtx)
	d := divider(gtx)
	close(&r)
	testing.expect_value(t, d.size, ops.Size{1, 40})
	f := h.scene.ops[index_of(&h.scene, ops.Fill)].(ops.Fill)
	testing.expect_value(t, f.paint.(ops.Color), h.theme.outline)
}

// The authoring density the package is for: no per-child boilerplate.

@(private)
item_list :: proc(h: ^Harness, s: ^List_State, m: ^List_Model) -> Dims {
	return list(&h.gtx, s, 100, list_item, m)
}
