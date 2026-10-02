package primer

import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of dialog and confirmation_dialog, driven through ui.Probe by
// tags.

@(private = "file")
Dialog_Model :: struct {
	open:       bool,
	dismissed:  Dismissal,
	saves:      int,
	cancels:    int,
	behind:     int, // clicks on the page button behind
	auto_focus: bool,
	width:      Dialog_Width,
	height:     Dialog_Height,
	position:   Dialog_Position,
	narrow:     Dialog_Narrow_Position,
	align:      Dialog_Align,
	lines:      int,
	answer:     Confirmation,
	confirm:    bool, // show the confirmation dialog instead
	danger:     bool,
}

@(private = "file")
dialog_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Dialog_Model)(user)
	page := ui.column_open(gtx)
	defer ui.close(&page)
	if button(gtx, "Behind") {
		m.behind += 1
	}
	if m.confirm {
		a := confirmation_dialog(gtx, &m.open, "Delete it?", "It cannot be undone.", confirm_content = "Delete", confirm_type = m.danger ? .Danger : .Primary)
		if a != .None {
			m.answer = a
		}
		return
	}
	save, cancel := false, false
	buttons := [2]Dialog_Button{{content = "Cancel", clicked = &cancel}, {content = "Save", type = .Primary, auto_focus = m.auto_focus, clicked = &save}}
	d := dialog_open(gtx, &m.open, "Edit", "Subtitle", buttons[:], m.width, height = m.height, position = m.position, narrow = m.narrow, align = m.align)
	if d.visible {
		c := ui.column_open(gtx)
		button(gtx, "Body")
		for i in 0 ..< m.lines {
			p := ui.widget_open(gtx, u64(i + 1))
			ui.widget_close(gtx, &p, {size = {100, 40}})
		}
		ui.close(&c)
	}
	if d.dismissed != .None {
		m.dismissed = d.dismissed
	}
	dialog_close(&d)
	if save {
		m.saves += 1
	}
	if cancel {
		m.cancels += 1
	}
}

@(private = "file")
dialog_probe :: proc(p: ^ui.Probe, m: ^Dialog_Model, size := ops.Size{1000, 800}) {
	ui.probe_init(p, dialog_view, m, size, allocator = context.temp_allocator)
	ui.probe_advance(p, 20, 1.0 / 60)
}

@(test)
test_dialog_focuses_traps_and_returns_focus :: proc(t: ^testing.T) {
	m: Dialog_Model
	p: ui.Probe
	dialog_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Behind"))
	behind, _ := ui.probe_find(&p, "Behind")
	m.open = true
	ui.probe_advance(&p, 2, 1.0 / 60)
	// No autofocus button: the Close button, first in the window.
	close, _ := ui.probe_find(&p, "Close")
	testing.expect_value(t, p.router.focus, close.area)
	// Tab cycles Close, Body, Cancel, Save and round.
	stops := [?]string{"Body", "Cancel", "Save", "Close"}
	for s in stops {
		ui.probe_key(&p, .Tab)
		h, _ := ui.probe_find(&p, s)
		testing.expectf(t, p.router.focus == h.area, "Tab reaches %s", s)
	}
	// A press on the page behind lands on the backdrop, not the page.
	testing.expect(t, ui.probe_click(&p, "Behind"))
	testing.expect_value(t, m.behind, 1)
	testing.expect(t, !m.open)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, behind.area) // focus back where it was
}

@(test)
test_dialog_closes_by_escape_close_button_and_backdrop_click :: proc(t: ^testing.T) {
	m := Dialog_Model{open = true}
	p: ui.Probe
	dialog_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	behind, _ := ui.probe_find(&p, "Behind")
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Escape)
	m.open, m.dismissed = true, .None
	ui.probe_advance(&p, 20, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "Close"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Close_Button)
	// A press and release on the backdrop closes it, reported as Escape;
	// the page under it hears nothing.
	m.open, m.dismissed = true, .None
	ui.probe_advance(&p, 20, 1.0 / 60)
	testing.expect(t, ui.probe_click(&p, "Behind"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Escape)
	testing.expect_value(t, m.behind, 0)
	// A drag from inside the window out onto the backdrop does not.
	m.open, m.dismissed = true, .None
	ui.probe_advance(&p, 20, 1.0 / 60)
	body := ui.probe_bounds(&p, "Body")
	b := ui.probe_bounds(&p, "Behind")
	testing.expect(t, ui.probe_drag(&p, "Body", b.x + 5 - (body.x + body.w / 2), b.y + 5 - (body.y + body.h / 2)))
	testing.expect(t, m.open)
	testing.expect_value(t, p.router.pointer, ops.Point{b.x + 5, b.y + 5}) // it did end over the backdrop
	testing.expect_value(t, m.behind, 0)
	_ = behind
}

@(test)
test_dialog_footer_buttons_report_clicks_and_take_arrow_keys :: proc(t: ^testing.T) {
	m := Dialog_Model{open = true, auto_focus = true}
	p: ui.Probe
	dialog_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// The autofocus footer button takes focus first.
	save, _ := ui.probe_find(&p, "Save")
	cancel, _ := ui.probe_find(&p, "Cancel")
	testing.expect_value(t, p.router.focus, save.area)
	ui.probe_key(&p, .Left)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, cancel.area)
	ui.probe_key(&p, .Left)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, cancel.area) // stops at the end
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, save.area)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.saves, 1)
	testing.expect(t, m.open) // a footer button does not close it
	testing.expect(t, ui.probe_click(&p, "Cancel"))
	testing.expect_value(t, m.cancels, 1)
}

@(test)
test_dialog_geometry_follows_the_css :: proc(t: ^testing.T) {
	m := Dialog_Model{open = true, width = .XLarge}
	p: ui.Probe
	dialog_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	win := ui.probe_bounds(&p, "Edit")
	testing.expect_value(t, win.w, 640)
	testing.expect(t, near(win.x, (1000 - 640) / 2) && near(win.y + win.h / 2, 400), "centred")
	// The body pads 16px; the header is 8px of padding round a block
	// padded 6 by 8, with a 1px rule under it.
	body := ui.probe_bounds(&p, "Body")
	testing.expect_value(t, body.x, win.x + tok.BASE_SIZE_16)
	cancel := ui.probe_bounds(&p, "Cancel")
	save := ui.probe_bounds(&p, "Save")
	// Footer buttons at the end, 8px apart, 16px in from the edges.
	testing.expect(t, near(save.x + save.w, win.x + win.w - tok.BASE_SIZE_16), "flush right, 16px in")
	testing.expect(t, near(save.x - (cancel.x + cancel.w), tok.BASE_SIZE_8), "8px apart")
	testing.expect(t, near(win.y + win.h - (save.y + save.h), tok.BASE_SIZE_16), "16px from the bottom")
	// Small: 296px. Tall content caps at the window less 64px and scrolls.
	m.width, m.lines = .Small, 40
	ui.probe_advance(&p, 3, 1.0 / 60)
	win = ui.probe_bounds(&p, "Edit")
	testing.expect_value(t, win.w, 296)
	testing.expect_value(t, win.h, 800 - DIALOG_VIEWPORT_INSET)
	// A fixed height.
	m.height, m.lines = .Small, 2
	ui.probe_advance(&p, 3, 1.0 / 60)
	testing.expect_value(t, ui.probe_bounds(&p, "Edit").h, 480)
	// Align top: 64px from the top.
	m.height, m.align = .Auto, .Top
	ui.probe_advance(&p, 3, 1.0 / 60)
	testing.expect_value(t, ui.probe_bounds(&p, "Edit").y, DIALOG_VIEWPORT_INSET)
	// A right sheet: the window's full height against its right edge.
	m.align, m.position, m.width = .Center, .Right, .Medium
	ui.probe_advance(&p, 20, 1.0 / 60)
	testing.expect_value(t, ui.probe_bounds(&p, "Edit"), ops.Rect{1000 - 320, 0, 320, 800})
}

@(test)
test_dialog_takes_its_narrow_position_below_768px :: proc(t: ^testing.T) {
	m := Dialog_Model{open = true, narrow = .Bottom, width = .XLarge}
	p: ui.Probe
	dialog_probe(&p, &m, {600, 700})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	win := ui.probe_bounds(&p, "Edit")
	testing.expect_value(t, win.w, 600)
	testing.expect(t, near(win.y + win.h, 700), "on the bottom edge")
	m.narrow = .Fullscreen
	ui.probe_advance(&p, 20, 1.0 / 60)
	testing.expect_value(t, ui.probe_bounds(&p, "Edit"), ops.Rect{0, 0, 600, 700})
	// Narrow center keeps its width step, within the window less 64px.
	m.narrow = .Center
	ui.probe_advance(&p, 20, 1.0 / 60)
	testing.expect_value(t, ui.probe_bounds(&p, "Edit").w, 600 - DIALOG_VIEWPORT_INSET)
}

@(test)
test_escape_on_the_close_buttons_tooltip_closes_the_dialog :: proc(t: ^testing.T) {
	m := Dialog_Model{open = true}
	p: ui.Probe
	dialog_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// Keyboard focus on Close shows its tooltip; Escape still closes the
	// dialog at once (Dialog.tsx:222-238).
	for _ in 0 ..< 4 {
		ui.probe_key(&p, .Tab)
	}
	close, _ := ui.probe_find(&p, "Close")
	testing.expect_value(t, p.router.focus, close.area)
	tips := 0
	for tg in ui.probe_current(&p).tags {
		if tg.name == "Close" {
			tips += 1
		}
	}
	testing.expect_value(t, tips, 2) // the button and its tooltip
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Escape)
}

@(test)
test_confirmation_dialog_answers_and_focuses_by_danger :: proc(t: ^testing.T) {
	m := Dialog_Model{open = true, confirm = true}
	p: ui.Probe
	dialog_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, ui.probe_bounds(&p, "Delete it?").w, DIALOG_WIDTHS[.Medium])
	del, _ := ui.probe_find(&p, "Delete")
	testing.expect_value(t, p.router.focus, del.area) // confirm takes focus
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.answer, Confirmation.Confirm)
	testing.expect(t, !m.open)
	// Danger: cancel takes focus, so Enter does not destroy.
	m.open, m.danger, m.answer = true, true, .None
	ui.probe_advance(&p, 3, 1.0 / 60)
	cancel, _ := ui.probe_find(&p, "Cancel")
	testing.expect_value(t, p.router.focus, cancel.area)
	ui.probe_key(&p, .Tab)
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, p.router.focus, cancel.area)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.answer, Confirmation.Cancel)
	testing.expect(t, !m.open)
	m.open, m.answer = true, .None
	ui.probe_advance(&p, 3, 1.0 / 60)
	ui.probe_key(&p, .Escape)
	testing.expect_value(t, m.answer, Confirmation.Escape)
}
