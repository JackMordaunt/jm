package ui

import "core:strings"
import "jm:ui/ops"
import "core:testing"

// inspect_view is a 200x100 column of two labels, the second tagged.
@(private = "file")
inspect_view :: proc(gtx: ^Ctx, user: rawptr) {
	col := column_open(gtx, key = 1)
	defer close(&col)
	label(gtx, "first", key = 2)
	p := widget_open(gtx, 3)
	ops.input_area(gtx.scene, p.id, ops.Rect{0, 0, 60, 20}, {.Press})
	ops.tag(gtx.scene, p.id, "second")
	widget_close(gtx, &p, {size = {60, 20}})
}

@(test)
test_inspect_reports_the_widget_under_a_point :: proc(t: ^testing.T) {
	p: Probe
	probe_init(&p, inspect_view, nil, {200, 100}, debug = {.Inspect}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	f := probe_current(&p)
	testing.expect_value(t, len(f.boxes), 3) // two widgets and their column

	// Under the second: its own box, deepest, its hit and its tag.
	second := f.boxes[1].rect
	got := inspect_at(f, {second.x + 5, second.y + 5})
	testing.expect(t, got.has_box && got.box.depth == 1 && got.box.rect == second)
	testing.expect(t, got.has_hit && got.name == "second")
	// Its ancestry: the column that made it, then itself, by widget and tag.
	testing.expect_value(t, got.path, "column/inspect_view#second") // the view opens the second box itself, so it is the widget
	first := f.boxes[0].rect
	testing.expect_value(t, got.box.max, ops.Size{200, 100 - first.h}) // the column's width, and what the first child left of its height

	report := inspect_report(f, &p.layout, {second.x + 5, second.y + 5}, context.temp_allocator)
	testing.expect(t, strings.contains(report, "inspect_test.odin"))
	testing.expect(t, strings.contains(report, "path column/inspect_view#second"), report)
	testing.expect(t, strings.contains(report, "max  200x"))
	testing.expect(t, strings.contains(inspect_report(f, &p.layout, {250, 50}, context.temp_allocator), "nothing at 250,50"))

	layout := layout_report(f, context.temp_allocator)
	testing.expect_value(t, strings.count(layout, "\n"), 3)
	testing.expect(t, strings.contains(layout, "\"second\""))
}

@(test)
test_inspect_defers_one_root_panel_when_hovering :: proc(t: ^testing.T) {
	p: Probe
	probe_init(&p, inspect_view, nil, {200, 100}, debug = {.Inspect}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	probe_move(&p, 5, 5) // over the first label: the next frame paints its panel
	probe_frame(&p)
	deferred := 0
	for op in p.scene.ops {
		if d, ok := op.(ops.Defer); ok && d.root {
			deferred += 1
		}
	}
	testing.expect_value(t, deferred, 1)
}

@(test)
test_bounds_outlines_input_areas_too :: proc(t: ^testing.T) {
	p: Probe
	probe_init(&p, inspect_view, nil, {200, 100}, debug = {.Bounds}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	hits := 0
	for op in p.scene.ops {
		s, is_stroke := op.(ops.Stroke)
		if !is_stroke {
			continue
		}
		if c, ok := s.paint.(ops.Color); ok && c == ops.HIT_BOUNDS_COLOR {
			hits += 1
		}
	}
	testing.expect_value(t, hits, 1)
}

@(test)
test_inspect_prefers_an_overlay_over_the_page_beneath :: proc(t: ^testing.T) {
	view :: proc(gtx: ^Ctx, user: rawptr) {
		// A deep page widget, then a shallow one in an overlay over it: a
		// menu open above the page.
		outer := column_open(gtx, key = 1)
		inner := column_open(gtx, key = 2)
		p := widget_open(gtx, 3)
		widget_close(gtx, &p, {size = {100, 100}})
		close(&inner)
		close(&outer)
		o := overlay_open(gtx, {10, 10})
		m := widget_open(gtx, 4)
		widget_close(gtx, &m, {size = {50, 50}})
		close(&o)
	}
	p: Probe
	probe_init(&p, view, nil, {200, 200}, debug = {.Inspect}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	got := inspect_at(probe_current(&p), {20, 20})
	testing.expect(t, got.has_box)
	testing.expect_value(t, got.box.rect, ops.Rect{10, 10, 50, 50})
	testing.expect(t, got.box.layer > 0)
}

// Tally is a widget's own retained value: what widget_data keeps for it.
@(private = "file")
Tally :: struct {
	frames: int,
	last:   string,
}

// tally_view is one widget that counts its frames in a Tally.
@(private = "file")
tally_view :: proc(gtx: ^Ctx, user: rawptr) {
	p := widget_open(gtx, 7)
	t := widget_data(gtx, p.id, Tally)
	t.frames += 1
	t.last = "seen"
	widget_close(gtx, &p, {size = {40, 40}})
}

@(test)
test_inspect_prints_a_widgets_data_values :: proc(t: ^testing.T) {
	p: Probe
	probe_init(&p, tally_view, nil, {100, 100}, debug = {.Inspect}, allocator = context.temp_allocator)
	defer probe_destroy(&p)
	defer free_all(context.temp_allocator)
	probe_frame(&p)
	report := inspect_report(probe_current(&p), &p.layout, {10, 10}, context.temp_allocator)
	// The value as fmt prints it, after the widget's own flags, under
	// "state": a reader sees what the widget remembers, typed.
	testing.expect(t, strings.contains(report, `state  Tally{frames = 2, last = "seen"}`), report)
}
