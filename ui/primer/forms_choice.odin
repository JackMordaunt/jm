package primer

import "jm:ui"
import "jm:ui/design"
import "jm:ui/ops"
import tok "jm:ui/primer/tokens"

// The choice controls: Checkbox, Radio and ToggleSwitch (checkbox.json,
// radio.json, toggle-switch.json; Checkbox.module.css, Radio.module.css,
// shared.module.css and ToggleSwitch.module.css at the kit's release).
// None has a hover or pressed colour of its own but the switch's track.

// CHOICE_BOX is a checkbox's or radio's side, border included, and
// CHOICE_TOP its top margin, which centres it on a 20px line beside it
// (shared.module.css:1-16).
CHOICE_BOX :: tok.BASE_SIZE_16
CHOICE_TOP :: tok.BASE_SIZE_2

// CHOICE_FOCUS_OFFSET is a checkbox's and radio's focus outline offset:
// 2px outside, unlike a button's inset ring (Checkbox.module.css:82-84,
// Radio.module.css:25-27).
CHOICE_FOCUS_OFFSET :: f32(2)

// Choice_Layout is where a checkbox's or radio's parts sit, with the
// horizontal FormControl around it when it has a label
// (FormControl.module.css:1-57): the box, its leading visual, label and
// caption, the whole size and the hit area, which is the box and the
// label (label for=id) but not the caption.
@(private)
Choice_Layout :: struct {
	box:                ops.Rect,
	visual:             ops.Rect,
	label_at, caption_at: ops.Point,
	size:               ops.Size,
	hit:                ops.Rect,
}

// choice_layout lays a box out beside l and its caption cap: the label
// column 8px after the box (or after the leading visual, itself 8px
// after the box and 16px, or 24px with a caption), the box at the top
// of its cell; with a leading visual every item is centred instead.
@(private)
choice_layout :: proc(l: Form_Label_Text, cap: ui.Paragraph, has_label, has_caption: bool, leading: Icon) -> (k: Choice_Layout) {
	outer := CHOICE_BOX + CHOICE_TOP
	k.box = {0, CHOICE_TOP, CHOICE_BOX, CHOICE_BOX}
	if !has_label {
		k.size = {CHOICE_BOX, outer}
		k.hit = k.box
		return
	}
	col_h := l.text.height + (has_caption ? cap.height : 0)
	col_w := max(l.width, has_caption ? cap.width : 0)
	x := CHOICE_BOX
	h := max(outer, col_h)
	col_y: f32
	if leading != .None {
		vs := has_caption ? tok.BASE_SIZE_24 : tok.TEXT_BODY_SIZE_LARGE
		h = max(h, vs)
		x += CHOICE_GAP
		k.visual = {x, (h - vs) / 2, vs, vs}
		x += vs
		k.box.y = (h - outer) / 2 + CHOICE_TOP
		col_y = (h - col_h) / 2
	}
	x += CHOICE_GAP
	k.label_at = {x, col_y}
	k.caption_at = {x, col_y + l.text.height}
	k.size = {x + col_w, h}
	top := min(k.box.y, col_y)
	k.hit = {0, top, x + l.width, max(k.box.y + CHOICE_BOX, col_y + l.text.height) - top}
	return
}

// Choice_Parts is a labelled box's text, shaped.
@(private)
Choice_Parts :: struct {
	label:              Form_Label_Text,
	cap:                ui.Paragraph,
	has_label, has_cap: bool,
}

@(private)
choice_parts :: proc(gtx: ^ui.Ctx, label, caption_text: string, required: bool) -> (cp: Choice_Parts) {
	cp.has_label, cp.has_cap = label != "", label != "" && caption_text != ""
	cp.label = shape_form_label(gtx, label, form_label_style(false), required, {"*", tok.BASE_SIZE_4})
	if cp.has_cap {
		st := form_caption_style()
		cp.cap = design.layout_style(gtx, caption_text, st, font_for(gtx, st.weight))
	}
	return
}

// paint_choice_text draws a labelled box's leading visual, label and
// caption: --fgColor-default (the leading visual too:
// form-control.json notes), --fgColor-muted for the caption, all
// --control-fgColor-disabled when disabled.
@(private)
paint_choice_text :: proc(gtx: ^ui.Ctx, cp: Choice_Parts, k: Choice_Layout, leading: Icon, disabled: bool) {
	if !cp.has_label {
		return
	}
	fg := color(disabled ? .Control_Fg_Color_Disabled : .Fg_Color_Default)
	if leading != .None {
		icon(gtx, leading, {k.visual.x, k.visual.y}, k.visual.w, fg)
	}
	draw_form_label(gtx, cp.label, k.label_at, fg)
	if cp.has_cap {
		design.draw_paragraph(gtx, cp.cap, k.caption_at, color(disabled ? .Control_Fg_Color_Disabled : .Fg_Color_Muted))
	}
}

// CHECK_MARK and CHECK_DASH are the checkbox glyphs' masks: a 12 by 9
// checkmark and a 10 by 2 bar (Checkbox.module.css:18,77).
@(private)
CHECK_MARK :: "M11.7803 0.219625 C11.921 0.360427 12 0.551305 12 0.750313 C12 0.949321 11.921 1.14019 11.7803 1.281 L4.5186 8.54042 C4.37775 8.681 4.18682 8.76 3.98774 8.76 C3.78867 8.76 3.59773 8.681 3.45689 8.54042 L0.201622 5.2862 C0.0689277 5.14383 -0.00330905 4.95555 0.000116493 4.76098 C0.00355205 4.56643 0.0823894 4.38081 0.220032 4.24321 C0.357665 4.10562 0.543355 4.02681 0.73797 4.02338 C0.932584 4.01994 1.12093 4.09217 1.26334 4.22482 L3.98774 6.94835 L10.7186 0.219625 C10.8595 0.0789923 11.0504 0 11.2495 0 C11.4485 0 11.6395 0.0789923 11.7803 0.219625 Z"
@(private)
CHECK_DASH :: "M0 1 C0 0.447715 0.447715 0 1 0 H9 C9.55229 0 10 0.447715 10 1 C10 1.55228 9.55229 2 9 2 H1 C0.447715 2 0 1.55228 0 1 Z"

// CHECK_GLYPH is the glyphs' drawn width, 75% of the box
// (Checkbox.module.css:19).
@(private)
CHECK_GLYPH :: CHOICE_BOX * 0.75

// CHECK_REVEAL is the checkmark's clip transition, 80ms after the box
// fills when checking (Checkbox.module.css:87-105): the control
// transition, 80ms cubic-bezier(0.65, 0, 0.35, 1), which the checkbox's
// CSS repeats as literals. The border fades over 80ms on a curve per
// direction (Checkbox.module.css:4-7,62-65).
@(private)
CHECK_REVEAL :: CONTROL_TRANSITION
@(private)
CHECK_BORDER_IN :: tok.Bezier{0.32, 0, 0.67, 0}
@(private)
CHECK_BORDER_OUT :: tok.Bezier{0.33, 1, 0.68, 1}

// Check_Reveal is a checkbox's checkmark clip between frames: the shown
// fraction, from the bottom up, and the transition toward on or off.
@(private)
Check_Reveal :: struct {
	from, to, value: f32,
	on, live:        bool,
	tween:           ui.Tween,
}

// check_reveal is the fraction of the checkmark shown, bottom up: it
// grows over CHECK_REVEAL after an 80ms delay when checked and shrinks
// top-down at once when cleared. A forced state shows it whole or not.
@(private)
check_reveal :: proc(gtx: ^ui.Ctx, c: Control, id: ops.Area_Id, on: bool) -> f32 {
	target: f32 = on ? 1 : 0
	if c.st == nil {
		return target
	}
	r := ui.widget_data(gtx, id, Check_Reveal)
	if !r.live {
		r^ = {from = target, to = target, value = target, on = on, live = true}
		return target
	}
	dur := CHECK_REVEAL.duration / 1000
	delay: f32 = on ? dur : 0
	if on != r.on {
		r.from, r.to, r.on = r.value, target, on
		r.tween = {to = 1, duration = delay + dur}
	}
	elapsed := ui.tween_update(&r.tween, gtx) * r.tween.duration
	x := r.tween.duration > 0 ? clamp((elapsed - delay) / dur, 0, 1) : 1
	r.value = r.from + (r.to - r.from) * design.bezier_ease(CHECK_REVEAL.easing, x)
	return r.value
}

// checkbox is Primer's Checkbox (checkbox.json): a 16px box, its border
// inside it at the small radius, that a click or Space toggles. checked^
// flips and it returns true on that frame. indeterminate draws the dash
// in place of the check and stays drawn until the caller clears it. With
// a label it is FormControl's horizontal layout: the label 8px after the
// box (normal weight, "*" after it when required), caption under the
// label, leading an octicon between box and label; a press on the label
// toggles it too. Checked fills and borders in --control-checked-bgColor
// -rest with an --fgColor-onEmphasis glyph; the fill snaps, the border
// fades and the check is revealed from the bottom (the spec's notes on
// the CSS's 0s fill transition). Keyboard focus draws a 2px outline 2px
// outside the box. validation only marks it invalid: a single checkbox
// has no validation look.
//
// Departures: the dash shows with the box rather than after the CSS's
// 230ms visibility delay, as the spec permits; forced colours are the
// themes' high-contrast bindings, not the CSS's CanvasText rule.
checkbox :: proc(
	gtx: ^ui.Ctx,
	checked: ^bool,
	label := "",
	caption := "",
	leading := Icon.None,
	indeterminate := false,
	required := false,
	validation := Validation_Status.None,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	fc := field_context(gtx, p.id, label, validation, required, state)
	cp := choice_parts(gtx, label, caption, fc.required)
	k := choice_layout(cp.label, cp.cap, cp.has_label, cp.has_cap, leading)
	sz := ui.constrain_min(gtx.constraints, k.size)
	c := control(gtx, p.id, k.hit, fc.state)
	toggled := c.clicked && !c.disabled
	if toggled {
		checked^ = !checked^
	}
	on := checked^ || indeterminate
	fill, border, glyph: tok.Role
	switch {
	case c.disabled && on:
		fill, border, glyph = .Control_Checked_Bg_Color_Disabled, .Control_Checked_Border_Color_Disabled, .Control_Checked_Fg_Color_Disabled
	case c.disabled:
		fill, border = .Control_Bg_Color_Disabled, .Control_Border_Color_Disabled
	case on:
		// The border reads the fill's token (Checkbox.module.css:25-38).
		fill, border, glyph = .Control_Checked_Bg_Color_Rest, .Control_Checked_Bg_Color_Rest, .Fg_Color_On_Emphasis
	case:
		fill, border = .Bg_Color_Default, .Control_Border_Color_Emphasis
	}
	rr := ops.Round_Rect{k.box, tok.BORDER_RADIUS_SMALL}
	ops.fill(gtx.scene, rr, color(fill))
	stroke_inside(gtx, rr, design.blend(gtx, c.fades, 0, color(border), CHECK_REVEAL.duration, on ? CHECK_BORDER_IN : CHECK_BORDER_OUT), tok.BORDER_WIDTH_THIN)
	shown := check_reveal(gtx, c, p.id, checked^ && !indeterminate)
	if indeterminate {
		h := CHECK_GLYPH / 10 * 2
		paint_svg(gtx, CHECK_DASH, 10, {k.box.x + (CHOICE_BOX - CHECK_GLYPH) / 2, k.box.y + (CHOICE_BOX - h) / 2}, CHECK_GLYPH, color(glyph))
	} else if shown > 0 {
		ops.clip_push(gtx.scene, ops.Rect{k.box.x, k.box.y + CHOICE_BOX * (1 - shown), CHOICE_BOX, CHOICE_BOX * shown})
		mark := on ? color(glyph) : color(c.disabled ? .Control_Checked_Fg_Color_Disabled : .Fg_Color_On_Emphasis)
		paint_svg(gtx, CHECK_MARK, 12, {k.box.x + (CHOICE_BOX - CHECK_GLYPH) / 2, k.box.y + (CHOICE_BOX - 9) / 2}, CHECK_GLYPH, mark)
		ops.clip_pop(gtx.scene)
	}
	paint_focus_outline(gtx, c, rr, CHOICE_FOCUS_OFFSET)
	paint_choice_text(gtx, cp, k, leading, c.disabled)
	listen(gtx, c.st, p.id, k.hit, cursor = .Pointer)
	said := ui.frame_string(gtx, label)
	ops.tag(gtx.scene, p.id, said)
	states := design.state_if(checked^ && !indeterminate, {.Checked}) + design.state_if(indeterminate, {.Mixed}) + design.state_if(c.disabled, {.Disabled}) + design.state_if(fc.required, {.Required}) + design.state_if(fc.status == .Error, {.Invalid})
	ui.semantics(gtx, &p, {role = .Checkbox, label = said, description = ui.frame_string(gtx, caption), states = states})
	ui.widget_close(gtx, &p, {sz, k.label_at.y + baseline_of(cp.label.text)})
	return toggled
}

// RADIO_RING_CHECKED is a checked radio's ring, leaving an 8px dot of
// fill (Radio.module.css:7-14, --borderWidth-thicker).
@(private)
RADIO_RING_CHECKED :: tok.BORDER_WIDTH_THICKER

// RADIO_FADE is the ring colour's transition: 80ms
// cubic-bezier(0.33, 1, 0.68, 1); width and fill snap (Radio.module.css
// :3-5, radio.json notes).
@(private)
RADIO_FADE :: tok.Transition{80, {0.33, 1, 0.68, 1}}

// radio is Primer's Radio (radio.json): a 16px circle, a 1px
// --control-borderColor-emphasis ring on --bgColor-default, which checked
// thickens to 4px of --control-checked-bgColor-rest around an 8px
// --control-checked-fgColor-rest dot. checked is the caller's: radio
// returns true on the frame it is chosen, by a click or Space, and the
// caller checks it and clears the rest. A checked radio pressed again
// returns false. label, caption and leading are checkbox's horizontal
// FormControl. Inside radio_group_open, the arrow keys move the choice
// through the group and a disabled group disables it.
//
// Departures: a radio outside a group has no name and no exclusivity of
// its own, which the caller's single choice gives; the CSS's unscoped
// forced-colours fill (radio.json notes) is not reproduced, as jm:ui has
// no forced-colours mode.
radio :: proc(
	gtx: ^ui.Ctx,
	checked: bool,
	label := "",
	caption := "",
	leading := Icon.None,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	fc := field_context(gtx, p.id, label, .None, false, state)
	cp := choice_parts(gtx, label, caption, false)
	k := choice_layout(cp.label, cp.cap, cp.has_label, cp.has_cap, leading)
	sz := ui.constrain_min(gtx.constraints, k.size)
	c := control(gtx, p.id, k.hit, fc.state)
	chosen := c.clicked && !c.disabled && !checked
	if f := open_form(); f != nil && f.radios != nil {
		ring := f.radios
		place := ring_add(ring, p.id, c.disabled)
		if ring.chosen == p.id {
			chosen = !checked
			ring.chosen = 0
		}
		if c.st != nil && c.focused {
			for e in ui.events(gtx, p.id) {
				if e.kind != .Key {
					continue
				}
				#partial switch e.key {
				case .Down, .Right:
					ring_step(gtx, ring, place, 1)
				case .Up, .Left:
					ring_step(gtx, ring, place, -1)
				}
			}
		}
	}
	on := checked || chosen
	fill, ring_role: tok.Role
	switch {
	case c.disabled && on:
		fill, ring_role = .Control_Checked_Fg_Color_Disabled, .Control_Checked_Bg_Color_Disabled
	case c.disabled:
		fill, ring_role = .Control_Bg_Color_Disabled, .Control_Border_Color_Disabled
	case on:
		fill, ring_role = .Control_Checked_Fg_Color_Rest, .Control_Checked_Bg_Color_Rest
	case:
		fill, ring_role = .Bg_Color_Default, .Control_Border_Color_Emphasis
	}
	centre := ops.Point{k.box.x + CHOICE_BOX / 2, k.box.y + CHOICE_BOX / 2}
	ring_color := design.blend(gtx, c.fades, 0, color(ring_role), RADIO_FADE.duration, RADIO_FADE.easing)
	width := on ? RADIO_RING_CHECKED : tok.BORDER_WIDTH_THIN
	ops.fill(gtx.scene, ui.circle(centre, CHOICE_BOX / 2), ring_color)
	ops.fill(gtx.scene, ui.circle(centre, CHOICE_BOX / 2 - width), color(fill))
	paint_focus_outline(gtx, c, {k.box, CHOICE_BOX / 2}, CHOICE_FOCUS_OFFSET)
	paint_choice_text(gtx, cp, k, leading, c.disabled)
	listen(gtx, c.st, p.id, k.hit, cursor = .Pointer)
	said := ui.frame_string(gtx, label)
	ops.tag(gtx.scene, p.id, said)
	ui.semantics(gtx, &p, {role = .Radio, label = said, description = ui.frame_string(gtx, caption), states = design.state_if(on, {.Checked}) + design.state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, k.label_at.y + baseline_of(cp.label.text)})
	return chosen
}

// Switch_Size is a ToggleSwitch's track: 64 by 32px or 48 by 24px.
Switch_Size :: enum u8 {
	Medium,
	Small,
}

// Status_Position is which side of the track the On/Off label sits.
Status_Position :: enum u8 {
	Start,
	End,
}

// SWITCH_SLIDE is the knob's, glyphs' and track colours' transition:
// 80ms cubic-bezier(0.5, 1, 0.89, 1) (ToggleSwitch.module.css:1-3), local
// to the module.
SWITCH_SLIDE :: tok.Transition{80, {0.5, 1, 0.89, 1}}

// SWITCH_FOCUS_OFFSET is the switch's keyboard outline offset: 3px
// outside the track (ToggleSwitch.module.css:78-82).
SWITCH_FOCUS_OFFSET :: f32(3)

// SWITCH_LINE and SWITCH_RING are the on and off glyphs, 16px paths
// filled in the glyph colour (ToggleSwitch.tsx:53-77). The ring fills
// even-odd, which jm:ui's fills do not, so it is stroked instead: a
// circle of radius 5.25 stroked 1.5px is the same ring (6 out, 4.5 in).
@(private)
SWITCH_LINE :: "M8 2a.75.75 0 0 1 .75.75v11.5a.75.75 0 0 1-1.5 0V2.75A.75.75 0 0 1 8 2Z"

@(private)
Switch_Slide :: struct {
	from, to, value: f32,
	live:            bool,
	tween:           ui.Tween,
}

// switch_position is the knob's place, 0 off to 1 on, sliding over
// SWITCH_SLIDE; a forced state is where it rests.
@(private)
switch_position :: proc(gtx: ^ui.Ctx, c: Control, id: ops.Area_Id, on: bool) -> f32 {
	target: f32 = on ? 1 : 0
	if c.st == nil {
		return target
	}
	s := ui.widget_data(gtx, id, Switch_Slide)
	if !s.live {
		s^ = {from = target, to = target, value = target, live = true}
		return target
	}
	if target != s.to {
		s.from, s.to = s.value, target
		s.tween = {to = 1, duration = SWITCH_SLIDE.duration / 1000}
	}
	t := ui.tween_update(&s.tween, gtx)
	s.value = s.from + (s.to - s.from) * design.bezier_ease(SWITCH_SLIDE.easing, t)
	return s.value
}

// toggle_switch is Primer's ToggleSwitch (toggle-switch.json): a setting
// that applies at once. on^ flips on a press of the track or of its
// status label, or Space or Enter while the track has focus, and it
// returns true on that frame. The status label says label_on or
// label_off, right-aligned in the wider of the two so the track never
// moves, 8px each side, before the track (status_position Start) or
// after it. The track is 64 by 32px (48 by 24px small) at the 6px
// default radius, not a pill; its fill changes on hover, keyboard focus
// and press, and its knob, half its width, slides 1px inside it with the
// line or ring glyph. loading shows a 16px spinner, ignores input and
// draws the disabled look while keeping the track focusable. name, or
// the widget labelled_by names, is its accessible name: On/Off is its
// state, not its name.
//
// Departures: it is announced as a switch (ops has no pressed state for
// a toggle button: toggle-switch.json notes allow the platform's switch
// role); disabled takes no input or focus, as jm:ui's disabled is not
// focusable; the loading label is not announced after its delay, as
// jm:ui has no live regions, though the switch is marked busy; the
// coarse-pointer 44px target is not drawn.
toggle_switch :: proc(
	gtx: ^ui.Ctx,
	on: ^bool,
	name := "",
	size := Switch_Size.Medium,
	status_position := Status_Position.Start,
	label_on := "On",
	label_off := "Off",
	loading := false,
	labelled_by: ops.Area_Id = 0,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	fc := field_context(gtx, p.id, name, .None, false, state)
	small := size == .Small
	track_sz := small ? ops.Size{48, 24} : ops.Size{64, 32}
	st := tok.Type_Style{weight = tok.BASE_TEXT_WEIGHT_NORMAL, size = small ? tok.TEXT_BODY_SIZE_SMALL : tok.TEXT_BODY_SIZE_MEDIUM}
	st.line_height = st.size * 1.5
	font := font_for(gtx, st.weight)
	t_on := design.shape_style(gtx, label_on, st, font)
	t_off := design.shape_style(gtx, label_off, st, font)
	label_w := max(t_on.width, t_off.width)
	gap := tok.BASE_SIZE_8
	spin_w: f32 = loading ? BUTTON_ICON : 0
	h := max(track_sz.y, st.line_height, spin_w)
	w := spin_w + 2 * gap + label_w + track_sz.x
	if loading && status_position == .End {
		w += gap
	}
	sz := ui.constrain_min(gtx.constraints, {w, h})
	// Start: spinner, label, track; End reverses the row and gives the
	// spinner an 8px start margin (ToggleSwitch.module.css:9-24).
	track, text_box, spin: ops.Rect
	if status_position == .Start {
		spin = {0, (h - spin_w) / 2, spin_w, spin_w}
		text_box = {spin_w, (h - st.line_height) / 2, 2 * gap + label_w, st.line_height}
		track = {text_box.x + text_box.w, (h - track_sz.y) / 2, track_sz.x, track_sz.y}
	} else {
		track = {0, (h - track_sz.y) / 2, track_sz.x, track_sz.y}
		text_box = {track_sz.x, (h - st.line_height) / 2, 2 * gap + label_w, st.line_height}
		spin = {text_box.x + text_box.w + gap, (h - spin_w) / 2, spin_w, spin_w}
	}
	c := control(gtx, p.id, track, fc.state)
	label_id := ui.id_mix(p.id, 0x51a7)
	lc := control(gtx, label_id, text_box, fc.state)
	flipped := (c.clicked || lc.clicked) && !c.disabled && !loading
	if flipped {
		on^ = !on^
	}
	look := c
	if loading {
		look.disabled, look.state = true, .Disabled
	}
	paint_switch(gtx, look, p.id, track, on^, small)
	if loading {
		paint_spinner(gtx, {spin.x, spin.y}, BUTTON_ICON, color(.Fg_Color_Default))
	}
	words := on^ ? t_on : t_off
	draw_text(gtx, words, {text_box.x + gap + label_w - words.width, text_box.y}, color(look.disabled ? .Fg_Color_Muted : .Fg_Color_Default))
	listen(gtx, c.st, p.id, track, cursor = .Pointer)
	listen(gtx, lc.st, label_id, text_box, {.Press, .Release, .Enter, .Leave}, .Pointer)
	said := ui.frame_string(gtx, fc.name)
	ops.tag(gtx.scene, p.id, said != "" ? said : "toggle switch")
	ops.tag(gtx.scene, label_id, ui.frame_string(gtx, on^ ? label_on : label_off))
	states := design.state_if(on^, {.Checked}) + design.state_if(look.disabled, {.Disabled}) + design.state_if(loading, {.Busy})
	ui.semantics(gtx, &p, {role = .Switch, label = said, labelled_by = labelled_by, states = states})
	ui.widget_close(gtx, &p, {sz, text_box.y + baseline_of(words)})
	return flipped
}

// paint_switch draws the track, glyphs and knob at their slide position,
// and the keyboard outline.
@(private)
paint_switch :: proc(gtx: ^ui.Ctx, c: Control, id: ops.Area_Id, track: ops.Rect, on, small: bool) {
	b := tok.BORDER_WIDTH_THIN
	rr := ops.Round_Rect{track, tok.BORDER_RADIUS_DEFAULT}
	bg, border, knob_bg, knob_border: tok.Role
	switch {
	case c.disabled:
		bg, border = .Control_Track_Bg_Color_Disabled, .Bg_Color_Transparent
		knob_bg, knob_border = .Control_Knob_Bg_Color_Disabled, .Control_Track_Bg_Color_Disabled
	case on:
		bg = role_for({.Control_Checked_Bg_Color_Rest, .Control_Checked_Bg_Color_Hover, .Control_Checked_Bg_Color_Active, .Control_Checked_Bg_Color_Rest}, c)
		border, knob_bg, knob_border = .Control_Checked_Border_Color_Rest, .Control_Knob_Bg_Color_Rest, .Control_Knob_Border_Color_Checked
	case:
		bg = role_for({.Control_Track_Bg_Color_Rest, .Control_Track_Bg_Color_Hover, .Control_Track_Bg_Color_Active, .Control_Track_Bg_Color_Rest}, c)
		border, knob_bg, knob_border = .Control_Track_Border_Color_Rest, .Control_Knob_Bg_Color_Rest, .Control_Knob_Border_Color_Rest
	}
	// Keyboard focus takes the hover fill (ToggleSwitch.module.css:136-158).
	if c.focus_visible && !c.pressed && !c.disabled {
		bg = on ? .Control_Checked_Bg_Color_Hover : .Control_Track_Bg_Color_Hover
	}
	duration := c.disabled ? 0 : SWITCH_SLIDE.duration // no transitions when disabled
	fill := design.blend(gtx, c.fades, 0, color(bg), duration, SWITCH_SLIDE.easing)
	edge := design.blend(gtx, c.fades, 1, color(border), duration, SWITCH_SLIDE.easing)
	ops.fill(gtx.scene, rr, fill)
	if ui.painted(edge) {
		stroke_inside(gtx, rr, edge, b)
	}
	t := switch_position(gtx, c, id, on)
	inner := ops.Rect{track.x + b, track.y + b, track.w - 2 * b, track.h - 2 * b}
	half := inner.w / 2
	glyph: f32 = small ? 12 : 16
	gy := inner.y + (inner.h - glyph) / 2
	ops.clip_push(gtx.scene, ops.Round_Rect{inner, rr.radius - b})
	line_x := inner.x + (half - glyph) / 2 + (t - 1) * half
	paint_svg(gtx, SWITCH_LINE, 16, {line_x, gy}, glyph, color(c.disabled ? .Control_Checked_Fg_Color_Disabled : .Control_Checked_Fg_Color_Rest))
	ring_centre := ops.Point{inner.x + half + half / 2 + t * half, gy + glyph / 2}
	k := glyph / 16
	ops.stroke(gtx.scene, ui.circle(ring_centre, 5.25 * k), color(c.disabled ? .Control_Track_Fg_Color_Disabled : .Control_Track_Fg_Color_Rest), {width = 1.5 * k})
	knob := ops.Rect{inner.x + 1 + t * (half - 2), inner.y + 1, half, inner.h - 2}
	krr := ops.Round_Rect{knob, tok.BORDER_RADIUS_DEFAULT - tok.BORDER_WIDTH_THICK}
	ops.fill(gtx.scene, krr, color(knob_bg))
	stroke_inside(gtx, krr, design.blend(gtx, c.fades, 2, color(knob_border), duration, SWITCH_SLIDE.easing), b)
	ops.clip_pop(gtx.scene)
	paint_focus_outline(gtx, c, rr, SWITCH_FOCUS_OFFSET)
}
