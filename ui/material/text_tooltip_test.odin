package material

import "core:testing"
import "jm:ui"
import "jm:ui/ops"

// Behaviour of text, driven through ui.Probe.

@(private = "file")
Wrap_Model :: struct {
	short, long:     ui.Dims,
	short_w, line_h: f32, // "Short" on one line, and a Body_Medium line's height
}

@(private = "file")
wrap_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Wrap_Model)(user)
	m.short_w = shape_text(gtx, "Short", .Body_Medium).width
	m.line_h = TYPE_STYLES[.Body_Medium].line_height
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if ui.row(gtx) {
		m.short = text(gtx, "Short", .Body_Medium, {0, 0, 0, 255})
	}
	m.long = text(gtx, "a line long enough to wrap in a narrow window", .Body_Medium, {0, 0, 0, 255}, width = 120)
}

@(test)
test_text_hugs_one_line_and_wraps_at_its_width :: proc(t: ^testing.T) {
	m: Wrap_Model
	p: ui.Probe
	ui.probe_init(&p, wrap_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, m.short_w > 0)
	testing.expect_value(t, m.short.size, ops.Size{m.short_w, m.line_h})
	testing.expect(t, m.short.baseline > 0)
	testing.expect(t, m.long.size.x <= 120)
	testing.expect(t, m.long.size.y >= 2 * m.line_h)
	_, tagged := ui.probe_find(&p, "Short")
	testing.expect(t, tagged)
}
