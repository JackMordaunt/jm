package fluent

import "core:fmt"
import "jm:ui"
import "jm:ui/design"
import tok "jm:ui/fluent/tokens"
import "jm:ui/ops"

// Form controls: checkbox, radio group, switch and slider, on the
// fluent-kit's components/checkbox.json, radio-group.json, switch.json
// and slider.json and the styles files they cite at the kit's commit
// (source/COMMIT). Every size is a constant those files hard-code, cited
// as use<Name>Styles.styles.ts:lines; every colour is an alias token
// per state. Checkbox, radio and slider declare no transition, so their
// colours snap; the switch eases its track colours and thumb over
// DURATION_NORMAL with CURVE_EASY_EASE. Keyboard focus is the default
// outline around the whole control, label included.

// CONTROL_MARGIN is the spacingVerticalS / spacingHorizontalS margin
// every indicator (box, circle, track) keeps on all four sides, so a
// 16px indicator sits in a 32px row and hit column.
@(private)
CONTROL_MARGIN :: tok.SPACING_HORIZONTAL_S

// label_text shapes a control's label at body1, the Label component's
// default (checkbox.json notes).
@(private)
label_text :: proc(gtx: ^ui.Ctx, s: string) -> Text {
	return shape_text(gtx, s, .Body1)
}

// Label_Side is which side of the indicator the label sits on.
Label_Side :: enum u8 {
	After,
	Before,
}

// control_row is the geometry shared by checkbox, radio and switch: an
// indicator of ind (w, h) in its margins beside a label t, the label
// padded spacingHorizontalXS toward the indicator and spacingHorizontalS
// away from it (use*Styles.styles.ts label rules). It returns the row's
// size, the indicator's rect and where the label's line box starts.
@(private)
control_row :: proc(gtx: ^ui.Ctx, ind: ops.Size, t: Text, has_label: bool, side: Label_Side) -> (size: ops.Size, box: ops.Rect, label_at: ops.Point) {
	col := ind.x + 2 * CONTROL_MARGIN // the hit column
	row := ind.y + 2 * CONTROL_MARGIN
	w := col
	if has_label {
		w += tok.SPACING_HORIZONTAL_XS + t.width + tok.SPACING_HORIZONTAL_S
	}
	size = ui.constrain_min(gtx.constraints, {w, row})
	ly := (row - t.height) / 2 // the first line centres on the indicator
	switch side {
	case .After:
		box = {CONTROL_MARGIN, CONTROL_MARGIN, ind.x, ind.y}
		label_at = {col + tok.SPACING_HORIZONTAL_XS, ly}
	case .Before:
		box = {size.x - col + CONTROL_MARGIN, CONTROL_MARGIN, ind.x, ind.y}
		label_at = {tok.SPACING_HORIZONTAL_S, ly}
	}
	return
}

// Checkbox_Size is the indicator's size: 16px in a 32px row, or 20px
// in a 36px row.
Checkbox_Size :: enum u8 {
	Medium,
	Large,
}

// checkbox is a Fluent checkbox (checkbox.json). checked^ flips on a
// click anywhere on the row or Space while focused; with mixed the box
// shows the indeterminate square and a click sets checked^ true, as
// Fluent's does. shape .Circular rounds the box fully. Returns true on
// the frame it toggled.
//
// The label's colour tracks state: Foreground 3 unchecked, 2 hovered, 1
// pressed, checked or mixed (the spec's gotcha). Disabled and checked
// shows no fill, only a disabled check inside a disabled border. No
// transition is declared, so colours snap.
checkbox :: proc(
	gtx: ^ui.Ctx,
	checked: ^bool,
	label := "",
	mixed := false,
	size := Checkbox_Size.Medium,
	side := Label_Side.After,
	circular := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	// useCheckboxStyles.styles.ts: 16px box and 12px glyph at medium, 20
	// and 16 at large.
	ind: f32 = size == .Large ? 20 : 16
	glyph: f32 = size == .Large ? 16 : 12
	t := label_text(gtx, label)
	sz, box, at := control_row(gtx, {ind, ind}, t, label != "", side)
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	if c.clicked {
		checked^ = mixed ? true : !checked^
	}
	on := checked^ && !mixed

	// One state class applies: disabled, mixed, checked, unchecked; hover
	// and press live inside it (checkbox.json behaviour state-priority).
	label_role, border_role, fill_role, glyph_role: tok.Role
	switch {
	case c.disabled:
		label_role, border_role, glyph_role = .Neutral_Foreground_Disabled, .Neutral_Stroke_Disabled, .Neutral_Foreground_Disabled
	case mixed:
		label_role = .Neutral_Foreground1
		border_role = role_for({.Compound_Brand_Stroke, .Compound_Brand_Stroke_Hover, .Compound_Brand_Stroke_Pressed, .Neutral_Stroke_Disabled}, c)
		glyph_role = role_for({.Compound_Brand_Foreground1, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	case on:
		label_role = .Neutral_Foreground1
		fill_role = role_for({.Compound_Brand_Background, .Compound_Brand_Background_Hover, .Compound_Brand_Background_Pressed, .Neutral_Background_Disabled}, c)
		border_role = fill_role
		glyph_role = .Neutral_Foreground_Inverted
	case:
		label_role = role_for({.Neutral_Foreground3, .Neutral_Foreground2, .Neutral_Foreground1, .Neutral_Foreground_Disabled}, c)
		border_role = role_for({.Neutral_Stroke_Accessible, .Neutral_Stroke_Accessible_Hover, .Neutral_Stroke_Accessible_Pressed, .Neutral_Stroke_Disabled}, c)
	}

	rad := circular ? ind / 2 : tok.BORDER_RADIUS_SMALL
	rr := ops.Round_Rect{box, rad}
	if on && !c.disabled {
		ops.fill(gtx.scene, rr, color(fill_role))
	}
	stroke_inside(gtx, rr, color(border_role), tok.STROKE_WIDTH_THIN)
	if on {
		icon(gtx, .Checkmark, {box.x + (ind - glyph) / 2, box.y + (ind - glyph) / 2}, glyph, color(glyph_role))
	} else if mixed {
		// The mixed glyph is a filled square icon at the glyph size; its
		// square covers two thirds of that box, as Fluent's Square12Filled does.
		sq := glyph * 2 / 3
		ops.fill(gtx.scene, ops.Round_Rect{{box.x + (ind - sq) / 2, box.y + (ind - sq) / 2, sq, sq}, 1}, color(glyph_role))
	}
	if label != "" {
		draw_text(gtx, t, at, color(label_role))
	}
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	ui.semantics(gtx, &p, {role = .Checkbox, label = label, states = design.state_if(mixed, {.Mixed}) + design.state_if(on, {.Checked}) + design.state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, at.y + baseline_of(t)})
	return c.clicked
}

// RADIO_INDICATOR is a radio's 16px circle; RADIO_DOT the 10px checked
// dot inside it, 0.625 of the circle (useRadioStyles.styles.ts).
@(private)
RADIO_INDICATOR :: f32(16)
@(private)
RADIO_DOT :: f32(10)

// radio_group is a Fluent RadioGroup (radio-group.json): one radio per
// label, stacked as touching 32px rows, or abutting in a row with
// horizontal. selected^ is the index of the chosen one, -1 for none. A
// click on a radio's row selects it. The group is one roving focus
// scope, so one tab stop, entered at the selected radio (the first, with
// none); the arrow keys move focus and the selection to the next or
// previous radio, wrapping, and Space selects the focused one when none
// is (radio-group.json accessibility). Each radio is its own input area
// tagged with its label. Returns true on the frame selected^ changed.
//
// A forced state paints the selected radio (the first, with none) in
// that state and the rest enabled.
radio_group :: proc(
	gtx: ^ui.Ctx,
	labels: []string,
	selected: ^int,
	horizontal := false,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	old := selected^
	n := len(labels)
	texts := make([]Text, n, gtx.allocator)
	rows := make([]ops.Rect, n, gtx.allocator)
	total: ops.Size
	for l, i in labels {
		texts[i] = label_text(gtx, l)
		w := RADIO_INDICATOR + 2 * CONTROL_MARGIN + tok.SPACING_HORIZONTAL_XS + texts[i].width + tok.SPACING_HORIZONTAL_S
		h := RADIO_INDICATOR + 2 * CONTROL_MARGIN
		if horizontal {
			rows[i] = {total.x, 0, w, h}
			total.x += w
			total.y = max(total.y, h)
		} else {
			rows[i] = {0, total.y, w, h}
			total.y += h
			total.x = max(total.x, w)
		}
	}
	sz := ui.constrain_min(gtx.constraints, total)
	if !horizontal {
		for &r in rows {
			r.w = sz.x // a column's rows share the widest label's width
		}
	}
	ui.semantics(gtx, &p, {role = .Radio_Group, states = design.state_if(state == .Disabled, {.Disabled})})
	ui.focus_scope_open(gtx, p.id, rove = .Both, wrap = true)
	for i in 0 ..< n {
		id := ui.id_mix(p.id, u64(i))
		st := state
		if state != .Live && i != max(selected^, 0) {
			st = .Enabled
		}
		c := control(gtx, id, rows[i], st)
		if c.clicked {
			selected^ = i
		}
		// The scope moved focus here by an arrow: the selection follows.
		for e in ui.events(gtx, id) {
			if c.st != nil && e.kind == .Focus && e.key != .None && e.key != .Tab {
				selected^ = i
			}
		}
		paint_radio(gtx, c, rows[i], texts[i], i == selected^)
		listen(gtx, c.st, id, rows[i])
		ops.tag(gtx.scene, id, ui.frame_string(gtx, labels[i]))
		ui.part_semantics(gtx, &p, id, rows[i], {role = .Radio, label = labels[i], states = design.state_if(i == selected^, {.Checked}) + design.state_if(c.disabled, {.Disabled})})
	}
	ui.focus_scope_close(gtx, ui.id_mix(p.id, u64(max(selected^, 0))))
	ui.widget_close(gtx, &p, {size = sz})
	return selected^ != old
}

// paint_radio paints one radio row: its 16px ring, the dot when
// checked, its label, and the focus outline around the row.
@(private)
paint_radio :: proc(gtx: ^ui.Ctx, c: Control, row: ops.Rect, t: Text, checked: bool) {
	label_role, ring_role, dot_role: tok.Role
	switch {
	case c.disabled:
		label_role, ring_role, dot_role = .Neutral_Foreground_Disabled, .Neutral_Stroke_Disabled, .Neutral_Foreground_Disabled
	case checked:
		label_role = .Neutral_Foreground1
		ring_role = role_for({.Compound_Brand_Stroke, .Compound_Brand_Stroke_Hover, .Compound_Brand_Stroke_Pressed, .Neutral_Stroke_Disabled}, c)
		dot_role = role_for({.Compound_Brand_Foreground1, .Compound_Brand_Foreground1_Hover, .Compound_Brand_Foreground1_Pressed, .Neutral_Foreground_Disabled}, c)
	case:
		label_role = role_for({.Neutral_Foreground3, .Neutral_Foreground2, .Neutral_Foreground1, .Neutral_Foreground_Disabled}, c)
		ring_role = role_for({.Neutral_Stroke_Accessible, .Neutral_Stroke_Accessible_Hover, .Neutral_Stroke_Accessible_Pressed, .Neutral_Stroke_Disabled}, c)
	}
	centre := ops.Point{row.x + CONTROL_MARGIN + RADIO_INDICATOR / 2, row.y + CONTROL_MARGIN + RADIO_INDICATOR / 2}
	// The ring is a 1px border on a 16px circle: stroked half a pixel in.
	ops.stroke(gtx.scene, ui.circle(centre, RADIO_INDICATOR / 2 - tok.STROKE_WIDTH_THIN / 2), color(ring_role), {width = tok.STROKE_WIDTH_THIN})
	if checked {
		ops.fill(gtx.scene, ui.circle(centre, RADIO_DOT / 2), color(dot_role))
	}
	draw_text(gtx, t, {row.x + RADIO_INDICATOR + 2 * CONTROL_MARGIN + tok.SPACING_HORIZONTAL_XS, row.y + (row.h - t.height) / 2}, color(label_role))
	paint_focus_outline(gtx, c, {row, tok.BORDER_RADIUS_MEDIUM})
}

// Switch_Size is the track's size: 40 by 20px in a 36px row, or 32 by
// 16px in a 32px row.
Switch_Size :: enum u8 {
	Medium,
	Small,
}

// Switch_Thumb is a switch's thumb travel between frames, so it slides
// over DURATION_NORMAL rather than jumping (switch.json behaviour
// transition). It is the switch's widget data.
Switch_Thumb :: struct {
	from, to: f32, // 0 off, 1 on
	tween:    ui.Tween,
	live:     bool,
}

// toggle_switch is a Fluent switch (switch.json; switch is Odin's
// keyword). on^ flips on a click anywhere
// on the row or Space while focused. Returns true on the frame it
// flipped. The track's background, border and thumb colours and the
// thumb's position ease over DURATION_NORMAL with CURVE_EASY_EASE; the
// label does not change with state.
//
// Under high contrast the theme's bindings apply, not the styles file's
// forced-colours rules (a Canvas thumb on a Highlight track).
toggle_switch :: proc(
	gtx: ^ui.Ctx,
	on: ^bool,
	label := "",
	size := Switch_Size.Medium,
	side := Label_Side.After,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	// useSwitchStyles.styles.ts: 40x20 medium and 32x16 small tracks, a
	// 1px border, the thumb 2px smaller than the track's height and
	// travelling the track's width less the thumb and 2px.
	track := size == .Small ? ops.Size{32, 16} : {40, 20}
	thumb := track.y - 2
	travel := track.x - thumb - 2
	t := label_text(gtx, label)
	sz, box, at := control_row(gtx, track, t, label != "", side)
	area := ops.Rect{0, 0, sz.x, sz.y}
	c := control(gtx, p.id, area, state)
	if c.clicked {
		on^ = !on^
	}

	fill_role, border_role, thumb_role: tok.Role
	switch {
	case c.disabled && on^:
		fill_role, border_role, thumb_role = .Neutral_Background_Disabled, .Transparent_Stroke_Disabled, .Neutral_Foreground_Disabled
	case c.disabled:
		fill_role, border_role, thumb_role = .Transparent_Background, .Neutral_Stroke_Disabled, .Neutral_Foreground_Disabled
	case on^:
		fill_role = role_for({.Compound_Brand_Background, .Compound_Brand_Background_Hover, .Compound_Brand_Background_Pressed, .Neutral_Background_Disabled}, c)
		border_role = role_for({.Transparent_Stroke, .Transparent_Stroke_Interactive, .Transparent_Stroke_Interactive, .Transparent_Stroke_Disabled}, c)
		thumb_role = .Neutral_Foreground_Inverted
	case:
		fill_role = .Transparent_Background
		border_role = role_for({.Neutral_Stroke_Accessible, .Neutral_Stroke_Accessible_Hover, .Neutral_Stroke_Accessible_Pressed, .Neutral_Stroke_Disabled}, c)
		thumb_role = border_role
	}
	// Slots 0-2 are the track's background and border and the thumb's
	// colour; the thumb's travel keeps its own tween.
	fill := blend(gtx, c, 0, color(fill_role), tok.DURATION_NORMAL)
	stroke := blend(gtx, c, 1, color(border_role), tok.DURATION_NORMAL)
	thumb_color := blend(gtx, c, 2, color(thumb_role), tok.DURATION_NORMAL)
	pos: f32 = on^ ? 1 : 0
	if c.st != nil {
		pos = slide(gtx, ui.widget_data(gtx, p.id, Switch_Thumb), pos)
	}

	rr := ops.Round_Rect{box, track.y / 2}
	if ui.painted(fill) {
		ops.fill(gtx.scene, rr, fill)
	}
	if ui.painted(stroke) {
		stroke_inside(gtx, rr, stroke, 1)
	}
	ops.fill(gtx.scene, ui.circle({box.x + 1 + thumb / 2 + travel * pos, box.y + track.y / 2}, thumb / 2), thumb_color)
	if label != "" {
		draw_text(gtx, t, at, color(.Neutral_Foreground_Disabled if c.disabled else .Neutral_Foreground1))
	}
	paint_focus_outline(gtx, c, {area, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.id, area)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, label))
	ui.semantics(gtx, &p, {role = .Switch, label = label, states = design.state_if(on^, {.Checked}) + design.state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {sz, at.y + baseline_of(t)})
	return c.clicked
}

// slide is target eased from where the thumb was: a new target starts a
// DURATION_NORMAL move along CURVE_EASY_EASE, and the first frame has
// nothing to move from.
@(private)
slide :: proc(gtx: ^ui.Ctx, th: ^Switch_Thumb, target: f32) -> f32 {
	if !th.live {
		th^ = {from = target, to = target, live = true}
		return target
	}
	if target != th.to {
		th.from = slide_value(th)
		th.to = target
		th.tween = {to = 1, duration = tok.DURATION_NORMAL / 1000}
	}
	ui.tween_update(&th.tween, gtx)
	return slide_value(th)
}

@(private = "file")
slide_value :: proc(th: ^Switch_Thumb) -> f32 {
	if th.tween.duration <= 0 {
		return th.to
	}
	return th.from + (th.to - th.from) * design.bezier_ease(tok.CURVE_EASY_EASE, th.tween.t / th.tween.duration)
}

// Slider_Metrics are one size's constants (useSliderStyles.styles.ts):
// the thumb, its inner (brand) radius, the rail's thickness and the
// root's minimum cross size.
@(private)
Slider_Metrics :: struct {
	thumb, inner, rail, cross: f32,
}

@(private)
slider_metrics :: proc(size: Size) -> Slider_Metrics {
	if size == .Small {
		return {16, 5, 2, 24}
	}
	return {20, 6, 4, 32}
}

// SLIDER_MIN_LENGTH is a slider's minimum length along its axis.
@(private)
SLIDER_MIN_LENGTH :: f32(120)

// SLIDER_KINDS is what a slider's input area asks for: a press jumps,
// a drag moves, the keys step.
@(private)
SLIDER_KINDS :: ops.Event_Kinds{.Press, .Release, .Move, .Enter, .Leave, .Key, .Focus, .Blur}

// slider is a Fluent slider (slider.json): value^ between lo and hi,
// continuous, or snapped to step with a tick per step as Fluent draws
// when a step is given, along length px, horizontal or
// vertical (min at the bottom). A press anywhere on it jumps the value
// there and a drag moves it; Left/Down and Right/Up step, Page keys move
// ten steps, Home and End go to the ends. name is what its tag carries
// and a reader says; labelled_by names it by another node's label
// instead: an app draws the caption with base.label (or label here),
// keeps the id that returns, and passes it. Returns true on a frame
// value^ changed. Colours and the thumb snap; nothing transitions.
//
// The hit area is the whole root, not just the thumb-sized band the
// hidden input covers. The focus outline is drawn 2px inside the root
// along its axis and flush across it, as the styles file offsets it;
// the vertical form keeps the same offsets rather than the file's
// mirrored ones. Step ticks and the thumb's ring read Background 1,
// so they assume that surface.
slider :: proc(
	gtx: ^ui.Ctx,
	value: ^f32,
	lo: f32 = 0,
	hi: f32 = 100,
	step: f32 = 0,
	length: f32 = SLIDER_MIN_LENGTH,
	size := Size.Medium,
	vertical := false,
	name := "slider",
	labelled_by: ops.Area_Id = 0,
	state := Interaction.Live,
	key: u64 = 0,
	loc := #caller_location,
) -> bool {
	p := ui.widget_open(gtx, key, loc)
	m := slider_metrics(size)
	span := max(hi - lo, 1e-6)
	l := max(length, SLIDER_MIN_LENGTH)
	sz := ui.constrain_min(gtx.constraints, vertical ? ops.Size{m.cross, l} : {l, m.cross})
	area := ops.Rect{0, 0, sz.x, sz.y}
	old := value^
	c := control(gtx, p.id, area, state)
	// The rail runs the length less a thumb, inset half a thumb from each
	// end, and the thumb's centre stays m.inner inside the rail's ends.
	run := (vertical ? sz.y : sz.x) - m.thumb
	at_value :: proc(v, lo, span: f32) -> f32 {
		return clamp((v - lo) / span, 0, 1)
	}
	set_from :: proc(value: ^f32, pos, lo, hi, step, run, thumb: f32, vertical: bool) {
		f := clamp((pos - thumb / 2) / max(run, 1), 0, 1)
		if vertical {
			f = 1 - f // min at the bottom
		}
		v := lo + f * (hi - lo)
		if step > 0 {
			v = lo + f32(int((v - lo) / step + 0.5)) * step
		}
		value^ = clamp(v, lo, hi)
	}
	if c.st != nil {
		for e in ui.events(gtx, p.id) {
			#partial switch e.kind {
			case .Press:
				if e.button == .Left {
					set_from(value, vertical ? e.pos.y : e.pos.x, lo, hi, step, run, m.thumb, vertical)
				}
			case .Move:
				if c.st.pressed {
					set_from(value, vertical ? e.pos.y : e.pos.x, lo, hi, step, run, m.thumb, vertical)
				}
			case .Key:
				d := step > 0 ? step : span / 100
				v := value^
				#partial switch e.key {
				case .Left, .Down:
					v -= d
				case .Right, .Up:
					v += d
				case .Page_Down:
					v -= d * 10
				case .Page_Up:
					v += d * 10
				case .Home:
					v = lo
				case .End:
					v = hi
				case:
					continue
				}
				value^ = clamp(v, lo, hi)
			}
		}
	}
	f := at_value(value^, lo, span)

	rail_role: tok.Role = .Neutral_Stroke_Accessible
	fill_role := role_for({.Compound_Brand_Background, .Compound_Brand_Background_Hover, .Compound_Brand_Background_Pressed, .Neutral_Foreground_Disabled}, c)
	if c.disabled {
		rail_role = .Neutral_Background_Disabled
	}
	// The rail, then its filled part up to the value (the styles file's
	// gradient), then step ticks, then the thumb.
	rail: ops.Rect
	filled: ops.Rect
	centre: ops.Point
	if vertical {
		rail = {(sz.x - m.rail) / 2, m.thumb / 2, m.rail, run}
		fh := run * f
		filled = {rail.x, rail.y + run - fh, rail.w, fh}
		centre = {sz.x / 2, m.thumb / 2 + run - clamp(run * f, m.inner, run - m.inner)}
	} else {
		rail = {m.thumb / 2, (sz.y - m.rail) / 2, run, m.rail}
		filled = {rail.x, rail.y, run * f, rail.h}
		centre = {m.thumb / 2 + clamp(run * f, m.inner, run - m.inner), sz.y / 2}
	}
	ops.fill(gtx.scene, ops.Round_Rect{rail, tok.BORDER_RADIUS_XLARGE}, color(rail_role))
	if (vertical ? filled.h : filled.w) > 0 {
		ops.fill(gtx.scene, ops.Round_Rect{filled, tok.BORDER_RADIUS_XLARGE}, color(fill_role))
	}
	if step > 0 {
		n := int(span / step + 0.5)
		if n > 1 {
			for i in 1 ..< n {
				u := run * f32(i) / f32(n)
				tick := vertical ? ops.Rect{rail.x, rail.y + u, rail.w, 1} : {rail.x + u, rail.y, 1, rail.h}
				ops.fill(gtx.scene, tick, color(.Neutral_Background1))
			}
		}
	}
	// The thumb: a 1px Stroke 1 border, a Background 1 ring a fifth of
	// the thumb wide, and the brand centre.
	ops.fill(gtx.scene, ui.circle(centre, m.thumb / 2), color(.Neutral_Foreground_Disabled if c.disabled else .Neutral_Stroke1))
	ops.fill(gtx.scene, ui.circle(centre, m.thumb / 2 - m.thumb * 0.05), color(.Neutral_Background1))
	ops.fill(gtx.scene, ui.circle(centre, m.thumb / 2 - m.thumb * 0.2), color(fill_role))
	ring := vertical ? ops.Rect{area.x + 2, area.y + 2, area.w - 4, area.h - 4} : {area.x + 4, area.y + 2, area.w - 8, area.h - 4}
	paint_focus_outline(gtx, c, {ring, tok.BORDER_RADIUS_MEDIUM})
	listen(gtx, c.st, p.id, area, SLIDER_KINDS)
	ops.tag(gtx.scene, p.id, ui.frame_string(gtx, name))
	ui.semantics(gtx, &p, {role = .Slider, label = labelled_name(name, labelled_by), labelled_by = labelled_by, value = ui.frame_string(gtx, fmt.tprintf("%g", value^)), states = design.state_if(c.disabled, {.Disabled})})
	ui.widget_close(gtx, &p, {size = sz})
	return value^ != old
}
