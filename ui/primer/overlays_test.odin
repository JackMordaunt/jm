package primer

import "core:testing"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Behaviour of overlay, anchored_overlay, popover, tooltip and details,
// driven through ui.Probe by tags.

@(private = "file")
near :: proc(a, b: f32) -> bool {
	return abs(a - b) < 0.01
}

// Overlay.

@(private = "file")
Overlay_Model :: struct {
	open, inner: bool, // the overlay, and one opened from inside it
	dismissed:   Dismissal,
	width:       Overlay_Width,
	fullscreen:  bool,
	presses:     int,
}

@(private = "file")
overlay_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Overlay_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if button(gtx, "Page") {
		m.presses += 1
	}
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	if button(gtx, "Trigger") {
		m.open = !m.open
	}
	t := ui.last_widget(gtx)
	o := overlay_open(gtx, &m.open, {0, 100}, width = m.width, slide = Anchor_Side.Outside_Bottom, ignore = {0, 0, t.size.x, t.size.y}, fullscreen = m.fullscreen, name = "Surface")
	if o.visible {
		c := ui.column_open(gtx, gap = 8)
		button(gtx, "One")
		if button(gtx, "Two") {
			m.inner = true
		}
		inner := overlay_open(gtx, &m.inner, {300, 0}, name = "Inner")
		if inner.visible {
			button(gtx, "Deep")
		}
		overlay_close(&inner)
		ui.close(&c)
	}
	if o.dismissed != .None {
		m.dismissed = o.dismissed
	}
	overlay_close(&o)
}

@(private = "file")
overlay_probe :: proc(p: ^ui.Probe, m: ^Overlay_Model, size := ops.Size{800, 600}) {
	ui.probe_init(p, overlay_view, m, size, allocator = context.temp_allocator)
}

@(test)
test_overlay_moves_focus_in_and_back_and_closes_on_escape :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	overlay_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Trigger"))
	trigger := ui.probe_current(&p) // the frame the click landed in
	_ = trigger
	ui.probe_frame(&p)
	one, _ := ui.probe_find(&p, "One")
	testing.expect_value(t, p.router.focus, one.area) // its first focusable area
	trig, _ := ui.probe_find(&p, "Trigger")
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Escape)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, trig.area) // back where it was
	testing.expect(t, !ui.probe_tagged(&p, "One"))
}

@(test)
test_overlay_escape_and_outside_presses_close_the_newest_first :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	overlay_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Trigger"))
	testing.expect(t, ui.probe_click(&p, "Two"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Deep"))
	// Escape closes only the inner one.
	ui.probe_key(&p, .Escape)
	testing.expect(t, m.open && !m.inner)
	// A press in the outer one closes the inner one only.
	testing.expect(t, ui.probe_click(&p, "Two"))
	ui.probe_frame(&p)
	testing.expect(t, m.inner)
	testing.expect(t, ui.probe_click(&p, "One"))
	testing.expect(t, m.open && !m.inner)
	// A press on the trigger is ignored, so the trigger's own toggle closes it once.
	testing.expect(t, ui.probe_click(&p, "Trigger"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.None) // no gesture of its own
	// A press outside everything closes both, and still lands. (The inner
	// one's open stays its caller's to clear: closed with its parent, it is
	// never asked again that frame.)
	testing.expect(t, ui.probe_click(&p, "Trigger"))
	testing.expect(t, ui.probe_click(&p, "Two"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Page"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Click_Outside)
	testing.expect_value(t, m.presses, 1)
	// A secondary press does not dismiss.
	testing.expect(t, ui.probe_click(&p, "Trigger"))
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Page", .Right))
	testing.expect(t, m.open)
}

@(test)
test_overlay_sizes_follow_the_css :: proc(t: ^testing.T) {
	m := Overlay_Model{open = true}
	p: ui.Probe
	overlay_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_advance(&p, 20, 1.0 / 60) // past the slide
	auto := ui.probe_bounds(&p, "Surface")
	testing.expect_value(t, auto.w, OVERLAY_MIN_WIDTH) // short content: the 192px minimum
	testing.expect_value(t, auto.y, 100 + button_metrics(.Medium).height + 16) // at its at, from the stack under the Page button
	m.width = .Small
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Surface").w, 256)
	m.width = .XXLarge
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Surface").w, 800 - OVERLAY_VIEWPORT_INSET) // capped by the window less 32px
	// Fullscreen applies below 768px wide only.
	m.fullscreen = true
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Surface").w, 800 - OVERLAY_VIEWPORT_INSET)
	narrow: ui.Probe
	overlay_probe(&narrow, &m, {700, 500})
	defer ui.probe_destroy(&narrow)
	ui.probe_advance(&narrow, 20, 1.0 / 60)
	testing.expect_value(t, ui.probe_bounds(&narrow, "Surface"), ops.Rect{0, 0, 700, 500})
}

@(test)
test_overlay_fades_and_slides_in_over_200ms :: proc(t: ^testing.T) {
	m: Overlay_Model
	p: ui.Probe
	overlay_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Trigger"))
	// The first frame: dt in, nearly transparent and 8px up.
	f := ui.probe_current(&p)
	faded := false
	for d in f.draws {
		if d.fade > 0.5 {
			faded = true
		}
	}
	testing.expect(t, faded, "the first frame is faded")
	settled := ui.probe_bounds(&p, "Surface").y
	ui.probe_advance(&p, 12, 1.0 / 60) // 200ms
	at := ui.probe_bounds(&p, "Surface").y
	testing.expectf(t, at - settled > 6 && at - settled <= OVERLAY_SLIDE, "it slid %v down", at - settled)
	for d in ui.probe_current(&p).draws {
		testing.expect_value(t, d.fade, 0)
	}
	testing.expect(t, !p.wants_frame, "it stops asking for frames")
	// Under reduced motion it does not fade, though it still slides.
	p.reduce_motion = true
	testing.expect(t, ui.probe_click(&p, "Trigger")) // closed
	testing.expect(t, ui.probe_click(&p, "Trigger")) // and opened again
	for d in ui.probe_current(&p).draws {
		testing.expect_value(t, d.fade, 0)
	}
	testing.expect(t, ui.probe_bounds(&p, "Surface").y < at, "it still slides")
}

// Anchored overlay.

@(private = "file")
Anchored_Model :: struct {
	open:      bool,
	side:      Anchor_Side,
	align:     Anchor_Align,
	narrow:    Narrow_Variant,
	at:        ops.Point, // where the anchor sits
	opened:    Open_Gesture,
	dismissed: Dismissal,
}

@(private = "file")
anchored_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Anchored_Model)(user)
	ops.transform_push(gtx.scene, ops.translate(m.at.x, m.at.y))
	defer ops.transform_pop(gtx.scene)
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	if button(gtx, "Anchor") {
		m.open = !m.open
	}
	a := anchored_overlay_open(gtx, &m.open, ui.last_widget(gtx), m.side, m.align, narrow = m.narrow, name = "Menu")
	if a.visible {
		ov := ui.sized_open(gtx, {min = {200, 100}, max = {200, 100}})
		c := ui.column_open(gtx)
		button(gtx, "Copy")
		button(gtx, "Paste")
		ui.close(&c)
		ui.close(&ov)
	}
	if a.opened != .None {
		m.opened = a.opened
	}
	if a.dismissed != .None {
		m.dismissed = a.dismissed
	}
	anchored_overlay_close(&a)
}

@(private = "file")
anchored_probe :: proc(p: ^ui.Probe, m: ^Anchored_Model, size := ops.Size{800, 600}) {
	ui.probe_init(p, anchored_view, m, size, allocator = context.temp_allocator)
	ui.probe_advance(p, 20, 1.0 / 60)
}

@(test)
test_anchored_overlay_places_against_its_anchor_and_flips :: proc(t: ^testing.T) {
	m := Anchored_Model{open = true, at = {100, 100}}
	p: ui.Probe
	anchored_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	anchor := ui.probe_bounds(&p, "Anchor")
	// Below, 4px away, flush with the anchor's left.
	testing.expect_value(t, ui.probe_bounds(&p, "Menu"), ops.Rect{anchor.x, anchor.y + anchor.h + ANCHOR_OFFSET, 200, 100})
	// End-aligned: flush with its right; where that runs off the left,
	// start alignment is tried next and fits.
	m.align = .End
	ui.probe_advance(&p, 2, 1.0 / 60)
	testing.expect_value(t, ui.probe_bounds(&p, "Menu").x, anchor.x)
	m.at = {400, 100}
	ui.probe_advance(&p, 2, 1.0 / 60)
	anchor = ui.probe_bounds(&p, "Anchor")
	testing.expect(t, near(ui.probe_bounds(&p, "Menu").x, anchor.x + anchor.w - 200), "end-aligned")
	// Near the bottom it flips above; near the right edge a start
	// alignment flips to end.
	m.align = .Start
	m.at = {700, 520}
	ui.probe_advance(&p, 20, 1.0 / 60)
	anchor = ui.probe_bounds(&p, "Anchor")
	menu := ui.probe_bounds(&p, "Menu")
	testing.expect_value(t, menu.y, anchor.y - ANCHOR_OFFSET - 100)
	testing.expect_value(t, menu.x, anchor.x + anchor.w - 200)
	// Inside-center: centred across the anchor, 4px down from its top.
	m.at = {300, 300}
	m.side = .Inside_Center
	ui.probe_advance(&p, 2, 1.0 / 60)
	anchor = ui.probe_bounds(&p, "Anchor")
	menu = ui.probe_bounds(&p, "Menu")
	testing.expect(t, near(menu.x, anchor.x + (anchor.w - 200) / 2), "centred across")
	testing.expect_value(t, menu.y, anchor.y + INSIDE_ALIGNMENT_OFFSET)
}

@(test)
test_anchored_overlay_opens_on_arrow_keys_traps_focus_and_returns_it :: proc(t: ^testing.T) {
	m := Anchored_Model{at = {100, 100}}
	p: ui.Probe
	anchored_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	anchor, _ := ui.probe_find(&p, "Anchor")
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, anchor.area)
	ui.probe_key(&p, .Down)
	testing.expect(t, m.open)
	testing.expect_value(t, m.opened, Open_Gesture.Anchor_Key_Press)
	ui.probe_frame(&p)
	copy, _ := ui.probe_find(&p, "Copy")
	paste, _ := ui.probe_find(&p, "Paste")
	testing.expect_value(t, p.router.focus, copy.area)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, paste.area)
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, p.router.focus, copy.area) // trapped: round, not out to the anchor
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Escape)
	ui.probe_frame(&p)
	testing.expect_value(t, p.router.focus, anchor.area)
	// A press on the anchor toggles it, and is no outside press.
	testing.expect(t, ui.probe_click(&p, "Anchor"))
	testing.expect(t, m.open)
	m.dismissed = .None
	testing.expect(t, ui.probe_click(&p, "Anchor"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.None)
}

@(test)
test_anchored_overlay_goes_fullscreen_with_a_close_button_when_narrow :: proc(t: ^testing.T) {
	m := Anchored_Model{open = true, at = {100, 100}, narrow = .Fullscreen}
	p: ui.Probe
	anchored_probe(&p, &m, {600, 500})
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect_value(t, ui.probe_bounds(&p, "Menu"), ops.Rect{0, 0, 600, 500})
	side := button_metrics(.Medium).height
	testing.expect_value(t, ui.probe_bounds(&p, "Close"), ops.Rect{600 - 8 - side, 8, side, side})
	testing.expect(t, ui.probe_click(&p, "Close"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Close_Button)
}

// Popover.

@(private = "file")
Pop_Model :: struct {
	open:      bool,
	dismissed: Dismissal,
	clicks:    int,
	caret:     Popover_Caret,
}

@(private = "file")
pop_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Pop_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	if button(gtx, "Elsewhere") {
		m.clicks += 1
	}
	st := ui.stack_open(gtx)
	defer ui.close(&st)
	if button(gtx, "Show tip") {
		m.open = !m.open
	}
	t := ui.last_widget(gtx)
	p := popover_open(gtx, &m.open, {0, t.size.y + 12}, caret = m.caret, ignore = {0, 0, t.size.x, t.size.y})
	if p.visible {
		button(gtx, "Inside")
	}
	if p.dismissed != .None {
		m.dismissed = p.dismissed
	}
	popover_close(&p)
}

@(test)
test_popover_opens_and_closes_on_escape_and_outside_press :: proc(t: ^testing.T) {
	m: Pop_Model
	p: ui.Probe
	ui.probe_init(&p, pop_view, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, ui.probe_click(&p, "Show tip"))
	testing.expect(t, m.open)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_tagged(&p, "Inside"))
	testing.expect_value(t, p.router.focus != 0, true) // the trigger's click focused it...
	inside, _ := ui.probe_find(&p, "Inside")
	testing.expect(t, p.router.focus != inside.area, "...and the popover moved nothing")
	// A press inside does not close it.
	testing.expect(t, ui.probe_click(&p, "Inside"))
	testing.expect(t, m.open)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Escape)
	testing.expect(t, ui.probe_click(&p, "Show tip"))
	testing.expect(t, m.open)
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Elsewhere"))
	testing.expect(t, !m.open)
	testing.expect_value(t, m.dismissed, Dismissal.Click_Outside)
	testing.expect_value(t, m.clicks, 1) // the outside press still lands
}

@(test)
test_popover_card_and_caret_follow_the_css :: proc(t: ^testing.T) {
	m := Pop_Model{open = true}
	p: ui.Probe
	ui.probe_init(&p, pop_view, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	trigger := ui.probe_bounds(&p, "Show tip")
	inside := ui.probe_bounds(&p, "Inside")
	// Content 24px in from a 320px card at the asked spot.
	testing.expect_value(t, inside.x, trigger.x + tok.BASE_SIZE_24)
	testing.expect_value(t, inside.y, trigger.y + trigger.h + 12 + tok.BASE_SIZE_24)
	// A corner caret moves the card 9px toward its corner.
	m.caret = .Top_Left
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Inside").x, trigger.x + tok.BASE_SIZE_24 - POPOVER_CARET_SHIFT)
	// The caret's triangles: base on the edge, tip 8 and 7px out, 1px left
	// of centre on a 320px card (Popover.module.css:33-54).
	outer, inner := popover_caret(.Top, {320, 100})
	testing.expect_value(t, outer, [3]ops.Point{{151, 0}, {167, 0}, {159, -8}})
	testing.expect_value(t, inner, [3]ops.Point{{152, 0}, {166, 0}, {159, -7}})
	// Top-right: 20px from the right edge to the outer box, 21 to the inner.
	outer, inner = popover_caret(.Top_Right, {320, 100})
	testing.expect_value(t, outer[1].x, 320 - 20)
	testing.expect_value(t, inner[1].x, 320 - 21)
	// Right-bottom: 16px from the bottom to the outer box, 17 to the inner.
	outer, inner = popover_caret(.Right_Bottom, {320, 100})
	testing.expect_value(t, outer, [3]ops.Point{{320, 68}, {320, 84}, {328, 76}})
	testing.expect_value(t, inner[1].y, 100 - 17)
	// Left-top: the box 24px down less the 9px margin, so the tip at 23.
	outer, _ = popover_caret(.Left_Top, {320, 100})
	testing.expect_value(t, outer[2], ops.Point{-8, 23})
}

// Tooltip.

@(private = "file")
Tip_Model :: struct {
	direction: Tooltip_Direction,
	shown:     bool,
	disabled:  bool,
	dialog:    bool,
}

@(private = "file")
tip_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Tip_Model)(user)
	ops.transform_push(gtx.scene, ops.translate(200, 200))
	defer ops.transform_pop(gtx.scene)
	r := ui.row_open(gtx, gap = 40)
	defer ui.close(&r)
	{
		st := ui.stack_open(gtx)
		defer ui.close(&st)
		button(gtx, "Save")
		m.shown = tooltip(gtx, "Saves the file", ui.last_widget(gtx), direction = m.direction, disabled = m.disabled)
	}
	icon_button(gtx, .Pencil, "Edit")
	button(gtx, "Plain")
}

@(test)
test_tooltip_shows_after_its_delay_and_hides_on_leave :: proc(t: ^testing.T) {
	m := Tip_Model{direction = .S}
	p: ui.Probe
	ui.probe_init(&p, tip_view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	ui.probe_set_dt(&p, 0.02)
	c, _ := ui.probe_center(&p, "Save")
	ui.probe_move(&p, c.x, c.y)
	testing.expect(t, !m.shown)
	testing.expect(t, p.wants_frame, "it asks for a frame to end its delay on")
	ui.probe_frame(&p) // 20ms
	testing.expect(t, !m.shown)
	ui.probe_advance(&p, 2, 0.02) // 60ms
	testing.expect(t, m.shown)
	testing.expect(t, ui.probe_tagged(&p, "Saves the file"))
	// The trigger keeps its hover: the tooltip only observes it.
	save, _ := ui.probe_find(&p, "Save")
	testing.expect_value(t, p.router.hover, save.area)
	// Onto the bubble, across the bridge, it stays.
	bubble := ui.probe_bounds(&p, "Saves the file")
	ui.probe_move(&p, bubble.x + bubble.w / 2, bubble.y - 2)
	testing.expect(t, m.shown)
	ui.probe_move(&p, bubble.x + bubble.w / 2, bubble.y + bubble.h / 2)
	testing.expect(t, m.shown)
	// Off both, it hides at once.
	ui.probe_move(&p, 10, 10)
	testing.expect(t, !m.shown)
	// Disabled, it never shows.
	m.disabled = true
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 5, 0.02)
	testing.expect(t, !m.shown)
}

@(test)
test_tooltip_bubble_follows_the_css :: proc(t: ^testing.T) {
	m := Tip_Model{direction = .S}
	p: ui.Probe
	ui.probe_init(&p, tip_view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	c, _ := ui.probe_center(&p, "Save")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 10, 0.02)
	save := ui.probe_bounds(&p, "Save")
	bubble := ui.probe_bounds(&p, "Saves the file")
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	para := tooltip_text(&gtx, "Saves the file", TOOLTIP_MAX_WIDTH - 2 * tok.OVERLAY_PADDING_CONDENSED)
	// 8px by 4px of padding round the text, 4px below, centred.
	testing.expect(t, near(bubble.w, para.width + 2 * tok.OVERLAY_PADDING_CONDENSED), "8px either side")
	testing.expect(t, near(bubble.h, para.height + 2 * tok.OVERLAY_PADDING_BLOCK_CONDENSED), "4px above and below")
	testing.expect_value(t, bubble.y, save.y + save.h + tok.OVERLAY_OFFSET)
	testing.expect(t, near(bubble.x + bubble.w / 2, save.x + save.w / 2), "centred under its trigger")
	// North east: above, from the trigger's left edge.
	m.direction = .NE
	ui.probe_frame(&p)
	bubble = ui.probe_bounds(&p, "Saves the file")
	testing.expect_value(t, bubble.x, save.x)
	testing.expect_value(t, bubble.y, save.y - tok.OVERLAY_OFFSET - bubble.h)
	// Long text wraps within 250px, balanced: no narrower width keeps its lines.
	long := "Tooltips wrap by word once they reach their widest, and balance their lines"
	wide := tooltip_text(&gtx, long, TOOLTIP_MAX_WIDTH - 16)
	testing.expect(t, len(wide.lines) > 1)
	testing.expect(t, wide.width <= TOOLTIP_MAX_WIDTH - 16)
	unbalanced := design_lines(&gtx, long, TOOLTIP_MAX_WIDTH - 16)
	testing.expect_value(t, len(wide.lines), unbalanced)
	testing.expect(t, wide.width < TOOLTIP_MAX_WIDTH - 16 - 1, "balanced lines are narrower than the cap")
}

// design_lines is how many lines text breaks into at width, unbalanced.
@(private = "file")
design_lines :: proc(gtx: ^ui.Ctx, text: string, width: f32) -> int {
	st := style(.Body_Small)
	return len(ui.paragraph_layout(gtx.shaper, font_for(gtx, st.weight), st.size, text, width, gtx.allocator, line_pitch = st.line_height).lines)
}

@(test)
test_tooltip_shows_on_keyboard_focus_only_and_escape_hides_it :: proc(t: ^testing.T) {
	m := Tip_Model{direction = .S}
	p: ui.Probe
	ui.probe_init(&p, tip_view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// A click focuses without showing it.
	testing.expect(t, ui.probe_click(&p, "Save"))
	ui.probe_move(&p, 10, 10)
	testing.expect(t, !m.shown)
	// Tab from the last button wraps to it: shown at once.
	testing.expect(t, ui.probe_click(&p, "Plain"))
	ui.probe_key(&p, .Tab)
	testing.expect(t, m.shown)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !m.shown)
	ui.probe_frame(&p)
	testing.expect(t, !m.shown) // stays down until focus leaves
	ui.probe_key(&p, .Tab) // to the icon button: its tooltip names it
	testing.expect(t, !m.shown)
	testing.expect(t, ui.probe_tagged(&p, "Edit")) // the button
	tips := 0
	for tg in ui.probe_current(&p).tags {
		if tg.name == "Edit" {
			tips += 1
		}
	}
	testing.expect_value(t, tips, 2) // the button and its tooltip
}

@(test)
test_only_one_tooltip_shows_at_a_time :: proc(t: ^testing.T) {
	m := Tip_Model{direction = .S}
	p: ui.Probe
	ui.probe_init(&p, tip_view, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	// Keyboard focus on Save shows its tooltip; hovering the icon button
	// shows that one and takes Save's down.
	testing.expect(t, ui.probe_click(&p, "Plain"))
	ui.probe_key(&p, .Tab)
	testing.expect(t, m.shown)
	c, _ := ui.probe_center(&p, "Edit")
	ui.probe_move(&p, c.x, c.y)
	ui.probe_advance(&p, 6, 0.02)
	testing.expect(t, !m.shown)
	ui.probe_frame(&p)
	testing.expect(t, !m.shown) // and it does not come back while focus stays
}

// Details.

@(private = "file")
Details_Model :: struct {
	open:    bool,
	outside: bool,
}

@(private = "file")
details_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Details_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	d := details_open(gtx, &m.open, close_on_outside = m.outside)
	if details_summary(&d, button(gtx, "More")) {
		button(gtx, "Hidden")
	}
	details_close(&d)
	button(gtx, "After")
}

@(test)
test_details_toggles_its_content_from_its_summary :: proc(t: ^testing.T) {
	m: Details_Model
	p: ui.Probe
	ui.probe_init(&p, details_view, &m, {400, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	testing.expect(t, !ui.probe_tagged(&p, "Hidden"))
	after := ui.probe_bounds(&p, "After").y
	testing.expect(t, ui.probe_click(&p, "More"))
	testing.expect(t, m.open)
	testing.expect(t, ui.probe_tagged(&p, "Hidden"))
	testing.expect(t, ui.probe_bounds(&p, "After").y > after, "the content takes room in the flow")
	ui.probe_key(&p, .Space) // the summary keeps focus: Space toggles it back
	testing.expect(t, !m.open)
	// A press outside closes it only with close_on_outside.
	testing.expect(t, ui.probe_click(&p, "More"))
	testing.expect(t, ui.probe_click(&p, "After"))
	testing.expect(t, m.open)
	m.outside = true
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Hidden"))
	testing.expect(t, m.open) // inside
	testing.expect(t, ui.probe_click(&p, "After"))
	testing.expect(t, !m.open)
	got := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, len(got) > 0)
}
