package material

// Caret_Scroll is a text field's horizontal scroll, kept so the caret
// stays in view.
@(private = "file")
Caret_Scroll :: struct {
	x: f32,
}

import "core:fmt"
import "core:math"
import "core:strings"
import "core:unicode/utf8"
import "jm:ui"
import tok "jm:ui/material/tokens"

// Text fields, per the m3e-kit's components/text-field.json: filled and
// outlined, a label that rests inside and floats (or sits fixed above),
// leading and trailing icons, prefix and suffix, placeholder, supporting
// or error text and a character counter, plus the autocomplete variants'
// options menu. Editing is jm:ui's own single-line model (ui.Text_State,
// ui.text_key, ui.text_hit): the spec's multi-line inputs (singleLine,
// minLines, maxLines) are not supported, since ui.Text_State has no lines.

Text_Field_Kind :: enum u8 {
	Filled,
	Outlined,
}

// Layout values from text-field.json layout, which the tokens lack.

// FIELD_H is the container's minimum height. Only the outlined field has a
// token for it; the filled one shares the value (TextFieldDefaults.kt:83,89).
@(private = "file")
FIELD_H :: tok.OUTLINED_TEXT_FIELD_CONTAINER_HEIGHT

// INSET is the horizontal content inset (TextFieldImpl.kt:2235-2236).
@(private = "file")
INSET :: f32(16)

// ICON_SLOT is an icon's touch target around its 24dp glyph
// (TextFieldImpl.kt:2170-2174).
@(private = "file")
ICON_SLOT :: MIN_TOUCH

// SUPPORT_GAP is the space above the supporting row (TextFieldImpl.kt:2235,2241).
@(private = "file")
SUPPORT_GAP :: f32(4)

// AFFIX_PAD is the prefix's and suffix's gap to the input (TextFieldImpl.kt:2243-2244).
@(private = "file")
AFFIX_PAD :: f32(2)

// NOTCH_PAD is the outline cut's padding either side of the floated label
// (OutlinedTextField.kt:562-591).
@(private = "file")
NOTCH_PAD :: f32(4)

// ABOVE_GAP is the space between a label fixed above the field and the
// container. The kit gives no value for it; 4dp matches the supporting
// row's gap below.
@(private = "file")
ABOVE_GAP :: f32(4)

// CARET_W is the caret's width. The kit has no value for it; 2dp is a
// choice.
@(private = "file")
CARET_W :: f32(2)

// Field_Colors are one field's resolved paint in one look.
@(private = "file")
Field_Colors :: struct {
	container, indicator, label, input, leading, trailing, supporting, caret, placeholder, prefix, suffix: ui.Color,
}

@(private = "file")
Field_Look :: enum u8 {
	Rest,
	Hover,
	Focus,
}

// field_colors resolves kind's colour tokens for error and look. Hover
// recolours the label, input, icons and indicator but draws no state layer
// (text-field.json states).
@(private = "file")
field_colors :: proc(kind: Text_Field_Kind, error: bool, look: Field_Look) -> (f: Field_Colors) {
	set :: proc(f: ^Field_Colors, indicator, label, input, leading, trailing, supporting: tok.Role) {
		f.indicator, f.label, f.input = color(indicator), color(label), color(input)
		f.leading, f.trailing, f.supporting = color(leading), color(trailing), color(supporting)
	}
	switch kind {
	case .Filled:
		f.container = color(tok.FILLED_TEXT_FIELD_CONTAINER_COLOR)
		f.caret = color(tok.FILLED_TEXT_FIELD_CARET_COLOR)
		f.placeholder = color(tok.FILLED_TEXT_FIELD_INPUT_PLACEHOLDER_COLOR)
		f.prefix = color(tok.FILLED_TEXT_FIELD_INPUT_PREFIX_COLOR)
		f.suffix = color(tok.FILLED_TEXT_FIELD_INPUT_SUFFIX_COLOR)
		switch {
		case error && look == .Focus:
			set(&f, tok.FILLED_TEXT_FIELD_ERROR_FOCUS_ACTIVE_INDICATOR_COLOR, tok.FILLED_TEXT_FIELD_ERROR_FOCUS_LABEL_COLOR, tok.FILLED_TEXT_FIELD_ERROR_FOCUS_INPUT_COLOR, tok.FILLED_TEXT_FIELD_ERROR_FOCUS_LEADING_ICON_COLOR, tok.FILLED_TEXT_FIELD_ERROR_FOCUS_TRAILING_ICON_COLOR, tok.FILLED_TEXT_FIELD_ERROR_FOCUS_SUPPORTING_COLOR)
			f.caret = color(tok.FILLED_TEXT_FIELD_ERROR_FOCUS_CARET_COLOR)
		case error && look == .Hover:
			set(&f, tok.FILLED_TEXT_FIELD_ERROR_HOVER_ACTIVE_INDICATOR_COLOR, tok.FILLED_TEXT_FIELD_ERROR_HOVER_LABEL_COLOR, tok.FILLED_TEXT_FIELD_ERROR_HOVER_INPUT_COLOR, tok.FILLED_TEXT_FIELD_ERROR_HOVER_LEADING_ICON_COLOR, tok.FILLED_TEXT_FIELD_ERROR_HOVER_TRAILING_ICON_COLOR, tok.FILLED_TEXT_FIELD_ERROR_HOVER_SUPPORTING_COLOR)
		case error:
			set(&f, tok.FILLED_TEXT_FIELD_ERROR_ACTIVE_INDICATOR_COLOR, tok.FILLED_TEXT_FIELD_ERROR_LABEL_COLOR, tok.FILLED_TEXT_FIELD_ERROR_INPUT_COLOR, tok.FILLED_TEXT_FIELD_ERROR_LEADING_ICON_COLOR, tok.FILLED_TEXT_FIELD_ERROR_TRAILING_ICON_COLOR, tok.FILLED_TEXT_FIELD_ERROR_SUPPORTING_COLOR)
		case look == .Focus:
			set(&f, tok.FILLED_TEXT_FIELD_FOCUS_ACTIVE_INDICATOR_COLOR, tok.FILLED_TEXT_FIELD_FOCUS_LABEL_COLOR, tok.FILLED_TEXT_FIELD_FOCUS_INPUT_COLOR, tok.FILLED_TEXT_FIELD_FOCUS_LEADING_ICON_COLOR, tok.FILLED_TEXT_FIELD_FOCUS_TRAILING_ICON_COLOR, tok.FILLED_TEXT_FIELD_FOCUS_SUPPORTING_COLOR)
		case look == .Hover:
			set(&f, tok.FILLED_TEXT_FIELD_HOVER_ACTIVE_INDICATOR_COLOR, tok.FILLED_TEXT_FIELD_HOVER_LABEL_COLOR, tok.FILLED_TEXT_FIELD_HOVER_INPUT_COLOR, tok.FILLED_TEXT_FIELD_HOVER_LEADING_ICON_COLOR, tok.FILLED_TEXT_FIELD_HOVER_TRAILING_ICON_COLOR, tok.FILLED_TEXT_FIELD_HOVER_SUPPORTING_COLOR)
		case:
			set(&f, tok.FILLED_TEXT_FIELD_ACTIVE_INDICATOR_COLOR, tok.FILLED_TEXT_FIELD_LABEL_COLOR, tok.FILLED_TEXT_FIELD_INPUT_COLOR, tok.FILLED_TEXT_FIELD_LEADING_ICON_COLOR, tok.FILLED_TEXT_FIELD_TRAILING_ICON_COLOR, tok.FILLED_TEXT_FIELD_SUPPORTING_COLOR)
		}
	case .Outlined:
		f.caret = color(tok.OUTLINED_TEXT_FIELD_CARET_COLOR)
		f.placeholder = color(tok.OUTLINED_TEXT_FIELD_INPUT_PLACEHOLDER_COLOR)
		f.prefix = color(tok.OUTLINED_TEXT_FIELD_INPUT_PREFIX_COLOR)
		f.suffix = color(tok.OUTLINED_TEXT_FIELD_INPUT_SUFFIX_COLOR)
		switch {
		case error && look == .Focus:
			set(&f, tok.OUTLINED_TEXT_FIELD_ERROR_FOCUS_OUTLINE_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_FOCUS_LABEL_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_FOCUS_INPUT_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_FOCUS_LEADING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_FOCUS_TRAILING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_FOCUS_SUPPORTING_COLOR)
			f.caret = color(tok.OUTLINED_TEXT_FIELD_ERROR_FOCUS_CARET_COLOR)
		case error && look == .Hover:
			set(&f, tok.OUTLINED_TEXT_FIELD_ERROR_HOVER_OUTLINE_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_HOVER_LABEL_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_HOVER_INPUT_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_HOVER_LEADING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_HOVER_TRAILING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_HOVER_SUPPORTING_COLOR)
		case error:
			set(&f, tok.OUTLINED_TEXT_FIELD_ERROR_OUTLINE_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_LABEL_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_INPUT_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_LEADING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_TRAILING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_ERROR_SUPPORTING_COLOR)
		case look == .Focus:
			set(&f, tok.OUTLINED_TEXT_FIELD_FOCUS_OUTLINE_COLOR, tok.OUTLINED_TEXT_FIELD_FOCUS_LABEL_COLOR, tok.OUTLINED_TEXT_FIELD_FOCUS_INPUT_COLOR, tok.OUTLINED_TEXT_FIELD_FOCUS_LEADING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_FOCUS_TRAILING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_FOCUS_SUPPORTING_COLOR)
		case look == .Hover:
			set(&f, tok.OUTLINED_TEXT_FIELD_HOVER_OUTLINE_COLOR, tok.OUTLINED_TEXT_FIELD_HOVER_LABEL_COLOR, tok.OUTLINED_TEXT_FIELD_HOVER_INPUT_COLOR, tok.OUTLINED_TEXT_FIELD_HOVER_LEADING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_HOVER_TRAILING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_HOVER_SUPPORTING_COLOR)
		case:
			set(&f, tok.OUTLINED_TEXT_FIELD_OUTLINE_COLOR, tok.OUTLINED_TEXT_FIELD_LABEL_COLOR, tok.OUTLINED_TEXT_FIELD_INPUT_COLOR, tok.OUTLINED_TEXT_FIELD_LEADING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_TRAILING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_SUPPORTING_COLOR)
		}
	}
	return
}

// field_disabled_colors is kind's disabled paint: each part's disabled colour at
// its disabled opacity. The placeholder, prefix and suffix have no disabled
// tokens and dim as the input does.
@(private = "file")
field_disabled_colors :: proc(kind: Text_Field_Kind) -> (f: Field_Colors) {
	switch kind {
	case .Filled:
		f.container = token_color(tok.FILLED_TEXT_FIELD_DISABLED_CONTAINER_COLOR, tok.FILLED_TEXT_FIELD_DISABLED_CONTAINER_OPACITY)
		f.indicator = token_color(tok.FILLED_TEXT_FIELD_DISABLED_ACTIVE_INDICATOR_COLOR, tok.FILLED_TEXT_FIELD_DISABLED_ACTIVE_INDICATOR_OPACITY)
		f.label = token_color(tok.FILLED_TEXT_FIELD_DISABLED_LABEL_COLOR, tok.FILLED_TEXT_FIELD_DISABLED_LABEL_OPACITY)
		f.input = token_color(tok.FILLED_TEXT_FIELD_DISABLED_INPUT_COLOR, tok.FILLED_TEXT_FIELD_DISABLED_INPUT_OPACITY)
		f.leading = token_color(tok.FILLED_TEXT_FIELD_DISABLED_LEADING_ICON_COLOR, tok.FILLED_TEXT_FIELD_DISABLED_LEADING_ICON_OPACITY)
		f.trailing = token_color(tok.FILLED_TEXT_FIELD_DISABLED_TRAILING_ICON_COLOR, tok.FILLED_TEXT_FIELD_DISABLED_TRAILING_ICON_OPACITY)
		f.supporting = token_color(tok.FILLED_TEXT_FIELD_DISABLED_SUPPORTING_COLOR, tok.FILLED_TEXT_FIELD_DISABLED_SUPPORTING_OPACITY)
	case .Outlined:
		f.indicator = token_color(tok.OUTLINED_TEXT_FIELD_DISABLED_OUTLINE_COLOR, tok.OUTLINED_TEXT_FIELD_DISABLED_OUTLINE_OPACITY)
		f.label = token_color(tok.OUTLINED_TEXT_FIELD_DISABLED_LABEL_COLOR, tok.OUTLINED_TEXT_FIELD_DISABLED_LABEL_OPACITY)
		f.input = token_color(tok.OUTLINED_TEXT_FIELD_DISABLED_INPUT_COLOR, tok.OUTLINED_TEXT_FIELD_DISABLED_INPUT_OPACITY)
		f.leading = token_color(tok.OUTLINED_TEXT_FIELD_DISABLED_LEADING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_DISABLED_LEADING_ICON_OPACITY)
		f.trailing = token_color(tok.OUTLINED_TEXT_FIELD_DISABLED_TRAILING_ICON_COLOR, tok.OUTLINED_TEXT_FIELD_DISABLED_TRAILING_ICON_OPACITY)
		f.supporting = token_color(tok.OUTLINED_TEXT_FIELD_DISABLED_SUPPORTING_COLOR, tok.OUTLINED_TEXT_FIELD_DISABLED_SUPPORTING_OPACITY)
	}
	f.placeholder, f.prefix, f.suffix = f.input, f.input, f.input
	return
}

// lerp_field_colors blends every part of a toward b by t.
@(private = "file")
lerp_field_colors :: proc(a, b: Field_Colors, t: f32) -> (f: Field_Colors) {
	if t <= 0 {
		return a
	}
	if t >= 1 {
		return b
	}
	f.container = ui.mix(a.container, b.container, t)
	f.indicator = ui.mix(a.indicator, b.indicator, t)
	f.label = ui.mix(a.label, b.label, t)
	f.input = ui.mix(a.input, b.input, t)
	f.leading = ui.mix(a.leading, b.leading, t)
	f.trailing = ui.mix(a.trailing, b.trailing, t)
	f.supporting = ui.mix(a.supporting, b.supporting, t)
	f.caret = ui.mix(a.caret, b.caret, t)
	f.placeholder = ui.mix(a.placeholder, b.placeholder, t)
	f.prefix = ui.mix(a.prefix, b.prefix, t)
	f.suffix = ui.mix(a.suffix, b.suffix, t)
	return
}

// indicator_widths are kind's indicator (filled) or outline (outlined)
// thickness at rest, hovered, focused and disabled.
@(private = "file")
indicator_widths :: proc(kind: Text_Field_Kind) -> (rest, hover, focus, disabled: f32) {
	switch kind {
	case .Filled:
		return tok.FILLED_TEXT_FIELD_ACTIVE_INDICATOR_HEIGHT, tok.FILLED_TEXT_FIELD_HOVER_ACTIVE_INDICATOR_HEIGHT, tok.FILLED_TEXT_FIELD_FOCUS_ACTIVE_INDICATOR_HEIGHT, tok.FILLED_TEXT_FIELD_DISABLED_ACTIVE_INDICATOR_HEIGHT
	case .Outlined:
		return tok.OUTLINED_TEXT_FIELD_OUTLINE_WIDTH, tok.OUTLINED_TEXT_FIELD_HOVER_OUTLINE_WIDTH, tok.OUTLINED_TEXT_FIELD_FOCUS_OUTLINE_WIDTH, tok.OUTLINED_TEXT_FIELD_DISABLED_OUTLINE_WIDTH
	}
	return 1, 1, 2, 1
}

// lerp_style is the type style between a and b at t, the label's float:
// Compose lerps the two typographies rather than scaling one
// (TextFieldImpl.kt:1951).
@(private = "file")
lerp_style :: proc(a, b: tok.Type_Style, t: f32) -> tok.Type_Style {
	l :: proc(x, y, t: f32) -> f32 {return x + (y - x) * t}
	return {l(a.weight, b.weight, t), l(a.size, b.size, t), l(a.line_height, b.line_height, t), l(a.tracking, b.tracking, t)}
}

// Field_Opts are everything text_field and autocomplete share.
@(private = "file")
Field_Opts :: struct {
	label, supporting, placeholder, prefix, suffix: string,
	kind:                                           Text_Field_Kind,
	leading, trailing:                              Icon,
	error, label_above, read_only:                  bool,
	max_length:                                     int,
	width:                                          f32,
	state:                                          Interaction,
	trailing_action:                                ^bool,
	menu:                                           bool, // autocomplete: the trailing arrow turns with open, and Up, Down, Enter and Escape are the menu's
	open:                                           bool,
}

// Field_Result is one frame of a field: what happened and where it sits.
@(private = "file")
Field_Result :: struct {
	changed, pressed: bool, // the text was edited; the field was pressed
	nav:              [8]ui.Key, // with Field_Opts.menu, this frame's menu keys
	n_nav:            int,
	size:             ui.Size,
	field:            ui.Rect, // the container, in the widget's space
	focused:          bool,
}

// Field_Geom is where a field's parts sit, in the widget's space.
@(private = "file")
Field_Geom :: struct {
	size:                   ui.Size,
	field:                  ui.Rect, // the container
	text_x, text_r:         f32, // the text area, between the icons
	in_x, inner:            f32, // the input itself, after the prefix and before the suffix
	pre, suf:               Text,
	inside, above, has_row: bool, // label inside or above; a supporting row
	input_font, label_font: tok.Type_Style,
	sup_font:               tok.Type_Style,
	lead_size, trail_size:  f32,
}

// field_geom lays out a field of o's parts at the widget's constraints.
@(private = "file")
field_geom :: proc(gtx: ^ui.Ctx, o: Field_Opts) -> (g: Field_Geom) {
	filled := o.kind == .Filled
	g.input_font = filled ? tok.FILLED_TEXT_FIELD_INPUT_FONT : tok.OUTLINED_TEXT_FIELD_INPUT_FONT
	g.label_font = filled ? tok.FILLED_TEXT_FIELD_LABEL_FONT : tok.OUTLINED_TEXT_FIELD_LABEL_FONT
	g.sup_font = filled ? tok.FILLED_TEXT_FIELD_SUPPORTING_FONT : tok.OUTLINED_TEXT_FIELD_SUPPORTING_FONT
	g.lead_size = filled ? tok.FILLED_TEXT_FIELD_LEADING_ICON_SIZE : tok.OUTLINED_TEXT_FIELD_LEADING_ICON_SIZE
	g.trail_size = filled ? tok.FILLED_TEXT_FIELD_TRAILING_ICON_SIZE : tok.OUTLINED_TEXT_FIELD_TRAILING_ICON_SIZE
	small := TYPE_STYLES[.Body_Small]

	g.above = o.label_above && o.label != ""
	g.inside = !o.label_above && o.label != ""
	g.has_row = o.supporting != "" || o.max_length > 0
	above_h: f32 = g.above ? small.line_height + ABOVE_GAP : 0
	row_h: f32 = g.has_row ? SUPPORT_GAP + g.sup_font.line_height : 0
	g.size = ui.constrain(gtx.constraints, {o.width, above_h + FIELD_H + row_h})
	g.field = {0, above_h, g.size.x, FIELD_H}

	// A glyph sits centred in its 48dp slot; the text keeps INSET from the
	// glyph, so 52dp from the edge beside a 24dp icon.
	g.text_x = o.leading != .None ? ICON_SLOT - (ICON_SLOT - g.lead_size) / 2 + INSET : INSET
	g.text_r = o.trailing != .None ? g.size.x - (ICON_SLOT - (ICON_SLOT - g.trail_size) / 2 + INSET) : g.size.x - INSET
	if o.prefix != "" {
		g.pre = shape_style(gtx, o.prefix, g.input_font)
	}
	if o.suffix != "" {
		g.suf = shape_style(gtx, o.suffix, g.input_font)
	}
	g.in_x = g.text_x + (o.prefix != "" ? g.pre.width + AFFIX_PAD : 0)
	in_r := g.text_r - (o.suffix != "" ? g.suf.width + AFFIX_PAD : 0)
	g.inner = max(in_r - g.in_x, 0)
	return
}

// Field_Input is a field's interaction this frame.
@(private = "file")
Field_Input :: struct {
	st:                         ^ui.Widget_State, // nil unless Live
	hovered, focused, disabled: bool,
	scroll:                     f32, // the input's horizontal scroll, keeping the caret in view
}

// field_input reads the field's events (Live) or its forced state, edits s,
// and records into r what happened.
@(private = "file")
field_input :: proc(gtx: ^ui.Ctx, id: ui.Area_Id, s: ^ui.Text_State, o: Field_Opts, g: Field_Geom, r: ^Field_Result) -> (fi: Field_Input) {
	s.cursor = clamp(s.cursor, 0, len(s.buf))
	if o.state != .Live {
		fi.hovered = o.state == .Hovered
		fi.focused = o.state == .Focused || o.state == .Pressed // a field has no pressed look
		fi.disabled = o.state == .Disabled
		return
	}
	st := ui.widget_state(gtx, id)
	fi.st = st
	cs := ui.widget_data(gtx, id, Caret_Scroll)
	for e in ui.events(gtx, id) {
		#partial switch e.kind {
		case .Enter:
			st.hovered = true
		case .Leave:
			st.hovered = false
		case .Focus:
			st.focused = true
		case .Blur:
			st.focused = false
		case .Press:
			r.pressed = true
			s.cursor = ui.text_hit(gtx, s, g.input_font.size, e.pos.x - g.in_x + cs.x)
		case .Text:
			if len(e.text) > 0 && !o.read_only {
				inject_at_elems(&s.buf, s.cursor, ..transmute([]u8)e.text)
				s.cursor += len(e.text)
				r.changed = true
			}
		case .Key:
			if o.menu && (e.key == .Up || e.key == .Down || e.key == .Enter || e.key == .Escape) {
				if r.n_nav < len(r.nav) {
					r.nav[r.n_nav] = e.key
					r.n_nav += 1
				}
				continue
			}
			if o.read_only && (e.key == .Backspace || e.key == .Delete) {
				continue
			}
			r.changed |= ui.text_key(s, e.key)
		}
	}
	fi.hovered, fi.focused = st.hovered, st.focused
	// Horizontal scroll that keeps the caret in view, as ui.text_field.
	str := string(s.buf[:])
	full := shape_style(gtx, str, g.input_font).width
	caret := s.cursor < len(s.buf) ? shape_style(gtx, str[:s.cursor], g.input_font).width : full
	cs.x = min(cs.x, max(full + CARET_W - g.inner, 0))
	cs.x = max(clamp(cs.x, caret + CARET_W - g.inner, caret), 0)
	fi.scroll = cs.x
	return
}

// draw_field is a text field drawn into the widget p: the shared body of
// text_field and autocomplete.
@(private = "file")
draw_field :: proc(gtx: ^ui.Ctx, p: ^ui.Placement, s: ^ui.Text_State, o: Field_Opts) -> (r: Field_Result) {
	g := field_geom(gtx, o)
	r.size, r.field = g.size, g.field
	fi := field_input(gtx, p.id, s, o, g, &r)
	r.focused = fi.focused
	str := string(s.buf[:])
	if o.state == .Live {
		// Registered before the trailing icon's, which sits over it and
		// must win its hits.
		ui.input_area(gtx.ops, p.id, g.field, {.Press, .Release, .Enter, .Leave, .Move, .Key, .Text, .Focus, .Blur})
	}
	filled := o.kind == .Filled
	field := g.field
	small := TYPE_STYLES[.Body_Small] // the floated label (text-field.json behaviour)

	// Springs, on the field's state: 0 label float (0-1), 1 indicator
	// thickness (dp), 2 placeholder alpha (0-1), 3 focus colour (0-1). On a
	// second state beside it: 0 hover colour (0-1), 1 menu arrow turn (0-1).
	c := Control{st = fi.st}
	cx := Control{st = fi.st != nil ? ui.widget_state(gtx, ui.id_mix(p.id, 0x7466)) : nil}
	floated := fi.focused || len(str) > 0
	float_t := animate(gtx, c, 0, floated ? 1 : 0, .Fast_Spatial)
	if !g.inside {
		float_t = 1
	}
	w_rest, w_hover, w_focus, w_disabled := indicator_widths(o.kind)
	w_target := w_rest
	switch {
	case fi.disabled:
		w_target = w_disabled
	case fi.focused:
		w_target = w_focus
	case fi.hovered:
		w_target = w_hover
	}
	thick := max(animate(gtx, c, 1, w_target, .Fast_Spatial, 0.1), 0.5)
	show_ph := o.placeholder != "" && len(str) == 0 && (!g.inside || floated)
	ph_a := animate(gtx, c, 2, show_ph ? 1 : 0, show_ph ? .Fast_Effects : .Slow_Effects)
	focus_f := animate(gtx, c, 3, fi.focused ? 1 : 0, .Fast_Effects)
	hover_f := animate(gtx, cx, 0, fi.hovered ? 1 : 0, .Fast_Effects)
	turn := animate(gtx, cx, 1, o.open ? 1 : 0, .Fast_Spatial)

	col: Field_Colors
	if fi.disabled {
		col = field_disabled_colors(o.kind)
	} else {
		rest := field_colors(o.kind, o.error, .Rest)
		hov := field_colors(o.kind, o.error, .Hover)
		foc := field_colors(o.kind, o.error, .Focus)
		col = lerp_field_colors(lerp_field_colors(rest, hov, hover_f), foc, focus_f)
	}

	// The label: shaped at its current point between rest and float.
	lab: Text
	lab_pos: ui.Point
	if g.inside {
		lab = shape_style(gtx, o.label, lerp_style(g.label_font, small, clamp(float_t, 0, 1)))
		rest_y := field.y + (FIELD_H - g.label_font.line_height) / 2
		// Filled floats to the top of the row the label and input share;
		// outlined floats onto the outline, centred on it.
		float_y := filled ? field.y + (FIELD_H - small.line_height - g.input_font.line_height) / 2 : field.y - small.line_height / 2
		float_x := filled ? g.text_x : INSET
		lab_pos = {g.text_x + (float_x - g.text_x) * float_t, rest_y + (float_y - rest_y) * float_t}
	}

	// Container, then indicator or outline.
	switch o.kind {
	case .Filled:
		ui.fill(gtx.ops, rounded(gtx, field, corners(tok.FILLED_TEXT_FIELD_CONTAINER_SHAPE, field)), col.container)
		ui.fill(gtx.ops, ui.Rect{field.x, field.y + field.h - thick, field.w, thick}, col.indicator)
	case .Outlined:
		gap0, gap1: f32
		if g.inside && float_t > 0 {
			// The cut grows with the float, around the label as drawn now.
			gap0 = lab_pos.x - NOTCH_PAD
			gap1 = gap0 + (lab.width + 2 * NOTCH_PAD) * clamp(float_t, 0, 1)
		}
		stroke_outline_with_gap(gtx, field, corners(tok.OUTLINED_TEXT_FIELD_CONTAINER_SHAPE, field).tl, gap0, gap1, col.indicator, thick)
	}
	if g.inside {
		draw_text(gtx, lab, lab_pos, col.label)
	} else if g.above {
		draw_style_text(gtx, o.label, {0, 0}, small, col.label)
	}

	// Input row: prefix, text (or placeholder), suffix, caret.
	input_y := field.y + (FIELD_H - g.input_font.line_height) / 2
	if filled && g.inside {
		input_y = field.y + (FIELD_H - small.line_height - g.input_font.line_height) / 2 + small.line_height
	}
	// Prefix and suffix show once the label is out of the way.
	affix_a := g.inside ? clamp(float_t, 0, 1) : 1
	if o.prefix != "" {
		draw_text(gtx, g.pre, {g.text_x, input_y}, fade(col.prefix, affix_a))
	}
	if o.suffix != "" {
		draw_text(gtx, g.suf, {g.text_r - g.suf.width, input_y}, fade(col.suffix, affix_a))
	}
	ui.push_clip(gtx.ops, ui.Rect{g.in_x, field.y, g.inner, field.h})
	if len(str) > 0 {
		draw_text(gtx, shape_style(gtx, str, g.input_font), {g.in_x - fi.scroll, input_y}, col.input)
	}
	if ph_a > 0 && o.placeholder != "" {
		draw_text(gtx, shape_style(gtx, o.placeholder, g.input_font), {g.in_x, input_y}, fade(col.placeholder, ph_a))
	}
	if fi.focused && !fi.disabled && !o.read_only {
		cw := shape_style(gtx, str[:s.cursor], g.input_font).width
		ui.fill(gtx.ops, ui.Rect{g.in_x + cw - fi.scroll, input_y + 2, CARET_W, g.input_font.line_height - 4}, col.caret)
	}
	ui.pop_clip(gtx.ops)

	if o.leading != .None {
		icon(gtx, o.leading, {(ICON_SLOT - g.lead_size) / 2, field.y + (FIELD_H - g.lead_size) / 2}, g.lead_size, col.leading)
	}
	if o.trailing != .None {
		draw_field_trailing(gtx, p.id, o, g, col.trailing, fi.disabled, turn)
	}
	if g.has_row {
		draw_field_row(gtx, o, g, str, col.supporting, fi.disabled)
	}
	name := o.label != "" ? o.label : (o.placeholder != "" ? o.placeholder : "text field")
	ui.tag(gtx.ops, p.id, ui.frame_string(gtx, name))
	return
}

// draw_field_trailing draws the trailing icon centred in its slot, turned by
// turn half-circles, and, with o.trailing_action set, makes it a button.
@(private = "file")
draw_field_trailing :: proc(gtx: ^ui.Ctx, id: ui.Area_Id, o: Field_Opts, g: Field_Geom, col: ui.Color, disabled: bool, turn: f32) {
	slot := ui.Rect{g.size.x - ICON_SLOT, g.field.y + (FIELD_H - ICON_SLOT) / 2, ICON_SLOT, ICON_SLOT}
	ctr := ui.Point{slot.x + ICON_SLOT / 2, slot.y + ICON_SLOT / 2}
	if o.trailing_action != nil {
		// An actionable trailing icon is an icon button: its own 48dp
		// target, a 40dp state layer, and a name (text-field.json
		// accessibility).
		rid := ui.id_mix(id, 0x7472)
		tc := control(gtx, rid, slot, disabled ? .Disabled : (o.state == .Live ? .Live : .Enabled))
		if tc.clicked {
			o.trailing_action^ = true
		}
		paint_state_layer(gtx, tc, ui.circle(ctr, 20), col)
		listen(gtx, tc, rid, slot)
		ui.tag(gtx.ops, rid, fmt.aprintf("%s trailing", o.label, allocator = gtx.allocator))
	}
	// The autocomplete arrow turns half a circle as the menu opens.
	if turn != 0 {
		ui.push_transform(gtx.ops, ui.mul(ui.mul(ui.translate(-ctr.x, -ctr.y), ui.rotate(turn * math.PI)), ui.translate(ctr.x, ctr.y)))
	}
	icon(gtx, o.trailing, {ctr.x - g.trail_size / 2, ctr.y - g.trail_size / 2}, g.trail_size, col)
	if turn != 0 {
		ui.pop_transform(gtx.ops)
	}
}

// draw_field_row draws the supporting row: helper or error text at the start,
// the counter at the end.
@(private = "file")
draw_field_row :: proc(gtx: ^ui.Ctx, o: Field_Opts, g: Field_Geom, str: string, col: ui.Color, disabled: bool) {
	y := g.field.y + g.field.h + SUPPORT_GAP
	if o.supporting != "" {
		draw_style_text(gtx, o.supporting, {INSET, y}, g.sup_font, col)
	}
	if o.max_length > 0 {
		n := utf8.rune_count_in_string(str)
		t := shape_style(gtx, fmt.aprintf("%d/%d", n, o.max_length, allocator = gtx.allocator), g.sup_font)
		cc := col
		if n > o.max_length && !disabled {
			// Past the limit the counter is an error, whatever the field's
			// own error (text-field.json notes).
			cc = color(o.kind == .Filled ? tok.FILLED_TEXT_FIELD_ERROR_SUPPORTING_COLOR : tok.OUTLINED_TEXT_FIELD_ERROR_SUPPORTING_COLOR)
		}
		draw_text(gtx, t, {g.size.x - INSET - t.width, y}, cc)
	}
}

// text_field edits s, a single line. Returns true when the text changed.
//
//	kind            filled (tinted, bottom indicator) or outlined (border)
//	label           rests inside and floats on focus or content; with
//	                label_above it sits fixed above the container instead
//	leading, trailing  24dp icons; with trailing_action non-nil the
//	                trailing icon is a button that sets it true
//	prefix, suffix  inline text before and after the input, shown once
//	                the label has floated
//	supporting      helper text below; error text when error is set
//	max_length      when > 0, an "n/max" counter at the row's end, in the
//	                error colour past the limit (it does not stop input)
//	read_only       focusable and navigable, not editable
//
// state forces a look: Focused shows the caret and floated label, Hovered
// the hover colours; Pressed paints as Focused (a field has no pressed
// look). Motion: the label float and indicator/outline thickness follow
// fast-spatial, colours fast-effects, the placeholder fades in on
// fast-effects and out on slow-effects (text-field.json behaviour).
text_field :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	label: string,
	kind := Text_Field_Kind.Filled,
	leading := Icon.None,
	trailing := Icon.None,
	supporting := "",
	placeholder := "",
	error := false,
	width: f32 = 280,
	prefix := "",
	suffix := "",
	max_length := 0,
	label_above := false,
	read_only := false,
	trailing_action: ^bool = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_begin(gtx, key, loc)
	r := draw_field(
		gtx,
		&p,
		s,
		{
			label = label,
			supporting = supporting,
			placeholder = placeholder,
			prefix = prefix,
			suffix = suffix,
			kind = kind,
			leading = leading,
			trailing = trailing,
			error = error,
			label_above = label_above,
			read_only = read_only,
			max_length = max_length,
			width = width,
			state = state,
			trailing_action = trailing_action,
		},
	)
	ui.widget_end(gtx, &p, {size = r.size})
	return r.changed
}

// MENU_ITEM_H is the autocomplete menu's item height (menu.json layout,
// Menu.kt:2374).
@(private = "file")
MENU_ITEM_H :: f32(48)

// MENU_PAD is the menu list's vertical padding (menu.json layout, Menu.kt:2386).
@(private = "file")
MENU_PAD :: f32(8)

// MENU_ITEM_INSET is an item's horizontal padding (menu.json layout, Menu.kt:2390).
@(private = "file")
MENU_ITEM_INSET :: f32(12)

// Autocomplete_Highlight is the autocomplete menu's keyboard highlight,
// kept in the field's widget_data: the row, 1-based so the zero value an
// unseen field starts with is no highlight.
@(private)
Autocomplete_Highlight :: struct {
	row: int,
}

// autocomplete is a text field composed with a menu of options
// (text-field.json's filled-autocomplete and outlined-autocomplete). A
// press on the field, typing, or Down opens the menu under it, as wide as
// the field, listing the options that contain the text (all of them when
// the text is empty or already one of them); Up and Down move a
// highlight, Enter or a click takes an option into the field and closes
// the menu, Escape or a press anywhere else closes it. expanded is the
// caller's open state. Returns the chosen option's index, or -1.
//
// The trailing arrow turns 180 degrees open on fast-spatial: text-field.json
// behaviour records animating it as the kit's deliberate deviation from
// Compose's plain rotate (ExposedDropdownMenu.kt:462-463). The menu does
// not keep the spec's 48dp from the window's edges (menu.json layout,
// Menu.kt:2324-2325): an overlay here does not know the window.
autocomplete :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	label: string,
	options: []string,
	expanded: ^bool,
	kind := Text_Field_Kind.Filled,
	leading := Icon.None,
	supporting := "",
	placeholder := "",
	error := false,
	width: f32 = 280,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> int {
	chosen := -1
	stk := ui.stack(gtx, key, loc)
	defer ui.end(&stk)
	p := ui.widget_begin(gtx, key ~ 0x6175746f636f6d70, loc)
	r := draw_field(
		gtx,
		&p,
		s,
		{
			label = label,
			supporting = supporting,
			placeholder = placeholder,
			kind = kind,
			leading = leading,
			trailing = .Arrow_Drop_Down,
			error = error,
			width = width,
			state = state,
			menu = true,
			open = expanded^,
		},
	)
	ui.widget_end(gtx, &p, {size = r.size})
	if state != .Live {
		return chosen
	}

	// Which options match, into frame memory.
	str := ui.text_string(s)
	exact := false
	for o in options {
		if strings.equal_fold(o, str) {
			exact = true
		}
	}
	matches := make([dynamic]int, 0, len(options), gtx.allocator)
	needle := strings.to_lower(str, gtx.allocator)
	for o, i in options {
		if str == "" || exact || strings.contains(strings.to_lower(o, gtx.allocator), needle) {
			append(&matches, i)
		}
	}

	// The keyboard highlight: an index into matches, -1 for none.
	hs := ui.widget_data(gtx, p.id, Autocomplete_Highlight)
	hl := hs.row - 1
	if r.pressed || r.changed {
		expanded^ = true
		hl = -1
	}
	pick := -1
	for k in r.nav[:r.n_nav] {
		#partial switch k {
		case .Down:
			if !expanded^ {
				expanded^ = true
				hl = -1
			}
			hl = min(hl + 1, len(matches) - 1)
		case .Up:
			hl = max(hl - 1, 0)
		case .Enter:
			if expanded^ && hl >= 0 && hl < len(matches) {
				pick = matches[hl]
			}
		case .Escape:
			expanded^ = false
		}
	}
	if !r.focused && !r.pressed {
		hl = -1
	}

	if expanded^ && len(matches) > 0 {
		menu_id := ui.id_mix(p.id, 0x6d656e75)
		o := ui.overlay(gtx, {0, r.field.y + r.field.h})
		defer ui.end(&o)
		defer o.discard = !expanded^ // closed this frame: draw nothing, catch nothing
		// Scrim: a press outside the menu closes it and reaches nothing else.
		scrim_id := ui.id_mix(menu_id, 0xffff)
		for e in ui.events(gtx, scrim_id) {
			if e.kind == .Press {
				expanded^ = false
			}
		}
		ui.input_area(gtx.ops, scrim_id, ui.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		filled := kind == .Filled
		w := r.field.w // the menu matches the field's width (ExposedDropdownMenu.kt:204-213)
		h := 2 * MENU_PAD + MENU_ITEM_H * f32(len(matches))
		box := ui.Rect{0, 0, w, h}
		shape := corners(filled ? tok.FILLED_AUTOCOMPLETE_MENU_CONTAINER_SHAPE : tok.OUTLINED_AUTOCOMPLETE_MENU_CONTAINER_SHAPE, box)
		rr := ui.Round_Rect{box, shape.tl}
		paint_elevation(gtx, rr, elevation_level(filled ? tok.FILLED_AUTOCOMPLETE_MENU_CONTAINER_ELEVATION : tok.OUTLINED_AUTOCOMPLETE_MENU_CONTAINER_ELEVATION))
		ui.fill(gtx.ops, rr, color(filled ? tok.FILLED_AUTOCOMPLETE_MENU_CONTAINER_COLOR : tok.OUTLINED_AUTOCOMPLETE_MENU_CONTAINER_COLOR))
		ui.input_area(gtx.ops, ui.id_mix(menu_id, 0xfffe), rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
		for oi, row in matches {
			item := ui.Rect{0, MENU_PAD + MENU_ITEM_H * f32(row), w, MENU_ITEM_H}
			id := ui.id_mix(menu_id, u64(oi) + 1)
			c := control(gtx, id, item, .Live)
			if c.clicked {
				pick = oi
			}
			label_col := color(.On_Surface)
			if strings.equal_fold(options[oi], str) {
				ui.fill(gtx.ops, item, color(tok.MENU_LIST_ITEM_SELECTED_CONTAINER_COLOR))
				label_col = color(tok.MENU_LIST_ITEM_SELECTED_LABEL_TEXT_COLOR)
			}
			if row == hl && c.layer == 0 {
				c.layer = FOCUS_OPACITY // the keyboard highlight reads as focus
			}
			paint_state_layer(gtx, c, item, label_col)
			t := shape_text(gtx, options[oi], .Body_Large)
			draw_text(gtx, t, {MENU_ITEM_INSET, item.y + (MENU_ITEM_H - t.height) / 2}, label_col)
			// No key kinds, so a press here leaves focus on the field
			// (text-field.json behaviour: picking returns focus to it).
			listen(gtx, c, id, item, {.Press, .Release, .Enter, .Leave, .Move})
			ui.tag(gtx.ops, id, ui.frame_string(gtx, options[oi]))
		}
	}
	if pick >= 0 {
		ui.text_set(s, options[pick])
		expanded^ = false
		chosen = pick
		hl = -1
	}
	hs.row = hl + 1
	return chosen
}

// stroke_outline_with_gap strokes r's rounded outline at width w, leaving the top
// edge open between x = gap0 and gap1 (none when they are equal) — the
// outlined text field's notch behind its floated label.
@(private)
stroke_outline_with_gap :: proc(gtx: ^ui.Ctx, r: ui.Rect, radius, gap0, gap1: f32, color: ui.Color, w: f32) {
	h := w / 2
	x0, y0, x1, y1 := r.x + h, r.y + h, r.x + r.w - h, r.y + r.h - h
	rad := max(radius - h, 0)
	k := rad * KAPPA
	verbs := make([dynamic]ui.Path_Verb, gtx.allocator)
	pts := make([dynamic]ui.Point, gtx.allocator)
	open := gap1 > gap0
	start := open ? gap1 : x0 + rad
	append(&verbs, ui.Path_Verb.Move)
	append(&pts, ui.Point{start, y0})
	append(&verbs, ui.Path_Verb.Line, ui.Path_Verb.Cubic)
	append(&pts, ui.Point{x1 - rad, y0}, ui.Point{x1 - rad + k, y0}, ui.Point{x1, y0 + rad - k}, ui.Point{x1, y0 + rad})
	append(&verbs, ui.Path_Verb.Line, ui.Path_Verb.Cubic)
	append(&pts, ui.Point{x1, y1 - rad}, ui.Point{x1, y1 - rad + k}, ui.Point{x1 - rad + k, y1}, ui.Point{x1 - rad, y1})
	append(&verbs, ui.Path_Verb.Line, ui.Path_Verb.Cubic)
	append(&pts, ui.Point{x0 + rad, y1}, ui.Point{x0 + rad - k, y1}, ui.Point{x0, y1 - rad + k}, ui.Point{x0, y1 - rad})
	append(&verbs, ui.Path_Verb.Line, ui.Path_Verb.Cubic)
	append(&pts, ui.Point{x0, y0 + rad}, ui.Point{x0, y0 + rad - k}, ui.Point{x0 + rad - k, y0}, ui.Point{x0 + rad, y0})
	if open {
		append(&verbs, ui.Path_Verb.Line)
		append(&pts, ui.Point{gap0, y0})
	} else {
		append(&verbs, ui.Path_Verb.Close)
	}
	path := ui.Path_Ref{ui.add_path(gtx.ops, {verbs[:], pts[:]})}
	ui.stroke(gtx.ops, path, color, {width = w})
}
