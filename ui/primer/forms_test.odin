package primer

import "core:mem"
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
	// One Tab stop, entered at the checked radio, which Tab does not change.
	changes := m.radio_changes
	ui.probe_key(&p, .Tab)
	testing.expect_value(t, focus_name(&p), "Terms") // out of the group, last on the page: round to the first
	ui.probe_key(&p, .Tab, {.Shift})
	testing.expect_value(t, focus_name(&p), "Secret")
	ui.probe_frame(&p)
	testing.expect_value(t, m.radio, 3)
	testing.expect_value(t, m.radio_changes, changes)
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

@(private = "file")
fields :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	{
		f := form_control_open(gtx, "Name", caption = "Your full name", disabled = m.disabled)
		e := text_input(gtx, &m.name)
		m.edited ||= e.changed
		if e.submitted {
			m.submits += 1
		}
		form_control_close(gtx, &f)
	}
	if text_input(gtx, &m.search, "Search", leading = .Search, action = .X_Circle_Fill, action_name = "Clear").action {
		m.actions += 1
	}
	text_input(gtx, &m.limited, name = "Limited", character_limit = 5)
	textarea(gtx, &m.bio, name = "Bio", auto_size = true, max_height = 4 * FIELD_LINE + 2 * TEXTAREA_PAD)
	text_input(gtx, &m.name, name = "Small", size = .Small)
	text_input(gtx, &m.name, name = "Large", size = .Large)
}

@(private = "file")
fields_probe :: proc(p: ^ui.Probe, m: ^Forms_Model) {
	ui.probe_init(p, fields, m, {800, 900}, allocator = context.temp_allocator)
}

@(test)
test_a_text_input_edits_submits_and_ignores_input_when_disabled :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	fields_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Name"))
	ui.probe_type(&p, "Mona")
	testing.expect_value(t, ui.text_string(&m.name), "Mona")
	testing.expect(t, m.edited)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.submits, 1)
	testing.expect_value(t, ui.text_string(&m.name), "Mona") // Enter is not text
	m.disabled = true // the form control disables its input
	ui.probe_frame(&p)
	testing.expect(t, !ui.probe_click(&p, "Name"))
	ui.probe_type(&p, "!")
	testing.expect_value(t, ui.text_string(&m.name), "Mona")
}

@(test)
test_a_form_label_focuses_its_input :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	fields_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Name label"))
	ui.probe_frame(&p) // the focus request lands at the next route
	ui.probe_type(&p, "Hubot")
	testing.expect_value(t, ui.text_string(&m.name), "Hubot")
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(report, `text field "Name" value "Hubot" desc "Your full name"`), report)
}

@(test)
test_text_input_geometry_follows_the_wrapper_css :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	fields_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	zero := text_width(&p, "0", field_style(.Medium))
	name := ui.probe_bounds(&p, "Name")
	testing.expect_value(t, name.h, tok.CONTROL_MEDIUM_SIZE)
	// No visuals: 12px of input padding each side of 20ch, in the border.
	testing.expect_value(t, name.w, 2 * FIELD_BORDER + 2 * tok.BASE_SIZE_12 + 20 * zero)
	// A leading visual: the wrapper's 8px, the 16px icon and its 8px
	// margin; an action: 8px, 4px, the 24px action and 4px.
	search := ui.probe_bounds(&p, "Search")
	testing.expect_value(t, search.w, 2 * FIELD_BORDER + 8 + 16 + 8 + 20 * zero + 8 + 4 + 24 + 4)
	clear_ := ui.probe_bounds(&p, "Clear")
	testing.expect_value(t, clear_, ops.Rect{search.x + search.w - FIELD_BORDER - 4 - 24, search.y + 4, 24, 24})
	testing.expect_value(t, ui.probe_bounds(&p, "Small").h, tok.CONTROL_SMALL_SIZE)
	testing.expect_value(t, ui.probe_bounds(&p, "Large").h, tok.CONTROL_LARGE_SIZE)
	// The character counter adds its row under the well, before the
	// column's 16px gap to the next field.
	limited := ui.probe_bounds(&p, "Limited")
	testing.expect_value(t, limited.h, tok.CONTROL_MEDIUM_SIZE)
	testing.expect(t, testutil.near(ui.probe_bounds(&p, "Bio").y, limited.y + limited.h + counter_height() + 16))
}

@(test)
test_the_trailing_action_activates_without_editing :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	fields_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	testing.expect(t, ui.probe_click(&p, "Clear"))
	testing.expect_value(t, m.actions, 1)
	ui.probe_key(&p, .Enter) // its own tab stop: focused, Enter activates it
	testing.expect_value(t, m.actions, 2)
	ui.probe_type(&p, "x")
	testing.expect_value(t, ui.text_string(&m.search), "") // the field was never focused
}

@(private = "file")
count_strokes :: proc(p: ^ui.Probe, c: ops.Color, width: f32) -> (n: int) {
	for op in p.scene.ops {
		if s, ok := op.(ops.Stroke); ok && s.style.width == width {
			if got, solid := s.paint.(ops.Color); solid && got == c {
				n += 1
			}
		}
	}
	return
}

@(test)
test_a_field_rings_on_any_focus_in_its_status_colour :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	fields_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	accent := color(.Border_Color_Accent_Emphasis)
	testing.expect_value(t, count_strokes(&p, accent, 2), 0)
	ui.probe_click(&p, "Name") // a pointer focus, not the keyboard's
	ui.probe_frame(&p)
	testing.expect_value(t, count_strokes(&p, accent, 2), 1)
	// Over its limit a field is in error: its ring turns danger.
	ui.probe_click(&p, "Limited")
	ui.probe_type(&p, "123456")
	testing.expect_value(t, count_strokes(&p, accent, 2), 0)
	testing.expect_value(t, count_strokes(&p, color(.Control_Border_Color_Danger), 2), 1)
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(report, `text field "Limited" value "123456" desc "You can enter up to 5 characters" invalid`), report)
	testing.expect_value(t, ui.text_string(&m.limited), "123456") // never blocked
	testing.expect_value(t, ui.probe_bounds(&p, "Limited").h, tok.CONTROL_MEDIUM_SIZE)
}

@(test)
test_a_character_counter_counts_utf16_units :: proc(t: ^testing.T) {
	gtx := ui.Ctx{allocator = context.temp_allocator}
	defer free_all(context.temp_allocator)
	testing.expect_value(t, utf16_len("a😀é"), 4) // the emoji is a surrogate pair
	msg, over := counter_message(&gtx, 4, 5)
	testing.expect_value(t, msg, "1 character remaining")
	testing.expect(t, !over)
	msg, over = counter_message(&gtx, 7, 5)
	testing.expect_value(t, msg, "2 characters over")
	testing.expect(t, over)
	msg, _ = counter_message(&gtx, 6, 5)
	testing.expect_value(t, msg, "1 character over")
}

@(test)
test_a_textarea_grows_by_line_with_auto_size_up_to_its_maximum :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	fields_probe(&p, &m)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	line_h :: proc(lines: int) -> f32 {
		return f32(lines) * FIELD_LINE + 2 * TEXTAREA_PAD + 2 * FIELD_BORDER
	}
	testing.expect_value(t, ui.probe_bounds(&p, "Bio").h, line_h(1))
	ui.probe_click(&p, "Bio")
	ui.probe_type(&p, "one")
	ui.probe_key(&p, .Enter)
	ui.probe_type(&p, "two")
	testing.expect_value(t, ui.text_string(&m.bio), "one\ntwo")
	testing.expect_value(t, ui.probe_bounds(&p, "Bio").h, line_h(2))
	for _ in 0 ..< 4 {
		ui.probe_key(&p, .Enter)
	}
	testing.expect_value(t, ui.probe_bounds(&p, "Bio").h, line_h(4)) // max_height holds; the text scrolls
	ui.probe_key(&p, .Up)
	ui.probe_type(&p, "!")
	testing.expect_value(t, ui.text_string(&m.bio), "one\ntwo\n\n\n!\n") // Up moved one line, not to the start
}

@(private = "file")
resizable_textareas :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx)
	defer ui.close(&col)
	textarea(gtx, &m.bio, name = "Notes")
	textarea(gtx, &m.search, name = "Fixed", rows = 2, resize = .None)
}

@(test)
test_a_textarea_is_rows_tall_and_its_grip_resizes_it :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	ui.probe_init(&p, resizable_textareas, &m, {800, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	notes := ui.probe_bounds(&p, "Notes")
	testing.expect_value(t, notes.h, 7 * FIELD_LINE + 2 * TEXTAREA_PAD + 2 * FIELD_BORDER) // 166
	zero := text_width(&p, "0", field_style(.Medium))
	testing.expect_value(t, notes.w, 30 * zero + 2 * TEXTAREA_PAD + 2 * FIELD_BORDER)
	testing.expect(t, ui.probe_drag(&p, "Notes resize", 40, 30))
	ui.probe_frame(&p)
	grown := ui.probe_bounds(&p, "Notes")
	testing.expect_value(t, grown.w, notes.w + 40)
	testing.expect_value(t, grown.h, notes.h + 30)
	testing.expect(t, !ui.probe_tagged(&p, "Fixed resize")) // resize none has no grip
	ui.probe_move(&p, grown.x + grown.w - 4, grown.y + grown.h - 4)
	ui.probe_move(&p, grown.x + grown.w + 20, grown.y + grown.h + 20) // hovering moves nothing
	testing.expect_value(t, ui.probe_bounds(&p, "Notes"), grown)
}

@(private = "file")
SIZES_OPTIONS := [?]Select_Option{{label = "Small"}, {label = "Medium", disabled = true}, {label = "Large"}, {label = "Extra large"}}

@(private = "file")
selects :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx, gap = 16)
	defer ui.close(&col)
	select(gtx, SIZES_OPTIONS[:], &m.choice, "Pick a size", name = "Size")
	off := 0
	select(gtx, SIZES_OPTIONS[:], &off, name = "Off", state = .Disabled)
}

@(test)
test_a_select_changes_by_keys_and_by_its_list :: proc(t: ^testing.T) {
	m := Forms_Model {
		choice = -1,
	}
	p: ui.Probe
	ui.probe_init(&p, selects, &m, {600, 600}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	before := ui.probe_bounds(&p, "Size")
	// As wide as its widest label, with its 1px start margin and 12px sides.
	st := field_style(.Medium)
	testing.expect_value(t, before.w, FIELD_BORDER + 1 + 12 + text_width(&p, "Extra large", st) + 12 + FIELD_BORDER)
	testing.expect(t, ui.probe_click(&p, "Size")) // opens
	testing.expect(t, ui.probe_tagged(&p, "Large"))
	testing.expect(t, ui.probe_click(&p, "Large"))
	testing.expect_value(t, m.choice, 2)
	testing.expect(t, !ui.probe_tagged(&p, "Large")) // chosen: closed
	testing.expect_value(t, ui.probe_bounds(&p, "Size"), before) // the width never follows the choice
	ui.probe_key(&p, .Up) // closed: Up changes the choice, past the disabled one
	testing.expect_value(t, m.choice, 0)
	ui.probe_key(&p, .Up)
	testing.expect_value(t, m.choice, 0) // stays at the end
	ui.probe_key(&p, .E)
	testing.expect_value(t, m.choice, 3) // a letter jumps
	ui.probe_key(&p, .Space)
	testing.expect(t, ui.probe_tagged(&p, "Small"))
	ui.probe_key(&p, .Down) // open: Down moves the highlight, not the choice
	testing.expect_value(t, m.choice, 3)
	ui.probe_key(&p, .Escape)
	testing.expect(t, !ui.probe_tagged(&p, "Small"))
	testing.expect_value(t, m.choice, 3)
	ui.probe_key(&p, .Enter)
	ui.probe_key(&p, .Up)
	ui.probe_key(&p, .Enter)
	testing.expect_value(t, m.choice, 2)
	testing.expect(t, !ui.probe_click(&p, "Off")) // disabled: no area
}

@(private = "file")
validated_forms :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx, gap = 16, align = .Start)
	defer ui.close(&col)
	{
		f := form_control_open(gtx, "Email", caption = "Never shared", validation = "Enter a whole address", required = true)
		text_input(gtx, &m.name)
		form_control_close(gtx, &f)
	}
	{
		f := form_control_open(gtx, "Hidden", hide_label = true)
		text_input(gtx, &m.search)
		form_control_close(gtx, &f)
	}
}

@(test)
test_a_form_control_lays_out_label_input_message_caption_and_names_the_input :: proc(t: ^testing.T) {
	m: Forms_Model
	defer forms_model_destroy(&m)
	p: ui.Probe
	ui.probe_init(&p, validated_forms, &m, {600, 400}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	label := ui.probe_bounds(&p, "Email label")
	input := ui.probe_bounds(&p, "Email")
	message := ui.probe_bounds(&p, "Enter a whole address")
	caption_ := ui.probe_bounds(&p, "Never shared")
	testing.expect_value(t, label.y, 0)
	testing.expect_value(t, input.y, label.h + FORM_GAP)
	testing.expect_value(t, message.y, input.y + input.h + FORM_GAP)
	testing.expect_value(t, message.h, VALIDATION_LINE)
	testing.expect_value(t, caption_.y, message.y + message.h + FORM_GAP) // the caption after the message
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(report, `text field "Email" desc "Enter a whole address Never shared" required invalid`), report)
	testing.expect(t, strings.contains(report, `text field "Hidden"`), report) // named, though nothing is drawn
	testing.expect(t, !ui.probe_tagged(&p, "Hidden label"))
	testing.expect_value(t, ui.probe_bounds(&p, "Hidden").y, caption_.y + caption_.h + 16)
}

@(private = "file")
VIEW_SEGMENTS := [?]Segment{{label = "Preview"}, {label = "Raw"}, {label = "Blame", disabled = true}, {label = "Grid", icon = .Apps, icon_only = true}}

@(private = "file")
segments_view :: proc(gtx: ^ui.Ctx, user: rawptr) {
	m := (^Forms_Model)(user)
	col := ui.column_open(gtx, align = .Start)
	defer ui.close(&col)
	if segmented_control(gtx, VIEW_SEGMENTS[:], &m.view, "View") {
		m.view_presses += 1
	}
}

@(test)
test_a_segmented_control_selects_and_keeps_each_segment_s_width :: proc(t: ^testing.T) {
	m: Forms_Model
	p: ui.Probe
	ui.probe_init(&p, segments_view, &m, {800, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)

	semi := segment_style(.Medium, true)
	raw := ui.probe_bounds(&p, "Raw")
	// The semibold width, 12px each side and the content's 1px border.
	testing.expectf(t, testutil.near(raw.w, text_width(&p, "Raw", semi) + 2 * SEGMENT_PAD + 2), "Raw is %v wide", raw.w)
	testing.expect_value(t, raw.h, tok.CONTROL_MEDIUM_SIZE) // overlapping the track's border
	testing.expect_value(t, ui.probe_bounds(&p, "Grid").w, SEGMENT_ICON_WIDTH)
	testing.expect_value(t, ui.probe_bounds(&p, "Preview").x, 0)
	testing.expect(t, testutil.near(raw.x, ui.probe_bounds(&p, "Preview").w + 1)) // 1px for the separator
	grid := ui.probe_bounds(&p, "Grid")
	testing.expect(t, testutil.near(ui.probe_bounds(&p, "View").w, grid.x + grid.w)) // the last ends on the track's edge
	testing.expect(t, ui.probe_click(&p, "Raw"))
	testing.expect_value(t, m.view, 1)
	testing.expect_value(t, ui.probe_bounds(&p, "Raw"), raw) // selected, the same width
	testing.expect(t, ui.probe_click(&p, "Raw"))
	testing.expect_value(t, m.view_presses, 2) // reported again when already selected
	testing.expect(t, !ui.probe_click(&p, "Blame"))
	testing.expect_value(t, m.view, 1)
	testing.expect(t, ui.probe_click(&p, "Preview"))
	ui.probe_key(&p, .Right) // arrows do nothing
	testing.expect_value(t, m.view, 0)
	report := ui.probe_semantics(&p, context.temp_allocator)
	testing.expect(t, strings.contains(report, `list "View"`), report)
	testing.expect(t, strings.contains(report, `button "Preview" selected`), report)
}

// weighted_shaper is the stub shaper with every face wider than the one
// before it: face 2, the semibold, sets text half again as wide as face 0.
@(private = "file")
weighted_shaper :: proc() -> ui.Shaper {
	return {
		shape = proc(data: rawptr, font: ops.Font_Id, size: f32, text: string, allocator: mem.Allocator) -> ops.Glyph_Run {
			run := ui.stub_shaper().shape(data, font, size, text, allocator)
			k := 1 + 0.25 * f32(font)
			for &g in run.glyphs {
				g.x *= k
			}
			run.advance *= k
			return run
		},
		metrics = ui.stub_shaper().metrics,
	}
}

@(test)
test_a_segment_reserves_its_label_s_semibold_width :: proc(t: ^testing.T) {
	m: Forms_Model
	p: ui.Probe
	ui.probe_init(&p, segments_view, &m, {800, 200}, allocator = context.temp_allocator)
	defer ui.probe_destroy(&p)
	defer free_all(context.temp_allocator)
	use_fonts({normal = 0, medium = 1, semibold = 2})
	defer loaded = false
	p.shaper = weighted_shaper()
	ui.probe_frame(&p)

	gtx := ui.Ctx{shaper = p.shaper, allocator = context.temp_allocator}
	semi := segment_style(.Medium, true)
	bold := design.shape_style(&gtx, "Raw", semi, font_for(&gtx, semi.weight)).width
	testing.expect(t, bold > design.shape_style(&gtx, "Raw", segment_style(.Medium, false), 0).width)
	want := bold + 2 * SEGMENT_PAD + 2
	raw := ui.probe_bounds(&p, "Raw") // unselected, set in normal weight
	testing.expectf(t, testutil.near(raw.w, want), "Raw is %v wide, want %v", raw.w, want)
	testing.expect(t, ui.probe_click(&p, "Raw"))
	raw = ui.probe_bounds(&p, "Raw") // selected, set in semibold: the same box
	testing.expectf(t, testutil.near(raw.w, want), "selected Raw is %v wide, want %v", raw.w, want)
}
