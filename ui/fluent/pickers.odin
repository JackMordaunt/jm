package fluent

import "core:fmt"
import "core:math"
import "core:strconv"
import "core:strings"
import "jm:ui"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// The pickers: combobox and dropdown, select, spin button, search box,
// tag picker, swatch picker, colour picker and rating, on the
// fluent-kit's components/combobox.json, select.json, spin-button.json,
// search-box.json, tag-picker.json, swatch-picker.json,
// color-picker.json and rating.json and the styles files they cite
// under source/components at the kit's commit (source/COMMIT).
//
// The first five share Fluent's input field: a box in Input's four
// appearances whose bottom edge is its own token, a focus line that
// grows from the centre, and content slots at either end. inputs.odin's
// input keeps that look to itself, so this file has its own Field:
// the same numbers from the same styles files, read here for fields
// that hold buttons, tags and a listbox as well as text. The listbox
// the combobox, dropdown, select and tag picker open is one private
// popover on ui's overlay, the way overlays.odin's menu is built.

// FIELD_MIN_WIDTH is a combobox's and tag picker's minimum width
// (useComboboxStyles.styles.ts:17-38, useTagPickerControlStyles.
// styles.ts:24-35); select and the spin button take their constraints.
@(private = "file")
FIELD_MIN_WIDTH :: f32(250)

// FIELD_DEFAULT_WIDTH is a field's width where its constraints leave it
// free and no width is given.
@(private = "file")
FIELD_DEFAULT_WIDTH :: f32(250)

// Field_Metrics are one size's numbers shared by the combobox, dropdown
// and select (useComboboxStyles.styles.ts:103-116,192-204,215-282;
// useDropdownStyles.styles.ts:100-143; useSelectStyles.styles.ts:27-55,
// 207-245): the height, the start padding (the outer inset plus the
// inner content padding), the end padding, the icon size, the
// icon-to-text gap and the text style.
@(private = "file")
Field_Metrics :: struct {
	h, pad_start, pad_end, icon, gap: f32,
	style:                            tok.Type_Style,
}

@(private = "file")
field_metrics :: proc(size: Size) -> Field_Metrics {
	switch size {
	case .Small:
		return {24, tok.SPACING_HORIZONTAL_SNUDGE + tok.SPACING_HORIZONTAL_XXS, tok.SPACING_HORIZONTAL_SNUDGE, 16, tok.SPACING_HORIZONTAL_XXS, style(.Caption1)}
	case .Medium:
	case .Large:
		return {40, tok.SPACING_HORIZONTAL_M + tok.SPACING_HORIZONTAL_SNUDGE, tok.SPACING_HORIZONTAL_M, 24, tok.SPACING_HORIZONTAL_SNUDGE, style(.Body2)}
	}
	return {32, tok.SPACING_HORIZONTAL_MNUDGE + tok.SPACING_HORIZONTAL_XXS, tok.SPACING_HORIZONTAL_MNUDGE, 20, tok.SPACING_HORIZONTAL_XXS, style(.Body1)}
}

// Field_Stepping is which appearances react to hover, press and focus
// on their border: the combobox family steps outline only (combobox.
// json notes), the spin button every appearance (spin-button.json
// states), select's outline steps its sides but never its bottom edge.
@(private = "file")
Field_Stepping :: enum u8 {
	Outline_Only,
	All,
	Sides_Only,
}

// Field_Colors are a field's resolved colours for one frame.
@(private = "file")
Field_Colors :: struct {
	bg, border, bottom, text, placeholder, icon, line: ops.Color,
}

// field_colors is appearance a's colours for c (useComboboxStyles.
// styles.ts:117-190, useSpinButtonStyles.styles.ts:39-62,122-176,
// useSelectStyles.styles.ts:110-163): nothing transitions. The icon is
// Neutral_Stroke_Accessible, the placeholder Neutral_Foreground4;
// invalid turns the border Palette_Red_Border2 while focus is not
// within; disabled drops the fill and takes the Disabled tokens.
@(private = "file")
field_colors :: proc(a: Input_Appearance, c: Control, invalid: bool, stepping: Field_Stepping) -> (k: Field_Colors) {
	filled := a >= .Filled_Darker
	darker := a == .Filled_Darker || a == .Filled_Darker_Shadow
	k.text, k.placeholder, k.icon = color(.Neutral_Foreground1), color(.Neutral_Foreground4), color(.Neutral_Stroke_Accessible)
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
		k.text, k.placeholder, k.icon = color(.Neutral_Foreground_Disabled), color(.Neutral_Foreground_Disabled), color(.Neutral_Foreground_Disabled)
		k.line = {}
		if a == .Underline {
			k.border = {}
		}
		return
	}
	active := c.focused || c.pressed
	steps := stepping == .All || a == .Outline
	switch {
	case filled:
		k.border = color(steps && (active || c.hovered) ? .Transparent_Stroke_Interactive : .Transparent_Stroke)
		k.bottom = k.border
	case steps && active:
		k.border, k.bottom = color(.Neutral_Stroke1_Pressed), color(.Neutral_Stroke_Accessible_Pressed)
	case steps && c.hovered:
		k.border, k.bottom = color(.Neutral_Stroke1_Hover), color(.Neutral_Stroke_Accessible_Hover)
	case:
		k.border, k.bottom = color(.Neutral_Stroke1), color(.Neutral_Stroke_Accessible)
	}
	if stepping == .Sides_Only && !filled {
		k.bottom = color(.Neutral_Stroke_Accessible) // select.json notes: the bottom never steps
	}
	if invalid && !active {
		k.border, k.bottom = color(.Palette_Red_Border2), color(.Palette_Red_Border2)
	}
	if a == .Underline {
		k.border = {}
	}
	return
}

// paint_field paints a field's box: the fill, the border, and the
// bottom edge over the border's bottom run (combobox.json variants;
// the underline appearance has no radius and only the bottom edge).
@(private = "file")
paint_field :: proc(gtx: ^ui.Ctx, area: ops.Rect, a: Input_Appearance, k: Field_Colors) -> (rad: f32) {
	rad = a == .Underline ? 0 : tok.BORDER_RADIUS_MEDIUM
	if ui.painted(k.bg) {
		ops.fill(gtx.scene, ops.Round_Rect{area, rad}, k.bg)
	}
	if ui.painted(k.border) {
		stroke_inside(gtx, {area, rad}, k.border, tok.STROKE_WIDTH_THIN)
	}
	if ui.painted(k.bottom) {
		ops.fill(gtx.scene, ops.Rect{area.x + rad, area.y + area.h - tok.STROKE_WIDTH_THIN, area.w - 2 * rad, tok.STROKE_WIDTH_THIN}, k.bottom)
	}
	return
}

// Focus_Growth is a field's focus line between frames: a scale easing
// toward 1 as focus enters over DURATION_NORMAL with CURVE_DECELERATE_
// MID and back to 0 over DURATION_ULTRA_FAST with CURVE_ACCELERATE_MID
// (combobox.json states.focused; the styles files write the curves to
// transitionDelay, which the spec's gotcha note says to read as the
// easing).
@(private = "file")
Focus_Growth :: struct {
	from, to: f32,
	tween:    ui.Tween,
	curve:    tok.Bezier,
	live:     bool,
}

// focus_growth is the line's scale this frame for c under the widget
// id: the target at once for a forced or disabled control, eased for a
// live one.
@(private = "file")
focus_growth :: proc(gtx: ^ui.Ctx, c: Control, id: ops.Area_Id, within := false) -> f32 {
	if c.disabled {
		return 0
	}
	target: f32 = c.focused || within ? 1 : 0
	if c.st == nil {
		return target
	}
	g := ui.widget_data(gtx, ui.id_mix(id, 0xf0c5), Focus_Growth)
	if !g.live {
		g^ = {from = target, to = target, live = true}
		return target
	}
	if target != g.to {
		g.from = growth_value(g)
		g.to = target
		entering := target == 1
		g.tween = {to = 1, duration = (entering ? tok.DURATION_NORMAL : tok.DURATION_ULTRA_FAST) / 1000}
		g.curve = entering ? tok.CURVE_DECELERATE_MID : tok.CURVE_ACCELERATE_MID
	}
	ui.tween_update(&g.tween, gtx)
	return growth_value(g)
}

@(private = "file")
growth_value :: proc(g: ^Focus_Growth) -> f32 {
	if g.tween.duration <= 0 {
		return g.to
	}
	return g.from + (g.to - g.from) * bezier_ease(g.curve, g.tween.t / g.tween.duration)
}

// paint_growth paints the focus line under area at scale t: 2px thick
// (strokeWidthThick), grown from the centre, 1px outside the box's
// left, right and bottom edges with the box's bottom radius
// (useComboboxStyles.styles.ts:47-59), or, with inside, along the box's
// own bottom edge as select draws it (useSelectStyles.styles.ts:68-84).
@(private = "file")
paint_growth :: proc(gtx: ^ui.Ctx, area: ops.Rect, rad, t: f32, col: ops.Color, inside := false) {
	if t <= 0 || !ui.painted(col) {
		return
	}
	outset: f32 = inside ? 0 : 1
	full := area.w + 2 * outset
	w := full * clamp(t, 0, 1)
	bottom := area.y + area.h + outset
	thick := tok.STROKE_WIDTH_THICK
	ops.clip_push(gtx.scene, ops.Rect{area.x - outset + (full - w) / 2, bottom - thick, w, thick})
	h := max(rad, thick)
	ops.fill(gtx.scene, rounded(gtx, {area.x - outset, bottom - h, full, h}, {0, 0, rad, rad}), col)
	ops.clip_pop(gtx.scene)
}

// Listbox: the popover the combobox family opens.

// LISTBOX_* are the listbox's and option's metrics (combobox.json
// layout: useListboxStyles.styles.ts:15-27, useOptionStyles.styles.ts:
// 18-30,74-106).
@(private = "file")
LISTBOX_MIN_WIDTH :: f32(160)
@(private = "file")
LISTBOX_PAD :: tok.SPACING_HORIZONTAL_XS
@(private = "file")
LISTBOX_GAP :: tok.SPACING_HORIZONTAL_XXS
@(private = "file")
OPTION_PAD_V :: tok.SPACING_VERTICAL_SNUDGE
@(private = "file")
OPTION_PAD_H :: tok.SPACING_HORIZONTAL_S
@(private = "file")
OPTION_GAP :: tok.SPACING_HORIZONTAL_XS
@(private = "file")
OPTION_CHECK :: tok.FONT_SIZE_BASE400
// LISTBOX_MAX_ROWS stands in for the listbox's 80% of the viewport: an
// immediate-mode overlay has no viewport height to read.
@(private = "file")
LISTBOX_MAX_ROWS :: 8

// Listbox_Data is what a listbox keeps between frames: whether it was
// open, and the keyboard-active option.
@(private = "file")
Listbox_Data :: struct {
	was_open: bool,
	active:   int,
	by_keys:  bool, // the active option was reached by keyboard, so it draws its ring
	scroll:   int, // the first row shown
}

// Listbox_Pick is what one frame of an open listbox did.
@(private = "file")
Listbox_Pick :: struct {
	picked: int, // -1 unless an option was chosen
	closed: bool,
}

// listbox paints the options below the field of width w and height h
// while open^, and reads the clicks on them: Neutral_Background1 with
// shadow16, borderRadiusMedium and 4px padding around rows 2px apart,
// each a body1 row with the check column, hovering Background1_Hover,
// selected showing Icon.Checkmark. A press outside closes it. Rows
// beyond LISTBOX_MAX_ROWS scroll by the wheel or with the active row.
@(private = "file")
listbox :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, open: ^bool, options: []string, selected: int, w, h: f32, check := true, chosen: []bool = nil) -> (r: Listbox_Pick) {
	r.picked = -1
	d := ui.widget_data(gtx, ui.id_mix(id, 0x11b0), Listbox_Data)
	if !open^ {
		d.was_open = false
		return
	}
	scrim_id := ui.id_mix(id, 0xffff)
	for e in ui.events(gtx, scrim_id) {
		if e.kind == .Press {
			open^ = false
			r.closed = true
		}
	}
	if !open^ {
		d.was_open = false
		return
	}
	if !d.was_open {
		d.was_open = true
		d.active = selected
		d.by_keys = false
		d.scroll = 0
	}
	n := len(options)
	rows := min(n, LISTBOX_MAX_ROWS)
	if d.active >= 0 && d.active < n {
		d.scroll = clamp(d.scroll, d.active - rows + 1, d.active)
	}
	d.scroll = clamp(d.scroll, 0, max(n - rows, 0))
	row_h := 2 * OPTION_PAD_V + tok.LINE_HEIGHT_BASE300
	pw := max(w, LISTBOX_MIN_WIDTH)
	ph := 2 * (LISTBOX_PAD + tok.STROKE_WIDTH_THIN) + f32(rows) * row_h + f32(max(rows - 1, 0)) * LISTBOX_GAP
	// Below the trigger, flipped above it or shifted along it to stay in
	// the window (ui.popup_open).
	ov := ui.popup_open(gtx, {0, 0, w, h}, id, .Below, .Start, tok.SPACING_VERTICAL_XXS)
	defer ui.popup_close(&ov, {pw, ph})
	ops.input_area(gtx.scene, scrim_id, ops.Rect{-1e5, -1e5, 2e5, 2e5}, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	box_id := ui.id_mix(id, 0xfffe)
	for e in ui.events(gtx, box_id) {
		if e.kind == .Scroll {
			d.scroll = clamp(d.scroll + (e.scroll.y > 0 ? 1 : -1), 0, max(n - rows, 0))
		}
	}
	area := ops.Rect{0, 0, pw, ph}
	rr := ops.Round_Rect{area, tok.BORDER_RADIUS_MEDIUM}
	paint_shadow(gtx, rr, tok.SHADOW16)
	ops.fill(gtx.scene, rr, color(.Neutral_Background1))
	stroke_inside(gtx, rr, color(.Transparent_Stroke), tok.STROKE_WIDTH_THIN)
	ops.input_area(gtx.scene, box_id, rr, {.Press, .Release, .Move, .Enter, .Leave, .Scroll})
	y := LISTBOX_PAD + tok.STROKE_WIDTH_THIN
	for i in d.scroll ..< min(d.scroll + rows, n) {
		row := ops.Rect{LISTBOX_PAD + tok.STROKE_WIDTH_THIN, y, pw - 2 * (LISTBOX_PAD + tok.STROKE_WIDTH_THIN), row_h}
		is_sel := chosen != nil ? chosen[i] : i == selected
		if option(gtx, ui.id_mix(id, u64(0x0900 + i)), row, options[i], is_sel, check, i == d.active && d.by_keys) {
			r.picked = i
		}
		y += row_h + LISTBOX_GAP
	}
	return
}

// step_listbox moves the active option by the keys the trigger took
// (combobox.json behaviour active-descendant): Down and Up step, Home
// and End jump, Page keys move a page; Enter picks the active one.
// Returns the pick, -1 for none, and whether a key was taken.
@(private = "file")
step_listbox :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, k: ui.Key, n: int) -> (picked: int, taken: bool) {
	d := ui.widget_data(gtx, ui.id_mix(id, 0x11b0), Listbox_Data)
	picked = -1
	if n == 0 {
		return
	}
	#partial switch k {
	case .Down:
		d.active = (d.active + 1) %% n
	case .Up:
		d.active = (d.active - 1 + n) %% n
	case .Home:
		d.active = 0
	case .End:
		d.active = n - 1
	case .Page_Down:
		d.active = min(d.active + LISTBOX_MAX_ROWS, n - 1)
	case .Page_Up:
		d.active = max(d.active - LISTBOX_MAX_ROWS, 0)
	case .Enter:
		if d.active >= 0 && d.active < n {
			picked = d.active
		}
		return picked, true
	case:
		return
	}
	d.by_keys = true
	return picked, true
}

// option is one listbox row (combobox.json layout option-box, states):
// the check column, then the label; hover and press read Neutral_
// Background1's and Foreground1's twins, a selected row shows the check,
// and the keyboard-active row draws a 2px Stroke_Focus2 ring 2px
// outside itself. Returns true on a click.
@(private = "file")
option :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, row: ops.Rect, label: string, selected, check, active: bool) -> bool {
	c := control(gtx, id, row, .Live)
	bg := color_for({.Neutral_Background1, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Neutral_Background1}, c)
	fg := color_for({.Neutral_Foreground1, .Neutral_Foreground1_Hover, .Neutral_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	ops.fill(gtx.scene, ops.Round_Rect{row, tok.BORDER_RADIUS_MEDIUM}, bg)
	x := row.x + OPTION_PAD_H
	if check {
		if selected {
			icon(gtx, .Checkmark, {x - tok.SPACING_HORIZONTAL_XXS, row.y + (row.h - OPTION_CHECK) / 2}, OPTION_CHECK, fg)
		}
		x += OPTION_CHECK + OPTION_GAP
	}
	t := shape_style(gtx, label, style(.Body1))
	draw_text(gtx, t, {x, row.y + OPTION_PAD_V}, fg)
	if active {
		ring := ops.Rect{row.x - 2, row.y - 2, row.w + 4, row.h + 4}
		ops.stroke(gtx.scene, ops.Round_Rect{{ring.x - 1, ring.y - 1, ring.w + 2, ring.h + 2}, tok.BORDER_RADIUS_MEDIUM + 3}, color(.Stroke_Focus2), {width = tok.STROKE_WIDTH_THICK})
	}
	listen(gtx, c.st, id, row)
	ops.tag(gtx.scene, id, ui.frame_string(gtx, label))
	return c.clicked
}

// Combobox.

// Combobox_Kind is the trigger: a text input the user types into, or a
// button that only picks from the list (combobox.json variants kind).
Combobox_Kind :: enum u8 {
	Combobox,
	Dropdown,
}

// Picker_Result is what one frame of a picker did.
Picker_Result :: struct {
	changed: bool, // the selection is not what it was
	edited:  bool, // the typed text changed (combobox)
	opened:  bool, // the list is open after this frame
}

// Combobox_Data is what a combobox keeps between frames when the caller
// gives it no open flag, plus what the text held when it last matched
// the selection, to revert a non-freeform combobox on blur.
@(private = "file")
Combobox_Data :: struct {
	open:        bool,
	was_focused: bool,
}

// FIELD_KINDS is what a typed field's area asks for: a click's kinds
// plus typed text and the wheel.
@(private = "file")
FIELD_KINDS :: EDIT_KINDS

// combobox is a Fluent combobox or dropdown (combobox.json): a field
// that opens a listbox of options, selected^ being the chosen one, -1
// for none. As a Combobox s is the text typed, which opens the list and
// filters options to those containing it (the spec leaves filtering to
// the caller; this is the plainest reading); as a Dropdown s may be nil
// and the field shows the selection or the placeholder. open is the
// caller's flag, or nil for the widget's own. Clicking the field or its
// chevron, ArrowDown or ArrowUp, and typing open it; a click on an
// option or Enter on the active one picks and closes; Escape, Tab and a
// press outside close. On blur a non-freeform combobox reverts typed
// text that matches no option. With clearable and a selection, the
// chevron gives way to a dismiss control that clears it.
//
// Departures: multiselect and option groups are not built; the listbox
// shows at most LISTBOX_MAX_ROWS rows, scrolling by the wheel and the
// active row, in place of 80% of a viewport it cannot see; the active
// option's ring shows only after keyboard travel, as specified.
combobox :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	options: []string,
	selected: ^int,
	placeholder := "",
	kind := Combobox_Kind.Combobox,
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	open: ^bool = nil,
	freeform := false,
	clearable := false,
	invalid := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Picker_Result) {
	p := ui.widget_open(gtx, key, loc)
	m := field_metrics(size)
	d := ui.widget_data(gtx, p.id, Combobox_Data)
	flag := open != nil ? open : &d.open
	typed := kind == .Combobox && s != nil
	cs := gtx.constraints
	w := width
	if w <= 0 {
		w = ui.is_finite(cs.max.x) ? cs.max.x : FIELD_DEFAULT_WIDTH
	}
	w = max(w, FIELD_MIN_WIDTH)
	sz := ui.constrain(cs, {w, m.h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	if c.disabled {
		flag^ = false
	}
	old := selected^

	// The visible options: all, or those containing the typed text
	// while it differs from the selection's own text; filtered again
	// after this frame's typing, so the list follows it at once.
	shown, map_back, shown_sel := filter_options(gtx, options, typed ? string(s.buf[:]) : "", selected^)
	pick_shown :: proc(i: int, map_back: []int) -> int {
		return map_back != nil ? map_back[i] : i
	}

	if c.st != nil {
		if typed {
			s.cursor = clamp(s.cursor, 0, len(s.buf))
		}
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left && !c.disabled {
					if typed {
						s.cursor = ui.paragraph_hit(layout_style(gtx, string(s.buf[:]), m.style), {e.pos.x - m.pad_start, 0})
					}
					if !typed || e.pos.x >= sz.x - m.pad_end - m.icon - m.gap {
						flag^ = !flag^
					} else {
						flag^ = true
					}
				}
			case .Text:
				if typed && len(e.text) > 0 && !c.disabled {
					inject_at_elems(&s.buf, s.cursor, ..transmute([]u8)e.text)
					s.cursor += len(e.text)
					r.edited = true
					flag^ = true
				}
			case .Key:
				if c.disabled {
					continue
				}
				#partial switch e.key {
				case .Escape:
					flag^ = false
				case .Tab:
					flag^ = false
				case .Down, .Up:
					if !flag^ {
						flag^ = true
					} else if pk, _ := step_listbox(gtx, p.id, e.key, len(shown)); pk >= 0 {
						selected^ = pick_shown(pk, map_back)
					}
				case .Enter, .Space:
					if e.key == .Space && typed {
						inject_at_elems(&s.buf, s.cursor, ' ')
						s.cursor += 1
						r.edited = true
						continue
					}
					if !flag^ {
						flag^ = true
					} else if pk, _ := step_listbox(gtx, p.id, e.key, len(shown)); pk >= 0 {
						selected^ = pick_shown(pk, map_back)
						flag^ = false
					}
				case .Home, .End, .Page_Up, .Page_Down:
					if flag^ && !typed {
						step_listbox(gtx, p.id, e.key, len(shown))
					} else if typed {
						r.edited |= ui.text_key(s, e.key, text_stops(gtx, s, m.style))
					}
				case:
					if typed {
						r.edited |= ui.text_key(s, e.key, text_stops(gtx, s, m.style))
					}
				}
			}
		}
		sel_text := selected^ >= 0 && selected^ < len(options) ? options[selected^] : ""
		if typed && d.was_focused && !c.focused && !flag^ && !freeform && string(s.buf[:]) != sel_text {
			// Blur: revert text that matches no option (behaviour filter).
			ui.text_set(s, sel_text)
		}
		d.was_focused = c.focused
	}
	query := typed ? string(s.buf[:]) : ""
	sel_text := selected^ >= 0 && selected^ < len(options) ? options[selected^] : ""
	shown, map_back, shown_sel = filter_options(gtx, options, query, selected^)

	k := field_colors(appearance, c, invalid, .Outline_Only)
	rad := paint_field(gtx, area, appearance, k)
	// The text: typed, or the selection's, else the placeholder.
	shown_text := typed ? query : sel_text
	t := layout_style(gtx, shown_text, m.style)
	inner_w := sz.x - m.pad_start - m.pad_end - m.icon - m.gap
	y_text := (sz.y - m.style.line_height) / 2
	ops.clip_push(gtx.scene, ops.Rect{m.pad_start, tok.STROKE_WIDTH_THIN, max(inner_w, 0), sz.y - 2 * tok.STROKE_WIDTH_THIN})
	if shown_text != "" {
		draw_paragraph(gtx, t, {m.pad_start, y_text}, k.text)
	} else if placeholder != "" {
		draw_text(gtx, shape_style(gtx, placeholder, m.style), {m.pad_start, y_text}, k.placeholder)
	}
	if typed && c.focused && !c.disabled {
		_, caret := ui.paragraph_caret(t, s.cursor)
		ops.fill(gtx.scene, ops.Rect{m.pad_start + caret, y_text + 2, 1, m.style.line_height - 4}, k.text)
	}
	ops.clip_pop(gtx.scene)
	// The field's area first, so the clear control sits on top of it.
	listen(gtx, c.st, p.id, area, typed ? FIELD_KINDS : CLICK_KINDS, typed ? .Text : .Default)
	// The expand icon, or the clear control in its place.
	icon_at := ops.Point{sz.x - m.pad_end - m.icon, (sz.y - m.icon) / 2}
	if clearable && selected^ >= 0 && !c.disabled {
		clear_id := ui.id_mix(p.id, 0xc1ea)
		hit := ops.Rect{icon_at.x - m.gap, 0, m.icon + m.gap + m.pad_end, sz.y}
		cc := control(gtx, clear_id, hit, state)
		if cc.clicked {
			selected^ = -1
			if typed {
				ui.text_set(s, "")
			}
		}
		icon(gtx, .Dismiss, icon_at, m.icon, color_for({.Neutral_Stroke_Accessible, .Neutral_Stroke_Accessible_Hover, .Neutral_Stroke_Accessible_Pressed, .Neutral_Foreground_Disabled}, cc))
		listen(gtx, cc.st, clear_id, hit)
		ops.tag(gtx.scene, clear_id, "clear")
	} else {
		icon(gtx, .Chevron_Down, icon_at, m.icon, k.icon)
	}
	paint_growth(gtx, area, rad, focus_growth(gtx, c, p.id, flag^), k.line)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : placeholder))

	pk := listbox(gtx, p.id, flag, shown, shown_sel, sz.x, sz.y)
	if pk.picked >= 0 {
		selected^ = pick_shown(pk.picked, map_back)
		flag^ = false
	}
	if selected^ != old {
		r.changed = true
		if typed {
			ui.text_set(s, selected^ >= 0 && selected^ < len(options) ? options[selected^] : "")
		}
	}
	r.opened = flag^
	ui.widget_close(gtx, &p, {sz, y_text + t.lines[0].baseline})
	return
}

// filter_options is the options containing query, case-folded, with
// each shown row's index in options and the selection's row; all of
// them, with no index map, while query is empty or the selection's own
// text.
@(private = "file")
filter_options :: proc(gtx: ^ui.Ctx, options: []string, query: string, selected: int) -> (shown: []string, map_back: []int, shown_sel: int) {
	sel_text := selected >= 0 && selected < len(options) ? options[selected] : ""
	if query == "" || query == sel_text {
		return options, nil, selected
	}
	idx := make([dynamic]int, gtx.allocator)
	q := strings.to_lower(query, gtx.allocator)
	for o, i in options {
		if strings.contains(strings.to_lower(o, gtx.allocator), q) {
			append(&idx, i)
		}
	}
	shown = make([]string, len(idx), gtx.allocator)
	shown_sel = -1
	for i, j in idx {
		shown[j] = options[i]
		if i == selected {
			shown_sel = j
		}
	}
	return shown, idx[:], shown_sel
}

// dropdown is combobox as a button trigger: no typing, the selection's
// text or the placeholder, and Enter or Space to open.
dropdown :: proc(
	gtx: ^ui.Ctx,
	options: []string,
	selected: ^int,
	placeholder := "",
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	open: ^bool = nil,
	clearable := false,
	invalid := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> Picker_Result {
	return combobox(gtx, nil, options, selected, placeholder, .Dropdown, appearance, size, open, false, clearable, invalid, width, name, state, key, loc)
}

// select is Fluent's styled native select (select.json): a field showing
// the chosen option with a chevron, in Input's appearances and sizes,
// that opens the listbox in place of the platform's popup. Its hover
// and press step only the side borders, never the StrokeAccessible
// bottom edge, and its focus line sits inside the box along its bottom
// edge rather than 1px outside (select.json notes).
//
// Departure: the platform-drawn popup is the listbox here, so the list
// is themed where Fluent's is not.
select :: proc(
	gtx: ^ui.Ctx,
	options: []string,
	selected: ^int,
	placeholder := "",
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	invalid := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Picker_Result) {
	p := ui.widget_open(gtx, key, loc)
	m := field_metrics(size)
	d := ui.widget_data(gtx, p.id, Combobox_Data)
	cs := gtx.constraints
	w := width
	if w <= 0 {
		w = ui.is_finite(cs.max.x) ? cs.max.x : FIELD_DEFAULT_WIDTH
	}
	sz := ui.constrain(cs, {w, m.h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	old := selected^
	if c.disabled {
		d.open = false
	}
	if c.st != nil && !c.disabled {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left {
					d.open = !d.open
				}
			case .Key:
				#partial switch e.key {
				case .Escape, .Tab:
					d.open = false
				case .Down, .Up, .Enter, .Space, .Home, .End:
					if !d.open {
						d.open = true
					} else if pk, _ := step_listbox(gtx, p.id, e.key, len(options)); pk >= 0 {
						selected^ = pk
						d.open = false
					}
				}
			}
		}
	}
	k := field_colors(appearance, c, invalid, .Sides_Only)
	rad := paint_field(gtx, area, appearance, k)
	sel_text := selected^ >= 0 && selected^ < len(options) ? options[selected^] : ""
	t := shape_style(gtx, sel_text, m.style)
	y_text := (sz.y - m.style.line_height) / 2
	inner_w := sz.x - m.pad_start - m.pad_end - m.icon - 2 * m.gap
	ops.clip_push(gtx.scene, ops.Rect{m.pad_start, tok.STROKE_WIDTH_THIN, max(inner_w, 0), sz.y - 2 * tok.STROKE_WIDTH_THIN})
	if sel_text != "" {
		draw_text(gtx, t, {m.pad_start, y_text}, k.text)
	} else if placeholder != "" {
		draw_text(gtx, shape_style(gtx, placeholder, m.style), {m.pad_start, y_text}, k.placeholder)
	}
	ops.clip_pop(gtx.scene)
	icon(gtx, .Chevron_Down, {sz.x - m.pad_end - m.icon, (sz.y - m.icon) / 2}, m.icon, k.icon)
	paint_growth(gtx, area, rad, focus_growth(gtx, c, p.id, d.open), k.line, inside = true)
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : placeholder))
	pk := listbox(gtx, p.id, &d.open, options, selected^, sz.x, sz.y, check = false)
	if pk.picked >= 0 {
		selected^ = pk.picked
		d.open = false
	}
	r.changed = selected^ != old
	r.opened = d.open
	ui.widget_close(gtx, &p, {sz, y_text + baseline_of(t)})
	return
}

// Spin button.

// SPIN_* are the spin button's metrics (spin-button.json layout:
// useSpinButtonStyles.styles.ts:19-37,122-126,250-268,296-323): the
// button column, the button heights, and the spin timing from
// useSpinButton.tsx (300ms to the first repeat, then quickening to an
// 80ms floor over 1s).
@(private = "file")
SPIN_COLUMN :: f32(24)
@(private = "file")
SPIN_GAP :: tok.SPACING_HORIZONTAL_XS
@(private = "file")
SPIN_FIRST_REPEAT :: f32(0.3)
@(private = "file")
SPIN_FASTEST :: f32(0.08)
@(private = "file")
SPIN_RAMP :: f32(1)

// Spin_Data is a spin button's own text while it is being edited, the
// hold timer, and which button is held.
@(private = "file")
Spin_Data :: struct {
	buf:         [32]u8,
	n, cursor:   int,
	editing:     bool,
	was_focused: bool,
	held:        int, // 0 none, 1 increment, -1 decrement
	held_for:    f32, // seconds
	next_in:     f32, // seconds to the next repeat
}

// spin_metrics is size's numbers: the height, the start padding, the
// button height and the text style.
@(private = "file")
spin_metrics :: proc(size: Size) -> (h, pad_start, button_h, glyph: f32, st: tok.Type_Style) {
	if size == .Small {
		return 24, tok.SPACING_HORIZONTAL_S, 12, 10, style(.Caption1)
	}
	return 32, tok.SPACING_HORIZONTAL_MNUDGE, 16, 12, style(.Body1)
}

// spin_format writes v with precision decimals.
@(private = "file")
spin_format :: proc(v: f32, precision: int, allocator := context.temp_allocator) -> string {
	return fmt.aprintf("%.*f", precision, v, allocator = allocator)
}

// spin_precision is the decimals step needs: 0 for a whole step, else
// the count that writes it exactly, up to 6.
@(private = "file")
spin_precision :: proc(step: f32) -> int {
	for p in 0 ..< 6 {
		scaled := step * math.pow(10, f32(p))
		if abs(scaled - math.round(scaled)) < 1e-5 {
			return p
		}
	}
	return 6
}

// spin_button is a numeric field with stacked increment and decrement
// buttons at its end (spin-button.json). value^ is the number; a button
// press or ArrowUp/ArrowDown steps it by step, Page keys by step_page,
// Home and End go to lo and hi, all clamped and rounded to precision
// (step's own decimals when -1). Holding a button repeats the step,
// the first after 300ms and then quickening to every 80ms. Typing
// edits the field's own text, committed on Enter or blur (a number
// parses, clamps and rounds; anything else reverts) and dropped by
// Escape. lo and hi are optional bounds: pass -inf and +inf for none.
// Returns true on a frame value^ changed.
//
// Departure: the small size's 12px buttons are under the kit's 24px
// target, as the spec notes; keyboard stepping is the accessible path.
spin_button :: proc(
	gtx: ^ui.Ctx,
	value: ^f32,
	step: f32 = 1,
	lo: f32 = math.NEG_INF_F32,
	hi: f32 = math.INF_F32,
	step_page: f32 = 10,
	precision := -1,
	placeholder := "",
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	invalid := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	h, pad_start, button_h, glyph, tst := spin_metrics(size)
	prec := precision >= 0 ? precision : spin_precision(step)
	d := ui.widget_data(gtx, p.id, Spin_Data)
	cs := gtx.constraints
	w := width
	if w <= 0 {
		w = ui.is_finite(cs.max.x) ? cs.max.x : FIELD_DEFAULT_WIDTH
	}
	sz := ui.constrain(cs, {w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	old := value^
	apply :: proc(value: ^f32, v, lo, hi: f32, prec: int) {
		scale := math.pow(10, f32(prec))
		value^ = clamp(math.round(v * scale) / scale, lo, hi)
	}
	nudge :: proc(value: ^f32, by, lo, hi: f32, prec: int) {
		apply(value, value^ + by, lo, hi, prec)
	}

	// The two buttons: 24px wide, one per row of the height, the outer
	// end corner rounded (styles.ts:250-268).
	col_x := sz.x - SPIN_COLUMN - tok.STROKE_WIDTH_THIN
	up := ops.Rect{col_x, tok.STROKE_WIDTH_THIN, SPIN_COLUMN, button_h}
	down := ops.Rect{col_x, sz.y - tok.STROKE_WIDTH_THIN - button_h, SPIN_COLUMN, button_h}
	up_id, down_id := ui.id_mix(p.id, 0x5a01), ui.id_mix(p.id, 0x5a02)
	// A forced state shows on the increment button alone, as a pointer
	// can only be over one.
	cu := control(gtx, up_id, up, state)
	cd := control(gtx, down_id, down, state == .Live || state == .Disabled ? state : .Enabled)
	if c.st != nil && !c.disabled {
		// Holding: repeat while a button stays pressed.
		held := cu.pressed ? 1 : cd.pressed ? -1 : 0
		if held != d.held {
			d.held, d.held_for, d.next_in = held, 0, SPIN_FIRST_REPEAT
		} else if held != 0 {
			d.held_for += gtx.dt
			d.next_in -= gtx.dt
			if d.next_in <= 0 {
				nudge(value, f32(held) * step, lo, hi, prec)
				ramp := clamp(d.held_for / SPIN_RAMP, 0, 1)
				d.next_in = SPIN_FIRST_REPEAT + (SPIN_FASTEST - SPIN_FIRST_REPEAT) * ramp
			}
		}
		if held != 0 {
			ui.request_frame(gtx)
		}
		if cu.press {
			nudge(value, step, lo, hi, prec)
		}
		if cd.press {
			nudge(value, -step, lo, hi, prec)
		}
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left {
					if !d.editing {
						txt := spin_format(value^, prec)
						d.n = copy(d.buf[:], txt)
						d.editing = true
					}
					// The caret from the press: measure prefixes.
					str := string(d.buf[:d.n])
					d.cursor = d.n
					for i in 0 ..= d.n {
						if shape_style(gtx, str[:i], tst).width >= e.pos.x - pad_start {
							d.cursor = i
							break
						}
					}
				}
			case .Text:
				for b in transmute([]u8)e.text {
					if d.n < len(d.buf) && ((b >= '0' && b <= '9') || b == '.' || b == '-' || b == '+' || b == 'e') {
						copy(d.buf[d.cursor + 1:d.n + 1], d.buf[d.cursor:d.n])
						d.buf[d.cursor] = b
						d.n += 1
						d.cursor += 1
						d.editing = true
					}
				}
			case .Key:
				#partial switch e.key {
				case .Up:
					nudge(value, step, lo, hi, prec)
					d.editing = false
				case .Down:
					nudge(value, -step, lo, hi, prec)
					d.editing = false
				case .Page_Up:
					nudge(value, step_page, lo, hi, prec)
					d.editing = false
				case .Page_Down:
					nudge(value, -step_page, lo, hi, prec)
					d.editing = false
				case .Home:
					if lo > math.NEG_INF_F32 {
						apply(value, lo, lo, hi, prec)
						d.editing = false
					}
				case .End:
					if hi < math.INF_F32 {
						apply(value, hi, lo, hi, prec)
						d.editing = false
					}
				case .Enter:
					spin_commit(d, value, lo, hi, prec)
				case .Escape:
					d.editing = false
				case .Backspace:
					if d.editing && d.cursor > 0 {
						copy(d.buf[d.cursor - 1:], d.buf[d.cursor:d.n])
						d.n -= 1
						d.cursor -= 1
					}
				case .Delete:
					if d.editing && d.cursor < d.n {
						copy(d.buf[d.cursor:], d.buf[d.cursor + 1:d.n])
						d.n -= 1
					}
				case .Left:
					d.cursor = max(d.cursor - 1, 0)
				case .Right:
					d.cursor = min(d.cursor + 1, d.n)
				}
			}
		}
		if d.was_focused && !c.focused {
			spin_commit(d, value, lo, hi, prec)
		}
		d.was_focused = c.focused
	}

	k := field_colors(appearance, c, invalid, .All)
	rad := paint_field(gtx, area, appearance, k)
	// Text: the edit in progress, else the formatted value.
	shown := d.editing ? string(d.buf[:d.n]) : spin_format(value^, prec)
	t := shape_style(gtx, shown, tst)
	y_text := (sz.y - tst.line_height) / 2
	inner_w := col_x - SPIN_GAP - pad_start
	ops.clip_push(gtx.scene, ops.Rect{pad_start, tok.STROKE_WIDTH_THIN, max(inner_w, 0), sz.y - 2 * tok.STROKE_WIDTH_THIN})
	if shown != "" {
		draw_text(gtx, t, {pad_start, y_text}, k.text)
	} else if placeholder != "" {
		draw_text(gtx, shape_style(gtx, placeholder, tst), {pad_start, y_text}, k.placeholder)
	}
	if c.focused && !c.disabled && d.editing {
		caret := shape_style(gtx, shown[:min(d.cursor, len(shown))], tst).width
		ops.fill(gtx.scene, ops.Rect{pad_start + caret, y_text + 2, 1, tst.line_height - 4}, k.text)
	}
	ops.clip_pop(gtx.scene)
	// The buttons' tints: Subtle for outline and underline, the fill's
	// own Hover and Pressed for the filled appearances; the held
	// direction paints pressed (spin-button.json states).
	tint: State_Roles
	switch appearance {
	case .Filled_Darker, .Filled_Darker_Shadow:
		tint = {.Transparent_Background, .Neutral_Background3_Hover, .Neutral_Background3_Pressed, .Transparent_Background}
	case .Filled_Lighter, .Filled_Lighter_Shadow:
		tint = {.Transparent_Background, .Neutral_Background1_Hover, .Neutral_Background1_Pressed, .Transparent_Background}
	case .Outline, .Underline:
		tint = {.Transparent_Background, .Subtle_Background_Hover, .Subtle_Background_Pressed, .Transparent_Background}
	}
	GLYPH :: State_Roles{.Neutral_Foreground3, .Neutral_Foreground3_Hover, .Neutral_Foreground3_Pressed, .Neutral_Foreground_Disabled}
	paint_spin_button(gtx, up, .Chevron_Up, cu, tint, GLYPH, glyph, {0, rad, 0, 0})
	paint_spin_button(gtx, down, .Chevron_Down, cd, tint, GLYPH, glyph, {0, 0, rad, 0})
	paint_growth(gtx, area, rad, focus_growth(gtx, c, p.id), k.line)
	listen(gtx, c.st, p.id, area, FIELD_KINDS, .Text)
	listen(gtx, cu.st, up_id, up)
	listen(gtx, cd.st, down_id, down)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : placeholder))
	ops.tag(gtx.scene, up_id, "increment")
	ops.tag(gtx.scene, down_id, "decrement")
	ui.widget_close(gtx, &p, {sz, y_text + baseline_of(t)})
	return value^ != old
}

// spin_commit parses the edit in progress into value^ (behaviour
// commit): a number clamps and rounds, anything else reverts.
@(private = "file")
spin_commit :: proc(d: ^Spin_Data, value: ^f32, lo, hi: f32, prec: int) {
	if !d.editing {
		return
	}
	d.editing = false
	if v, ok := strconv.parse_f32(string(d.buf[:d.n])); ok {
		scale := math.pow(10, f32(prec))
		value^ = clamp(math.round(v * scale) / scale, lo, hi)
	}
}

@(private = "file")
paint_spin_button :: proc(gtx: ^ui.Ctx, r: ops.Rect, ic: Icon, c: Control, tint, glyph_roles: State_Roles, glyph: f32, k: Corners) {
	if bg := color_for(tint, c); ui.painted(bg) {
		ops.fill(gtx.scene, rounded(gtx, r, k), bg)
	}
	icon(gtx, ic, {r.x + (r.w - glyph) / 2, r.y + (r.h - glyph) / 2}, glyph, color_for(glyph_roles, c))
}

// Search box.

// SEARCH_MAX_WIDTH is the search box's maximum width
// (useSearchBoxStyles.styles.ts:20-41).
@(private = "file")
SEARCH_MAX_WIDTH :: f32(468)

// search_metrics is size's numbers (search-box.json variants, layout):
// the root's side padding, the dismiss icon size, and Input's height,
// icon and text style.
@(private = "file")
search_metrics :: proc(size: Size) -> (h, pad, icon_size: f32, st: tok.Type_Style) {
	switch size {
	case .Small:
		return 24, tok.SPACING_HORIZONTAL_SNUDGE, 16, style(.Caption1)
	case .Medium:
	case .Large:
		return 40, tok.SPACING_HORIZONTAL_MNUDGE, 24, style(.Body2)
	}
	return 32, tok.SPACING_HORIZONTAL_S, 20, style(.Body1)
}

// search_box is an Input for queries (search-box.json): the Search icon
// leading, the text, and, while focused with text, a dismiss control
// that clears it and keeps focus; Escape clears too. Input's
// appearances, sizes, focus line and disabled look apply; the box is
// at most 468px wide. Returns what the frame did to s.
search_box :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	placeholder := "Search",
	appearance := Input_Appearance.Outline,
	size := Size.Medium,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Edit) {
	p := ui.widget_open(gtx, key, loc)
	h, pad, icon_size, tst := search_metrics(size)
	cs := gtx.constraints
	w := width
	if w <= 0 {
		w = ui.is_finite(cs.max.x) ? cs.max.x : FIELD_DEFAULT_WIDTH
	}
	w = min(w, SEARCH_MAX_WIDTH)
	sz := ui.constrain(cs, {w, h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	s.cursor = clamp(s.cursor, 0, len(s.buf))
	left := pad + icon_size + tok.SPACING_HORIZONTAL_SNUDGE
	// The dismiss control shows while the box, or the control itself,
	// has focus or the pointer down, and there is text.
	dismiss_id := ui.id_mix(p.id, 0xd155)
	dst := c.st != nil ? ui.widget_state(gtx, dismiss_id) : nil
	own := dst != nil && (dst.focused || dst.pressed)
	showing_dismiss := (c.focused || c.pressed || own) && !c.disabled && len(s.buf) > 0
	dismiss := ops.Rect{sz.x - pad - icon_size, 0, pad + icon_size, sz.y}
	cd := control(gtx, dismiss_id, dismiss, c.disabled ? .Disabled : state)
	if c.st != nil && !c.disabled {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				s.cursor = ui.paragraph_hit(layout_style(gtx, string(s.buf[:]), tst), {e.pos.x - left, 0})
			case .Text:
				if len(e.text) > 0 {
					inject_at_elems(&s.buf, s.cursor, ..transmute([]u8)e.text)
					s.cursor += len(e.text)
					r.changed = true
				}
			case .Key:
				#partial switch e.key {
				case .Enter:
					r.submitted = true
				case .Escape:
					if len(s.buf) > 0 {
						ui.text_set(s, "")
						r.changed = true
					}
				case:
					r.changed |= ui.text_key(s, e.key, text_stops(gtx, s, tst))
				}
			}
		}
		if cd.clicked && showing_dismiss {
			ui.text_set(s, "")
			r.changed = true
		}
	}
	r.focused = c.focused && !c.disabled
	showing_dismiss = (c.focused || c.pressed || own) && !c.disabled && len(s.buf) > 0
	k := field_colors(appearance, c, false, .Outline_Only)
	rad := paint_field(gtx, area, appearance, k)
	content := color(c.disabled ? .Neutral_Foreground_Disabled : .Neutral_Foreground3)
	icon(gtx, .Search, {pad, (sz.y - icon_size) / 2}, icon_size, content)
	right := showing_dismiss ? pad + icon_size + tok.SPACING_HORIZONTAL_M : pad
	inner := max(sz.x - left - right, 0)
	str := string(s.buf[:])
	t := layout_style(gtx, str, tst)
	y_text := (sz.y - tst.line_height) / 2
	ops.clip_push(gtx.scene, ops.Rect{left, tok.STROKE_WIDTH_THIN, inner, sz.y - 2 * tok.STROKE_WIDTH_THIN})
	if len(str) > 0 {
		draw_paragraph(gtx, t, {left, y_text}, k.text)
	} else if placeholder != "" {
		draw_text(gtx, shape_style(gtx, placeholder, tst), {left, y_text}, k.placeholder)
	}
	if r.focused {
		_, caret := ui.paragraph_caret(t, s.cursor)
		ops.fill(gtx.scene, ops.Rect{left + caret, y_text + 2, 1, tst.line_height - 4}, k.text)
	}
	ops.clip_pop(gtx.scene)
	listen(gtx, c.st, p.id, area, FIELD_KINDS, .Text) // under the dismiss control
	if showing_dismiss {
		icon(gtx, .Dismiss, {sz.x - pad - icon_size, (sz.y - icon_size) / 2}, icon_size, color_for({.Neutral_Foreground3, .Neutral_Foreground3_Hover, .Neutral_Foreground3_Pressed, .Neutral_Foreground_Disabled}, cd))
		listen(gtx, cd.st, dismiss_id, dismiss)
		ops.tag(gtx.scene, dismiss_id, "dismiss")
	}
	paint_growth(gtx, area, rad, focus_growth(gtx, c, p.id), k.line)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : placeholder))
	ui.widget_close(gtx, &p, {sz, y_text + t.lines[0].baseline})
	return
}

// Tag picker.

// Tag_Picker_Size is the picker's size, one step above the tags it
// holds: medium holds extra-small tags, large small ones, extra-large
// medium ones (tagPicker2Tag.ts; tag-picker.json notes).
Tag_Picker_Size :: enum u8 {
	Medium,
	Large,
	Extra_Large,
}

// tag_picker_metrics is size's numbers (tag-picker.json variants and
// layout: useTagPickerControlStyles.styles.ts:24-35,94-103,183-225,
// useTagPickerGroupStyles.styles.ts:17-36, useTagPickerInputStyles.
// styles.ts:13-56): the minimum height, the group's vertical padding
// and gap, the expand icon and its margin, and the tag's own height,
// icon and text style (tag.json variants size).
@(private = "file")
Tag_Picker_Metrics :: struct {
	min_h, pad_v, gap, icon, icon_gap: f32,
	tag_h, tag_icon, tag_pad:           f32,
	tag_style:                          tok.Type_Style,
}

@(private = "file")
tag_picker_metrics :: proc(size: Tag_Picker_Size) -> Tag_Picker_Metrics {
	switch size {
	case .Medium:
		return {32, tok.SPACING_VERTICAL_SNUDGE, tok.SPACING_HORIZONTAL_XS, 16, tok.SPACING_HORIZONTAL_XXS, 20, 12, 5, style(.Caption1)}
	case .Large:
		return {40, tok.SPACING_VERTICAL_S, tok.SPACING_HORIZONTAL_SNUDGE, 20, tok.SPACING_HORIZONTAL_XXS, 24, 16, 5, style(.Caption1)}
	case .Extra_Large:
		return {44, tok.SPACING_VERTICAL_S, tok.SPACING_HORIZONTAL_SNUDGE, 24, tok.SPACING_HORIZONTAL_SNUDGE, 32, 20, 7, style(.Body1)}
	}
	return {}
}

// TAG_INPUT_MIN_WIDTH is the typing slot's minimum width
// (useTagPickerInputStyles.styles.ts:13-56).
@(private = "file")
TAG_INPUT_MIN_WIDTH :: f32(24)

// tag_picker is a multi-select field whose picks show as dismissible
// tags inside it (tag-picker.json): chosen[i] is whether options[i] is
// picked, s the text typed to filter the rest. Clicking the control,
// ArrowDown or typing opens the list of unpicked options containing the
// text; a pick adds a tag, clears the text and keeps the list open;
// a tag's dismiss, or Backspace in an empty input, removes it. Escape,
// Tab and a press outside close the list. Tags are filled: Background 3
// with Foreground 2 text, rounded, at the size below the picker's.
//
// Departures: the button trigger, the secondary action slot, inline
// and no-popover forms are not built; tags do not wrap to a second
// row, they scroll out of view past the control's width.
tag_picker :: proc(
	gtx: ^ui.Ctx,
	s: ^ui.Text_State,
	options: []string,
	chosen: []bool,
	placeholder := "",
	appearance := Input_Appearance.Outline,
	size := Tag_Picker_Size.Medium,
	open: ^bool = nil,
	invalid := false,
	width: f32 = 0,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> (r: Picker_Result) {
	p := ui.widget_open(gtx, key, loc)
	m := tag_picker_metrics(size)
	d := ui.widget_data(gtx, p.id, Combobox_Data)
	flag := open != nil ? open : &d.open
	cs := gtx.constraints
	w := width
	if w <= 0 {
		w = ui.is_finite(cs.max.x) ? cs.max.x : FIELD_DEFAULT_WIDTH
	}
	w = max(w, FIELD_MIN_WIDTH)
	sz := ui.constrain(cs, {w, m.min_h})
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	if c.disabled {
		flag^ = false
	}
	s.cursor = clamp(s.cursor, 0, len(s.buf))
	query := string(s.buf[:])

	// The unpicked options containing the text.
	idx := make([dynamic]int, gtx.allocator)
	lower_q := strings.to_lower(query, gtx.allocator)
	for o, i in options {
		if i < len(chosen) && chosen[i] {
			continue
		}
		if query == "" || strings.contains(strings.to_lower(o, gtx.allocator), lower_q) {
			append(&idx, i)
		}
	}
	shown := make([]string, len(idx), gtx.allocator)
	for i, j in idx {
		shown[j] = options[i]
	}
	pick := proc(chosen: []bool, s: ^ui.Text_State, i: int, r: ^Picker_Result) {
		if i >= 0 && i < len(chosen) {
			chosen[i] = true
			ui.text_set(s, "")
			r.changed = true
		}
	}

	// The tags, then the text slot: laid left to right, spacingHorizontalXXS
	// apart, inside the control's spacingHorizontalM start padding.
	x := tok.SPACING_HORIZONTAL_M
	tag_y := (sz.y - m.tag_h) / 2
	if c.st != nil && !c.disabled {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left {
					flag^ = true
					s.cursor = len(s.buf)
				}
			case .Text:
				if len(e.text) > 0 {
					inject_at_elems(&s.buf, s.cursor, ..transmute([]u8)e.text)
					s.cursor += len(e.text)
					r.edited = true
					flag^ = true
				}
			case .Key:
				#partial switch e.key {
				case .Escape, .Tab:
					flag^ = false
				case .Down, .Up:
					if !flag^ {
						flag^ = true
					} else if pk, _ := step_listbox(gtx, p.id, e.key, len(shown)); pk >= 0 {
						pick(chosen, s, idx[pk], &r)
					}
				case .Enter:
					if flag^ {
						if pk, _ := step_listbox(gtx, p.id, e.key, len(shown)); pk >= 0 {
							pick(chosen, s, idx[pk], &r)
						}
					} else {
						flag^ = true
					}
				case .Backspace:
					if len(s.buf) == 0 {
						#reverse for &ch in chosen {
							if ch {
								ch = false
								r.changed = true
								break
							}
						}
					} else {
						r.edited |= ui.text_key(s, e.key, text_stops(gtx, s, style(.Body1)))
					}
				case:
					r.edited |= ui.text_key(s, e.key, text_stops(gtx, s, style(.Body1)))
				}
			}
		}
	}

	k := field_colors(appearance, c, invalid, .Outline_Only)
	rad := paint_field(gtx, area, appearance, k)
	listen(gtx, c.st, p.id, area, FIELD_KINDS, .Text) // under the tags, which take their own clicks
	end_pad := tok.SPACING_HORIZONTAL_M + m.icon + m.icon_gap
	ops.clip_push(gtx.scene, ops.Rect{tok.STROKE_WIDTH_THIN, tok.STROKE_WIDTH_THIN, sz.x - end_pad - tok.STROKE_WIDTH_THIN, sz.y - 2 * tok.STROKE_WIDTH_THIN})
	for o, i in options {
		if i >= len(chosen) || !chosen[i] {
			continue
		}
		// A forced picker's tags rest; only a live one's react.
		tag_state: Interaction = c.disabled ? .Disabled : state == .Live ? .Live : .Enabled
		tw := paint_tag(gtx, ui.id_mix(p.id, u64(0x7a00 + i)), {x, tag_y}, o, m, tag_state)
		if tw < 0 {
			chosen[i] = false
			r.changed = true
			tw = -tw
		}
		x += tw + tok.SPACING_HORIZONTAL_XXS
	}
	// The text slot takes the rest, at least TAG_INPUT_MIN_WIDTH.
	tst := style(.Body1)
	t := layout_style(gtx, query, tst)
	y_text := (sz.y - tst.line_height) / 2
	slot_w := max(sz.x - end_pad - x, TAG_INPUT_MIN_WIDTH)
	ops.clip_push(gtx.scene, ops.Rect{x, tok.STROKE_WIDTH_THIN, slot_w, sz.y - 2 * tok.STROKE_WIDTH_THIN})
	if query != "" {
		draw_paragraph(gtx, t, {x, y_text}, k.text)
	} else if placeholder != "" && x == tok.SPACING_HORIZONTAL_M {
		draw_text(gtx, shape_style(gtx, placeholder, tst), {x, y_text}, k.placeholder)
	}
	if c.focused && !c.disabled {
		_, caret := ui.paragraph_caret(t, s.cursor)
		ops.fill(gtx.scene, ops.Rect{x + caret, y_text + 2, 1, tst.line_height - 4}, k.text)
	}
	ops.clip_pop(gtx.scene)
	ops.clip_pop(gtx.scene)
	icon(gtx, .Chevron_Down, {sz.x - tok.SPACING_HORIZONTAL_M - m.icon, (m.min_h - m.icon) / 2}, m.icon, k.icon)
	paint_growth(gtx, area, rad, focus_growth(gtx, c, p.id, flag^), k.line)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : placeholder))
	pk := listbox(gtx, p.id, flag, shown, -1, sz.x, sz.y, check = false)
	if pk.picked >= 0 {
		pick(chosen, s, idx[pk.picked], &r)
	}
	r.opened = flag^
	ui.widget_close(gtx, &p, {sz, y_text + t.lines[0].baseline})
	return
}

// paint_tag paints one picked tag at pos (tag.json: filled appearance,
// rounded, Background 3 with Foreground 2 text, the dismiss icon at its
// end) and reads its dismiss click. Returns the tag's width, negated
// when its dismiss was clicked.
@(private = "file")
paint_tag :: proc(gtx: ^ui.Ctx, id: ops.Area_Id, pos: ops.Point, label: string, m: Tag_Picker_Metrics, state: Interaction) -> f32 {
	t := shape_style(gtx, label, m.tag_style)
	w := m.tag_pad + tok.SPACING_HORIZONTAL_XXS + t.width + tok.SPACING_HORIZONTAL_XXS + m.tag_icon + m.tag_pad
	r := ops.Rect{pos.x, pos.y, w, m.tag_h}
	c := control(gtx, id, r, state)
	disabled := state == .Disabled
	bg := color(disabled ? .Neutral_Background_Disabled : .Neutral_Background3)
	fg := color(disabled ? .Neutral_Foreground_Disabled : .Neutral_Foreground2)
	rr := ops.Round_Rect{r, tok.BORDER_RADIUS_MEDIUM}
	ops.fill(gtx.scene, rr, bg)
	stroke_inside(gtx, rr, color(disabled ? .Transparent_Stroke_Disabled : .Transparent_Stroke), tok.STROKE_WIDTH_THIN)
	draw_text(gtx, t, {r.x + m.tag_pad + tok.SPACING_HORIZONTAL_XXS, r.y + (r.h - t.height) / 2}, fg)
	dismiss_fg := color_for({.Neutral_Foreground2, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	icon(gtx, .Dismiss, {r.x + r.w - m.tag_pad - m.tag_icon, r.y + (r.h - m.tag_icon) / 2}, m.tag_icon, dismiss_fg)
	paint_focus_outline(gtx, c, rr)
	listen(gtx, c.st, id, r)
	ops.tag(gtx.scene, id, ui.frame_string(gtx, label))
	return c.clicked ? -w : w
}

// Swatch picker.

// Swatch is one swatch: a colour, an empty slot, or an image, which
// jm:ui cannot draw, so it takes a paint callback or shows as empty.
Swatch :: struct {
	color:    ops.Color,
	border:   ops.Color, // zero: Transparent_Stroke
	empty:    bool,
	disabled: bool,
	name:     string, // the tag; the colour's hex when empty
}

Swatch_Size :: enum u8 {
	Extra_Small,
	Small,
	Medium,
	Large,
}

Swatch_Shape :: enum u8 {
	Square,
	Rounded,
	Circular,
}

// swatch_metrics is size's side, icon size and the ring pairs by state
// (swatch-picker.json layout and states: useColorSwatchStyles.styles.
// ts:21-30,104-171): the hover inner and outer widths, the pressed
// pair, and the selected pair at rest, hovered and pressed.
@(private = "file")
Swatch_Metrics :: struct {
	side, icon:                     f32,
	hover_in, hover_out:            f32,
	press_in, press_out:            f32,
	sel_in, sel_out:                f32,
	sel_hover_in, sel_hover_out:    f32,
	sel_press_in, sel_press_out:    f32,
}

@(private = "file")
swatch_metrics :: proc(size: Swatch_Size) -> Swatch_Metrics {
	thin, thick, thicker, thickest := tok.STROKE_WIDTH_THIN, tok.STROKE_WIDTH_THICK, tok.STROKE_WIDTH_THICKER, tok.STROKE_WIDTH_THICKEST
	switch size {
	case .Extra_Small:
		return {20, 16, thin, thick, thick, thicker, thick, thicker, thick, thicker, thicker, thickest}
	case .Small:
		return {24, 16, thick, thicker, thick, thicker, thick, thicker, thick, thicker, thicker, thickest}
	case .Medium:
		return {28, 20, thick, thicker, thicker, thickest, thicker, 5, thickest, 6, thickest, 7}
	case .Large:
		return {32, 24, thick, thicker, thicker, thickest, thicker, 5, thickest, 6, thickest, 7}
	}
	return {}
}

// swatch_picker is a row, or a grid of columns per row, of swatches of
// which selected^ is chosen (swatch-picker.json). A click selects and
// returns true; arrow keys on a focused swatch move the selection. Each
// swatch is a square clipped to the shape, its own border replaced by
// two inset rings when hovered, pressed, focused or selected; a
// disabled swatch keeps its colour and takes nothing. An empty swatch
// draws a dashed Neutral_Foreground4 border, as short dashes on its
// straight edges, or a solid ring when circular (ops strokes no
// dashes).
//
// Departure: focusMode arrow, one tab stop with arrows moving focus,
// has no jm:ui equivalent; every swatch is a tab stop and arrows move
// the selection instead.
swatch_picker :: proc(
	gtx: ^ui.Ctx,
	swatches: []Swatch,
	selected: ^int,
	columns := 0, // 0: one row
	size := Swatch_Size.Medium,
	shape := Swatch_Shape.Square,
	spacing_small := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	m := swatch_metrics(size)
	gap: f32 = spacing_small ? 2 : 4
	n := len(swatches)
	cols := columns > 0 ? min(columns, n) : n
	rows := cols > 0 ? (n + cols - 1) / cols : 0
	sz := ui.constrain(gtx.constraints, {f32(cols) * m.side + f32(max(cols - 1, 0)) * gap, f32(rows) * m.side + f32(max(rows - 1, 0)) * gap})
	old := selected^
	rad: f32
	switch shape {
	case .Square:
		rad = tok.BORDER_RADIUS_NONE
	case .Rounded:
		rad = tok.BORDER_RADIUS_MEDIUM
	case .Circular:
		rad = m.side / 2
	}
	for sw, i in swatches {
		r := ops.Rect{f32(i %% cols) * (m.side + gap), f32(i / cols) * (m.side + gap), m.side, m.side}
		id := ui.id_mix(p.id, u64(i))
		c := control(gtx, id, r, sw.disabled ? .Disabled : state)
		if c.clicked && !sw.disabled {
			selected^ = i
		}
		if c.st != nil && c.focused {
			for e in ui.events(gtx, id) {
				if e.kind != .Key {
					continue
				}
				#partial switch e.key {
				case .Right:
					selected^ = (i + 1) %% n
				case .Left:
					selected^ = (i - 1 + n) %% n
				case .Down:
					if columns > 0 && i + cols < n {
						selected^ = i + cols
					}
				case .Up:
					if columns > 0 && i - cols >= 0 {
						selected^ = i - cols
					}
				}
			}
		}
		rr := ops.Round_Rect{r, rad}
		if sw.empty {
			ops.fill(gtx.scene, rr, color(.Neutral_Background1))
			if shape == .Circular {
				stroke_inside(gtx, rr, color(.Neutral_Foreground4), tok.STROKE_WIDTH_THIN) // no dashed arc: a solid ring
			} else {
				paint_dashed(gtx, r, rad, color(.Neutral_Foreground4))
			}
		} else {
			ops.fill(gtx.scene, rr, sw.color)
			stroke_inside(gtx, rr, ui.or_color(sw.border, color(.Transparent_Stroke)), tok.STROKE_WIDTH_THIN)
		}
		// The rings: an inner brand ring inside an outer light ring, both
		// inset, by state; selected has its own pair (states).
		inner, outer: f32
		inner_col, outer_col := color(.Brand_Stroke1), color(.Stroke_Focus1)
		is_sel := i == selected^
		switch {
		case sw.disabled:
		case is_sel && c.pressed:
			inner, outer, inner_col = m.sel_press_in, m.sel_press_out, color(.Compound_Brand_Stroke_Pressed)
		case is_sel && c.hovered:
			inner, outer, inner_col = m.sel_hover_in, m.sel_hover_out, color(.Compound_Brand_Stroke_Hover)
		case is_sel && c.focused:
			inner, outer, inner_col = m.sel_in, m.sel_out, color(.Stroke_Focus2)
		case is_sel:
			inner, outer = m.sel_in, m.sel_out
		case c.pressed:
			inner, outer, inner_col = m.press_in, m.press_out, color(.Compound_Brand_Stroke_Pressed)
		case c.focused:
			inner, outer, inner_col = m.hover_in, m.hover_out, color(.Stroke_Focus2)
		case c.hovered:
			inner, outer = m.hover_in, m.hover_out
		}
		if outer > 0 {
			stroke_inside(gtx, rr, outer_col, outer)
			stroke_inside(gtx, rr, inner_col, inner)
		}
		listen(gtx, c.st, id, r)
		ops.tag(gtx.scene, id, ui.frame_string(gtx, sw.name))
	}
	ui.widget_close(gtx, &p, {size = sz})
	return selected^ != old
}

// paint_dashed strokes r's inside edge in 1px dashes 3px long, 2px
// apart, for the empty swatch's dashed border.
@(private = "file")
paint_dashed :: proc(gtx: ^ui.Ctx, r: ops.Rect, rad: f32, col: ops.Color) {
	step: f32 = 5
	dash: f32 = 3
	for x := r.x + rad; x < r.x + r.w - rad; x += step {
		w := min(dash, r.x + r.w - rad - x)
		ops.fill(gtx.scene, ops.Rect{x, r.y, w, 1}, col)
		ops.fill(gtx.scene, ops.Rect{x, r.y + r.h - 1, w, 1}, col)
	}
	for y := r.y + rad; y < r.y + r.h - rad; y += step {
		h := min(dash, r.y + r.h - rad - y)
		ops.fill(gtx.scene, ops.Rect{r.x, y, 1, h}, col)
		ops.fill(gtx.scene, ops.Rect{r.x + r.w - 1, y, 1, h}, col)
	}
}

// Colour picker.

// Hsv is the colour the picker's controls share: hue in degrees 0-360,
// saturation, value and alpha in 0-1.
Hsv :: struct {
	h, s, v, a: f32,
}

// hsv_to_rgb is c as an opaque-or-not Color, the conversion
// createHsvColor.ts's callers use.
hsv_to_rgb :: proc(c: Hsv) -> ops.Color {
	h := math.mod(max(c.h, 0), 360) / 60
	i := int(h)
	f := h - f32(i)
	s, v := clamp(c.s, 0, 1), clamp(c.v, 0, 1)
	p := v * (1 - s)
	q := v * (1 - s * f)
	t := v * (1 - s * (1 - f))
	r, g, b: f32
	switch i {
	case 0:
		r, g, b = v, t, p
	case 1:
		r, g, b = q, v, p
	case 2:
		r, g, b = p, v, t
	case 3:
		r, g, b = p, q, v
	case 4:
		r, g, b = t, p, v
	case:
		r, g, b = v, p, q
	}
	return {u8(math.round(r * 255)), u8(math.round(g * 255)), u8(math.round(b * 255)), u8(math.round(clamp(c.a, 0, 1) * 255))}
}

// rgb_to_hsv is the inverse; a grey keeps hue 0.
rgb_to_hsv :: proc(c: ops.Color) -> Hsv {
	r, g, b := f32(c[0]) / 255, f32(c[1]) / 255, f32(c[2]) / 255
	hi, lo := max(r, g, b), min(r, g, b)
	d := hi - lo
	out := Hsv{0, hi > 0 ? d / hi : 0, hi, f32(c[3]) / 255}
	if d > 0 {
		switch hi {
		case r:
			out.h = 60 * math.mod((g - b) / d + 6, 6)
		case g:
			out.h = 60 * ((b - r) / d + 2)
		case:
			out.h = 60 * ((r - g) / d + 4)
		}
	}
	return out
}

// COLOR_* are the picker's metrics (color-picker.json layout:
// useColorAreaStyles.styles.ts:23-65, useColorSliderStyles.styles.ts:
// 30-109): the area's minimum side, the thumb, the rail, a slider's
// minimum length and height.
@(private = "file")
COLOR_AREA_MIN :: f32(300)
@(private = "file")
COLOR_THUMB :: f32(20)
@(private = "file")
COLOR_RAIL :: f32(20)
@(private = "file")
COLOR_SLIDER_MIN :: f32(200)
@(private = "file")
COLOR_SLIDER_MIN_VERTICAL :: f32(280)
@(private = "file")
COLOR_SLIDER_CROSS :: f32(32)

// even_stops is colors as gradient stops spread evenly from 0 to 1, in
// the frame allocator, as a gradient paint holds them.
@(private = "file")
even_stops :: proc(gtx: ^ui.Ctx, colors: ..ops.Color) -> []ops.Gradient_Stop {
	stops := make([]ops.Gradient_Stop, len(colors), gtx.allocator)
	for c, i in colors {
		stops[i] = {f32(i) / f32(max(len(colors) - 1, 1)), c}
	}
	return stops
}

// rail_ends are a rail's gradient end points: low to high value left to
// right, or bottom to top when vertical (color-picker.json layout).
@(private = "file")
rail_ends :: proc(rail: ops.Rect, vertical: bool) -> (p0, p1: ops.Point) {
	if vertical {
		return {rail.x, rail.y + rail.h}, {rail.x, rail.y}
	}
	return {rail.x, rail.y}, {rail.x + rail.w, rail.y}
}

Color_Shape :: enum u8 {
	Rounded,
	Square,
}

Color_Channel :: enum u8 {
	Hue,
	Saturation,
	Value,
}

@(private = "file")
COLOR_KINDS :: ops.Event_Kinds{.Press, .Release, .Move, .Enter, .Leave, .Key, .Focus, .Blur}

// color_area is the saturation-and-value square (color-picker.json):
// x is saturation, y value from the bottom, a 1px Neutral_Stroke1
// border, and the 20px thumb, which a press or drag moves (rounded to
// two decimals) and arrow keys nudge by 0.01. The square is the hue under
// white fading out to the right, under black fading in toward the bottom
// (useColorAreaStyles.styles.ts:26). Returns true on a frame hsv^ changed.
color_area :: proc(
	gtx: ^ui.Ctx,
	hsv: ^Hsv,
	side: f32 = COLOR_AREA_MIN,
	shape := Color_Shape.Rounded,
	name := "color area",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	l := max(side, COLOR_AREA_MIN)
	sz := ui.constrain_min(gtx.constraints, {l, l})
	area := ops.Rect{0, 0, sz.x, sz.y}
	old := hsv^
	c := control(gtx, p.id, area, state)
	set_from :: proc(hsv: ^Hsv, pos: ops.Point, sz: ops.Size) {
		hsv.s = math.round(clamp(pos.x / sz.x, 0, 1) * 100) / 100
		hsv.v = math.round(clamp(1 - pos.y / sz.y, 0, 1) * 100) / 100
	}
	if c.st != nil && !c.disabled {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left {
					set_from(hsv, e.pos, sz)
				}
			case .Move:
				if c.st.pressed {
					set_from(hsv, e.pos, sz)
				}
			case .Key:
				#partial switch e.key {
				case .Left:
					hsv.s = clamp(hsv.s - 0.01, 0, 1)
				case .Right:
					hsv.s = clamp(hsv.s + 0.01, 0, 1)
				case .Down:
					hsv.v = clamp(hsv.v - 0.01, 0, 1)
				case .Up:
					hsv.v = clamp(hsv.v + 0.01, 0, 1)
				}
			}
		}
	}
	rad := shape == .Rounded ? tok.BORDER_RADIUS_MEDIUM : 0
	ops.clip_push(gtx.scene, ops.Round_Rect{area, rad})
	white :: ops.Color{255, 255, 255, 255}
	black :: ops.Color{0, 0, 0, 255}
	ops.fill(gtx.scene, area, hsv_to_rgb({hsv.h, 1, 1, 1}))
	ops.fill(gtx.scene, area, ops.Linear_Gradient{{0, 0}, {sz.x, 0}, even_stops(gtx, white, ops.with_alpha(white, 0))})
	ops.fill(gtx.scene, area, ops.Linear_Gradient{{0, 0}, {0, sz.y}, even_stops(gtx, ops.with_alpha(black, 0), black)})
	ops.clip_pop(gtx.scene)
	stroke_inside(gtx, {area, rad}, color(.Neutral_Stroke1), tok.STROKE_WIDTH_THIN)
	centre := ops.Point{clamp(hsv.s, 0, 1) * sz.x, (1 - clamp(hsv.v, 0, 1)) * sz.y}
	paint_color_thumb(gtx, c, centre, hsv_to_rgb({hsv.h, hsv.s, hsv.v, 1}), false)
	listen(gtx, c.st, p.id, area, COLOR_KINDS)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	ui.widget_close(gtx, &p, {size = sz})
	return hsv^ != old
}

// paint_color_thumb paints the 20px thumb at centre: a strokeWidthThin
// Neutral_Foreground4 border, a strokeWidthThick Neutral_Background1
// ring inside it and the colour within, under shadow4; focused, the
// border widens to strokeWidthThick and, on the area, the default
// outline surrounds it, or, on a slider, it turns Stroke_Focus2
// (color-picker.json states).
@(private = "file")
paint_color_thumb :: proc(gtx: ^ui.Ctx, c: Control, centre: ops.Point, fill: ops.Color, on_slider: bool, ring_fill := ops.Color{}) {
	r := COLOR_THUMB / 2
	box := ops.Rect{centre.x - r, centre.y - r, COLOR_THUMB, COLOR_THUMB}
	paint_shadow(gtx, {box, r}, tok.SHADOW4)
	border_w := tok.STROKE_WIDTH_THIN
	border := color(.Neutral_Foreground4)
	if c.focused && !c.disabled {
		border_w = tok.STROKE_WIDTH_THICK
		if on_slider {
			border = color(.Stroke_Focus2)
		}
	}
	ops.fill(gtx.scene, ui.circle(centre, r), border)
	ops.fill(gtx.scene, ui.circle(centre, r - border_w), color(.Neutral_Background1))
	inner := r - border_w - tok.STROKE_WIDTH_THICK
	if ui.painted(ring_fill) {
		ops.fill(gtx.scene, ui.circle(centre, r - border_w), ring_fill)
	}
	ops.fill(gtx.scene, ui.circle(centre, inner), fill)
	if !on_slider {
		paint_focus_outline(gtx, c, {box, r})
	}
}

// color_slider is a rail for one channel of hsv^ (color-picker.json):
// hue over its six-colour gradient 0-360, saturation from #808080 to
// the hue, or value from black to the hue, 0-100. A press or drag sets
// the channel from the position along the rail; arrow keys step one
// unit, Home and End go to the ends. The rail is 20px thick with a 1px
// Transparent_Stroke outline and the shape's radius, in a root 32px
// across and at least 200px long (280 tall when vertical, where the
// smallest value is at the bottom). Each rail is one gradient paint
// (useColorSliderStyles.styles.ts:16-25,62-65).
color_slider :: proc(
	gtx: ^ui.Ctx,
	hsv: ^Hsv,
	channel := Color_Channel.Hue,
	length: f32 = COLOR_SLIDER_MIN,
	vertical := false,
	shape := Color_Shape.Rounded,
	name := "",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	l := max(length, vertical ? COLOR_SLIDER_MIN_VERTICAL : COLOR_SLIDER_MIN)
	sz := ui.constrain_min(gtx.constraints, vertical ? ops.Size{COLOR_SLIDER_CROSS, l} : {l, COLOR_SLIDER_CROSS})
	area := ops.Rect{0, 0, sz.x, sz.y}
	old := hsv^
	c := control(gtx, p.id, area, state)
	span: f32 = channel == .Hue ? 360 : 100
	get :: proc(hsv: ^Hsv, ch: Color_Channel) -> f32 {
		switch ch {
		case .Hue:
			return hsv.h
		case .Saturation:
			return hsv.s * 100
		case .Value:
			return hsv.v * 100
		}
		return 0
	}
	set :: proc(hsv: ^Hsv, ch: Color_Channel, v: f32) {
		switch ch {
		case .Hue:
			hsv.h = clamp(v, 0, 360)
		case .Saturation:
			hsv.s = clamp(v, 0, 100) / 100
		case .Value:
			hsv.v = clamp(v, 0, 100) / 100
		}
	}
	run := (vertical ? sz.y : sz.x) - COLOR_THUMB
	from_pos :: proc(pos: ops.Point, run: f32, vertical: bool) -> f32 {
		f := clamp(((vertical ? pos.y : pos.x) - COLOR_THUMB / 2) / max(run, 1), 0, 1)
		return vertical ? 1 - f : f
	}
	if c.st != nil && !c.disabled {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left {
					set(hsv, channel, math.round(from_pos(e.pos, run, vertical) * span))
				}
			case .Move:
				if c.st.pressed {
					set(hsv, channel, math.round(from_pos(e.pos, run, vertical) * span))
				}
			case .Key:
				v := get(hsv, channel)
				#partial switch e.key {
				case .Left, .Down:
					set(hsv, channel, v - 1)
				case .Right, .Up:
					set(hsv, channel, v + 1)
				case .Home:
					set(hsv, channel, 0)
				case .End:
					set(hsv, channel, span)
				}
			}
		}
	}
	rad := shape == .Rounded ? tok.BORDER_RADIUS_MEDIUM : 0
	rail := vertical ? ops.Rect{(sz.x - COLOR_RAIL) / 2, 0, COLOR_RAIL, sz.y} : {0, (sz.y - COLOR_RAIL) / 2, sz.x, COLOR_RAIL}
	ops.clip_push(gtx.scene, ops.Round_Rect{rail, rad})
	// Stops in the order the channel's value rises, so they follow the
	// thumb: hue through its six primaries and secondaries back to red,
	// saturation from grey to the hue, value from black to the hue.
	stops: []ops.Gradient_Stop
	hue := hsv_to_rgb({hsv.h, 1, 1, 1})
	switch channel {
	case .Hue:
		stops = even_stops(gtx, hsv_to_rgb({0, 1, 1, 1}), hsv_to_rgb({60, 1, 1, 1}), hsv_to_rgb({120, 1, 1, 1}), hsv_to_rgb({180, 1, 1, 1}), hsv_to_rgb({240, 1, 1, 1}), hsv_to_rgb({300, 1, 1, 1}), hsv_to_rgb({360, 1, 1, 1}))
	case .Saturation:
		stops = even_stops(gtx, {128, 128, 128, 255}, hue)
	case .Value:
		stops = even_stops(gtx, {0, 0, 0, 255}, hue)
	}
	p0, p1 := rail_ends(rail, vertical)
	ops.fill(gtx.scene, rail, ops.Linear_Gradient{p0, p1, stops})
	ops.clip_pop(gtx.scene)
	stroke_inside(gtx, {rail, rad}, color(.Transparent_Stroke), tok.STROKE_WIDTH_THIN)
	f := clamp(get(hsv, channel) / span, 0, 1)
	centre := vertical ? ops.Point{sz.x / 2, COLOR_THUMB / 2 + run * (1 - f)} : {COLOR_THUMB / 2 + run * f, sz.y / 2}
	thumb_fill := channel == .Hue ? hsv_to_rgb({hsv.h, 1, 1, 1}) : hsv_to_rgb({hsv.h, hsv.s, hsv.v, 1})
	paint_color_thumb(gtx, c, centre, thumb_fill, true)
	listen(gtx, c.st, p.id, area, COLOR_KINDS)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name != "" ? name : channel == .Hue ? "hue" : channel == .Saturation ? "saturation" : "value"))
	ui.widget_close(gtx, &p, {size = sz})
	return hsv^ != old
}

// alpha_slider is the rail for hsv^'s alpha (color-picker.json layout
// alpha-rail): the colour fading to transparent toward the low end over
// a checkerboard drawn from 5px cells, inside a 1px Neutral_Stroke1
// border; with transparency the value is 100 minus the alpha and the
// gradient runs the other way. The thumb is Neutral_Background1 with
// its inner ring in the colour at its alpha.
alpha_slider :: proc(
	gtx: ^ui.Ctx,
	hsv: ^Hsv,
	length: f32 = COLOR_SLIDER_MIN,
	vertical := false,
	transparency := false,
	shape := Color_Shape.Rounded,
	name := "alpha",
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	l := max(length, vertical ? COLOR_SLIDER_MIN_VERTICAL : COLOR_SLIDER_MIN)
	sz := ui.constrain_min(gtx.constraints, vertical ? ops.Size{COLOR_SLIDER_CROSS, l} : {l, COLOR_SLIDER_CROSS})
	area := ops.Rect{0, 0, sz.x, sz.y}
	old := hsv^
	c := control(gtx, p.id, area, state)
	run := (vertical ? sz.y : sz.x) - COLOR_THUMB
	// The slider's value: the alpha percentage, or its complement.
	value := transparency ? 100 * (1 - hsv.a) : 100 * hsv.a
	set :: proc(hsv: ^Hsv, v: f32, transparency: bool) {
		f := clamp(math.round(v), 0, 100) / 100
		hsv.a = transparency ? 1 - f : f
	}
	if c.st != nil && !c.disabled {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press, .Move:
				if e.kind == .Press ? e.button == .Left : c.st.pressed {
					f := clamp(((vertical ? e.pos.y : e.pos.x) - COLOR_THUMB / 2) / max(run, 1), 0, 1)
					set(hsv, (vertical ? 1 - f : f) * 100, transparency)
				}
			case .Key:
				#partial switch e.key {
				case .Left, .Down:
					set(hsv, value - 1, transparency)
				case .Right, .Up:
					set(hsv, value + 1, transparency)
				case .Home:
					set(hsv, 0, transparency)
				case .End:
					set(hsv, 100, transparency)
				}
			}
		}
	}
	value = transparency ? 100 * (1 - hsv.a) : 100 * hsv.a
	rad := shape == .Rounded ? tok.BORDER_RADIUS_MEDIUM : 0
	rail := vertical ? ops.Rect{(sz.x - COLOR_RAIL) / 2, 0, COLOR_RAIL, sz.y} : {0, (sz.y - COLOR_RAIL) / 2, sz.x, COLOR_RAIL}
	ops.clip_push(gtx.scene, ops.Round_Rect{rail, rad})
	// The checkerboard, then the colour at rising alpha along the rail.
	cell: f32 = 5
	for y := rail.y; y < rail.y + rail.h; y += cell {
		for x := rail.x; x < rail.x + rail.w; x += cell {
			dark := (int((x - rail.x) / cell) + int((y - rail.y) / cell)) % 2 == 0
			ops.fill(gtx.scene, ops.Rect{x, y, cell, cell}, dark ? ops.Color{204, 204, 204, 255} : ops.Color{255, 255, 255, 255})
		}
	}
	base := hsv_to_rgb({hsv.h, hsv.s, hsv.v, 1})
	// Transparent to the colour as the value rises; with transparency the
	// value is 100 minus the alpha, so the gradient runs the other way
	// (useAlphaSliderStyles.styles.ts:25).
	clear := ops.with_alpha(base, 0)
	p0, p1 := rail_ends(rail, vertical)
	ops.fill(gtx.scene, rail, ops.Linear_Gradient{p0, p1, transparency ? even_stops(gtx, base, clear) : even_stops(gtx, clear, base)})
	ops.clip_pop(gtx.scene)
	stroke_inside(gtx, {rail, rad}, color(.Neutral_Stroke1), tok.STROKE_WIDTH_THIN)
	f := clamp(value / 100, 0, 1)
	centre := vertical ? ops.Point{sz.x / 2, COLOR_THUMB / 2 + run * (1 - f)} : {COLOR_THUMB / 2 + run * f, sz.y / 2}
	paint_color_thumb(gtx, c, centre, {255, 255, 255, 255}, true, ring_fill = ops.with_alpha(base, hsv.a))
	listen(gtx, c.st, p.id, area, COLOR_KINDS)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	ui.widget_close(gtx, &p, {size = sz})
	return hsv^ != old
}

// color_picker composes the area, the hue slider and the alpha slider
// in a column spacingVerticalXS apart (color-picker.json layout
// picker), all sharing hsv^. Returns true on a frame it changed.
color_picker :: proc(
	gtx: ^ui.Ctx,
	hsv: ^Hsv,
	side: f32 = COLOR_AREA_MIN,
	shape := Color_Shape.Rounded,
	alpha := true,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	col := ui.column_open(gtx, gap = tok.SPACING_VERTICAL_XS, key = key, loc = loc)
	defer ui.close(&col)
	changed := color_area(gtx, hsv, side, shape, state = state)
	changed |= color_slider(gtx, hsv, .Hue, max(side, COLOR_AREA_MIN), shape = shape, state = state)
	if alpha {
		changed |= alpha_slider(gtx, hsv, max(side, COLOR_AREA_MIN), shape = shape, state = state)
	}
	return changed
}

// Rating.

Rating_Size :: enum u8 {
	Small,
	Medium,
	Large,
	Extra_Large,
}

Rating_Color :: enum u8 {
	Neutral,
	Brand,
	Marigold,
}

// RATING_STAR is a star's side per size (rating.json layout star:
// useRatingItemStyles.styles.ts:20-48).
RATING_STAR := [Rating_Size]f32{.Small = 12, .Medium = 16, .Large = 20, .Extra_Large = 28}

// rating_colors is the filled star's colour and a display's unfilled
// one for c (rating.json variants color).
@(private = "file")
rating_colors :: proc(c: Rating_Color) -> (filled, muted: ops.Color) {
	switch c {
	case .Neutral:
		return color(.Neutral_Foreground1), color(.Neutral_Background6)
	case .Brand:
		return color(.Brand_Foreground1), color(.Brand_Background2)
	case .Marigold:
		return color(.Palette_Marigold_Border_Active), color(.Palette_Marigold_Background2)
	}
	return {}, {}
}

// Rating_Hover is which star the pointer is over, and whether its left
// half, for the preview.
@(private = "file")
Rating_Hover :: struct {
	over: int, // -1 none
	half: bool,
}

// rating collects a rating of max stars (rating.json): value^ rounds to
// the nearest whole, or half with half_steps, and a star at exactly half
// draws its filled icon clipped to the left half over the outline. Each
// star is its own radio: a click sets its value (its half from its left
// half), arrow keys on a focused star move the value a step, and
// hovering previews the value until the pointer leaves; hover, when
// given, receives the value the stars show. Returns true on a frame
// value^ changed.
rating :: proc(
	gtx: ^ui.Ctx,
	value: ^f32,
	max_stars := 5,
	half_steps := false,
	size := Rating_Size.Extra_Large,
	tint := Rating_Color.Neutral,
	name := "rating",
	hover: ^f32 = nil,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	side := RATING_STAR[size]
	n := max(max_stars, 1)
	sz := ui.constrain(gtx.constraints, {f32(n) * side, side})
	old := value^
	hv := ui.widget_data(gtx, p.id, Rating_Hover)
	step: f32 = half_steps ? 0.5 : 1
	shown := math.round(value^ / step) * step
	filled_col, _ := rating_colors(tint)
	any_hover := false
	cs := make([]Control, n, gtx.allocator)
	for i in 0 ..< n {
		r := ops.Rect{f32(i) * side, 0, side, side}
		id := ui.id_mix(p.id, u64(i))
		c := control(gtx, id, r, state)
		cs[i] = c
		if c.st != nil && !c.disabled {
			for e in ui.events(gtx, id) {
				#partial switch e.kind {
				case .Move, .Enter:
					hv.over, hv.half = i, half_steps && e.pos.x - r.x < side / 2
					any_hover = true
				case .Press:
					if e.button == .Left {
						value^ = f32(i) + (half_steps && e.pos.x - r.x < side / 2 ? 0.5 : 1)
					}
				case .Key:
					#partial switch e.key {
					case .Left, .Down:
						value^ = max(value^ - step, step)
					case .Right, .Up:
						value^ = min(value^ + step, f32(n))
					}
				}
			}
			if c.hovered {
				any_hover = true
			}
		}
		if c.hovered && c.st == nil {
			hv.over, hv.half = i, false
			any_hover = true
		}
		listen(gtx, c.st, id, r, CLICK_KINDS)
		ops.tag(gtx.scene, id, ui.frame_string(gtx, fmt.tprintf("%s %d", name, i + 1)))
	}
	if !any_hover {
		hv.over = -1
	}
	preview := shown
	if hv.over >= 0 {
		preview = f32(hv.over) + (hv.half ? 0.5 : 1)
	}
	if hover != nil {
		hover^ = preview
	}
	for i in 0 ..< n {
		r := ops.Rect{f32(i) * side, 0, side, side}
		fill := preview - f32(i) // 1 full, 0.5 half, else none
		paint_star(gtx, r, fill, filled_col, filled_col, false)
		paint_focus_outline(gtx, cs[i], {r, tok.BORDER_RADIUS_MEDIUM})
	}
	ui.widget_close(gtx, &p, {size = sz})
	return value^ != old
}

// paint_star paints one star box: the filled icon where fill >= 1, the
// unfilled look where fill <= 0 (the outline icon in fill_col, or the
// filled icon in muted for a display), and a half split at the centre.
@(private = "file")
paint_star :: proc(gtx: ^ui.Ctx, r: ops.Rect, fill: f32, fill_col, muted: ops.Color, display: bool) {
	unfilled :: proc(gtx: ^ui.Ctx, r: ops.Rect, display: bool, fill_col, muted: ops.Color) {
		if display {
			icon(gtx, .Star_Filled, {r.x, r.y}, r.w, muted)
		} else {
			icon(gtx, .Star, {r.x, r.y}, r.w, fill_col)
		}
	}
	switch {
	case fill >= 1:
		icon(gtx, .Star_Filled, {r.x, r.y}, r.w, fill_col)
	case fill >= 0.5:
		ops.clip_push(gtx.scene, ops.Rect{r.x, r.y, r.w / 2, r.h})
		icon(gtx, .Star_Filled, {r.x, r.y}, r.w, fill_col)
		ops.clip_pop(gtx.scene)
		ops.clip_push(gtx.scene, ops.Rect{r.x + r.w / 2, r.y, r.w / 2, r.h})
		unfilled(gtx, r, display, fill_col, muted)
		ops.clip_pop(gtx.scene)
	case:
		unfilled(gtx, r, display, fill_col, muted)
	}
}

// rating_display shows a rating read-only (rating.json kind display): the
// stars with unfilled ones in the muted fill, then the value in
// semibold caption1 and, with count >= 0, a middle dot and the count
// with thousands separators. compact shows one filled star before the
// texts. Medium is its default size.
rating_display :: proc(
	gtx: ^ui.Ctx,
	value: f32,
	count := -1,
	max_stars := 5,
	compact := false,
	size := Rating_Size.Medium,
	tint := Rating_Color.Neutral,
	key: u64 = 0,
	loc := #caller_location,
) -> ui.Dims {
	p := ui.widget_open(gtx, key, loc)
	side := RATING_STAR[size]
	n := compact ? 1 : max(max_stars, 1)
	gap: f32
	tst := style(.Caption1)
	switch size {
	case .Small, .Medium:
		gap = tok.SPACING_HORIZONTAL_XS
	case .Large:
		gap = tok.SPACING_HORIZONTAL_SNUDGE
		tst = {tok.FONT_WEIGHT_REGULAR, tok.FONT_SIZE_BASE300, tok.LINE_HEIGHT_BASE300, 0}
	case .Extra_Large:
		gap = tok.SPACING_HORIZONTAL_S
		tst = {tok.FONT_WEIGHT_REGULAR, tok.FONT_SIZE_BASE400, tok.LINE_HEIGHT_BASE400, 0}
	}
	shown := math.round(value * 2) / 2
	value_text := value > 0 ? fmt.tprintf("%g", shown) : ""
	count_text := count >= 0 ? thousands(count, gtx.allocator) : ""
	if value_text != "" && count_text != "" {
		count_text = fmt.tprintf("· %s", count_text)
	}
	vst := tst
	vst.weight = tok.FONT_WEIGHT_SEMIBOLD
	vt := shape_style(gtx, value_text, vst)
	ct := shape_style(gtx, count_text, tst)
	w := f32(n) * side
	if value_text != "" {
		w += gap + vt.width
	}
	if count_text != "" {
		w += gap + ct.width
	}
	h := max(side, tst.line_height)
	sz := ui.constrain(gtx.constraints, {w, h})
	filled_col, muted := rating_colors(tint)
	for i in 0 ..< n {
		r := ops.Rect{f32(i) * side, (h - side) / 2, side, side}
		fill: f32 = compact ? 1 : shown - f32(i)
		paint_star(gtx, r, fill, filled_col, muted, true)
	}
	x := f32(n) * side
	fg := color(.Neutral_Foreground1)
	if value_text != "" {
		x += gap
		draw_text(gtx, vt, {x, (h - tst.line_height) / 2}, fg)
		x += vt.width
	}
	if count_text != "" {
		x += gap
		draw_text(gtx, ct, {x, (h - tst.line_height) / 2}, fg)
	}
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, value_text != "" ? value_text : "rating"))
	return ui.widget_close(gtx, &p, {sz, (h - tst.line_height) / 2 + baseline_of(vt)})
}

// thousands writes n with a comma every three digits (rating.json
// behaviour count-format, in the one locale jm:ui has).
thousands :: proc(n: int, allocator := context.temp_allocator) -> string {
	digits := fmt.tprintf("%d", abs(n))
	b := strings.builder_make(allocator)
	if n < 0 {
		strings.write_byte(&b, '-')
	}
	for ch, i in digits {
		if i > 0 && (len(digits) - i) % 3 == 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_rune(&b, ch)
	}
	return strings.to_string(b)
}
