package primer

import "core:strings"
import "core:testing"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import "jm:ui/testutil"
import tok "jm:ui/primer/tokens"

// Behaviour of the form controls, driven through ui.Probe by tags.

@(private = "file")
Forms_Model :: struct {
	name, bio, search, limited:    ui.Text_State,
	submits, actions:              int,
	disabled:                      bool,
	choice:                        int,
	terms, news, off:              bool,
	radio:                         int,
	on, loading:                   bool,
	view:                          int,
	radio_changes:                 int,
	view_presses:                  int,
	edited:                        bool,
}

@(private = "file")
forms_model_destroy :: proc(m: ^Forms_Model) {
	ui.text_destroy(&m.name)
	ui.text_destroy(&m.bio)
	ui.text_destroy(&m.search)
	ui.text_destroy(&m.limited)
}

@(private = "file")
text_width :: proc(p: ^ui.Probe, s: string, st: tok.Type_Style) -> f32 {
	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	return design.shape_style(&gtx, s, st, font_for(&gtx, st.weight)).width
}

@(private = "file")
choices :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	checkbox(gtx, &m.terms, "Terms", caption = "Read them")
	checkbox(gtx, &m.off, "Off", state = .Disabled)
	plain := false
	checkbox(gtx, &plain)
	{
		g := checkbox_group_open(gtx, "Mail", disabled = m.disabled)
		checkbox(gtx, &m.news, "News")
		checkbox_group_close(gtx, &g)
	}
	{
		g := radio_group_open(gtx, "Visibility", validation = "Pick one", status = .Error)
		names := [?]string{"Public", "Private", "Internal", "Secret"}
		for n, i in names {
			if radio(gtx, m.radio == i, n, state = i == 2 ? .Disabled : .Live) {
				m.radio = i
				m.radio_changes += 1
			}
		}
		radio_group_close(gtx, &g)
	}
}

@(test)
test_a_checkbox_toggles_by_box_label_and_space_but_not_its_caption :: proc(t: ^testing.T) {
	m: Forms_Model
	p: ui.Probe
	ui.probe_init(&p, choices, &m, {600, 800}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	terms := ui.probe_bounds(&p, "Terms")
	label_w := text_width(&p, "Terms", form_label_style(false))
	// The hit area is the box and the label 8px after it, not the caption.
	testing.expect_value(t, terms.w, CHOICE_BOX + CHOICE_GAP + label_w)
	testing.expect_value(t, terms.h, form_label_style(false).line_height)
	testing.expect(t, ui.probe_click(&p, "Terms"))
	testing.expect(t, m.terms)
	ui.probe_key(&p, .Space)
	testing.expect(t, !m.terms)
	ui.probe_move(&p, terms.x + CHOICE_BOX + CHOICE_GAP + 2, terms.y + terms.h + 8) // on the caption
	ui.router_push(&p.router, {kind = .Press, pos = {terms.x + CHOICE_BOX + CHOICE_GAP + 2, terms.y + terms.h + 8}})
	ui.probe_frame(&p)
	ui.router_push(&p.router, {kind = .Release, pos = {terms.x + CHOICE_BOX + CHOICE_GAP + 2, terms.y + terms.h + 8}})
	ui.probe_frame(&p)
	testing.expect(t, !m.terms)
	testing.expect(t, !ui.probe_click(&p, "Off"))
	testing.expect(t, !m.off)
	// A bare checkbox is its 16px box with 2px above it.
	plain := ui.probe_bounds(&p, "")
	testing.expect_value(t, plain.w, CHOICE_BOX)
	testing.expect_value(t, plain.h, CHOICE_BOX)
}

@(test)
test_a_disabled_group_disables_its_checkboxes :: proc(t: ^testing.T) {
	m: Forms_Model
	p: ui.Probe
	ui.probe_init(&p, choices, &m, {600, 800}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "News"))
	testing.expect(t, m.news)
	m.disabled = true
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_click(&p, "News"))
	testing.expect(t, m.news)
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(report, `group "Mail" disabled`), report)
	testing.expect(t, strings.contains(report, `checkbox "News" checked disabled`), report)
}

@(test)
test_radio_group_arrows_check_the_next_enabled_radio_and_wrap :: proc(t: ^testing.T) {
	m: Forms_Model
	p: ui.Probe
	ui.probe_init(&p, choices, &m, {600, 800}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Private"))
	testing.expect_value(t, m.radio, 1)
	testing.expect(t, ui.probe_click(&p, "Private"))
	testing.expect_value(t, m.radio_changes, 1) // pressed again: no change reported
	ui.probe_key(&p, .Down)
	testing.expect_value(t, m.radio, 3) // past the disabled Internal
	ui.probe_frame(&p) // focus follows
	ui.probe_key(&p, .Right)
	ui.probe_frame(&p) // wrapped back to the first, drawn before: reported next frame
	testing.expect_value(t, m.radio, 0)
	ui.probe_frame(&p)
	ui.probe_key(&p, .Up)
	testing.expect_value(t, m.radio, 3) // and back over the end
	ui.probe_frame(&p) // Public drew checked before Secret took it
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(report, `radio "Secret" checked focused`), report)
	testing.expect(t, strings.contains(report, `alert "Pick one"`), report)
}

@(private = "file")
switches :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	toggle_switch(gtx, &m.on, "Notify", loading = m.loading)
	small := true
	toggle_switch(gtx, &small, "Compact", size = .Small)
}

@(test)
test_a_toggle_switch_flips_by_track_and_label_and_never_moves :: proc(t: ^testing.T) {
	m: Forms_Model
	p: ui.Probe
	ui.probe_init(&p, switches, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	track := ui.probe_bounds(&p, "Notify")
	testing.expect(t, testutil.near(track.w, 64) && track.h == 32)
	small := ui.probe_bounds(&p, "Compact")
	testing.expect(t, testutil.near(small.w, 48) && small.h == 24)
	// The status label is as wide as the wider word, 8px each side.
	st := tok.Type_Style{tok.BASE_TEXT_WEIGHT_NORMAL, tok.TEXT_BODY_SIZE_MEDIUM, tok.TEXT_BODY_SIZE_MEDIUM * 1.5, 0}
	testing.expect(t, testutil.near(track.x, 16 + max(text_width(&p, "On", st), text_width(&p, "Off", st))))
	testing.expect(t, ui.probe_click(&p, "Notify"))
	testing.expect(t, m.on)
	ui.probe_frame(&p)
	testing.expect_value(t, ui.probe_bounds(&p, "Notify"), track) // "On" is narrower; the track stays
	testing.expect(t, ui.probe_click(&p, "On")) // the status label toggles too
	testing.expect(t, !m.on)
	ui.probe_key(&p, .Space)
	testing.expect(t, m.on)
	m.loading = true
	ui.probe_frame(&p)
	testing.expect(t, ui.probe_click(&p, "Notify")) // still live, still focusable
	testing.expect(t, m.on) // but ignores the press
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(report, `switch "Notify" checked disabled busy`), report)
}

@(private = "file")
one_checkbox :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	checkbox(gtx, &m.terms, "Terms")
}

// checkmark_clip_height is the height of the checkmark's clip this frame, -1 with
// none: how much of the mark shows, from the bottom up.
@(private = "file")
checkmark_clip_height :: proc(p: ^ui.Probe) -> f32 {
	for op in p.scene.ops {
		if c, ok := op.(ops.Push_Clip); ok {
			if r, is_rect := c.shape.(ops.Rect); is_rect && r.w == CHOICE_BOX {
				return r.h
			}
		}
	}
	return -1
}

@(test)
test_a_checkmark_is_revealed_after_the_fill_and_hidden_at_once :: proc(t: ^testing.T) {
	m: Forms_Model
	p: ui.Probe
	ui.probe_init(&p, one_checkbox, &m, {300, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	ui.probe_set_dt(&p, 0.01)
	testing.expect(t, ui.probe_click(&p, "Terms"))
	testing.expect(t, m.terms)
	testing.expect_value(t, checkmark_clip_height(&p), -1) // the first 80ms wait for the fill
	ui.probe_advance(&p, 9, 0.01) // 100ms in: 20ms into the reveal
	h := checkmark_clip_height(&p)
	testing.expectf(t, h > 0 && h < CHOICE_BOX, "the mark shows %vpx", h)
	ui.probe_advance(&p, 8, 0.01)
	testing.expect_value(t, checkmark_clip_height(&p), CHOICE_BOX)
	testing.expect(t, ui.probe_click(&p, "Terms"))
	testing.expect(t, !m.terms)
	ui.probe_advance(&p, 2, 0.01) // no delay going out
	h = checkmark_clip_height(&p)
	testing.expectf(t, h > 0 && h < CHOICE_BOX, "the mark shows %vpx", h)
	ui.probe_advance(&p, 8, 0.01)
	testing.expect_value(t, checkmark_clip_height(&p), -1)
}
