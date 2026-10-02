package primer

import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of button and icon_button, driven through ui.Probe by tags.

@(private = "file")
Buttons_Model :: struct {
	saves, deletes, stars, offs, loads, nopes: int,
	loading:                                   bool,
}

@(private = "file")
buttons :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Buttons_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	if button(gtx, "Save", .Primary) {
		m.saves += 1
	}
	if button(gtx, "Delete", .Danger, .Small, leading = .Trash) {
		m.deletes += 1
	}
	if icon_button(gtx, .Star, "Star", size = .Large) {
		m.stars += 1
	}
	if button(gtx, "Off", state = .Disabled) {
		m.offs += 1
	}
	if button(gtx, "Load", loading = m.loading) {
		m.loads += 1
	}
	if button(gtx, "Nope", inactive = true) {
		m.nopes += 1
	}
	button(gtx, "Issues", count = "12")
	button(gtx, "Read more", .Link)
	button(gtx, "Wide", block = true)
}

@(private = "file")
buttons_probe :: proc(p: ^ui.Probe, m: ^Buttons_Model) {
	ui.probe_init(p, buttons, m, {600, 700}, allocator = context.temp_allocator)
}

@(test)
test_button_activates_by_click_and_keyboard_and_not_when_disabled :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Save"))
	testing.expect_value(t, m.saves, 1)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.saves, 2)
	ui.probe_key(&p, .Space)
	testing.expect_value(t, m.saves, 3)
	testing.expect(t, ui.probe_click(&p, "Delete"))
	testing.expect_value(t, m.deletes, 1)
	testing.expect(t, ui.probe_click(&p, "Star")) // an icon button is tagged by its name
	testing.expect_value(t, m.stars, 1)
	testing.expect(t, !ui.probe_click(&p, "Off")) // disabled: no input area
	testing.expect_value(t, m.offs, 0)
	// Inactive looks disabled but stays live (button.json states).
	testing.expect(t, ui.probe_click(&p, "Nope"))
	testing.expect_value(t, m.nopes, 1)
}

@(test)
test_a_loading_button_keeps_focus_but_ignores_activation :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Load"))
	testing.expect_value(t, m.loads, 1)
	m.loading = true
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Load")) // still a live area: it keeps focus
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.loads, 1)
	testing.expect(t, p.wants_frame) // its spinner turns
}

@(test)
test_button_geometry_follows_the_css :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	save := ui.probe_bounds(&p, "Save")
	testing.expect_value(t, save.h, tok.CONTROL_MEDIUM_SIZE) // 32
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	st := button_metrics(.Medium).style
	label := design.shape_style(&gtx, "Save", st, font_for(&gtx, st.weight))
	testing.expect_value(t, save.w, label.width + 2 * tok.CONTROL_MEDIUM_PADDING_INLINE_NORMAL) // hugs: 12px each side
	del := ui.probe_bounds(&p, "Delete")
	testing.expect_value(t, del.h, tok.CONTROL_SMALL_SIZE) // 28
	star := ui.probe_bounds(&p, "Star")
	testing.expect_value(t, star, ops.Rect{star.x, star.y, tok.CONTROL_LARGE_SIZE, tok.CONTROL_LARGE_SIZE}) // a 40px square
	// A count adds one gap and the pill after the label.
	issues := design.shape_style(&gtx, "Issues", st, font_for(&gtx, st.weight))
	cst := counter_style()
	pill := counter_size(design.shape_style(&gtx, "12", cst, font_for(&gtx, cst.weight)))
	counted := ui.probe_bounds(&p, "Issues")
	want := 2 * tok.CONTROL_MEDIUM_PADDING_INLINE_NORMAL + issues.width + tok.BASE_SIZE_8 + pill.x
	testing.expectf(t, abs(counted.w - want) < 0.01, "counted button %v wide, want %v", counted.w, want)
	// A link has no box: as tall as its line, exactly as wide as its label.
	link := ui.probe_bounds(&p, "Read more")
	testing.expect_value(t, link.h, st.line_height)
	testing.expect_value(t, link.w, design.shape_style(&gtx, "Read more", st, font_for(&gtx, st.weight)).width)
	testing.expect_value(t, ui.probe_bounds(&p, "Wide").w, 600) // block fills the width
}

@(private = "file")
is_color :: proc(p: ops.Paint, c: ops.Color) -> bool {
	got, solid := p.(ops.Color)
	return solid && got == c
}

@(private = "file")
count_focus_strokes :: proc(p: ^ui.Probe) -> (n: int) {
	focus := color(.Focus_Outline_Color)
	for op in p.scene.ops {
		if s, ok := op.(ops.Stroke); ok && is_color(s.paint, focus) {
			n += 1
		}
	}
	return
}

@(test)
test_focus_shows_for_the_keyboard_not_a_click :: proc(t: ^testing.T) {
	m: Buttons_Model
	p: ui.Probe
	buttons_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_click(&p, "Delete")
	ui.probe_frame(&p)
	testing.expect_value(t, count_focus_strokes(&p), 0) // focused by a click: no outline
	ui.probe_key(&p, .Tab)
	ui.probe_frame(&p)
	testing.expect_value(t, count_focus_strokes(&p), 1) // moved by Tab: the outline shows
}

@(test)
test_a_counter_label_without_a_count_takes_no_space :: proc(t: ^testing.T) {
	view :: proc(gtx: ^ui.Ctx, user: rawptr) {
		r := ui.row_open(gtx)
		defer ui.close(&r)
		counter_label(gtx, "")
		counter_label(gtx, "0", .Primary)
	}
	p: ui.Probe
	ui.probe_init(&p, view, nil, {200, 100}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	fills := 0
	for op in p.scene.ops {
		if f, ok := op.(ops.Fill); ok && is_color(f.paint, color(.Bg_Color_Neutral_Emphasis)) {
			fills += 1
			r := f.shape.(ops.Round_Rect).rect
			testing.expect_value(t, r.x, 0) // the empty one before it took no width
			testing.expect_value(t, r.h, tok.TEXT_BODY_SIZE_SMALL + 2 * (2 + tok.BORDER_WIDTH_THIN)) // 18px
		}
	}
	testing.expect_value(t, fills, 1) // "0" is a count, "" is not
}
