package primer

import "core:fmt"
import "core:strings"
import "core:unicode"
import "core:unicode/utf8"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// The text fields: TextInput, Textarea and Select, which share
// TextInputWrapper's well (text-input.json, textarea.json, select.json;
// TextInputWrapper.module.css at the kit's release). Editing is jm:ui's
// (ui.Text_State, ui.text_edit, ui.text_edit_lines,
// ui.text_follow_pointer); the caret, placeholder, scrolling and
// Select's list, which a browser supplies, are drawn here.

// Combobox is what a text field that drives a list of options says to a
// reader (aria-expanded, aria-activedescendant): whether the list shows,
// and the option it points at while keeping focus itself.
Combobox :: struct {
	expanded: bool,
	active:   ops.Area_Id,
}

// combobox_semantics turns a field's semantics into a combo box's when
// combo is set.
@(private)
combobox_semantics :: proc(s: ^ops.Semantics, combo: Maybe(Combobox)) {
	cb, ok := combo.?
	if !ok {
		return
	}
	s.role = .Combo_Box
	s.states += {.Expandable} + design.state_if(cb.expanded, {.Expanded})
	s.active_descendant = cb.active
}

// Field_Edit is what one frame of a text field did.
Field_Edit :: struct {
	changed:   bool, // the text is not what it was
	submitted: bool, // Enter while focused (a TextInput only)
	action:    bool, // the trailing action was activated
	focused:   bool,
	id:        ops.Area_Id, // the field's area, for ui.focus_request
}

// FIELD_BORDER is the well's border (--borderWidth-thin).
@(private)
FIELD_BORDER :: tok.BORDER_WIDTH_THIN

// FIELD_LINE is a field's text line: 20px at every size
// (TextInputWrapper.module.css:7,110).
@(private)
FIELD_LINE :: tok.BASE_SIZE_20

// FIELD_CARET_W is the caret's width, 1px: this package's choice, as the
// browser draws the caret.
@(private)
FIELD_CARET_W :: f32(1)

// field_style is a field's text at size: medium body size, small body
// at small, on FIELD_LINE (TextInputWrapper.module.css:5-7,108-110).
@(private)
field_style :: proc(size: Field_Size) -> tok.Type_Style {
	return {weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = size == .Small ? tok.TEXT_BODY_SIZE_SMALL : tok.TEXT_BODY_SIZE_MEDIUM, line_height = FIELD_LINE}
}

// field_height is a field's height: 28px and 32px minimums, 40px fixed
// (TextInputWrapper.module.css:3,101,116). Nothing in a field is taller
// than its line, so the minimum is the height.
@(private)
field_height :: proc(size: Field_Size) -> f32 {
	switch size {
	case .Small:
		return tok.CONTROL_SMALL_SIZE
	case .Large:
		return tok.CONTROL_LARGE_SIZE
	case .Medium:
	}
	return tok.CONTROL_MEDIUM_SIZE
}

// field_ch is the width of "0" in st, CSS's ch unit: what a native field's
// default width is counted in (text-input.json notes: the browser's
// default is about 20 average characters).
@(private)
field_ch :: proc(gtx: ^ui.Ctx, st: tok.Type_Style) -> f32 {
	return design.shape_style(gtx, "0", st, font_for(gtx, st.weight)).width
}

// Well is how a field's well looks this frame.
@(private)
Well :: struct {
	focused, disabled, contrast: bool,
	status:                      Validation_Status,
}

// well_border is the well's border colour (TextInputWrapper.module.css
// :8-83): disabled, then error (danger, or the control's danger border
// when focused), success (--bgColor-success-emphasis, a background
// token: text-input.json notes), focused (accent), else rest.
@(private)
well_border :: proc(w: Well) -> tok.Role {
	switch {
	case w.disabled:
		return .Control_Border_Color_Disabled
	case w.status == .Error:
		return w.focused ? .Control_Border_Color_Danger : .Border_Color_Danger_Emphasis
	case w.status == .Success:
		return .Bg_Color_Success_Emphasis
	case w.focused:
		return .Border_Color_Accent_Emphasis
	}
	return .Control_Border_Color_Rest
}

// paint_well draws a field's well in box: its fill (--bgColor-default,
// --bgColor-inset for contrast, the disabled control fill), the 1px inset
// top shadow unless disabled, and its border.
@(private)
paint_well :: proc(gtx: ^ui.Ctx, box: ops.Rect, w: Well) {
	rr := ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM}
	fill := tok.Role.Bg_Color_Default
	if w.contrast {
		fill = .Bg_Color_Inset
	}
	if w.disabled {
		fill = .Control_Bg_Color_Disabled
	}
	ops.fill(gtx.scene, rr, color(fill))
	if !w.disabled {
		b := FIELD_BORDER
		paint_shadow(gtx, {{box.x + b, box.y + b, box.w - 2 * b, box.h - 2 * b}, rr.radius - b}, tok.SHADOW_INSET)
	}
	stroke_inside(gtx, rr, color(well_border(w)), FIELD_BORDER)
}

// paint_well_focus draws a focused well's ring: 2px of the border's
// colour at offset -1px, over the border and 1px outside it, on any
// focus, not only the keyboard's (:focus-within, TextInputWrapper.module
// .css:35-40,72-77).
@(private)
paint_well_focus :: proc(gtx: ^ui.Ctx, box: ops.Rect, w: Well) {
	if !w.focused || w.disabled {
		return
	}
	ring := w.status == .Error ? tok.Role.Control_Border_Color_Danger : .Border_Color_Accent_Emphasis
	c := design.Control {
		focused = true,
	}
	design.paint_focus_ring(gtx, c, {box, tok.BORDER_RADIUS_MEDIUM}, {tok.BORDER_WIDTH_THICK, -FIELD_BORDER, color(ring)})
}

// field_live is c's focus as a field shows it: a forced Pressed reads as
// focused, since a press focuses a field.
@(private)
field_focused :: proc(c: Control) -> bool {
	return (c.focused || c.state == .Pressed) && !c.disabled
}

// utf16_len is s's length as String.length counts it, in UTF-16 code
// units, which a character limit counts (text-input.json behaviour).
@(private)
utf16_len :: proc(s: string) -> (n: int) {
	for r in s {
		n += r >= 0x10000 ? 2 : 1
	}
	return
}

// counter_message is the character counter's words for length against
// limit, and whether it is over (character-counter.ts:24-43).
@(private)
counter_message :: proc(gtx: ^ui.Ctx, length, limit: int) -> (msg: string, over: bool) {
	left := limit - length
	if left >= 0 {
		return fmt.aprintf("%d %s remaining", left, left == 1 ? "character" : "characters", allocator = gtx.allocator), false
	}
	return fmt.aprintf("%d %s over", -left, left == -1 ? "character" : "characters", allocator = gtx.allocator), true
}

// limit_message is what describes a field with a character limit
// (TextInput.tsx:280-282).
@(private)
limit_message :: proc(gtx: ^ui.Ctx, limit: int) -> string {
	return fmt.aprintf("You can enter up to %d %s", limit, limit == 1 ? "character" : "characters", allocator = gtx.allocator)
}

// COUNTER_ICON is the over-limit icon's size (TextInput.tsx:288).
@(private)
COUNTER_ICON :: f32(16)

// counter_height is the character counter's row: small body text on its
// line (Text.module.css:2-5).
@(private)
counter_height :: proc() -> f32 {
	return style(.Body_Small).line_height
}

// paint_counter_row draws the character counter at y: the message in
// --fgColor-muted, or the 16px AlertFill and the message in
// --fgColor-danger, 4px apart (TextInput.module.css:1-10). It is hidden
// from a reader, which hears the limit in the field's description.
@(private)
paint_counter_row :: proc(gtx: ^ui.Ctx, msg: string, over: bool, y: f32) {
	st := style(.Body_Small)
	t := design.shape_style(gtx, msg, st, font_for(gtx, st.weight))
	fg := color(over ? .Fg_Color_Danger : .Fg_Color_Muted)
	x: f32
	if over {
		icon(gtx, .Alert_Fill, {0, y + (st.line_height - COUNTER_ICON) / 2}, COUNTER_ICON, fg)
		x = COUNTER_ICON + tok.CONTROL_XSMALL_GAP
	}
	draw_text(gtx, t, {x, y}, fg)
}

// Loader_Position is where a loading TextInput's spinner goes: auto is
// the trailing slot unless there is a leading visual (TextInput.tsx
// :142-145).
Loader_Position :: enum u8 {
	Auto,
	Leading,
	Trailing,
}

// Field_Visual is a TextInput's leading or trailing visual: a 16px octicon or
// short text, in --fgColor-muted.
@(private)
Field_Visual :: struct {
	ic:   Icon,
	text: Text,
	w:    f32, // 0 when there is none
}

@(private)
shape_field_visual :: proc(gtx: ^ui.Ctx, ic: Icon, s: string, st: tok.Type_Style) -> (v: Field_Visual) {
	v.ic = ic
	if ic != .None {
		v.w = BUTTON_ICON
	} else if s != "" {
		v.text = design.shape_style(gtx, s, st, font_for(gtx, st.weight))
		v.w = v.text.width
	}
	return
}

// paint_visual_slot draws v in its slot at x, or a spinner there while
// spinning: a 16px one in an empty slot, else one as tall as the line
// and no wider than the visual, over the visual it hides
// (TextInputInnerVisualSlot.tsx:42-60).
@(private)
paint_visual_slot :: proc(gtx: ^ui.Ctx, v: Field_Visual, x, h: f32, spinning: bool, fg: ops.Color) {
	if spinning {
		side := BUTTON_ICON
		if v.w > 0 && v.ic == .None {
			side = min(v.w, FIELD_LINE)
		}
		w := v.w > 0 ? v.w : BUTTON_ICON
		paint_spinner(gtx, {x + (w - side) / 2, (h - side) / 2}, side, fg)
		return
	}
	if v.ic != .None {
		icon(gtx, v.ic, {x, (h - BUTTON_ICON) / 2}, BUTTON_ICON, fg)
	} else if v.w > 0 {
		draw_text(gtx, v.text, {x, (h - v.text.height) / 2}, fg)
	}
}

// Input_Row is a TextInput's horizontal layout: where its visuals,
// text and action sit, from the CSS's padding and margin rules.
@(private)
Input_Row :: struct {
	lead_x, text_x, text_r, trail_x, action_x: f32,
	lead, trail, action:                      bool, // which slots show
	lead_flag, trail_flag:                    bool, // data-leading-visual, data-trailing-visual
}

// INNER_ACTION is the trailing action's square per size
// (--inner-action-size, TextInputWrapper.module.css:96-114).
@(private)
INNER_ACTION := [Field_Size]f32 {
	.Small  = tok.BASE_SIZE_20,
	.Medium = tok.BASE_SIZE_24,
	.Large  = tok.BASE_SIZE_28,
}

// input_row lays a TextInput of width w out (TextInputWrapper.module.css
// :152-221, TextInputInnerAction.module.css:33-38): the container pads
// 8px (12px large) before a leading visual and after a trailing one with
// no action; every child but the last has 8px after it; the action 4px
// each side; the input pads 12px each side with no visuals, 8px on a
// side whose end has none, nothing beside a visual.
@(private)
input_row :: proc(w: f32, size: Field_Size, lead, trail: Field_Visual, lead_spin, trail_spin, trail_slot, action: bool) -> (r: Input_Row) {
	gap := tok.BASE_SIZE_8
	side := size == .Large ? tok.BASE_SIZE_12 : tok.BASE_SIZE_8
	r.lead = lead.w > 0 || lead_spin
	r.trail = trail_slot
	r.action = action
	r.lead_flag = r.lead
	r.trail_flag = trail.w > 0 || trail_spin
	lead_w := lead.w > 0 ? lead.w : BUTTON_ICON
	trail_w := trail.w > 0 ? trail.w : BUTTON_ICON
	x := FIELD_BORDER
	if r.lead_flag {
		x += side
		r.lead_x = x
		x += lead_w + gap
	}
	pad_l, pad_r: f32
	switch {
	case !r.lead_flag && !r.trail_flag && !action:
		pad_l, pad_r = tok.BASE_SIZE_12, tok.BASE_SIZE_12
	case !r.lead_flag:
		pad_l = gap
	case !r.trail_flag && !action:
		pad_r = gap
	}
	r.text_x = x + pad_l
	xr := w - FIELD_BORDER
	if r.trail_flag && !action {
		xr -= side
	}
	if action {
		xr -= tok.BASE_SIZE_4
		r.action_x = xr - INNER_ACTION[size]
		xr = r.action_x - tok.BASE_SIZE_4
	}
	if r.trail {
		if action {
			xr -= gap
		}
		r.trail_x = xr - trail_w
		xr = r.trail_x
	}
	if r.trail || action {
		xr -= gap
	}
	r.text_r = xr - pad_r
	return
}

// Input_Scroll is a TextInput's horizontal scroll, kept so the caret
// stays in view.
@(private)
Input_Scroll :: struct {
	x: f32,
}

// TEXT_INPUT_COLUMNS is a TextInput's default width in ch: the browser's
// default size (text-input.json notes).
TEXT_INPUT_COLUMNS :: 20

// text_input is Primer's TextInput (text-input.json): a single-line
// field in the bordered well. s is the caller's buffer; placeholder
// shows in --fgColor-muted while it is empty. leading and trailing are
// 16px octicons inside the well, or leading_text and trailing_text short
// text (a unit, a prefix), in --fgColor-muted. action is a trailing
// invisible icon button named action_name, its own tab stop; Field_Edit
// .action reports it. loading shows a spinner where loader says and
// marks the field busy. character_limit > 0 adds the "N characters
// remaining" counter under the well and, past it, the error state;
// typing is never blocked. validation borders the field (a FormControl's
// validation sets it too). block fills the width offered; else width,
// else 20ch of the field's text plus its insets. contrast fills the well
// with --bgColor-inset. name is the accessible name and tag, else the
// open FormControl's label, else the placeholder. The ring shows
// whenever the field has focus, from a press or a key; there is no hover
// state. Typing edits s; Enter sets submitted. combobox makes it a combo
// box to a reader: one whose list of options SelectPanel or Autocomplete
// draws.
//
// secret makes it a password field (TextInput type="password"): it shows a
// bullet per character, its text cannot be copied or cut, and a reader is
// told it is a password field and how long, never what it holds.
//
// Departures: the other native input types (email, number, date) and
// monospace are not offered (the kit's fonts have no monospace face); the action's tooltip and the debounced live
// announcement of the remaining count are not drawn, as jm:ui has neither
// tooltips nor live regions yet; the coarse-pointer 44px action target
// is not enlarged.
text_input :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	placeholder := "",
	size := Field_Size.Medium,
	leading := Icon.None,
	trailing := Icon.None,
	leading_text := "",
	trailing_text := "",
	action := Icon.None,
	action_name := "",
	loading := false,
	loader := Loader_Position.Auto,
	character_limit := 0,
	validation := Validation_Status.None,
	block := false,
	contrast := false,
	required := false,
	width: f32 = 0,
	name := "",
	combobox: Maybe(Combobox) = nil,
	secret := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Field_Edit) {
	p := ui.widget_open(gtx, key, loc)
	fc := field_context(gtx, p.id, name, validation, required, state)
	st := field_style(size)
	ui.text_clamp(s)
	lead := shape_field_visual(gtx, leading, leading_text, st)
	trail := shape_field_visual(gtx, trailing, trailing_text, st)
	lead_spin := loading && (loader == .Leading || (loader == .Auto && lead.w > 0))
	trail_spin := loading && !lead_spin
	// The trailing slot shows while loading even when its spinner is
	// the leading one, hidden but keeping its 16px (TextInputInner
	// VisualSlot.tsx:23-25: it renders whenever loading is a boolean).
	row := input_row(0, size, lead, trail, lead_spin, trail_spin, trail.w > 0 || loading, action != .None)
	h := field_height(size)
	natural := row.text_x + TEXT_INPUT_COLUMNS * field_ch(gtx, st) - row.text_r // text_r measured from 0 is negative
	cs := gtx.constraints
	w := natural
	switch {
	case block && ui.is_finite(cs.max.x):
		w = cs.max.x
	case width > 0:
		w = width
	}
	box_sz := ui.constrain(cs, {w, h})
	box_sz.y = max(box_sz.y, h)
	row = input_row(box_sz.x, size, lead, trail, lead_spin, trail_spin, trail.w > 0 || loading, action != .None)
	box := ops.Rect{0, 0, box_sz.x, box_sz.y}
	c := control(gtx, p.id, box, fc.state)
	inner := max(row.text_r - row.text_x, 0)
	sc := c.st != nil ? ui.widget_data(gtx, p.id, Input_Scroll) : nil
	if c.st != nil {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press, .Move, .Release:
				input_pointer(gtx, s, e, {e.pos.x - row.text_x + sc.x, 0}, st, secret)
			case .Blur:
				ui.text_compose_end(s)
			case .Text, .Paste, .Compose:
				r.changed |= ui.text_edit(gtx, s, p.id, e, input_stops(gtx, s, st, secret), secret = secret)
			case .Key:
				if e.key == .Enter {
					r.submitted = true
				} else {
					r.changed |= ui.text_edit(gtx, s, p.id, e, input_stops(gtx, s, st, secret), secret = secret)
				}
			}
		}
		ui.text_claim_keys(gtx, s, p.id)
	}
	// What shows: the text, or for a secret its bullets, caret and all; a
	// secret never composes, so its view is never spliced with a preedit.
	shown := s
	if secret {
		view := ui.secret_view(s, gtx.allocator)
		shown = &view
	}
	str := string(shown.buf[:])
	display := ui.text_display(shown, gtx.allocator)
	length := utf16_len(string(s.buf[:]))
	msg, over := "", false
	if character_limit > 0 {
		msg, over = counter_message(gtx, length, character_limit)
	}
	status := over ? Validation_Status.Error : fc.status
	r.focused = field_focused(c)
	r.id = p.id
	t := design.layout_style(gtx, display.text, st, font_for(gtx, st.weight))
	_, caret := ui.paragraph_caret(t, display.caret)
	scroll: f32
	if sc != nil {
		sc.x = ui.text_scroll(sc.x, t.width + FIELD_CARET_W, caret, FIELD_CARET_W, inner)
		scroll = sc.x
	}

	well := Well{r.focused, c.disabled, contrast, status}
	paint_well(gtx, box, well)
	visual_fg := color(.Fg_Color_Muted)
	ops.clip_push(gtx.scene, ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM})
	if row.lead {
		paint_visual_slot(gtx, lead, row.lead_x, box.h, lead_spin, visual_fg)
	}
	if row.trail && (trail.w > 0 || trail_spin) {
		paint_visual_slot(gtx, trail, row.trail_x, box.h, trail_spin, visual_fg)
	}
	text_y := (box.h - FIELD_LINE) / 2
	fg := color(c.disabled ? .Fg_Color_Disabled : .Fg_Color_Default)
	ops.clip_push(gtx.scene, ops.Rect{row.text_x, 0, inner, box.h})
	if len(display.text) > 0 {
		design.draw_paragraph(gtx, t, {row.text_x - scroll, text_y}, fg, selection_paint(shown, r.focused))
		draw_preedit(gtx, t, {row.text_x - scroll, text_y}, display, fg)
	} else if placeholder != "" {
		draw_text(gtx, design.shape_style(gtx, placeholder, st, font_for(gtx, st.weight)), {row.text_x, text_y}, color(.Fg_Color_Muted))
	}
	if r.focused && c.st != nil {
		ops.fill(gtx.scene, ops.Rect{row.text_x + caret - scroll, text_y + 2, FIELD_CARET_W, FIELD_LINE - 4}, fg)
	}
	if state == .Live {
		ui.text_caret(gtx, p.id, ops.Rect{row.text_x, 0, inner, box.h}, row.text_x + caret - scroll, kind = .Password if secret else .Text)
	}
	ops.clip_pop(gtx.scene)
	ops.clip_pop(gtx.scene)
	paint_well_focus(gtx, box, well)
	listen(gtx, c.st, p.id, box, design.EDIT_KINDS, .Text)
	if row.action {
		r.action = inner_action(gtx, &p, action, action_name, {row.action_x, (box.h - INNER_ACTION[size]) / 2, INNER_ACTION[size], INNER_ACTION[size]}, c.disabled ? .Disabled : fc.state)
	}
	sz := box_sz
	if character_limit > 0 {
		paint_counter_row(gtx, msg, over, box.h)
		sz.y += counter_height()
	}
	tag := fc.name != "" ? fc.name : placeholder
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, tag))
	desc := fc.description
	if character_limit > 0 {
		desc = join_words(gtx, limit_message(gtx, character_limit), desc)
	}
	desc = join_words(gtx, desc, join_words(gtx, leading_text, trailing_text))
	if loading {
		desc = join_words(gtx, desc, "Loading")
	}
	states := design.state_if(c.disabled, {.Disabled}) + design.state_if(fc.required, {.Required}) + design.state_if(status == .Error, {.Invalid}) + design.state_if(loading, {.Busy})
	sem := ops.Semantics{role = .Password_Field if secret else .Text_Field, label = ui.frame_string(gtx, tag), value = ui.frame_string(gtx, str), description = desc, states = states}
	combobox_semantics(&sem, combobox)
	ui.semantics(gtx, &p, sem)
	ui.widget_close(gtx, &p, {sz, text_y + (len(t.lines) > 0 ? t.lines[0].baseline : 0)})
	return
}

// input_stops are a text input's caret stops: the text's own, or for a
// secret every character and no words.
@(private)
input_stops :: proc(gtx: ^ui.Ctx, s: ^ui.Text_State, st: tok.Type_Style, secret: bool) -> ui.Text_Stops {
	return ui.secret_stops(gtx, s) if secret else field_stops(gtx, s, st)
}

// input_pointer follows a press, drag or release on a text input at pt,
// on its bullets for a secret, which move the text's caret to match.
@(private)
input_pointer :: proc(gtx: ^ui.Ctx, s: ^ui.Text_State, e: ui.Event, pt: ops.Point, st: tok.Type_Style, secret: bool) {
	font := font_for(gtx, st.weight)
	if !secret {
		ui.text_follow_pointer(s, design.layout_style(gtx, string(s.buf[:]), st, font), e, pt, field_stops(gtx, s, st))
		return
	}
	view := ui.secret_view(s, gtx.allocator)
	ui.text_follow_pointer(&view, design.layout_style(gtx, string(view.buf[:]), st, font), e, pt, ui.secret_stops(gtx, &view))
	ui.secret_apply(s, &view)
}

// field_stops is s's caret stops in st.
@(private)
field_stops :: proc(gtx: ^ui.Ctx, s: ^ui.Text_State, st: tok.Type_Style) -> ui.Text_Stops {
	return ui.text_stops(gtx, s, font_for(gtx, st.weight), st.size)
}

// inner_action is a TextInput's trailing action at rect: an invisible
// icon button with 2px and 4px of padding, its icon --fgColor-muted
// turning --fgColor-default on hover or focus (TextInputInnerAction
// .module.css:1-18), its own tab stop with Button's keyboard focus
// outline. Returns true when activated.
@(private)
inner_action :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, ic: Icon, name: string, rect: ops.Rect, state: Interaction) -> bool {
	id := ui.id_mix(p.id, 0xac7)
	c := control(gtx, id, rect, state == .Disabled ? .Disabled : state == .Live ? .Live : .Enabled)
	rr := ops.Round_Rect{rect, tok.BORDER_RADIUS_MEDIUM}
	bg := color_for({.Bg_Color_Transparent, .Button_Invisible_Bg_Color_Hover, .Button_Invisible_Bg_Color_Active, .Bg_Color_Transparent}, c)
	if ui.painted(bg) {
		ops.fill(gtx.scene, rr, bg)
	}
	fg := tok.Role.Fg_Color_Muted
	switch {
	case c.disabled:
		fg = .Control_Fg_Color_Disabled
	case c.hovered || c.focused || c.pressed:
		fg = .Fg_Color_Default
	}
	icon(gtx, ic, {rect.x + (rect.w - BUTTON_ICON) / 2, rect.y + (rect.h - BUTTON_ICON) / 2}, BUTTON_ICON, color(fg))
	paint_focus_outline(gtx, c, rr)
	listen(gtx, c.st, id, rect, cursor = .Pointer)
	said := ui.frame_string(gtx, name)
	ops.tag(gtx.scene, id, said)
	ui.part_semantics(gtx, p, id, rect, {role = .Button, label = said, states = design.state_if(c.disabled, {.Disabled})})
	return c.clicked
}

// Textarea_Resize is which axes a Textarea's grip resizes.
Textarea_Resize :: enum u8 {
	Both,
	Horizontal,
	Vertical,
	None,
}

// TEXTAREA_PAD is the text area's padding on every side
// (TextInputWrapper.module.css:42-44).
@(private)
TEXTAREA_PAD :: tok.BASE_SIZE_12

// GRIP is the resize grip's square at the bottom-end corner. The grip is
// the platform's in a browser; its 12px here is this package's choice.
@(private)
GRIP :: f32(12)

// Textarea_View is a Textarea's state between frames: its vertical
// scroll and the size a drag on the grip set, zero until dragged.
@(private)
Textarea_View :: struct {
	scroll: f32,
	w, h:   f32,
	grip:   ui.Drag, // the press on the grip
}

// textarea is Primer's Textarea (textarea.json): a multi-line field in
// TextInput's well, the text padded 12px on every side on 20px lines.
// Its width is cols ch plus padding unless block or width say otherwise;
// its text area is rows lines tall, or with auto_size as tall as its
// wrapped text, bounded by min_height and max_height (the text area's,
// not the well's) when they are > 0; past them the text scrolls, keeping
// the caret in view. The well is at least 32px tall. resize names the
// axes the bottom-end grip drags; disabled has none. Enter inserts a
// newline, Up and Down move between lines, Home and End along one.
// character_limit, validation, contrast, required and name are
// text_input's.
//
// Departures: the grip's look is this package's, two diagonal lines in
// --fgColor-muted, since the browser's is the platform's own; Tab is not
// taken by the field but jm:ui has no traversal for it to move focus on
// with yet.
textarea :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	placeholder := "",
	rows := 7,
	cols := 30,
	resize := Textarea_Resize.Both,
	auto_size := false,
	min_height: f32 = 0,
	max_height: f32 = 0,
	character_limit := 0,
	validation := Validation_Status.None,
	block := false,
	contrast := false,
	required := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Field_Edit) {
	p := ui.widget_open(gtx, key, loc)
	fc := field_context(gtx, p.id, name, validation, required, state)
	st := field_style(.Medium)
	font := font_for(gtx, st.weight)
	ui.text_clamp(s)
	cs := gtx.constraints
	b, pad := FIELD_BORDER, TEXTAREA_PAD
	live := fc.state == .Live
	forced: Textarea_View
	view := live ? ui.widget_data(gtx, p.id, Textarea_View) : &forced
	w := f32(cols) * field_ch(gtx, st) + 2 * pad + 2 * b
	switch {
	case block && ui.is_finite(cs.max.x):
		w = cs.max.x
	case width > 0:
		w = width
	case view.w > 0:
		w = view.w
	}
	w = ui.constrain(cs, {w, 0}).x
	wrap := max(w - 2 * b - 2 * pad, 1)
	str := string(s.buf[:])
	para := design.layout_style(gtx, str, st, font, wrap)
	text_h := textarea_height(len(para.lines), rows, auto_size, view.h, min_height, max_height)
	box := ops.Rect{0, 0, w, max(text_h + 2 * b, tok.CONTROL_MEDIUM_SIZE)}
	c := control(gtx, p.id, box, fc.state)
	text_at := ops.Point{b + pad, b + pad}
	if c.st != nil {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press, .Move, .Release:
				ui.text_follow_pointer(s, para, e, {e.pos.x - text_at.x, e.pos.y - text_at.y + view.scroll}, field_stops(gtx, s, st))
			case .Scroll:
				view.scroll += e.scroll.y * ui.SCROLL_STEP
			case .Blur:
				ui.text_compose_end(s)
			case .Text, .Paste, .Compose, .Key:
				if r.changed {
					para = design.layout_style(gtx, string(s.buf[:]), st, font, wrap)
				}
				r.changed |= ui.text_edit_lines(gtx, s, p.id, e, field_stops(gtx, s, st), para)
			}
		}
		ui.text_claim_keys(gtx, s, p.id)
		if r.changed {
			str = string(s.buf[:])
			para = design.layout_style(gtx, str, st, font, wrap)
			text_h = textarea_height(len(para.lines), rows, auto_size, view.h, min_height, max_height)
			box.h = max(text_h + 2 * b, tok.CONTROL_MEDIUM_SIZE)
		}
	}
	r.focused = field_focused(c)
	r.id = p.id
	// shown splices in an input method's preedit over the selection; para
	// and box.h follow it while composing, so a clause that wraps still
	// fits.
	shown := ui.text_display(s, gtx.allocator)
	if ui.text_composing(s) {
		para = design.layout_style(gtx, shown.text, st, font, wrap)
		text_h = textarea_height(len(para.lines), rows, auto_size, view.h, min_height, max_height)
		box.h = max(text_h + 2 * b, tok.CONTROL_MEDIUM_SIZE)
	}
	view_h := box.h - 2 * b
	line, cx := ui.paragraph_caret(para, shown.caret)
	view.scroll = clamp(view.scroll, 0, max(para.height + 2 * pad - view_h, 0))
	if r.focused {
		view.scroll = ui.text_scroll(view.scroll, para.height + 2 * pad, f32(line) * FIELD_LINE, FIELD_LINE + 2 * pad, view_h)
	}
	msg, over := "", false
	if character_limit > 0 {
		msg, over = counter_message(gtx, utf16_len(str), character_limit)
	}
	status := over ? Validation_Status.Error : fc.status
	well := Well{r.focused, c.disabled, contrast, status}
	paint_well(gtx, box, well)
	fg := color(c.disabled ? .Fg_Color_Disabled : .Fg_Color_Default)
	ops.clip_push(gtx.scene, ops.Rect{b, b, box.w - 2 * b, view_h})
	y := text_at.y - view.scroll
	if len(shown.text) == 0 && placeholder != "" {
		draw_text(gtx, design.shape_style(gtx, placeholder, st, font), {text_at.x, y}, color(.Fg_Color_Muted))
	}
	design.draw_paragraph(gtx, para, {text_at.x, y}, fg, selection_paint(s, r.focused))
	draw_preedit(gtx, para, {text_at.x, y}, shown, fg)
	if r.focused && c.st != nil {
		ops.fill(gtx.scene, ops.Rect{text_at.x + cx, y + f32(line) * FIELD_LINE + 2, FIELD_CARET_W, FIELD_LINE - 4}, fg)
	}
	if live {
		ui.text_caret(gtx, p.id, ops.Rect{b, y + f32(line) * FIELD_LINE, box.w - 2 * b, FIELD_LINE}, text_at.x + cx)
	}
	ops.clip_pop(gtx.scene)
	paint_well_focus(gtx, box, well)
	listen(gtx, c.st, p.id, box, design.EDIT_KINDS, .Text)
	tag := fc.name != "" ? fc.name : placeholder
	if resize != .None && !c.disabled {
		textarea_grip(gtx, &p, view, box, resize, c.st != nil, tag)
	}
	sz := ops.Size{box.w, box.h}
	if character_limit > 0 {
		paint_counter_row(gtx, msg, over, box.h)
		sz.y += counter_height()
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, tag))
	desc := fc.description
	if character_limit > 0 {
		desc = join_words(gtx, limit_message(gtx, character_limit), desc)
	}
	states := design.state_if(c.disabled, {.Disabled}) + design.state_if(fc.required, {.Required}) + design.state_if(status == .Error, {.Invalid})
	ui.semantics(gtx, &p, {role = .Text_Field, label = ui.frame_string(gtx, tag), value = ui.frame_string(gtx, str), description = desc, states = states})
	ui.widget_close(gtx, &p, {sz, text_at.y + (len(para.lines) > 0 ? para.lines[0].baseline : 0)})
	return
}

// textarea_height is the text area's height, padding included: rows
// lines, or the text's lines with auto_size, or the height a drag set,
// then bounded by min and max where they are > 0 (Textarea.tsx:146-154).
@(private)
textarea_height :: proc(lines, rows: int, auto_size: bool, dragged, min_h, max_h: f32) -> f32 {
	h := f32(auto_size ? max(lines, 1) : rows) * FIELD_LINE + 2 * TEXTAREA_PAD
	if dragged > 0 && !auto_size {
		h = dragged
	}
	if min_h > 0 {
		h = max(h, min_h)
	}
	if max_h > 0 {
		h = min(h, max_h)
	}
	return h
}

// textarea_grip draws the resize grip in box's bottom-end corner and,
// when live, lets a drag on it set the size along the axes resize
// allows, no smaller than the well's 32px minimum. It is tagged
// "<name> resize".
@(private)
textarea_grip :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, view: ^Textarea_View, box: ops.Rect, resize: Textarea_Resize, live: bool, name: string) {
	id := ui.id_mix(p.id, 0x9e1b)
	g := ops.Rect{box.w - FIELD_BORDER - GRIP, box.h - FIELD_BORDER - GRIP, GRIP, GRIP}
	if live {
		axis := ui.Drag_Axis.Both
		#partial switch resize {
		case .Horizontal:
			axis = .Horizontal
		case .Vertical:
			axis = .Vertical
		}
		ui.drag_update(&view.grip, ui.events(gtx, id), axis, slop = 0)
		if d := view.grip.delta; d != {} {
			if view.w == 0 {
				view.w = box.w
			}
			if view.h == 0 {
				view.h = box.h - 2 * FIELD_BORDER
			}
			view.w = max(view.w + d.x, 2 * TEXTAREA_PAD + GRIP)
			view.h = max(view.h + d.y, tok.CONTROL_MEDIUM_SIZE - 2 * FIELD_BORDER)
		}
		cursor := ops.Cursor.Resize_NWSE
		#partial switch resize {
		case .Horizontal:
			cursor = .Resize_EW
		case .Vertical:
			cursor = .Resize_NS
		}
		ops.input_area(gtx.scene, id, g, {.Press, .Release, .Move}, cursor)
		ops.tag(gtx.scene, id, strings.concatenate({name, " resize"}, gtx.allocator))
	}
	fg := color(.Fg_Color_Muted)
	for k in 1 ..= 2 {
		d := f32(k) * GRIP / 3 + 1
		ops.stroke(gtx.scene, ui.line(gtx, {g.x + g.w - d, g.y + g.h - 1}, {g.x + g.w - 1, g.y + g.h - d}), fg, {width = 1, cap = .Round})
	}
}

// Select_Option is one of a Select's options: its label, the group
// heading it sits under (Select.OptGroup; a run of options sharing a
// group shows the heading once), and whether it can be chosen.
Select_Option :: struct {
	label:    string,
	group:    string,
	disabled: bool,
}

// SELECT_ARROW is Select's up-and-down arrow, a 16px path in currentColor
// (Select.tsx:16-27).
@(private)
SELECT_ARROW :: "m4.074 9.427 3.396 3.396a.25.25 0 0 0 .354 0l3.396-3.396A.25.25 0 0 0 11.043 9H4.251a.25.25 0 0 0-.177.427ZM4.074 7.47 7.47 4.073a.25.25 0 0 1 .354 0L11.22 7.47a.25.25 0 0 1-.177.426H4.251a.25.25 0 0 1-.177-.426Z"

// SELECT_ROW is the height of a row in Select's list, this package's
// choice for the browser's list: a row on Primer's 4px grid.
@(private)
SELECT_ROW :: tok.BASE_SIZE_24

// Select_State is a Select's list between frames: open, and which row the
// keyboard or pointer has highlighted.
@(private)
Select_State :: struct {
	open:      bool,
	highlight: int,
}

// select is Primer's Select (select.json): one choice from options, in
// TextInput's well with the chosen label (or the placeholder while
// selected^ is -1) inset 12px and Select's up-and-down arrow 4px from
// the end, both in the text colour. It is as wide as its widest option,
// so a choice never changes its width, unless block or width say
// otherwise; long labels run under the arrow and are clipped. A press,
// Space, Enter or Alt+Down opens the list; Up and Down change the choice
// without opening it (select.json keyboard: "on some platforms without
// opening") and a letter jumps to the next option starting with it.
// Returns true on the frame selected^ changes.
//
// The list is the browser's, so this one is this package's choice
// (select.json notes): it opens --overlay-offset (4px) below the field in
// Primer's overlay surface (--overlay-bgColor, --overlay-borderColor,
// --shadow-floating-small), at least the field's width, its rows 24px
// with a check by the chosen option, the highlighted row filled in
// --bgColor-accent-emphasis with --fgColor-onEmphasis text, group headings in small semibold muted text and
// disabled options in --fgColor-disabled. In it Up and Down move the
// highlight past disabled options, Enter or Space chooses, Escape or a
// press outside closes, and a letter jumps.
//
// Departures: the list does not scroll, so a Select suits the short lists
// the spec names; with required, the placeholder is never offered in the
// list, and without it is not offered either, as -1 is not an option.
select :: proc(
	gtx: ^ui.Ctx,
	options: []Select_Option,
	selected: ^int,
	placeholder := "",
	size := Field_Size.Medium,
	validation := Validation_Status.None,
	block := false,
	required := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	fc := field_context(gtx, p.id, name, validation, required, state)
	st := field_style(size)
	font := font_for(gtx, st.weight)
	old := selected^
	widest := design.shape_style(gtx, placeholder, st, font).width
	for o in options {
		widest = max(widest, design.shape_style(gtx, o.label, st, font).width)
	}
	// The select keeps a 1px margin at its start (Select.module.css:1-8),
	// then the no-visuals 12px padding each side.
	inset := FIELD_BORDER + 1 + tok.BASE_SIZE_12
	cs := gtx.constraints
	w := inset + widest + tok.BASE_SIZE_12 + FIELD_BORDER
	switch {
	case block && ui.is_finite(cs.max.x):
		w = cs.max.x
	case width > 0:
		w = width
	}
	h := field_height(size)
	sz := ui.constrain(cs, {w, h})
	sz.y = max(sz.y, h)
	box := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, box, fc.state)
	forced: Select_State
	menu := c.st != nil ? ui.widget_data(gtx, p.id, Select_State) : &forced
	if c.st != nil {
		select_keys(gtx, p.id, options, selected, menu)
	}
	if c.disabled {
		menu.open = false
	}
	focused := field_focused(c) || menu.open
	well := Well{focused, c.disabled, false, fc.status}
	paint_well(gtx, box, well)
	fg := color(c.disabled ? .Fg_Color_Disabled : .Fg_Color_Default)
	said := placeholder
	if selected^ >= 0 && selected^ < len(options) {
		said = options[selected^].label
	}
	ops.clip_push(gtx.scene, ops.Round_Rect{box, tok.BORDER_RADIUS_MEDIUM})
	draw_text(gtx, design.shape_style(gtx, said, st, font), {inset, (box.h - FIELD_LINE) / 2}, fg)
	arrow_at := ops.Point{box.w - FIELD_BORDER - tok.BASE_SIZE_4 - BUTTON_ICON, (box.h - BUTTON_ICON) / 2}
	paint_svg(gtx, SELECT_ARROW, 16, arrow_at, BUTTON_ICON, fg)
	ops.clip_pop(gtx.scene)
	paint_well_focus(gtx, box, well)
	listen(gtx, c.st, p.id, box, cursor = .Pointer)
	tag := fc.name != "" ? fc.name : placeholder
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, tag))
	states := design.state_if(c.disabled, {.Disabled}) + design.state_if(fc.required, {.Required}) + design.state_if(fc.status == .Error, {.Invalid}) + {.Expandable} + design.state_if(menu.open, {.Expanded})
	ui.semantics(gtx, &p, {role = .Combo_Box, label = ui.frame_string(gtx, tag), value = ui.frame_string(gtx, said), description = fc.description, states = states})
	if menu.open {
		select_list(gtx, p.id, box, options, selected, menu, tag)
	}
	ui.widget_close(gtx, &p, {sz, (box.h - FIELD_LINE) / 2 + baseline_of(design.shape_style(gtx, said, st, font))})
	return selected^ != old
}

// select_keys applies a Select's keys this frame: see select.
@(private)
select_keys :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, options: []Select_Option, selected: ^int, menu: ^Select_State) {
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Press:
			if e.button == .Left {
				menu.open = !menu.open
				menu.highlight = selected^
			}
		case .Blur:
			menu.open = false
		case .Key:
			select_key(options, selected, menu, e.key, e.mods)
		}
	}
}

@(private)
select_key :: proc(options: []Select_Option, selected: ^int, menu: ^Select_State, k: ui.Key, mods: ui.Mods) {
	at := menu.open ? &menu.highlight : selected
	#partial switch k {
	case .Up, .Down:
		if k == .Down && .Alt in mods && !menu.open {
			menu.open, menu.highlight = true, selected^
			return
		}
		at^ = next_option(options, at^, k == .Down ? 1 : -1)
	case .Enter, .Space:
		if !menu.open {
			menu.open, menu.highlight = true, selected^
			return
		}
		if menu.highlight >= 0 && menu.highlight < len(options) && !options[menu.highlight].disabled {
			selected^ = menu.highlight
		}
		menu.open = false
	case .Escape:
		menu.open = false
	case .A ..= .Z:
		at^ = option_by_letter(options, at^, 'a' + rune(int(k) - int(ui.Key.A)))
	}
}

// next_option is the next enabled option from i by step, staying at i
// at either end.
@(private)
next_option :: proc(options: []Select_Option, i, step: int) -> int {
	j := i
	for {
		j += step
		if j < 0 || j >= len(options) {
			return i
		}
		if !options[j].disabled {
			return j
		}
	}
}

// option_by_letter is the next enabled option after i whose label starts
// with letter, wrapping, else i.
@(private)
option_by_letter :: proc(options: []Select_Option, i: int, letter: rune) -> int {
	n := len(options)
	for k in 1 ..= n {
		j := (max(i, -1) + k) % n
		o := options[j]
		if o.disabled || o.label == "" {
			continue
		}
		r, _ := utf8.decode_rune_in_string(o.label)
		if unicode.to_lower(r) == letter {
			return j
		}
	}
	return i
}

// select_list draws a Select's open list under the field: see select.
@(private)
select_list :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, field: ops.Rect, options: []Select_Option, selected: ^int, menu: ^Select_State, name: string) {
	menu_id := ui.id_mix(id, 0x5e1ec7)
	st := field_style(.Medium)
	font := font_for(gtx, st.weight)
	head := style(.Caption)
	head.weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD
	pad := tok.OVERLAY_PADDING_BLOCK_CONDENSED
	inset := tok.BASE_SIZE_8
	label_x := inset + BUTTON_ICON + inset
	w := field.w
	h := 2 * pad
	group := ""
	for o in options {
		if o.group != group && o.group != "" {
			h += SELECT_ROW
		}
		group = o.group
		w = max(w, label_x + design.shape_style(gtx, o.label, st, font).width + 2 * inset)
		h += SELECT_ROW
	}
	o := ui.popup_open(gtx, field, menu_id, gap = tok.OVERLAY_OFFSET)
	defer ui.popup_close(&o, {w, h})
	defer o.discard = !menu.open // closed this frame: draw nothing, catch nothing
	scrim := ui.id_mix(menu_id, 0xffff)
	for e in ui.events(gtx, scrim) {
		if e.kind == .Press {
			menu.open = false
		}
	}
	ops.input_area(gtx.scene, scrim, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	box := ops.Rect{0, 0, w, h}
	rr := ops.Round_Rect{box, tok.OVERLAY_BORDER_RADIUS}
	paint_shadow(gtx, rr, tok.SHADOW_FLOATING_SMALL)
	ops.fill(gtx.scene, rr, color(.Overlay_Bg_Color))
	stroke_inside(gtx, rr, color(.Overlay_Border_Color), FIELD_BORDER)
	ops.input_area(gtx.scene, ui.id_mix(menu_id, 0xfffe), rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	list := ui.overlay_semantics(gtx, &o, {role = .List_Box, label = name}, u64(menu_id))
	y := pad
	group = ""
	for opt, i in options {
		if opt.group != group && opt.group != "" {
			t := design.shape_style(gtx, opt.group, head, font_for(gtx, head.weight))
			draw_text(gtx, t, {inset, y + (SELECT_ROW - t.height) / 2}, color(.Fg_Color_Muted))
			y += SELECT_ROW
		}
		group = opt.group
		row := ops.Rect{0, y, w, SELECT_ROW}
		rid := ui.id_mix(menu_id, u64(i) + 1)
		c := control(gtx, rid, row, opt.disabled ? .Disabled : .Live)
		if c.hovered {
			menu.highlight = i
		}
		if c.clicked {
			selected^ = i
			menu.open = false
		}
		lit := i == menu.highlight && !opt.disabled
		fg := color(opt.disabled ? .Fg_Color_Disabled : .Fg_Color_Default)
		if lit {
			ops.fill(gtx.scene, ops.Round_Rect{{tok.BASE_SIZE_4, y, w - 2 * tok.BASE_SIZE_4, SELECT_ROW}, tok.BORDER_RADIUS_SMALL}, color(.Bg_Color_Accent_Emphasis))
			fg = color(.Fg_Color_On_Emphasis)
		}
		if i == selected^ {
			icon(gtx, .Check, {inset, y + (SELECT_ROW - BUTTON_ICON) / 2}, BUTTON_ICON, fg)
		}
		draw_text(gtx, design.shape_style(gtx, opt.label, st, font), {label_x, y + (SELECT_ROW - FIELD_LINE) / 2}, fg)
		// No key kinds: a press here leaves focus, and the keys, on the field.
		listen(gtx, c.st, rid, row, {.Press, .Release, .Enter, .Leave, .Move}, .Pointer)
		said := ui.frame_string(gtx, opt.label)
		ops.tag(gtx.scene, rid, said)
		ui.child_semantics(gtx, list, rid, row, {role = .Option, label = said, states = design.state_if(i == selected^, {.Selected}) + design.state_if(opt.disabled, {.Disabled})})
		y += SELECT_ROW
	}
}
