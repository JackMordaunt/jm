package primer

import "base:runtime"
import "core:strings"
import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// Form controls (primer-kit components/text-input.json, textarea.json,
// select.json, checkbox.json, checkbox-group.json, radio.json,
// radio-group.json, toggle-switch.json, form-control.json and
// segmented-control.json). This file holds what they share: a field's
// validation status, the open FormControl or group a control reads its
// name, description, status and disabled flag from, the validation
// message and caption, and FormControl, CheckboxGroup and RadioGroup
// themselves. The text fields are in forms_text.odin, the choice
// controls in forms_choice.odin, SegmentedControl in
// forms_segmented.odin.
//
// Primer's forms lean on the browser for the label-to-input link
// (label for=id: FormControlLabel.tsx:40-51), fieldset's disabled
// propagation (CheckboxOrRadioGroup.tsx:67,80-104) and the radio group's
// keyboard model (Radio.tsx:70-84 adds none: radio.json notes). Here an
// open FormControl or group is a thread-local record the controls inside
// it read and register with, as an open Fluent field is
// (ui/fluent/inputs.odin, field_open).

// Validation_Status is a field's validation: error borders it in danger
// and marks it invalid, success borders it in the success colour.
Validation_Status :: enum u8 {
	None,
	Error,
	Success,
}

// Field_Size is a text field's or select's height: 28px minimum, 32px
// minimum, or 40px fixed (TextInputWrapper.module.css:1-4,96-123).
Field_Size :: enum u8 {
	Small,
	Medium,
	Large,
}

// Open_Form is what an open FormControl or group tells the controls
// inside it: the label that names them, the caption and validation
// message that describe them, the status the message sets, and whether
// they are required or disabled. A control registers its area in input
// so a press on the label can focus it.
@(private)
Open_Form :: struct {
	label, caption, message: string,
	status:                  Validation_Status,
	required, disabled:      bool,
	group:                   bool, // a CheckboxGroup or RadioGroup: names the group, not each control
	input:                   ops.Area_Id,
	radios:                  ^Radio_Ring, // a RadioGroup's, else nil
}

@(private = "file")
FORM_DEPTH :: 8

@(private = "file", thread_local)
open_forms: [FORM_DEPTH]Open_Form

@(private = "file", thread_local)
open_form_count: int

@(private = "file")
form_push :: proc(f: Open_Form) {
	if open_form_count < FORM_DEPTH {
		open_forms[open_form_count] = f
	}
	open_form_count += 1
}

@(private = "file")
form_pop :: proc() -> (f: Open_Form) {
	open_form_count = max(open_form_count - 1, 0)
	if open_form_count < FORM_DEPTH {
		f = open_forms[open_form_count]
	}
	return
}

// open_form is the innermost open FormControl or group, nil outside one.
@(private)
open_form :: proc() -> ^Open_Form {
	if open_form_count == 0 || open_form_count > FORM_DEPTH {
		return nil
	}
	return &open_forms[open_form_count - 1]
}

// Field_Context is a control's view of the form around it, resolved: the
// name and description it is announced with, its status, and its
// interaction once a disabled form or group has had its say.
@(private)
Field_Context :: struct {
	name, description: string,
	status:            Validation_Status,
	required:          bool,
	state:             Interaction,
}

// field_context resolves a control's own name, status, required flag and
// state against the open form, and registers id as the form's input. The
// control's own name and status win where it sets them (FormControl.tsx
// :208-221 passes its props as defaults); a disabled form or group
// disables it.
@(private)
field_context :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, name: string, status: Validation_Status, required: bool, state: Interaction) -> (fc: Field_Context) {
	fc = {name = name, status = status, required = required, state = state}
	f := open_form()
	if f == nil {
		return
	}
	if !f.group {
		f.input = id
		if fc.name == "" {
			fc.name = f.label
		}
		if fc.status == .None && f.message != "" {
			fc.status = f.status
		}
		fc.description = join_words(gtx, f.message, f.caption)
	}
	fc.required ||= f.required && !f.group
	if f.disabled {
		fc.state = .Disabled
	}
	return
}

// join_words is the non-empty of a and b, joined by a space, in frame
// memory: a control's description from its parts.
@(private)
join_words :: proc(gtx: ^ui.Ctx, a, b: string) -> string {
	switch {
	case a == "":
		return b
	case b == "":
		return a
	}
	return strings.concatenate({a, " ", b}, gtx.allocator)
}

// FORM_GAP is the space between a vertical FormControl's label, input,
// validation and form_caption (FormControl.module.css:9-21).
FORM_GAP :: tok.BASE_SIZE_4

// CHOICE_GAP is a horizontal FormControl's inset from the box to its
// label and form_caption (--stack-gap-condensed, FormControl.module.css:28-32)
// and a group's space between options and after its legend
// (CheckboxOrRadioGroup.module.css:1-29).
CHOICE_GAP :: tok.BASE_SIZE_8

// form_label_style is a label's text: medium body, semibold for a FormControl
// or a group's legend, normal weight beside a checkbox or radio
// (InputLabel.module.css:1-5, FormControl.module.css:34-36), on the
// page's 1.5 line (foundations typography.rules).
@(private)
form_label_style :: proc(semibold: bool) -> tok.Type_Style {
	st := style(.Body_Medium)
	st.weight = semibold ? tok.BASE_TEXT_WEIGHT_SEMIBOLD : tok.BASE_TEXT_WEIGHT_NORMAL
	return st
}

// form_caption_style is a FormControl caption's text: small body on the
// page's 1.5 line (FormControlCaption.module.css:1-4).
@(private)
form_caption_style :: proc() -> tok.Type_Style {
	return {weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = tok.TEXT_BODY_SIZE_SMALL, line_height = tok.TEXT_BODY_SIZE_SMALL * 1.5}
}

// Form_Marker is what follows a required label and how far after it:
// FormControl's "*" 4px after (InputLabel.module.css:30-33), a group
// legend's 8px (CheckboxOrRadioGroup.module.css:46-48).
@(private)
Form_Marker :: struct {
	text: string,
	gap:  f32,
}

// Form_Label_Text is a label shaped with its required marker, if any.
@(private)
Form_Label_Text :: struct {
	text, marker: Text,
	gap, width:   f32,
}

@(private)
shape_form_label :: proc(gtx: ^ui.Ctx, text: string, st: tok.Type_Style, required: bool, marker: Form_Marker) -> (l: Form_Label_Text) {
	l.text = design.shape_style(gtx, text, st, font_for(gtx, st.weight))
	l.width = l.text.width
	if required {
		l.marker = design.shape_style(gtx, marker.text, st, font_for(gtx, st.weight))
		l.gap = marker.gap
		l.width += l.gap + l.marker.width
	}
	return
}

@(private)
draw_form_label :: proc(gtx: ^ui.Ctx, l: Form_Label_Text, pos: ops.Point, fg: ops.Color) {
	draw_text(gtx, l.text, pos, fg)
	if l.marker.width > 0 {
		draw_text(gtx, l.marker, {pos.x + l.text.width + l.gap, pos.y}, fg)
	}
}

// field_label is a vertical FormControl's label: semibold, its marker
// after it when required, --control-fgColor-disabled when disabled. A
// press on it focuses target, the input registered last frame (label
// for=id, FormControlLabel.tsx:40-51). It is tagged "<text> label".
@(private)
field_label :: proc(gtx: ^ui.Ctx, text: string, required, disabled: bool, target: ops.Area_Id, loc := #caller_location) {
	p := ui.widget_open(gtx, 0, loc)
	l := shape_form_label(gtx, text, form_label_style(true), required, {"*", tok.BASE_SIZE_4})
	sz := ui.constrain_min(gtx.constraints, {l.width, l.text.height})
	sz.x = l.width // align-self: flex-start, its own width
	draw_form_label(gtx, l, {0, 0}, color(disabled ? .Control_Fg_Color_Disabled : .Fg_Color_Default))
	area := ops.Rect{0, 0, sz.x, sz.y}
	if !disabled {
		st := ui.widget_state(gtx, p.id)
		if ui.click_from_events(gtx, p.id, st, area) && target != 0 {
			ui.focus_request(gtx, target)
		}
		ops.input_area(gtx.scene, p.id, area, {.Press, .Release, .Enter, .Leave}, .Pointer)
	}
	ops.tag(gtx.scene, p.id, strings.concatenate({text, " label"}, gtx.allocator))
	ui.semantics(gtx, &p, {role = .Text, label = ui.frame_string(gtx, text)})
	ui.widget_close(gtx, &p, {sz, baseline_of(l.text)})
}

// form_caption is a FormControl's hint under its input: small body text in
// --fgColor-muted, --control-fgColor-disabled when disabled
// (FormControlCaption.module.css:1-9), wrapping at the width offered.
@(private)
form_caption :: proc(gtx: ^ui.Ctx, text: string, disabled: bool, st := tok.Type_Style{}, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	s := st == {} ? form_caption_style() : st
	width := ui.is_finite(gtx.constraints.max.x) ? gtx.constraints.max.x : 0
	para := design.layout_style(gtx, text, s, font_for(gtx, s.weight), width)
	sz := ui.constrain(gtx.constraints, {para.width, para.height})
	design.draw_paragraph(gtx, para, {0, 0}, color(disabled ? .Control_Fg_Color_Disabled : .Fg_Color_Muted))
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text), {0, 0, sz.x, sz.y})
	ui.widget_close(gtx, &p, {sz, len(para.lines) > 0 ? para.lines[0].baseline : 0})
}

// VALIDATION_ICON is a validation message's icon, VALIDATION_LINE its
// text's line: 12px over 16px, literals in InputValidation.tsx:36-40.
VALIDATION_ICON :: f32(12)
VALIDATION_LINE :: f32(16)

// VALIDATION_ENTER is the message's entrance: 170ms
// cubic-bezier(0.44, 0.74, 0.36, 1) (ValidationAnimationContainer.module
// .css:1-2), a literal, not a token.
VALIDATION_ENTER :: tok.Transition{170, {0.44, 0.74, 0.36, 1}}

// Form_Entrance is a validation message's entrance between frames.
@(private)
Form_Entrance :: struct {
	tween: ui.Tween,
	live:  bool,
}

// validation_message is the message under a field or group: a 12px
// AlertFill (error) or CheckCircleFill (success) 2px down with 4px after
// it, then small semibold text on a 16px line, all in --fgColor-danger
// or --fgColor-success (InputValidation.module.css:1-32). It enters by
// fading in while sliding down from one message-height above, clipped,
// over VALIDATION_ENTER. A reader hears it as an alert.
@(private)
validation_message :: proc(gtx: ^ui.Ctx, text: string, status: Validation_Status, key: u64 = 0, loc := #caller_location) {
	p := ui.widget_open(gtx, key, loc)
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_SEMIBOLD, size = tok.TEXT_BODY_SIZE_SMALL, line_height = VALIDATION_LINE}
	gutter := VALIDATION_ICON + tok.BASE_SIZE_4
	width := ui.is_finite(gtx.constraints.max.x) ? max(gtx.constraints.max.x - gutter, 1) : 0
	para := design.layout_style(gtx, text, st, font_for(gtx, st.weight), width)
	sz := ui.constrain(gtx.constraints, {gutter + para.width, max(para.height, VALIDATION_LINE)})
	en := ui.widget_data(gtx, p.id, Form_Entrance)
	if !en.live {
		en^ = {tween = {to = 1, duration = VALIDATION_ENTER.duration / 1000}, live = true}
	}
	t := design.bezier_ease(VALIDATION_ENTER.easing, ui.tween_update(&en.tween, gtx))
	fg := fade(color(status == .Success ? .Fg_Color_Success : .Fg_Color_Danger), t)
	dy := -(1 - t) * sz.y
	ops.clip_push(gtx.scene, ops.Rect{0, 0, sz.x, sz.y})
	icon(gtx, status == .Success ? .Check_Circle_Fill : .Alert_Fill, {0, dy + tok.BASE_SIZE_2}, VALIDATION_ICON, fg)
	design.draw_paragraph(gtx, para, {gutter, dy}, fg)
	ops.clip_pop(gtx.scene)
	said := ui.frame_string(gtx, text)
	ops.tag(gtx.scene, p.id, said, {0, 0, sz.x, sz.y})
	ui.semantics(gtx, &p, {role = .Alert, label = said})
	ui.widget_close(gtx, &p, {sz, len(para.lines) > 0 ? para.lines[0].baseline : 0})
}

// Form_Control is an open FormControl: form_control_close draws its
// validation message and caption under the input and closes it.
Form_Control :: struct {
	col:    ui.Flex,
	target: ^ops.Area_Id, // the input the label focuses, kept a frame
}

// form_control_open opens a FormControl (form-control.json) around one
// text input, textarea or select: a column, start-aligned, 4px apart, of
// the label, the input the caller draws next, then the validation
// message and the caption, which form_control_close draws. The label
// names the input and a press on it focuses the input; hide_label keeps
// the name and draws nothing. validation, when set, is shown with
// status's icon and colour and sets the input's status; caption and
// validation describe it. required adds "*" after the label and marks
// the input required; disabled greys the label and caption and disables
// the input.
//
// Departures: a checkbox or radio takes FormControl's horizontal layout
// through its own label, caption and leading parameters rather than
// sitting in one of these, since its label must share its hit area;
// requiredText and requiredIndicator are not offered; the entrance
// ignores reduced motion, which jm:ui does not expose.
form_control_open :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption := "",
	validation := "",
	status := Validation_Status.Error,
	required := false,
	disabled := false,
	hide_label := false,
	key: u64 = 0,
	loc := #caller_location,
) -> (f: Form_Control) {
	id := ui.claim_id(gtx, key, loc)
	f.target = ui.widget_data(gtx, id, ops.Area_Id)
	form_push({label = ui.frame_string(gtx, label), caption = ui.frame_string(gtx, caption), message = ui.frame_string(gtx, validation), status = status, required = required, disabled = disabled})
	f.col = ui.column_open(gtx, gap = FORM_GAP, align = .Start, key = key, loc = loc)
	if !hide_label {
		field_label(gtx, label, required, disabled, f.target^)
	}
	return
}

// form_control_close draws f's validation message, then its caption
// (FormControl.tsx:229-232: caption after the message), and closes it.
form_control_close :: proc(gtx: ^ui.Ctx, f: ^Form_Control) {
	w := form_pop()
	f.target^ = w.input
	if w.message != "" && w.status != .None {
		validation_message(gtx, w.message, w.status)
	}
	if w.caption != "" {
		form_caption(gtx, w.caption, w.disabled)
	}
	ui.close(&f.col)
}

// form_control is form_control_open as a guard: `if primer.form_control(gtx,
// "Name") { … }` closes it at the end of the if, or of the block when called
// as a statement.
@(deferred_in = form_control_guard_close)
form_control :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption := "",
	validation := "",
	status := Validation_Status.Error,
	required := false,
	disabled := false,
	hide_label := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	ui.guard_hold(gtx, Form_Control)^ = form_control_open(gtx, label, caption, validation, status, required, disabled, hide_label, key, loc)
	return true
}

@(private = "file")
form_control_guard_close :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption: string,
	validation: string,
	status: Validation_Status,
	required: bool,
	disabled: bool,
	hide_label: bool,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	h := ui.guard_take(gtx, Form_Control)
	form_control_close(gtx, h)
}

// Choice_Group is an open CheckboxGroup or RadioGroup: its close draws
// the validation message under the options and closes it.
Choice_Group :: struct {
	outer, options: ui.Flex,
	box:            ui.Inset, // a RadioGroup's: holds its roving scope round the options
	ring:           ^Radio_Ring,
	validation:     string,
	status:         Validation_Status,
}

// choice_group_open is CheckboxGroup's and RadioGroup's shared body
// (CheckboxOrRadioGroup.tsx, CheckboxOrRadioGroup.module.css): the
// legend (the label, semibold, --fgColor-muted when disabled, "*" 8px
// after it when required; then the caption in medium body muted text),
// 8px, then the options in a column 8px apart, then, with a validation
// message, 8px and the message.
@(private)
choice_group_open :: proc(gtx: ^ui.Ctx, label, caption_text, validation: string, status: Validation_Status, required, disabled, hide_label, radios: bool, key: u64, loc: runtime.Source_Code_Location) -> (g: Choice_Group) {
	id := ui.claim_id(gtx, key, loc)
	if radios {
		g.ring = ui.widget_data(gtx, id, Radio_Ring)
		g.ring.checked = 0
	}
	g.validation, g.status = ui.frame_string(gtx, validation), status
	said := ui.frame_string(gtx, label)
	form_push({label = said, caption = ui.frame_string(gtx, caption_text), message = g.validation, status = status, required = required, disabled = disabled, group = true, radios = g.ring})
	g.outer = ui.column_open(gtx, align = .Start, key = key, loc = loc)
	ui.container_semantics(gtx, {role = .Group, label = said, description = join_words(gtx, g.validation, caption_text), states = design.state_if(required, {.Required}) + design.state_if(disabled, {.Disabled})})
	if !hide_label || caption_text != "" {
		legend := ui.column_open(gtx, align = .Start)
		if !hide_label {
			group_legend(gtx, label, required, disabled)
		}
		if caption_text != "" {
			form_caption(gtx, caption_text, false, style(.Body_Medium))
		}
		ui.close(&legend)
		if !hide_label {
			ui.spacer(gtx, CHOICE_GAP)
		}
	}
	if radios {
		g.box = ui.inset_open(gtx, {}, key = u64(ui.id_mix(id, 1)))
		ui.focus_scope_open(gtx, id, rove = .Both, wrap = true)
	}
	g.options = ui.column_open(gtx, gap = CHOICE_GAP, align = .Start)
	return
}

// group_legend is a group's visible label.
@(private = "file")
group_legend :: proc(gtx: ^ui.Ctx, text: string, required, disabled: bool) {
	p := ui.widget_open(gtx)
	l := shape_form_label(gtx, text, form_label_style(true), required, {"*", CHOICE_GAP})
	sz := ui.constrain(gtx.constraints, {l.width, l.text.height})
	draw_form_label(gtx, l, {0, 0}, color(disabled ? .Fg_Color_Muted : .Fg_Color_Default))
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text), {0, 0, sz.x, sz.y})
	ui.widget_close(gtx, &p, {sz, baseline_of(l.text)})
}

@(private)
choice_group_close :: proc(gtx: ^ui.Ctx, g: ^Choice_Group) {
	ui.close(&g.options)
	form_pop()
	if g.ring != nil {
		ui.focus_scope_close(gtx, g.ring.checked)
		ui.close(&g.box)
	}
	if g.validation != "" && g.status != .None {
		ui.spacer(gtx, CHOICE_GAP)
		validation_message(gtx, g.validation, g.status)
	}
	ui.close(&g.outer)
}

// checkbox_group_open opens a CheckboxGroup (checkbox-group.json): a
// labelled set of checkboxes drawn inside it, each with its own label,
// sharing one caption and one validation message, which
// checkbox_group_close draws. disabled disables every checkbox and mutes
// the legend; required marks the legend. Each checkbox reports its own
// toggle and keeps its own state; the group reports nothing itself.
//
// Departure: onChange's array of checked values has no counterpart:
// each checkbox's own bool is its state, in option order, which the
// spec's notes recommend over the order values were checked in.
checkbox_group_open :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption := "",
	validation := "",
	status := Validation_Status.Error,
	required := false,
	disabled := false,
	hide_label := false,
	key: u64 = 0,
	loc := #caller_location,
) -> Choice_Group {
	return choice_group_open(gtx, label, caption, validation, status, required, disabled, hide_label, false, key, loc)
}

// checkbox_group_close closes g, drawing its validation message.
checkbox_group_close :: proc(gtx: ^ui.Ctx, g: ^Choice_Group) {
	choice_group_close(gtx, g)
}

// checkbox_group is checkbox_group_open as a guard: `if
// primer.checkbox_group(gtx, "Notify") { … }` closes it at the end of the
// if, or of the block when called as a statement.
@(deferred_in = checkbox_group_guard_close)
checkbox_group :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption := "",
	validation := "",
	status := Validation_Status.Error,
	required := false,
	disabled := false,
	hide_label := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	ui.guard_hold(gtx, Choice_Group)^ = checkbox_group_open(gtx, label, caption, validation, status, required, disabled, hide_label, key, loc)
	return true
}

@(private = "file")
checkbox_group_guard_close :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption: string,
	validation: string,
	status: Validation_Status,
	required: bool,
	disabled: bool,
	hide_label: bool,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	h := ui.guard_take(gtx, Choice_Group)
	checkbox_group_close(gtx, h)
}

// radio_group_open opens a RadioGroup (radio-group.json): checkbox_group
// _open's layout around radios, which it makes one roving focus scope, so
// one Tab stop, entered at the checked radio: while one has focus, Down
// and Right check and focus the next enabled radio, Up and Left the
// previous, wrapping and skipping disabled ones (the browser's native
// radio group, which Primer relies on: radio.json notes). Each radio
// reports the frame it is chosen; the caller keeps the choice.
//
// Departures: Home and End also check and focus the first and last
// radio, the ends of jm:ui's roving scope, where radio.json names only
// the arrows; there is no name or value, as the caller's own choice is
// the group's.
radio_group_open :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption := "",
	validation := "",
	status := Validation_Status.Error,
	required := false,
	disabled := false,
	hide_label := false,
	key: u64 = 0,
	loc := #caller_location,
) -> Choice_Group {
	return choice_group_open(gtx, label, caption, validation, status, required, disabled, hide_label, true, key, loc)
}

// radio_group_close closes g, drawing its validation message.
radio_group_close :: proc(gtx: ^ui.Ctx, g: ^Choice_Group) {
	choice_group_close(gtx, g)
}

// radio_group is radio_group_open as a guard: `if primer.radio_group(gtx,
// "Size") { … }` closes it at the end of the if, or of the block when called
// as a statement.
@(deferred_in = radio_group_guard_close)
radio_group :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption := "",
	validation := "",
	status := Validation_Status.Error,
	required := false,
	disabled := false,
	hide_label := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	ui.guard_hold(gtx, Choice_Group)^ = radio_group_open(gtx, label, caption, validation, status, required, disabled, hide_label, key, loc)
	return true
}

@(private = "file")
radio_group_guard_close :: proc(
	gtx: ^ui.Ctx,
	label: string,
	caption: string,
	validation: string,
	status: Validation_Status,
	required: bool,
	disabled: bool,
	hide_label: bool,
	key: u64,
	loc: runtime.Source_Code_Location,
) {
	h := ui.guard_take(gtx, Choice_Group)
	radio_group_close(gtx, h)
}

// Radio_Ring is what a RadioGroup learns from its radios this frame:
// the checked one, where Tab enters the group's roving focus scope.
@(private)
Radio_Ring :: struct {
	checked: ops.Area_Id,
}

// paint_svg fills SVG path data d, drawn in a box-unit square, at size
// with its top-left at pos: for the few glyphs Primer draws that are not
// octicons. The path is parsed into frame memory.
@(private)
paint_svg :: proc(gtx: ^ui.Ctx, d: string, box: f32, pos: ops.Point, size: f32, c: ops.Color) {
	if !ui.painted(c) {
		return
	}
	path, _ := design.parse_svg_path(d, gtx.allocator)
	if len(path.points) == 0 {
		return
	}
	k := size / box
	ops.transform_push(gtx.scene, ops.mul(ops.scale(k, k), ops.translate(pos.x, pos.y)))
	ops.fill(gtx.scene, ops.Path_Ref{ops.add_path(gtx.scene, path)}, c)
	ops.transform_pop(gtx.scene)
}
