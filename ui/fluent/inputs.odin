package fluent

import "base:runtime"
import "jm:ui"
import "jm:ui/ops"
import tok "jm:ui/fluent/tokens"

// Text entry and what names it: input, textarea, field, label and link,
// on the fluent-kit's components/input.json, textarea.json, field.json,
// label.json and link.json and the styles files they cite at the kit's
// commit. Editing is jm:ui's single-line model (ui.Text_State,
// ui.text_key, ui.text_hit); textarea keeps the same buffer with
// newlines in it and does its own line wrapping and vertical caret
// moves, as ui has no multi-line editor.
//
// Departures: the native input types (email, password, number, ...),
// resize handles, and the anchor/button element choice have no jm:ui
// counterpart; an input's hit area is its box, so a link's is the text
// box the spec warns is under 24px tall.

// Input_Appearance is an input's colour and border treatment. Underline
// is input's only; textarea reads it as outline. The two _Shadow values
// are deprecated in Fluent and add shadow2.
Input_Appearance :: enum u8 {
	Outline,
	Underline,
	Filled_Darker,
	Filled_Lighter,
	Filled_Darker_Shadow,
	Filled_Lighter_Shadow,
}

// Edit is what one frame of an input did to its text.
Edit :: struct {
	changed:   bool, // the text is not what it was
	submitted: bool, // Enter while focused (input only)
	focused:   bool,
}

// EDIT_KINDS is what an input's area asks for: a click's kinds plus
// typed text and the wheel.
EDIT_KINDS :: ops.Event_Kinds{.Press, .Release, .Enter, .Leave, .Move, .Key, .Text, .Focus, .Blur, .Scroll}

// BORDER is the input border: strokeWidthThin, which the input's styles
// file spells as a 1px constant (useInputStyles.styles.ts:42-59) and
// the textarea's as the token.
@(private = "file")
BORDER :: tok.STROKE_WIDTH_THIN

// FOCUS_LINE is the focus line's thickness and its outset from the box
// (useInputStyles.styles.ts:61-85), the focus outline's own width.
@(private = "file")
FOCUS_LINE :: FOCUS_OUTLINE_WIDTH

// CARET_W is the caret's width; jm:ui draws no native caret.
@(private = "file")
CARET_W :: f32(1)

// DEFAULT_WIDTH is an input's width where its constraints leave it free.
@(private = "file")
DEFAULT_WIDTH :: f32(200)

// Input_Metrics are one size's numbers (useInputStyles.styles.ts:16-40,
// 119-130, 218-235, 264-292, 303-326): the minimum height, the text's
// inset with no content slot, the root's and the text's inset beside a
// slot, the icon size, the slot-to-text gap and the text style.
@(private = "file")
Input_Metrics :: struct {
	min_h, pad, root_pad, inner_pad, icon, gap: f32,
	style:                                     tok.Type_Style,
}

@(private = "file")
input_metrics :: proc(size: Size) -> Input_Metrics {
	switch size {
	case .Small:
		return {24, tok.SPACING_HORIZONTAL_S, tok.SPACING_HORIZONTAL_SNUDGE, tok.SPACING_HORIZONTAL_XXS, 16, tok.SPACING_HORIZONTAL_XXS, style(.Caption1)}
	case .Medium:
	case .Large:
		return {40, tok.SPACING_HORIZONTAL_M + tok.SPACING_HORIZONTAL_SNUDGE, tok.SPACING_HORIZONTAL_M, tok.SPACING_HORIZONTAL_SNUDGE, 24, tok.SPACING_HORIZONTAL_SNUDGE, style(.Body2)}
	}
	return {32, tok.SPACING_HORIZONTAL_M, tok.SPACING_HORIZONTAL_MNUDGE, tok.SPACING_HORIZONTAL_XXS, 20, tok.SPACING_HORIZONTAL_XXS, style(.Body1)}
}

// Input_Colors are an input's resolved colours for one frame.
@(private = "file")
Input_Colors :: struct {
	bg, border, bottom, text, placeholder, content, line: ops.Color,
}

// input_colors is the appearance's colours for c (useInputStyles.
// styles.ts:56-59, 109-217): nothing transitions, so they are read, not
// blended. Focus shows the pressed border; invalid turns every border
// red until focus is within; disabled drops the fill and takes the
// Disabled tokens. The focus line is Compound_Brand_Stroke, pressed
// while a focused input is clicked again.
@(private = "file")
input_colors :: proc(a: Input_Appearance, c: Control, invalid: bool) -> (k: Input_Colors) {
	filled := a >= .Filled_Darker
	darker := a == .Filled_Darker || a == .Filled_Darker_Shadow
	shadow := a >= .Filled_Darker_Shadow
	k.text, k.placeholder, k.content = color(.Neutral_Foreground1), color(.Neutral_Foreground4), color(.Neutral_Foreground3)
	k.line = color(c.pressed ? .Compound_Brand_Stroke_Pressed : .Compound_Brand_Stroke)
	switch {
	case a == .Underline:
		k.bg = color(.Transparent_Background)
	case darker:
		k.bg = color(.Neutral_Background3)
	case:
		k.bg = color(.Neutral_Background1)
	}
	if c.disabled {
		k.bg = color(.Transparent_Background)
		k.border, k.bottom = color(.Neutral_Stroke_Disabled), color(.Neutral_Stroke_Disabled)
		k.text, k.placeholder, k.content = color(.Neutral_Foreground_Disabled), color(.Neutral_Foreground_Disabled), color(.Neutral_Foreground_Disabled)
		k.line = {}
		return
	}
	active := c.focused || c.pressed
	switch {
	case filled:
		k.border = color(active || c.hovered || shadow ? .Transparent_Stroke_Interactive : .Transparent_Stroke)
		k.bottom = k.border
	case active:
		k.border, k.bottom = color(.Neutral_Stroke1_Pressed), color(.Neutral_Stroke_Accessible_Pressed)
	case c.hovered:
		k.border, k.bottom = color(.Neutral_Stroke1_Hover), color(.Neutral_Stroke_Accessible_Hover)
	case:
		k.border, k.bottom = color(.Neutral_Stroke1), color(.Neutral_Stroke_Accessible)
	}
	if invalid && !active {
		k.border, k.bottom = color(.Palette_Red_Border2), color(.Palette_Red_Border2)
	}
	if a == .Underline {
		k.border = {}
	}
	return
}

// Focus_Line is an input's focus line between frames: its scale, easing
// toward 1 when focus enters over DURATION_NORMAL with CURVE_DECELERATE_
// MID and back to 0 over DURATION_ULTRA_FAST with CURVE_ACCELERATE_MID
// (input.json behaviour focus-line-motion; the styles file writes those
// curves to transitionDelay, which input.json's upstream-bug note says
// to read as the timing function).
@(private = "file")
Focus_Line :: struct {
	from, to: f32,
	tween:    ui.Tween,
	curve:    tok.Bezier,
	live:     bool,
}

// focus_line_scale is the line's scale this frame for c: the target at
// once for a forced state or a disabled input, eased for a live one.
@(private = "file")
focus_line_scale :: proc(gtx: ^ui.Ctx, c: Control, id: ops.Area_Id) -> f32 {
	if c.disabled {
		return 0
	}
	target: f32 = c.focused ? 1 : 0
	if c.st == nil {
		return target
	}
	f := ui.widget_data(gtx, id, Focus_Line)
	if !f.live {
		f^ = {from = target, to = target, live = true}
		return target
	}
	if target != f.to {
		f.from = focus_line_value(f)
		f.to = target
		f.tween = {to = 1, duration = (target == 1 ? tok.DURATION_NORMAL : tok.DURATION_ULTRA_FAST) / 1000}
		f.curve = target == 1 ? tok.CURVE_DECELERATE_MID : tok.CURVE_ACCELERATE_MID
	}
	ui.tween_update(&f.tween, gtx)
	return focus_line_value(f)
}

@(private = "file")
focus_line_value :: proc(f: ^Focus_Line) -> f32 {
	if f.tween.duration <= 0 {
		return f.to
	}
	return f.from + (f.to - f.from) * bezier_ease(f.curve, f.tween.t / f.tween.duration)
}

// paint_focus_line paints the line under box r at scale t: FOCUS_LINE
// thick, outset px outside the left, right and bottom edges, following
// the box's bottom corners at radius, and grown from the centre
// (useInputStyles.styles.ts:61-85; underline passes outset and radius
// 0 so the line spans exactly the border with square ends).
@(private = "file")
paint_focus_line :: proc(gtx: ^ui.Ctx, r: ops.Rect, outset, radius, t: f32, col: ops.Color) {
	if t <= 0 || !ui.painted(col) {
		return
	}
	full := r.w + 2 * outset
	w := full * clamp(t, 0, 1)
	bottom := r.y + r.h + outset
	ops.clip_push(gtx.scene, ops.Rect{r.x - outset + (full - w) / 2, bottom - FOCUS_LINE, w, FOCUS_LINE})
	h := max(radius, FOCUS_LINE)
	ops.fill(gtx.scene, rounded(gtx, {r.x - outset, bottom - h, full, h}, {0, 0, radius, radius}), col)
	ops.clip_pop(gtx.scene)
}

// Input_Scroll is a single-line input's horizontal scroll, kept so the
// caret stays in view.
@(private = "file")
Input_Scroll :: struct {
	x: f32,
}

// input is a single-line text entry (input.json). s is the caller's
// buffer. placeholder shows in Neutral_Foreground4 while s is empty;
// before and after are the content slots' icons; invalid draws the
// error border; width is the box's width, else the constraints' or
// DEFAULT_WIDTH. name is the accessible name the tag carries, else the
// placeholder. Typing edits s; Enter sets submitted.
input :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	placeholder := "",
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	before := Icon.None,
	after := Icon.None,
	invalid := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Edit) {
	p := ui.widget_open(gtx, key, loc)
	m := input_metrics(size)
	cs := gtx.constraints
	w := width
	if w <= 0 {
		w = ui.is_finite(cs.max.x) ? cs.max.x : DEFAULT_WIDTH
	}
	sz := ui.constrain(cs, {w, m.min_h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	ui.text_clamp(s)

	// The text's inset: the whole pad with no slot, the split beside one.
	left := before != .None ? m.root_pad + m.icon + m.gap + m.inner_pad : m.pad
	right := after != .None ? m.root_pad + m.icon + m.gap + m.inner_pad : m.pad
	inner := max(sz.x - left - right, 0)
	sc := c.st != nil ? ui.widget_data(gtx, p.id, Input_Scroll) : nil
	if c.st != nil {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press, .Move, .Release:
				ui.text_follow_pointer(s, layout_style(gtx, string(s.buf[:]), m.style), e, {e.pos.x - left + sc.x, 0}, text_stops(gtx, s, m.style))
			case .Text, .Paste:
				r.changed |= ui.text_edit(gtx, s, p.id, e, text_stops(gtx, s, m.style))
			case .Key:
				if e.key == .Enter {
					r.submitted = true
				} else {
					r.changed |= ui.text_edit(gtx, s, p.id, e, text_stops(gtx, s, m.style))
				}
			}
		}
	}
	r.focused = c.focused && !c.disabled
	str := string(s.buf[:])
	t := layout_style(gtx, str, m.style)
	_, caret := ui.paragraph_caret(t, s.cursor)
	scroll: f32
	if sc != nil {
		sc.x = min(sc.x, max(t.width + CARET_W - inner, 0))
		sc.x = max(clamp(sc.x, caret + CARET_W - inner, caret), 0)
		scroll = sc.x
	}

	k := input_colors(appearance, c, invalid)
	underline := appearance == .Underline
	rad := underline ? 0 : tok.BORDER_RADIUS_MEDIUM
	if appearance >= .Filled_Darker_Shadow {
		paint_shadow(gtx, {area, rad}, tok.SHADOW2)
	}
	if ui.painted(k.bg) {
		ops.fill(gtx.scene, ops.Round_Rect{area, rad}, k.bg)
	}
	if ui.painted(k.border) {
		stroke_inside(gtx, {area, rad}, k.border, BORDER)
	}
	if ui.painted(k.bottom) {
		// The bottom edge is its own token (input.json notes): drawn over
		// the border's bottom run, clear of the rounded corners.
		ops.fill(gtx.scene, ops.Rect{area.x + rad, area.y + area.h - BORDER, area.w - 2 * rad, BORDER}, k.bottom)
	}
	y_text := (sz.y - m.style.line_height) / 2
	if before != .None {
		icon(gtx, before, {m.root_pad, (sz.y - m.icon) / 2}, m.icon, k.content)
	}
	if after != .None {
		icon(gtx, after, {sz.x - m.root_pad - m.icon, (sz.y - m.icon) / 2}, m.icon, k.content)
	}
	ops.clip_push(gtx.scene, ops.Rect{left, BORDER, inner, sz.y - 2 * BORDER})
	if len(str) > 0 {
		draw_paragraph(gtx, t, {left - scroll, y_text}, k.text, selection_paint(s, r.focused))
	} else if placeholder != "" {
		draw_text(gtx, shape_style(gtx, placeholder, m.style), {left, y_text}, k.placeholder)
	}
	if r.focused {
		ops.fill(gtx.scene, ops.Rect{left + caret - scroll, y_text + 2, CARET_W, m.style.line_height - 4}, k.text)
	}
	ops.clip_pop(gtx.scene)
	paint_focus_line(gtx, area, underline ? 0 : BORDER, rad, focus_line_scale(gtx, c, p.id), k.line)
	listen(gtx, c.st, p.id, area, EDIT_KINDS, .Text)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : placeholder))
	ui.widget_close(gtx, &p, {sz, y_text + t.lines[0].baseline})
	return
}

// Textarea_Metrics are one size's numbers (useTextareaStyles.styles.ts:
// 179-198): the text area's minimum and maximum height, its vertical
// and horizontal padding and its text style.
@(private = "file")
Textarea_Metrics :: struct {
	min_h, max_h, pad_v, pad_h: f32,
	style:                     tok.Type_Style,
}

@(private = "file")
textarea_metrics :: proc(size: Size) -> Textarea_Metrics {
	switch size {
	case .Small:
		return {40, 200, tok.SPACING_VERTICAL_XS, tok.SPACING_HORIZONTAL_SNUDGE + tok.SPACING_HORIZONTAL_XXS, style(.Caption1)}
	case .Medium:
	case .Large:
		return {64, 320, tok.SPACING_VERTICAL_S, tok.SPACING_HORIZONTAL_M + tok.SPACING_HORIZONTAL_XXS, style(.Body2)}
	}
	return {52, 260, tok.SPACING_VERTICAL_SNUDGE, tok.SPACING_HORIZONTAL_MNUDGE + tok.SPACING_HORIZONTAL_XXS, style(.Body1)}
}

// Textarea_Scroll is a textarea's vertical scroll, kept so the caret
// stays in view once the text outgrows the size's maximum height.
@(private = "file")
Textarea_Scroll :: struct {
	y: f32,
}

// textarea is a multi-line text entry (textarea.json): s holds the text
// with newlines, Enter inserts one, Up and Down move the caret between
// lines and Home and End along one. Its height follows the lines from
// the size's minimum to its maximum, then the text scrolls. Underline
// is not a textarea appearance and reads as outline. The native resize
// handle has no counterpart.
textarea :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	placeholder := "",
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	invalid := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Edit) {
	p := ui.widget_open(gtx, key, loc)
	m := textarea_metrics(size)
	a := appearance == .Underline ? Input_Appearance.Outline : appearance
	cs := gtx.constraints
	w := width
	if w <= 0 {
		w = ui.is_finite(cs.max.x) ? cs.max.x : DEFAULT_WIDTH
	}
	ui.text_clamp(s)
	str := string(s.buf[:])
	inner_w := max(w - 2 * BORDER - 2 * m.pad_h, 1)
	lh := m.style.line_height
	para := layout_style(gtx, str, m.style, inner_w)
	// The text area's height: its lines plus padding, between the size's
	// bounds; the root adds the borders and FOCUS_LINE of bottom padding
	// (useTextareaStyles.styles.ts:17-26). Sized again after this frame's
	// edits, so a new line grows the box in the frame that adds it.
	box_for :: proc(cs: ui.Constraints, w: f32, lines: int, m: Textarea_Metrics) -> (sz: ops.Size, box: ops.Rect) {
		text_h := clamp(f32(lines) * m.style.line_height + 2 * m.pad_v, m.min_h, m.max_h)
		sz = ui.constrain(cs, {w, text_h + 2 * BORDER + FOCUS_LINE})
		box = {0, 0, sz.x, sz.y - FOCUS_LINE}
		return
	}
	sz, box := box_for(cs, w, len(para.lines), m)
	c := control(gtx, p.id, box, state)
	sc := c.st != nil ? ui.widget_data(gtx, p.id, Textarea_Scroll) : nil
	text_x, text_y := BORDER + m.pad_h, BORDER + m.pad_v
	if c.st != nil {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press, .Move, .Release:
				ui.text_follow_pointer(s, para, e, {e.pos.x - text_x, e.pos.y - text_y + sc.y}, text_stops(gtx, s, m.style))
			case .Scroll:
				sc.y += e.scroll.y * ui.SCROLL_STEP
			case .Text, .Paste:
				r.changed |= ui.text_edit(gtx, s, p.id, e, text_stops(gtx, s, m.style))
			case .Key:
				// Lines are the textarea's: moves along them extend with
				// Shift like text_edit's own; the rest is text_edit's.
				extend := .Shift in e.mods
				#partial switch e.key {
				case .Enter:
					ui.text_replace(s, "\n")
					r.changed = true
				case .Up, .Down:
					li, x := ui.paragraph_caret(para, s.cursor)
					to := li + (e.key == .Up ? -1 : 1)
					if to >= 0 && to < len(para.lines) {
						ui.text_move(s, ui.paragraph_hit(para, {x, (f32(to) + 0.5) * para.pitch}), extend)
					}
				case .Home:
					ui.text_move(s, para.lines[ui.paragraph_line_of(para, s.cursor)].start, extend)
				case .End:
					ui.text_move(s, ui.paragraph_line_end(para, ui.paragraph_line_of(para, s.cursor)), extend)
				case:
					r.changed |= ui.text_edit(gtx, s, p.id, e, text_stops(gtx, s, m.style))
				}
			}
		}
		if r.changed {
			str = string(s.buf[:])
			para = layout_style(gtx, str, m.style, inner_w)
			sz, box = box_for(cs, w, len(para.lines), m)
		}
	}
	text_h := box.h - 2 * BORDER
	r.focused = c.focused && !c.disabled
	li, cx := ui.paragraph_caret(para, s.cursor)
	content_h := para.height
	view_h := text_h - 2 * m.pad_v
	scroll: f32
	if sc != nil {
		sc.y = clamp(sc.y, 0, max(content_h - view_h, 0))
		if r.focused {
			// Keep the caret's line in view.
			sc.y = clamp(sc.y, f32(li + 1) * lh - view_h, f32(li) * lh)
			sc.y = clamp(sc.y, 0, max(content_h - view_h, 0))
		}
		scroll = sc.y
	}

	k := input_colors(a, c, invalid)
	rad := tok.BORDER_RADIUS_MEDIUM
	if a >= .Filled_Darker_Shadow && !c.disabled {
		paint_shadow(gtx, {box, rad}, tok.SHADOW2)
	}
	if ui.painted(k.bg) {
		ops.fill(gtx.scene, ops.Round_Rect{box, rad}, k.bg)
	}
	if ui.painted(k.border) {
		stroke_inside(gtx, {box, rad}, k.border, BORDER)
	}
	if ui.painted(k.bottom) && !c.disabled {
		// Outline's focused bottom is Compound_Brand_Stroke here, where
		// input's is the pressed accessible stroke (textarea.json notes).
		bottom := a == .Outline && c.focused ? color(.Compound_Brand_Stroke) : k.bottom
		ops.fill(gtx.scene, ops.Rect{box.x + rad, box.y + box.h - BORDER, box.w - 2 * rad, BORDER}, bottom)
	}
	ops.clip_push(gtx.scene, ops.Rect{BORDER, text_y, box.w - 2 * BORDER, view_h})
	if len(str) == 0 && placeholder != "" {
		draw_text(gtx, shape_style(gtx, placeholder, m.style), {text_x, text_y}, k.placeholder)
	}
	draw_paragraph(gtx, para, {text_x, text_y - scroll}, k.text, selection_paint(s, r.focused))
	if r.focused {
		ops.fill(gtx.scene, ops.Rect{text_x + cx, text_y + f32(li) * lh - scroll + 2, CARET_W, lh - 4}, k.text)
	}
	ops.clip_pop(gtx.scene)
	paint_focus_line(gtx, box, BORDER, rad, focus_line_scale(gtx, c, p.id), k.line)
	listen(gtx, c.st, p.id, box, EDIT_KINDS, .Text)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : placeholder))
	ui.widget_close(gtx, &p, {sz, text_y + para.lines[0].baseline})
	return
}

// Weight is a label's weight: regular, or semibold for emphasis.
Weight :: enum u8 {
	Regular,
	Semibold,
}

// label_style is a label's text style (useLabelStyles.styles.ts:34-48):
// the size's base font size and line height, semibold at large always.
@(private = "file")
label_style :: proc(size: Size, weight: Weight) -> tok.Type_Style {
	w := weight == .Semibold || size == .Large ? tok.FONT_WEIGHT_SEMIBOLD : tok.FONT_WEIGHT_REGULAR
	return control_style(size, w)
}

// label is text that names a control (label.json): Neutral_Foreground1
// at the size's style, with a required asterisk in Palette_Red_
// Foreground3 spacingHorizontalXS after it; disabled draws both in the
// Disabled foreground. It is not focusable; the control it names draws
// the focus.
label :: proc(gtx: ^ui.Ctx, text: string, required := false, size := Size.Medium, weight := Weight.Regular, disabled := false, key: u64 = 0, loc := #caller_location) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	st := label_style(size, weight)
	t := shape_style(gtx, text, st)
	w := t.width
	star: Text
	if required {
		star = shape_style(gtx, "*", st)
		w += tok.SPACING_HORIZONTAL_XS + star.width
	}
	sz := ui.constrain(gtx.constraints, {w, st.line_height})
	fg := color(disabled ? .Neutral_Foreground_Disabled : .Neutral_Foreground1)
	draw_text(gtx, t, {0, 0}, fg)
	if required {
		draw_text(gtx, star, {t.width + tok.SPACING_HORIZONTAL_XS, 0}, color(disabled ? .Neutral_Foreground_Disabled : .Palette_Red_Foreground3))
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	return ui.widget_close(gtx, &p, {sz, baseline_of(t)})
}

// Validation is a field's message state: it colours the message icon
// and, for Error, the text (field.json).
Validation :: enum u8 {
	None,
	Error,
	Warning,
	Success,
}

// Orientation is where a field's label sits: above the control, or in a
// column to its left.
Orientation :: enum u8 {
	Vertical,
	Horizontal,
}

// LABEL_COLUMN is a horizontal field's label column, a share of its
// width (useFieldStyles.styles.ts:22-32).
@(private = "file")
LABEL_COLUMN :: f32(0.33)

// VALIDATION_ICON is the message icon's size (useFieldStyles.styles.ts:
// 16-17, 92-108).
@(private = "file")
VALIDATION_ICON :: f32(12)

// Field is an open field: the containers field_open opened, which
// field_close closes after drawing the message and hint below the body.
Field :: struct {
	outer:                    ui.Flex, // the row (horizontal) or the column (vertical)
	inner:                    ui.Flex, // horizontal: the column beside the label
	horizontal:               bool,
	hint, message:            string,
	validation:               Validation,
	disabled:                 bool,
}

// field_open opens a field (field.json) around one control: label above
// (or to the left, in a LABEL_COLUMN column, for Horizontal), then the
// body the caller draws, then the validation message with its state
// icon and the hint, both caption1 in Neutral_Foreground3. The label's
// padding aligns it with a control of the same size. A message with
// Validation.None shows without an icon; the control's own invalid
// look is the caller's to set.
field_open :: proc(
	gtx: ^ui.Ctx,
	text: string,
	required := false,
	hint := "",
	message := "",
	validation := Validation.Error,
	orientation := Orientation.Vertical,
	size := Size.Medium,
	disabled := false,
	key: u64 = 0,
	loc := #caller_location,
) -> (f: Field) {
	f.hint, f.message = ui.frame_string(gtx, hint), ui.frame_string(gtx, message)
	f.validation, f.disabled = validation, disabled
	f.horizontal = orientation == .Horizontal && ui.is_finite(gtx.constraints.max.x)
	if !f.horizontal {
		// Vertical: spacingVerticalXXS around the label and below it, 1px
		// and spacingVerticalXS at large (useFieldStyles.styles.ts:43-58).
		pad, gap := tok.SPACING_VERTICAL_XXS, tok.SPACING_VERTICAL_XXS
		if size == .Large {
			pad, gap = 1, tok.SPACING_VERTICAL_XS
		}
		f.outer = ui.column_open(gtx, key = key, loc = loc)
		if text != "" {
			in_ := ui.inset_open(gtx, {0, pad, 0, pad + gap})
			label(gtx, text, required, size, disabled = disabled)
			ui.close(&in_)
		}
		return
	}
	// Horizontal: the label column pads so its text centres on a
	// control of its size, spacingHorizontalM before the control
	// (useFieldStyles.styles.ts:60-78).
	pad: f32
	switch size {
	case .Small:
		pad = tok.SPACING_VERTICAL_XS
	case .Medium:
		pad = tok.SPACING_VERTICAL_SNUDGE
	case .Large:
		pad = 9 // (40px - lineHeightBase400) / 2, no token
	}
	col_w := gtx.constraints.max.x * LABEL_COLUMN
	f.outer = ui.row_open(gtx, key = key, loc = loc)
	{
		// The column's width is a spacer's, laid in a row so it spans only
		// width; the label sits over it.
		st := ui.stack_open(gtx)
		sp := ui.row_open(gtx)
		ui.spacer(gtx, col_w)
		ui.close(&sp)
		in_ := ui.inset_open(gtx, {0, pad, tok.SPACING_HORIZONTAL_M, pad})
		if text != "" {
			label(gtx, text, required, size, disabled = disabled)
		}
		ui.close(&in_)
		ui.close(&st)
	}
	ui.flexible(gtx, 1)
	f.inner = ui.column_open(gtx)
	return
}

// field_close draws the message and hint under the body and closes what
// field_open opened.
field_close :: proc(gtx: ^ui.Ctx, f: ^Field) {
	if f.message != "" {
		ic: Icon
		tint := color(.Neutral_Foreground3)
		switch f.validation {
		case .None:
		case .Error:
			ic, tint = .Error_Circle_Filled, color(.Palette_Red_Foreground1)
		case .Warning:
			ic, tint = .Warning_Filled, color(.Palette_Dark_Orange_Foreground1)
		case .Success:
			ic, tint = .Checkmark_Circle_Filled, color(.Palette_Green_Foreground1)
		}
		text := f.validation == .Error ? tint : color(.Neutral_Foreground3)
		paint_secondary_text(gtx, f.message, text, ic, tint, 1)
	}
	if f.hint != "" {
		paint_secondary_text(gtx, f.hint, color(.Neutral_Foreground3), .None, {}, 2)
	}
	if f.horizontal {
		ui.close(&f.inner)
	}
	ui.close(&f.outer)
}

// paint_secondary_text is a field's message or hint: caption1 with
// spacingVerticalXXS above, and with an icon a VALIDATION_ICON gutter
// before the text, the icon shifted 1px down (useFieldStyles.styles.ts:
// 81-108). A widget of its own so a probe finds it by its text.
@(private = "file")
paint_secondary_text :: proc(gtx: ^ui.Ctx, text: string, fg: ops.Color, ic: Icon, tint: ops.Color, key: u64) {
	p := ui.widget_open(gtx, key)
	st := style(.Caption1)
	t := shape_style(gtx, text, st)
	gutter := ic != .None ? VALIDATION_ICON + tok.SPACING_HORIZONTAL_XS : 0
	sz := ui.constrain(gtx.constraints, {gutter + t.width, tok.SPACING_VERTICAL_XXS + st.line_height})
	y := tok.SPACING_VERTICAL_XXS
	if ic != .None {
		icon(gtx, ic, {0, y + (st.line_height - VALIDATION_ICON) / 2 + 1}, VALIDATION_ICON, tint)
	}
	draw_text(gtx, t, {gutter, y}, fg)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	ui.widget_close(gtx, &p, {sz, y + baseline_of(t)})
}

// field is field_open as a guard: `if fluent.field(gtx, "Name") { … }`
// draws the body inside and closes itself at the end of the if (see
// ui/guards.odin).
@(deferred_in = field_guard_close)
field :: proc(
	gtx: ^ui.Ctx,
	text: string,
	required := false,
	hint := "",
	message := "",
	validation := Validation.Error,
	orientation := Orientation.Vertical,
	size := Size.Medium,
	disabled := false,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	f := ui.guard_hold(gtx, Field)
	f^ = field_open(gtx, text, required, hint, message, validation, orientation, size, disabled, key, loc)
	return true
}

@(private = "file")
field_guard_close :: proc(gtx: ^ui.Ctx, text: string, required: bool, hint, message: string, validation: Validation, orientation: Orientation, size: Size, disabled: bool, key: u64, loc: runtime.Source_Code_Location) {
	field_close(gtx, ui.guard_take(gtx, Field))
}

// Link_Appearance is a link's colour family: brand, or neutral until
// hovered.
Link_Appearance :: enum u8 {
	Default,
	Subtle,
}

// Link_Background is the surface a link sits on, which overrides its
// appearance: an inverted surface reads Brand_Foreground_Inverted in
// every state, a brand surface the inverted neutral link family.
Link_Background :: enum u8 {
	Neutral,
	Inverted,
	Brand,
}

// link_colors is a link's text colour for c (useLinkStyles.styles.ts:
// 21-94): instant, no transition.
@(private = "file")
link_colors :: proc(a: Link_Appearance, on: Link_Background, c: Control) -> ops.Color {
	if c.disabled {
		return color(.Neutral_Foreground_Disabled)
	}
	roles: State_Roles
	switch {
	case on == .Inverted:
		roles = {.Brand_Foreground_Inverted, .Brand_Foreground_Inverted, .Brand_Foreground_Inverted, .Neutral_Foreground_Disabled}
	case on == .Brand:
		roles = {.Neutral_Foreground_Inverted_Link, .Neutral_Foreground_Inverted_Link_Hover, .Neutral_Foreground_Inverted_Link_Pressed, .Neutral_Foreground_Disabled}
	case a == .Subtle:
		roles = {.Neutral_Foreground2_Link, .Neutral_Foreground2_Link_Hover, .Neutral_Foreground2_Link_Pressed, .Neutral_Foreground_Disabled}
	case:
		roles = {.Brand_Foreground_Link, .Brand_Foreground_Link_Hover, .Brand_Foreground_Link_Pressed, .Neutral_Foreground_Disabled}
	}
	return color_for(roles, c)
}

// link is text that navigates or acts (link.json): fontSizeBase300 at
// regular weight in the appearance's link colour, underlined
// strokeWidthThin on hover and press (always, when inline), and on
// keyboard focus double-underlined in Stroke_Focus2 in place of an
// outline. Disabled loses its underline in every state. Returns true on
// the frame it is clicked, or activated by Enter while focused. Its hit
// area is the text box, under the foundations' 24px, as the spec warns.
link :: proc(
	gtx: ^ui.Ctx,
	text: string,
	appearance := Link_Appearance.Default,
	inline := false,
	on := Link_Background.Neutral,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	st := control_style(.Medium, tok.FONT_WEIGHT_REGULAR)
	t := shape_style(gtx, text, st)
	sz := ui.constrain(gtx.constraints, {t.width, st.line_height})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	fg := link_colors(appearance, on, c)
	draw_text(gtx, t, {0, 0}, fg)
	base := baseline_of(t)
	if !c.disabled {
		if c.focused {
			fc := color(.Stroke_Focus2)
			ops.fill(gtx.scene, ops.Rect{0, base + 2, t.width, tok.STROKE_WIDTH_THIN}, fc)
			ops.fill(gtx.scene, ops.Rect{0, base + 4, t.width, tok.STROKE_WIDTH_THIN}, fc)
		} else if inline || c.hovered || c.pressed {
			ops.fill(gtx.scene, ops.Rect{0, base + 2, t.width, tok.STROKE_WIDTH_THIN}, fg)
		}
	}
	listen(gtx, c.st, p.id, area, cursor = .Pointer) // a link, as a browser shows one
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, text))
	ui.widget_close(gtx, &p, {sz, base})
	return c.clicked
}
