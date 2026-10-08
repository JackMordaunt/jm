package ui

import "core:testing"
import "jm:ui/ops"

@(private = "file")
Fields :: struct {
	caret_x:   f32,
	read_only: bool,
	composed:  [dynamic]string, // the Compose texts field 1 heard
}

// fields_view lays out two text areas side by side at a density of 2: area 1
// tells its caret, area 2 does not.
@(private = "file")
fields_view :: proc(gtx: ^Ctx, user: rawptr) {
	m := (^Fields)(user)
	ops.transform_push(gtx.scene, ops.scale(2, 2))
	defer ops.transform_pop(gtx.scene)
	kinds := ops.Event_Kinds{.Press, .Key, .Text, .Focus, .Blur}
	for e in events(gtx, 1) {
		if e.kind == .Compose {
			append(&m.composed, e.text)
		}
	}
	ops.input_area(gtx.scene, 1, ops.Rect{10, 10, 100, 20}, kinds)
	text_caret(gtx, 1, ops.Rect{10, 10, 100, 20}, 10 + m.caret_x, read_only = m.read_only)
	ops.input_area(gtx.scene, 2, ops.Rect{200, 10, 100, 20}, kinds)
	ops.input_area(gtx.scene, 3, ops.Rect{0, 100, 50, 50}, {.Press})
}

@(test)
test_the_focused_text_area_turns_the_input_method_on_at_its_caret :: proc(t: ^testing.T) {
	m: Fields
	defer delete(m.composed)
	p: Probe
	probe_init(&p, fields_view, &m, {800, 400}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, !p.text_input.active)
	testing.expect_value(t, p.text_inputs, 0)

	probe_click_at(&p, {40, 40})
	testing.expect(t, p.text_input.active)
	testing.expect_value(t, p.text_input.area, ops.Area_Id(1))
	testing.expect_value(t, p.text_input.rect, ops.Rect{20, 20, 200, 40})
	testing.expect_value(t, p.text_input.caret, f32(0))
	testing.expect_value(t, p.text_input.kind, Text_Input_Kind.Text)

	// An unchanged frame asks nothing more; a moved caret asks again.
	n := p.text_inputs
	probe_frame(&p)
	testing.expect_value(t, p.text_inputs, n)
	m.caret_x = 15
	probe_frame(&p)
	testing.expect_value(t, p.text_inputs, n + 1)
	testing.expect_value(t, p.text_input.caret, f32(30))

	// A preedit goes to the focused text area.
	probe_compose(&p, "かな")
	testing.expect_value(t, len(m.composed), 1)
	testing.expect_value(t, m.composed[0], "かな")

	// An area that tells no caret gets its bounds, the caret at its left.
	probe_click_at(&p, {440, 40})
	testing.expect(t, p.text_input.active)
	testing.expect_value(t, p.text_input.area, ops.Area_Id(2))
	testing.expect_value(t, p.text_input.rect, ops.Rect{400, 20, 200, 40})

	// A press on an area that takes no keys leaves focus, and the input
	// method, where they are; a press on nothing clears both.
	probe_click_at(&p, {20, 220})
	testing.expect(t, p.text_input.active)
	probe_click_at(&p, {700, 300})
	testing.expect(t, !p.text_input.active)
	probe_compose(&p, "x")
	testing.expect_value(t, len(m.composed), 1)
}

@(test)
test_a_read_only_text_area_keeps_the_input_method_off :: proc(t: ^testing.T) {
	m := Fields{read_only = true}
	defer delete(m.composed)
	p: Probe
	probe_init(&p, fields_view, &m, {800, 400}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)

	probe_click_at(&p, {40, 40})
	testing.expect(t, !p.text_input.active)
	testing.expect_value(t, p.text_inputs, 0)
}
